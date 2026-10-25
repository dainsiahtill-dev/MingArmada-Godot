extends CanvasLayer
const Parchment = preload("res://game/ui/shared/parchment_theme.gd")

signal command_requested(intent: Dictionary)
signal view_requested(tactical: bool)
var _status: Label
var _pause: Button
var _assist: Button

func _ready() -> void:
	var panel := PanelContainer.new()
	panel.theme = Parchment.create()
	panel.position = Vector2(24, 24)
	var style: StyleBox = Parchment.panel(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	panel.add_child(column)
	var title := Label.new()
	title.text = "海上明旗  ·  厦门海域"
	title.add_theme_font_size_override("font_size", 27)
	title.add_theme_font_override("font", Parchment.title_font())
	title.add_theme_color_override("font_color", Parchment.CINNABAR)
	column.add_child(title)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 18)
	_status.add_theme_color_override("font_color", Parchment.INK)
	column.add_child(_status)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_pause = _button(buttons, "暂停", func(): command_requested.emit({"type": "pause"}))
	_assist = _button(buttons, "均衡操船", func(): command_requested.emit({"type": "assist"}))
	_button(buttons, "船长视角", func(): view_requested.emit(false))
	_button(buttons, "高位海图", func(): view_requested.emit(true))
	var hint := Label.new()
	hint.text = "W/S 升帆与收帆 · A/D 转舵 · Q/E 调帆\n空格 暂停 · 1/2 镜头 · F12 截图"
	hint.add_theme_color_override("font_color", Parchment.MUTED)
	column.add_child(hint)

func _button(parent: Control, label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(92, 38)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func apply_snapshot(state: Dictionary) -> void:
	if not _status or state.is_empty(): return
	var ship: Dictionary = state.ship
	var speed := sqrt(float(ship.velocity.x) ** 2 + float(ship.velocity.z) ** 2) * 1.943844
	_status.text = "航向 %03d°   航速 %.1f 节\n帆面 %d%%   帆角 %d°   风速 %.0f m/s" % [fposmod(rad_to_deg(ship.heading), 360), speed, int(ship.sailDeployment * 100), int(rad_to_deg(ship.sailAngle)), state.wind.speed]
	_pause.text = "继续" if state.paused else "暂停"
	_assist.text = "均衡操船" if state.assisted else "真实操船"
