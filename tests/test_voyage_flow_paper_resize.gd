extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	await process_frame; await process_frame; await process_frame; await process_frame
func resize_connections(viewport: Viewport, demo: Node) -> int:
	return viewport.size_changed.get_connections().filter(func(connection): return connection.callable.get_object() == demo).size()
func run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960,640)
	root.add_child(viewport)
	var original_connections := viewport.size_changed.get_connections().size()
	var demo = load("res://game/research/demos/voyage_flow_experiment.gd").new()
	demo.configure({"preset":"partial"})
	viewport.add_child(demo)
	await settle()
	demo.advance(1.0/32.0)
	var before: Dictionary = demo.inspection_snapshot()
	var paper: Control = demo.find_child("VoyageFlowPaper",true,false)
	var label: Label = demo.find_child("VoyageFlowFixture",true,false)
	var wide_height := paper.size.y
	check(paper.get_rect().end.x <= 936, "wide paper fits its owning viewport")
	check(resize_connections(viewport,demo) == 1, "one resize subscription follows the owning viewport")
	viewport.size = Vector2i(360,640)
	await settle()
	check(paper.position.x >= 24 and paper.get_rect().end.x <= 336, "splitter narrowing retains both paper gutters")
	check(label.size.x <= paper.size.x-40 and paper.size.y > wide_height, "narrowed paper reflows text instead of clipping its original width")
	check(demo.inspection_snapshot().state == before.state and demo.inspection_snapshot().tick == before.tick, "resize leaves fixture and clock unchanged")
	viewport.size = Vector2i(960,640)
	await settle()
	check(is_equal_approx(paper.size.y,wide_height) and paper.get_rect().end.x <= 936, "restoring viewport width restores compact text height")
	for iteration in 3:
		check(demo.configure({"preset":"partial"}).ok, "repeat configure accepts the same fixture")
		await settle()
		check(resize_connections(viewport,demo) == 1, "repeat configure retains one resize listener")
		check(demo.get_child_count() == 1, "repeat configure retains one paper owner")
		demo.dispose()
		check(viewport.size_changed.get_connections().size() == original_connections, "dispose disconnects viewport resize listener")
		check(demo.get_child_count() == 0, "dispose frees paper and text")
		viewport.size = Vector2i(400+iteration*20,640)
		await settle()
		check(not demo.inspection_snapshot().ready, "post-dispose resize cannot resurrect presentation")
	viewport.free()
	await process_frame
	print("VOYAGE_FLOW_PAPER_RESIZE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
