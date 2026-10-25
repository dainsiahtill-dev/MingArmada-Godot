extends SceneTree
## CPU-only diagnostic. Replays the frozen cloud GPU fixture and traces source triangles.
const Demo = preload("res://game/research/demos/architecture_convergence_experiment.gd")
const OUT := "res://docs/research/evidence/architecture-convergence-2026-10-21/billboard-reuse-20261026/ship-pixel-trace-01/run-02"
const GPU_REPORT := "res://docs/research/evidence/architecture-convergence-2026-10-21/billboard-reuse-20261026/gpu-01/GPU_VERIFY.json"
const TARGETS := {34:Vector2i(631,263),38:Vector2i(620,253),67:Vector2i(656,212)}
var failures:Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(ok:bool, message:String) -> void:
	if not ok: failures.append(message); printerr("SHIP_PIXEL_TRACE: ",message)

func vec(v:Vector3) -> Array: return [v.x,v.y,v.z]

func normalized32(values:Array) -> PackedByteArray:
	var floats := PackedFloat32Array()
	for value in values: floats.append(float(value))
	return floats.to_byte_array()

func material_info(material:Material) -> Dictionary:
	if material == null: return {}
	var result := {"class":material.get_class(),"name":material.resource_name,"path":material.resource_path,"renderPriority":material.render_priority}
	if material is BaseMaterial3D:
		result.merge({"cullMode":material.cull_mode,"transparency":material.transparency,"shadingMode":material.shading_mode,"albedo":[material.albedo_color.r,material.albedo_color.g,material.albedo_color.b,material.albedo_color.a],"metallic":material.metallic,"roughness":material.roughness,"albedoTexture":material.albedo_texture.resource_path if material.albedo_texture else ""})
	elif material is ShaderMaterial:
		result.shader = material.shader.resource_path if material.shader else ""
		result.uniforms = {}
		for parameter:String in ["sail_surface","damage_stage","original_roughness","original_alpha_cutoff","original_color","use_original_vertex_color","use_original_albedo","use_source_hull_layers","original_albedo"]:
			var value:Variant = material.get_shader_parameter(parameter)
			if value is Texture2D: value = {"path":value.resource_path,"size":[value.get_width(),value.get_height()]}
			elif value is Color: value = [value.r,value.g,value.b,value.a]
			result.uniforms[parameter] = value
	return result

func trace(camera:Camera3D, ship:Node3D, screen:Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var hits:Array = []
	var visible_meshes := 0
	var triangles := 0
	for child:Node in ship.find_children("*","MeshInstance3D",true,false):
		var mesh := child as MeshInstance3D
		if not mesh.is_visible_in_tree() or mesh.mesh == null: continue
		visible_meshes += 1
		var inverse := mesh.global_transform.affine_inverse()
		var local_origin:Vector3 = inverse * origin
		var local_direction:Vector3 = (inverse.basis * direction).normalized()
		var blends:Array = []
		for blend_index in mesh.mesh.get_blend_shape_count():
			var weight := mesh.get_blend_shape_value(blend_index)
			if absf(weight)>0.000001: blends.append({"index":blend_index,"name":str(mesh.mesh.get_blend_shape_name(blend_index)),"weight":weight})
		for surface in mesh.mesh.get_surface_count():
			var arrays:Array = mesh.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var normals:PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
			var uvs:PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			if indices.is_empty():
				for index in points.size(): indices.append(index)
			triangles += indices.size()/3
			for index in range(0,indices.size(),3):
				var ia := indices[index]; var ib := indices[index+1]; var ic := indices[index+2]
				var a := points[ia]; var b := points[ib]; var c := points[ic]
				var contact:Variant = Geometry3D.ray_intersects_triangle(local_origin,local_direction,a,b,c)
				if not contact is Vector3: continue
				var world_contact:Vector3 = mesh.global_transform * contact
				var face_normal:Vector3 = (mesh.global_basis.inverse().transposed() * (b-a).cross(c-a).normalized()).normalized()
				var vertex_normal := Vector3.ZERO
				if normals.size() == points.size(): vertex_normal = (mesh.global_basis.inverse().transposed() * (normals[ia]+normals[ib]+normals[ic]).normalized()).normalized()
				var ab := b-a; var ac := c-a; var ap:Vector3 = contact-a
				var denominator := ab.dot(ab)*ac.dot(ac)-ab.dot(ac)*ab.dot(ac)
				var bary_b := (ac.dot(ac)*ap.dot(ab)-ab.dot(ac)*ap.dot(ac))/denominator if denominator != 0.0 else 0.0
				var bary_c := (ab.dot(ab)*ap.dot(ac)-ab.dot(ac)*ap.dot(ab))/denominator if denominator != 0.0 else 0.0
				var uv := uvs[ia]*(1.0-bary_b-bary_c)+uvs[ib]*bary_b+uvs[ic]*bary_c if uvs.size()==points.size() else Vector2.ZERO
				var projected:Array = []
				for point:Vector3 in [a,b,c]:
					var p := camera.unproject_position(mesh.global_transform * point); projected.append([p.x,p.y])
				hits.append({"mesh":str(ship.get_path_to(mesh)),"surface":surface,"triangle":index/3,"distanceM":origin.distance_to(world_contact),"worldPoint":vec(world_contact),"localPoint":vec(contact),"localVertices":[vec(a),vec(b),vec(c)],"projectedVertices":projected,"barycentric":[1.0-bary_b-bary_c,bary_b,bary_c],"faceNormalWorld":vec(face_normal),"vertexNormalWorld":vec(vertex_normal),"faceNormalDotRay":face_normal.dot(direction),"vertexNormalDotRay":vertex_normal.dot(direction),"uv":[uv.x,uv.y],"material":material_info(mesh.get_active_material(surface)),"authoredMaterial":material_info(mesh.mesh.surface_get_material(surface)),"nonzeroBlendShapes":blends,"blendShapeAppliedToRay":false})
		hits.sort_custom(func(a:Dictionary,b:Dictionary) -> bool: return a.distanceM < b.distanceM)
	var first := float(hits[0].distanceM) if not hits.is_empty() else 0.0
	for hit:Dictionary in hits: hit.gapFromNearestM = float(hit.distanceM)-first
	return {"screen":[screen.x,screen.y],"origin":vec(origin),"direction":vec(direction),"visibleMeshCount":visible_meshes,"sourceTriangleCount":triangles,"intersectionCount":hits.size(),"nearest":hits.slice(0,20)}

func run() -> void:
	check(DisplayServer.get_name()=="headless","headless execution required")
	check(not DirAccess.dir_exists_absolute(OUT),"fresh evidence directory required")
	if not failures.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(OUT)
	var reference:Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GPU_REPORT))
	var sources := {}
	for path:String in ["res://tools/research/trace-ship-pixel.gd","res://game/research/demos/architecture_convergence_experiment.gd","res://game/presentation/ships/ship_view.gd","res://game/presentation/ships/ship_damage.gd","res://game/presentation/ships/ship_damage.gdshader","res://game/presentation/ships/ship_damage_surface.gdshaderinc","res://assets/models/hero_fuchuan_v3_r6/fuchuan-lod0.glb"]: sources[path] = FileAccess.get_sha256(path)
	root.size = Vector2i(1600,1000); root.content_scale_size = root.size
	var viewport := SubViewport.new(); viewport.name = "HeadlessExperimentViewport"; viewport.size = Vector2i(1220,444); viewport.world_3d = World3D.new(); root.add_child(viewport)
	var demo := Demo.new()
	var configured:Dictionary = demo.configure({"kind":"fuchuan","depth":4.0,"clouds":true,"billboard_variant":"candidate","paused":false,"camera_mode":"side"})
	check(configured.ok,"same frozen configuration accepts")
	viewport.add_child(demo)
	await process_frame
	var rows:Array = []
	for frame in 68:
		if frame == 48: demo.set_camera_mode("high")
		demo.advance(1.0/32.0)
		if not TARGETS.has(frame): continue
		var state:Dictionary = demo.inspection_snapshot()
		var expected:Dictionary = reference.framePairs[frame]
		var camera_match := normalized32(state.camera_transform)==normalized32(expected.cameraTransform)
		var projection_match := normalized32(state.camera_projection)==normalized32(expected.cameraProjection)
		check(camera_match and projection_match,"GPU01 float32 camera and projection byte match frame%d"%frame)
		var camera:Camera3D = demo.get("_camera")
		var ship:Node3D = demo.get("_ship")
		var target:Vector2i = TARGETS[frame]
		var rays:Array = []
		for offset:Vector2 in [Vector2(.5,.5),Vector2(0,0),Vector2(.25,.25),Vector2(.75,.25),Vector2(.25,.75),Vector2(.75,.75),Vector2(.5,0),Vector2(.5,1),Vector2(0,.5),Vector2(1,.5)]: rays.append(trace(camera,ship,Vector2(target)+offset))
		rows.append({"frame":frame,"pixel":[target.x,target.y],"cameraTransformFloat32BytesMatch":camera_match,"cameraProjectionFloat32BytesMatch":projection_match,"cameraTransform":state.camera_transform,"cameraProjection":state.camera_projection,"acceptedTime":state.time,"renderTime":state.render_time,"acceptedTimeMatches":absf(state.time-float(expected.acceptedTime))<1e-12,"renderTimeMatches":absf(state.render_time-float(expected.renderTime))<1e-12,"shipTransform":Demo._matrix(Projection(ship.global_transform)),"rays":rays})
		print("SHIP_PIXEL_TRACE frame=",frame," cameraMatch=",camera_match," projectionMatch=",projection_match," centerNearest=",JSON.stringify(rays[0].nearest.slice(0,3)))
	var unchanged := true
	for path:String in sources: unchanged = unchanged and FileAccess.get_sha256(path)==sources[path]
	check(unchanged,"source hashes unchanged")
	var report := {"valid":failures.is_empty(),"scope":"Headless original visible ShipView triangle ray intersections, fixed actual GPU01 camera/projection and accepted replay. No GPU rendering, rasterization, lighting, depth-buffer or cause proof. Mesh blend shapes recorded but not applied to ray; relevant wood meshes have none.","engine":Engine.get_version_info(),"display":DisplayServer.get_name(),"sources":sources,"sourcesUnchanged":unchanged,"gpuReportPath":GPU_REPORT,"gpuReportSha256":FileAccess.get_sha256(GPU_REPORT),"viewport":[1220,444],"antiAliasing":{"msaa3d":viewport.msaa_3d,"screenSpaceAA":viewport.screen_space_aa,"taa":viewport.use_taa},"frameStepSeconds":1.0/32.0,"seed":1661,"rows":rows,"failures":failures}
	var file := FileAccess.open(OUT+"/SHIP_PIXEL_TRACE.json",FileAccess.WRITE); file.store_string(JSON.stringify(report,"\t")); file.close()
	demo.dispose(); viewport.free()
	await process_frame
	print("SHIP_PIXEL_TRACE valid=",failures.is_empty()," rows=",rows.size())
	quit(1 if not failures.is_empty() else 0)
