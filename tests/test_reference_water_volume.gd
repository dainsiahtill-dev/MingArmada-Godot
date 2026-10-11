extends SceneTree
## Real mesh/state contracts: missing depth, wall-clock animation, stale events,
## bow foam during reverse travel, or unbounded effects must fail this suite.
var assertions := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func _initialize() -> void: _run.call_deferred()
func _water(x: float, z: float, seconds: float) -> float: return x*0.001+z*0.002+seconds*0.5
func _sea_only(x: float, _z: float) -> bool: return x < 50.0
func _ship(x: float, heading: float, speed: float) -> Dictionary:
	return {"id":"vessel","hull":100.0,"dimensions":{"length":20.0,"width":5.0},"visual":{"position":{"x":x,"z":0.0},"heading":heading,"velocity":{"x":cos(heading)*speed,"z":sin(heading)*speed}}}
func _span(node: MeshInstance3D) -> Vector3:
	var minimum := Vector3(INF,INF,INF); var maximum := -minimum
	for v: Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]: minimum = minimum.min(v); maximum = maximum.max(v)
	return maximum-minimum
func _peak(node: MeshInstance3D) -> float:
	if not node or not node.mesh or not node.visible: return 0.0
	var peak := 0.0
	for c: Color in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]: peak = maxf(peak,c.a)
	return peak

func _history_excitation(accelerating: bool) -> float:
	var wakes = load("res://game/presentation/water/wake_trails.gd").new()
	root.add_child(wakes); wakes.configure(_water)
	for step in 10:
		var speed := 1.0 if accelerating and step < 5 else 4.0
		wakes.apply_snapshot({"time":step*0.2,"ships":[_ship(step*0.8,0.0,speed)]})
	var trail: MeshInstance3D = wakes.get_child(0)
	var colors: PackedColorArray = trail.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	# Row 4 is the same real speed, phase, observed position and history age;
	# only acceleration into this particular history sample differs.
	var excitation := colors[4*5+2].a
	wakes.dispose(); wakes.free(); return excitation

func _check_wet_triangles(mesh: ArrayMesh, message: String) -> void:
	var wet := true
	if mesh and mesh.get_surface_count() > 0:
		var arrays := mesh.surface_get_arrays(0)
		for index: int in arrays[Mesh.ARRAY_INDEX]: wet = wet and arrays[Mesh.ARRAY_VERTEX][index].x < 50.0
	check(wet,message)

func _check_attached_wave_axis() -> void:
	var helper = load("res://game/presentation/water/ship_wave_geometry.gd")
	var forward := Vector2(cos(0.37),sin(0.37)); var ship_center := Vector2(13,7)
	# Helper contract is explicitly ship center. The public presenter still owns
	# the distinction between its historical stern samples and this attachment.
	var pose := {"position":ship_center,"forward":forward,"length":20.0,"width":5.0,"speed":4.0}
	var bow: ArrayMesh = helper.build(pose,"bow",1.0,_water,Callable())
	var vertices: PackedVector3Array = bow.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var apex := Vector2(vertices[7*5+2].x,vertices[7*5+2].z)
	check(absf((apex-ship_center).dot(forward)-10.2) < 0.0001,"bow centerline apex lies at ship center plus 0.51 length")
	var along: Array[float] = []
	for row in [3,4,5]:
		var p: Vector3 = vertices[row*5+2]
		along.append((Vector2(p.x,p.z)-ship_center).dot(forward))
	check(along[0]-2.0*along[1]+along[2] < -0.02,"bow centerline has continuous curvature rather than two straight V legs")
	for kind: String in ["port","starboard"]:
		var side_mesh: ArrayMesh = helper.build(pose,kind,1.0,_water,Callable())
		var minimum := INF; var maximum := -INF
		for p: Vector3 in side_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
			var axis := (Vector2(p.x,p.z)-ship_center).dot(forward)
			minimum = minf(minimum,axis); maximum = maxf(maximum,axis)
		check(absf(maximum-8.0) < 0.0001 and absf(minimum+9.6) < 0.0001,kind+" foam spans bow-side to stern-side of the actual hull")
	var wakes = load("res://game/presentation/water/wake_trails.gd").new()
	root.add_child(wakes); wakes.configure(_water)
	wakes.apply_snapshot({"time":1.0,"ships":[_ship(0,0.37,4)]})
	wakes.apply_snapshot({"time":1.2,"ships":[_ship(0.6,0.37,4)]})
	var actual: MeshInstance3D = wakes.get_child(0).get_node("BowFoam")
	var actual_vertices: PackedVector3Array = actual.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var actual_apex := Vector2(actual_vertices[7*5+2].x,actual_vertices[7*5+2].z)
	check(absf((actual_apex-Vector2(0.6,0)).dot(forward)-10.2) < 0.0001,"public ship snapshot preserves correct bow attachment across stern-history conversion")
	wakes.dispose(); wakes.free()

func _run() -> void:
	_check_attached_wave_axis()
	check(_history_excitation(true) > _history_excitation(false)*1.1,"historical stern foam preserves local forward-acceleration surge")
	var splashes = load("res://game/presentation/water/water_splashes.gd").new()
	root.add_child(splashes); splashes.position = Vector3(70,0,30); splashes.configure(_water); splashes.apply_snapshot(10.0)
	var event := {"id":"shot","time":10.0,"position":{"x":3.0,"y":5.011,"z":4.0}}
	splashes.add_event(event); splashes.add_event(event)
	check(splashes.diagnostics().splashes == 1,"standalone splash presenter deduplicates real event identity")
	splashes.apply_snapshot(10.25)
	var effect: Node3D = splashes.get_child(0)
	check(effect.global_transform == Transform3D.IDENTITY,"translated presenter cannot move world-space impact origin")
	var column = effect.get_node_or_null("WaterColumn")
	var shell = effect.get_node_or_null("UmbrellaShell")
	var drops = effect.get_node_or_null("WorldDroplets")
	check(column != null and shell != null,"impact creates separate 3D column and umbrella shell")
	check(drops != null,"impact creates world-space droplets")
	if column:
		check(String(column.material_override.get_shader_parameter("foam_texture").resource_path).ends_with("fx_water_splash_004.dds.png"),"column binds original splash004 alpha dependency")
	if drops:
		var drop_material = drops.multimesh.mesh.surface_get_material(0)
		check(drop_material is ShaderMaterial and String(drop_material.get_shader_parameter("foam_texture").resource_path).ends_with("fx_streakin_001.dds.png"),"world droplets bind original streak alpha dependency")
	var mist = effect.get_node_or_null("WeakMist")
	check(mist != null and String(mist.material_override.get_shader_parameter("foam_texture").resource_path).ends_with("fx_mist_01.dds.png"),"weak mist binds original mist alpha dependency")
	if column and shell:
		var depth := _span(column); var flare := _span(shell)
		check(depth.x > 0.2 and depth.z > 0.2 and depth.y > 1.0,"column has volume from both horizontal camera axes")
		check(flare.x > 1.0 and flare.z > 1.0 and flare.y > 0.3,"umbrella flares in all directions above water")
		splashes.add_event({"id":"sailor-entry","time":10.0,"scale":0.45,"position":{"x":12.0,"y":5.0,"z":4.0}})
		var small_column = splashes.get_child(1).get_node_or_null("WaterColumn")
		check(small_column != null and _span(small_column).y < depth.y*0.65,"crew entry scale produces smaller volume than a cannon impact")
		splashes.add_event({"id":"sinking-froth","time":10.25,"scale":1.8,"surface_only":true,"position":{"x":20.0,"y":5.0,"z":4.0}})
		var surface: Node3D = splashes.get_child(2)
		check(not surface.get_node("WaterColumn").visible and not surface.get_node("UmbrellaShell").visible and not surface.get_node("WorldDroplets").visible and not surface.get_node("WaterSpray").visible,"sinking surface event cannot emit cannon plume, droplets or mist")
		var froth = surface.get_node_or_null("SurfaceFroth")
		check(froth != null and froth.visible and froth.mesh != null,"sinking surface event emits wave-conforming radial froth")
		var frozen: Array = shell.mesh.surface_get_arrays(0)
		splashes.apply_snapshot(10.25)
		check(frozen == shell.mesh.surface_get_arrays(0),"same accepted time freezes actual volume vertices")
	if drops:
		check(drops.multimesh.instance_count <= 40,"each impact has finite droplet slots")
		# Dummy headless renderer does not read back MultiMesh GPU transforms.
		# Production diagnostics retain the same CPU positions submitted to it.
		var before: Vector3 = splashes.diagnostics().droplet_positions[0]
		splashes.apply_snapshot(10.40)
		var after: Vector3 = splashes.diagnostics().droplet_positions[0]
		check(before != after,"droplets advance from accepted event age")
		check(absf(after.x-before.x) > 0.02 or absf(after.z-before.z) > 0.02,"droplets travel through world space rather than scaling a billboard")
		check(after.y < 9.5,"droplet trajectory uses meter-scaled gravity rather than raw NIF units")
		var replay = load("res://game/presentation/water/water_splashes.gd").new()
		root.add_child(replay); replay.configure(_water); replay.apply_snapshot(10.40); replay.add_event(event)
		check(replay.diagnostics().droplet_positions[0].distance_to(after) < 0.00001,"delayed event reconstructs same droplet position without missed-frame integration")
		replay.dispose(); replay.free()
		splashes.apply_snapshot(10.55)
		var later: Vector3 = splashes.diagnostics().droplet_positions[0]
		check(absf(later.y-2.0*after.y+before.y+0.220725) < 0.0001,"droplet curvature follows 9.81 meters-per-second gravity")
		splashes.apply_snapshot(10.55)
		check(later == splashes.diagnostics().droplet_positions[0],"paused authority phase freezes actual droplet trajectory")
	var final_phase := 10.55 if drops else 10.40
	splashes.apply_snapshot(final_phase)
	for v: Vector3 in effect.get_node("RippleRing").mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		check(absf(v.y-_water(v.x,v.z,final_phase)-0.10) < 0.0001,"rings conform to injected accepted water phase")
	splashes.apply_snapshot(9.0)
	check(splashes.diagnostics().splashes == 0 and splashes.get_child_count() == 0,"rollback releases every future volume")
	splashes.apply_snapshot(20.0); splashes.add_event(event)
	check(splashes.diagnostics().splashes == 0,"old event cannot resurrect expired volume")
	for i in 100: splashes.add_event({"id":"pool%d"%i,"time":20.0,"position":{"x":i,"z":0.0}})
	check(splashes.get_child_count() <= 32,"salvo volume pool remains bounded")
	splashes.apply_snapshot(24.0)
	check(splashes.get_child_count() == 0,"finite lifetime releases mesh and droplet nodes")
	check(splashes.has_method("configure_surface_filter"),"coast contract permits authoritative sea-only filter")
	if splashes.has_method("configure_surface_filter"):
		splashes.configure_surface_filter(_sea_only); splashes.add_event({"id":"land","time":24.0,"position":{"x":80.0,"z":0.0}})
		check(splashes.get_child_count() == 0,"land event does not spawn water column")
		splashes.add_event({"id":"coast","time":24.0,"position":{"x":49.8,"z":0.0}})
		splashes.apply_snapshot(24.2)
		for label: String in ["RippleRing","WaterColumn","UmbrellaShell"]:
			_check_wet_triangles(splashes.get_child(0).get_node(label).mesh,"coastal "+label+" excludes land-facing triangles")
		var dry_drops := false
		for p: Vector3 in splashes.diagnostics().droplet_positions: dry_drops = dry_drops or p.x >= 50.0
		check(not dry_drops,"world droplets reaching land leave the visible pool")
	splashes.dispose(); splashes.dispose(); splashes.free()
	var wakes = load("res://game/presentation/water/wake_trails.gd").new()
	root.add_child(wakes); wakes.position = Vector3(70,0,30); wakes.configure(_water)
	wakes.apply_snapshot({"time":0.0,"ships":[_ship(0,0,2.0)]})
	for step in range(1,9): wakes.apply_snapshot({"time":step*0.2,"ships":[_ship(step*0.4,0,2.0)]})
	var trail: MeshInstance3D = wakes.get_child(0)
	check(String(trail.material_override.get_shader_parameter("foam_texture").resource_path).ends_with("wake3unique.dds.png"),"historical foam binds original unique wake dependency")
	check(trail.global_transform == Transform3D.IDENTITY,"translated presenter cannot move observed world-space stern history")
	var bow = trail.get_node_or_null("BowFoam")
	var port = trail.get_node_or_null("PortFoam")
	var starboard = trail.get_node_or_null("StarboardFoam")
	check(bow != null and port != null and starboard != null,"forward movement creates bow and both side wave geometry")
	if bow and port and starboard:
		var steady := _peak(bow)
		check(steady > 0.0,"real forward speed makes bow wave visible")
		wakes.apply_snapshot({"time":1.8,"ships":[_ship(4.0,0,5.0)]})
		check(_peak(bow) > steady,"accepted forward acceleration strengthens bow surge")
		wakes.apply_snapshot({"time":2.0,"ships":[_ship(4.6,0.25,5.0)]})
		check(absf(_peak(port)-_peak(starboard)) > 0.01,"turning redistributes side foam asymmetrically")
		var frozen: Array = bow.mesh.surface_get_arrays(0)
		wakes.apply_snapshot({"time":2.0,"ships":[_ship(90.0,1.0,20.0)]})
		check(frozen == bow.mesh.surface_get_arrays(0),"pause cannot animate bow foam or adopt changed pose")
		wakes.apply_snapshot({"time":2.2,"ships":[_ship(4.4,0.25,-3.0)]})
		check(not bow.visible and not port.visible and not starboard.visible,"reverse motion stops attached waves while history fades")
		wakes.apply_snapshot({"time":2.4,"ships":[_ship(4.4,0.25,0.0)]})
		check(wakes.diagnostics().samples > 2,"stopping preserves historical foam until its lifetime ends")
		wakes.apply_snapshot({"time":10.0,"ships":[_ship(4.4,0.25,0.0)]})
		check(wakes.get_child_count() == 0,"stopped bow and historical foam release together")
	wakes.apply_snapshot({"time":0.0,"ships":[]})
	check(wakes.diagnostics().samples == 0,"wake rollback releases motion history")
	check(wakes.has_method("configure_surface_filter"),"bow, side and stern waves accept shared authoritative sea filter")
	if wakes.has_method("configure_surface_filter"):
		wakes.configure_surface_filter(_sea_only)
		for step in 5: wakes.apply_snapshot({"time":step*0.2+1.0,"ships":[_ship(48.0+step*0.3,0,3)]})
		var coastal: MeshInstance3D = wakes.get_child(0)
		check(not coastal.get_node("BowFoam").visible,"bow crest beyond sea boundary remains hidden")
		_check_wet_triangles(coastal.mesh,"coastal historical stern triangles remain in sea")
		for label: String in ["PortFoam","StarboardFoam"]: _check_wet_triangles(coastal.get_node(label).mesh,"coastal "+label+" triangles remain in sea")
	wakes.dispose(); wakes.dispose(); wakes.free()
	print("REFERENCE_WATER_VOLUME_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
