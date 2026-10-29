extends Control
## An input-free sibling can paint beyond the chart's own clipping boundary.
var edge: StyleBoxTexture
var _chart: Control

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	focus_mode = Control.FOCUS_NONE
	clip_contents = false
	hide()

func follow(chart: Control, style: StyleBoxTexture) -> void:
	_chart = chart
	edge = style
	_chart.item_rect_changed.connect(_sync)
	_chart.visibility_changed.connect(_sync)
	_chart.tree_exiting.connect(_chart_exiting)
	_sync()

func _sync() -> void:
	if not is_instance_valid(_chart):
		hide()
		return
	position = _chart.position
	size = _chart.size
	visible = _chart.visible and edge != null
	queue_redraw()

func _chart_exiting() -> void:
	_chart = null
	hide()

func _draw() -> void:
	if edge != null: draw_style_box(edge, Rect2(Vector2.ZERO, size))
