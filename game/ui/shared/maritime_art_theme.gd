extends RefCounted
## Painted maritime components. State and text stay in native Controls.
const Core = preload("res://game/ui/shared/parchment_theme.gd")
const WindowStyle = preload("res://game/ui/shared/painted_window_style.gd")
const ROOT := "res://assets/ui/ming_maritime/painted/"
const ACTIVE_ROOT := ROOT+"quiet/"
const FRAME_ROOT := ACTIVE_ROOT+"framed/"
const PAPER := Color("14353e")
const INK := Color("eadfca")
const MUTED := Color("bbc3b8")
const OUTLINE := Color("7e8c7e")
const CINNABAR := Color("c9b58f")
const SEA := Color("9bc3b8")
const SUCCESS := Color("b9ce98")
const DANGER := Color("ffb193")
const PALE := Color("fff2d5")
static var _textures: Dictionary = {}

static func has_texture(path: String) -> bool:
	# Exported PNGs are imported resources (.remap/.ctex), not raw files.
	# The raw-file branch also supports the editor's pre-import interval.
	return ResourceLoader.exists(path) or FileAccess.file_exists(path)

static func title_font() -> Font:
	var font:=SystemFont.new()
	font.font_names=PackedStringArray(["KaiTi","楷体","STKaiti","华文楷体","Noto Serif CJK SC","serif"])
	font.font_weight=400
	return font

static func _texture(path: String) -> Texture2D:
	if _textures.has(path): return _textures[path]
	# During an editor import, the file can exist before its resource metadata.
	# Production uses the same bundled PNG after import, never an external path.
	if ResourceLoader.exists(path):
		var imported := load(path) as Texture2D
		if imported: _textures[path]=imported
		return imported
	if FileAccess.file_exists(path):
		var pixels := Image.load_from_file(path)
		if pixels != null and not pixels.is_empty():
			var original := ImageTexture.create_from_image(pixels)
			_textures[path]=original
			return original
	return null

static func _skin(filename: String, margin: float, tint: Color = Color.WHITE, tone: String = "") -> StyleBox:
	var skin := StyleBoxTexture.new()
	var runtime_name:=filename.replace(".png","-small.png") if filename.begins_with("button-") else filename
	var family:=ACTIVE_ROOT if has_texture(ACTIVE_ROOT+filename) else ROOT
	var runtime_path:=family+"runtime/"+runtime_name
	if not has_texture(runtime_path): runtime_path=family+"runtime/"+filename
	skin.texture = _texture(runtime_path if has_texture(runtime_path) else family+filename)
	if skin.texture:
		var extent := skin.texture.get_size()
		# Buttons keep their actual painted outline, excluding only blank alpha.
		var inset := Vector2.ZERO
		if tone == "inset": inset = Vector2(extent.x*0.18,extent.y*0.24)
		skin.region_rect=Rect2(inset,extent-inset*2)
	if filename.begins_with("button-"):
		skin.set_texture_margin(SIDE_LEFT,8);skin.set_texture_margin(SIDE_RIGHT,8)
		skin.set_texture_margin(SIDE_TOP,3);skin.set_texture_margin(SIDE_BOTTOM,3)
		skin.set_content_margin_all(margin)
	elif tone=="inset":
		skin.set_texture_margin_all(2);skin.set_content_margin_all(margin)
	else:
		skin.set_texture_margin_all(8)
		skin.set_content_margin_all(maxf(margin,24))
		if margin<=12:
			skin.set_content_margin(SIDE_TOP,16);skin.set_content_margin(SIDE_BOTTOM,16)
		if filename=="folio-panel.png":
			# The single pale cloud occupies a separate folio head margin.
			# Text never crosses its lighter ink wash.
			skin.set_content_margin(SIDE_TOP,maxf(margin,76))
	skin.modulate_color=tint
	if not filename.begins_with("button-") and tone!="inset":
		return frame_style(skin,filename)
	return skin

static func window_edge(tone: String = "paper") -> StyleBoxTexture:
	var filename:="folio-panel.png" if tone=="folio" else "command-panel.png"
	return WindowStyle.framed_edge(_texture(FRAME_ROOT+"runtime/"+filename))

static func frame_style(body: StyleBoxTexture, filename: String = "command-panel.png") -> StyleBox:
	# Keep the reading surface and native margins intact. The generated gold
	# edge and alpha shadow draw outside that surface, never through its text.
	var edge:=window_edge("folio" if filename=="folio-panel.png" else "paper")
	var composed: StyleBox=WindowStyle.compose(body,edge)
	return composed if composed!=null else body

static func panel(margin: float = 24.0, tone: String = "paper") -> StyleBox:
	return _skin("folio-panel.png" if tone=="folio" else "command-panel.png",margin,Color.WHITE,tone)

static func button_style(state: String = "normal", primary: bool = false, margin: float = 12.0) -> StyleBox:
	if state=="focus":
		var focus := _skin("button-selected.png",0,Color(2.1,2.0,1.85,1)) as StyleBoxTexture
		focus.draw_center=false
		focus.set_texture_margin(SIDE_LEFT,4);focus.set_texture_margin(SIDE_RIGHT,4)
		focus.set_texture_margin(SIDE_TOP,2);focus.set_texture_margin(SIDE_BOTTOM,2)
		return focus
	var tint:=Color.WHITE
	if state=="hover": tint=Color(1.16,1.14,1.07,1)
	elif state=="pressed": tint=Color(0.82,0.85,0.82,1)
	elif state=="disabled": tint=Color(0.68,0.72,0.73,1)
	return _skin("button-selected.png" if primary else "button-normal.png",margin,tint)

static func background(parent: Node, variant: String = "ledger", node_name: String = "PaintedBackground") -> TextureRect:
	var current := parent.get_node_or_null(NodePath(node_name)) as TextureRect
	if current: return current
	var art:=TextureRect.new();art.name=node_name;art.texture=_texture(ACTIVE_ROOT+"folio-panel.png")
	art.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;art.stretch_mode=TextureRect.STRETCH_SCALE
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(art);parent.move_child(art,0)
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return art

static func create() -> Theme:
	var result:=Core.create()
	var native:=ThemeDB.get_default_theme()
	result.set_font("font","HeadingLabel",title_font())
	result.set_font_size("font_size","HeadingLabel",30)
	for kind: String in ["Label","Button","OptionButton","CheckBox","CheckButton","LineEdit","TextEdit","RichTextLabel","PopupMenu","ItemList","Tree","TabBar","TabContainer","Window","FileDialog","ProgressBar","SpinBox"]:
		for key: String in ["font_color","font_hover_color","font_pressed_color","font_focus_color","font_hover_pressed_color","font_selected_color"]: result.set_color(key,kind,INK)
		for key: String in ["font_disabled_color","font_readonly_color","font_placeholder_color"]: result.set_color(key,kind,MUTED)
		result.set_color("caret_color",kind,CINNABAR)
		result.set_color("selection_color",kind,Color("6b5738"))
		result.set_color("font_outline_color",kind,Color.TRANSPARENT)
		result.set_color("font_shadow_color",kind,Color.TRANSPARENT)
	result.set_color("default_color","RichTextLabel",INK)
	result.set_color("font_color","MutedLabel",MUTED)
	for kind: String in ["PanelContainer","Panel","PopupPanel","TooltipPanel"]: result.set_stylebox("panel",kind,panel(22))
	# Embedded dialogs already have the complete outer Window border. Their
	# client sheet stays inset, avoiding a second gold frame inside one window.
	for kind: String in ["AcceptDialog","FileDialog"]: result.set_stylebox("panel",kind,panel(22,"inset"))
	for kind: String in ["Button","OptionButton","CheckBox","CheckButton","PrimaryButton"]:
		for state: String in ["normal","hover","pressed","disabled","focus"]: result.set_stylebox(state,kind,button_style(state,kind=="PrimaryButton" or state=="pressed",8))
		result.set_stylebox("hover_pressed",kind,button_style("pressed",true,8))
	# Navigation glyphs use the engine's neutral light icons on the dark skins.
	# The generated artwork supplies the material; controls keep familiar cues.
	for kind: String in ["Button","OptionButton"]:
		for key: String in ["icon_normal_color","icon_hover_color","icon_focus_color","icon_pressed_color"]: result.set_color(key,kind,INK)
		result.set_color("icon_disabled_color",kind,MUTED)
	result.set_icon("arrow","OptionButton",native.get_icon("arrow","OptionButton"))
	result.set_icon("submenu","PopupMenu",native.get_icon("submenu","PopupMenu"))
	for icon: String in ["arrow","arrow_collapsed"]: result.set_icon(icon,"Tree",native.get_icon(icon,"Tree"))
	for icon: String in ["close","close_pressed"]: result.set_icon(icon,"Window",native.get_icon(icon,"Window"))
	result.set_color("folder_icon_color","FileDialog",CINNABAR)
	result.set_color("file_icon_color","FileDialog",INK)
	for kind: String in ["LineEdit","TextEdit"]:
		result.set_stylebox("normal",kind,panel(8,"inset"));result.set_stylebox("read_only",kind,panel(8,"inset"))
		result.set_stylebox("focus",kind,button_style("focus"))
		result.set_color("background_color",kind,Color.TRANSPARENT)
	for kind: String in ["PopupMenu","ItemList","Tree"]:
		result.set_stylebox("panel",kind,panel(12,"inset") if kind!="PopupMenu" else panel(12))
		for state: String in ["hover","selected","selected_focus"]: result.set_stylebox(state,kind,button_style("pressed",true,4))
	for kind: String in ["TabBar","TabContainer"]:
		for state: String in ["unselected","selected","hovered","disabled"]: result.set_stylebox("tab_"+state,kind,button_style("pressed" if state=="selected" else "normal",state=="selected",8))
		result.set_stylebox("panel",kind,panel(16,"folio"))
	for direction: String in ["up","down"]:
		result.set_color(direction+"_icon_modulate","SpinBox",INK)
		result.set_color(direction+"_hover_icon_modulate","SpinBox",PALE)
		result.set_color(direction+"_pressed_icon_modulate","SpinBox",CINNABAR)
		result.set_stylebox(direction+"_background_hovered","SpinBox",button_style("hover",true,0))
		result.set_stylebox(direction+"_background_pressed","SpinBox",button_style("pressed",true,0))
	for state: String in ["embedded_border","embedded_unfocused_border"]:
		var border = panel(12)
		border.set_expand_margin(SIDE_TOP,32);border.set_expand_margin(SIDE_LEFT,8);border.set_expand_margin(SIDE_RIGHT,8);border.set_expand_margin(SIDE_BOTTOM,6)
		result.set_stylebox(state,"Window",border)
	result.set_color("title_color","Window",INK)
	result.set_font("title_font","Window",title_font())
	result.set_font_size("title_font_size","Window",24)
	result.set_color("font_color","TooltipLabel",INK)
	return result
