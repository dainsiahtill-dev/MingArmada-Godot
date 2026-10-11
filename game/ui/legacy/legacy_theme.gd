extends RefCounted
static func create() -> Theme:
	var theme=Theme.new();theme.default_font_size=16
	var font=SystemFont.new();font.font_names=PackedStringArray(["Microsoft YaHei","Noto Sans CJK SC","sans-serif"]);theme.default_font=font
	var panel=StyleBoxFlat.new();panel.bg_color=Color("123b3d");panel.border_color=Color("c5a059");panel.set_border_width_all(1);panel.set_content_margin_all(14)
	theme.set_stylebox("panel","PanelContainer",panel)
	for state in ["normal","hover","pressed","disabled","focus"]:
		var style=StyleBoxFlat.new();style.bg_color=Color("26534e") if state=="normal" else Color("386c61") if state=="hover" else Color("816d44") if state=="pressed" else Color("263b3b") if state=="disabled" else Color(0,0,0,0)
		style.border_color=Color("e3c780") if state=="focus" else Color("9a8756");style.set_border_width_all(2 if state=="focus" else 1);style.set_content_margin_all(8)
		for type in ["Button","OptionButton","CheckBox"]:theme.set_stylebox(state,type,style)
	for type in ["Button","Label","OptionButton","CheckBox","LineEdit","TextEdit"]:
		theme.set_color("font_color",type,Color("f2e9d0"));theme.set_color("font_disabled_color",type,Color("88958a"));theme.set_color("font_hover_color",type,Color("fff0c6"))
	return theme
