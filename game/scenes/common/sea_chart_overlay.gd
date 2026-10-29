extends CanvasLayer
## Scene-owned compact view. A click requests the career's existing chart page.
signal chart_requested
const Chart = preload("res://game/ui/charts/nautical_chart.gd")
const Frame = preload("res://game/ui/charts/floating_chart_frame.gd")
const Maritime = preload("res://game/ui/shared/maritime_art_theme.gd")
var chart: Control
var _blocked := false
var _disposed := false
func _ready() -> void:
	layer = 22
	chart = Chart.new(); chart.name = "minimap"; add_child(chart)
	var frame := Frame.new(); frame.name = "minimap_frame"; add_child(frame); move_child(frame, chart.get_index())
	frame.follow(chart, Maritime.window_edge())
	chart.chart_requested.connect(func(): chart_requested.emit())
	get_viewport().size_changed.connect(_layout)
	_layout()
func configure(ports: Array, height_sampler: Callable, options: Dictionary = {}) -> bool:
	var settings := options.duplicate(true)
	settings.compact = true; settings.title = "近海航图"
	return chart.configure(ports,height_sampler,settings)
func present(native: Dictionary, overlays: Dictionary = {}, blocked: bool = false) -> void:
	if _disposed: return
	_blocked = blocked
	chart.apply_naval_snapshot(native,navigation_overlays(native,overlays))
	_layout()
static func navigation_overlays(native: Dictionary, overlays: Dictionary = {}) -> Dictionary:
	var marks := overlays.duplicate(true)
	if not marks.get("waypoint") is Dictionary or marks.waypoint.is_empty():
		marks.waypoint = {}
		for ship: Dictionary in native.get("ships",[]):
			if ship.get("id") == native.get("playerId") and ship.get("navigation") is Dictionary:
				marks.waypoint = ship.navigation.duplicate(true)
	return marks
func _layout() -> void:
	if not chart: return
	var viewport := chart.get_viewport_rect().size
	# The existing career HUD is 430px wide. Narrow windows retain the full chart
	# through its regular navigation button, without a second overlapping HUD.
	chart.visible = not _disposed and not _blocked and viewport.x>=820 and viewport.y>=480
	var width := clampf(viewport.x*0.18,230,290)
	chart.size = Vector2(width,width+33)
	chart.position = Vector2(viewport.x-width-18,18)
func dispose() -> void:
	if _disposed: return
	_disposed = true
	if chart: chart.dispose(); chart.hide()
func _exit_tree() -> void: dispose()
