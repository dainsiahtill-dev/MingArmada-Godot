extends "res://game/ui/charts/nautical_chart.gd"
## Current-1650 adapter. Shared chart owns presentation; native snapshot owns contacts.
signal point_requested(point: Dictionary)
const GEOGRAPHY = "res://game/data/mingqi_geography.json"
var vessels: Dictionary = {}
var ports: Dictionary = {}
var routes: Dictionary = {}
var selected_id := ""

func _ready() -> void:
	super._ready()
	custom_minimum_size = Vector2(360, 280)
	waypoint_requested.connect(func(point): point_requested.emit(point.duplicate(true)))

func configure_geography(height_sampler: Callable) -> bool:
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string(GEOGRAPHY))
	# Stable geography window includes every native island and source campaign route.
	# Radius sizes the window only; sampled Scene height supplies every coastline.
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for port: Dictionary in geography:
		var center := Vector2(float(port.islandX), float(port.islandZ))
		var extent := Vector2.ONE * (float(port.radius) + 90.0)
		minimum = minimum.min(center - extent)
		maximum = maximum.max(center + extent)
	return configure(geography, height_sampler, {"bounds": Rect2(minimum, maximum-minimum), "title": "厦金沿海航图"})

func apply_data(current: Dictionary, harbors: Dictionary, lanes: Dictionary, selected: String) -> void:
	# Retained interface boundary for route/trade presentation. Never synthesize ships.
	vessels = current.duplicate(true)
	ports = harbors.duplicate(true)
	routes = lanes.duplicate(true)
	selected_id = selected

func apply_packet(packet: Dictionary) -> void:
	var campaign: Dictionary = packet.get("campaign", {})
	var native: Dictionary = packet.get("naval", {}).duplicate(true)
	# Recorded native fixtures omit playerId; campaign identity supplies no pose.
	if not native.has("playerId"): native.playerId = campaign.get("flagshipId", "")
	var overlay_routes: Array = []
	for route: Dictionary in routes.values():
		overlay_routes.append({"points": route.get("points", []).duplicate(true), "minimumDepth": route.get("minimumDepth", 0)})
	apply_naval_snapshot(native, {"routes": overlay_routes, "selectedShipId": selected_id})
