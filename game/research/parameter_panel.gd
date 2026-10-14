extends HFlowContainer
## Data-driven parameter widgets only. The experiment owns validation and state.
signal parameter_changed(id: String, value: Variant)
var _specs: Array = []
var _controls: Dictionary = {}

func bind_specs(specs: Array) -> Dictionary:
	var seen: Dictionary = {}
	for item: Variant in specs:
		if not item is Dictionary or not item.get("id") is String or not item.get("label") is String or not item.get("type") is String:
			return {"ok":false,"reason":"参数描述格式无效"}
		if not item.id.is_valid_identifier() or seen.has(item.id): return {"ok":false,"reason":"参数名称无效或重复"}
		seen[item.id] = true
		match item.type:
			"toggle":
				if not item.get("value") is bool: return {"ok":false,"reason":"开关参数必须为布尔值"}
			"choice":
				if not item.get("choices") is Array or item.choices.is_empty(): return {"ok":false,"reason":"选项为空"}
				var values: Array = []
				for choice: Variant in item.choices:
					if not choice is Dictionary or not choice.get("label") is String or not choice.has("value") or choice.value in values: return {"ok":false,"reason":"选项格式无效或重复"}
					values.append(choice.value)
				if item.get("value") not in values: return {"ok":false,"reason":"参数默认选项未登记"}
			"range":
				for field: String in ["value","min","max","step"]:
					if not (item.get(field) is float or item.get(field) is int) or not is_finite(float(item[field])): return {"ok":false,"reason":"数值参数不是有限数"}
				if item.min > item.max or item.step <= 0 or item.value < item.min or item.value > item.max: return {"ok":false,"reason":"数值范围无效"}
			_: return {"ok":false,"reason":"参数控件类型未支持"}
	for child: Node in get_children(): child.free()
	_controls.clear(); _specs = specs.duplicate(true)
	for item: Dictionary in _specs:
		var id: String = item.id
		match item.type:
			"toggle":
				var toggle := CheckBox.new(); toggle.name = "Param_"+id; toggle.text = item.label; toggle.button_pressed = item.value
				add_child(toggle); _controls[id] = toggle
				toggle.toggled.connect(func(value: bool): parameter_changed.emit(id,value))
			"choice":
				var option := OptionButton.new(); option.name = "Param_"+id
				var values: Array = []
				for choice: Dictionary in item.choices: option.add_item(item.label+"："+choice.label); values.append(choice.value)
				option.select(values.find(item.value)); option.set_meta("values",values)
				add_child(option); _controls[id] = option
				option.item_selected.connect(func(index: int): parameter_changed.emit(id,option.get_meta("values")[index]))
			"range":
				var row := HBoxContainer.new(); add_child(row)
				var label := Label.new(); label.text = item.label; row.add_child(label)
				var value := SpinBox.new(); value.name = "Param_"+id; value.min_value = item.min; value.max_value = item.max; value.step = item.step; value.value = item.value
				value.custom_minimum_size.x = 90; row.add_child(value); _controls[id] = value
				value.value_changed.connect(func(number: float): parameter_changed.emit(id,number))
	return {"ok":true}

func sync_values(parameters: Dictionary) -> void:
	for item: Dictionary in _specs:
		if not parameters.has(item.id): continue
		var value: Variant = parameters[item.id]; var control: Control = _controls[item.id]
		match item.type:
			"toggle": control.set_pressed_no_signal(value)
			"choice": control.select(control.get_meta("values").find(value))
			"range": control.set_value_no_signal(value)
