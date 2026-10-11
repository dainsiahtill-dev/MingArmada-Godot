extends Control
## Presentation only. Owner supplies confirmed snapshots and resolves tokened intents.
signal intent_requested(intent: Dictionary)
signal settings_requested
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const DEFAULT_NAME := "沈沧海"
const MODES := ["mingqi","mingqi-continue","career","continue","duel","fleet","sail","qa"]
const PAPER := Color("f1e6cb")
const INK := Color("183e3c")
const BRASS := Color("b89a60")
var _built := false
var _model: Dictionary = {"settings":{"captainName":DEFAULT_NAME},"hasLegacySave":false,"mingqiSlot":"missing","dev":false,"qa":false}
var _generation := -1
var _nonce := 0
var _active_nonce := 0
var _phase := "menu"
var _last_intent: Dictionary = {}
var _draft_name := DEFAULT_NAME
var _name_dirty := false
var _applying := false
var _focus_epoch := 0
var _buttons: Dictionary = {}
var _panel: PanelContainer
var _scroll: ScrollContainer
var _captain: LineEdit
var _seed: LineEdit
var _seed_row: VBoxContainer
var _seed_error: Label
var _status: Label
var _progress: ProgressBar
var _retry: Button
var _back: Button
var _settings: Button
var _status_box: VBoxContainer
var _slot_hint: Label

func _ready() -> void: build()

static func normalized_name(encoded: String) -> String:
	var units: Array = Text.utf16_units(Text.source_trim(encoded))
	var collapsed: Array = []; var in_space := false
	for unit in units:
		if Text.whitespace(unit):
			if not in_space: collapsed.append(32)
			in_space = true
		else: collapsed.append(unit); in_space = false
	return Text.from_units(collapsed.slice(0,20)) if not collapsed.is_empty() else DEFAULT_NAME

func draft_name() -> String: return _draft_name

func apply_view_model(model: Dictionary, generation: int) -> bool:
	if generation < _generation: return false
	build()
	var changed := generation != _generation
	if changed:
		if _generation >= 0: _focus_epoch += 1
		_generation = generation; _active_nonce = 0; _phase = "menu"; _name_dirty = false
	_model.merge(model.duplicate(true),true)
	if changed or not _name_dirty:
		var confirmed: Variant = _model.get("settings",{}).get("captainName",DEFAULT_NAME)
		_draft_name = confirmed if confirmed is String and not confirmed.is_empty() else DEFAULT_NAME
		_applying = true; _captain.text = Text.display_text(_draft_name); _applying = false
	_render(); return true

func apply_status(status: Dictionary, generation: int, nonce: int) -> bool:
	if generation != _generation or nonce != _active_nonce or _active_nonce == 0: return false
	var next: String = status.get("phase","")
	if next not in ["loading","error","complete"] or _phase not in ["pending","loading"]: return false
	_phase = next
	_progress.value = clampf(float(status.get("progress",100 if next == "complete" else _progress.value)),0,100)
	_status.text = String(status.get("message",{"loading":"正在备帆，请稍候。","error":"航程暂未启程，请重试。","complete":"准备就绪。"}[next]))
	_render(); return true

func acknowledge(generation: int, nonce: int) -> bool:
	if generation != _generation or nonce != _active_nonce or _active_nonce == 0 or _phase != "complete": return false
	_active_nonce = 0; _phase = "menu"; _render(); return true

func _qa_enabled() -> bool: return _model.get("dev",false) == true or _model.get("qa",false) == true

func _name_changed(value: String) -> void:
	if _applying or _phase != "menu": return
	_draft_name = Text.from_units(Text.native_units(value).slice(0,20)); _name_dirty = true
	var display: String = Text.display_text(_draft_name)
	if display != value:
		var caret := _captain.caret_column
		_applying = true; _captain.text = display; _captain.caret_column = mini(caret,display.length()); _applying = false

func _seed_value() -> Dictionary:
	var value: String = Text.source_trim(Text.encode_native(_seed.text))
	if value.is_empty(): return {"ok":true}
	var units: Array = Text.utf16_units(value)
	for unit in units:
		if unit < 48 or unit > 57: return {"ok":false,"reason":"QA 种子须为 0–4294967295 的十进制整数，留空使用随机种子。"}
	var number := 0
	for unit in units:
		number = number*10+unit-48
		if number > 4294967295: return {"ok":false,"reason":"QA 种子超出 uint32 范围（0–4294967295）。"}
	return {"ok":true,"seed":number}

func _request(entry: String) -> void:
	if _phase != "menu" or _generation < 0: return
	if entry == "continue" and _model.get("hasLegacySave",false) != true: return
	if entry in ["qa","practice"] and not _qa_enabled(): return
	if entry not in MODES and entry not in ["ships","practice","quit"]: return
	var payload: Dictionary = {"type":"start" if entry in MODES else entry,"name":_draft_name}
	if entry in MODES:
		if entry == "mingqi" and _qa_enabled():
			var parsed := _seed_value()
			if not parsed.ok:
				_seed_error.text = parsed.reason; _seed_error.show(); _seed.grab_focus(); return
			if parsed.has("seed"): payload.qaSeed = parsed.seed
		_seed_error.hide(); payload.mode = entry
		_draft_name = normalized_name(_draft_name); payload.name = _draft_name
		_applying = true; _captain.text = Text.display_text(_draft_name); _applying = false
	_last_intent = payload.duplicate(true)
	_dispatch(payload)

func _dispatch(payload: Dictionary) -> void:
	_nonce += 1; _active_nonce = _nonce
	var request := payload.duplicate(true); request.generation = _generation; request.nonce = _nonce
	_phase = "pending"; _progress.value = 0; _status.text = "正在备帆，请稍候。"
	_render(); _scroll.scroll_vertical = 0
	intent_requested.emit(request)

func _retry_request() -> void:
	if _phase != "error" or _last_intent.is_empty(): return
	var request := _last_intent.duplicate(true); request.entryType = request.type; request.type = "retry"
	_dispatch(request)

func _back_request() -> void:
	if _phase == "menu" or _active_nonce == 0: return
	_nonce += 1
	var request := {"type":"back","generation":_generation,"nextGeneration":_generation+1,"nonce":_nonce,"cancelledNonce":_active_nonce}
	_generation += 1; _focus_epoch += 1; _active_nonce = 0; _phase = "menu"
	_render(); intent_requested.emit(request)

func _settings_request() -> void:
	if _phase == "menu": settings_requested.emit()

func _render() -> void:
	if not _built: return
	var idle := _phase == "menu"
	for entry in _buttons:
		var button: Button = _buttons[entry]
		button.disabled = not idle or (entry == "continue" and _model.get("hasLegacySave",false) != true)
		if entry in ["qa","practice"]: button.visible = _qa_enabled()
	_seed_row.visible = _qa_enabled(); _captain.editable = idle; _seed.editable = idle
	_settings.disabled = not idle
	_status_box.visible = not idle; _progress.visible = _phase in ["pending","loading","complete"]
	_retry.visible = _phase == "error"; _back.visible = not idle
	_buttons["continue"].text = "继续旧版航程\n"+("载入旧版本地航程" if _model.get("hasLegacySave",false) == true else "尚无旧版存档")
	_slot_hint.text = {"present":"载入本地安全存档","unreadable":"读取受阻 · 重试或导入存档","missing":"导入存档或恢复航程"}.get(_model.get("mingqiSlot","missing"),"导入存档或恢复航程")
	_buttons["mingqi-continue"].text = "继续海上明旗 · 1650\n"+_slot_hint.text

func _style(background: Color, border: Color, margin: int = 14) -> StyleBoxFlat:
	var style := StyleBoxFlat.new(); style.bg_color = background; style.border_color = border
	style.set_border_width_all(1); style.set_content_margin_all(margin); style.set_corner_radius_all(3)
	return style

func _theme() -> Theme:
	var result := Theme.new(); result.default_font_size = 17
	var font := SystemFont.new(); font.font_names = PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"]); result.default_font = font
	for type in ["Label","Button","LineEdit"]: result.set_color("font_color",type,INK)
	result.set_color("font_disabled_color","Button",Color("82908a"))
	result.set_color("font_hover_color","Button",INK); result.set_color("font_pressed_color","Button",INK)
	result.set_color("font_focus_color","Button",INK)
	result.set_color("font_selected_color","LineEdit",PAPER); result.set_color("selection_color","LineEdit",INK)
	for state in ["normal","hover","pressed","disabled"]:
		var color: Color = {"normal":Color("e7ddc4"),"hover":Color("f9edcc"),"pressed":Color("ccb789"),"disabled":Color("ded6c4")}[state]
		result.set_stylebox(state,"Button",_style(color,BRASS,12))
	var focus := _style(Color(0,0,0,0),Color("187b77"),2); focus.set_border_width_all(3)
	result.set_stylebox("focus","Button",focus); result.set_stylebox("focus","LineEdit",focus)
	result.set_stylebox("normal","LineEdit",_style(Color("faf2df"),BRASS,10))
	result.set_stylebox("read_only","LineEdit",_style(Color("ded6c4"),BRASS,10))
	return result

func _label(parent: Node, id: String, text: String, font_size: int = 17) -> Label:
	var label := Label.new(); label.name = id; label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size",font_size); parent.add_child(label); return label

func _entry(parent: Node, id: String, title: String, subtitle: String, primary: bool = false) -> Button:
	var button := Button.new(); button.name = id; button.text = title+"\n"+subtitle
	button.tooltip_text = title+" · "+subtitle; button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; button.custom_minimum_size.y = 70 if primary else 64
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.add_theme_font_size_override("font_size",19 if primary else 16)
	if primary:
		button.add_theme_stylebox_override("normal",_style(Color("c9ad73"),Color("907239"),15))
		button.add_theme_stylebox_override("hover",_style(Color("e3c78d"),Color("907239"),15))
	parent.add_child(button); _buttons[id] = button
	button.pressed.connect(func(): _request(id)); return button

func build() -> void:
	if _built: return
	_built = true; name = "MainMenu"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP; theme = _theme()
	var harbor := TextureRect.new(); harbor.name = "Harbor"; harbor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	harbor.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; harbor.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	harbor.texture = load("res://assets/art/ports/xiamen-harbor-v1.png"); harbor.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(harbor)
	var shade := TextureRect.new(); shade.name = "Shade"; shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var gradient := Gradient.new(); gradient.set_color(0,Color(0.035,0.16,0.16,0.88)); gradient.set_color(1,Color(0.035,0.16,0.16,0.16))
	var shade_texture := GradientTexture2D.new(); shade_texture.gradient = gradient; shade_texture.fill_from = Vector2.ZERO; shade_texture.fill_to = Vector2.RIGHT
	shade.texture = shade_texture; shade.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(shade)
	_panel = PanelContainer.new(); _panel.name = "MenuPanel"; _panel.add_theme_stylebox_override("panel",_style(PAPER,BRASS,22)); add_child(_panel)
	_scroll = ScrollContainer.new(); _scroll.name = "MenuScroll"; _scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _panel.add_child(_scroll)
	var column := VBoxContainer.new(); column.name = "Content"; column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",12); _scroll.add_child(column)
	_label(column,"Era","南明 · 永历四年 · 1650",15).add_theme_color_override("font_color",Color("7a643c"))
	var title := _label(column,"Title","海上明旗",54)
	var song := SystemFont.new(); song.font_names = PackedStringArray(["SimSun","Songti SC","serif"]); title.add_theme_font_override("font",song)
	_label(column,"Intro","一叶福船，万里海疆。\n乘风起航，在炮火与商路间写下你的海上生涯。",16)
	_label(column,"CaptainLabel","船长姓名",14)
	_captain = LineEdit.new(); _captain.name = "Captain"; _captain.text = DEFAULT_NAME; _captain.placeholder_text = DEFAULT_NAME
	_captain.custom_minimum_size.y = 44; _captain.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_child(_captain)
	_captain.text_changed.connect(_name_changed); _captain.text_submitted.connect(func(_text: String): _request("mingqi"))
	_seed_row = VBoxContainer.new(); _seed_row.name = "QASeedRow"; column.add_child(_seed_row)
	_label(_seed_row,"SeedLabel","QA 新生涯种子",14)
	_seed = LineEdit.new(); _seed.name = "QASeed"; _seed.text = "1661"; _seed.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER; _seed_row.add_child(_seed)
	_seed.text_submitted.connect(func(_text: String): _request("mingqi"))
	_label(_seed_row,"SeedHelp","uint32：0–4294967295；留空随机。仅用于新的 1650 航程。",12)
	_seed_error = _label(_seed_row,"SeedError","",14); _seed_error.add_theme_color_override("font_color",Color("923b27")); _seed_error.hide()
	_status_box = VBoxContainer.new(); _status_box.name = "StatusBox"; column.add_child(_status_box)
	_status = _label(_status_box,"Status","正在备帆，请稍候。",18)
	_progress = ProgressBar.new(); _progress.name = "Progress"; _progress.custom_minimum_size.y = 24; _status_box.add_child(_progress)
	_progress.add_theme_stylebox_override("background",_style(Color("d7cbb2"),BRASS,0)); _progress.add_theme_stylebox_override("fill",_style(Color("2c6860"),Color("2c6860"),0))
	var recovery := HBoxContainer.new(); recovery.add_theme_constant_override("separation",10); _status_box.add_child(recovery)
	_retry = Button.new(); _retry.name = "Retry"; _retry.text = "重新加载"; _retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL; recovery.add_child(_retry); _retry.pressed.connect(_retry_request)
	_back = Button.new(); _back.name = "Back"; _back.text = "返回菜单"; _back.size_flags_horizontal = Control.SIZE_EXPAND_FILL; recovery.add_child(_back); _back.pressed.connect(_back_request)
	_entry(column,"mingqi","海上明旗新生涯","1650 · 厦金护粮",true)
	_entry(column,"mingqi-continue","继续海上明旗 · 1650","导入存档或恢复航程")
	_slot_hint = _label(column,"SlotHint","",12); _slot_hint.hide()
	_entry(column,"career","旧版航程 · 1661","开始旧版生涯")
	_entry(column,"continue","继续旧版航程","尚无旧版存档")
	var battles := HBoxContainer.new(); battles.name = "Battles"; battles.add_theme_constant_override("separation",10); column.add_child(battles)
	_entry(battles,"duel","单舰炮战","一对一交锋"); _entry(battles,"fleet","舰队遭遇","一对二挑战")
	_entry(column,"sail","自由试航","练习风帆与操舵")
	_entry(column,"ships","检阅船只","福船、渔舟与远洋商船")
	_entry(column,"qa","画面验收","真实引擎 · 可重复场景")
	_entry(column,"practice","玩法验收","决斗、陆战、寻宝与宴会")
	var utility := HBoxContainer.new(); utility.name = "Utility"; utility.add_theme_constant_override("separation",10); column.add_child(utility)
	_settings = Button.new(); _settings.name = "Settings"; _settings.text = "航海设置"; _settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL; utility.add_child(_settings); _settings.pressed.connect(_settings_request)
	var exit := Button.new(); exit.name = "quit"; exit.text = "退出游戏"; exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; utility.add_child(exit); _buttons.quit = exit; exit.pressed.connect(func():_request("quit"))
	_label(column,"Footer","1650 · 厦门至金门\n键盘 / 鼠标 · 单人航海",12).add_theme_color_override("font_color",Color("7a643c"))
	resized.connect(_layout); _layout(); _render()
	tree_exiting.connect(_cancel_initial_focus)
	_focus_after_layout()

func _cancel_initial_focus() -> void: _focus_epoch += 1

func _focus_after_layout() -> void:
	# Container sorting first resolves text widths, then wrapped minimum heights.
	# Focusing during that transient layout can make follow_focus scroll to the end.
	var tree := get_tree(); var epoch := _focus_epoch
	await tree.process_frame
	if not is_inside_tree() or _focus_epoch != epoch or _phase != "menu": return
	var generation := _generation
	await tree.process_frame
	if not is_inside_tree() or _focus_epoch != epoch or _generation != generation or _phase != "menu": return
	_captain.grab_focus()

func _layout() -> void:
	if not _built: return
	var bounds := size
	if bounds.x <= 0 or bounds.y <= 0: bounds = get_viewport_rect().size
	var narrow := bounds.x < 760
	var margin_x := 12.0 if narrow else clampf(bounds.x*0.065,28,100)
	var margin_y := 12.0 if bounds.y < 600 else 28.0
	_panel.position = Vector2(margin_x,margin_y)
	_panel.size = Vector2(minf(480,bounds.x-margin_x*2),maxf(0,bounds.y-margin_y*2))
