extends SceneTree
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/ui/shared/parchment_theme.gd"):
		check(false,"shared parchment theme must exist for every UI family"); _finish(); return
	var factory = load("res://game/ui/shared/parchment_theme.gd")
	if factory == null: check(false,"shared theme parses"); _finish(); return
	var theme: Theme = factory.create()
	for kind in ["Button","OptionButton","CheckBox","CheckButton"]:
		for state in ["normal","hover","pressed","disabled","focus"]:
			check(theme.has_stylebox(state,kind),kind+" exposes "+state+" state")
	check(factory.panel() is StyleBoxTexture,"panels use actual generated paper resource")
	var panel_style: StyleBoxTexture = factory.panel(22)
	var panel_image := panel_style.texture.get_image()
	var panel_x := int(panel_style.region_rect.position.x)
	check(panel_image.get_pixel(panel_x,int(panel_image.get_height()/2)).a > 0.9,"visible panel edge starts at opaque paper rather than a transparent inset")
	var button_frame: StyleBoxTexture = factory.button_style("normal")
	check(button_frame.get_texture_margin(SIDE_TOP)+button_frame.get_texture_margin(SIDE_BOTTOM)<=8,"small controls keep textured edge caps below a quarter of a 32px row")
	check(theme.has_stylebox("panel","AcceptDialog") and theme.has_stylebox("panel","FileDialog"),"native embedded file dialogs replace default dark client background")
	var window_border: StyleBox = theme.get_stylebox("embedded_border","Window")
	check(window_border.has_method("get_body_style") and window_border.get_expand_margin(SIDE_TOP)>=32,"embedded file dialog title retains an opaque paper backing and outer frame")
	check(theme.has_color("icon_normal_color","Button") and theme.get_color("icon_normal_color","Button").get_luminance()<0.3,"standard file-navigation icons remain visible on pale paper")
	check(factory.button_style("normal") is StyleBoxTexture,"normal buttons use generated material")
	check(factory.button_style("normal",true).texture != factory.button_style("normal").texture,"primary action has a distinct generated cinnabar material")
	var ink_luminance := theme.get_color("font_color","Label").srgb_to_linear().get_luminance()
	var paper_luminance: float = factory.PAPER.srgb_to_linear().get_luminance()
	check((paper_luminance+0.05)/(ink_luminance+0.05) >= 7.0,"paper labels retain at least 7:1 contrast with the current maritime ink palette")
	check(theme.get_stylebox("hover","Button") != theme.get_stylebox("normal","Button"),"hover has separate visual state")
	for kind in ["LineEdit","TextEdit","PopupMenu","ItemList","Tree","TabContainer","Window"]:
		check(theme.has_color("font_color",kind) or theme.has_color("title_color",kind),kind+" receives paper-compatible text")
	check(theme.has_icon("checked","CheckBox") and theme.has_icon("unchecked","CheckBox"),"check states are visible custom ink symbols")
	for direction in ["up","down"]:
		for state in ["","_hover","_pressed","_disabled"]:
			var icon_key: String = direction+state
			check(theme.has_icon(icon_key,"SpinBox") and theme.get_icon(icon_key,"SpinBox").get_size()==Vector2(16,8),"SpinBox "+icon_key+" has a state icon without enlarging the input row")
		for state in ["","_hover"]:
			var color_key: String = direction+state+"_icon_modulate"
			var background: Color = factory.PAPER if state.is_empty() else theme.get_stylebox(direction+"_background_hovered","SpinBox").bg_color
			var icon_luminance := theme.get_color(color_key,"SpinBox").srgb_to_linear().get_luminance()
			var background_luminance := background.srgb_to_linear().get_luminance()
			var contrast := (maxf(icon_luminance,background_luminance)+0.05)/(minf(icon_luminance,background_luminance)+0.05)
			check(theme.has_color(color_key,"SpinBox") and contrast>=3.0,"SpinBox "+color_key+" has at least 3:1 contrast against its actual paper state")
	var host := Control.new();root.add_child(host);host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var button := Button.new();button.text="航海设置";host.add_child(button)
	var bg: TextureRect = factory.background(host,"menu")
	check(bg.texture != null and bg.mouse_filter == Control.MOUSE_FILTER_IGNORE,"real menu texture never intercepts actions")
	check(host.get_child(0) == bg,"background stays behind interactive content")
	check(factory.background(host,"menu") == bg,"background attach is idempotent")
	var intents: Array = [];button.pressed.connect(func():intents.append(true));button.pressed.emit()
	check(intents.size()==1,"decorative material leaves actual button action intact")
	for variant in ["ledger","chart"]:
		var p := Control.new();host.add_child(p);check(factory.background(p,variant).texture != null,variant+" background exists")
	host.free();_finish()
func _finish() -> void:
	print("PARCHMENT_THEME_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
