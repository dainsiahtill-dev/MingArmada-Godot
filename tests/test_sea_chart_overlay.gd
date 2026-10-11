extends SceneTree
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
var failures := 0
var assertions := 0
var requests := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var path := "res://game/scenes/common/sea_chart_overlay.gd"
	var script = load(path) if ResourceLoader.exists(path) else null
	check(script != null,"a shared native minimap must be available to both sea scenes")
	if script:
		root.size = Vector2i(1600,900)
		var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
		var heights := Height.new(); heights.configure_ports(ports)
		var overlay = script.new(); root.add_child(overlay)
		check(overlay.configure(ports,heights.sample_height),"minimap uses the same height field as the actual ocean scene")
		overlay.chart_requested.connect(func(): requests += 1)
		var native := {"playerId":"test-flagship","ships":[{"id":"test-flagship","team":"player","visual":{"position":{"x":0.0,"z":200.0},"heading":0.0},"navigation":{"x":282.0,"z":107.0}}]}
		overlay.present(native)
		await process_frame
		check(overlay.chart.visible and overlay.chart.get_global_rect().end.x<=1600 and overlay.chart.get_global_rect().position.x>430,"wide minimap stays inside the viewport and clear of the left HUD")
		check(overlay.chart.view_bounds().get_center()==Vector2(0,200),"compact map centers on the current native flagship")
		check(overlay.chart._overlays.waypoint==native.ships[0].navigation,"route marker uses the actual native navigation target")
		var point: Vector2 = overlay.chart.map_rect().get_center()
		var click := InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=overlay.chart.global_position+point
		Input.parse_input_event(click); await process_frame
		check(requests==1,"actual Control input opens the expanded chart once")
		check(not native.ships[0].has("input") and native.ships[0].navigation.x==282.0,"minimap click does not directly mutate the fleet")
		native.ships[0].visual.position.x=150.0
		overlay.present(native,{},true)
		check(not overlay.chart.visible and overlay.chart.view_bounds().get_center()==Vector2(150,200),"modal hides minimap while native position remains synchronized")
		root.size=Vector2i(640,480); root.content_scale_size=root.size; await process_frame
		overlay.present(native)
		check(not overlay.chart.visible,"small viewport avoids overlapping the existing HUD")
		root.size=Vector2i(1280,720); root.content_scale_size=root.size; await process_frame
		overlay.present(native)
		check(overlay.chart.visible and overlay.chart.get_global_rect().end.y<=720,"resizing restores a bounded usable map")
		overlay.dispose(); overlay.present(native)
		check(not overlay.chart.visible and overlay.chart._native.is_empty(),"disposed view releases terrain and fleet snapshot references")
		overlay.queue_free(); await process_frame
	print("SEA_CHART_OVERLAY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
