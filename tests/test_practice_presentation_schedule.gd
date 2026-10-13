extends SceneTree
## Actual free-sail Scene/Runtime/Sea with controlled native callback cadence.
## Tracing observes production presentation; it supplies no replacement scheduler.
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const STEP := 1.0 / 60.0
const TAIL_STEP := 0.05

class TracedPractice:
	extends "res://game/scenes/naval_practice/naval_practice.gd"
	var present_calls := 0
	var local_fire_calls := 0
	var presented_event_ids: Array[String] = []
	func _present_local_fire(consumed: float) -> void:
		local_fire_calls += 1
		if runtime.simulation:
			for event: Dictionary in runtime.simulation.get("_events"):
				presented_event_ids.append(str(event.get("id", "")))
		super._present_local_fire(consumed)
	func _present(consumed: float) -> void:
		present_calls += 1
		# Observe without draining. The real inherited presentation owns the buffer.
		if runtime.simulation:
			for event: Dictionary in runtime.simulation.get("_events"):
				presented_event_ids.append(str(event.get("id", "")))
		super._present(consumed)

class ConsumedSeaTrace:
	extends Node3D
	var actual: Node3D
	var accepted_deltas: Array[float] = []
	func cancel_camera_drag() -> void: actual.cancel_camera_drag()
	func camera_status() -> Dictionary: return actual.camera_status()
	func apply_local_fire(native: Dictionary, events: Array = [], consumed: float = 0.0) -> Array:
		return actual.apply_local_fire(native, events, consumed)
	func apply_snapshot(native: Dictionary, events: Array = [], consumed: float = 0.0) -> Array:
		# Only trace the delta crossing the scene/real-Sea boundary. The actual
		# source ships, crew, effects and world still execute their original code.
		accepted_deltas.append(consumed)
		return actual.apply_snapshot(native, events, consumed)

var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", detail)
	return value

func close(value: float, expected: float) -> bool:
	return absf(value - expected) < 1.0e-8

func _initialize() -> void:
	_run.call_deferred()

func _finish(scene: Node) -> void:
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self, playbacks), "Practice cleanup releases actual audio playback")
	print("PRACTICE_PRESENTATION_SCHEDULE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _has_render_callback(scene: Node) -> bool:
	# Native Node virtual-method discovery is insufficient for an absent script
	# callback. Check the actual script chain before calling the future API.
	var script: Script = scene.get_script()
	while script != null:
		for method: Dictionary in script.get_script_method_list():
			if method.name == "_process": return true
		script = script.get_base_script()
	return false

func _ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.ships:
		if ship.id == id: return ship
	return {}

func _run() -> void:
	var scene: Node3D = TracedPractice.new()
	scene.set("startup_options", {"mode":"sail", "staged":true})
	scene.set("settings_storage", Settings.new("user://verification/practice-schedule-no-write-%d.json" % OS.get_process_id()))
	root.add_child(scene)
	# Synchronous ready completes before any await. The calls below are actual
	# production callbacks; no automatic producer may sneak into this cadence.
	scene.set_physics_process(false)
	scene.set_process(false)
	if not check(scene.get("startup_receipt").get("ok", false), "actual free-sail Practice starts native fleet, geography, source ships and UI"):
		await _finish(scene); return
	scene.call("activate_entry")
	var runtime: RefCounted = scene.get("runtime")
	var sea: Node3D = scene.get("sea")
	check(not runtime.is_paused() and runtime.snapshot().runtime.mode == "sail", "ordinary activation clears staged loading and retains free-sail mode")
	var initial: Dictionary = runtime.snapshot().naval
	check(initial.ships.size() == 3 and initial.status == "sailing", "fixture retains the actual three-ship free-sail authority")
	var player: Node3D = sea.get("ships")[initial.playerId]
	var crew: Node3D = sea.get("sailors")[initial.playerId]
	var pool: Node3D = crew.get_impact_pool()
	# Presentation-only fixtures use actual barrels and drawn source bones. They
	# are not claimed as real projectiles and cannot change native authority.
	player.apply_events([{"type":"fire", "id":"practice-schedule-recoil-only", "shipId":initial.playerId, "side":"port", "time":initial.time}])
	if not check(not player.get("_recoil").is_empty() and crew.get_visible_count() > 0, "actual source barrel and standing skin provide consumed-delta witnesses"):
		await _finish(scene); return
	var skin: Node3D = crew.get("_instances").values()[0].root
	var point: Vector3 = skin.global_position
	var hit: Dictionary = {"type":"hit", "id":"practice-schedule-nonlethal-hit", "targetId":initial.playerId, "position":{"x":point.x, "y":point.y, "z":point.z}, "velocity":{"x":10.0, "y":0.0, "z":0.0}, "damage":{"crew":0.5}}
	crew.apply_events([hit, hit])
	check(runtime.snapshot().naval == initial, "explicit recoil/nonlethal presentation fixtures preserve every native authority field")
	if not check(pool.get_body_count() == 1 and crew.get("_seen").has(hit.id), "duplicate presentation hit transfers one actual source skin into one Jolt rig"):
		await _finish(scene); return
	var rig_id: String = pool.get("_bodies").keys()[0]
	var entry: Dictionary = pool.get("_bodies")[rig_id]
	check(entry.bones.size() == 18 and not entry.casualty, "fixture retains the actual eighteen-bone nonlethal rig")
	var bone: RigidBody3D = entry.bones[1]
	var gun: String = player.get("_recoil").keys()[0]
	var recoil: float = player.get("_recoil")[gun]
	var drawn_time: float = player.get("_time")
	var rig_age: float = entry.age
	var pool_phase: float = pool.get("_phase")
	scene.set("present_calls", 0)
	for unused in 8: scene.call("_physics_process", STEP)
	var advanced: Dictionary = runtime.snapshot().naval
	check(int(advanced.tick) - int(initial.tick) == 8 and close(float(advanced.time) - float(initial.time), 8.0 * STEP), "eight physics callbacks accept exactly eight authoritative fixed ticks")
	check(scene.get("present_calls") == 0, "eight ordinary physics callbacks perform no full Sea/world/UI presentation")
	check(close(float(player.get("_time")), drawn_time) and close(float(player.get("_recoil")[gun]), recoil), "physics-only source history does not advance drawn ship or render-owned recoil")
	var poses: Array = player.get("_source_poses")
	check(poses.size() >= 9 and close(float(poses[-1].time), advanced.time), "each physics tick records the real authoritative source pose before render")
	check(pool.get("_bodies").has(rig_id) and close(float(entry.age) - rig_age, 8.0 * STEP) and close(float(pool.get("_phase")) - pool_phase, 8.0 * STEP), "real Jolt rig phase and lifetime advance on every physics tick without full presentation")
	check(close(float(bone.get("accepted_delta")), STEP), "native bone retains one physics step rather than an accumulated render request")
	if not check(_has_render_callback(scene), "Practice implements an actual script render presentation callback"):
		await _finish(scene); return
	var age_after: float = entry.age
	var phase_after: float = pool.get("_phase")
	scene.call("_process", 30.0)
	check(scene.get("present_calls") == 1, "one render callback presents all eight accepted ticks exactly once")
	check(close(float(player.get("_time")), advanced.time) and close(float(crew.get("_time")), advanced.time), "drawn ship and crew receive the same latest native source time")
	check(scene.get("interface").get("_snapshot").naval == advanced, "real HUD receives the same full native authority snapshot")
	check(close(float(player.get("_recoil")[gun]), recoil * exp(-8.0 * STEP * 9.0)), "real barrel consumes only accumulated accepted delta despite thirty seconds of render wall delta")
	check(close(float(entry.age), age_after) and close(float(pool.get("_phase")), phase_after) and close(float(bone.get("accepted_delta")), STEP), "render neither double-steps the real rig nor overwrites its pending native request")
	recoil = player.get("_recoil")[gun]
	scene.call("_process", 60.0)
	check(scene.get("present_calls") == 2 and close(float(player.get("_recoil")[gun]), recoil) and close(float(entry.age), age_after), "duplicate render consumes no accepted interval twice and invents no wall-clock motion")

	# A real public fire command must consume native ammo before the test can
	# claim a generated shot or check the sparse immediate event transfer.
	var ammo_before: int = _ship(advanced, advanced.playerId).ammo.solid
	scene.call("_command", {"type":"fire", "side":"starboard"})
	var calls_before: int = scene.get("present_calls")
	for unused in 4: scene.call("_physics_process", STEP)
	var fired: Dictionary = runtime.snapshot().naval
	check(_ship(fired, fired.playerId).ammo.solid < ammo_before and not fired.projectiles.is_empty(), "actual Practice fire consumes ammo and creates authoritative projectiles")
	check(scene.get("present_calls") == calls_before and scene.get("local_fire_calls") == 1 and runtime.simulation.get("_events").is_empty(), "fresh fire gets one immediate local birth without another full scene presentation")
	var fire_ids: Array[String] = []
	for event_id: String in player.get("_seen_events"):
		if event_id != "practice-schedule-recoil-only" and sea.get("effects").get("_seen").has(event_id): fire_ids.append(event_id)
	check(not fire_ids.is_empty(), "actual generated fire reaches both real ship and combat presentation")
	scene.call("_process", 0.0)
	scene.call("_process", 0.0)
	for event_id: String in fire_ids:
		check(scene.get("presented_event_ids").count(event_id) == 1, "native fire event presents exactly once: " + event_id)
	crew.apply_events([hit])
	check(pool.get_body_count() == 1, "already seen nonlethal hit cannot duplicate its actual rig after render")

	# A pause command flushes intervals already accepted; later paused physics
	# and render callbacks preserve both authority and presentation consumers.
	for unused in 3: scene.call("_physics_process", STEP)
	var pause_native: Dictionary = runtime.snapshot().naval
	calls_before = scene.get("present_calls")
	scene.call("_command", {"type":"pause"})
	check(runtime.is_paused() and scene.get("present_calls") == calls_before + 1, "actual pause immediately flushes pending accepted state")
	var pause_time: float = player.get("_time")
	var pause_age: float = entry.age
	var pause_phase: float = pool.get("_phase")
	calls_before = scene.get("present_calls")
	for unused in 6: scene.call("_physics_process", STEP)
	check(scene.get("present_calls") == calls_before and runtime.snapshot().naval == pause_native, "paused physics neither presents nor changes any native authority field")
	scene.call("_process", 60.0)
	check(close(float(player.get("_time")), pause_time) and close(float(entry.age), pause_age) and close(float(pool.get("_phase")), pause_phase), "paused render freezes real ship and Jolt phase despite wall delta")
	scene.call("_command", {"type":"resume"})
	check(not runtime.is_paused(), "actual Practice resume clears its user pause")

	var source_events: Array[Dictionary] = []
	player.presentation_event.connect(func(event: Dictionary): source_events.append(event.duplicate(true)))
	check(runtime.simulation.encounter.update_ship_stats(str(fired.playerId), {"hull":0.0}).get("ok", false), "public native validator accepts a lethal free-sail flagship fixture")
	scene.call("_physics_process", STEP)
	var terminal: Dictionary = runtime.snapshot()
	check(terminal.naval.status == "defeat" and terminal.runtime.pauseReasons.has("result"), "actual Encounter settles flagship defeat and owns the terminal authority pause")
	check(close(player.damage_diagnostics().sinking_age, 0.0), "first terminal physics immediately anchors sinking at zero without render delay")
	calls_before = scene.get("present_calls")
	for unused in 6: scene.call("_physics_process", TAIL_STEP)
	check(scene.get("present_calls") == calls_before and close(player.damage_diagnostics().sinking_age, 0.0), "six tail physics callbacks defer full presentation while retaining the birth anchor")
	check(runtime.snapshot().naval == terminal.naval, "terminal physics tail preserves the complete frozen native authority")
	var tail_phase: float = pool.get("_phase")
	scene.call("_process", 60.0)
	check(close(player.damage_diagnostics().sinking_age, 0.3) and close(float(pool.get("_phase")), tail_phase), "one delayed render accepts exactly the accumulated terminal tail without Jolt double-step")
	check(scene.get("interface").get("_snapshot").naval == terminal.naval, "terminal HUD remains on the frozen authoritative source snapshot")
	scene.call("_command", {"type":"menu", "value":true})
	var sink_age: float = player.damage_diagnostics().sinking_age
	tail_phase = pool.get("_phase")
	calls_before = scene.get("present_calls")
	for unused in 6: scene.call("_physics_process", TAIL_STEP)
	scene.call("_process", 60.0)
	check(scene.get("present_calls") == calls_before + 1 and close(player.damage_diagnostics().sinking_age, sink_age) and close(float(pool.get("_phase")), tail_phase), "actual menu pause freezes terminal tail; only the requested render presents")
	check(runtime.snapshot().naval == terminal.naval, "menu pause leaves terminal native authority deeply equal")
	scene.call("_command", {"type":"resume"})
	for unused in 24: scene.call("_physics_process", TAIL_STEP)
	scene.call("_process", 0.0)
	check(close(player.damage_diagnostics().sinking_age, 1.5), "resume excludes all paused wall time and accepts only new terminal intervals")
	scene.call("_process", 60.0)
	for kind: String in ["destruction-explosion", "sinking-froth"]:
		var matching: Array = source_events.filter(func(event: Dictionary): return event.type == kind)
		check(matching.size() == 1 and sea.get("effects").get("_seen").has(matching[0].id), "real terminal source key reaches CombatEffects exactly once: " + kind)
	check(runtime.snapshot().naval == terminal.naval, "all delayed terminal renders preserve every frozen native authority field")

	# Return through the actual restart command, then prepare a healthy epoch
	# with accepted but unrendered mouse sailing. No pose or native state is forged.
	scene.call("_command", {"type":"restart"})
	var opening: Dictionary = runtime.snapshot()
	player = sea.get("ships")[opening.naval.playerId]
	check(opening.naval.tick == 0 and close(float(opening.naval.time), 0.0) and player.damage_diagnostics().sinking_age < 0.0, "actual restart supplies a healthy source epoch for the pending-interval regression")
	var wind: Dictionary = opening.naval.wind.direction
	var upwind: Vector2 = Vector2(-float(wind.x), -float(wind.get("z", wind.get("y", 0.0)))).normalized()
	var origin: Dictionary = _ship(opening.naval, opening.naval.playerId).visual.position
	var course_point: Dictionary = {}
	for reach: float in [1000.0, 2000.0, 4000.0]:
		var candidate: Vector2 = Vector2(float(origin.x), float(origin.z)) + upwind * reach
		var height: float = scene.get("heights").sample_height(candidate.x, candidate.y)
		if is_finite(height) and height < 0.0:
			course_point = {"x":candidate.x, "z":candidate.y}
			break
	if not check(not course_point.is_empty() and runtime.command({"type":"mouse-course", "point":course_point}).get("ok", false), "public mouse course accepts an actual water point against the source wind"):
		await _finish(scene); return
	check(runtime.simulation.handling_status().has("targetHeading"), "old epoch actually owns the accepted upwind mouse course before restart")
	player.apply_events([{"type":"fire", "id":"practice-schedule-restart-recoil-only", "shipId":opening.naval.playerId, "side":"port", "time":opening.naval.time}])
	calls_before = scene.get("present_calls")
	for unused in 8: scene.call("_physics_process", STEP)
	var unrendered: Dictionary = runtime.snapshot()
	check(unrendered.naval.tick == 8 and close(float(unrendered.naval.time), 8.0 * STEP) and scene.get("present_calls") == calls_before, "eight real mouse-course ticks remain pending before any render or restart")
	check(close(float(scene.get("_pending_presentation_seconds")), 8.0 * STEP) and not player.get("_recoil").is_empty(), "old epoch retains a nonzero pending interval and actual source recoil")
	var old_instance: int = player.get_instance_id()
	# Scoped instrumentation delegates the restart presentation to the same Sea.
	# It creates no replacement actor/world, and never intercepts physics callbacks.
	var trace: Node3D = ConsumedSeaTrace.new()
	trace.set("actual", sea)
	scene.set("sea", trace)
	scene.call("_command", {"type":"restart"})
	scene.set("sea", sea)
	var restart_deltas: Array[float] = trace.get("accepted_deltas").duplicate()
	trace.free()
	var fresh: Dictionary = runtime.snapshot()
	player = sea.get("ships")[fresh.naval.playerId]
	crew = sea.get("sailors")[fresh.naval.playerId]
	check(fresh.runtime.generation > unrendered.runtime.generation and fresh.naval.battleId != unrendered.naval.battleId, "restart replaces the actual native and runtime identities before presenting")
	check(restart_deltas.size() == 1 and close(restart_deltas[0], 0.0), "new epoch reaches real Sea with zero consumed delta rather than the old pending eight ticks")
	check(fresh.naval.tick == 0 and close(float(fresh.naval.time), 0.0) and close(float(player.get("_time")), 0.0) and close(float(crew.get("_time")), 0.0), "new native, source ship and source crew all begin at epoch time zero")
	check(player.get_instance_id() != old_instance and player.get("_recoil").is_empty() and crew.get_impact_pool().get_body_count() == 0, "restart owns a fresh source actor without old recoil or Jolt rigs")
	check(not runtime.simulation.handling_status().has("targetHeading") and not runtime.simulation.has_pending_input() and runtime.simulation.handling_status().phase == "idle", "restart clears old upwind mouse course, held input and handling recovery")
	check(close(float(scene.get("_pending_presentation_seconds")), 0.0) and not scene.get("_terminal_presentation").is_anchored(), "restart clears pending presentation and terminal anchor ownership")
	check(close(float(scene.get("services").get("audio").diagnostics().clock), 0.0) and scene.get("interface").get("_snapshot").naval == fresh.naval, "new epoch audio and actual HUD remain on the fresh native clock")
	scene.call("_process", 60.0)
	check(runtime.snapshot().naval == fresh.naval and close(float(player.get("_time")), 0.0) and player.get("_recoil").is_empty(), "render after restart cannot replay discarded pending time or old recoil")
	await _finish(scene)
