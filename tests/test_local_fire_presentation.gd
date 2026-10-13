extends SceneTree
## Real scene callbacks, authority, source ships, FX and HUD. Traces only count
## production calls; each trace forwards into the original live presenter.
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const STEP := 1.0 / 60.0

class TracedPractice:
	extends "res://game/scenes/naval_practice/naval_practice.gd"
	var full_calls := 0
	var local_events: Array = []
	var local_snapshots: Array[Dictionary] = []
	var native_snapshots: Array[Dictionary] = []
	func _physics_process(delta: float) -> void:
		native_snapshots.append(runtime.simulation.snapshot().duplicate(true))
		super._physics_process(delta)
		native_snapshots.append(runtime.simulation.snapshot().duplicate(true))
	func _present(consumed: float) -> void:
		full_calls += 1
		super._present(consumed)
	func _present_local_fire(consumed: float) -> void:
		local_events.append_array(runtime.simulation._events.duplicate(true))
		local_snapshots.append(runtime.simulation.snapshot().duplicate(true))
		super._present_local_fire(consumed)

class TracedMingqi:
	extends "res://game/scenes/mingqi/mingqi_scene.gd"
	var full_calls := 0
	var local_events: Array = []
	var local_snapshots: Array[Dictionary] = []
	var native_snapshots: Array[Dictionary] = []
	func _physics_process(delta: float) -> void:
		native_snapshots.append(runtime.simulation.snapshot().duplicate(true))
		super._physics_process(delta)
		native_snapshots.append(runtime.simulation.snapshot().duplicate(true))
	func _present(consumed: float) -> void:
		full_calls += 1
		super._present(consumed)
	func _present_local_fire(consumed: float) -> void:
		local_events.append_array(runtime._events.duplicate(true))
		local_snapshots.append(runtime.simulation.snapshot().duplicate(true))
		super._present_local_fire(consumed)

class DetachedWater:
	extends "res://game/presentation/water/water_splashes.gd"
	var release_calls: Array = []
	func dispose() -> void:
		super.dispose()
		release_calls.append(true)

class DetachedEffects:
	extends "res://game/presentation/combat/combat_effects.gd"
	var release_calls: Array = []
	func dispose() -> void:
		super.dispose()
		release_calls.append(true)

class WorldTrace:
	extends Node3D
	var actual: Node3D
	var calls := 0
	func apply_snapshot(native: Dictionary, consumed: float) -> void:
		calls += 1
		actual.apply_snapshot(native, consumed)

class InterfaceTrace:
	extends CanvasLayer
	var actual: CanvasLayer
	var chart: Control
	var calls := 0
	func apply_snapshot(packet: Dictionary) -> void:
		calls += 1
		actual.apply_snapshot(packet)
	func is_menu_open() -> bool: return actual.is_menu_open()
	func is_panel_open() -> bool: return actual.is_panel_open()
	func captures_keyboard() -> bool: return actual.captures_keyboard()

var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL local fire: ", detail)
	return ok

func close(value: float, expected: float) -> bool: return absf(value-expected) < 1.0e-8

func _run() -> void:
	await _scene_case(false)
	await _scene_case(true)
	_detached_disposal()
	print("LOCAL_FIRE_PRESENTATION_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _scene_case(mingqi: bool) -> void:
	var scene: Node3D = TracedMingqi.new() if mingqi else TracedPractice.new()
	var label := "Mingqi" if mingqi else "Practice"
	scene.set("startup_options", {"seed":1650,"campaignId":"local-fire-1650","captainName":"炮火船长","staged":true} if mingqi else {"mode":"sail","staged":true})
	if not mingqi: scene.set("settings_storage", Settings.new("user://verification/local-fire-no-write-%d.json" % OS.get_process_id()))
	root.add_child(scene)
	scene.set_physics_process(false); scene.set_process(false)
	if not check(scene.get("startup_receipt").get("ok",false), label+" real scene starts source actors, water and interface"):
		await _release(scene); return
	scene.call("activate_entry")
	var runtime: RefCounted = scene.get("runtime")
	if mingqi:
		scene.get("interface").close_panel()
		var campaign: Dictionary = runtime.snapshot().campaign
		var accepted: Dictionary = runtime.command({"type":"accept-convoy","commandId":"local-fire-accept","expectedRevision":campaign.revision})
		campaign = runtime.snapshot().campaign
		var departed: Dictionary = runtime.command({"type":"depart","commandId":"local-fire-depart","expectedRevision":campaign.revision})
		if not check(accepted.get("ok",false) and departed.get("ok",false), label+" real opening campaign authorizes departure before firing"):
			await _release(scene); return
		scene.call("_present",0.0)
	var sea: Node3D = scene.get("sea")
	var world_trace := WorldTrace.new(); world_trace.actual = sea.get("world"); scene.add_child(world_trace); sea.set("world",world_trace)
	var interface_trace := InterfaceTrace.new(); interface_trace.actual = scene.get("interface")
	if not mingqi: interface_trace.chart = interface_trace.actual.get("chart")
	scene.add_child(interface_trace); scene.set("interface",interface_trace)
	var initial: Dictionary = runtime.snapshot().naval
	var player: Node3D = sea.get("ships")[initial.playerId]
	var full_before: int = scene.get("full_calls")
	var authority_before: Dictionary = initial.duplicate(true)
	# Public scene command queues the real salvo. No injected fire events are used
	# to establish whether the physics scheduler still traverses the whole scene.
	scene.call("_command",{"type":"fire","side":"starboard"})
	check(scene.get("full_calls")==full_before and world_trace.calls==0 and interface_trace.calls==0,label+" successful public fire queues input without full scene/world/HUD presentation")
	# Accepted physics must retain the same local boundary for subsequent guns.
	full_before = scene.get("full_calls"); world_trace.calls = 0; interface_trace.calls = 0
	# Opening Mingqi has 60/80 crew: ten-tick gun interval, last birth at tick31.
	# Practice starts its healthy native battery at eight-tick gun intervals.
	var ticks := 32 if mingqi else 26
	for unused in ticks: scene.call("_physics_process",STEP)
	var fired: Dictionary = runtime.snapshot().naval
	var source: Array = sea.get("effects").get("_source_fire")
	var ids: Array[String] = []
	for effect: Dictionary in source: ids.append(String(effect.node.name).trim_prefix("CannonSource_"))
	check(source.size()==4, label+" four actual native cannon births survive one delayed render")
	check(scene.get("full_calls")==full_before, label+" physics fire births perform zero full scene presentations")
	check(world_trace.calls==0 and interface_trace.calls==0, label+" four births perform zero world and HUD updates")
	check(int(fired.tick)-int(authority_before.tick)==ticks and close(float(fired.time)-float(authority_before.time),float(ticks)*STEP), label+" accepted authority retains every fixed tick")
	check(not player.get("_recoil").is_empty(), label+" local births immediately reach actual source cannon recoil")
	check(runtime.get("_events").is_empty() if mingqi else runtime.simulation.get("_events").is_empty(), label+" local fire drains authoritative ordered events immediately")
	var actual_events: Array = scene.get("local_events").filter(func(event: Dictionary)->bool: return event.get("type")=="fire")
	var birth_snapshots: Array[Dictionary] = scene.get("local_snapshots")
	var accepted_snapshots: Array[Dictionary] = scene.get("native_snapshots")
	check(actual_events.size()==4,label+" local hook receives all four original ordered fire payloads")
	var oracle := Ship.new(); root.add_child(oracle)
	check(oracle.configure(String(initial.ships[0].kind),sea.get("library")),label+" actual source ship supplies independent born-pose oracle")
	var original: Node3D = sea.get("library").instantiate_model(str(oracle.get_model().get_meta("source_path"))); root.add_child(original)
	for index in source.size():
		var effect: Dictionary = source[index]
		var id := String(effect.node.name).trim_prefix("CannonSource_")
		check(player.get("_seen_events").has(id) and sea.get("effects").get("_seen").has(id), label+" each accepted cannon reaches ship and FX once: "+id)
		if index<actual_events.size(): check(id==str(actual_events[index].id) and close(float(effect.time),float(actual_events[index].time)),label+" local source retains authoritative fire id, time and ordering")
		if index<birth_snapshots.size():
			var born: Dictionary = {}
			for sample: Dictionary in accepted_snapshots:
				if close(float(sample.time),float(actual_events[index].time)): born=sample; break
			if not check(not born.is_empty(),label+" independent oracle has authoritative pose at exact event birth stamp"): continue
			var vessel := Sea.find_ship(born,String(initial.playerId)); vessel.time=born.time
			oracle.apply_snapshot(vessel,born.wind,0.0)
			var expected := _original_mouth(oracle,actual_events[index],original)
			check(effect.node.diagnostics().origin.distance_to(expected)<0.001,label+" source smoke retains untouched GLB muzzle at its own accepted birth pose")
			check(close(float(effect.node.diagnostics().accepted_time),float(birth_snapshots[-1].time)),label+" existing FX advances only at original accepted fire appTimes")
		check(scene.get("services").get("audio").get("_seen").has(id),label+" real audio receives original fire id once")
	oracle.dispose(); oracle.free(); original.free()
	var native_copy := fired.duplicate(true)
	scene.call("_process",60.0)
	check(scene.get("full_calls")==full_before+1 and world_trace.calls==1 and interface_trace.calls==1, label+" next render presents scene/world/HUD exactly once")
	check(runtime.snapshot().naval==native_copy and sea.get("effects").get("_source_fire").size()==4, label+" render preserves ballistics and does not replay births")
	check(sea.has_method("apply_local_fire"),label+" Sea exposes narrow fire birth API")
	if sea.has_method("apply_local_fire") and not source.is_empty():
		var captured: Dictionary = source[0]
		var duplicate: Dictionary = {"id":ids[0],"type":"fire","shipId":initial.playerId,"side":"starboard","time":captured.time,"projectileId":"duplicate-fixture","position":{"x":0.0,"y":3.0,"z":0.0},"velocity":{"x":1.0,"y":0.0,"z":0.0}}
		var state_before: Dictionary = captured.node.diagnostics()
		var recoil_before: Dictionary = player.get("_recoil").duplicate(true)
		sea.call("apply_local_fire",fired,[duplicate,duplicate],0.0)
		check(sea.get("effects").get("_source_fire").size()==4 and captured.node.diagnostics()==state_before and player.get("_recoil")==recoil_before,label+" duplicate same-time fire does not recreate FX or force recoil")
		check(world_trace.calls==1 and interface_trace.calls==1,label+" duplicate birth never redraws world or HUD")
		# Supplementary presentation fixture: change only the current accepted
		# displayed pose, then deliver a NEW id carrying the first native birth.
		# The authoritative runtime remains exactly equal to its real fired state.
		var late: Dictionary = actual_events[0].duplicate(true); late.id=label+"-late-original-fire"
		var late_copy := late.duplicate(true)
		var moved := fired.duplicate(true)
		var moved_player := Sea.find_ship(moved,String(initial.playerId)); moved_player.visual.position.x+=100.0
		sea.remember_authoritative_poses(moved,0.0)
		sea.call("apply_local_fire",moved,[late],0.0)
		var late_source: Dictionary = sea.get("effects").get("_source_fire")[-1]
		check(late_source.node.diagnostics().origin==captured.node.diagnostics().origin and close(float(late_source.node.diagnostics().age),float(fired.time)-float(late.time)),label+" late local birth retains historical original mouth and age after displayed ship moves")
		check(late==late_copy and runtime.snapshot().naval==native_copy,label+" late local adapter leaves native payload and ballistics immutable")
		check(world_trace.calls==1 and interface_trace.calls==1,label+" late fire remains local despite current ship moving")
	scene.call("_command",{"type":"pause"} if not mingqi else {"type":"menu","value":true})
	var paused: Dictionary = runtime.snapshot().naval
	if sea.has_method("apply_local_fire") and not actual_events.is_empty():
		var newborn: Dictionary = actual_events[-1].duplicate(true)
		newborn.id=label+"-paused-same-time-newborn"; newborn.time=paused.time
		newborn.source_muzzle_position={"x":12.25,"y":4.5,"z":-8.0}
		var prior_count: int = sea.get("effects").get("_source_fire").size()
		sea.call("apply_local_fire",paused,[newborn],0.0)
		var fresh: Dictionary = sea.get("effects").get("_source_fire")[-1]
		check(sea.get("effects").get("_source_fire").size()==prior_count+1 and fresh.node.diagnostics().origin==Vector3(12.25,4.5,-8.0) and close(float(fresh.time),float(paused.time)),label+" paused same-time new id still creates exact captured born muzzle")
		check(player.get("_seen_events").has(newborn.id) and player.get("_recoil").values().has(-0.6),label+" same-time newborn forces actual source cannon recoil")
	var paused_sources: Array = sea.get("effects").diagnostics().source_effects
	var paused_recoil: Dictionary = player.get("_recoil").duplicate(true)
	for unused in 4: scene.call("_physics_process",STEP)
	scene.call("_process",60.0)
	check(runtime.snapshot().naval==paused and sea.get("effects").diagnostics().source_effects==paused_sources and player.get("_recoil")==paused_recoil,label+" pause freezes real native FX and recoil despite wall delta")
	full_before=scene.get("full_calls")
	var world_before := world_trace.calls
	var hud_before := interface_trace.calls
	scene.call("_command",{"type":"fire","side":"starboard"})
	check(scene.get("full_calls")==full_before+1 and world_trace.calls==world_before+1 and interface_trace.calls==hud_before+1 and not String(runtime.snapshot().runtime.notice).is_empty(),label+" rejected paused fire still immediately presents real error notice")
	# Restore original ownership handles before disposal; trace helpers own none
	# of the forwarding targets and cannot conceal lifecycle leaks.
	scene.set("interface",interface_trace.actual); sea.set("world",world_trace.actual)
	await _release(scene)

func _water(_x: float,_z: float,_time: float) -> float: return 0.0

func _original_mouth(view: Node3D,event: Dictionary,original: Node3D) -> Vector3:
	var model: Node3D = view.get_model()
	var nearest: Node3D = null
	var distance := INF
	var point := Vector3(float(event.position.x),float(event.position.y),float(event.position.z))
	for socket: Node3D in model.find_children("socket_smoke_"+str(event.side)+"_*","Node3D",true,false):
		var next := socket.global_position.distance_squared_to(point)
		if next<distance: nearest=socket; distance=next
	var source: Node3D = original.find_child(str(nearest.name),true,false)
	return model.global_transform*(original.global_transform.affine_inverse()*source.global_position)

func _detached_disposal() -> void:
	for replacement in [true,false]:
		var owner := Effects.new()
		var water := DetachedWater.new()
		var ledger: Array = []
		water.release_calls = ledger
		owner.add_child(water); owner.set("_water_splashes",water)
		water.configure(_water)
		# configure itself calls dispose; only subsequent OWNER calls count.
		ledger.clear()
		var retained: WeakRef = weakref(water)
		if replacement: owner.set_water_sampler(_water)
		else: owner.dispose()
		check(ledger.size()==1 and retained.get_ref()==null,"detached Combat explicitly disposes WaterSplashes before "+("sampler replacement" if replacement else "owner teardown"))
		owner.dispose(); owner.free()
	var sea := Sea.new()
	var effects := DetachedEffects.new()
	var ledger: Array = []
	effects.release_calls = ledger
	sea.add_child(effects); sea.set("effects",effects); sea.get("_owned").append(effects)
	sea.dispose()
	check(ledger.size()==1,"detached Sea explicitly disposes Combat before freeing its owned subtree")
	sea.free()
	sea = Sea.new(); effects = DetachedEffects.new(); ledger=[]
	effects.release_calls=ledger
	sea.add_child(effects); sea.set("effects",effects); sea.get("_owned").append(effects)
	sea.set("_water",_water)
	sea.call("_reset_fleet")
	check(ledger.size()==1,"detached Sea epoch reset explicitly disposes old Combat before replacing its subtree")
	sea.dispose(); sea.free()

func _release(scene: Node) -> void:
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self,playbacks),"real scene disposal releases audio playback")
