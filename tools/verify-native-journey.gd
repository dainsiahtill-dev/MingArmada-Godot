extends SceneTree
## Honest continuous voyage probe. Commands and accepted fixed ticks only.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const HeightField = preload("res://modules/scene_engine/terrain/height_field.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
const STEP := 1.0 / 60.0
const WALL_LIMIT_MS := 300000
const ACCEPTED_LIMIT := 1800.0
var runtime := Runtime.new()
var height := HeightField.new()
var directory := ""
var sequence := 0
var accepted := 0.0
var events := 0
var ticks := 0
var started := 0
var records: Array = []
var phase := "configure"
var failure := ""
var log_file: FileAccess
var strategy := "passive"
var wall_limit_ms := WALL_LIMIT_MS
var active_stage := "waiting-for-native-enemy"
var active_stage_started := 0
var enemy_id := ""
var boarding_id := ""
var weakening_observed := false
var native_enemy_hits := 0
var ammo_selected := ""
var escort_source_ids: Array = []
func _initialize() -> void: call_deferred("run")
func record(kind: String, data: Dictionary) -> void:
	var row := {"kind":kind,"phase":phase,"acceptedSeconds":accepted,"wallMs":Time.get_ticks_msec()-started,"data":data}
	records.append(row)
	if log_file:
		log_file.store_line(JSON.stringify(row)); log_file.flush()
	if kind in ["initial","progress"]:
		print("NATIVE_JOURNEY ",JSON.stringify({"kind":kind,"phase":phase,"acceptedSeconds":accepted,"wallMs":row.wallMs,"evidence":directory+"/events.jsonl"}))
	else: print("NATIVE_JOURNEY ",JSON.stringify(row))
func packet() -> Dictionary: return runtime.snapshot()
func business(type: String, fields: Dictionary = {}) -> Dictionary:
	sequence += 1
	var command := fields.duplicate(true)
	command["type"] = type; command["commandId"] = "journey-%d-%d" % [OS.get_process_id(),sequence]
	command["expectedRevision"] = packet().campaign.revision
	if type == "assign-order": command.order["id"] = command.commandId
	var result: Dictionary = runtime.command(command)
	if not result.get("ok",false):
		var key_types: Array = []
		for key in command: key_types.append({"key":str(key),"keyType":typeof(key),"valueType":typeof(command[key])})
		record("command-validation",{"dataValid":preload("res://game/domain/persistence/save_codec.gd").command_data(command),"domainValid":runtime.campaign._valid_command(command),"keyTypes":key_types})
	record("command",{"input":command,"result":result})
	if not result.get("ok",false): failure = type+":"+result.get("reason","rejected")
	return result
func sailing(type: String, fields: Dictionary) -> Dictionary:
	var command := fields.duplicate(true); command["type"] = type
	var result: Dictionary = runtime.command(command)
	record("sailing-command",{"input":command,"result":result})
	if not result.get("ok",false): failure = type+":"+result.get("reason","rejected")
	return result
func distance(a: Dictionary,b: Dictionary) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
func order(ship_ids: Array, intent: Dictionary) -> Dictionary:
	return business("assign-order",{"order":{"id":"pending","shipIds":ship_ids,"intent":intent,"issuedAt":packet().campaign.simulationSeconds}})
func active_transition(stage: String) -> void:
	active_stage = stage; active_stage_started = Time.get_ticks_msec()
	record("active-stage",{"stage":stage,"nativeEnemyHits":native_enemy_hits,"weakeningObserved":weakening_observed})
func active_escort_step() -> void:
	var p := packet(); var state: Dictionary = p.campaign
	var flag: String = state.flagshipId
	var enemy := live(enemy_id); var player := live(flag)
	if enemy.is_empty(): return # A source route representation is not a native sighting.
	if Time.get_ticks_msec()-active_stage_started > wall_limit_ms:
		failure = "active-stage-wall-budget-exhausted:"+active_stage; return
	if enemy.hull <= 0:
		failure = "enemy-sunk-before-prize-boarding"; record("active-outcome",{"enemy":enemy}); return
	var gap := distance(player.visual.position,enemy.visual.position)
	if active_stage == "waiting-for-native-enemy":
		record("native-enemy-sighted",{"enemy":enemy,"flagship":player,"distance":gap})
		if not sailing("select-ammo",{"shipId":flag,"ammo":"chain"}).ok: return
		ammo_selected = "chain"
		if not order([flag],{"kind":"intercept","targetId":enemy_id}).ok: return
		active_transition("intercept-chain")
	if active_stage == "intercept-chain" and gap <= 240:
		if not order([flag],{"kind":"focus","targetId":enemy_id}).ok: return
		active_transition("broadside-weakening")
	var profile: Dictionary = Catalog.DATA.profiles[state.vessels[enemy_id].profileId]
	var weakened: bool = enemy.hull/float(profile.maxHull) <= 0.65 or enemy.crew/float(profile.complement) <= 0.6
	if weakened and native_enemy_hits > 0 and not weakening_observed:
		weakening_observed = true
		record("actual-weakening",{"enemy":enemy,"distance":gap,"nativeEnemyHits":native_enemy_hits})
		if enemy.crew > 0:
			if not order([flag],{"kind":"prepare-boarding","targetId":enemy_id}).ok: return
		else:
			# A zero-able-crew ship cannot be an order target; canonical navigation
			# cancels the fire order without changing any native state.
			if not sailing("navigate",{"shipId":flag,"point":{"x":enemy.visual.position.x,"z":enemy.visual.position.z}}).ok: return
		active_transition("closing-for-boarding")
	if active_stage in ["intercept-chain","broadside-weakening"]:
		var wanted := "grape" if gap <= 80 else "chain"
		if wanted != ammo_selected:
			if not sailing("select-ammo",{"shipId":flag,"ammo":wanted}).ok: return
			ammo_selected = wanted
		# Orders may autonomously fire, but explicit fire is queued only when the
		# real live ship has ammunition, cooldown ready, range and broadside arc.
		var bearing := atan2(enemy.visual.position.z-player.visual.position.z,enemy.visual.position.x-player.visual.position.x)
		for side in ["port","starboard"]:
			var gun_bearing: float = player.visual.heading+(PI/2 if side == "starboard" else -PI/2)
			if player.ammo[wanted] > 0 and player.cooldownSeconds[side] <= 0 and gap <= Cannon.BALLISTICS[wanted].range and absf(wrapf(bearing-gun_bearing,-PI,PI)) <= Cannon.ARC:
				if not sailing("fire",{"shipId":flag,"side":side}).ok: return
	if active_stage == "closing-for-boarding":
		var eligibility: Dictionary = p.runtime.eligibility.get("start-boarding:"+flag+":"+enemy_id,{})
		if eligibility.get("ok",false):
			if not business("start-boarding",{"targetId":enemy_id,"fromShipId":flag}).ok: return
			for b: Dictionary in packet().campaign.boardings.values():
				if b.targetId == enemy_id and b.status == "active": boarding_id = b.id
			if boarding_id.is_empty(): failure = "boarding-receipt-without-active-domain-boarding"; return
			for point in ["bow","deck","helm"]:
				if not business("board-action",{"encounterId":boarding_id,"point":point,"action":"advance"}).ok: return
			active_transition("actual-boarding-progression")
	if active_stage == "actual-boarding-progression":
		var boarding: Dictionary = packet().campaign.boardings[boarding_id]
		if boarding.status != "active":
			record("actual-boarding-outcome",{"boarding":boarding,"winningReceiptVerified":runtime.campaign.is_winning_boarding(boarding_id)})
			failure = "boarding-"+str(boarding.status)+":remaining-prize-port-second-convoy-and-disk-continue-unproven"
func live(id: String) -> Dictionary:
	for ship: Dictionary in packet().naval.ships:
		if ship.id == id: return ship
	return {}
func diagnostic() -> Dictionary:
	var p := packet(); var ships: Array = []
	for ship: Dictionary in p.naval.ships:
		ships.append({"id":ship.id,"position":ship.visual.position,"velocity":ship.visual.velocity,"hull":ship.hull,"crew":ship.crew,"navigation":ship.get("navigation"),"route":runtime.simulation.encounter.navigation_status(ship.id),"sailDeployment":ship.sailDeployment,"heading":ship.visual.heading})
	return {"campaignRevision":p.campaign.revision,"simulationSeconds":p.campaign.simulationSeconds,"ships":ships,"voyages":p.campaign.voyages,"contracts":p.campaign.contracts,"stock":p.campaign.ports,"runtime":p.runtime}
func tick() -> bool:
	if Time.get_ticks_msec()-started >= wall_limit_ms: failure = "wall-budget-exhausted"; return false
	if accepted >= ACCEPTED_LIMIT: failure = "accepted-time-budget-exhausted"; return false
	if FileAccess.file_exists("res://build/native-journey/STOP"): failure = "stopped-for-gpu-measurement"; return false
	var delta: float = runtime.advance(STEP)
	accepted += delta; ticks += 1
	var drained: Array = runtime.drain_events(); events += drained.size()
	for event: Dictionary in drained:
		record("native-event",event)
		if event.get("type") == "hit" and event.get("targetId") == enemy_id and event.get("shipId") in escort_source_ids: native_enemy_hits += 1
	if delta < STEP-1e-9: failure = "tick-not-accepted:"+packet().runtime.notice; return false
	if ticks % 1800 == 0: record("progress",diagnostic())
	return true
func run() -> void:
	started = Time.get_ticks_msec()
	directory = "res://build/native-journey/%d-%d" % [OS.get_process_id(),started]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	log_file = FileAccess.open(directory+"/events.jsonl",FileAccess.WRITE)
	if not log_file: push_error("journey-evidence-open-failed"); quit(1); return
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--strategy="): strategy = argument.trim_prefix("--strategy=")
		elif argument.begins_with("--wall-seconds="):
			var raw := argument.trim_prefix("--wall-seconds=")
			if not raw.is_valid_int() or int(raw) < 1 or int(raw) > 1800: failure = "invalid-wall-seconds:expected-1-to-1800"; finish(); return
			wall_limit_ms = int(raw)*1000
		else: failure = "unknown-journey-argument:"+argument; finish(); return
	if not strategy in ["passive","active-escort"]: failure = "unknown-strategy:"+strategy; finish(); return
	record("probe-options",{"strategy":strategy,"wallLimitMs":wall_limit_ms,"acceptedLimit":ACCEPTED_LIMIT,"fixedStep":STEP})
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not height.configure_ports(geography): failure = "geography-invalid"; finish(); return
	var configured: Dictionary = runtime.configure(height.sample_height,Campaign.new())
	record("configured",configured)
	if not configured.ok: failure = "configure:"+configured.get("reason",""); finish(); return
	record("initial",diagnostic())
	phase = "accept-first-convoy"
	if not business("accept-convoy",{"contractId":"convoy-001"}).ok: finish(); return
	phase = "depart"
	if not business("depart").ok: finish(); return
	var state: Dictionary = packet().campaign
	var flag: String = state.flagshipId
	var fast: String = state.campaignId+"-fast"
	enemy_id = state.campaignId+"-enemy"
	escort_source_ids = [flag,fast]
	var route: Array = Catalog.DATA.routes["xiamen-kinmen-deep"].points
	var waypoint := 1
	if not sailing("navigate",{"shipId":flag,"point":route[waypoint]}).ok: finish(); return
	var protected_id: String = state.campaignId+"-grain-a" if strategy == "active-escort" else flag
	if strategy == "active-escort" and not sailing("select-ammo",{"shipId":fast,"ammo":"chain"}).ok: finish(); return
	if not order([fast],{"kind":"protect","targetId":protected_id}).ok: finish(); return
	active_stage_started = Time.get_ticks_msec()
	phase = "continuous-first-delivery"
	while failure.is_empty():
		if not tick(): break
		if ticks % 120 == 0:
			var p := packet()
			var ship := live(flag)
			if strategy == "active-escort": active_escort_step()
			if not failure.is_empty(): break
			if strategy == "passive" and waypoint < route.size()-1 and distance(ship.visual.position,route[waypoint]) < 30:
				waypoint += 1
				if not sailing("navigate",{"shipId":flag,"point":route[waypoint]}).ok: break
			var delivered: Dictionary = runtime.campaign.evaluate_convoy("convoy-001")
			if delivered.reason != "in-progress":
				record("first-delivery-result",delivered)
				if delivered.delivered <= 0: failure = "first-convoy-no-delivery"; break
				phase = "claim-first-convoy"
				business("claim-convoy",{"contractId":"convoy-001"})
				if failure.is_empty(): failure = "remaining-combat-port-second-convoy-and-disk-continue-not-yet-proven"
				break
			await process_frame
	finish()
func finish() -> void:
	var final := {"complete":false,"failure":failure,"phase":phase,"strategy":strategy,"activeStage":active_stage,"nativeEnemyHits":native_enemy_hits,"weakeningObserved":weakening_observed,"wallLimitMs":wall_limit_ms,"acceptedSeconds":accepted,"ticks":ticks,"drainedEvents":events,"wallMs":Time.get_ticks_msec()-started,"engine":Engine.get_version_info(),"evidenceDirectory":directory,"scope":"Actual Mingqi HeightField including shelf; unmodified default campaign; runtime.command plus runtime.advance(1/60); drain_events every tick. No state edits, teleports, fake receipts, or time jumps.","final":diagnostic() if runtime.campaign else {}}
	var output := FileAccess.open(directory+"/receipt.json",FileAccess.WRITE)
	if not output:
		push_error("journey-receipt-write-failed:"+directory)
	else:
		output.store_string(JSON.stringify(final,"\t")); output.flush()
		if output.get_error() != OK: push_error("journey-receipt-flush-failed:"+directory)
		output.close()
	record("finished",{"failure":failure,"evidenceDirectory":directory,"ticks":ticks,"drainedEvents":events})
	if log_file: log_file.close()
	runtime.dispose()
	print("NATIVE_JOURNEY_INCOMPLETE ",failure)
	quit(1)
