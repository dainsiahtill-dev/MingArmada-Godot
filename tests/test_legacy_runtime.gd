extends SceneTree
const Session = preload("res://game/domain/legacy/adventure_session.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Text = preload("res://game/domain/legacy/utf16_text.gd")
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; print("FAIL ",detail)
func sea(_x: float,_z: float) -> float: return -20.0
func equivalent(a,b) -> bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]: return abs(float(a)-float(b))<=1e-10*maxf(1,maxf(abs(float(a)),abs(float(b))))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equivalent(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equivalent(a[index],b[index]): return false
		return true
	return a==b
func projection(r) -> Dictionary:
	var packet: Dictionary = r.snapshot(); var s: Dictionary = packet.adventure; var n: Dictionary = packet.naval; var domain := {}
	for key in ["seed","elapsedSeconds","day","player","flagshipId","currentPortId","cargo","quests","relations","mainChapter","career","markets","battleActive","officers","ammoStocks","supplyPerDay","wagesPerDay"]: domain[key] = s[key]
	domain.fleet = []
	for fleet: Dictionary in s.fleet:
		var entry := fleet.duplicate(true)
		for key in ["position","heading","speed","navalState"]: entry.erase(key)
		domain.fleet.append(entry)
	var ships := []
	for ship: Dictionary in n.ships:
		var entry := {}
		for key in ["id","name","kind","team","hull","sail","crew","ammo","stats","sailDeployment"]: entry[key] = ship[key]
		ships.append(entry)
	return {"domain":domain,"native":{"tick":n.tick,"status":n.status,"playerId":n.playerId,"ships":ships}}
func test_source_oracle(Runtime) -> void:
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
	check(fixture!=null and fixture.sourceHead=="9ad6a44daecd4ec36a8172d83ff27493feffe5dd","frozen source runtime oracle")
	for scenario: Dictionary in fixture.scenarios:
		var r = Runtime.new(); check(r.configure(sea,scenario.options).ok,"oracle configure")
		check(equivalent(projection(r),scenario.initial),"source runtime initial canonical projection")
		for step: Dictionary in scenario.steps:
			var result: Dictionary = r.command(step.command)
			check(equivalent(result,step.result),"source runtime receipt "+step.command.type)
			check(equivalent(projection(r),step.projection),"source runtime domain/native projection "+step.command.type)
		r.dispose()
func career_checkpoint(Runtime,step_index: int):
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
	var r = Runtime.new(); r.configure(sea,{"initialDock":true})
	check(r.adopt_save(fixture.careerCheckpoints[str(step_index)]).ok,"source career checkpoint adopted "+str(step_index))
	return r
func test_surrender(Runtime) -> void:
	var r = career_checkpoint(Runtime,14)
	check(r.snapshot().naval.status=="active","near real hostile starts native battle")
	var initial: Dictionary = r.snapshot(); var prompt: Dictionary = r.begin_surrender()
	check(prompt.ok,"native/domain surrender quote")
	var tick: int = r.snapshot().naval.tick
	check(r.advance(5)==0 and r.snapshot().naval.tick==tick,"prompt freezes accepted tick")
	r.set_pause("menu",true)
	check(not r.confirm_surrender(prompt.quote.token).ok,"pause epoch invalidates quote")
	check(r.cancel_surrender(prompt.quote.token).ok and r.snapshot().runtime.pauseReasons.has("menu"),"cancel keeps unrelated pause")
	r.set_pause("menu",false); prompt = r.begin_surrender()
	check(prompt.ok,"fresh surrender quote")
	check(not r.confirm_surrender({"battleId":prompt.quote.token.battleId,"tick":prompt.quote.token.tick+1,"lossDigest":prompt.quote.token.lossDigest}).ok,"changed token refused")
	var confirmed: Dictionary = r.confirm_surrender(prompt.quote.token)
	check(confirmed.ok and r.snapshot().naval.status=="surrendered","native accepts actual surrender")
	var settled: Dictionary = r.snapshot()
	check(settled.adventure.player.silver==prompt.quote.terms.silver.after,"domain precise silver loss")
	check(settled.adventure.career.surrenders==initial.adventure.career.surrenders+1,"once-only surrender career")
	check(not r.confirm_surrender(prompt.quote.token).ok and r.snapshot()==settled,"duplicate confirmation atomic")
	check(not r.command({"type":"depart"}).ok,"pending receipt blocks business")
	var save: Dictionary = r.export_save(); check(save.ok,"pending receipt valid v1 checkpoint")
	check(r.resume_voyage().ok,"surrender result acknowledges home candidate")
	var resumed: Dictionary = r.snapshot()
	check(resumed.adventure.currentPortId=="xiamen" and not resumed.adventure.has("pendingSurrenderReceipt"),"source home receipt cleared")
	check(resumed.runtime.generation>settled.runtime.generation,"result replacement generation fence")
	check(not r.resume_voyage().ok,"result cannot acknowledge twice")
	r.dispose()
func test_panel_directed_commands(Runtime) -> void:
	var r = Runtime.new(); check(r.configure(sea,{"initialDock":true}).ok,"panel regression configures real runtime")
	check(r.command({"type":"depart"}).ok,"panel regression departs real voyage")
	r.set_pause("panel",true)
	var flag: Dictionary = r.snapshot().naval.ships[0]
	var waypoint := {"type":"navigate","point":{"x":flag.visual.position.x+80,"z":flag.visual.position.z}}
	var before: Dictionary = r.snapshot()
	check(r.preview_command(waypoint).ok,"chart waypoint ready under panel sea suspension")
	check(r.snapshot()==before,"panel waypoint preview detached")
	check(r.command(waypoint).ok,"chart waypoint installs native route under panel")
	check(r.snapshot().naval.ships[0].has("navigation"),"panel directed waypoint reaches native authority")
	var routed: Dictionary = r.snapshot()
	check(r.advance(.5)==0 and r.snapshot()==routed,"panel retains suspended sea clock after waypoint")
	check(not r.set_held("KeyW",true).ok and not r.set_sails(.5).ok and not r.toggle_trim().ok,"panel still fences manual helm sails and trim")
	check(not r.command({"type":"native-action","action":{"type":"fire","side":"port"}}).ok,"panel still fences fire")
	for reason in ["player","menu","blur","hidden"]:
		r.set_pause(reason,true); before = r.snapshot()
		check(not r.preview_command(waypoint).ok and not r.command(waypoint).ok and r.snapshot()==before,"real pause fences directed waypoint "+reason)
		r.set_pause(reason,false)
	check(r.snapshot().runtime.pauseReasons==["panel"],"directed waypoint preserves panel pause ownership")
	r.dispose()
	r = career_checkpoint(Runtime,14); r.set_pause("panel",true)
	check(r.snapshot().runtime.surrenderEligibility.ok and r.preview_command({"type":"begin-surrender"}).ok,"settings surrender button ready in actual battle under panel")
	for reason in ["player","menu","blur","hidden"]:
		r.set_pause(reason,true); before = r.snapshot()
		check(not r.snapshot().runtime.surrenderEligibility.ok and not r.begin_surrender().ok and r.snapshot()==before,"real pause fences settings surrender "+reason)
		r.set_pause(reason,false)
	var prompt: Dictionary = r.begin_surrender()
	check(prompt.ok,"settings surrender launches real quote under panel")
	if prompt.ok:
		check(r.cancel_surrender(prompt.quote.token).ok and r.snapshot().runtime.pauseReasons==["panel"],"settings surrender cancellation preserves panel sea pause")
	r.dispose()
func test_event_and_fleet_authority(Runtime) -> void:
	var r = career_checkpoint(Runtime,14)
	var original: Dictionary = r.snapshot()
	check(not r.command({"type":"native-action","action":{"type":"controls","shipId":"pirate-dongshan","rudder":1,"sailDeployment":1}}).ok,"hostile helm cannot be forged through UI intent")
	check(r.snapshot()==original,"hostile helm refusal atomic")
	check(r.simulation.encounter.updateShipStats("pirate-dongshan",{"hull":0}).ok,"native damage transition accepts zero hull")
	r.simulation.refresh_snapshot()
	var settled: Dictionary = r.snapshot()
	check(settled.adventure.career.battlesWon==original.adventure.career.battlesWon+1,"actual native victory enters career")
	check(settled.adventure.player.silver==original.adventure.player.silver+90,"actual sink source loot")
	check(settled.runtime.revision>original.runtime.revision,"automatic career settlement invalidates stale intents")
	var events: Array = r.drain_events()
	check(events.any(func(e): return e.type=="sink") and events.any(func(e): return e.type=="victory"),"native event stream observable")
	for event in events: r.simulation.encounter.events.append(event.duplicate(true))
	r.simulation.refresh_snapshot()
	check(r.snapshot().adventure==settled.adventure,"native duplicate events no duplicate reward")
	check(r.advance(.1)==0,"terminal result blocks time")
	check(r.resume_voyage().ok,"actual victory resumes")
	check(not r.snapshot().naval.ships.any(func(s): return s.id=="pirate-dongshan"),"sunk target never respawns")
	r.dispose()
	r = career_checkpoint(Runtime,73)
	check(r.command({"type":"buy-ship","kind":"fisherman"}).ok,"source earned fleet purchase")
	var new_id: String = r.snapshot().adventure.fleet[-1].id
	check(r.snapshot().naval.ships.any(func(s): return s.id==new_id),"purchase reconciles into native")
	check(r.command({"type":"sell-ship","shipId":new_id}).ok,"empty nonflagship sells")
	check(not r.snapshot().naval.ships.any(func(s): return s.id==new_id),"sold ship atomically removed")
	r.dispose()
func _initialize() -> void:
	var Runtime = load("res://game/runtime/legacy_runtime.gd")
	check(Runtime != null,"Legacy runtime authority exists")
	if Runtime == null: finish(); return
	var disk_runtime = Runtime.new()
	var disk_storage = Storage.new("user://tests/legacy-configure-v1.json",Runtime.validate_save)
	check(disk_runtime.configure(sea,{"initialDock":true,"storage":disk_storage}).ok,"real SaveCoordinator remains runtime-owned during initial dock")
	check(disk_runtime.voyage.storage==null,"domain autosave cannot bypass checkpoint transaction")
	check(disk_runtime.save_checkpoint().ok,"configured disk storage receives v1 transaction")
	disk_runtime.notify("operation-refused"); check(disk_runtime.snapshot().runtime.notice=="operation-refused","public notice seam")
	disk_runtime.dispose()
	var refusal = Runtime.new(); refusal.configure(sea,{"initialDock":true})
	refusal.simulation.encounter._ship("player").state.controlsSequence = refusal.simulation.encounter.SAFE_INTEGER
	refusal.simulation.refresh_snapshot(); var exhausted: Dictionary = refusal.snapshot()
	var rejected: Dictionary = refusal.command({"type":"hire-officer","role":"gunner"})
	check(not rejected.ok and rejected.reason=="Control sequence exhausted","actual native reconciliation refuses exhausted control sequence")
	check(refusal.snapshot()==exhausted,"native reconciliation failure leaves money/officer/native unchanged")
	refusal.dispose()
	test_source_oracle(Runtime)
	test_surrender(Runtime)
	test_panel_directed_commands(Runtime)
	test_event_and_fleet_authority(Runtime)
	var r = Runtime.new()
	check(r.configure(sea,{"seed":1661,"name":"沈沧海","initialDock":true}).ok,"configure docked legacy voyage")
	var opening: Dictionary = r.snapshot()
	check(opening.adventure.currentPortId == "xiamen","safe initial docking")
	check(opening.naval.tick == 0,"source 60Hz starts at tick zero")
	check(r.advance(1.0) == 0,"docked clock rejected")
	check(r.preview_command({"type":"buy","good":"iron","quantity":2}).ok,"readonly price preview")
	check(r.snapshot() == opening,"preview never mutates packet")
	var bought: Dictionary = r.command({"type":"buy","good":"iron","quantity":2,"generation":opening.runtime.generation,"expectedRevision":opening.runtime.revision})
	check(bought.ok,"staged business trade")
	var after_buy: Dictionary = r.snapshot()
	check(after_buy.adventure.cargo.iron == 2 and after_buy.runtime.revision > opening.runtime.revision,"trade commits and revision advances")
	check(not r.command({"type":"buy","good":"iron","quantity":1,"expectedRevision":opening.runtime.revision}).ok,"stale UI intent refused")
	check(not r.command({"type":"buy","good":"iron","quantity":-1}).ok,"invalid business quantity refused")
	check(r.snapshot() == after_buy,"failed command atomic across domain/native")
	check(r.command({"type":"hire-officer","role":"gunner"}).ok,"officer setup commits")
	var setup: Dictionary = r.snapshot()
	check(setup.naval.ships[0].stats.reloadMultiplier == Session.C.OFFICERS.gunner.reloadMultiplier,"officer modifier reaches native")
	var detached: Dictionary = r.snapshot(); detached.adventure.player.silver = 0; detached.naval.ships.clear(); detached.runtime.pauseReasons.append("forged")
	check(not r.snapshot().naval.ships.is_empty() and r.snapshot().adventure.player.silver > 0,"detached packet")
	check(r.command({"type":"depart"}).ok,"depart constructs actual native voyage")
	var generation: int = r.snapshot().runtime.generation
	check(generation > opening.runtime.generation,"native replacement bumps generation")
	var elapsed: float = r.snapshot().adventure.elapsedSeconds
	var accepted: float = r.advance(.5)
	check(abs(accepted-.1)<1e-8,"source frame clamp accepts only .1 native seconds")
	check(abs(r.snapshot().adventure.elapsedSeconds-elapsed-accepted)<1e-8,"domain advances native accepted time")
	r.set_pause("menu",true); var paused: Dictionary = r.snapshot()
	check(r.advance(.1)==0 and r.snapshot()==paused,"sea pause no hidden time")
	r.set_pause("player",true); r.set_pause("menu",false)
	check(r.snapshot().runtime.paused,"independent pause reasons")
	r.set_pause("player",false)
	var flag: Dictionary = r.snapshot().naval.ships[0]
	check(r.command({"type":"navigate","point":{"x":flag.visual.position.x+80,"z":flag.visual.position.z}}).ok,"native wet navigation")
	r.set_held("KeyA",true)
	check(not r.snapshot().naval.ships[0].has("navigation"),"manual helm cancels navigation")
	r.advance(.1); r.set_held("KeyA",false)
	check(abs(r.snapshot().naval.ships[0].rudder)>0,"held control reaches native")
	check(not r.command({"type":"resolve-banquet","portId":"xiamen","score":100}).ok,"UI cannot forge minigame rewards")
	check(not r.command({"type":"surrender","token":{}}).ok,"direct domain surrender fenced")
	check(not r.command({"type":"native-action","action":{"type":"surrender"}}).ok,"native surrender cannot bypass transaction")
	check(not r.preview_command({"type":"native-action","action":{"type":"controls","rudder":8,"sailDeployment":1}}).ok,"native preview returns real controls refusal")
	check(r.command({"type":"native-action","action":{"type":"select-ammo","ammo":"chain"}}).ok,"native ammunition uses exact source command")
	var save: Dictionary = r.export_save()
	check(save.ok,"safe sea save available")
	var storage = Storage.new("user://tests/legacy-runtime-v1.json",Runtime.validate_save)
	check(r.save_checkpoint(storage).ok and storage.read_checkpoint().ok,"real v1 disk transaction")
	var restored = Runtime.new(); restored.configure(sea,{"initialDock":true})
	var before_restore: Dictionary = restored.snapshot()
	var blocked = Storage.new("res://project.godot/blocked.json",Runtime.validate_save)
	check(not restored.adopt_save(save.json,blocked).ok,"actual disk directory failure refuses adoption")
	check(restored.snapshot()==before_restore,"failed adoption preserves generation/runtime")
	check(restored.adopt_save(save.json,storage).ok,"validated persisted candidate adopted")
	check(restored.snapshot().runtime.generation>before_restore.runtime.generation,"adoption invalidates callbacks")
	check(not restored.adopt_save('{"version":2}',storage).ok,"v2 cannot enter legacy v1")
	var exceptional = Session.new({"initialDock":false}); exceptional.command({"type":"rename","name":Text.from_units([97,0,0xd800,98])})
	check(restored.adopt_save(exceptional.serialize(),storage).ok,"exceptional UTF16 import validates original bytes")
	check(restored.voyage.state.player.name==exceptional.state.player.name,"exceptional UTF16 retained")
	r.dispose(); check(r.advance(.1)==0 and not r.command({"type":"depart"}).ok,"dispose fences runtime")
	restored.dispose()
	finish()
func finish() -> void:
	print("LEGACY_RUNTIME_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
