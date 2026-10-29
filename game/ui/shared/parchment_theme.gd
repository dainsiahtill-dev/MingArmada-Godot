extends RefCounted
## Shared paper/ink presentation only. No business state or input ownership.
const WindowStyle = preload("res://game/ui/shared/painted_window_style.gd")
const FRAME_PATH := "res://assets/ui/ming_maritime/painted/quiet/framed/runtime/command-panel.png"
const PAPER := Color("ead6aa")
const INK := Color("173c46")
const MUTED := Color("4b5953")
const OUTLINE := Color("ab8449")
const CINNABAR := Color("9f4331")
const SEA := Color("365d61")
const SUCCESS := Color("315b3d")
const DANGER := Color("8d3025")
const PALE := Color("fff1d3")
const PANEL_PATH := "res://assets/ui/ming_maritime/panel-paper.png"
const BUTTON_PATH := "res://assets/ui/ming_maritime/secondary-button.png"
const PRIMARY_PATH := "res://assets/ui/ming_maritime/primary-button.png"
const BACKGROUNDS := {"menu":"res://assets/ui/ming_maritime/menu-painting.png","ledger":PANEL_PATH,"chart":"res://assets/ui/ming_maritime/chart-paper.png"}

static func title_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["SimSun","Songti SC","Noto Serif CJK SC","serif"])
	return font

static func _flat(color: Color, border: Color = OUTLINE, margin: float = 6.0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color; style.border_color = border
	style.set_border_width_all(1); style.set_corner_radius_all(2); style.set_content_margin_all(margin)
	return style

static func _paper(path: String, margin: float, tint: Color = Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load(path) as Texture2D
	# New artwork is opaque edge-to-edge. Protect the corner ornaments for large
	# panels; short controls use a quiet inner crop so their cap stays small.
	if style.texture != null:
		var inset := Vector2(5,3) if path == BUTTON_PATH else Vector2.ZERO if path == PRIMARY_PATH or margin >= 22.0 else Vector2(64,64)
		style.region_rect = Rect2(inset,style.texture.get_size()-inset*2)
	style.set_texture_margin_all(48.0 if margin >= 22.0 and path == PANEL_PATH else 2.0)
	style.set_content_margin_all(margin)
	style.modulate_color = tint
	return style

static func panel(margin: float = 14.0, tone: String = "paper") -> StyleBox:
	if tone == "dark": return _flat(INK,OUTLINE,margin)
	var tint: Color = Color("e7e9dd") if tone == "inset" else Color.WHITE
	return _paper(PANEL_PATH,margin,tint)

static func _floating_frame(body: StyleBoxTexture) -> StyleBox:
	# Reuse the generated transparent frame without depending on Maritime's
	# factory (which itself builds on this theme).
	var texture: Texture2D
	if ResourceLoader.exists(FRAME_PATH): texture = load(FRAME_PATH) as Texture2D
	elif FileAccess.file_exists(FRAME_PATH):
		var pixels := Image.load_from_file(FRAME_PATH)
		if pixels != null and not pixels.is_empty(): texture = ImageTexture.create_from_image(pixels)
	var edge := WindowStyle.framed_edge(texture)
	var framed: StyleBox = WindowStyle.compose(body,edge)
	return framed if framed != null else body

static func floating_panel(margin: float = 14.0) -> StyleBox:
	return _floating_frame(panel(margin) as StyleBoxTexture)

static func button_style(state: String = "normal", primary: bool = false, margin: float = 12.0) -> StyleBox:
	if state == "focus":
		var focus := _flat(Color.TRANSPARENT,SEA,0)
		focus.set_border_width_all(2)
		return focus
	var tint := Color.WHITE
	if state == "hover": tint = Color(1.09,1.07,1.02,1)
	elif state == "pressed": tint = Color(0.84,0.80,0.72,1)
	elif state == "disabled": tint = Color(0.88,0.85,0.79,0.74)
	var material := _paper(PRIMARY_PATH if primary else BUTTON_PATH,margin,tint)
	material.set_texture_margin_all(2.0)
	return material

static func background(parent: Node, variant: String = "ledger", node_name: String = "ParchmentBackground") -> TextureRect:
	var existing := parent.get_node_or_null(NodePath(node_name)) as TextureRect
	if existing != null: return existing
	var art := TextureRect.new(); art.name = node_name
	art.texture = load(BACKGROUNDS.get(variant,BACKGROUNDS.ledger)) as Texture2D
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(art); parent.move_child(art,0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return art

static func _icon(name: String) -> Texture2D:
	return load("res://assets/ui/parchment/"+name+".svg") as Texture2D

static func create() -> Theme:
	var result := Theme.new(); result.default_font_size = 16
	var font := SystemFont.new(); font.font_names = PackedStringArray(["Microsoft YaHei UI","Microsoft YaHei","Noto Sans CJK SC","sans-serif"])
	result.default_font = font
	for kind in ["Label","Button","OptionButton","CheckBox","CheckButton","LineEdit","TextEdit","RichTextLabel","PopupMenu","ItemList","Tree","TabBar","TabContainer","Window","FileDialog","ProgressBar","SpinBox"]:
		for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color","font_selected_color"]: result.set_color(key,kind,INK)
		result.set_color("font_disabled_color",kind,MUTED)
		result.set_color("font_readonly_color",kind,MUTED)
		result.set_color("font_placeholder_color",kind,MUTED)
		result.set_color("font_outline_color",kind,Color.TRANSPARENT)
		result.set_color("font_shadow_color",kind,Color.TRANSPARENT)
		result.set_color("caret_color",kind,CINNABAR)
		result.set_color("selection_color",kind,Color("d2b580"))
	result.set_color("default_color","RichTextLabel",INK)
	for kind in ["PanelContainer","Panel"]: result.set_stylebox("panel",kind,panel())
	result.set_stylebox("panel","PopupPanel",floating_panel())
	# A dialog's single outer Window border supplies the frame and shadow.
	for kind in ["AcceptDialog","FileDialog"]: result.set_stylebox("panel",kind,panel())
	for kind in ["Button","OptionButton","CheckBox","CheckButton"]:
		for state in ["normal","hover","pressed","disabled","focus"]: result.set_stylebox(state,kind,button_style(state,false,8))
		result.set_stylebox("hover_pressed",kind,button_style("pressed",false,8))
		result.set_constant("h_separation",kind,8)
	for kind in ["Button","OptionButton"]:
		for key in ["icon_normal_color","icon_hover_color","icon_focus_color","icon_pressed_color"]: result.set_color(key,kind,INK)
		result.set_color("icon_disabled_color",kind,Color(MUTED,0.45))
	result.set_type_variation("PrimaryButton","Button")
	for state in ["normal","hover","pressed","disabled","focus"]: result.set_stylebox(state,"PrimaryButton",button_style(state,true,10))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color"]: result.set_color(key,"PrimaryButton",PALE)
	result.set_color("font_disabled_color","PrimaryButton",Color("d3ba9c"))
	result.set_type_variation("HeadingLabel","Label"); result.set_font("font","HeadingLabel",title_font()); result.set_font_size("font_size","HeadingLabel",30)
	result.set_type_variation("MutedLabel","Label"); result.set_color("font_color","MutedLabel",MUTED)
	for kind in ["LineEdit","TextEdit"]:
		result.set_stylebox("normal",kind,panel(8,"inset"))
		result.set_stylebox("read_only",kind,panel(8,"inset"))
		result.set_stylebox("focus",kind,button_style("focus"))
		result.set_color("background_color",kind,Color.TRANSPARENT)
		result.set_color("current_line_color",kind,Color(0.6,0.4,0.2,0.08))
	for kind in ["CheckBox","CheckButton","PopupMenu"]:
		for name in ["checked","checked_disabled"]: result.set_icon(name,kind,_icon("check-on"))
		for name in ["unchecked","unchecked_disabled"]: result.set_icon(name,kind,_icon("check-off"))
		result.set_icon("radio_checked",kind,_icon("radio-on")); result.set_icon("radio_unchecked",kind,_icon("radio-off"))
	result.set_icon("arrow","OptionButton",_icon("arrow-down")); result.set_constant("arrow_margin","OptionButton",8)
	for direction in ["up","down"]:
		for state in ["","_hover","_pressed","_disabled"]:
			result.set_icon(direction+state,"SpinBox",_icon("spin-"+direction))
		result.set_color(direction+"_icon_modulate","SpinBox",INK)
		result.set_color(direction+"_hover_icon_modulate","SpinBox",CINNABAR)
		result.set_color(direction+"_pressed_icon_modulate","SpinBox",PALE)
		result.set_color(direction+"_disabled_icon_modulate","SpinBox",Color(MUTED,0.55))
		result.set_stylebox(direction+"_background_hovered","SpinBox",_flat(Color("d6b781"),OUTLINE,0))
		result.set_stylebox(direction+"_background_pressed","SpinBox",_flat(CINNABAR,CINNABAR,0))
	result.set_constant("buttons_width","SpinBox",16)
	result.set_color("font_hover_color","PopupMenu",INK)
	result.set_stylebox("panel","PopupMenu",floating_panel(8))
	result.set_stylebox("hover","PopupMenu",_flat(Color("d6b781"),OUTLINE,4))
	result.set_stylebox("separator","PopupMenu",_flat(OUTLINE,OUTLINE,1))
	result.set_constant("v_separation","PopupMenu",10)
	result.set_icon("submenu","PopupMenu",_icon("arrow-right"))
	for kind in ["ItemList","Tree"]:
		result.set_stylebox("panel",kind,panel(8,"inset"))
		result.set_stylebox("selected",kind,_flat(Color("d6b781"),OUTLINE,4))
		result.set_stylebox("selected_focus",kind,_flat(Color("dcc195"),CINNABAR,4))
		result.set_stylebox("cursor",kind,button_style("focus"))
		result.set_stylebox("cursor_unfocused",kind,_flat(Color.TRANSPARENT,OUTLINE,0))
		result.set_color("guide_color",kind,Color("baa17a"))
	result.set_icon("arrow","Tree",_icon("arrow-down")); result.set_icon("arrow_collapsed","Tree",_icon("arrow-right"))
	for kind in ["TabBar","TabContainer"]:
		result.set_stylebox("tab_unselected",kind,button_style("normal",false,8))
		result.set_stylebox("tab_selected",kind,button_style("hover",false,8))
		result.set_stylebox("tab_hovered",kind,button_style("hover",false,8))
		result.set_stylebox("tab_disabled",kind,button_style("disabled",false,8))
		result.set_stylebox("tab_focus",kind,button_style("focus"))
		result.set_stylebox("panel",kind,panel())
		result.set_color("font_selected_color",kind,CINNABAR)
	for kind in ["HSlider","VSlider"]:
		var track := _flat(Color("c2a77e"),OUTLINE,3); track.set_content_margin_all(3)
		result.set_stylebox("slider",kind,track)
		result.set_stylebox("grabber_area",kind,_flat(SEA,SEA,3))
		result.set_stylebox("grabber_area_highlight",kind,_flat(CINNABAR,CINNABAR,3))
		for key in ["grabber","grabber_highlight","grabber_disabled"]: result.set_icon(key,kind,_icon("grabber"))
	for kind in ["HScrollBar","VScrollBar"]:
		result.set_stylebox("scroll",kind,_flat(Color("d6c09b"),Color("c1a57b"),2))
		result.set_stylebox("scroll_focus",kind,button_style("focus"))
		for state in ["grabber","grabber_highlight","grabber_pressed"]: result.set_stylebox(state,kind,_flat(OUTLINE if state=="grabber" else CINNABAR,OUTLINE,5))
	result.set_stylebox("background","ProgressBar",_flat(Color("d3bc94"),OUTLINE,2))
	result.set_stylebox("fill","ProgressBar",_flat(Color("a0b3a1"),SEA,0))
	result.set_color("font_color","ProgressBar",INK)
	for kind in ["HSeparator","VSeparator"]: result.set_stylebox("separator",kind,_flat(OUTLINE,OUTLINE,1))
	for state in ["embedded_border","embedded_unfocused_border"]:
		var window_paper: StyleBoxTexture = panel(10,"paper" if state=="embedded_border" else "inset")
		# Match Godot's embedded-window decoration geometry; title is above client.
		window_paper.set_expand_margin(SIDE_TOP,32); window_paper.set_expand_margin(SIDE_LEFT,8)
		window_paper.set_expand_margin(SIDE_RIGHT,8); window_paper.set_expand_margin(SIDE_BOTTOM,6)
		window_paper.set_content_margin(SIDE_TOP,28); window_paper.set_content_margin(SIDE_BOTTOM,8)
		result.set_stylebox(state,"Window",_floating_frame(window_paper))
	result.set_constant("title_height","Window",36)
	result.set_color("title_color","Window",INK); result.set_color("title_outline_modulate","Window",Color.TRANSPARENT)
	result.set_icon("close","Window",_icon("close")); result.set_icon("close_pressed","Window",_icon("close"))
	result.set_color("files_disabled","FileDialog",MUTED); result.set_color("folder_icon_color","FileDialog",OUTLINE); result.set_color("file_icon_color","FileDialog",SEA)
	result.set_stylebox("panel","TooltipPanel",floating_panel(8)); result.set_color("font_color","TooltipLabel",INK)
	return result
