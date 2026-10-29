extends SceneTree
## Scripted real menu entry. Four accepted native ticks per sampled GPU frame.
## This is not 60fps, per-physics-tick imagery, manual play, or campaign acceptance.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0 / 60.0
const TICKS_PER_FRAME := 4
const MAX_FRAMES := 300
const SEED := 1661
var failures: Array = []
var captures: Array = []
var sequence: Array = []
var actions: Array = []
var checks: Array = []
var output := ""
var own_output := false
var main: Node
var lab: Control
var physics_checks := 0
var visible_projectile_samples := 0
var early_stop: Dictionary = {}
var last_snapshot: Dictionary = {}

func _initialize() -> void: run.call_deferred()

func check(value: bool, message: String) -> bool:
	if not value:
		failures.append(message)
		printerr("FAIL CREW BATTLE GPU: ", message)
	return value

func frames(count: int) -> void:
	for _index in count: await process_frame

func normal(path: String) -> String:
	return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func inside(path: String, parent: String) -> bool:
	return not parent.is_empty() and normal(path).begins_with(normal(parent) + "/")

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected := OS.get_environment("CREW_BATTLE_CAPTURE_OUTPUT")
	var profile := OS.get_environment("CREW_BATTLE_PROFILE_ROOT")
	var original := OS.get_environment("CREW_BATTLE_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/crew-role-effects/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		check(not adapter.is_empty() and not "llvmpipe" in adapter and not "swiftshader" in adapter and not "software" in adapter, "hardware graphics required")
	if not failures.is_empty():
		print("CREW_BATTLE_GPU_GUARD_REJECTED failures=", failures.size())
		quit(2)
		return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create fresh output"): quit(2); return
	own_output = true
	seed(SEED)
	AudioServer.set_bus_mute(0, true)
	await resize(Vector2i(1600, 900))
	main = Main.instantiate()
	root.add_child(main)
	await frames(4)
	var button: Button = main.menu.find_child("laboratory", true, false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled, "actual main menu laboratory button"): await finish(); return
	button.pressed.emit()
	for _index in 120:
		await process_frame
		if is_instance_valid(main.current_scene): break
	lab = main.current_scene
	if not check(is_instance_valid(lab) and lab.startup_receipt.get("ok", false), "laboratory opened from actual menu"): await finish(); return
	lab.set_process(false)
	if not check(lab.select_topic("crew-role-effects"), "registered crew topic selectable"): await finish(); return
	var started: Dictionary = lab.start_demo({"mode":"battle", "roster":"ordinary", "pressure":"duel", "paused":true, "repair_helpers":0, "seed":SEED, "camera_mode":"fixed"})
	checks.append({"name":"real_entry", "receipt":started.duplicate(true)})
	if not check(started.get("ok", false), "start actual battle mode: " + str(started)): await finish(); return
	await frames(5)
	last_snapshot = lab._demo.inspection_snapshot()
	if not check(conserved(last_snapshot), "initial authoritative state and contract"): await finish(); return
	if not await sample_frame(0, 0, "wide-start"): await finish(); return
	for frame in range(1, MAX_FRAMES + 1):
		var accepted := 0
		for _tick in TICKS_PER_FRAME:
			var before: Dictionary = lab._demo.inspection_snapshot()
			if before.get("finished", false): break
			var receipt: Dictionary = lab.step_demo()
			if not check(receipt.get("ok", false), "actual host single-step accepted"): await finish(); return
			var after: Dictionary = lab._demo.inspection_snapshot()
			if not check(int(after.tick) == int(before.tick) + 1 and conserved(after), "one native tick with material, health and budget conservation"): await finish(); return
			physics_checks += 1
			accepted += 1
			if int(after.tick) in [60, 180]: issue_assignment(1 if int(after.tick) == 60 else 0, after)
			if after.get("finished", false): break
		if accepted == 0: break
		if not await sample_frame(frame, accepted, "wide-middle" if frame == 60 else ""): await finish(); return
		if frame % 60 == 0:
			print("CREW_BATTLE_GPU_PROGRESS frame=", frame, " tick=", last_snapshot.tick, " accepted_seconds=", last_snapshot.time)
		if last_snapshot.get("finished", false):
			early_stop = {"reason":"native trial finished", "outcome":last_snapshot.get("outcome", ""), "frame":frame, "tick":last_snapshot.tick, "before_minimum_120_frames":frame < 120}
			break
	if sequence.size() <= 60:
		# A very early terminal battle still has an honest final checkpoint; no
		# duplicate accepted ticks are manufactured to meet a frame quota.
		if not save_page("wide-middle", last_snapshot): await finish(); return
	if not save_page("wide-end", last_snapshot): await finish(); return
	var stopped: Dictionary = lab._demo.inspection_snapshot()
	await frames(8)
	var unchanged: bool = lab._demo.inspection_snapshot() == stopped
	check(unchanged, "paused rendering leaves complete authoritative and view state unchanged")
	checks.append({"name":"pause", "frames":8, "tick":stopped.get("tick", 0), "unchanged":unchanged})
	await resize(Vector2i(960, 640))
	await process_frame
	await RenderingServer.frame_post_draw
	var narrow: Dictionary = lab._demo.inspection_snapshot()
	check(narrow.tick == stopped.tick and narrow.state == stopped.state, "viewport resize does not advance or mutate trial")
	if not save_page("narrow-page", narrow): await finish(); return
	var metrics: Dictionary = last_snapshot.get("metrics", {})
	check(int(metrics.get("fire_count", 0)) > 0 and int(metrics.get("hit_count", 0)) > 0 and float(metrics.get("hull_damage_taken", 0.0)) > 0.0, "actual native fire, hit and incoming physical loss observed")
	check(visible_projectile_samples > 0, "at least one native projectile mesh is visible on screen outside HUD")
	check(sequence.size() - 1 >= 120 or not early_stop.is_empty(), "minimum sequence or explicit native early-stop reason")
	check(actions.size() == 2 or not early_stop.is_empty(), "both scheduled commands attempted unless native battle ended first")
	await finish()

func resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.content_scale_size = size
	root.size = size
	await frames(4)

func issue_assignment(count: int, before: Dictionary) -> void:
	# Use the same host operation as the live parameter widgets. Its returned
	# receipt records real casualty or transition rejections without a state edit.
	var receipt: Dictionary = lab._change_parameter("repair_helpers", count)
	var after: Dictionary = lab._demo.inspection_snapshot()
	actions.append({"tick":before.tick, "action":"repair_helpers", "value":count, "receipt":receipt.duplicate(true), "before":before.state.duplicate(true), "after":after.state.duplicate(true)})
	check(after.tick == before.tick and after.native == before.native and after.contract == before.contract, "assignment cannot award time, hull, projectiles or money")
	print("CREW_BATTLE_GPU_ACTION tick=", before.tick, " helpers=", count, " receipt=", JSON.stringify(receipt))

func ship(native: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in native.get("ships", []):
		if value.get("id") == id: return value
	return {}

func near(a: float, b: float) -> bool: return absf(a - b) <= 0.000001

func conserved(snap: Dictionary) -> bool:
	var native: Dictionary = snap.get("native", {})
	var crew: Dictionary = snap.get("crew", {})
	var ledger: Dictionary = crew.get("ledger", {})
	var contract: Dictionary = snap.get("contract", {})
	var metrics: Dictionary = snap.get("metrics", {})
	var player := ship(native, "player")
	if player.is_empty() or crew.is_empty() or ledger.is_empty() or contract.is_empty() or metrics.is_empty(): return false
	if not snap.get("ready", false) or not snap.get("paused", false) or snap.get("camera_mode") != "fixed" or not near(float(snap.fixed_step), STEP) or not near(float(snap.time), int(snap.tick) * STEP) or int(native.tick) != int(snap.tick) or not near(float(native.time), float(snap.time)): return false
	if not near(float(contract.budget), 144.0) or int(contract.day) != 0 or not near(float(contract.wages_paid), 0.0) or not contract.phase_receipts.is_empty(): return false
	if not near(float(contract.recruitment_paid) + float(contract.wage_reserved) + float(contract.wages_paid) + float(contract.free_cash), 144.0): return false
	var health := 0.0
	var ids: Array = []
	for worker: Dictionary in crew.workers:
		if not is_finite(float(worker.health)) or float(worker.health) < 0.0 or float(worker.health) > 1.0 or worker.id in ids: return false
		health += float(worker.health)
		ids.append(worker.id)
	if ids != contract.hired_ids or not near(health, float(crew.crew_equivalent)) or not near(health, float(player.crew)): return false
	if not near(float(player.hull), float(crew.hull)) or not near(float(player.hull), 54.0 + float(metrics.hull_repaired) - float(metrics.hull_damage_taken)): return false
	if not near(float(ledger.hull_repaired), float(metrics.hull_repaired)) or not near(float(ledger.hull_damage), float(metrics.hull_damage_taken)) or not near(float(ledger.crew_lost), float(metrics.crew_lost)): return false
	if not near(16.0 - float(crew.wood), float(ledger.wood_used)) or not near(float(ledger.wood_used), float(metrics.hull_repaired) * 0.5): return false
	if not near(24.0 - float(crew.grain), float(ledger.grain_used)) or not near(float(ledger.meals_cooked), float(ledger.grain_used)) or not near(float(ledger.meals_cooked), float(ledger.meals_eaten) + float(crew.cooked_rations)): return false
	return near(12.0 - health, float(metrics.crew_lost)) and float(crew.hull) >= 0.0 and float(crew.hull) <= 80.0 and float(crew.wood) >= 0.0 and float(crew.grain) >= 0.0 and int(player.ammo.solid) + int(metrics.ammo_spent) == 40

func visible_projectiles(snap: Dictionary, viewport: SubViewport) -> Array:
	var result: Array = []
	var sea: Node3D = lab._demo.find_child("CrewBattleProductionSea", true, false)
	if not is_instance_valid(sea) or not is_instance_valid(sea.camera) or not is_instance_valid(sea.effects): return result
	var balls: Dictionary = sea.effects.get("_balls")
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var overlays: Array[Rect2] = []
	for id: String in ["CrewBattleShips", "CrewBattleLedger"]:
		var panel: Control = lab._demo.find_child(id, true, false)
		if is_instance_valid(panel): overlays.append(panel.get_global_rect())
	for projectile: Dictionary in snap.get("native", {}).get("projectiles", []):
		var ball: MeshInstance3D = balls.get(projectile.id)
		if not is_instance_valid(ball) or not ball.is_visible_in_tree() or sea.camera.is_position_behind(ball.global_position): continue
		var screen: Vector2 = sea.camera.unproject_position(ball.global_position)
		if not bounds.has_point(screen) or overlays.any(func(rect: Rect2) -> bool: return rect.has_point(screen)): continue
		result.append({"id":projectile.id, "ship_id":projectile.shipId, "screen":[screen.x, screen.y], "mesh_visible":true})
	return result

func sample_frame(index: int, ticks: int, page: String = "") -> bool:
	await process_frame
	await RenderingServer.frame_post_draw
	var snap: Dictionary = lab._demo.inspection_snapshot()
	var viewport: SubViewport = lab.find_child("ExperimentViewport", true, false)
	if not check(is_instance_valid(viewport) and conserved(snap), "same-frame viewport and authoritative snapshot"): return false
	var seen := visible_projectiles(snap, viewport)
	visible_projectile_samples += seen.size()
	var metrics: Dictionary = snap.metrics
	sequence.append({"frame":index, "tick":snap.tick, "time":snap.time, "ticks_advanced":ticks, "native_projectile_count":snap.native.projectiles.size(), "visible_projectiles":seen, "physical_events_count":int(metrics.events_count), "metrics":metrics.duplicate(true), "hull":snap.crew.hull, "crew_equivalent":snap.crew.crew_equivalent, "wood":snap.crew.wood, "contract_day":snap.contract.day})
	last_snapshot = snap
	if not save_image(viewport.get_texture().get_image(), "battle-%03d.png" % index, "experiment", snap): return false
	if not page.is_empty() and not save_page(page, snap): return false
	return true

func save_page(name: String, snap: Dictionary) -> bool:
	var viewport: SubViewport = lab.find_child("ExperimentViewport", true, false)
	if not check(is_instance_valid(viewport), "experiment viewport exists in full page"): return false
	var bounds := Rect2(Vector2.ZERO, Vector2(viewport.size))
	var layout: Dictionary = {"experiment_size":[viewport.size.x, viewport.size.y], "panels":[]}
	for id: String in ["CrewBattleShips", "CrewBattleLedger"]:
		var panel: Control = lab._demo.find_child(id, true, false)
		if not check(is_instance_valid(panel), "generated-art information panel exists"): return false
		var rect := panel.get_global_rect()
		layout.panels.append({"id":id, "rect":[rect.position.x, rect.position.y, rect.size.x, rect.size.y], "fits":bounds.encloses(rect)})
		check(bounds.encloses(rect), "full-page information panel fits viewport: " + id)
	checks.append({"name":"page_layout", "page":name, "layout":layout})
	return save_image(root.get_texture().get_image(), name + ".png", "page", snap)

func save_image(im: Image, name: String, kind: String, snap: Dictionary) -> bool:
	if not check(im != null and not im.is_empty(), "GPU framebuffer exists"): return false
	im.convert(Image.FORMAT_RGBA8)
	var path := output + "/" + name
	if not check(not FileAccess.file_exists(path), "never overwrite capture"): return false
	if not check(im.save_png(path) == OK, "PNG write"): return false
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(im.get_data())
	captures.append({"file":name, "kind":kind, "viewport":[im.get_width(), im.get_height()], "sha256":FileAccess.get_sha256(path), "framebuffer_sha256":digest.finish().hex_encode(), "framebuffer_format":"RGBA8", "snapshot":snap.duplicate(true)})
	return true

func finish() -> void:
	var report := {"valid":failures.is_empty(), "failures":failures, "scope":"Actual menu and registered laboratory, scripted four native ticks per sampled GPU frame. Mesh visibility plus framebuffer evidence requires visual review; no 60fps, per-physics-tick capture, manual play, campaign economy, or full-game performance claim.", "engine":Engine.get_version_info(), "gpu":RenderingServer.get_video_adapter_name(), "renderer":RenderingServer.get_current_rendering_method(), "displayServer":DisplayServer.get_name(), "fixedStep":STEP, "seed":SEED, "ticksPerFrame":TICKS_PER_FRAME, "maximumSampledFrames":MAX_FRAMES, "physicsChecks":physics_checks, "visibleProjectileSamples":visible_projectile_samples, "earlyStop":early_stop, "captures":captures, "sequence":sequence, "checks":checks, "actions":actions, "audioMuted":AudioServer.is_bus_mute(0)}
	if own_output:
		var path := output + "/capture-result.json"
		if check(not FileAccess.file_exists(path), "fresh report path"):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report)); file.close()
			else: check(false, "report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("CREW_BATTLE_GPU captures=", captures.size(), " samples=", sequence.size(), " physics_ticks=", physics_checks, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
