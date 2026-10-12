extends SceneTree
const Atmosphere = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Manifest = "res://assets/data/fidelity_fx/manifest.json"
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	var host:=Node3D.new(); root.add_child(host)
	var camera:=Camera3D.new(); host.add_child(camera); camera.fov=55; camera.near=.5; camera.far=4000
	camera.position=Vector3(33,27,-39); camera.look_at(Vector3(0,3,0)); camera.current=true
	var manifest: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(Manifest))
	for config in [{"cloud_sky_radius":1200.0,"cloud_sky_height":380.0},{"cloud_sky_radius":2800.0,"cloud_sky_height":680.0},{"cloud_sky_radius":3200.0,"cloud_sky_height":700.0},{"cloud_sky_radius":1800.0,"cloud_sky_height":390.0}]:
		var weather:=Atmosphere.new(); weather.configure(host,manifest,config); weather.apply_snapshot({"time":0.0},camera)
		var node: Node3D=host.get_node("OriginalCloudAndFog")
		var low:=INF; var high:=-INF; var on_screen:=0; var closest_screen_y:=-INF
		var viewport:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
		for mesh: MeshInstance3D in node.get_children():
			var screen:=Rect2(); var started:=false
			for vertex: Vector3 in mesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
				var point:=mesh.global_transform*vertex
				low=minf(low,point.y); high=maxf(high,point.y)
				if camera.is_position_behind(point): continue
				var projected:=camera.unproject_position(point)
				if not started: screen=Rect2(projected,Vector2.ZERO); started=true
				else: screen=screen.expand(projected)
			if started and screen.position.x < viewport.end.x and screen.end.x > 0: closest_screen_y=maxf(closest_screen_y,screen.end.y)
			if started and screen.intersects(viewport): on_screen+=1
		print(JSON.stringify({"config":config,"minimumY":low,"maximumY":high,"screenIntersections":on_screen,"nearestScreenBottom":closest_screen_y,"total":node.get_child_count(),"viewport":str(viewport)}))
		weather.dispose()
	host.free(); quit()
