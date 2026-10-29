extends SceneTree
## Resolve the actual menu FileDialog theme; opening it must remain presentation-only.
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ",detail)

func _initialize() -> void: _run.call_deferred()

func _contrast(foreground: Color, background: Color) -> float:
	var first := foreground.srgb_to_linear().get_luminance()
	var second := background.srgb_to_linear().get_luminance()
	return (maxf(first,second)+0.05)/(minf(first,second)+0.05)

func _run() -> void:
	var ui := Interface.new()
	root.add_child(ui)
	await process_frame
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json"))
	ui.apply_snapshot({"campaign":envelope.state,"naval":{"ships":[]},"runtime":{"generation":1,"paused":true,"canSave":false,"saveReason":"save-safe-port-required","status":"ready"}})
	ui.open_menu()
	var requests: Array = []
	ui.command_requested.connect(func(intent: Dictionary): requests.append(intent))
	var opener := ui.find_child("import_choose_file",true,false) as Button
	var picker := ui.find_child("import_file_picker",true,false) as FileDialog
	check(opener != null and picker != null,"real voyage menu contains import opener and file picker")
	if opener == null or picker == null:
		ui.free(); _finish(); return
	opener.pressed.emit()
	await process_frame
	var paper := picker.get_theme_stylebox("panel","AcceptDialog")
	var texture_paper := paper as StyleBoxTexture
	if paper.has_method("get_body_style"): texture_paper=paper.call("get_body_style")
	var button_ink := picker.get_ok_button().get_theme_color("font_color")
	print("MINGQI_FILE_DIALOG_OBSERVATION ",JSON.stringify({"explicitTheme":picker.theme != null,"panelClass":paper.get_class(),"buttonInk":button_ink.to_html(),"title":picker.title,"confirm":picker.get_ok_button().text,"cancel":picker.get_cancel_button().text}))
	check(picker.visible,"voyage menu action actually opens the file picker")
	check(texture_paper != null and texture_paper.texture != null,"file picker resolves a real paper texture instead of default grey dialog panel")
	var border:=picker.get_theme_stylebox("embedded_border","Window")
	check(border.has_method("get_body_style") and border.call("get_body_style").texture!=null,"embedded title bar resolves a real painted body")
	check(border.has_method("get_edge_style") and border.call("get_edge_style").texture!=null and not border.call("get_edge_style").draw_center,"embedded title bar keeps a separate generated gold and shadow edge")
	var button_skin := picker.get_ok_button().get_theme_stylebox("normal") as StyleBoxTexture
	var button_background: Color=Maritime.PAPER
	if button_skin != null and button_skin.texture != null:
		var pixels := button_skin.texture.get_image()
		if pixels.is_compressed(): pixels.decompress()
		button_background=pixels.get_pixel(pixels.get_width()/2,pixels.get_height()/2)
	check(_contrast(button_ink,button_background) >= 4.5,"resolved confirm-button text retains contrast against its actual generated skin")
	check(picker.title == "导入航程存档","visible picker title is Chinese")
	check(picker.get_ok_button().text == "导入" and picker.get_cancel_button().text == "取消","visible file actions are Chinese")
	check(picker.file_mode == FileDialog.FILE_MODE_OPEN_FILE and picker.access == FileDialog.ACCESS_FILESYSTEM,"presentation keeps file mode and filesystem access")
	check(picker.filters == PackedStringArray(["*.json ; JSON 存档"]),"presentation preserves the JSON import filter")
	check(requests.is_empty(),"opening the file picker sends no import or world command")
	picker.hide()
	ui.free()
	await process_frame
	_finish()

func _finish() -> void:
	print("MINGQI_FILE_DIALOG_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
