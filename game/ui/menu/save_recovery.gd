extends Control
## Detached recovery presentation. Owner validates, reads and commits every action.
signal intent_requested(intent: Dictionary)
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
var _built := false
var _locked := false
var _reason: Label
var _json: TextEdit
var _buttons: Dictionary = {}
var _load: FileDialog
var _export: FileDialog
var _export_kind := "raw"
var _scroll: ScrollContainer
var _panel: PanelContainer
var _session := 0
var _dialog_serial := 0
var _load_callback: Callable
var _export_callback: Callable

func _ready() -> void: build()
func build() -> void:
	if _built: return
	_built = true; name = "SaveRecovery"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Parchment.create()
	Parchment.background(self,"ledger")
	var center := CenterContainer.new(); center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	_panel = PanelContainer.new(); _panel.name = "RecoveryPanel"; center.add_child(_panel)
	_panel.add_theme_stylebox_override("panel",Parchment.panel(20))
	_scroll = ScrollContainer.new(); _scroll.name = "RecoveryScroll"; _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _scroll.follow_focus = true; _panel.add_child(_scroll)
	var body := VBoxContainer.new(); body.size_flags_horizontal = Control.SIZE_EXPAND_FILL; body.add_theme_constant_override("separation",10); _scroll.add_child(body)
	var title := Label.new(); title.text = "恢复海上明旗 · 1650 航程"; title.add_theme_font_override("font",Parchment.title_font()); title.add_theme_font_size_override("font_size",25); body.add_child(title)
	_reason = Label.new(); _reason.name = "Reason"; _reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _reason.add_theme_color_override("font_color",Parchment.CINNABAR); body.add_child(_reason)
	var hint := Label.new(); hint.text = "可重新读取、使用备份，或导入网页导出的 v2 JSON。导入成功前保留原存档。"; hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; hint.add_theme_color_override("font_color",Parchment.MUTED); body.add_child(hint)
	_button(body,"Retry","重新读取本地存档","retry")
	_button(body,"Backup","验证并继续备份航程","read-backup")
	_button(body,"ExportRaw","复制原始待恢复内容","export-raw")
	_button(body,"ExportBackup","复制已验证备份","export-backup")
	_button(body,"ExportFile","将原始内容另存为文件","export-file-dialog")
	_json = TextEdit.new(); _json.name = "ImportJSON"; _json.placeholder_text = "在此粘贴 v2 JSON"; _json.custom_minimum_size.y = 130; body.add_child(_json)
	_button(body,"ImportJSONButton","验证并导入 JSON","import-json")
	_button(body,"ImportFile","选择 JSON 文件导入","import-file-dialog")
	_button(body,"Back","返回主菜单","back")
	_load = FileDialog.new(); _load.name = "ImportDialog"; _load.access = FileDialog.ACCESS_FILESYSTEM; _load.file_mode = FileDialog.FILE_MODE_OPEN_FILE; _load.filters = PackedStringArray(["*.json ; JSON 航程存档"]); add_child(_load)
	_export = FileDialog.new(); _export.name = "ExportDialog"; _export.access = FileDialog.ACCESS_FILESYSTEM; _export.file_mode = FileDialog.FILE_MODE_SAVE_FILE; _export.filters = PackedStringArray(["*.json ; JSON 原始内容"]); add_child(_export)
	_load.theme = theme; _export.theme = theme
	resized.connect(_resize); _resize(); hide()

func _button(parent: Control,id: String,label: String,action: String) -> void:
	var button := Button.new(); button.name = id; button.text = label; button.custom_minimum_size.y = 42; parent.add_child(button); _buttons[id] = button
	button.pressed.connect(_button_pressed.bind(action))
func _button_pressed(action: String) -> void:
	if _locked and action != "back": return
	match action:
		"import-json": _emit({"type":action,"json":_json.text})
		"import-file-dialog": _open_file_dialog(false)
		"export-file-dialog": _export_kind = "raw"; _export.current_file = "mingqi-recovery.json"; _open_file_dialog(true)
		_: _emit({"type":action})

func _open_file_dialog(exporting: bool) -> void:
	_dialog_serial += 1
	var epoch := _session; var serial := _dialog_serial; var kind := _export_kind
	var dialog: FileDialog = _export if exporting else _load
	var previous := _export_callback if exporting else _load_callback
	if previous.is_valid() and dialog.file_selected.is_connected(previous): dialog.file_selected.disconnect(previous)
	var callback := func(path: String):
		if epoch != _session or serial != _dialog_serial or not visible: return
		_emit({"type":"export-file" if exporting else "import-file","path":path,"kind":kind,"session":epoch})
	if exporting: _export_callback = callback
	else: _load_callback = callback
	dialog.file_selected.connect(callback); dialog.popup_centered_ratio(0.8)
	dialog.title = "导出原始存档内容" if exporting else "导入航程存档"
	dialog.ok_button_text = "保存" if exporting else "导入"
	dialog.get_cancel_button().text = "取消"

func _emit(intent: Dictionary) -> void:
	if _locked and intent.type != "back": return
	intent.session = _session
	intent_requested.emit(intent.duplicate(true))
func session_epoch() -> int: return _session
func _resize() -> void:
	if not _built: return
	var viewport := get_viewport_rect().size
	_panel.custom_minimum_size.x = clampf(viewport.x-32,250,700)
	_scroll.custom_minimum_size.y = clampf(viewport.y-80,200,690)

func open(snapshot: Dictionary) -> void:
	build(); _session += 1; _json.text = ""; set_busy(false); apply_snapshot(snapshot); show(); _buttons.Retry.grab_focus()
func apply_snapshot(snapshot: Dictionary,reason: String = "") -> void:
	build()
	_buttons.ExportRaw.disabled = _locked or not snapshot.get("has_raw",false)
	_buttons.ExportFile.disabled = _buttons.ExportRaw.disabled
	show_reason(snapshot.get("reason","save-not-found") if reason.is_empty() else reason)
func show_reason(reason: String) -> void:
	var messages := {"save-not-found":"本机尚无 1650 存档，请导入航程或读取备份。","save-read-failed":"暂时无法读取本地航程，可重试或选择 JSON 文件。","save-invalid":"本地航程校验未通过；原始内容仍保留。","backup-not-found":"尚无可用备份；可以导入网页 JSON。","import-read-failed":"无法读取所选文件，请重新选择。","save-write-failed":"存档写入失败，原航程与恢复内容仍保留。","recovery-bytes-unavailable":"没有已读取的原始内容可以导出。","exported":"内容已复制到剪贴板。","export-file-saved":"原始内容已另存为文件。"}
	_reason.text = messages.get(reason,"航程暂未恢复："+reason)
func set_busy(value: bool) -> void:
	build(); _locked = value; _json.editable = not value
	for key in _buttons: _buttons[key].disabled = value and key != "Back"
	if value: _reason.text = "正在验证航程并准备船队，请稍候。"
func close() -> void:
	_session += 1; _dialog_serial += 1; _load.hide(); _export.hide(); hide(); _locked = false
