extends SceneTree
class ProjectionCountChart:
	extends "res://game/ui/charts/nautical_chart.gd"
	var player_reads := 0
	func _player() -> Dictionary:
		player_reads+=1
		return super._player()
var failures := 0
var assertions := 0
var samples := 0
var waypoints: Array = []
var opens := 0
func check(value, message):
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", message)
func _initialize(): call_deferred("run")
func height(x, z):
	samples += 1
	return (x - 80.0 - z * 0.2) * 0.1
func run():
	var path = "res://game/ui/charts/nautical_chart.gd"
	check(ResourceLoader.exists(path), "new chart with sampled coastline exists")
	if not ResourceLoader.exists(path): finish(); return
	var script = load(path)
	check(script != null and script.can_instantiate(), "chart compiles")
	if not script or not script.can_instantiate(): finish(); return
	var chart = script.new(); root.add_child(chart); chart.size = Vector2(600, 420)
	await process_frame
	var ports = [{"id":"real-port","name":"厦门","x":130.0,"z":100.0,"radius":200.0,"islandX":-400,"islandZ":-400}]
	var bounds = Rect2(-300,-200,600,400)
	check(chart.configure(ports, height, {"bounds":bounds}), "real immutable sampler configures")
	await process_frame
	var cached_mesh = chart._land_mesh
	var rect: Rect2 = chart.map_rect()
	check(rect.position.x > 0 and rect.position.y > 0 and rect.end.x < 600 and rect.end.y < 420, "frame never claims navigable pixels")
	var origin = chart.projected({"x":-300,"z":-200})
	check(origin.is_equal_approx(rect.position), "northwest world bound reaches interior northwest")
	var center = chart.projected({"x":0,"z":0})
	check(center.is_equal_approx(rect.get_center()), "independent world center projects to map center")
	var back: Dictionary = chart.unprojected(chart.projected({"x":123.25,"z":-84.5}))
	check(absf(back.x-123.25)<0.001 and absf(back.z+84.5)<0.001, "projection round trip retains canonical point")
	check(not chart._coast_segments.is_empty(), "height source creates actual coastline")
	for edge in chart._coast_segments:
		for point in edge:
			check(absf(point.x-80.0-point.y*0.2)<0.01, "coast follows asymmetric linear height, never island radius")
	check(not chart._land_polygons.is_empty() and not chart._shoal_polygons.is_empty(), "land and underwater shoals derive same source height")
	var native = {"time":42.0,"playerId":"self","ships":[{"id":"self","team":"player","visual":{"position":{"x":25.0,"y":2,"z":-10.0},"heading":PI/2}},{"id":"enemy","team":"hostile","visual":{"position":{"x":150.0,"y":0,"z":50.0},"heading":0}},{"id":"trader","team":"neutral","visual":{"position":{"x":-80.0,"y":0,"z":80.0},"heading":0}}]}
	var overlay = {"activeObjectives":[{"label":"航点","position":{"x":0,"z":0}}],"waypoint":{"x":200,"z":100}}
	var original = native.duplicate(true); var initial_samples = samples
	chart.apply_naval_snapshot(native, overlay)
	native.ships[0].visual.position.x = 9999; ports[0].x = 9999; overlay.waypoint.x = 9999
	check(chart._native.ships[0].visual.position.x==25 and chart._ports[0].x==130 and chart._overlays.waypoint.x==200, "snapshots and ports detached at boundary")
	var marks: Array = chart.ship_marks()
	check(marks.size()==3 and marks[0].flagship and marks[0].position==Vector2(25,-10), "flagship takes actual native position")
	check(marks[0].direction.is_equal_approx(Vector2(0,1)) and marks[1].role=="hostile" and marks[2].role=="trade", "heading/team interpreted from native source")
	var selected_overlay = {"selectedShipId":"enemy"}
	chart.apply_naval_snapshot(original,selected_overlay)
	selected_overlay.selectedShipId="self"
	var selected_marks: Array = chart.ship_marks()
	check(selected_marks[1].get("selected",false) and not selected_marks[1].flagship, "campaign selection highlights real enemy independently of native flagship")
	check(selected_marks[0].flagship and not selected_marks[0].get("selected",false) and chart._native.playerId=="self", "selected enemy never replaces native flagship authority")
	check(chart._overlays.selectedShipId=="enemy", "selected contact overlay detached from caller mutation")
	chart.apply_naval_snapshot(original,{"selectedShipId":"unknown-contact"})
	check(chart.ship_marks().all(func(mark):return not mark.get("selected",false)) and chart.ship_marks().size()==3, "unknown selected id creates no fake contact or highlight")
	chart.waypoint_requested.connect(func(point): waypoints.append(point))
	chart.chart_requested.connect(func(): opens += 1)
	click(chart, chart.projected({"x":0,"z":0}))
	check(waypoints.size()==1 and absf(waypoints[0].x)<0.001 and absf(waypoints[0].z)<0.001, "actual expanded Control click emits canonical point")
	click(chart, Vector2(2,2)); click(chart, Vector2(-50,-50)); click(chart, Vector2(700,700))
	check(waypoints.size()==1 and opens==0, "frame/outside clicks cannot issue navigation")
	for frame in 8: chart.apply_naval_snapshot(original, {}); await process_frame
	check(samples==initial_samples, "paused redraw/snapshot never resamples cached terrain")
	check(chart._land_mesh==cached_mesh, "stationary land mesh reused while ship marks redraw")
	chart.size = Vector2(900,550); await process_frame
	check(samples==initial_samples and chart.projected({"x":0,"z":0}).is_equal_approx(chart.map_rect().get_center()), "resize updates projection without height work")
	check(chart.configure([{"id":"real-port","name":"厦门","x":130,"z":100}], height, {"compact":true,"span":1100}), "compact chart configures")
	chart.apply_naval_snapshot(original)
	check(chart.projected({"x":25,"z":-10}).is_equal_approx(chart.map_rect().get_center()), "compact map follows real flagship")
	check(chart.view_bounds().size.is_equal_approx(Vector2(1100,1100)), "compact map canonical metric span")
	var compact_samples = samples
	for frame in 4: chart.apply_naval_snapshot(original); await process_frame
	check(samples==compact_samples, "compact stationary frame retains sampler cache")
	click(chart, chart.map_rect().get_center())
	check(opens==1 and waypoints.size()==1, "compact actual Control opens chart, never navigates")
	var far = original.duplicate(true); far.ships[0].visual.position={"x":5000,"z":-5000}; chart.apply_naval_snapshot(far)
	check(chart.projected({"x":5000,"z":-5000}).is_equal_approx(chart.map_rect().get_center()), "off-world focus remains centered with real sampled land")
	check(chart._height_cache.size()<=chart.CACHE_LIMIT, "moving compact sampler cache has finite budget")
	check(chart.ship_marks().size()==1, "off-map enemies hidden instead of clipped to false position")
	for step in 18:
		far.ships[0].visual.position={"x":10000+step*2000,"z":10000+step*2000}
		var before_samples = samples
		chart.apply_naval_snapshot(far)
		check(samples-before_samples<=1600 and chart._height_cache.size()<=chart.CACHE_LIMIT, "long voyage enforces per-window sample and total cache budget")
	check(original.time==42 and original.ships[0].visual.position.x==25, "interaction never mutates authority or clock")
	chart.dispose(); check(chart._height_cache.is_empty() and chart._native.is_empty() and not chart._height.is_valid(), "dispose releases detached snapshots and sampler")
	check(not chart.configure([], height, {"bounds":Rect2(0,0,3900,300)}), "oversized request rejected before unbounded sampling")
	check(not chart.configure([], height, {"bounds":Rect2(Vector2(NAN,0),Vector2(200,200))}), "nonfinite bounds rejected")
	check(not chart.configure([], Callable()), "missing terrain authority rejected")
	await verify_real_geography(chart)
	await verify_legacy_wrapper()
	await verify_expanded_container()
	await verify_mesh_projection_budget()
	await verify_chart_materials()
	await verify_port_label_layout()
	chart.free(); await process_frame
	finish()
func verify_chart_materials():
	var chart = load("res://game/ui/charts/nautical_chart.gd").new(); root.add_child(chart)
	chart.size=Vector2(600,420); chart.configure([],height,{"compact":true,"span":600})
	var native = {"playerId":"actual","ships":[{"id":"actual","visual":{"position":{"x":0,"z":0},"heading":0}}]}
	chart.apply_naval_snapshot(native); await process_frame
	var polygon = PackedVector2Array([Vector2(-120,-60),Vector2(90,-60),Vector2(90,120)])
	var mesh = chart._terrain_mesh([polygon])
	var arrays: Array = mesh.surface_get_arrays(0)
	var original_uvs = arrays[Mesh.ARRAY_TEX_UV]
	check(original_uvs is PackedVector2Array and original_uvs.size()==3, "terrain mesh provides one material UV for every actual clipped vertex")
	if original_uvs is PackedVector2Array and original_uvs.size()==3:
		check(original_uvs[0].x<0 and original_uvs[0].y<0 and original_uvs[2].x>0 and original_uvs[2].y>0, "land grain spans world origin instead of restarting in each polygon")
		chart.size=Vector2(900,500); await process_frame
		var resized_uvs = chart._terrain_mesh([polygon]).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		check(original_uvs==resized_uvs, "resizing chart preserves texture coordinates on same real world points")
		native.ships[0].visual.position={"x":23.5,"z":-17.25}; chart.apply_naval_snapshot(native)
		var moved_uvs = chart._terrain_mesh([polygon]).surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		check(original_uvs==moved_uvs, "compact follow camera preserves world paper grain without swimming")
		chart.apply_naval_snapshot({"playerId":"actual","ships":[{"id":"actual","visual":{"position":{"x":0,"z":0}}}]})
		var crossing = chart._terrain_mesh([PackedVector2Array([Vector2(-360,-120),Vector2(-180,-120),Vector2(-180,120),Vector2(-360,120)])])
		var reference = chart._terrain_mesh([PackedVector2Array([Vector2(-300,-120),Vector2(-180,-120),Vector2(-180,120)])])
		var crossing_arrays: Array = crossing.surface_get_arrays(0); var reference_uvs = reference.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
		var edge_pixel: Vector2 = chart.projected({"x":-300,"z":-120}); var same_grain := false
		for i in crossing_arrays[Mesh.ARRAY_VERTEX].size():
			if crossing_arrays[Mesh.ARRAY_VERTEX][i].is_equal_approx(edge_pixel): same_grain=crossing_arrays[Mesh.ARRAY_TEX_UV][i].is_equal_approx(reference_uvs[0])
		check(same_grain, "new boundary intersections keep same world UV as adjacent interior geometry")
	check(chart.has_method("_load_texture"), "chart material loader supports missing-resource fallback")
	if chart.has_method("_load_texture"):
		check(chart._load_texture("res://assets/art/maps/missing-chart-material.png")==null, "absent material yields native fallback without load error")
		check(chart._load_texture("res://game/ui/charts/nautical_chart.gd")==null, "non-texture resource cannot become chart material")
		check(chart._background is Texture2D and chart._background==chart._load_texture(chart.BACKGROUND), "imported v2 ornament plate loads through guarded resource path")
		check(chart._land_paper is Texture2D, "imported land paper loads separately from sea ornament")
		check(chart._fallback_land_paper is Texture2D, "native land material stays available when generated paper is missing")
		await process_frame
		var stable_samples := samples; var stable_mesh = chart._land_mesh
		chart._land_paper=null; chart.queue_redraw(); await process_frame
		check(samples==stable_samples and chart._land_mesh==stable_mesh, "native land fallback reuses same terrain and mesh without sampling")
	chart.free(); await process_frame
func verify_port_label_layout():
	var chart = load("res://game/ui/charts/nautical_chart.gd").new(); root.add_child(chart); chart.size=Vector2(290,323)
	var ports = [{"id":"far","name":"远港","x":240,"z":40},{"id":"near","name":"近港","x":30,"z":0},{"id":"cluster-a","name":"甲港","x":30,"z":0},{"id":"cluster-b","name":"乙港","x":30,"z":0},{"id":"edge","name":"外港","x":-510,"z":-500}]
	chart.configure(ports,height,{"compact":true,"span":1100})
	chart.apply_naval_snapshot({"playerId":"actual","ships":[{"id":"actual","visual":{"position":{"x":0,"z":0}}}]}); await process_frame
	check(chart.has_method("_port_labels"), "port labels can resolve crowded live geography before drawing")
	if chart.has_method("_port_labels"):
		var labels: Array = chart._port_labels([])
		check(not labels.is_empty() and labels[0].port_id=="near", "nearest real harbor has label priority independent of catalog order")
		var separated := true; var contained := true
		for i in labels.size():
			contained=contained and chart.map_rect().encloses(labels[i].box)
			for j in range(i): separated=separated and not labels[i].box.intersects(labels[j].box)
		check(separated and contained and labels.size()<=3, "compact port labels remain distinct and fully inside actual chart frame")
		var reserved: Array = [chart.map_rect()]
		check(chart._port_labels(reserved).is_empty(), "occupied navigation annotations suppress overlapping harbor text")
		check(ports[0].id=="far" and chart._ports[0].id=="far", "label priority sorting never mutates canonical port order")
	chart.free(); await process_frame
func verify_expanded_container():
	var column = VBoxContainer.new(); column.position=Vector2(0,0); column.size=Vector2(622,600); root.add_child(column)
	var expanded = load("res://game/ui/charts/nautical_chart.gd").new(); column.add_child(expanded)
	check(expanded.configure([],height), "expanded chart configures in actual VBox container")
	for frame in 8: await process_frame
	check(absf(expanded.size.x-622)<1, "actual VBox allocates wide 622 pixel chart")
	check(expanded.map_rect().size.x>=500, "wide expanded chart uses at least 500 pixels for actual geography")
	check(expanded.custom_minimum_size.y>=300 and expanded.custom_minimum_size.y<=500, "expanded intrinsic height has bounded viewport budget")
	var stable_samples = samples; var stable_size: Vector2 = expanded.size
	for frame in 8: await process_frame
	check(expanded.size==stable_size and samples==stable_samples, "intrinsic layout settles without resize cycle or terrain resampling")
	column.size.x=430
	for frame in 8: await process_frame
	check(expanded.custom_minimum_size.y>=300 and expanded.custom_minimum_size.y<=500 and expanded.map_rect().size.x>=380, "narrower expanded allocation preserves geography aspect and width")
	check(samples==stable_samples, "responsive expanded height never calls terrain authority")
	expanded.configure([],height,{"bounds":Rect2(-500,-300,1100,700)})
	for frame in 8: await process_frame
	check(expanded.custom_minimum_size.y==332 and expanded.map_rect().size.x>=380, "430 pixel campaign allocation derives 332 pixel height from actual 1100 by 700 world aspect")
	expanded.configure([],height,{"compact":true,"span":1100}); column.remove_child(expanded); root.add_child(expanded); expanded.size=Vector2(290,323)
	for frame in 4: await process_frame
	check(expanded.size==Vector2(290,323), "compact configured root size remains exactly 290 by 323")
	expanded.free(); column.free(); await process_frame
func verify_mesh_projection_budget():
	var chart = ProjectionCountChart.new(); root.add_child(chart)
	chart.configure([],height,{"compact":true,"span":1100}); chart.size=Vector2(290,323)
	chart.apply_naval_snapshot({"playerId":"actual","ships":[{"id":"actual","visual":{"position":{"x":123.5,"z":-45.5},"heading":0}}]})
	var polygons: Array = []
	for i in 20:
		polygons.append(PackedVector2Array([Vector2(100+i,-40),Vector2(120+i,-40),Vector2(120+i,-20),Vector2(100+i,-20)]))
	chart.player_reads=0
	var mesh = chart._terrain_mesh(polygons)
	check(chart.player_reads<=2 and mesh.get_surface_count()==1, "one mesh derives native focus at most twice instead of scanning player per vertex")
	var bounds: Rect2 = chart.view_bounds(); var rect: Rect2 = chart.map_rect()
	var northwest: Vector2 = bounds.position; var southeast: Vector2 = bounds.end
	var inside_mesh = chart._terrain_mesh([PackedVector2Array([bounds.get_center(),Vector2(southeast.x,bounds.get_center().y),southeast])])
	var vertices = Array(inside_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX])
	check(vertices.size()==3 and vertices.any(func(point):return point.is_equal_approx(rect.get_center())) and vertices.any(func(point):return point.is_equal_approx(Vector2(rect.end.x,rect.get_center().y))) and vertices.any(func(point):return point.is_equal_approx(rect.end)), "interior mesh maps exact center and inclusive boundary coordinates")
	var outside_mesh = chart._terrain_mesh([PackedVector2Array([northwest-Vector2(100,100),northwest-Vector2(20,100),northwest-Vector2(20,20)])])
	check(outside_mesh.get_surface_count()==0, "entirely off-map polygon produces no drawing surface")
	var crossing_mesh = chart._terrain_mesh([PackedVector2Array([northwest-Vector2(50,50),Vector2(northwest.x+100,northwest.y-50),northwest+Vector2(100,100),Vector2(northwest.x-50,northwest.y+100)])])
	var clipped := true
	for point in crossing_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if not rect.grow(0.01).has_point(point): clipped=false
	check(clipped and crossing_mesh.get_surface_count()==1, "boundary-crossing polygon still clips exactly to frame")
	chart.free(); await process_frame
func verify_real_geography(chart):
	var catalog = load("res://game/domain/legacy/catalog.gd").DATA
	var field = load("res://modules/scene_engine/terrain/height_field.gd").new()
	check(field.configure_ports(catalog.PORTS), "production legacy height authority configures")
	check(chart.configure(catalog.PORTS,field.sample_height), "canonical ports and actual Scene sampler configure chart")
	await process_frame
	var mesh_clipped := true
	if chart._land_mesh.get_surface_count()>0:
		for point in chart._land_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			if not chart.map_rect().grow(0.01).has_point(point): mesh_clipped=false
	check(mesh_clipped, "actual batched land mesh clips every vertex inside navigable frame")
	check(not chart._coast_segments.is_empty(), "production geography has real sampled coast")
	var outside_radius := false
	for edge in chart._coast_segments:
		for point in edge:
			check(absf(field.sample_height(point.x,point.y))<2.0, "production chart coastline follows interpolated zero elevation")
			for port in catalog.PORTS:
				if Vector2(port.islandX,port.islandZ).distance_to(point)<port.radius-20 and Vector2(port.islandX,port.islandZ).distance_to(point)>port.radius*0.45: outside_radius=true
	check(outside_radius, "actual geological coastline differs from catalog decorative island radius")
	var clip = chart._clip_line(Vector2(-1000,-1000),Vector2(10000,10000))
	check(clip.size()==2 and chart.map_rect().grow(0.01).has_point(clip[0]) and chart.map_rect().grow(0.01).has_point(clip[1]), "actual draw-line clipping confines off-map segments to map interior")
func verify_legacy_wrapper():
	var wrapper = load("res://game/ui/legacy/legacy_chart.gd").new(); root.add_child(wrapper); await process_frame
	wrapper.size=Vector2(640,440); check(wrapper.configure([],height), "legacy wrapper accepts existing geography configuration")
	var adventure = {"fleet":[{"id":"fake-adventure","position":{"x":999,"z":999}}],"position":{"x":999,"z":999},"activeObjectives":[{"position":{"x":23,"z":42},"label":"目标"}]}
	wrapper.apply_snapshot(adventure); adventure.activeObjectives[0].position.x=999
	check(wrapper.snapshot.activeObjectives[0].position.x==23 and wrapper._overlays.activeObjectives[0].position.x==23, "legacy adventure overlays stay detached")
	check(wrapper.ship_marks().is_empty(), "legacy fleet cannot replace actual native ship authority")
	var runtime = load("res://game/runtime/legacy_runtime.gd").new()
	check(runtime.configure(height,{"initialDock":false}).ok, "real default LegacyRuntime configures")
	var packet: Dictionary = runtime.snapshot()
	wrapper.apply_snapshot(packet.adventure)
	wrapper.apply_naval_snapshot(packet.naval,{"waypoint":packet.adventure.get("waypoint"),"activeObjectives":null})
	check(wrapper._overlays.waypoint is Dictionary and wrapper._overlays.activeObjectives is Array, "canonical inactive null waypoint/objectives normalized for drawing")
	await process_frame
	runtime.dispose()
	wrapper.free(); await process_frame
func click(chart, point):
	var event = InputEventMouseButton.new(); event.position=point; event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true
	chart._gui_input(event)
func finish():
	print("NAUTICAL_CHART_TESTS assertions=", assertions, " failures=", failures, " samples=", samples)
	quit(1 if failures else 0)
