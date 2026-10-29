extends SceneTree
## A current NPC face is decoration; native story state and receipts retain authority.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var assertions := 0
var failures := 0
var commands: Array = []
var results: Array = []

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL story portrait: ", message)

func _initialize() -> void:
	_run.call_deferred()

func _settle() -> void:
	for frame in 8: await process_frame

func _portrait(ui) -> TextureRect:
	return ui.find_child("story_portrait_old-ledger", true, false) as TextureRect

func _click(point: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = point
		event.global_position = point
		event.pressed = pressed
		Input.parse_input_event(event)
		await process_frame

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1280, 720)
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).ok, "real opening configures")
	var initial: Dictionary = runtime.snapshot()
	check(initial.story.scenes[0].id == "old-ledger" and initial.story.scenes[0].status == "available" and initial.story.scenes[0].npc.name == "许福", "portrait is grounded in the actual available opening NPC")
	var ui = Interface.new()
	root.add_child(ui)
	ui.command_requested.connect(func(intent: Dictionary):
		commands.append(intent.duplicate(true))
		results.append(runtime.command(intent))
		ui.apply_snapshot(runtime.snapshot()))
	ui.apply_snapshot(initial)
	ui.open_panel("story")
	await _settle()
	var navigation: Label=ui.find_child("navigation",true,false)
	check(navigation.text.contains("\n"),"live navigation reserves separate lines for course and wind/port")
	var navigation_font:=navigation.get_theme_font("font")
	var navigation_size:=navigation.get_theme_font_size("font_size")
	for line: String in navigation.text.split("\n"):
		check(navigation_font.get_string_size(line,HORIZONTAL_ALIGNMENT_LEFT,-1,navigation_size).x<=navigation.size.x,"native navigation line fits without splitting the port name")
	var portrait := _portrait(ui)
	check(portrait != null and portrait.is_visible_in_tree(), "available Xu Fu dialogue consumes its actual painted portrait")
	if portrait:
		check(portrait.texture != null and portrait.texture.resource_path == "res://assets/ui/ming_maritime/painted/portrait-xufu.png", "displayed face is the generated Xu Fu asset")
		var image := portrait.texture.get_image() if portrait.texture else null
		check(image != null and image.detect_alpha() != Image.ALPHA_NONE, "consumed portrait retains real alpha")
		check(portrait.mouse_filter == Control.MOUSE_FILTER_IGNORE and portrait.focus_mode == Control.FOCUS_NONE, "alpha art never owns pointer or keyboard input")
		check(portrait.size.y >= 140 and portrait.size.y <= 170, "face stays compact in the reading frame")
		var scroll: ScrollContainer = ui.find_child("operation_scroll", true, false)
		scroll.ensure_control_visible(portrait)
		await _settle()
		await _click(portrait.get_global_rect().position + Vector2(2, 2))
		check(commands.is_empty(), "clicking transparent portrait margin issues no intent")
		var choice: Control = ui.find_child("story_choice_old-ledger_settle-wages", true, false)
		check(not portrait.get_global_rect().intersects(choice.get_global_rect()), "portrait cannot cover a native decision")
	check(ui.find_child("story_npc_old-ledger", true, false).text == "许福 · 老水手", "NPC name and role remain native text")
	check(ui.find_child("story_dialogue_old-ledger", true, false).text.contains("旧账册"), "supplied dialogue remains native readable text")
	check(ui.find_child("operation", true, false).size.x <= 440, "portrait does not widen the reading panel")
	root.size = Vector2i(320, 480)
	await _settle()
	var reading: Control = ui.find_child("operation_scroll", true, false)
	for id in ["story_portrait_old-ledger", "story_npc_old-ledger", "story_dialogue_old-ledger", "story_choice_old-ledger_settle-wages"]:
		var control := ui.find_child(id, true, false) as Control
		check(control != null and control.get_global_rect().position.x >= reading.get_global_rect().position.x - 1 and control.get_global_rect().end.x <= reading.get_global_rect().end.x + 1, "narrow reading frame keeps native story content horizontally reachable: " + id)
	root.size = Vector2i(1280, 720)
	await _settle()
	var renamed := initial.duplicate(true)
	renamed.story.scenes[0].npc.name = "另一位水手"
	ui.apply_snapshot(renamed)
	await _settle()
	portrait = _portrait(ui)
	check(portrait == null or not portrait.is_visible_in_tree(), "same-generation NPC rename cannot show Xu Fu's face")
	ui.apply_snapshot(initial)
	await _settle()
	check(_portrait(ui) != null and _portrait(ui).is_visible_in_tree(), "restoring the actual NPC restores its portrait")
	var locked := initial.duplicate(true)
	locked.story.scenes[0].status = "locked"
	locked.runtime.eligibility.story["old-ledger"] = {"ok": false, "reason": "story-locked"}
	ui.apply_snapshot(locked)
	await _settle()
	portrait = _portrait(ui)
	check(portrait == null or not portrait.is_visible_in_tree(), "locked scene never depicts a current conversation")
	check(ui.find_child("story_choice_old-ledger_settle-wages", true, false) == null, "locked scene has no choice behind portrait decoration")
	ui.apply_snapshot(initial)
	await _settle()
	var unsafe := initial.duplicate(true)
	unsafe.runtime.eligibility.story["old-ledger"] = {"ok": false, "reason": "unsafe-port"}
	ui.apply_snapshot(unsafe)
	await _settle()
	var choice: Button = ui.find_child("story_choice_old-ledger_settle-wages", true, false)
	check(choice.disabled, "face never overrides live safe-port eligibility")
	choice.pressed.emit()
	check(commands.is_empty(), "disabled portrait conversation cannot bypass command fence")
	ui.apply_snapshot(initial)
	await _settle()
	choice = ui.find_child("story_choice_old-ledger_settle-wages", true, false)
	check(not choice.disabled, "original available decision remains usable")
	choice.pressed.emit()
	await _settle()
	check(commands.size() == 1 and results.size() == 1 and results[0].ok, "native decision still reaches actual runtime exactly once")
	var after: Dictionary = runtime.snapshot()
	check(after.campaign.captain.silver == initial.campaign.captain.silver - 80 and after.story.scenes[0].status == "completed", "actual payment and receipt complete the conversation")
	portrait = _portrait(ui)
	check(portrait == null or not portrait.is_visible_in_tree(), "completed receipt removes the current-conversation portrait")
	check(ui.find_child("story_outcome_old-ledger", true, false).text.contains("80两"), "completed outcome remains native receipt text")
	ui.free()
	runtime.dispose()
	await process_frame
	print("MINGQI_STORY_PORTRAIT_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
