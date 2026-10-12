extends SceneTree
## Exercise the real opening scene, not a replacement scheduler or fake world.
## Root runs this headless: the author deliberately does not start a second Godot.
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const STEP := 1.0 / 60.0

class TracedMingqi:
	extends "res://game/scenes/mingqi/mingqi_scene.gd"
	var present_calls := 0
	var presented_event_ids: Array[String] = []
	func _present(consumed: float) -> void:
		present_calls += 1
		# Observe without draining: the production presentation owns that operation.
		for event: Dictionary in runtime._events:
			presented_event_ids.append(str(event.get("id", "")))
		super._present(consumed)

var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", detail)

func close(value: float, expected: float) -> bool:
	return absf(value - expected) < 1.0e-8

func _initialize() -> void:
	_run.call_deferred()

func _finish(scene: Node) -> void:
	var playbacks := AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self, playbacks), "scene cleanup releases real audio playback")
	print("MINGQI_PRESENTATION_SCHEDULE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)

func _run() -> void:
	var scene := TracedMingqi.new()
	scene.startup_options = {"seed":1650,"campaignId":"schedule-1650","captainName":"调度船长","staged":true}
	root.add_child(scene)
	# _ready is synchronous. Disable automatic callbacks before the first await;
	# calls below are the actual scene callbacks with a controlled frame cadence.
	scene.set_physics_process(false)
	scene.set_process(false)
	check(scene.startup_receipt.get("ok", false), "actual Mingqi geography, fleet, world and interface start")
	if not scene.startup_receipt.get("ok", false):
		await _finish(scene)
		return
	check(scene.runtime.snapshot().campaign.currentPortId == "xiamen", "fixture begins at the real opening anchorage")
	check(scene.interface.is_panel_open() and scene.interface._panel == "story", "opening story remains the real initial UI state")
	check(scene.activate_entry().get("ok", false), "normal entry activation clears staged loading pause")
	check(not scene.runtime.is_paused(), "opening story panel does not manufacture an authority pause")
	scene.interface.close_panel()
	var initial: Dictionary = scene.runtime.snapshot().naval
	var player: Node3D = scene.ships[initial.playerId]
	# A real barrel is a consumed-delta consumer: its exponential recoil decay
	# distinguishes an omitted, duplicated or wall-clock presentation delta.
	player.apply_events([{"type":"fire","id":"schedule-recoil-only","shipId":initial.playerId,"side":"port","time":initial.time}])
	check(not player._recoil.is_empty(), "actual source ship has an operable recoil barrel")
	if player._recoil.is_empty():
		await _finish(scene)
		return
	var gun: String = str(player._recoil.keys()[0])
	var recoil_before: float = player._recoil[gun]
	var visible_time_before: float = player._time
	scene.present_calls = 0
	for unused in 8:
		scene._physics_process(STEP)
	var advanced: Dictionary = scene.runtime.snapshot().naval
	check(int(advanced.tick) - int(initial.tick) == 8, "eight physics callbacks accept eight authoritative native ticks")
	check(close(float(advanced.time) - float(initial.time), 8.0 * STEP), "authority advances by eight accepted fixed intervals")
	check(scene.present_calls == 0, "eight physics callbacks perform no sea/world/interface presentation")
	check(close(player._time, visible_time_before), "physics history capture does not apply the visible ship snapshot")
	check(close(float(player._recoil[gun]), recoil_before), "physics-only cadence does not advance render-owned recoil")
	check(scene.has_method("_process"), "Mingqi exposes the render presentation callback")
	# On the original implementation this is an assertion failure, not a missing
	# method script error or a coroutine left waiting for an unimplemented render.
	if not scene.has_method("_process"):
		await _finish(scene)
		return
	scene.call("_process", STEP)
	check(scene.present_calls == 1, "one render callback presents the complete accepted state exactly once")
	check(close(player._time, advanced.time), "render receives the latest authoritative time")
	check(close(float(player._recoil[gun]), recoil_before * exp(-8.0 * STEP * 9.0)), "real recoil consumes accumulated accepted delta rather than render wall delta")
	check(scene.interface._packet.naval.tick == advanced.tick, "UI receives the same latest native tick as the ship")
	var recoil_after: float = player._recoil[gun]
	scene.call("_process", 2.0)
	check(scene.present_calls == 2 and close(float(player._recoil[gun]), recoil_after), "second render without physics does not consume the interval twice or invent wall time")

	for unused in 3:
		scene._physics_process(STEP)
	var before_command: Dictionary = scene.runtime.snapshot().naval
	var calls_before := scene.present_calls
	scene._command({"type":"pause","value":true})
	check(scene.present_calls == calls_before + 1 and scene.runtime.is_paused(), "pause command immediately flushes a pending presentation")
	check(scene.interface._packet.runtime.paused and scene.interface._packet.naval.tick == before_command.tick, "command flush publishes both pause and accumulated native state")
	check(close(float(player._recoil[gun]), recoil_after * exp(-3.0 * STEP * 9.0)), "pause command preserves already accepted delta in its immediate flush")
	recoil_after = player._recoil[gun]
	scene.call("_process", STEP)
	check(close(float(player._recoil[gun]), recoil_after), "render after command flush does not consume its delta again")
	calls_before = scene.present_calls
	for unused in 8:
		scene._physics_process(STEP)
	check(scene.runtime.snapshot().naval.tick == before_command.tick and scene.present_calls == calls_before, "paused physics neither advances authority nor presents")
	var camera_before: Vector3 = scene.camera.global_position
	var zoom_before: float = scene._zoom
	var wheel := InputEventMouseButton.new()
	wheel.pressed = true
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	scene._unhandled_input(wheel)
	scene.call("_process", STEP)
	check(scene._zoom < zoom_before and scene.camera.global_position.distance_to(camera_before) > 0.01, "paused render still applies actual wheel zoom to the real camera")
	check(close(player._time, before_command.time) and close(float(player._recoil[gun]), recoil_after), "paused camera interaction preserves simulation and recoil clocks")
	scene._command({"type":"pause","value":false})
	check(not scene.runtime.is_paused(), "resume command clears only its actual player pause")

	# Existing capture/tests advance the runtime directly and pass their accepted
	# interval to _present. This API must remain valid alongside queued physics.
	var direct_accepted: float = scene.runtime.advance(2.0 * STEP)
	calls_before = scene.present_calls
	scene._present(direct_accepted)
	check(scene.present_calls == calls_before + 1 and close(direct_accepted, 2.0 * STEP), "manual capture presentation remains callable with a real accepted interval")
	check(close(float(player._recoil[gun]), recoil_after * exp(-direct_accepted * 9.0)), "manual presentation forwards accepted delta exactly once")
	recoil_after = player._recoil[gun]
	scene.call("_process", STEP)
	check(close(float(player._recoil[gun]), recoil_after), "manual flush leaves no duplicate pending interval")

	# Fire only after a real, permitted acceptance/departure. Queuing a fire at
	# the initial dock is not evidence that the encounter generated a shot.
	var campaign: Dictionary = scene.runtime.snapshot().campaign
	var accepted: Dictionary = scene.runtime.command({"type":"accept-convoy","commandId":"schedule-accept","expectedRevision":campaign.revision})
	check(accepted.get("ok", false), "actual opening convoy acceptance succeeds")
	campaign = scene.runtime.snapshot().campaign
	var departed: Dictionary = scene.runtime.command({"type":"depart","commandId":"schedule-depart","expectedRevision":campaign.revision})
	check(departed.get("ok", false), "actual anchored fleet receives a valid departure")
	scene._present(0.0)
	if accepted.get("ok", false) and departed.get("ok", false):
		scene._command({"type":"fire","side":"starboard"})
		calls_before = scene.present_calls
		for unused in 8:
			scene._physics_process(STEP)
		# Fresh shots/hits intentionally retain immediate snapshot + event
		# transfer, so crew birth pose, retirement and cannon loading stay exact.
		# The normal eight-tick cadence above is still render-only presentation.
		var fire_ids: Array[String] = []
		for id in player._seen_events:
			if id != "schedule-recoil-only" and scene.effects._seen.has(id):
				fire_ids.append(str(id))
		check(not fire_ids.is_empty(), "actual accepted player fire reaches the immediate event presentation")
		check(scene.present_calls == calls_before + 1 and scene.runtime._events.is_empty(), "one fresh fire physics callback flushes events immediately without eight full presentations")
		scene.call("_process", STEP)
		check(scene.present_calls == calls_before + 2 and scene.runtime._events.is_empty(), "following render updates the latest state without replaying immediate events")
		for id in fire_ids:
			check(scene.presented_event_ids.count(id) == 1 and scene.effects._seen.has(id), "buffered fire reaches actual combat presentation exactly once: " + id)
		var effects_before: Dictionary = scene.effects.diagnostics()
		scene._present(0.0)
		check(scene.effects.diagnostics().source_fire == effects_before.source_fire, "same-time manual presentation does not duplicate source cannon effects")
		for id in fire_ids:
			check(scene.presented_event_ids.count(id) == 1, "already drained fire is not presented a second time: " + id)
	await _finish(scene)
