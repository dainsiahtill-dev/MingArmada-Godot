extends Control
## Presentation only. Owner supplies confirmed snapshots and resolves tokened intents.
signal intent_requested(intent: Dictionary)
signal settings_requested
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
const DEFAULT_NAME := "沈沧海"
const MODES := ["mingqi","mingqi-continue","career","continue","duel","fleet","fire","sail","qa"]
const DEVELOPMENT_MODES := ["career","continue","qa","practice","water-study","fidelity-source"]
const PAPER := Parchment.PAPER
const INK := Parchment.INK
const BRASS := Parchment.OUTLINE
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
var _development: VBoxContainer

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
	if entry in DEVELOPMENT_MODES and not _qa_enabled(): return
	if entry not in MODES and entry not in ["world-atlas","ships","laboratory","practice","water-study","fidelity-island","fidelity-source","quit"]: return
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
		if entry in DEVELOPMENT_MODES: button.visible = _qa_enabled()
	_development.visible = _qa_enabled()
	_seed_row.visible = _qa_enabled(); _captain.editable = idle; _seed.editable = idle
	_settings.disabled = not idle
	_status_box.visible = not idle; _progress.visible = _phase in ["pending","loading","complete"]
	_retry.visible = _phase == "error"; _back.visible = not idle
	_buttons["continue"].text = "继续旧版航程\n"+("载入旧版本地航程" if _model.get("hasLegacySave",false) == true else "尚无旧版存档")
	_slot_hint.text = {"present":"载入本地安全存档","unreadable":"读取受阻 · 重试或导入存档","missing":"导入存档或恢复航程"}.get(_model.get("mingqiSlot","missing"),"导入存档或恢复航程")
	_buttons["mingqi-continue"].text = "继续航程 · 1650" if _model.get("mingqiSlot","missing") == "present" else "恢复航程 · 1650"
	_buttons["mingqi-continue"].tooltip_text = _slot_hint.text

func _theme() -> Theme:
	var result:=Parchment.create()
	var floating:=Maritime.create()
	# The title painting keeps its original reading palette. Detached hints and
	# native editing menus share the same framed floating material as gameplay.
	for kind: String in ["PopupMenu","TooltipPanel","TooltipLabel"]:
		for key: String in floating.get_stylebox_list(kind): result.set_stylebox(key,kind,floating.get_stylebox(key,kind))
		for key: String in floating.get_color_list(kind): result.set_color(key,kind,floating.get_color(key,kind))
		for key: String in floating.get_font_list(kind): result.set_font(key,kind,floating.get_font(key,kind))
		for key: String in floating.get_font_size_list(kind): result.set_font_size(key,kind,floating.get_font_size(key,kind))
		for key: String in floating.get_icon_list(kind): result.set_icon(key,kind,floating.get_icon(key,kind))
		for key: String in floating.get_constant_list(kind): result.set_constant(key,kind,floating.get_constant(key,kind))
	return result

func _label(parent: Node, id: String, text: String, font_size: int = 17) -> Label:
	var label := Label.new(); label.name = id; label.text = text; label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL; label.add_theme_font_size_override("font_size",font_size); parent.add_child(label); return label

func _entry(parent: Node, id: String, title: String, subtitle: String, primary: bool = false) -> Button:
	var button := Button.new(); button.name = id; button.text = title+"\n"+subtitle if primary else title
	button.tooltip_text = title+" · "+subtitle; button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; button.custom_minimum_size.y = 60 if primary else 48
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL; button.add_theme_font_size_override("font_size",19 if primary else 16)
	if primary:
		button.theme_type_variation = "PrimaryButton"
		for state in ["normal","hover","pressed","disabled","focus"]:
			button.add_theme_stylebox_override(state,Parchment.button_style(state,true,10))
	parent.add_child(button); _buttons[id] = button
	button.pressed.connect(func(): _request(id)); return button

func build() -> void:
	if _built: return
	_built = true; name = "MainMenu"; set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP; theme = _theme()
	Parchment.background(self,"menu","Harbor")
	_panel = PanelContainer.new(); _panel.name = "MenuPanel"
	# The original painting supplies the quiet paper field. Keep the composition
	# open instead of covering the illustration with another full-height box.
	var menu_space := StyleBoxEmpty.new(); menu_space.set_content_margin_all(18)
	_panel.add_theme_stylebox_override("panel",menu_space); add_child(_panel)
	_scroll = ScrollContainer.new(); _scroll.name = "MenuScroll"; _scroll.follow_focus = true
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; _panel.add_child(_scroll)
	var column := VBoxContainer.new(); column.name = "Content"; column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",7); _scroll.add_child(column)
	_label(column,"Era","海 疆 绘 卷  /  永历四年",14).add_theme_color_override("font_color",Parchment.SEA)
	var title := _label(column,"Title","海上明旗",58)
	title.add_theme_font_override("font",Parchment.title_font())
	_label(column,"Intro","一叶福船，万里海疆。\n从厦金潮汐间，写下你的海上生涯。",16)
	_label(column,"CaptainLabel","船长姓名",14)
	_captain = LineEdit.new(); _captain.name = "Captain"; _captain.text = DEFAULT_NAME; _captain.placeholder_text = DEFAULT_NAME
	_captain.custom_minimum_size.y = 44; _captain.size_flags_horizontal = Control.SIZE_EXPAND_FILL; column.add_child(_captain)
	_captain.text_changed.connect(_name_changed); _captain.text_submitted.connect(func(_text: String): _request("mingqi"))
	_seed_row = VBoxContainer.new(); _seed_row.name = "QASeedRow"; column.add_child(_seed_row)
	_label(_seed_row,"SeedLabel","QA 新生涯种子",14)
	_seed = LineEdit.new(); _seed.name = "QASeed"; _seed.text = "1661"; _seed.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER; _seed_row.add_child(_seed)
	_seed.text_submitted.connect(func(_text: String): _request("mingqi"))
	_label(_seed_row,"SeedHelp","uint32：0–4294967295；留空随机。仅用于新的 1650 航程。",12)
	_seed_error = _label(_seed_row,"SeedError","",14); _seed_error.add_theme_color_override("font_color",Parchment.DANGER); _seed_error.hide()
	_status_box = VBoxContainer.new(); _status_box.name = "StatusBox"; column.add_child(_status_box)
	_status = _label(_status_box,"Status","正在备帆，请稍候。",18)
	_progress = ProgressBar.new(); _progress.name = "Progress"; _progress.custom_minimum_size.y = 24; _status_box.add_child(_progress)
	var recovery := HBoxContainer.new(); recovery.add_theme_constant_override("separation",10); _status_box.add_child(recovery)
	_retry = Button.new(); _retry.name = "Retry"; _retry.text = "重新加载"; _retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL; recovery.add_child(_retry); _retry.pressed.connect(_retry_request)
	_back = Button.new(); _back.name = "Back"; _back.text = "返回菜单"; _back.size_flags_horizontal = Control.SIZE_EXPAND_FILL; recovery.add_child(_back); _back.pressed.connect(_back_request)
	_entry(column,"mingqi","扬帆启程","1650 · 厦金护粮",true)
	_entry(column,"mingqi-continue","继续海上明旗 · 1650","导入存档或恢复航程")
	_slot_hint = _label(column,"SlotHint","",12); _slot_hint.hide()
	var battles := GridContainer.new(); battles.name = "Battles"; battles.columns = 2; battles.add_theme_constant_override("h_separation",10); battles.add_theme_constant_override("v_separation",7); column.add_child(battles)
	_entry(battles,"duel","单舰炮战","一对一交锋"); _entry(battles,"fleet","舰队遭遇","一对二挑战")
	_entry(column,"fire","火攻交锋","短程投送 · 水手调配 · 有限损管")
	_entry(column,"sail","自由试航","练习风帆与操舵")
	var exploration := GridContainer.new(); exploration.name = "Exploration"; exploration.columns = 2; exploration.add_theme_constant_override("h_separation",10); exploration.add_theme_constant_override("v_separation",7); column.add_child(exploration)
	_entry(exploration,"world-atlas","世界海图","东洋南海 · 港口图志")
	_entry(exploration,"ships","检阅船只","福船与远洋商船")
	var studies := GridContainer.new(); studies.name = "Studies"; studies.columns = 2; studies.add_theme_constant_override("h_separation",10); studies.add_theme_constant_override("v_separation",7); column.add_child(studies)
	_entry(studies,"laboratory","实验室","海疆技艺与研究")
	_entry(studies,"fidelity-island","海面与海岛验收","海水与动态岸浪")
	_development = VBoxContainer.new(); _development.name = "DevelopmentEntries"; _development.add_theme_constant_override("separation",10); column.add_child(_development)
	_label(_development,"DevelopmentTitle","开发工具与兼容航程",16)
	_entry(_development,"career","旧版航程 · 1661","开始旧版生涯")
	_entry(_development,"continue","继续旧版航程","尚无旧版存档")
	_entry(_development,"water-study","海岛水面参考","晴天、夕阳与潮起潮落的来源对照")
	_entry(_development,"fidelity-source","参考海岛对照","来源海面与岸浪的独立校验画面")
	_entry(_development,"qa","画面验收","真实引擎 · 可重复场景")
	_entry(_development,"practice","玩法验收","决斗、陆战、寻宝与宴会")
	var utility := GridContainer.new(); utility.name = "Utility"; utility.columns = 2; utility.add_theme_constant_override("h_separation",10); utility.add_theme_constant_override("v_separation",7); column.add_child(utility)
	_settings = Button.new(); _settings.name = "Settings"; _settings.text = "航海设置"; _settings.size_flags_horizontal = Control.SIZE_EXPAND_FILL; utility.add_child(_settings); _settings.pressed.connect(_settings_request)
	var exit := Button.new(); exit.name = "quit"; exit.text = "退出游戏"; exit.size_flags_horizontal = Control.SIZE_EXPAND_FILL; utility.add_child(exit); _buttons.quit = exit; exit.pressed.connect(func():_request("quit"))
	_label(column,"Footer","厦门 · 金门  /  键盘与鼠标",13).add_theme_color_override("font_color",Parchment.MUTED)
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
	var margin_x := 10.0 if narrow else clampf(bounds.x*0.055,28,106)
	var margin_y := 10.0 if bounds.y < 700 else 30.0
	_panel.position = Vector2(margin_x,margin_y)
	_panel.size = Vector2(minf(438,bounds.x-margin_x*2),maxf(0,bounds.y-margin_y*2))
	for row: String in ["Battles","Exploration","Studies","Utility"]:
		var grid := find_child(row,true,false) as GridContainer
		if grid: grid.columns = 1 if bounds.x < 460 else 2
	# Tight portrait windows use an opaque reading sheet over the cropped art.
	if narrow: _panel.add_theme_stylebox_override("panel",Maritime.frame_style(Parchment.panel(14) as StyleBoxTexture))
	else:
		var menu_space := StyleBoxEmpty.new(); menu_space.set_content_margin_all(18)
		_panel.add_theme_stylebox_override("panel",menu_space)
