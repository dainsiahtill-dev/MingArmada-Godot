extends SceneTree
## Ordinary fire practice route. Only actual UI intents and production callbacks.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0 / 60.0
const TICKS_PER_SAMPLE := 12
const MAX_SAMPLES := 90
var output := ""
var own_output := false
var main: Node
var scene: Node
var failures: Array = []
var limitations: Array = []
var captures: Array = []
var sequences: Array = []
var checks: Array = []
var commands: Array = []
var observed_events: Dictionary = {}
var observed_projectiles: Dictionary = {}
var presented_ids: Dictionary = {}
var physics_callbacks := 0
var accepted_steps := 0
var initial_tick := 0
var assignment_tick := -1
var player_heat_tick := -1
var enemy_heat_tick := -1
var paused_probe := false
var terminal: Dictionary = {}

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL FIRE SKIRMISH GPU: ", message)
	return value
func frames(count: int) -> void:
	for _i in count: await process_frame
func normal(path: String) -> String: return path.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()
func inside(path: String, parent: String) -> bool: return not parent.is_empty() and normal(path).begins_with(normal(parent) + "/")
func digest(bytes: PackedByteArray) -> String:
	var h := HashingContext.new(); h.start(HashingContext.HASH_SHA256); h.update(bytes); return h.finish().hex_encode()
func state_digest(value: Dictionary) -> String: return digest(JSON.stringify(value, "", false, true).to_utf8_buffer())
func find_ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships", []):
		if ship.id == id: return ship
	return {}
func button(id: String) -> Button: return scene.interface.find_child(id, true, false) as Button

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output = arg.trim_prefix("--output=")
		else: check(false, "unknown or duplicate argument")
	var expected := OS.get_environment("FIRE_SKIRMISH_CAPTURE_OUTPUT")
	var profile := OS.get_environment("FIRE_SKIRMISH_PROFILE_ROOT")
	var original := OS.get_environment("FIRE_SKIRMISH_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/fire-skirmish/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output)) == normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected), "fresh confined output")
	check(not original.is_empty() and inside(app, profile) and inside(local, profile) and normal(app) != normal(local) and inside(ProjectSettings.globalize_path("user://"), app) and not inside(profile, original) and not inside(original, profile) and normal(profile) != normal(original), "isolated actual userdata")
	check(DisplayServer.get_name() != "headless", "non-headless graphics required")
	if DisplayServer.get_name() != "headless":
		var gpu := RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu, "hardware graphics required")
	if not failures.is_empty(): print("FIRE_SKIRMISH_GPU_GUARD_REJECTED failures=", failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected) == OK, "create fresh output"): quit(2); return
	own_output = true; seed(1661)
	await resize(Vector2i(1600, 900))
	main = Main.instantiate(); root.add_child(main); await frames(4)
	await capture("menu-before.png", "menu", -1, {})
	var entry: Button = main.menu.find_child("fire", true, false)
	if not check(is_instance_valid(entry) and entry.is_visible_in_tree() and not entry.disabled, "ordinary fire main-menu button enabled"): await finish(); return
	entry.pressed.emit()
	for _i in 300:
		await process_frame
		if is_instance_valid(main.current_scene): break
	scene = main.current_scene
	if not check(is_instance_valid(scene) and scene.startup_receipt.get("ok", false) and scene.get_script().resource_path == "res://game/scenes/naval_practice/naval_practice.gd", "fire route opens actual NavalPractice"): await finish(); return
	scene.set_process(false); scene.set_physics_process(false)
	# Establish the real window focus once; never bypass production blur pausing.
	root.grab_focus(); await frames(2)
	if not check(root.has_focus(), "capture window owns initial OS focus"): await finish(); return
	observe_queues(); scene._present(0.0)
	scene.interface.command_requested.connect(_record_intent)
	var initial: Dictionary = full_state()
	initial_tick = int(initial.packet.naval.tick)
	var player := find_ship(initial.packet.naval, "player")
	var enemy := find_ship(initial.packet.naval, "enemy-1")
	if not check(initial.packet.runtime.mode == "fire" and not player.is_empty() and not enemy.is_empty() and player.kind == "fuchuan" and enemy.kind == "fuchuan" and player.fireControl.supplies == 24 and enemy.fireControl.supplies == 24 and player.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":2}, "real fire fixture owns two live equipped Fuchuan"): await finish(); return
	checks.append({"name":"entry","ordinary_button":true,"mode":"fire","scene":scene.get_script().resource_path,"startup":scene.startup_receipt.duplicate(true),"initial_tick":initial_tick,"initial":compact(initial)})
	if initial.packet.runtime.paused:
		if not await press("pause"): await finish(); return
		if not check(not scene.runtime.snapshot().runtime.paused, "actual continue button clears entry focus/player pause"): await finish(); return
	if not await press("toggle_fire"): await finish(); return
	var target: OptionButton = scene.interface.find_child("FireTarget", true, false)
	if not check(is_instance_valid(target) and target.item_count > 0, "actual FireTarget lists a live enemy"): await finish(); return
	var target_index := -1
	for i in target.item_count:
		if str(target.get_item_metadata(i)) == "enemy-1": target_index = i
	if target_index < 0 and target.item_count == 1: target_index = 0
	if not check(target_index >= 0, "actual target item identifies sole hostile"): await finish(); return
	target.select(target_index); target.item_selected.emit(target_index)
	if not await press("fire_ball"): await finish(); return
	if not await sample_frame(0): await finish(); return
	for sample in range(1, MAX_SAMPLES + 1):
		for _i in TICKS_PER_SAMPLE:
			if "blur" in scene.runtime.snapshot().runtime.pauseReasons:
				limitations.append("External root focus loss paused the production runtime; this capture is incomplete and was not auto-resumed.")
				check(false, "external window focus loss interrupted combat capture"); await finish(); return
			var before: Dictionary = scene.runtime.snapshot().naval
			scene._physics_process(STEP); physics_callbacks += 1
			var native: Dictionary = scene.runtime.snapshot().naval
			accepted_steps += maxi(0, int(native.tick) - int(before.tick))
			observe_queues()
			for shot: Dictionary in native.get("projectiles", []):
				if not observed_projectiles.has(shot.id): observed_projectiles[shot.id] = {"first_tick":native.tick,"first_time":native.time,"projectile":shot.duplicate(true)}
			player = find_ship(native, "player"); enemy = find_ship(native, "enemy-1")
			if float(enemy.get("fireControl", {}).get("heat",0.0)) > 0.0 and enemy_heat_tick < 0: enemy_heat_tick = int(native.tick)
			if float(player.get("fireControl", {}).get("heat",0.0)) > 0.0 and player_heat_tick < 0: player_heat_tick = int(native.tick)
			if assignment_tick < 0 and player_heat_tick >= 0 and native.status not in ["victory","defeat","surrendered"]:
				observe_queues(); scene._present(0.0)
				if not await press("fight_fire"): await finish(); return
				assignment_tick = int(native.tick)
		if not await sample_frame(sample): await finish(); return
		var now: Dictionary = full_state()
		if not paused_probe and assignment_tick >= 0 and now.packet.naval.tick >= assignment_tick + 132 and now.packet.naval.status not in ["victory","defeat","surrendered"]:
			if not await pause_probe(sample): await finish(); return
			paused_probe = true
		if now.packet.naval.status in ["victory","defeat","surrendered"]:
			terminal = {"status":now.packet.naval.status,"tick":now.packet.naval.tick,"time":now.packet.naval.time,"sample":sample}
			limitations.append("Native terminal result ended this scripted combat sequence before its maximum eighteen-second callback budget.")
			break
		if sample % 15 == 0: print("FIRE_SKIRMISH_GPU_PROGRESS sample=", sample, " native=", now.packet.naval.time, " player_heat_tick=", player_heat_tick, " enemy_heat_tick=", enemy_heat_tick)
	var final_combat: Dictionary = full_state()
	check(enemy_heat_tick >= 0 and player_heat_tick >= 0 and assignment_tick >= player_heat_tick, "real launch and hostile counterfire cause both canonical heat states before player team assignment")
	check(paused_probe, "active combat receives an exact eight-rendered-frame pause probe")
	checks.append({"name":"combat","player_heat_tick":player_heat_tick,"enemy_heat_tick":enemy_heat_tick,"assignment_tick":assignment_tick,"final":compact(final_combat),"terminal":terminal.duplicate(true)})
	if not await open_menu(): await finish(); return
	if not await press("restart"): await finish(); return
	await frames(3)
	var restarted: Dictionary = full_state()
	player = find_ship(restarted.packet.naval, "player")
	check(restarted.packet.naval.tick == 0 and restarted.packet.naval.time == 0.0 and player.fireControl.heat == 0.0 and player.fireControl.supplies == 24 and player.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":2}, "actual restart restores zero tick heat preparation and payload stock")
	checks.append({"name":"restart","before":compact(final_combat),"after":compact(restarted),"ok":failures.is_empty()})
	await capture("restarted.png", "restart", -1, restarted)
	for size: Vector2i in [Vector2i(800,600), Vector2i(320,480)]:
		if not await narrow_probe(size): await finish(); return
	await resize(Vector2i(1600,900)); scene._present(0.0)
	if not await actual_input_probe(): await finish(); return
	var scene_ref: WeakRef = weakref(scene)
	var sea_ref: WeakRef = weakref(scene.sea)
	var interface_ref: WeakRef = weakref(scene.interface)
	if not await open_menu(): await finish(); return
	if not await press("main_menu"): await finish(); return
	scene = null; await frames(4)
	var released: bool = scene_ref.get_ref() == null and sea_ref.get_ref() == null and interface_ref.get_ref() == null
	check(released, "actual return button releases NavalPractice Sea and UI")
	checks.append({"name":"leave","released":released})
	await capture("menu-returned.png", "menu", -1, {})
	await finish()

func _record_intent(intent: Dictionary) -> void:
	commands.append({"intent":intent.duplicate(true),"tick":scene.runtime.snapshot().naval.tick,"time":scene.runtime.snapshot().naval.time,"route":"actual UI command_requested after button.pressed"})
func observe_queues() -> void:
	if not is_instance_valid(scene): return
	for event: Dictionary in scene.runtime.simulation.get("_events"):
		if not observed_events.has(event.id): observed_events[event.id] = event.duplicate(true)
	for id: Variant in scene.sea.effects.get("_seen"): presented_ids[str(id)] = true

func resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size); root.content_scale_size = size; root.size = size
	await frames(4)
func reveal(control: Control) -> void:
	var parent := control.get_parent()
	while parent != null:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames(2)
func visible_rect(control: Control) -> Rect2:
	var rect := control.get_global_rect().intersection(Rect2(Vector2.ZERO, root.get_visible_rect().size))
	var parent := control.get_parent()
	while parent != null:
		if parent is Control and parent.clip_contents: rect = rect.intersection(parent.get_global_rect())
		parent = parent.get_parent()
	return rect
func press(id: String) -> bool:
	var control := button(id)
	if not check(is_instance_valid(control), "actual UI button exists: " + id): return false
	await reveal(control)
	if not check(control.is_visible_in_tree() and not control.disabled and visible_rect(control).has_area(), "actual UI button visible enabled and reachable: " + id): return false
	control.pressed.emit()
	return true
func open_menu() -> bool:
	if scene.interface.is_menu_open() or scene.runtime.snapshot().naval.status in ["victory","defeat","surrendered"]: return true
	var event := InputEventKey.new(); event.physical_keycode = KEY_ESCAPE; event.pressed = true
	root.push_input(event, true); await frames(2)
	return check(scene.interface.is_menu_open(), "actual Escape input opens navigation menu")

func pause_probe(sample: int) -> bool:
	if not await press("pause"): return false
	observe_queues(); scene._present(0.0)
	var before: Dictionary = full_state()
	if not check(before.packet.runtime.paused, "actual pause button pauses the runtime"): return false
	if not await capture("active-pause-before.png", "pause", sample, before): return false
	await frames(8); await RenderingServer.frame_post_draw
	var after: Dictionary = full_state()
	var unchanged := before == after
	checks.append({"name":"pause","frames":8,"unchanged":unchanged,"tick":before.packet.naval.tick,"before_sha256":state_digest(before),"after_sha256":state_digest(after)})
	if not check(unchanged, "paused full production snapshot and effects stay exact through eight rendered frames"): return false
	if not await capture("active-pause-after.png", "pause", sample, after): return false
	return await press("pause")

func narrow_probe(size: Vector2i) -> bool:
	await resize(size); scene._present(0.0)
	var target: OptionButton = scene.interface.find_child("FireTarget", true, false)
	if not target.is_visible_in_tree():
		if not await press("toggle_fire"): return false
	await frames(2)
	var controls: Array = []
	var requested: Array[Control] = [target]
	for id: String in ["fire_ball","thorn_ball","fight_fire"]:
		var control := button(id)
		if not check(is_instance_valid(control), "narrow fire control exists: " + id): return false
		requested.append(control)
	for control: Control in requested:
		await reveal(control)
		var rect := visible_rect(control)
		var point := rect.get_center()
		var motion := InputEventMouseMotion.new(); motion.position = point; motion.global_position = point
		root.push_input(motion, true); await frames(1)
		var hovered: Control = root.gui_get_hovered_control()
		var hit := hovered == control or (is_instance_valid(hovered) and control.is_ancestor_of(hovered))
		var enabled: bool = not control.disabled if control is BaseButton else true
		var fits := rect.has_area() and rect.size.x >= 16.0 and rect.size.y >= 16.0
		var expected_enabled:bool=control.name!="fight_fire"
		controls.append({"id":str(control.name),"enabled":enabled,"expected_enabled":expected_enabled,"visible":control.is_visible_in_tree(),"visible_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"hover_hit":hit,"hovered":str(hovered.name) if hovered != null else "","fits":fits})
		check(enabled==expected_enabled and control.is_visible_in_tree() and fits and hit, "%dx%d real fire control has correct availability and pointer hover without occlusion: %s" % [size.x,size.y,control.name])
		if not await capture("narrow-%dx%d-%s.png" % [size.x,size.y,str(control.name).to_snake_case().replace("_","-")], "layout", -1, full_state()): return false
	checks.append({"name":"narrow_layout","viewport":[size.x,size.y],"controls":controls,"activation_scope":"real pointer hover plus earlier actual button signal commands; hover does not claim a native mouse click"})
	return failures.is_empty()

func push_probe_key(viewport: Viewport, key: int, down: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key; event.physical_keycode = key; event.pressed = down
	viewport.push_input(event, true)

func push_probe_button(point: Vector2, index: int, down: bool, mask: int = 0) -> void:
	var event := InputEventMouseButton.new()
	event.position = point; event.global_position = point
	event.button_index = index; event.pressed = down; event.button_mask = mask
	root.push_input(event, true)

func popup_input_diagnostics(popup: PopupMenu) -> Dictionary:
	var state: Dictionary = scene.runtime.snapshot().runtime
	var focus: Control = root.gui_get_focus_owner()
	return {"popup_embedded":popup.is_embedded(),"popup_has_focus":popup.has_focus(),"root_has_focus":root.has_focus(),"popup_visible":popup.visible,"runtime_paused":state.paused,"pause_reasons":state.pauseReasons.duplicate(),"held_keys":scene.runtime.simulation.get("_held").keys().duplicate(),"root_gui_focus":str(focus.name) if focus != null else "none"}

func record_popup_input_diagnostics(phase: String, popup: PopupMenu) -> Dictionary:
	var result := popup_input_diagnostics(popup)
	checks.append({"name":"popup_input_diagnostics","phase":phase,"state":result.duplicate(true)})
	print("FIRE_SKIRMISH_GPU_INPUT_DIAGNOSTICS phase=",phase," ",JSON.stringify(result,"",false,true))
	return result

func actual_input_probe() -> bool:
	# This probe deliberately uses native input dispatch. No pressed/select or
	# item_selected emission stands in for opening/choosing the actual popup.
	var target: OptionButton = scene.interface.find_child("FireTarget", true, false)
	if not check(is_instance_valid(target) and target.item_count == 1 and target.is_visible_in_tree() and not target.disabled, "actual input probe has one enabled visible target"): return false
	await reveal(target)
	var before: Dictionary = scene.runtime.snapshot().naval
	var callback_before := physics_callbacks
	var popup: PopupMenu = target.get_popup()
	var window_before := record_popup_input_diagnostics("before", popup)
	if not check(not window_before.runtime_paused, "actual target probe begins with an unpaused production runtime"): return false
	# Establish a real held forward input before the Window takes keyboard
	# ownership. Production must release it on popup opening, before its key-up
	# can be consumed by that Window; the capture never edits the held map.
	push_probe_key(root, KEY_W, true); await frames(1)
	var held_before_open: Array = scene.runtime.simulation.get("_held").keys().duplicate()
	if not check(held_before_open.has("KeyW"), "real W down is held before opening the target popup"): return false
	record_popup_input_diagnostics("held-before-open", popup)
	var selected_ids: Array[int] = []
	var on_popup_choice: Callable = func(id: int) -> void: selected_ids.append(id)
	popup.id_pressed.connect(on_popup_choice)
	var point := visible_rect(target).get_center()
	var enter_target := InputEventMouseMotion.new(); enter_target.position = point; enter_target.global_position = point
	root.push_input(enter_target, true)
	push_probe_button(point, MOUSE_BUTTON_LEFT, true, MOUSE_BUTTON_MASK_LEFT)
	push_probe_button(point, MOUSE_BUTTON_LEFT, false)
	await frames(2)
	if not check(popup.visible, "real target mouse click opens its PopupMenu"):
		popup.id_pressed.disconnect(on_popup_choice)
		return false
	var window_open := record_popup_input_diagnostics("open", popup)
	var held_after_open: Array = scene.runtime.simulation.get("_held").keys().duplicate()
	check(not window_open.runtime_paused, "owned target popup does not add a production blur pause")
	check(held_after_open.is_empty(), "opening owned target popup releases all real held helm inputs before key-up")
	push_probe_key(root, KEY_W, false); await frames(1)
	var held_after_popup_keyup: Array = scene.runtime.simulation.get("_held").keys().duplicate()
	var window_popup_keyup := record_popup_input_diagnostics("popup-keyup", popup)
	check(popup.visible and held_after_popup_keyup.is_empty() and not window_popup_keyup.runtime_paused, "real W up while popup owns input leaves no held helm key and does not pause")
	if not await capture("target-popup-open.png", "input", -1, full_state()): return false
	# The Window-owned framebuffer proves the actual popup even when this
	# platform presents it as a separate native window outside the root image.
	if not await capture("target-popup-surface.png", "input-popup", -1, full_state(), popup): return false
	# Root Viewport forwards these to its embedded Window, preserving the
	# Window::_input_from_window route where PopupMenu handles navigation.
	# Pushing directly into PopupMenu's Viewport skips that native window layer.
	push_probe_key(root, KEY_DOWN, true); push_probe_key(root, KEY_DOWN, false)
	push_probe_key(root, KEY_ENTER, true); push_probe_key(root, KEY_ENTER, false)
	for _i in 30:
		await process_frame
		if not popup.visible: break
	await frames(2)
	popup.id_pressed.disconnect(on_popup_choice)
	var window_closed := record_popup_input_diagnostics("after", popup)
	var popup_closed := not popup.visible
	var focus: Control = root.gui_get_focus_owner()
	var focus_released := focus != target
	var sole_selected := selected_ids.size() == 1 and selected_ids[0] == popup.get_item_id(0) and target.selected == 0 and str(target.get_item_metadata(0)) == "enemy-1"
	check(popup_closed and sole_selected, "real popup keyboard dispatch chooses its sole enemy item and closes")
	check(focus_released, "actual target selection returns keyboard focus to the ship")
	check(not window_closed.runtime_paused, "actual target selection leaves production runtime unpaused without a resume workaround")
	push_probe_key(root, KEY_W, true); await frames(1)
	var held_down: Array = scene.runtime.simulation.get("_held").keys().duplicate()
	var forward_received := held_down.has("KeyW")
	push_probe_key(root, KEY_W, false); await frames(1)
	var held_up: Array = scene.runtime.simulation.get("_held").keys().duplicate()
	var forward_released := not held_up.has("KeyW")
	check(forward_received and forward_released, "real W down/up enters and leaves production helm held state")
	var world_point := Vector2(600,250)
	var move_to_world := InputEventMouseMotion.new(); move_to_world.position = world_point; move_to_world.global_position = world_point
	root.push_input(move_to_world, true); await frames(1)
	var dragging_before: Dictionary = scene.sea.camera_status()
	push_probe_button(world_point, MOUSE_BUTTON_RIGHT, true, MOUSE_BUTTON_MASK_RIGHT)
	await frames(1)
	var dragging_started: bool = scene.sea.camera_status().dragging
	var movement := Vector2(35,-12)
	var orbit := InputEventMouseMotion.new(); orbit.position = world_point + movement; orbit.global_position = orbit.position; orbit.relative = movement; orbit.button_mask = MOUSE_BUTTON_MASK_RIGHT
	root.push_input(orbit, true); await frames(1)
	var dragging_during: Dictionary = scene.sea.camera_status()
	push_probe_button(world_point + movement, MOUSE_BUTTON_RIGHT, false)
	await frames(1)
	var dragging_after: Dictionary = scene.sea.camera_status()
	var dragging_released: bool = not dragging_after.dragging
	check(dragging_started and dragging_released, "real world right-button down/motion/up starts and releases camera drag")
	scene._present(0.0)
	var after: Dictionary = scene.runtime.snapshot().naval
	var same_clock: bool = before.tick == after.tick and before.time == after.time and physics_callbacks == callback_before
	check(same_clock, "actual UI keyboard and camera probe advances no native time or production physics callback")
	checks.append({"name":"actual_input_probe","route":"real root W down held before pointer opens target PopupMenu; root W up while popup owns input; root Down/Enter forwards through embedded Window; subsequent root W and world right drag dispatch normally","popup_opened":true,"popup_closed":popup_closed,"popup_item_activations":selected_ids.duplicate(),"sole_item_id":popup.get_item_id(0),"selected_target_id":str(target.get_item_metadata(target.selected)),"sole_item_selected":sole_selected,"focus_released":focus_released,"focus_after_selection":str(focus.name) if focus != null else "none","popup_window_before":window_before,"popup_window_open":window_open,"popup_window_keyup":window_popup_keyup,"popup_window_after":window_closed,"unpaused_before_popup":not window_before.runtime_paused,"unpaused_during_popup":not window_open.runtime_paused,"unpaused_after_popup":not window_closed.runtime_paused,"held_before_open":held_before_open,"held_after_open":held_after_open,"held_after_popup_keyup":held_after_popup_keyup,"w_held_before_popup":held_before_open.has("KeyW"),"held_cleared_on_popup":held_after_open.is_empty(),"held_down":held_down,"held_up":held_up,"w_received":forward_received,"w_released":forward_released,"world_point":[world_point.x,world_point.y],"motion":[movement.x,movement.y],"dragging_started":dragging_started,"dragging_released":dragging_released,"camera_before":dragging_before,"camera_during":dragging_during,"camera_after":dragging_after,"before_clock":{"tick":before.tick,"time":before.time},"after_clock":{"tick":after.tick,"time":after.time},"physics_callbacks_before":callback_before,"physics_callbacks_after":physics_callbacks,"native_time_unchanged":same_clock})
	if not await capture("input-restored.png", "input", -1, full_state()): return false
	return failures.is_empty()

func full_state() -> Dictionary:
	var camera: Camera3D = scene.sea.camera
	var crew: Dictionary = {}
	for id: String in scene.sea.sailors: crew[id] = scene.sea.sailors[id].diagnostics()
	return {"packet":scene.runtime.snapshot(),"atmosphere":scene.sea.effects.atmosphere_diagnostics(),"effects":scene.sea.effects.diagnostics(),"tail":scene._terminal_presentation.diagnostics(),"crew":crew,"camera":{"position":[camera.global_position.x,camera.global_position.y,camera.global_position.z],"rotation":[camera.global_rotation.x,camera.global_rotation.y,camera.global_rotation.z],"status":scene.sea.camera_status()},"audio":scene.services.audio.diagnostics()}
func compact(state: Dictionary) -> Dictionary:
	if state.is_empty(): return {}
	var result := state.duplicate(true)
	var native: Dictionary = result.packet.naval
	var ships: Array = []
	for ship: Dictionary in native.ships:
		ships.append({"id":ship.id,"kind":ship.kind,"team":ship.team,"hull":ship.hull,"maxHull":ship.maxHull,"sail":ship.sail,"maxSail":ship.maxSail,"crew":ship.crew,"maxCrew":ship.maxCrew,"fireControl":ship.get("fireControl",{}).duplicate(true),"fireLauncher":ship.get("fireLauncher",{}).duplicate(true),"visual":ship.visual.duplicate(true)})
	result.packet.naval = {"tick":native.tick,"time":native.time,"battleId":native.battleId,"status":native.status,"playerId":native.playerId,"ships":ships,"projectiles":native.projectiles.duplicate(true)}
	result.atmosphere.erase("particles")
	result.effects.erase("source_effects"); result.effects.erase("sourcePrewarm")
	return result
func sample_frame(index: int) -> bool:
	observe_queues(); scene._present(0.0)
	var state := full_state()
	var file := "fire-%03d.png" % index
	sequences.append({"file":file,"sample":index,"physics_callbacks":physics_callbacks,"accepted_steps":accepted_steps,"tick":state.packet.naval.tick,"time":state.packet.naval.time,"visual_time":state.atmosphere.time,"native_sha256":state_digest(state.packet.naval),"full_state_sha256":state_digest(state)})
	return await capture(file, "combat", index, state)
func capture(file: String, kind: String, sample: int, state: Dictionary, source_viewport: Viewport = null) -> bool:
	await process_frame; await RenderingServer.frame_post_draw
	var source: Viewport = source_viewport if source_viewport != null else root
	var image := source.get_texture().get_image()
	if not check(image != null and not image.is_empty(), "hardware framebuffer exists: " + file): return false
	image.convert(Image.FORMAT_RGBA8)
	var path := output + "/" + file
	if not check(not FileAccess.file_exists(path) and image.save_png(path) == OK, "fresh PNG write: " + file): return false
	captures.append({"file":file,"kind":kind,"sample":sample,"tick":state.get("packet",{}).get("naval",{}).get("tick",0),"time":state.get("packet",{}).get("naval",{}).get("time",0.0),"viewport":[image.get_width(),image.get_height()],"viewport_source":"PopupMenu" if source_viewport != null else "root","sha256":FileAccess.get_sha256(path),"framebuffer_sha256":digest(image.get_data()),"framebuffer_format":"RGBA8","full_state_sha256":state_digest(state),"snapshot":compact(state)})
	return true
func finish() -> void:
	var missing_ids: Array = []
	for id: String in presented_ids:
		if not observed_events.has(id): missing_ids.append(id)
	limitations.append("Observed event bodies cover queues still readable after actual scene callbacks. Immediate production presentation can already have drained events; presented IDs missing bodies are listed, without reconstructing or fabricating events.")
	var report := {"valid":failures.is_empty(),"failures":failures,"limitations":limitations,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"fixedStep":STEP,"ticksPerSample":TICKS_PER_SAMPLE,"nominalSamplesPerAcceptedSecond":5,"maximumPhysicsCallbackSeconds":18,"physicsCallbacks":physics_callbacks,"acceptedSteps":accepted_steps,"initialTick":initial_tick,"terminal":terminal,"commands":commands,"observed_events":observed_events.values(),"observed_projectiles":observed_projectiles.values(),"presented_event_ids_without_observed_body":missing_ids,"sequences":sequences,"captures":captures,"checks":checks,"scope":"Scripted actual Main fire route and NavalPractice callbacks. Actual UI button signals launch payload and assign crew after counterfire heat. Native trajectory, collision and hostile AI remain authoritative. Five GPU samples per accepted callback-second; no fabricated event, modified health/position, manual mouse-play, real-time FPS, campaign or whole-game acceptance claim."}
	if own_output:
		var path := output + "/capture-result.json"
		if check(not FileAccess.file_exists(path), "fresh report"):
			var file := FileAccess.open(path, FileAccess.WRITE)
			if file: file.store_string(JSON.stringify(report,"",false,true)); file.close()
			else: check(false,"report write")
	if is_instance_valid(main): main.free()
	await frames(2)
	print("FIRE_SKIRMISH_GPU captures=",captures.size()," samples=",sequences.size()," callbacks=",physics_callbacks," accepted_steps=",accepted_steps," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
