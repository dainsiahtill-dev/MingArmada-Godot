extends Control
## Emits intent patches only. Owner persists/adopts and reapplies confirmed snapshot.
signal settings_requested(patch: Dictionary)
signal close_requested
const Settings = preload("res://game/persistence/user_settings.gd")
const Parchment = preload("res://game/ui/shared/maritime_art_theme.gd")
var _built := false
var _applying := false
var _controls: Dictionary = {}
var _reason: Label
var _panel: PanelContainer
var _scroll: ScrollContainer
var _first: Control
var _previous_focus: WeakRef
var _rows: Array[GridContainer] = []

func _ready() -> void: build()

func build() -> void:
	if _built: return
	_built = true
	name = "SettingsPanel"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Parchment.create()
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new(); shade.color = Color(Parchment.PAPER,0.62); shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(shade)
	var center := CenterContainer.new(); center.name = "Center"; center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(center)
	_panel = PanelContainer.new(); _panel.name = "Panel"; center.add_child(_panel)
	_panel.add_theme_stylebox_override("panel",Parchment.panel(16,"folio"))
	_panel.add_theme_font_size_override("font_size",16)
	var column := VBoxContainer.new(); column.name = "Column"; column.add_theme_constant_override("separation",10); _panel.add_child(column)
	var title := Label.new(); title.text = "航海设置"; title.add_theme_font_override("font",Parchment.title_font()); title.add_theme_font_size_override("font_size",28); column.add_child(title)
	_reason = Label.new(); _reason.name = "Reason"; _reason.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _reason.add_theme_font_size_override("font_size",16); _reason.add_theme_color_override("font_color",Parchment.CINNABAR); column.add_child(_reason)
	_scroll = ScrollContainer.new(); _scroll.name = "Scroll"; _scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _scroll.follow_focus = true; _scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL; column.add_child(_scroll)
	var fields := VBoxContainer.new(); fields.name = "Fields"; fields.size_flags_horizontal = Control.SIZE_EXPAND_FILL; fields.add_theme_constant_override("separation",10); _scroll.add_child(fields)
	_choice(fields,"handling","操船方式",["辅助操船","真实操船"],["assisted","realistic"])
	_choice(fields,"quality","画面质量",["低","均衡","高"],["low","balanced","high"])
	_toggle(fields,"sound","航海音效"); _slider(fields,"soundVolume","音效音量")
	_toggle(fields,"music","背景音乐"); _slider(fields,"musicVolume","音乐音量")
	_toggle(fields,"reducedMotion","减少动态效果"); _slider(fields,"cameraShake","镜头晃动")
	_toggle(fields,"cameraFollow","镜头跟随"); _slider(fields,"horizonStability","地平线稳定")
	var close_button := Button.new(); close_button.name = "Close"; close_button.text = "返回"; close_button.custom_minimum_size.y = 42
	close_button.pressed.connect(func(): close(); close_requested.emit()); column.add_child(close_button)
	resized.connect(_resize); get_viewport().size_changed.connect(_resize); _resize(); apply_settings(Settings.defaults()); hide()

func _row(parent: Control,key: String,label: String) -> GridContainer:
	var row := GridContainer.new(); row.name = key; row.columns = 2; row.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_theme_constant_override("h_separation",20); row.add_theme_constant_override("v_separation",4); parent.add_child(row); _rows.append(row)
	var text := Label.new(); text.name = "Caption"; text.text = label; text.custom_minimum_size.x = 140; text.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(text)
	return row

func _remember(row: Control,key: String,control: Control) -> void:
	control.name = "Value"; control.custom_minimum_size = Vector2(160,36); control.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(control); _controls[key] = control
	if not _first: _first = control

func _emit(key: String,value: Variant) -> void:
	if not _applying: settings_requested.emit({key:value})

func _choice(parent: Control,key: String,label: String,labels: Array,values: Array) -> void:
	var control := OptionButton.new()
	for text in labels: control.add_item(text)
	control.set_meta("values",values)
	_remember(_row(parent,key,label),key,control)
	control.item_selected.connect(func(index: int): _emit(key,values[index]))

func _toggle(parent: Control,key: String,label: String) -> void:
	var control := CheckButton.new(); control.text = "开启"
	_remember(_row(parent,key,label),key,control)
	control.toggled.connect(func(on: bool): _emit(key,on))

func _slider(parent: Control,key: String,label: String) -> void:
	var control := HSlider.new(); control.min_value = 0; control.max_value = 1; control.step = 0.01
	_remember(_row(parent,key,label),key,control)
	control.value_changed.connect(func(value: float): _emit(key,value))

func _resize() -> void:
	if not _built: return
	var viewport := get_viewport_rect().size
	var narrow := viewport.x < 560
	for row in _rows:
		row.columns = 1 if narrow else 2
		row.get_node("Caption").custom_minimum_size.x = 0 if narrow else 140
		row.get_node("Value").custom_minimum_size.x = 0 if narrow else 200
	_panel.custom_minimum_size.x = minf(620,maxf(0,viewport.x-24))
	# Give the window a bounded height; the expanding scroll area receives the
	# remainder after the actual wrapped reason, title, Return and art margins.
	# A fixed scroll minimum otherwise pushes two-line errors beyond 320×480.
	_panel.custom_minimum_size.y = minf(760,maxf(0,viewport.y-32))
	_scroll.custom_minimum_size.y = 0

func apply_settings(settings: Dictionary,reason: String = "") -> void:
	build(); _applying = true
	var actual := Settings.normalise_settings(settings)
	for key in _controls:
		var control: Control = _controls[key]
		if control is OptionButton: control.select(control.get_meta("values").find(actual[key]))
		elif control is CheckButton:
			control.set_pressed_no_signal(actual[key])
			control.text = "已开启" if actual[key] else "已关闭"
		elif control is HSlider: control.set_value_no_signal(actual[key]); control.tooltip_text = "%d%%" % roundi(float(actual[key])*100)
	_reason.text = _reason_text(reason); _applying = false

func _reason_text(reason: String) -> String:
	if reason.is_empty() or reason in ["settings-loaded","settings-saved"]: return "设置更改将保存到本机。"
	if reason == "settings-not-found": return "首次启动，使用默认设置。"
	if reason == "settings-normalized": return "已修正旧设置中的无效项目。"
	if reason == "settings-invalid-json": return "设置文件损坏，已恢复默认设置。"
	if reason == "settings-unsupported-version": return "设置版本不兼容，已使用默认设置。"
	if "readback" in reason: return "设置写入后校验失败，更改未应用。"
	if "read" in reason: return "无法读取本机设置，已使用默认设置。"
	if "write" in reason or "replace" in reason or "directory" in reason: return "设置写入失败，更改未应用。"
	if "invalid" in reason or "unknown" in reason: return "设置内容无效，更改未应用。"
	return "设置未保存："+reason

func open(settings: Dictionary = {},reason: String = "") -> void:
	build(); _previous_focus = weakref(get_viewport().gui_get_focus_owner()) if get_viewport().gui_get_focus_owner() else null
	if not settings.is_empty(): apply_settings(settings,reason)
	show(); _resize(); _first.grab_focus()

func close() -> void:
	hide()
	if _previous_focus and _previous_focus.get_ref(): _previous_focus.get_ref().grab_focus()
	_previous_focus = null

func _gui_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close(); close_requested.emit(); accept_event()
