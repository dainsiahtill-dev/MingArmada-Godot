extends SceneTree
## Real scenes, native validators, source models and Jolt pools. Callback cadence
## is controlled; no replacement snapshot, invented victory or fake damage view.
const MingqiScene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
const PracticeScene = preload("res://game/scenes/naval_practice/naval_practice.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const STEP := 1.0 / 60.0
const TAIL_STEP := 0.05
const UTC := "2026-10-13T00:00:00.000Z"

class TailAudioSettings extends "res://game/persistence/user_settings.gd":
	func _init(settings_path: String) -> void:
		super(settings_path)
		# This audio-clock fixture explicitly enables sound in its owned memory.
		# Product defaults stay muted; no settings file is loaded or written.
		_settings.sound = true

class MemoryCheckpoint extends RefCounted:
	var raw := ""
	func write_checkpoint(value: String) -> Dictionary:
		raw = value
		return {"ok":true}
	func read_checkpoint() -> Dictionary:
		return {"ok":true, "json":raw} if not raw.is_empty() else {"ok":false, "reason":"save-not-found"}

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

func _release(scene: Node) -> void:
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free()
	check(await AudioCleanup.wait_for_release(self, playbacks), "terminal scene releases actual audio playback")

func _mount(scene: Node, label: String) -> bool:
	scene.set("settings_storage", TailAudioSettings.new("user://verification/terminal-scene-%s-no-write-%d.json" % [label, OS.get_process_id()]))
	root.add_child(scene)
	# _ready is synchronous: no automatic callback can sneak into the fixture.
	scene.set_physics_process(false)
	scene.set_process(false)
	var started: bool = scene.get("startup_receipt").get("ok", false)
	check(started, "actual " + label + " scene starts with native fleet, source ships and UI")
	return started

func _clock(scene: Node):
	# A missing integration fails safely even before the production helper exists.
	for property: Dictionary in scene.get_property_list():
		if property.name == "_terminal_presentation": return scene.get("_terminal_presentation")
	return null

func _require_clock(scene: Node, label: String) -> bool:
	var clock: RefCounted = _clock(scene)
	var attached: bool = clock != null and clock.has_method("diagnostics") and clock.has_method("is_playing")
	check(attached, label + " owns the finite terminal presentation clock")
	return attached

func _draw(scene: Node) -> void:
	# Both actual scene scripts present on render. Do not rely on native Node
	# virtual method discovery to invent a callback for another scene type.
	if scene.get_script() in [MingqiScene, PracticeScene]: scene.call("_process", 0.0)

func _tick(scene: Node, seconds: float = TAIL_STEP) -> void:
	scene.call("_physics_process", seconds)
	_draw(scene)

func _watch(view: Node3D) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	view.presentation_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
	return events

func _ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.ships:
		if ship.id == id: return ship
	return {}

func _check_authority(scene: Node, terminal: Dictionary, label: String) -> void:
	var after: Dictionary = scene.get("runtime").snapshot()
	check(after.naval == terminal.naval and after.get("campaign", {}) == terminal.get("campaign", {}), label + " preserves every native and campaign authority field")
	var ui: Dictionary = scene.get("interface").get("_packet" if terminal.has("campaign") else "_snapshot")
	check(ui.naval == after.naval and ui.runtime.pauseReasons.has("result"), label + " UI keeps the paused authoritative native clock and result")

func _check_events(scene: Node, events: Array[Dictionary], label: String) -> void:
	var effects: Node3D = scene.get("sea").get("effects")
	for kind: String in ["destruction-explosion", "sinking-froth"]:
		var matching: Array = events.filter(func(event: Dictionary): return event.type == kind)
		check(matching.size() == 1, label + " emits actual " + kind + " exactly once")
		if matching.size() == 1:
			check(effects.get("_seen").has(matching[0].id), label + " real CombatEffects accepts " + kind)

func _frozen_interval(scene: Node, view: Node3D, reason: String) -> void:
	var before: Dictionary = scene.get("runtime").snapshot()
	var age: float = view.damage_diagnostics().sinking_age
	var pose: Transform3D = view.get_model().transform
	var crew: Node3D = scene.get("sea").get("sailors")[str(view.get("_snapshot").id)]
	var pool: Node3D = crew.get_impact_pool()
	var phase: float = pool.get("_phase")
	for unused in 4: _tick(scene)
	# Render wall time must never become accepted presentation time.
	if scene.get_script() in [MingqiScene, PracticeScene]: scene.call("_process", 60.0)
	check(close(view.damage_diagnostics().sinking_age, age) and view.get_model().transform.is_equal_approx(pose), reason + " freezes real sinking age and model pose")
	check(close(float(pool.get("_phase")), phase), reason + " freezes the actual Jolt accepted phase")
	check(not _clock(scene).is_playing(), reason + " leaves no active terminal playback while blocked")
	_check_authority(scene, before, reason + " interval")

func _exercise_pauses(scene: Node, view: Node3D, mingqi: bool) -> void:
	var runtime: RefCounted = scene.get("runtime")
	for reason: String in ["player", "menu", "blur", "loading"]:
		if reason == "player": scene.call("_command", {"type":"pause", "value":true})
		elif reason == "menu" and mingqi: scene.get("interface").open_menu()
		elif reason == "menu": scene.call("_command", {"type":"menu", "value":true})
		elif reason == "blur" and not mingqi: scene.call("_notification", Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
		else: check(runtime.set_pause(reason, true).get("ok", false), "public " + reason + " pause is accepted")
		check(runtime.snapshot().runtime.pauseReasons.has(reason), reason + " is a real independent authority pause")
		if reason == "menu":
			var audio: Node = scene.get("services").get("audio")
			check(audio.diagnostics().state == "paused", "actual menu command immediately pauses terminal audio before another physics callback")
			scene.call("_present", 0.0)
			check(audio.diagnostics().state == "paused", "immediate zero-delta menu presentation keeps terminal audio paused")
		var age: float = view.damage_diagnostics().sinking_age
		_frozen_interval(scene, view, reason)
		if reason == "player" and mingqi: scene.call("_command", {"type":"pause", "value":false})
		elif reason == "menu" and mingqi: scene.get("interface").close_menu()
		elif reason in ["player", "menu", "blur"] and not mingqi: scene.call("_command", {"type":"resume"})
		else: check(runtime.set_pause(reason, false).get("ok", false), "public " + reason + " resume is accepted")
		_tick(scene)
		check(close(view.damage_diagnostics().sinking_age, age + TAIL_STEP), reason + " resume accepts only the new interval and excludes paused time")
		check(runtime.snapshot().runtime.pauseReasons.has("result"), reason + " resume retains authoritative terminal pause")
	if mingqi:
		scene.call("_command", {"type":"time-scale", "value":0.0})
		check(close(runtime.snapshot().runtime.timeScale, 0.0), "actual time-scale command sets rate zero")
		var age: float = view.damage_diagnostics().sinking_age
		_frozen_interval(scene, view, "rate-zero")
		scene.call("_command", {"type":"time-scale", "value":1.0})
		_tick(scene)
		check(close(view.damage_diagnostics().sinking_age, age + TAIL_STEP), "rate-zero resume excludes all blocked intervals")
	else:
		scene.call("_command", {"type":"chart", "value":true})
		check(scene.get("interface").get("chart").visible and runtime.snapshot().runtime.pauseReasons.has("chart"), "actual practice chart pauses the terminal tail")
		var age: float = view.damage_diagnostics().sinking_age
		_frozen_interval(scene, view, "chart")
		scene.call("_command", {"type":"chart", "value":false})
		_tick(scene)
		check(close(view.damage_diagnostics().sinking_age, age + TAIL_STEP), "chart close resumes only a new accepted terminal interval")

func _advance_until(scene: Node, view: Node3D, age: float, label: String) -> void:
	var callbacks := 0
	while view.damage_diagnostics().sinking_age + 1.0e-8 < age and callbacks < 170:
		_tick(scene)
		callbacks += 1
	check(close(view.damage_diagnostics().sinking_age, age), label + " accepts the requested finite presentation time")

func _finish_sink(scene: Node, view: Node3D, terminal: Dictionary, events: Array[Dictionary], label: String, cap: bool = true) -> void:
	_advance_until(scene, view, 5.0, label)
	_check_authority(scene, terminal, label + " five-second tail")
	check(view.damage_diagnostics().ended and not view.get_model().visible, label + " real finite sinking ends and hides the source model")
	_check_events(scene, events, label)
	if cap:
		var max_seconds: float = _clock(scene).diagnostics().maxSeconds
		_advance_until(scene, view, max_seconds, label)
		# Decimal callback sums can land just below the finite limit; the next callback
		# must accept only that finite remainder rather than restart the tail.
		if _clock(scene).is_playing(): _tick(scene)
		check(not _clock(scene).is_playing(), label + " clock maximum finishes after sink, crew and residual water lifetimes")
		var audio: Node = scene.get("services").get("audio")
		check(scene.get("runtime").snapshot().runtime.pauseReasons == ["result"], label + " final audio boundary retains result as its only authority pause")
		check(close(audio.diagnostics().clock, float(view.get("_time"))) and audio.diagnostics().state == "running", label + " last positive tail interval publishes visual audio time and stays unpaused")
		_tick(scene, 0.0)
		check(close(audio.diagnostics().clock, float(view.get("_time"))) and audio.diagnostics().state == "paused", label + " next zero interval freezes finished terminal audio at final visual time")
		var phase: float = view.get("_time")
		for unused in 4: _tick(scene)
		check(close(float(view.get("_time")), phase), label + " finished tail never restarts from a frozen native clock")
		_check_events(scene, events, label + " finished replay")
		_check_authority(scene, terminal, label + " finished tail")

func _test_mingqi(scene: Node) -> void:
	scene.get("interface").close_panel()
	scene.set("storage", MemoryCheckpoint.new())
	var runtime: RefCounted = scene.get("runtime")
	var healthy: Dictionary = runtime.export_save(UTC)
	check(healthy.get("ok", false), "real safe opening authority exports a validated healthy checkpoint")
	var id: String = runtime.snapshot().naval.playerId
	var view: Node3D = scene.get("ships")[id]
	var events: Array[Dictionary] = _watch(view)
	check(runtime.simulation.encounter.update_ship_stats(id, {"hull":0.0}).get("ok", false), "public encounter validator accepts lethal Mingqi flagship fixture")
	_tick(scene, STEP)
	var terminal: Dictionary = runtime.snapshot()
	check(terminal.naval.status == "defeat" and terminal.runtime.pauseReasons.has("result"), "actual Mingqi authority settles flagship defeat and owns result pause")
	check(close(view.damage_diagnostics().sinking_age, 0.0), "first Mingqi death callback anchors source sinking without extra elapsed time")
	_tick(scene, 0.0)
	check(close(view.damage_diagnostics().sinking_age, 0.0), "zero physics and render callbacks cannot advance terminal presentation")
	_exercise_pauses(scene, view, true)
	_finish_sink(scene, view, terminal, events, "Mingqi")
	if not healthy.get("ok", false): return
	var generation: int = runtime.snapshot().runtime.generation
	scene.call("_command", {"type":"import-save", "json":healthy.json})
	var restored: Dictionary = runtime.snapshot()
	check(restored.runtime.generation > generation and restored.runtime.pauseReasons.has("loading"), "actual validated import replaces campaign/native epoch and keeps loading pause")
	check(close(_clock(scene).diagnostics().elapsed, 0.0) and not _clock(scene).is_playing(), "successful scene import clears finished terminal elapsed time and playback")
	view = scene.get("ships")[id]
	check(view.damage_diagnostics().sinking_age < 0.0 and not view.damage_diagnostics().ended and view.get_model().visible, "imported healthy source model has no old sink timeline")
	scene.get("interface").close_menu()
	scene.get("interface").close_panel()
	events = _watch(view)
	var crew: Node3D = scene.get("sailors")[id]
	var pool: Node3D = crew.get_impact_pool()
	check(crew.get_visible_count() > 0, "healthy imported source crew supplies an actual drawn skin for the rig fixture")
	if crew.get_visible_count() <= 0: return
	var skin: Node3D = crew.get("_instances").values()[0].root
	var point: Vector3 = skin.global_position
	var before_hit: Dictionary = runtime.snapshot()
	# Explicit presentation hit fixture, not a real projectile. The production
	# transfer creates native bones/joints from the actual drawn source skeleton;
	# nonlethal damage leaves native crew authority unchanged.
	crew.apply_events([{"type":"hit", "id":"terminal-nonlethal-rig", "targetId":id, "position":{"x":point.x, "y":point.y, "z":point.z}, "velocity":{"x":10.0, "y":0.0, "z":0.0}, "damage":{"crew":0.5}}])
	check(pool.get_body_count() == 1, "explicit nonlethal hit fixture transfers one actual source skin into a real Jolt rig")
	check(runtime.snapshot().naval == before_hit.naval and runtime.snapshot().campaign == before_hit.campaign, "nonlethal visual hit fixture preserves every native and campaign crew authority field")
	if pool.get_body_count() != 1: return
	var rig_id: String = pool.get("_bodies").keys()[0]
	var entry: Dictionary = pool.get("_bodies")[rig_id]
	check(entry.bones.size() == 18 and not entry.casualty, "fixture owns the actual eighteen-bone nonlethal source rig")
	var bone: RigidBody3D = entry.bones[1]
	check(runtime.simulation.encounter.update_ship_stats(id, {"hull":0.0}).get("ok", false), "second real Mingqi epoch accepts an independent lethal fixture")
	scene.call("_physics_process", STEP)
	terminal = runtime.snapshot()
	var age_before: float = entry.age
	var phase_before: float = pool.get("_phase")
	for unused in 6: scene.call("_physics_process", TAIL_STEP)
	check(close(float(pool.get("_phase")), phase_before + 0.3) and crew.get("_has_impact_phase"), "six physics-only terminal callbacks advance the actual Jolt rig phase before render")
	check(pool.get("_bodies").has(rig_id) and close(float(entry.age) - age_before, 0.3), "live native rig lifetime consumes all six terminal physics intervals after the lethal native step")
	check(close(float(bone.get("accepted_delta")), TAIL_STEP), "terminal native bone keeps one 0.05-second request rather than the accumulated render interval")
	var phase_after: float = pool.get("_phase")
	var age_after: float = entry.age
	_draw(scene)
	check(close(view.damage_diagnostics().sinking_age, 0.3), "delayed first render retains the first-death anchor across six physics intervals")
	check(close(float(pool.get("_phase")), phase_after) and close(float(entry.age), age_after) and close(float(bone.get("accepted_delta")), TAIL_STEP), "render of the latest terminal phase neither advances real rig lifetime twice nor overwrites its native step")
	_draw(scene)
	check(close(float(pool.get("_phase")), phase_after) and close(float(entry.age), age_after) and close(float(bone.get("accepted_delta")), TAIL_STEP) and close(view.damage_diagnostics().sinking_age, 0.3), "duplicate render preserves real rig phase, lifetime, pending bone request and source sinking age")
	check(events.filter(func(event: Dictionary): return event.type == "destruction-explosion").size() == 1, "delayed first render crosses and emits the real explosion key once")
	_check_authority(scene, terminal, "Mingqi delayed first render")

func _practice_fire(scene: Node) -> bool:
	var runtime: RefCounted = scene.get("runtime")
	var before: Dictionary = runtime.snapshot().naval
	var ammunition: int = _ship(before, before.playerId).ammo.solid
	scene.call("_command", {"type":"fire", "side":"starboard"})
	_tick(scene, STEP)
	var native: Dictionary = runtime.snapshot().naval
	var fired: bool = _ship(native, native.playerId).ammo.solid < ammunition
	check(fired and native.status == "active", "actual practice fire consumes native ammo and activates encounter before lethal fixture")
	return fired and native.status == "active"

func _restart_practice(scene: Node, label: String) -> void:
	var old: Dictionary = scene.get("runtime").snapshot()
	scene.call("_command", {"type":"restart"})
	var fresh: Dictionary = scene.get("runtime").snapshot()
	check(fresh.runtime.generation > old.runtime.generation and fresh.naval.battleId != old.naval.battleId and fresh.naval.tick == 0, label + " restart replaces actual native identity and tick")
	check(not fresh.runtime.paused and not _clock(scene).is_playing() and close(_clock(scene).diagnostics().elapsed, 0.0), label + " restart clears result pause and terminal elapsed time")
	var view: Node3D = scene.get("sea").get("ships")[fresh.naval.playerId]
	check(view.damage_diagnostics().sinking_age < 0.0 and view.get_model().visible and close(float(view.get("_time")), fresh.naval.time), label + " restarted source model begins healthy at its new native clock")
	check(scene.get("sea").get("effects").get("_seen").is_empty(), label + " restart drops old destruction and fire receipts")

func _test_practice(scene: Node) -> void:
	if not _practice_fire(scene): return
	var runtime: RefCounted = scene.get("runtime")
	var native: Dictionary = runtime.snapshot().naval
	check(not native.projectiles.is_empty(), "actual accepted practice fire leaves a live authoritative projectile before victory")
	var projectile_ids: Array[String] = []
	for projectile: Dictionary in native.projectiles: projectile_ids.append(str(projectile.id))
	var enemies: Array = native.ships.filter(func(ship: Dictionary): return ship.team == "hostile")
	check(enemies.size() == 1, "real duel has exactly one last hostile for victory fixture")
	if enemies.size() != 1: return
	var enemy_id: String = enemies[0].id
	var view: Node3D = scene.get("sea").get("ships")[enemy_id]
	var events: Array[Dictionary] = _watch(view)
	check(runtime.simulation.encounter.update_ship_stats(enemy_id, {"hull":0.0}).get("ok", false), "public native validator sinks the actual last hostile")
	_tick(scene, STEP)
	var terminal: Dictionary = runtime.snapshot()
	check(terminal.naval.status == "victory" and terminal.runtime.pauseReasons.has("result"), "native Encounter._finish produces actual last-enemy victory and result pause")
	for projectile_id: String in projectile_ids:
		check(terminal.naval.projectiles.any(func(projectile: Dictionary): return projectile.id == projectile_id), "terminal native authority retains the actual accepted fire projectile: " + projectile_id)
	check(not terminal.naval.projectiles.is_empty() and scene.get("sea").get("effects").diagnostics().projectiles == 0, "victory keeps frozen native projectiles while real CombatEffects stops drawing their ball meshes")
	check(close(view.damage_diagnostics().sinking_age, 0.0), "first practice victory callback anchors hostile source sinking at age zero")
	_exercise_pauses(scene, view, false)
	_finish_sink(scene, view, terminal, events, "practice victory")
	# Presenter rebuild from the actual frozen dead authority, not a forged view
	# snapshot or an invalid dead-flagship save. First-loaded dead skins skip clips.
	scene.get("sea")._reset_fleet()
	scene.call("_present", 0.0)
	view = scene.get("sea").get("ships")[enemy_id]
	events = _watch(view)
	check(view.damage_diagnostics().ended and not view.get_model().visible, "presenter rebuilt from actual dead authority starts ended and hidden")
	for unused in 4: _tick(scene)
	check(events.is_empty() and scene.get("sea").get("effects").get("_seen").is_empty(), "rebuilt dead presenter does not replay explosion or froth")
	_check_authority(scene, terminal, "practice dead-presenter rebuild")
	_restart_practice(scene, "victory")
	if not _practice_fire(scene): return
	native = runtime.snapshot().naval
	view = scene.get("sea").get("ships")[native.playerId]
	events = _watch(view)
	check(runtime.simulation.encounter.update_ship_stats(native.playerId, {"hull":0.0}).get("ok", false), "public native validator accepts lethal practice flagship fixture")
	_tick(scene, STEP)
	terminal = runtime.snapshot()
	check(terminal.naval.status == "defeat" and terminal.runtime.pauseReasons.has("result"), "actual practice player loss settles native defeat")
	check(close(view.damage_diagnostics().sinking_age, 0.0), "first practice defeat callback adds no extra sinking age")
	_finish_sink(scene, view, terminal, events, "practice defeat", false)
	_restart_practice(scene, "unfinished defeat tail")
	_tick(scene, STEP)
	check(close(_clock(scene).diagnostics().elapsed, 0.0), "new accepted practice physics cannot revive old terminal elapsed time")

func _run() -> void:
	var mingqi: Node3D = MingqiScene.new()
	if _mount(mingqi, "Mingqi") and _require_clock(mingqi, "Mingqi"):
		_test_mingqi(mingqi)
	await _release(mingqi)
	# Sequential scene ownership keeps real audio/Jolt resources out of each
	# other's startup and stays below the root runner's per-script timeout.
	var practice: Node3D = PracticeScene.new()
	if _mount(practice, "practice") and _require_clock(practice, "practice"):
		_test_practice(practice)
	await _release(practice)
	print("TERMINAL_SCENE_PRESENTATION_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
