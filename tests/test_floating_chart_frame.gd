extends SceneTree
## Floating frames preserve chart ownership, geometry and actual viewport input.
const Overlay = preload("res://game/scenes/common/sea_chart_overlay.gd")
const Practice = preload("res://game/ui/naval_practice.gd")
const Runtime = preload("res://game/runtime/naval_practice_runtime.gd")
var assertions := 0
var failures := 0
var requests := 0
var commands: Array = []

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL floating chart frame: ", detail)

func _initialize() -> void: _run.call_deferred()

func _frames() -> void:
	for frame in 5: await process_frame

func _click(point: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = point
	motion.global_position = point
	root.push_input(motion, true)
	for pressed: bool in [true, false]:
		var event := InputEventMouseButton.new()
		event.position = point
		event.global_position = point
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame

func _verify_frame(frame: Control, chart: Control, label: String) -> void:
	check(frame != null and frame.is_visible_in_tree(), label + " has a visible external painted frame")
	if frame == null: return
	check(frame.get_parent() == chart.get_parent() and frame.get_index() < chart.get_index(), label + " frame is a sibling behind the unchanged chart path")
	check(frame.get_global_rect().is_equal_approx(chart.get_global_rect()), label + " frame mirrors body geometry without expanding its hit area")
	check(not frame.clip_contents and chart.clip_contents, label + " external edge escapes only its own unclipped canvas")
	check(frame.mouse_filter == Control.MOUSE_FILTER_IGNORE and frame.focus_mode == Control.FOCUS_NONE, label + " frame cannot intercept map or world input")
	check(frame.custom_minimum_size == Vector2.ZERO, label + " decoration does not change native minimum size")
	var edge: Variant = frame.get("edge")
	check(edge is StyleBoxTexture and edge.texture != null and not edge.draw_center, label + " uses actual generated edge texture without another reading surface")
	if edge is StyleBoxTexture:
		check([SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM].all(func(side): return edge.get_expand_margin(side) > 0), label + " frame drawing expands beyond all four clipped map edges")

func _run() -> void:
	root.content_scale_size = Vector2i.ZERO
	root.size = Vector2i(1600, 900)
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var height := func(_x: float, _z: float) -> float: return -24.0
	var overlay := Overlay.new()
	root.add_child(overlay)
	check(overlay.configure(ports, height), "compact chart configures through original API")
	overlay.chart_requested.connect(func(): requests += 1)
	overlay.present({"playerId": "flag", "ships": [{"id": "flag", "team": "player", "visual": {"position": {"x": 0.0, "z": 200.0}, "heading": 0.0}}]})
	await _frames()
	check(overlay.get_node("minimap") == overlay.chart, "compact map keeps original direct node path")
	check(overlay.chart.get_rect() == Rect2(1294, 18, 288, 321) and overlay.chart.custom_minimum_size == Vector2(160, 230), "compact map keeps original position, size and minimum")
	var compact_frame := overlay.get_node_or_null("minimap_frame") as Control
	_verify_frame(compact_frame, overlay.chart, "compact map")
	await _click(overlay.chart.global_position + overlay.chart.map_rect().get_center())
	check(requests == 1, "actual viewport click still opens the existing chart once")
	await _click(overlay.chart.get_global_rect().position + Vector2(-4, 80))
	check(requests == 1 and (compact_frame == null or root.gui_get_hovered_control() != compact_frame), "outside painted edge owns no click or navigation")
	overlay.present({}, {}, true)
	check(compact_frame == null or not compact_frame.visible, "modal hides both the compact chart and external edge")
	root.size = Vector2i(1280, 720)
	await _frames()
	overlay.present({})
	if compact_frame: check(compact_frame.visible and compact_frame.get_global_rect().is_equal_approx(overlay.chart.get_global_rect()), "compact frame follows restored viewport layout")
	overlay.dispose()
	check(compact_frame == null or not compact_frame.visible, "disposed compact chart leaves no visible frame")
	overlay.queue_free()
	await _frames()
	var runtime := Runtime.new()
	check(runtime.configure(height, {"mode": "duel"}).ok, "actual practice runtime configures")
	var hud := Practice.new()
	root.add_child(hud)
	check(hud.configure_chart(ports, height), "expanded practice chart uses original configuration")
	hud.command_requested.connect(func(intent: Dictionary):
		commands.append(intent.duplicate(true))
		if intent.get("type") == "chart": runtime.set_pause("chart", bool(intent.get("value", false)))
		else: runtime.command(intent)
		hud.apply_snapshot(runtime.snapshot()))
	hud.apply_snapshot(runtime.snapshot())
	var practice_frame := hud.get_node_or_null("PracticeScreen/PracticeChartFrame") as Control
	check(hud.get_node("PracticeScreen/PracticeChart") == hud.chart and hud.chart.get_node("close_chart") == hud.find_child("close_chart", true, false), "expanded chart and close button keep original parent paths")
	check(not hud.chart.visible and (practice_frame == null or not practice_frame.visible), "expanded map frame starts hidden with the chart")
	runtime.set_pause("chart", true)
	check("chart" in runtime.snapshot().runtime.pauseReasons, "original chart pause opens expanded chart")
	hud.apply_snapshot(runtime.snapshot())
	await _frames()
	_verify_frame(practice_frame, hud.chart, "expanded practice chart")
	check(hud.chart.get_rect() == Rect2(160, 110, 960, 500) and hud.chart.custom_minimum_size == Vector2(160, 500), "expanded chart keeps original centered dimensions and minimum: " + str(hud.chart.get_rect()) + " / " + str(hud.chart.custom_minimum_size))
	var close: Control = hud.chart.get_node("close_chart")
	await _click(close.get_global_rect().get_center())
	await _frames()
	check(commands.size() == 1 and commands[0] == {"type": "chart", "value": false} and not runtime.is_paused(), "real viewport close still sends only the original chart intent")
	check(not hud.chart.visible and (practice_frame == null or not practice_frame.visible), "native close hides both expanded map and external edge")
	hud.free()
	runtime.dispose()
	await process_frame
	print("FLOATING_CHART_FRAME_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
