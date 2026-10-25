extends SceneTree
func _initialize() -> void:
	var base := ThemeDB.get_default_theme()
	var style := base.get_stylebox("embedded_border","Window")
	var values := {"class":style.get_class(),"constants":{},"style":{}}
	for key in base.get_constant_list("Window"): values.constants[key] = base.get_constant(key,"Window")
	for p in style.get_property_list():
		if "margin" in p.name or "border_width" in p.name: values.style[p.name] = style.get(p.name)
	print(JSON.stringify(values));quit()
