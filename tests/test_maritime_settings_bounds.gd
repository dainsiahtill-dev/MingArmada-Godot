extends SceneTree
## Window bounds and live Return remain valid with the longest real errors.
const SettingsPanel = preload("res://game/ui/settings/settings_panel.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var assertions:=0
var failures:=0

func _initialize() -> void: run.call_deferred()

func check(value: bool, detail: String) -> void:
	assertions+=1
	if not value:
		failures+=1
		printerr("FAIL: ",detail)

func settle() -> void:
	for index in 10: await process_frame

func run() -> void:
	var panel=SettingsPanel.new();root.add_child(panel)
	for dimensions: Vector2i in [Vector2i(320,480),Vector2i(1280,720),Vector2i(1600,900)]:
		root.size=dimensions;root.content_scale_size=dimensions
		var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
		for reason: String in ["settings-loaded","settings-write-failed","settings-unsupported-version","settings-readback-failed","settings-read-failed"]:
			panel.open(Settings.defaults(),reason);await settle()
			var close: Control=panel.find_child("Close",true,false)
			check(bounds.encloses(panel._panel.get_global_rect()),"complete settings window fits "+str(dimensions)+" / "+reason)
			check(bounds.encloses(close.get_global_rect()),"Return fits "+str(dimensions)+" / "+reason)
			for control: Control in panel._controls.values():
				panel._scroll.ensure_control_visible(control);await settle()
				check(panel._scroll.get_global_rect().grow(1).encloses(control.get_global_rect()),"settings field can scroll fully into view: "+str(control.get_path()))
			var point:=close.get_global_rect().get_center()
			var motion:=InputEventMouseMotion.new();motion.position=point;motion.global_position=point;root.push_input(motion,true)
			for pressed: bool in [true,false]:
				var event:=InputEventMouseButton.new();event.position=point;event.global_position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
				root.push_input(event,true);await process_frame
			check(not panel.visible,"actual viewport Return closes settings: "+reason)
	panel.free()
	print("MARITIME_SETTINGS_BOUNDS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
