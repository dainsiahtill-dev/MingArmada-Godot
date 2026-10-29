extends SceneTree
## UI-only native GPU witnesses. No performance, continuous sea or voyage claim.
## Invoke with child-only APPDATA/LOCALAPPDATA under Temp/parchment-ui-profiles.
const EVIDENCE_ROOT := "res://docs/design/2026-10-27-painted-ui/evidence/"
const GROUPS := ["menu", "atlas", "mingqi", "legacy", "naval", "catalog", "practice", "auxiliary"]
const DIMENSIONS := [Vector2i(1600, 900), Vector2i(1280, 720)]
var output := ""
var group := ""
var main: Node
var direct_scene: Node
var active_scene: Node
var storage: RefCounted
var assertions := 0
var failures: Array[String] = []
var captures: Array[Dictionary] = []
var actions: Array[Dictionary] = []
var source_hashes: Dictionary = {}
var original_slots: Dictionary = {}
var profile_slots: Dictionary = {}
var original_directory := ""
var slot_prefix := ""
var output_owned := false
var finishing := false
var route := "actual MainScene menu and native viewport input"

func _initialize() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): guard_tests.call_deferred()
	else: run.call_deferred()

func check(condition: bool, detail: String) -> bool:
	assertions += 1
	if not condition:
		failures.append(detail)
		printerr("PARCHMENT_UI_FAIL ", detail)
	return condition

func valid_output(path: String) -> bool:
	if not path.begins_with(EVIDENCE_ROOT): return false
	var leaf := path.trim_prefix(EVIDENCE_ROOT)
	if leaf.is_empty() or leaf.length() > 100: return false
	for character: String in leaf:
		if not character in "abcdefghijklmnopqrstuvwxyz0123456789-": return false
	if leaf in ["con", "prn", "aux", "nul", "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9", "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"]: return false
	var cursor := ProjectSettings.globalize_path("res://").trim_suffix("/")
	for part: String in path.trim_prefix("res://").split("/"):
		var directory := DirAccess.open(cursor)
		if directory and directory.is_link(part): return false
		cursor = cursor.path_join(part)
	return not FileAccess.file_exists(path) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path))

func slot_hashes(directory: String) -> Dictionary:
	var result: Dictionary = {}
	for relative: String in ["saves/mingqi-v2.json", "saves/legacy-v1.json", "settings.json"]:
		for suffix: String in ["", ".backup", ".rollback", ".staged"]:
			var path := directory.path_join(relative + suffix)
			result[relative + suffix] = {"exists": FileAccess.file_exists(path), "sha256": FileAccess.get_sha256(path) if FileAccess.file_exists(path) else ""}
	return result

func add_sources(directory: String, result: Dictionary) -> void:
	var access := DirAccess.open(directory)
	if not access: return
	for filename: String in access.get_files():
		if filename.get_extension() in ["gd", "tscn", "json", "png"]:
			var path := directory.path_join(filename)
			result[path] = FileAccess.get_sha256(path)
	for child: String in access.get_directories(): add_sources(directory.path_join(child), result)

func sources() -> Dictionary:
	var result: Dictionary = {}
	# Include state owners and all painted derivatives: a UI screenshot is stale
	# when its story, settings or skin dependency changes, not only its Controls.
	var directories: Array[String] = ["res://game/ui/shared", "res://game/ui/menu", "res://game/ui/settings", "res://game/scenes/main", "res://game/runtime", "res://game/domain", "res://game/persistence", "res://assets/ui/ming_maritime/painted"]
	var groups: Array = GROUPS if group == "all" else [group]
	for selected: String in groups:
		match selected:
			"atlas": directories.append("res://game/ui/charts")
			"mingqi": directories.append_array(["res://game/ui/mingqi", "res://game/ui/charts", "res://game/scenes/mingqi", "res://game/scenes/common"])
			"legacy": directories.append_array(["res://game/ui/legacy", "res://game/ui/charts", "res://game/scenes/legacy", "res://game/scenes/common"])
			"naval": directories.append_array(["res://game/ui/charts", "res://game/scenes/naval_practice", "res://game/scenes/common"])
			"catalog": directories.append_array(["res://game/ui/legacy", "res://game/scenes/ship_book", "res://game/research"])
			"practice": directories.append_array(["res://game/ui/legacy", "res://game/ui/encounters", "res://game/scenes/practice"])
			"auxiliary": directories.append_array(["res://game/ui/charts", "res://game/scenes/visual_qa", "res://game/scenes/fidelity_island", "res://game/scenes/reference_island_water", "res://game/scenes/natural_island", "res://game/scenes/sailing_trial", "res://game/scenes/common"])
	for directory: String in directories: add_sources(directory, result)
	for path: String in ["res://game/ui/naval_practice.gd", "res://game/ui/sailing_hud.gd"]:
		if group in ["all", "naval", "auxiliary"]: result[path] = FileAccess.get_sha256(path)
	if group in ["all", "auxiliary"]:
		result["res://game/research/demos/voyage_flow_experiment.gd"] = FileAccess.get_sha256("res://game/research/demos/voyage_flow_experiment.gd")
	for path: String in ["res://tools/capture-painted-ui.gd", "res://project.godot", "res://assets/research/catalog.json", "res://game/runtime/game_router.gd", "res://ming-armada-ui-background-parchment.png", "res://ming-armada-ui-background-ledger.png", "res://ming-armada-ui-background-chart.png", "res://ming-armada-ui-panel.png", "res://ming-armada-ui-button.png", "res://ming-armada-ui-button-primary.png"]:
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	for filename: String in ["menu-painting.png", "panel-paper.png", "primary-button.png", "secondary-button.png", "chart-paper.png"]:
		var path := "res://assets/ui/ming_maritime/" + filename
		result[path] = FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	for filename: String in ["command-panel.png","folio-panel.png","header-cartouche.png","button-normal.png","button-selected.png","compass-rose.png","portrait-xufu.png"]:
		for prefix: String in ["res://assets/ui/ming_maritime/painted/","res://assets/ui/ming_maritime/painted/runtime/"]:
			var path:=prefix+filename
			if FileAccess.file_exists(path): result[path]=FileAccess.get_sha256(path)
	for filename: String in ["button-normal-small.png","button-selected-small.png"]:
		var path:="res://assets/ui/ming_maritime/painted/runtime/"+filename
		result[path]=FileAccess.get_sha256(path)
	for filename: String in ["command-panel.png","folio-panel.png","button-normal.png","button-selected.png"]:
		for prefix: String in ["res://assets/ui/ming_maritime/painted/quiet/","res://assets/ui/ming_maritime/painted/quiet/runtime/"]:
			var path:=prefix+filename
			result[path]=FileAccess.get_sha256(path)
	for filename: String in ["command-panel.png","folio-panel.png"]:
		for prefix: String in ["res://assets/ui/ming_maritime/painted/quiet/framed/","res://assets/ui/ming_maritime/painted/quiet/framed/runtime/"]:
			var path:=prefix+filename
			if FileAccess.file_exists(path): result[path]=FileAccess.get_sha256(path)
	if group in ["all","atlas"]:
		result["res://assets/ui/ming_maritime/atlas-vignette.png"]=FileAccess.get_sha256("res://assets/ui/ming_maritime/atlas-vignette.png")
		for filename: String in ["east_asia_land.json","atlas_places.json"]:
			var path := "res://assets/data/cartography/"+filename
			result[path]=FileAccess.get_sha256(path)
	return result

func frames(count: int = 6) -> void:
	for index in count: await process_frame

func present_active() -> void:
	# Automatic scene processing is frozen, so preserve its ordinary presentation
	# pass after UI-only callbacks such as SettingsPanel.close_requested.
	if is_instance_valid(active_scene) and active_scene.has_method("_present"):
		active_scene.call("_present", 0.0)

func resize_view(dimensions: Vector2i) -> void:
	root.size = dimensions
	root.content_scale_size = dimensions
	await frames(10)
	if is_instance_valid(active_scene) and active_scene.has_method("_present"): active_scene.call("_present", 0.0)
	await frames(3)

func mouse(control: Control, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.position = control.get_global_rect().get_center()
	event.global_position = event.position
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	root.push_input(event, true)
	await process_frame

func click(control: Control) -> bool:
	if not check(is_instance_valid(control), "click target exists"): return false
	var parent: Node = control.get_parent()
	while parent:
		if parent is ScrollContainer: parent.ensure_control_visible(control)
		parent = parent.get_parent()
	await frames(4)
	if not check(control.is_visible_in_tree(), "visible click target: " + str(control.get_path())): return false
	if control is BaseButton and not check(not control.disabled, "enabled click target: " + str(control.get_path())): return false
	var point := control.get_global_rect().get_center()
	if not check(root.get_visible_rect().has_point(point), "click point within viewport: " + str(control.get_path())): return false
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	actions.append({"kind": "viewport-native-mouse", "node": str(control.get_path()), "position": [point.x, point.y]})
	await mouse(control, true)
	await mouse(control, false)
	await frames(4)
	present_active()
	await frames(2)
	return true

func press(owner: Node, id: String) -> bool:
	if not check(is_instance_valid(owner), "button owner exists: " + id): return false
	return await click(owner.find_child(id, true, false) as Control)

func wheel_inside(control: Control, ticks: int) -> void:
	var point:=control.get_global_rect().get_center()
	for index in ticks:
		var event:=InputEventMouseButton.new()
		event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.factor=1.0
		event.pressed=true;root.push_input(event,true)
		await process_frame
		event=event.duplicate();event.pressed=false;root.push_input(event,true)
		await process_frame
	actions.append({"kind":"viewport-native-mouse-wheel","node":str(control.get_path()),"ticks":ticks,"position":[point.x,point.y]})
	await frames(4)

func key(code: Key, target: Viewport = null) -> void:
	var viewport: Viewport = root if target == null else target
	for pressed: bool in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.keycode = code
		event.pressed = pressed
		viewport.push_input(event, true)
		await process_frame
	actions.append({"kind": "viewport-native-key", "key": OS.get_keycode_string(code), "viewport": str(viewport.get_path())})
	await frames(4)
	present_active()
	await frames(2)

func audit_node(node: Node, result: Dictionary) -> void:
	if node is SubViewport: return # Separate rendered worlds are not root UI geometry.
	if node is Window and node != root and not node.visible: return
	if node is Control and node.is_visible_in_tree():
		var control: Control = node
		var rect := control.get_global_rect()
		var clipped := false
		var ancestor := node.get_parent()
		var effective := rect
		while ancestor and ancestor != root:
			if ancestor is Control and ancestor.clip_contents:
				clipped = true
				effective = effective.intersection(ancestor.get_global_rect())
			ancestor = ancestor.get_parent()
		if effective.has_area() and root.get_visible_rect().intersects(effective):
			result.visibleControls += 1
			if control is BaseButton: result.visibleButtons += 1
			if control is ScrollContainer: result.scrollContainers += 1
			var row := {"node": str(control.get_path()), "type": control.get_class(), "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "mouseFilter": control.mouse_filter, "clippedByAncestor": clipped}
			if control is BaseButton or control is Label or control is LineEdit: row.text = str(control.get("text")).left(160)
			if control is BaseButton: row.disabled = control.disabled
			if control is Label or control is BaseButton:
				row.fontSize = control.get_theme_font_size("font_size")
				row.fontColor = control.get_theme_color("font_color").to_html()
				row.fontFamily = control.get_theme_font("font").get_font_name()
				row.fontShadowColor = control.get_theme_color("font_shadow_color").to_html()
				row.fontOutlineColor = control.get_theme_color("font_outline_color").to_html()
			if control is PanelContainer:
				var panel_style: StyleBox = control.get_theme_stylebox("panel")
				row.panelMargins = [panel_style.get_content_margin(SIDE_LEFT), panel_style.get_content_margin(SIDE_TOP), panel_style.get_content_margin(SIDE_RIGHT), panel_style.get_content_margin(SIDE_BOTTOM)]
			if control is PanelContainer or control is Label or control is BaseButton or control is LineEdit or control is TextEdit or control is RichTextLabel: result.controls.append(row)
			if not clipped and not root.get_visible_rect().grow(2).encloses(rect) and rect.has_area(): result.unclippedOverflow.append(row)
		if control is TextureRect and "Parchment" in str(control.name):
			check(control.mouse_filter == Control.MOUSE_FILTER_IGNORE, "paper decoration ignores mouse: " + str(control.get_path()))
			result.decorations.append({"node": str(control.get_path()), "mouseFilter": control.mouse_filter})
	for child: Node in node.get_children(): audit_node(child, result)

func capture(label: String, extra: Dictionary = {}) -> void:
	await frames(8)
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if not check(image != null and not image.is_empty(), "GPU image exists: " + label): return
	var destination := output.path_join(label + ".png")
	if not check(not FileAccess.file_exists(destination), "fresh image: " + label): return
	if not check(image.save_png(destination) == OK, "save actual GPU image: " + label): return
	var structure := {"visibleControls": 0, "visibleButtons": 0, "scrollContainers": 0, "controls": [], "decorations": [], "unclippedOverflow": []}
	audit_node(root, structure)
	check(structure.visibleControls > 0, "actual Controls rendered: " + label)
	var focus: Control = root.gui_get_focus_owner()
	var metadata := {"label": label, "engine": Engine.get_version_info(), "gpu": RenderingServer.get_video_adapter_name(), "display": DisplayServer.get_name(), "renderingMethod": RenderingServer.get_current_rendering_method(), "viewport": [image.get_width(), image.get_height()], "route": route, "focus": str(focus.get_path()) if focus else "", "embeddedSubwindows": root.gui_embed_subwindows, "structure": structure, "actionCount": actions.size(), "pngSha256": FileAccess.get_sha256(destination), "scope": "Actual native GPU UI state. Scene simulation frozen for layout inspection where supported. Not continuous sea, animation, full voyage, performance, or exported EXE acceptance."}
	if is_instance_valid(active_scene): metadata.scene = active_scene.get_script().resource_path
	metadata.merge(extra, true)
	write_json(output.path_join(label + ".json"), metadata)
	captures.append({"label": label, "png": destination, "sha256": metadata.pngSha256, "unclippedOverflow": structure.unclippedOverflow.size()})
	print("PARCHMENT_UI_CAPTURE ", label, " overflowCandidates=", structure.unclippedOverflow.size())

func write_json(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if check(file != null, "write evidence: " + path):
		if data.has("assertions"): data.assertions = assertions
		file.store_string(JSON.stringify(data, "\t"))
		file.close()

func make_main() -> bool:
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	if not check(packed != null, "actual MainScene loads"): return false
	var storage_script: GDScript = load("res://game/persistence/save_coordinator.gd")
	var settings_script: GDScript = load("res://game/persistence/user_settings.gd")
	var legacy_script: GDScript = load("res://game/runtime/legacy_runtime.gd")
	var router_script: GDScript = load("res://game/runtime/game_router.gd")
	storage = storage_script.new(slot_prefix + "-v2.json")
	var settings: RefCounted = settings_script.new(slot_prefix + "-settings.json")
	main = packed.instantiate()
	main.router = router_script.new({"dev": true, "qa": true, "mingqi_storage": storage, "legacy_storage": storage_script.new(slot_prefix + "-v1.json", legacy_script.validate_save), "settings_storage": settings})
	root.add_child(main)
	await frames(12)
	main.menu._seed.text = "1661"
	return check(main.menu.visible, "actual main menu mounted")

func enter(mode: String) -> Node:
	await resize_view(DIMENSIONS[0])
	if not check(main.current_scene == null, "previous world released before " + mode): return null
	if not check(main.menu._buttons.has(mode), "actual menu route exists: " + mode): return null
	if not await click(main.menu._buttons[mode]): return null
	for index in 480:
		if main.current_scene: break
		await process_frame
	if not check(main.current_scene != null, "actual menu enters " + mode):
		await capture("entry-failed-" + mode)
		return null
	active_scene = main.current_scene
	active_scene.set_process(false)
	active_scene.set_physics_process(false)
	var runtime: Variant = member(active_scene, "runtime")
	if is_instance_valid(runtime) and runtime.has_method("set_pause"): runtime.set_pause("blur", false)
	if active_scene.has_method("_present"): active_scene.call("_present", 0.0)
	await frames(8)
	return active_scene

func member(object: Object, property: String) -> Variant:
	if not is_instance_valid(object): return null
	for descriptor: Dictionary in object.get_property_list():
		if descriptor.name == property: return object.get(property)
	return null

func leave() -> void:
	if is_instance_valid(active_scene):
		var old: WeakRef = weakref(active_scene)
		if active_scene.has_signal("main_menu_requested"): active_scene.emit_signal("main_menu_requested")
		else: check(false, "routed scene has normal return signal")
		active_scene = null
		await frames(12)
		check(old.get_ref() == null, "returned world and UI disposed")
	if is_instance_valid(main): check(main.current_scene == null and main.menu.visible, "normal menu return")

func menu_group() -> void:
	# Public menu witnesses must not accidentally show the development inventory.
	main.router.dev = false
	main.router.qa = false
	main._refresh_menu()
	for size: Vector2i in DIMENSIONS:
		await resize_view(size)
		main.menu._scroll.scroll_vertical = 0
		await capture("menu-normal-" + str(size.x))
		main.menu._buttons.mingqi.grab_focus()
		await capture("menu-focus-" + str(size.x))
		await click(main.menu._settings)
		check(main.settings_panel.visible, "menu mouse opens real settings")
		await capture("menu-settings-" + str(size.x))
		var choice: OptionButton = main.settings_panel._controls.quality
		await click(choice)
		await capture("settings-dropdown-" + str(size.x), {"popup": "actual OptionButton PopupMenu"})
		await key(KEY_ESCAPE)
		await press(main.settings_panel, "Close")
		check(not main.settings_panel.visible, "native settings close returns menu")
	# A LineEdit owns an engine-created PopupMenu. Exercise its actual pointer
	# path so the title screen's native editing menu is not an untested theme.
	var point: Vector2=main.menu._captain.get_global_rect().get_center()
	var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point
	root.push_input(motion,true)
	for pressed: bool in [true,false]:
		var event:=InputEventMouseButton.new();event.position=point;event.global_position=point
		event.button_index=MOUSE_BUTTON_RIGHT;event.pressed=pressed;root.push_input(event,true)
		await process_frame
	actions.append({"kind":"viewport-native-right-click","node":str(main.menu._captain.get_path()),"position":[point.x,point.y]})
	await frames(4)
	check(main.menu._captain.get_menu().visible,"actual captain edit context menu opens")
	await capture("menu-edit-context-1280")
	await key(KEY_ESCAPE)
	await resize_view(Vector2i(320, 480))
	main.menu._scroll.scroll_vertical = 0
	await capture("menu-narrow-320")
	await click(main.menu._settings)
	check(main.settings_panel.visible,"narrow main menu opens actual settings")
	await capture("menu-settings-narrow-320")
	await press(main.settings_panel,"Close")
	check(not main.settings_panel.visible,"narrow settings return remains reachable")
	await resize_view(DIMENSIONS[1])
	# A malformed file exists only in the PID-isolated test slot.
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(storage.path.get_base_dir())) == OK, "create isolated fixture directory")
	var file := FileAccess.open(storage.path, FileAccess.WRITE)
	if check(file != null, "isolated malformed fixture opened"):
		file.store_string("{parchment-ui-isolated-invalid")
		file.close()
	await click(main.menu._buttons["mingqi-continue"])
	check(main.recovery.visible, "real continue presents recovery")
	await capture("recovery-1280")
	await press(main.recovery, "ImportFile")
	check(main.recovery._load.visible, "real recovery file dialog opens")
	await capture("recovery-file-dialog-1280", {"dialogMode": "Godot embedded FileDialog; no file selected"})
	main.recovery._load.hide()
	await press(main.recovery, "Back")
	check(main.menu.visible and not main.recovery.visible, "recovery back restores menu")
	main.router.dev = true
	main.router.qa = true
	main._refresh_menu()

func atlas_group() -> void:
	var atlas: Node = await enter("world-atlas")
	if not atlas: return
	for dimensions: Vector2i in [Vector2i(1600,900),Vector2i(1280,720),Vector2i(320,480)]:
		await resize_view(dimensions)
		await capture("atlas-main-entry-"+str(dimensions.x))
	await resize_view(Vector2i(1280,720))
	await press(atlas,"ZoomIn")
	await capture("atlas-main-entry-zoom")
	var selector: OptionButton = atlas.find_child("HarbourSelector",true,false)
	await click(selector)
	check(selector.get_popup().visible,"atlas harbour selector opens native popup")
	await capture("atlas-harbour-dropdown-1280",{"popup":"actual harbour PopupMenu"})
	var popup: PopupMenu = selector.get_popup()
	actions.append({"kind":"atlas-popup-state","step":"opened","visible":popup.visible,"focusedItem":popup.get_focused_item(),"selectedPort":atlas.selected_port().id})
	for index in selector.item_count:
		if popup.get_focused_item()==selector.item_count-1: break
		# PopupMenu consumes embedded window input before Viewport's GUI path.
		# Direct popup.push_input bypasses that path; dispatch through root.
		await key(KEY_DOWN)
		actions.append({"kind":"atlas-popup-state","step":"down-"+str(index),"visible":popup.visible,"focusedItem":popup.get_focused_item(),"selectedPort":atlas.selected_port().id})
	check(popup.get_focused_item()==selector.item_count-1,"native popup arrow navigation reaches final harbour")
	await key(KEY_ENTER)
	actions.append({"kind":"atlas-popup-state","step":"confirmed","visible":popup.visible,"focusedItem":popup.get_focused_item(),"selectedPort":atlas.selected_port().id})
	check(atlas.selected_port().id=="java","native atlas selector changes to Java")
	await press(atlas,"FocusHarbour")
	await capture("atlas-main-entry-java")
	await press(atlas,"ReturnFromAtlas")
	await frames(12)
	check(main.current_scene==null and main.menu.visible,"actual atlas return button restores menu")
	active_scene=null

func mingqi_group() -> void:
	var scene: Node = await enter("mingqi")
	if not scene: return
	for size: Vector2i in DIMENSIONS:
		await resize_view(size)
		for page: String in ["ship", "convoy", "port", "boarding", "tactics", "story"]:
			await press(scene.interface, "nav_" + page)
			if scene.has_method("_present"): scene.call("_present", 0.0)
			await capture("mingqi-" + page + "-" + str(size.x))
		await press(scene.interface,"sailing_manual")
		check(scene.interface.find_child("keys",true,false).visible,"native manual exposes complete instructions")
		await capture("mingqi-manual-"+str(size.x))
		await press(scene.interface,"sailing_manual")
		await press(scene.interface, "menu_open")
		await capture("mingqi-menu-" + str(size.x))
		await press(scene.interface, "import_choose_file")
		var picker: FileDialog = scene.interface.find_child("import_file_picker", true, false)
		if check(picker != null and picker.visible, "actual Mingqi FileDialog is visible"):
			check(picker.theme != null, "Mingqi FileDialog has explicit parchment theme")
			await capture("mingqi-file-dialog-" + str(size.x), {"dialogMode": "actual Godot embedded FileDialog; no file selected"})
			picker.hide()
		await press(scene.interface, "menu_close")
	await resize_view(Vector2i(320,480))
	await press(scene.interface,"nav_story")
	await capture("mingqi-narrow-320")
	await resize_view(DIMENSIONS[1])
	await press(scene.interface,"nav_story")
	var story_scroll: ScrollContainer=scene.interface.find_child("operation_scroll",true,false)
	await wheel_inside(story_scroll,5)
	check(story_scroll.scroll_vertical>0,"actual wheel scrolls story folio")
	await capture("mingqi-story-portrait-1280")
	var before: Dictionary=scene.runtime.snapshot()
	var silver_before: int=before.campaign.captain.silver
	await press(scene.interface,"story_choice_old-ledger_settle-wages")
	var after: Dictionary=scene.runtime.snapshot()
	check(after.campaign.captain.silver==silver_before-80,"actual story choice pays exactly80 silver")
	var opening: Array=after.story.scenes.filter(func(item):return item.id=="old-ledger")
	check(opening.size()==1 and opening[0].status=="completed","actual story receipt completes opening scene")
	check(scene.interface.find_child("story_portrait_old-ledger",true,false)==null,"completed dialogue releases available portrait")
	var outcome: Control=scene.interface.find_child("story_outcome_old-ledger",true,false)
	if check(outcome!=null,"story receipt has native outcome text"):
		# The confirmed story receipt rebuilt the native UI tree.
		story_scroll=scene.interface.find_child("operation_scroll",true,false)
		story_scroll.ensure_control_visible(outcome);await frames(4)
		await capture("mingqi-story-settled-1280")
	await leave()

func legacy_group() -> void:
	var scene: Node = await enter("career")
	if not scene: return
	for size: Vector2i in DIMENSIONS:
		await resize_view(size)
		scene.interface.open_panel("market")
		if scene.has_method("_present"): scene.call("_present", 0.0)
		await capture("legacy-market-" + str(size.x), {"panelOpen": "existing UI open_panel presentation API"})
		for page: String in ["chart", "save", "settings"]:
			await press(scene.interface, "tab_" + page)
			await capture("legacy-" + page + "-" + str(size.x))
	await leave()

func naval_diagnostic(scene: Node, step: String) -> void:
	var state: Dictionary = scene.runtime.snapshot().runtime
	var manual: Control = scene.interface.find_child("SailingManual",true,false)
	var surrender: Button = scene.interface.find_child("surrender",true,false)
	var hovered: Control = root.gui_get_hovered_control()
	actions.append({"kind":"naval-state","step":step,"pauseReasons":state.pauseReasons.duplicate(),"surrenderQuoted":not state.surrenderQuote.is_empty(),"chartVisible":scene.interface.chart.visible,"menuOpen":scene.interface.is_menu_open(),"settingsVisible":scene.services.settings_panel.visible,"manualVisible":manual.visible,"hudLayer":scene.interface.layer,"minimapLayer":scene.minimap.layer,"minimapVisible":scene.minimap.chart.visible,"manualRect":str(manual.get_global_rect()),"surrenderRect":str(surrender.get_global_rect()),"surrenderDisabled":surrender.disabled,"hovered":str(hovered.get_path()) if hovered else ""})

func naval_group() -> void:
	for mode: String in ["duel", "fleet", "sail"]:
		var scene: Node = await enter(mode)
		if not scene: continue
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("naval-" + mode + "-hud-" + str(size.x))
			await key(KEY_M)
			check(scene.interface.chart.visible, "actual M opens practice chart: " + mode)
			await capture("naval-" + mode + "-chart-" + str(size.x))
			await press(scene.interface, "close_chart")
			naval_diagnostic(scene,mode+"-chart-closed-"+str(size.x))
		if mode == "duel":
			await press(scene.interface, "help")
			naval_diagnostic(scene,"duel-help-open")
			check(scene.interface.find_child("SailingManual", true, false).visible, "manual exposes secondary actions")
			await press(scene.interface, "settings")
			naval_diagnostic(scene,"duel-settings-open")
			check(scene.services.settings_panel.visible, "manual opens real settings")
			await capture("naval-settings-1280")
			var panel: Control = scene.services.settings_panel
			await press(panel, "Close")
			naval_diagnostic(scene,"duel-settings-closed")
			await key(KEY_ESCAPE)
			naval_diagnostic(scene,"duel-escape")
			await capture("naval-pause-1280")
			await press(scene.interface, "resume")
			naval_diagnostic(scene,"duel-resumed")
			await press(scene.interface, "surrender")
			naval_diagnostic(scene,"duel-surrender-clicked")
			check(scene.interface._buttons.confirm_surrender.visible, "manual opens authority surrender confirmation")
			await capture("naval-surrender-1280")
			await press(scene.interface, "cancel_surrender")
		await leave()

func catalog_group() -> void:
	var book: Node = await enter("ships")
	if book:
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("shipbook-" + str(size.x))
		await leave()
	var lab: Node = await enter("laboratory")
	if not lab: return
	for size: Vector2i in DIMENSIONS:
		await resize_view(size)
		await press(lab, "ReadPaper")
		await capture("laboratory-paper-" + str(size.x))
		await press(lab, "ReadSources")
		await capture("laboratory-sources-" + str(size.x))
	await press(lab, "Topic_architecture-convergence-2026-10-21")
	await press(lab, "RunExperiment")
	check(is_instance_valid(lab._demo), "real catalog experiment builds parameter UI")
	if is_instance_valid(lab._demo):
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("laboratory-parameters-" + str(size.x), {"scopeOfExperiment": "UI controls only; no algorithm or timing result accepted"})
	await leave()

func practice_group() -> void:
	var scene: Node = await enter("practice")
	if not scene: return
	var choice: OptionButton = scene.find_child("PracticeKind", true, false)
	for kind: String in ["duel", "landBattle", "treasure", "banquet"]:
		var index: int = scene.KINDS.find(kind)
		choice.select(index)
		choice.item_selected.emit(index)
		actions.append({"kind": "actual-option-selected-signal", "node": str(choice.get_path()), "value": kind})
		await frames(5)
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("encounter-" + kind.to_lower() + "-" + str(size.x))
	await leave()

func auxiliary_group() -> void:
	for mode: String in ["qa", "fidelity-island", "water-study", "fidelity-source"]:
		var scene: Node = await enter(mode)
		if not scene: continue
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("aux-" + mode + "-" + str(size.x))
		await leave()
	# These existing production scenes are not registered menu modes.
	main.menu.hide()
	for entry: Dictionary in [{"id": "sailing-trial", "path": "res://game/scenes/sailing_trial/sailing_trial.tscn"}, {"id": "natural-island", "path": "res://game/scenes/natural_island/natural_island_prototype.gd"}, {"id": "voyage-flow", "path": "res://game/research/demos/voyage_flow_experiment.gd"}]:
		var resource: Resource = load(entry.path)
		if not check(resource is PackedScene or resource is GDScript, "direct auxiliary scene loads: " + entry.id): continue
		direct_scene = resource.instantiate() if resource is PackedScene else resource.new()
		if entry.id == "voyage-flow":
			check(direct_scene.configure({"preset": "partial", "paused": true}).ok, "existing read-only voyage fixture configures")
		root.add_child(direct_scene)
		active_scene = direct_scene
		direct_scene.set_process(false)
		direct_scene.set_physics_process(false)
		route = "direct existing scene, not registered MainScene menu route"
		for size: Vector2i in DIMENSIONS:
			await resize_view(size)
			await capture("aux-" + entry.id + "-" + str(size.x))
		if entry.id == "sailing-trial":
			await key(KEY_M)
			await capture("aux-sailing-trial-chart-1280")
		elif entry.id == "voyage-flow":
			await resize_view(Vector2i(360, 720))
			await capture("aux-voyage-flow-narrow-360", {"fixture": "existing declared read-only fabricated presentation state; no actual voyage"})
			await resize_view(Vector2i(960, 720))
			await capture("aux-voyage-flow-restored-960", {"fixture": "same existing presentation fixture after viewport restoration"})
		direct_scene.queue_free()
		direct_scene = null
		active_scene = null
		await frames(12)
	main.menu.show()
	route = "actual MainScene menu and native viewport input"

func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output=") and output.is_empty(): output = argument.trim_prefix("--output=")
		elif argument.begins_with("--group=") and group.is_empty(): group = argument.trim_prefix("--group=")
		else: check(false, "unknown or duplicate capture argument")
	check(valid_output(output), "explicit fresh confined output directory required")
	check(group in GROUPS or group == "all", "explicit known group required")
	check(DisplayServer.get_name() != "headless", "screenshots require native GPU display")
	var actual_user := ProjectSettings.globalize_path("user://").replace("\\", "/")
	var isolated_root := ProjectSettings.globalize_path("res://Temp/ming-maritime-profiles/").replace("\\", "/")
	check(actual_user.begins_with(isolated_root), "child APPDATA must isolate user:// under task profile")
	var original_appdata := OS.get_environment("PARCHMENT_ORIGINAL_APPDATA")
	check(not original_appdata.is_empty(), "original APPDATA required for real player-slot hash protection")
	original_directory = original_appdata.path_join("Godot/app_userdata/MingArmada")
	if not failures.is_empty(): await finish(); return
	original_slots = slot_hashes(original_directory)
	profile_slots = slot_hashes(actual_user)
	slot_prefix = "user://tests/parchment-ui-" + str(OS.get_process_id())
	for suffix: String in ["-v2.json", "-v1.json", "-settings.json"]:
		check(not FileAccess.file_exists(slot_prefix + suffix), "fresh PID slot: " + suffix)
	if not failures.is_empty(): await finish(); return
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output)) == OK, "create fresh task evidence directory")
	if not failures.is_empty(): await finish(); return
	output_owned = true
	source_hashes = sources()
	seed(1661)
	root.gui_embed_subwindows = true
	root.unresizable = true
	await resize_view(DIMENSIONS[0])
	# This watchdog quits only this SceneTree, never terminates unrelated processes.
	var watchdog_seconds := 1200.0 if group == "all" else 300.0
	create_timer(watchdog_seconds).timeout.connect(func():
		if not finishing:
			check(false, "capture exceeded " + str(watchdog_seconds) + "-second watchdog")
			finish())
	if not await make_main(): await finish(); return
	for selected: String in GROUPS:
		if group != "all" and group != selected: continue
		print("PARCHMENT_UI_GROUP_START ", selected)
		match selected:
			"menu": await menu_group()
			"atlas": await atlas_group()
			"mingqi": await mingqi_group()
			"legacy": await legacy_group()
			"naval": await naval_group()
			"catalog": await catalog_group()
			"practice": await practice_group()
			"auxiliary": await auxiliary_group()
	await finish()

func finish() -> void:
	if finishing: return
	finishing = true
	if is_instance_valid(direct_scene): direct_scene.queue_free()
	if is_instance_valid(main): main.queue_free()
	active_scene = null
	await frames(12)
	var after := slot_hashes(original_directory) if not original_slots.is_empty() else {}
	if not original_slots.is_empty(): check(after == original_slots, "all original player slots and backup states unchanged")
	var profile_after := slot_hashes(ProjectSettings.globalize_path("user://")) if not profile_slots.is_empty() else {}
	if not profile_slots.is_empty(): check(profile_after == profile_slots, "only explicit PID slots used inside isolated profile")
	if output_owned:
		check(sources() == source_hashes, "product UI, scene and source assets unchanged during this capture")
		write_json(output.path_join("capture-result.json"), {"group": group, "assertions": assertions, "failures": failures.size(), "errors": failures, "captures": captures, "actions": actions, "sourceHashes": source_hashes, "originalSlotsBefore": original_slots, "originalSlotsAfter": after, "originalSlotsUnchanged": after == original_slots, "profileSlotsBefore": profile_slots, "profileSlotsAfter": profile_after, "isolatedUserData": ProjectSettings.globalize_path("user://"), "isolatedSlotPrefix": slot_prefix, "isolatedFilesRetained": true, "scope": "Native UI screenshots, structural observations and listed viewport input actions only. Overflow candidates require visual review; scrolled-off controls are excluded. No continuous sea, FPS, complete gameplay, export package or native OS file-dialog claim."})
	print("PARCHMENT_UI_COMPLETE group=", group, " captures=", captures.size(), " assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func guard_tests() -> void:
	for bad: String in ["", "res://Temp/out", EVIDENCE_ROOT + "../outside", EVIDENCE_ROOT + "foo/bar", EVIDENCE_ROOT + "name.", EVIDENCE_ROOT + "name ", EVIDENCE_ROOT + "name:stream", EVIDENCE_ROOT + "con", EVIDENCE_ROOT + "lpt9", EVIDENCE_ROOT + "NAME", EVIDENCE_ROOT + "foo\\bar"]:
		check(not valid_output(bad), "reject unsafe output: " + bad)
	var fresh := EVIDENCE_ROOT + "guard-unused-" + str(OS.get_process_id())
	check(valid_output(fresh), "fresh task path accepted")
	check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(fresh)), "guard is read-only")
	check(not valid_output("res://docs/migration/evidence/menu"), "historical captures cannot be overwritten")
	print("PARCHMENT_UI_GUARDS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
