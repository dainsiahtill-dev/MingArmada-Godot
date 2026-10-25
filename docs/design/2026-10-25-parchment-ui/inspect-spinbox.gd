extends SceneTree
func _initialize() -> void:
	var base := ThemeDB.get_default_theme()
	var values := {"icons":[],"colors":{},"constants":{}}
	for key in base.get_icon_list("SpinBox"): values.icons.append({"name":key,"size":str(base.get_icon(key,"SpinBox").get_size())})
	for key in base.get_color_list("SpinBox"): values.colors[key] = base.get_color(key,"SpinBox").to_html()
	for key in base.get_constant_list("SpinBox"): values.constants[key] = base.get_constant(key,"SpinBox")
	print(JSON.stringify(values));quit()
