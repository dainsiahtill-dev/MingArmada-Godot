extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var path := "res://game/ui/charts/world_atlas.gd"
	check(ResourceLoader.exists(path), "a geographic world atlas exists independently of the local metre chart")
	if not ResourceLoader.exists(path): _finish(); return
	var script = load(path)
	check(script != null and script.can_instantiate(), "world atlas compiles")
	if script == null or not script.can_instantiate(): _finish(); return
	var staged=script.new(); staged.startup_options={"staged":true}; staged.hide(); staged.process_mode=Node.PROCESS_MODE_DISABLED; root.add_child(staged)
	await process_frame
	check(staged.startup_receipt.ok and not staged.visible and staged.size==root.get_visible_rect().size, "staged route becomes ready while hidden and fills logical viewport without leaked layers: atlas=%s viewport=%s" % [staged.size,root.get_visible_rect().size])
	staged.dispose(); staged.queue_free(); await process_frame
	var atlas = script.new(); root.add_child(atlas)
	atlas.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT); atlas.size = Vector2(1440,960)
	await process_frame
	check(atlas.configure({}).ok, "bundled geographic data configures")
	var rect: Rect2 = atlas.map_rect()
	var bounds: Rect2 = atlas.view_bounds()
	check(rect.size.x > 200 and rect.size.y > 200, "wide layout reserves a usable geographic viewport")
	var northwest: Vector2 = atlas.project(Vector2(bounds.position.x,bounds.end.y))
	check(northwest.distance_to(rect.position)<0.001, "northwest longitude latitude reaches the actual map northwest")
	for point in [Vector2(118.078071,24.451938),Vector2(129.555,33.371389),Vector2(106.827492,-6.172472),Vector2(120.980271,14.606105),Vector2(135,40)]:
		check(atlas.unproject(atlas.project(point)).distance_to(point)<0.00001, "geographic point round trips without game metre coordinates")
	check(atlas.select_port("xiamen"), "canonical geographic harbour can be selected")
	var snapshot: Dictionary = atlas.inspection_snapshot()
	check(snapshot.selected_port.id == "xiamen" and absf(snapshot.selected_port.lon-118.078071)<0.000001, "selection keeps Natural Earth point longitude")
	snapshot.selected_port.lon=0
	check(atlas.inspection_snapshot().selected_port.lon>100, "inspection cannot mutate atlas source points")
	check(not atlas.select_port("invented-city") and atlas.inspection_snapshot().selected_port.id=="xiamen", "unknown harbour never creates a fake city")
	var anchor: Vector2 = atlas.project(Vector2(124,18)); var anchored: Vector2 = atlas.unproject(anchor)
	check(atlas.zoom_at(1.5,anchor), "finite positive map zoom is accepted")
	check(atlas.unproject(anchor).distance_to(anchored)<0.00001, "zoom preserves the geographic point beneath pointer")
	var before: Rect2=atlas.view_bounds()
	check(not atlas.zoom_at(NAN,anchor) and atlas.view_bounds()==before, "nonfinite zoom is rejected without changing view")
	check(not atlas.pan_pixels(Vector2(INF,0)) and atlas.view_bounds()==before, "nonfinite pan is rejected")
	check(atlas.pan_pixels(Vector2(100000,100000)), "large finite pan is bounded")
	check(atlas.data_bounds().encloses(atlas.view_bounds()), "panning stays inside source geographic extent")
	atlas.reset_view(); atlas.zoom_at(2.0)
	var press:=InputEventMouseButton.new(); press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=atlas.map_rect().get_center(); atlas._gui_input(press)
	var release:=press.duplicate(); release.pressed=false; release.position=Vector2(-10,-10); atlas._gui_input(release)
	var released_bounds: Rect2=atlas.view_bounds()
	var motion:=InputEventMouseMotion.new(); motion.position=atlas.map_rect().get_center()+Vector2(30,10); motion.relative=Vector2(30,10); atlas._gui_input(motion)
	check(atlas.view_bounds()==released_bounds, "release outside map ends drag before later hover")
	atlas.reset_view(); atlas.size=Vector2(640,960); await process_frame
	var panel: Rect2=atlas.details_rect()
	check(panel.position.y>=atlas.map_rect().end.y and Rect2(Vector2.ZERO,atlas.size).encloses(panel), "narrow harbour details sit below map inside viewport")
	var count := [0]
	atlas.port_selected.connect(func(_point): count[0]+=1)
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;click.position=atlas.project(Vector2(120.980271,14.606105))
	atlas._gui_input(click)
	check(atlas.inspection_snapshot().selected_port.id=="manila" and count[0]==1, "actual map input selects geographic port once")
	atlas.size=Vector2(320,480); await process_frame
	var vignette: TextureRect=atlas.find_child("AtlasVignette",true,false)
	check(vignette!=null and not vignette.visible,"small atlas keeps illustrations out of the map and port controls")
	var selector: Control=atlas.find_child("HarbourSelector",true,false)
	for button_name in ["ZoomIn","ZoomOut","ResetView","ReturnFromAtlas"]:
		var tool: Control=atlas.find_child(button_name,true,false)
		check(not tool.get_rect().intersects(selector.get_rect()) and tool.get_rect().end.y<atlas.map_rect().position.y, "320px toolbar has a separate row clear of selector and map")
	check(Rect2(Vector2.ZERO,atlas.size).encloses(atlas.details_rect()), "320 by 480 harbour details remain inside the logical viewport")
	atlas.size=Vector2(1600,1000); await process_frame; await process_frame
	check(vignette.visible and vignette.texture!=null and vignette.mouse_filter==Control.MOUSE_FILTER_IGNORE,"wide folio displays generated illustration without capturing input")
	check(not vignette.get_rect().intersects(atlas.map_rect()) and not vignette.get_rect().intersects(atlas.details_rect()),"wide illustration stays clear of geographic picking and scrolling port text")
	check(atlas.details_rect().size.x<=310.1 and Rect2(Vector2.ZERO,atlas.size).encloses(atlas.details_rect()), "narrow to wide restores bounded harbour column without minimum-width feedback")
	check(atlas.find_child("FocusHarbour",true,false).get_global_rect().end.x<=atlas.size.x-20, "responsive harbour action stays within screen after narrow to wide transition")
	var state: Dictionary=atlas.inspection_snapshot()
	check(state.geometry.vertices<12000 and state.geometry.triangles<24000 and state.geometry.failed_polygons==0, "physical land uses bounded valid triangulated geometry")
	check(state.geometry.land_polygons>100, "regional land retains actual separate islands")
	check(state.geography_basis=="longitude-latitude" and not state.has("waypoint"), "atlas never invents a local or transoceanic navigation target")
	for landmark in [Vector2(114,30),Vector2(138,36),Vector2(127,39),Vector2(121,23.7),Vector2(121,16),Vector2(110,-7.5),Vector2(101,0),Vector2(114,0)]:
		check(atlas._is_land(landmark), "source geometry preserves a real mainland or major East Asian island interior")
	var returns: Array=[0]
	atlas.return_requested.connect(func(): returns[0]+=1)
	atlas.find_child("ReturnFromAtlas",true,false).pressed.emit()
	check(returns[0]==1, "native return control emits exactly one return request")
	atlas.dispose()
	check(atlas.inspection_snapshot().disposed and atlas.inspection_snapshot().geometry.vertices==0, "dispose releases atlas geometry and point references")
	atlas.queue_free(); await process_frame
	var demo_path:="res://game/research/demos/antique_cartography.gd"
	check(ResourceLoader.exists(demo_path), "cartography has an independent laboratory experiment")
	if not ResourceLoader.exists(demo_path): _finish(); return
	var demo_script=load(demo_path)
	check(demo_script!=null and demo_script.can_instantiate(), "independent experiment compiles")
	if demo_script==null or not demo_script.can_instantiate(): _finish(); return
	var demo=demo_script.new()
	check(demo.configure({"paused":false,"engraving":true}).ok, "experiment accepts controlled initial options")
	root.add_child(demo); await process_frame
	check(demo.inspection_snapshot().ready, "independent atlas builds under host viewport")
	demo.advance(0.125)
	check(demo.inspection_snapshot().tick==4 and demo.inspection_snapshot().time==0.125, "only host advance accepts fixed experiment time")
	demo.set_paused(true); demo.advance(1.0); demo.zoom_camera(-0.1); demo.orbit_camera(0.01,0.01)
	check(demo.inspection_snapshot().tick==4, "pause plus chart observation never advances accepted time")
	var vertices: int=demo.inspection_snapshot().atlas.geometry.vertices
	check(demo.set_parameter("engraving",false).ok and demo.inspection_snapshot().atlas.geometry.vertices==vertices, "baseline and engraved candidate retain identical geography")
	check(demo.reset_experiment({"paused":true,"engraving":true}).ok, "reset restores declared factors")
	var reset_state: Dictionary=demo.inspection_snapshot()
	check(reset_state.tick==0 and reset_state.atlas.zoom==1 and reset_state.atlas.selected_port.id=="xiamen", "repeat reset restores deterministic geography view and selection")
	demo.dispose()
	check(demo.inspection_snapshot().disposed and demo.inspection_snapshot().resources.atlas==0, "independent experiment releases owned atlas")
	demo.queue_free(); await process_frame
	_finish()
func _finish() -> void:
	print("WORLD_ATLAS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
