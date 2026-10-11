extends RefCounted
## Accepted-time coordinator for the existing 1650 opening. No render ownership.
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Bridge = preload("res://game/runtime/near_field_bridge.gd")
const CoastalWaves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
const PhysicsTypes = preload("res://modules/contracts/physics_types.gd")
const Readiness = preload("res://game/runtime/native_readiness.gd")
const STEP := 1.0/60.0
const MAX_TICKS := 24
const MAX_PENDING_SECONDS := 2.0
const MAX_EVENTS := 4096
const PAUSES := ["player","tactical","menu","blur","hidden","loading","error","result"]
var campaign: RefCounted
var simulation: RefCounted
var bridge: RefCounted
var _height: Callable
var _waves: RefCounted
var _pauses: Dictionary = {}
var _rate := 1.0
var _pending := 0.0
var _events: Array = []
var _drafts: Array = []
var _draft_results: Array = []
var _generation := 1
var _notice := ""
var _notice_revision := 0
var _error := false
var _disposed := false
var _accepted := 0.0
var _rejected := 0.0
var _handling_mode := "assisted"

static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func _ship(native: Dictionary,id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships",[]):
		if ship.id == id: return ship
	return {}
static func _distance(a: Dictionary,b: Dictionary) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
func configure(height_sampler: Callable, session: RefCounted = null) -> Dictionary:
	if not height_sampler.is_valid(): return _no("invalid-terrain-sampler")
	_height = height_sampler; _waves = CoastalWaves.new(); _waves.configure(_height)
	var next: RefCounted = session if session else Campaign.new()
	var bundle := build_native(next,false)
	if not bundle.ok: return bundle
	campaign = next; simulation = bundle.simulation; bridge = bundle.bridge
	bridge.set_observer(_observe)
	_pending = 0; _events.clear(); _drafts.clear(); _draft_results.clear(); _pauses.clear(); _error = false; _disposed = false
	return {"ok":true}
func build_native(session: RefCounted, paused: bool = true) -> Dictionary:
	var epoch: String = session.allocate_native_epoch()
	if epoch.is_empty(): return _no("near-epoch-buffer-full")
	var state: Dictionary = session.snapshot(); var ids: Array = []
	var full_policy: Dictionary = session.native_policy(state.vessels.keys())
	var ordinary := Bridge.ordinary_heritage_berth(state)
	var flagship: Dictionary = state.vessels[state.flagshipId]
	for vessel: Dictionary in state.vessels.values():
		if session.is_retired_prize(vessel.id): continue
		if ordinary and vessel.id == state.campaignId+"-heritage": continue
		if vessel.ownerId == "enemy" and state.currentPortId != null and not vessel.id in full_policy.capturedShipIds: continue
		if vessel.representation == "near" or vessel.id == state.flagshipId or vessel.ownerId == "captain" and vessel.damage.hull > 0 or vessel.damage.hull > 0 and _distance(vessel.pose.position,flagship.pose.position) <= 600: ids.append(vessel.id)
	for contract: Dictionary in state.contracts.values():
		if contract.status == "active":
			for voyage_id in contract.voyageIds:
				var id: String = state.voyages[voyage_id].vesselId
				if not id in ids: ids.append(id)
	for id in session.active_boarding_ship_ids():
		if not id in ids: ids.append(id)
	for work: Dictionary in state.works.values():
		if work.status == "active" and not work.shipId in ids: ids.append(work.shipId)
	ids = ids.filter(func(id): return not session.is_retired_prize(id))
	var setups: Array = []
	for id in ids:
		var vessel: Dictionary = state.vessels[id]
		var team: String = "hostile" if vessel.ownerId == "enemy" else "player" if vessel.profileId in ["flagship","fast"] or vessel.ownerId == "captain" else "neutral"
		setups.append(session.near_field_setup(vessel,team))
	var policy: Dictionary = session.native_policy(ids)
	var descriptors := WaveDescriptor.original_descriptors()
	for wave: Dictionary in descriptors: wave.direction = {"x":wave.direction.x,"y":wave.direction.z}
	var encounter := Encounter.new({"mode":"continuous","routePlanning":true,"seed":state.seed,"battleId":epoch,"playerId":state.flagshipId,"ships":setups,"controllableShipIds":policy.controllableShipIds,"hostileTargets":policy.hostileTargets,"sampleTerrainHeight":_height,"oceanWaves":descriptors,"waveSampler":_waves})
	if not encounter.last_error.is_empty(): return _no(encounter.last_error)
	var input := Simulation.new(encounter); input.set_handling_mode(_handling_mode); input.set_paused(paused)
	var handoff := Bridge.new(session,input)
	var projected: Dictionary = session.project_native(handoff.command_context().native)
	if not projected.ok: return projected
	return {"ok":true,"simulation":input,"bridge":handoff}
func _observe(events: Array) -> void:
	if _events.size()+events.size() > MAX_EVENTS: _fail("presentation-event-buffer-full"); return
	_events.append_array(events.duplicate(true))
func _notify(message: String) -> void: _notice = message; _notice_revision += 1
func _fail(reason: String) -> void: _error = true; _notify(reason); set_pause("error",true)
func is_paused() -> bool: return _rate == 0 or not _pauses.is_empty()
func set_pause(reason: String,value: bool) -> Dictionary:
	if not reason in PAUSES: return _no("invalid-pause-reason")
	var before := is_paused()
	if value: _pauses[reason] = true
	else: _pauses.erase(reason)
	if is_paused() != before:
		_pending = 0
		if simulation: simulation.set_paused(is_paused())
		if not is_paused(): _run_drafts()
	return {"ok":true}
func set_time_scale(rate: float) -> Dictionary:
	if not rate in [0.0,0.25,1.0,8.0]: return _no("invalid-time-scale")
	if rate == 8 and fast_forward_danger(): return _no("fast-forward-danger")
	var before := is_paused(); _rate = rate
	if before != is_paused():
		_pending = 0
		if simulation: simulation.set_paused(is_paused())
		if not is_paused(): _run_drafts()
	return {"ok":true}
func set_handling_mode(mode: String) -> void:
	if mode in ["assisted","realistic"]: _handling_mode = mode; simulation.set_handling_mode(mode)
func set_held(code: String,down: bool) -> void:
	if simulation and not _disposed and (not down or not is_paused()): simulation.set_held(code,down)
func command(input: Dictionary) -> Dictionary:
	if _disposed or not simulation: return _no("runtime-unavailable")
	var result: Dictionary
	var type: String = input.get("type","")
	if type in Campaign.BUSINESS:
		if _pauses.has("loading") or _pauses.has("error") or _pauses.has("result"): return _no("runtime-unavailable")
		if is_paused() and type in ["depart","start-boarding","board-action"]: return _no("runtime-paused")
		if type == "assign-order" and is_paused(): return draft_order(input)
		result = campaign.command(input,bridge.command_context())
	elif type == "pause": result = set_pause("player",input.get("value",not is_paused()))
	elif type == "time-scale": result = set_time_scale(input.get("value",1.0))
	elif type == "menu": result = set_pause("menu",input.get("value",true))
	elif type == "select-ship":
		result = simulation.encounter.setPlayerId(input.get("shipId","")); simulation.refresh_snapshot()
	elif type == "navigate":
		if is_paused(): return _no("runtime-paused")
		result = simulation.encounter.navigate(input.get("shipId",simulation.snapshot().playerId),input.get("point")); simulation.refresh_snapshot()
	elif type in ["controls","fire","select-ammo"]:
		if is_paused(): return _no("runtime-paused")
		result = _queue_sailing_intent(input)
	else: return _no("unknown-runtime-command")
	if not result.get("ok",false): _notify(result.get("reason","command-rejected"))
	return result
func _queue_sailing_intent(input: Dictionary) -> Dictionary:
	if input.type != "controls": simulation.action(input); return {"ok":true,"queued":true}
	var id: String = input.get("shipId",simulation.snapshot().playerId)
	var ship := _ship(simulation.encounter.snapshot(),id)
	if ship.is_empty(): return _no("Unknown ship")
	var commands: Array = []
	var controls := {"type":"controls","shipId":id,"rudder":ship.rudder,"sailDeployment":ship.sailDeployment,"sailAngle":ship.sailAngle,"autoTrim":ship.autoTrim}
	var pending: Dictionary = simulation.pending_controls(id)
	for field in ["rudder","sailDeployment","sailAngle","autoTrim"]:
		if pending.has(field): controls[field] = pending[field]
	var changed := false
	for field in ["rudder","sailDeployment","sailAngle","autoTrim"]:
		if input.has(field): controls[field] = input[field]; changed = true
	if changed: commands.append(controls)
	if input.has("ammoType"): commands.append({"type":"select-ammo","shipId":id,"ammo":input.ammoType})
	for side in ["port","starboard"]:
		if input.get("firePort" if side == "port" else "fireStarboard") == true: commands.append({"type":"fire","shipId":id,"side":side})
	if commands.is_empty(): return _no("Invalid controls")
	for command: Dictionary in commands: simulation.action(command)
	return {"ok":true,"queued":true}
func draft_order(input: Dictionary) -> Dictionary:
	if _disposed or _pauses.has("error") or _pauses.has("loading"): return _no("draft-unavailable")
	if not is_paused(): return _no("draft-requires-pause")
	if _drafts.size() >= 64: return _no("draft-buffer-full")
	for draft: Dictionary in _drafts:
		if draft.command.get("commandId") == input.get("commandId"): return _no("duplicate-draft-command")
	_drafts.append({"generation":_generation,"command":input.duplicate(true)})
	return {"ok":true,"drafted":true}
func _run_drafts() -> void:
	if not campaign: return
	var revision: int = campaign.snapshot().revision
	var drafts := _drafts; _drafts = []
	for draft: Dictionary in drafts:
		var result: Dictionary
		if draft.generation != _generation or draft.command.get("expectedRevision") != revision: result = _no("stale-draft")
		else:
			var command: Dictionary = draft.command.duplicate(true); command.expectedRevision = campaign.snapshot().revision
			result = campaign.command(command,bridge.command_context())
		_draft_results.append({"command":draft.command.duplicate(true),"result":result})
func fast_forward_danger() -> bool:
	if not campaign or not simulation: return true
	var state: Dictionary = campaign.snapshot(); var native: Dictionary = simulation.snapshot()
	var policy: Dictionary = campaign.native_policy(state.vessels.keys())
	for vessel: Dictionary in state.vessels.values():
		if vessel.damage.hull <= 0 or not (vessel.id == state.flagshipId or vessel.id in policy.controllableShipIds or vessel.ownerId == "captain"): continue
		var live := _ship(native,vessel.id); var position: Dictionary = live.visual.position if not live.is_empty() else vessel.pose.position
		var heading: float = live.visual.heading if not live.is_empty() else vessel.pose.heading
		var draft: float = campaign.effective_draft(vessel)
		var hull: Dictionary = PhysicsTypes.ship_spec(Catalog.DATA.profiles[vessel.profileId].modelKind)
		var dimensions: Dictionary = live.get("dimensions",{"length":hull.length,"width":hull.width})
		for length in [-0.5,0.0,0.5]:
			for width in [-0.5,0.0,0.5]:
				var x: float = position.x+cos(heading)*dimensions.length*length-sin(heading)*dimensions.width*width
				var z: float = position.z+sin(heading)*dimensions.length*length+cos(heading)*dimensions.width*width
				if -float(_height.call(x,z)) < draft+0.3: return true
		if state.currentPortId == null:
			for enemy: Dictionary in state.vessels.values():
				if enemy.ownerId != "enemy" or enemy.damage.hull <= 0 or enemy.id in policy.capturedShipIds: continue
				var real_enemy := _ship(native,enemy.id)
				if _distance(position,real_enemy.visual.position if not real_enemy.is_empty() else enemy.pose.position) <= 600: return true
	return false
func advance(frame_seconds: float) -> float:
	_accepted = 0; _rejected = 0
	if _disposed or not simulation or is_paused() or not is_finite(frame_seconds) or frame_seconds < 0: return 0
	if _rate == 8 and fast_forward_danger(): _rate = 1; _notify("fast-forward-danger")
	var requested := _pending+frame_seconds*_rate
	if requested > MAX_PENDING_SECONDS:
		_rejected = requested-MAX_PENDING_SECONDS; _rate = 1; _notify("simulation-budget-exceeded")
	_pending = minf(requested,MAX_PENDING_SECONDS)
	var iterations := 0
	while _pending+1e-10 >= STEP and iterations < MAX_TICKS and not is_paused():
		var tick: int = simulation.snapshot().tick
		simulation.advance(STEP)
		for outcome: Dictionary in simulation.drain_results():
			if not outcome.result.get("ok",false): _notify(outcome.result.get("reason","command-rejected"))
		if simulation.snapshot().tick != tick+1: _fail("native-tick-budget-mismatch"); break
		_pending = maxf(0,_pending-STEP); iterations += 1; _accepted = iterations*STEP
		var reconciled: Dictionary = bridge.reconcile()
		var business: Dictionary = campaign.advance(STEP,bridge.near_ids(),bridge.command_context() if reconciled.ok else {})
		if not reconciled.ok: _fail(reconciled.get("reason","near-handoff-rejected")); break
		if not business.ok: _fail(business.get("reason","business-advance-rejected")); break
		var state: Dictionary = campaign.snapshot()
		if state.vessels[state.flagshipId].damage.hull <= 0: set_pause("result",true); _notify("flagship-sunk"); break
		if _rate == 8 and fast_forward_danger(): _rate = 1; _notify("fast-forward-danger")
	return _accepted
func check_safety(session: RefCounted = null, native: Dictionary = {}, native_simulation: RefCounted = null) -> Dictionary:
	var source: RefCounted = session if session else campaign
	if not source: return _no("save-flagship-unavailable")
	var state: Dictionary = source.snapshot(); var flag: Dictionary = state.vessels.get(state.flagshipId,{})
	if flag.is_empty() or flag.damage.hull <= 0: return _no("save-flagship-unavailable")
	var real: Dictionary = native if not native.is_empty() else simulation.snapshot() if source == campaign and simulation else {}
	var authority: RefCounted = native_simulation if native_simulation else simulation if source == campaign else null
	var near_flag := _ship(real,state.flagshipId)
	var position: Dictionary = near_flag.visual.position if not near_flag.is_empty() else flag.pose.position
	var by_port := false
	for port: Dictionary in state.ports.values(): by_port = by_port or _distance(position,port.position) <= 55
	if not by_port: return _no("save-safe-port-required")
	if not source.active_boarding_ship_ids().is_empty(): return _no("save-active-boarding")
	if authority and authority.has_pending_input(): return _no("save-pending-input")
	if authority and authority.encounter.hasPendingAttacks(): return _no("save-pending-attacks")
	var policy: Dictionary = source.native_policy(state.vessels.keys())
	for enemy: Dictionary in state.vessels.values():
		if enemy.ownerId != "enemy" or enemy.damage.hull <= 0 or enemy.id in policy.capturedShipIds: continue
		var live := _ship(real,enemy.id)
		if _distance(position,live.visual.position if not live.is_empty() else enemy.pose.position) <= 600: return _no("save-local-hostile-threat")
	for vessel: Dictionary in state.vessels.values():
		if vessel.damage.hull <= 0 or not (vessel.id == state.flagshipId or vessel.id in policy.controllableShipIds or vessel.ownerId == "captain"): continue
		var live := _ship(real,vessel.id)
		if vessel.id == state.campaignId+"-heritage" and Bridge.ordinary_heritage_berth(state) and live.is_empty(): continue
		if vessel.voyageId != null and state.voyages.get(vessel.voyageId,{}).get("status") == "underway": return _no("save-fleet-underway:"+vessel.id)
		if authority and not real.is_empty():
			if live.is_empty() or not authority.encounter.isAnchored(vessel.id) or live.has("navigation") or authority.encounter.hasActiveOrder(vessel.id): return _no("save-fleet-not-anchored:"+vessel.id)
		elif vessel.representation != "near" or vessel.pose.speed > 0.05 or vessel.controls.rudder != 0 or vessel.controls.sailDeployment != 0: return _no("save-source-fleet-not-anchored:"+vessel.id)
	return {"ok":true}
func export_save(now_utc: String) -> Dictionary:
	if _disposed or not simulation or not bridge: return _no("runtime-unavailable")
	if _error or _pauses.has("error"): return _no(_notice if not _notice.is_empty() else "runtime-error")
	var sync: Dictionary = bridge.sync()
	if not sync.ok: return sync
	var safe := check_safety()
	return {"ok":true,"json":campaign.serialize(now_utc)} if safe.ok else safe
func save_checkpoint(storage: RefCounted, now_utc: String) -> Dictionary:
	var exported := export_save(now_utc)
	if not exported.ok: return exported
	var result: Dictionary = storage.write_checkpoint(exported.json)
	_notify("航程已保存。" if result.ok else result.get("reason","save-write-failed"))
	return result
func adopt_save(json: String, storage: RefCounted = null, now_utc: String = "2026-10-11T00:00:00.000Z") -> Dictionary:
	var candidate := Campaign.new()
	if not candidate.restore(json): return _no("save-invalid")
	var safety := check_safety(candidate)
	if not safety.ok: return safety
	var bundle := build_native(candidate,true)
	if not bundle.ok: return bundle
	safety = check_safety(candidate,bundle.simulation.snapshot(),bundle.simulation)
	if not safety.ok: bundle.bridge.dispose(); return safety
	if storage:
		var written: Dictionary = storage.write_checkpoint(candidate.serialize(now_utc))
		if not written.ok: bundle.bridge.dispose(); return written
	if simulation: simulation.set_paused(true)
	if bridge: bridge.dispose()
	campaign = candidate; simulation = bundle.simulation; bridge = bundle.bridge; bridge.set_observer(_observe)
	_generation += 1; _pending = 0; _events.clear(); _drafts.clear(); _draft_results.clear(); _error = false
	_pauses.clear(); _pauses.loading = true; simulation.set_paused(true); _notify("已恢复航程；准备后继续。")
	return {"ok":true}
func _dock_fact(state: Dictionary,native: Dictionary,policy: Dictionary,port_id: String) -> Dictionary:
	var flag := _ship(native,state.flagshipId); var port: Dictionary = state.ports.get(port_id,{})
	if flag.is_empty() or port.is_empty() or flag.hull <= 0 or _distance(flag.visual.position,port.position) > 55 or Vector2(flag.visual.velocity.x,flag.visual.velocity.z).length() > 0.75 or simulation.encounter.hasPendingAttacks() or not campaign.active_boarding_ship_ids().is_empty(): return _no("unsafe-port")
	for enemy: Dictionary in native.ships:
		if enemy.hull > 0 and state.flagshipId in policy.hostileTargets.get(enemy.id,[]) and _distance(flag.visual.position,enemy.visual.position) <= 600: return _no("unsafe-port")
	return {"ok":true}
func _eligibility(state: Dictionary,native: Dictionary,policy: Dictionary,docks: Dictionary) -> Dictionary:
	return Readiness.facts(state,native,policy,docks,campaign,simulation.encounter)
func snapshot() -> Dictionary:
	if not campaign or not simulation: return {}
	var state: Dictionary = campaign.snapshot(); var native: Dictionary = simulation.snapshot()
	var policy: Dictionary = campaign.native_policy(bridge.near_ids()); var docks: Dictionary = {}
	for id in state.ports: docks[id] = _dock_fact(state,native,policy,id)
	var safe := _no("runtime-error") if _error or _pauses.has("error") else check_safety()
	var depart: bool = state.currentPortId != null and docks.get(state.currentPortId,{}).get("ok",false) and state.flagshipId in policy.controllableShipIds
	for work: Dictionary in state.works.values(): depart = depart and work.status != "active"
	var loading_contract: Dictionary = {}
	for contract: Dictionary in state.contracts.values():
		if contract.status == "active":
			for voyage_id in contract.voyageIds:
				if state.voyages[voyage_id].status == "loading": loading_contract = contract; break
			if not loading_contract.is_empty(): break
	for voyage_id in loading_contract.get("voyageIds",[]):
		var voyage: Dictionary = state.voyages[voyage_id]
		var vessel: Dictionary = state.vessels[voyage.vesselId]
		depart = depart and voyage.status == "loading" and vessel.damage.hull > 0 and vessel.crew.able >= vessel.crew.minimum
	return {"campaign":state,"naval":native,"runtime":{"generation":_generation,"selectedShipId":native.playerId,"orderStatuses":simulation.encounter.orderStatus(),"paused":is_paused(),"pauseReasons":_pauses.keys(),"timeScale":_rate,"canSave":safe.ok,"saveReason":safe.get("reason",""),"status":"error" if _error else "ready","error":_error,"portId":state.currentPortId,"canDock":docks,"canDepart":depart,"departReason":"" if depart else "unsafe-port","eligibility":_eligibility(state,native,policy,docks),"controllableShipIds":policy.controllableShipIds,"policy":policy,"notice":_notice,"noticeRevision":_notice_revision,"acceptedSeconds":_accepted,"rejectedSeconds":_rejected,"handlingMode":_handling_mode,"handlingStatus":simulation.handling_status(),"drafts":_drafts.duplicate(true),"draftResults":_draft_results.duplicate(true)}}
func render_snapshot() -> Dictionary: return simulation.render_snapshot()
func drain_events() -> Array:
	var result := _events; _events = []; return result
func sample_water_height(x: float,z: float,seconds: float) -> float: return _waves.sample(x,z,seconds).height
func dispose() -> void:
	_disposed = true; _generation += 1; _pending = 0; _drafts.clear(); _events.clear()
	if simulation: simulation.set_paused(true)
	if bridge: bridge.dispose()
	bridge = null; simulation = null; campaign = null
