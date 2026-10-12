extends SceneTree

const Shore = preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func _wave_height(point: Vector3, waves: PackedVector4Array, time: float) -> float:
	var result := 0.0
	for wave: Vector4 in waves:
		result += wave.x*sin(point.x*wave.y+point.z*wave.z+wave.w*time)
	return result

func _surface_error(shore: Node3D, waves: PackedVector4Array) -> Dictionary:
	var largest_error := 0.0
	var largest_edge := 0.0
	var triangles := 0
	for child: MeshInstance3D in shore.get_children():
		var arrays: Array = child.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		triangles += indices.size()/3
		for i in range(0,indices.size(),3):
			var a := vertices[indices[i]]
			var b := vertices[indices[i+1]]
			var c := vertices[indices[i+2]]
			largest_edge = maxf(largest_edge,maxf(a.distance_to(b),maxf(b.distance_to(c),c.distance_to(a))))
			for time: float in [0.0,4.5,12.0,17.25]:
				var corner_heights := Vector3(_wave_height(a,waves,time),_wave_height(b,waves,time),_wave_height(c,waves,time))
				for weights: Vector3 in [Vector3.ONE/3.0,Vector3(.5,.5,0),Vector3(0,.5,.5),Vector3(.5,0,.5)]:
					var point := a*weights.x+b*weights.y+c*weights.z
					largest_error = maxf(largest_error,absf(corner_heights.dot(weights)-_wave_height(point,waves,time)))
	return {"maximumHeightError":largest_error,"maximumEdge":largest_edge,"renderedTriangles":triangles}

func _mesh_contract(mesh: ArrayMesh) -> Dictionary:
	var arrays: Array = mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var area := 0.0
	var uv_integral := Vector2.ZERO
	var winding_consistent := true
	for i in range(0,indices.size(),3):
		var a := indices[i]
		var b := indices[i+1]
		var c := indices[i+2]
		var signed_area := (vertices[b]-vertices[a]).cross(vertices[c]-vertices[a]).y*.5
		if area != 0.0 and signed_area*area < 0.0: winding_consistent = false
		area += signed_area
		uv_integral += (uv[a]+uv[b]+uv[c])*(signed_area/3.0)
	return {"area":area,"uvIntegral":uv_integral,"windingConsistent":winding_consistent}

func _run() -> void:
	var mapping := {"sourceCenter":Vector2(60,70),"sourceOutward":Vector2.UP,"islandCenter":Vector2.ZERO,"inward":Vector2.RIGHT,"scale":1.0}
	var sampler := func(_x: float,_z: float)->float:return -1.0
	var ocean := ShaderMaterial.new()
	ocean.shader = load("res://modules/scene_engine/ocean/reference_game_water.gdshader")
	var waves := PackedVector4Array([Vector4(1,.02,.015,.9),Vector4(1,.02,-.015,.1),Vector4(1,.05,0,-.6),Vector4(.25,.1,.11,2.05),Vector4(.25,.1,-.11,-.05),Vector4.ZERO,Vector4.ZERO,Vector4.ZERO])
	ocean.set_shader_parameter("wave_components",waves)
	ocean.set_shader_parameter("wave_count",5)
	ocean.set_shader_parameter("simulation_time",12.0)
	ocean.set_shader_parameter("has_shore_field",false)
	ocean.set_shader_parameter("coastal_attenuation",false)
	var static_mapped := Shore.new()
	check(static_mapped.configure(mapping,sampler,{"mode":"mapped","follow_surface":false}),"explicit mapped static surf accepts authored geometry")
	check(static_mapped.sync_surface_state(ocean) and not static_mapped.diagnostics().followSurface,"explicit false prevents mapped metre-wave displacement")
	check(static_mapped.diagnostics().triangles == 300,"static mapped surf retains original topology")
	static_mapped.free()
	var exact := Shore.new()
	check(exact.configure({},Callable(),{"mode":"exact","native_origin":Vector3(269925.21875,202766.25,0)}),"source observer accepts original origin")
	check(exact.sync_surface_state(ocean) and not exact.diagnostics().followSurface,"exact observer remains static even when a water owner is supplied")
	var exact_vertices := 0
	for child: MeshInstance3D in exact.get_children(): exact_vertices += child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()
	check(exact_vertices == 600 and exact.diagnostics().triangles == 300,"exact source preserves original600 vertices and300 triangles")
	exact.free()
	var shore := Shore.new()
	check(shore.configure(mapping,sampler,{"mode":"mapped"}),"mapped surf configures original render source")
	var original_contracts: Array[Dictionary] = []
	for child: MeshInstance3D in shore.get_children(): original_contracts.append(_mesh_contract(child.mesh))
	var before := _surface_error(shore,waves)
	check(before.maximumHeightError > .035,"fixture reproduces sparse triangle interpolation crossing the .035 water offset")
	ocean.set_shader_parameter("has_shore_field",true)
	check(not shore.sync_surface_state(ocean) and not shore.diagnostics().followSurface,"invalid terrain-field owner cannot enable surface following")
	check(_surface_error(shore,waves).renderedTriangles == 300,"invalid owner is rejected before any render topology adaptation")
	ocean.set_shader_parameter("has_shore_field",false)
	check(shore.sync_surface_state(ocean),"real five-wave material enables presentation refinement")
	var refined := _surface_error(shore,waves)
	check(refined.maximumEdge <= 5.30,"mapped render triangles resolve shortest authoritative wave")
	check(refined.maximumHeightError <= .00875,"mapped interpolated shore surface stays within quarter of .035 offset at centroids and edges")
	check(shore.diagnostics().triangles == 300 and refined.renderedTriangles > 300,"render refinement reports separately without changing authored triangle counts")
	var geometric_contract_preserved := true
	for i in shore.get_child_count():
		var refined_contract := _mesh_contract(shore.get_child(i).mesh)
		var original_contract := original_contracts[i]
		geometric_contract_preserved = geometric_contract_preserved and refined_contract.windingConsistent and absf(refined_contract.area-original_contract.area) <= absf(original_contract.area)*.00001
		geometric_contract_preserved = geometric_contract_preserved and refined_contract.uvIntegral.distance_to(original_contract.uvIntegral) <= original_contract.uvIntegral.length()*.0001
	check(geometric_contract_preserved,"refinement preserves each authored footprint, winding and area-weighted UV address integral")
	var meshes: Array = []
	for child: MeshInstance3D in shore.get_children(): meshes.append(child.mesh)
	shore.apply_snapshot(12.7)
	ocean.set_shader_parameter("simulation_time",17.25)
	check(shore.sync_surface_state(ocean),"new water clock reuses validated wave topology")
	var reused := true
	for i in meshes.size(): reused = reused and shore.get_child(i).mesh == meshes[i]
	check(reused,"UV seek and water-clock change reuse cached render meshes")
	var authored := Asset.read_json("res://assets/data/fidelity_island/shore-scene.json")
	var transparency_preserved := true
	for i in shore.get_child_count():
		var material: ShaderMaterial = shore.get_child(i).material_override
		transparency_preserved = transparency_preserved and float(material.get_shader_parameter("source_alpha_threshold")) == float(authored.meshes[i].alphaProperty.threshold)/255.0
		var texture: Texture2D = material.get_shader_parameter("shore_texture")
		transparency_preserved = transparency_preserved and texture.get_image().get_mipmap_count() == 7
	check(transparency_preserved,"render refinement preserves original alpha threshold and all eight authored mip levels")
	var report := {"scope":"Headless geometry/uniform contract only; actual visual/depth acceptance requires native GPU capture","before":before,"refined":refined,"diagnostics":shore.diagnostics(),"assertions":assertions,"failures":failures}
	DirAccess.make_dir_recursive_absolute("res://build/fidelity-wave-work/shore")
	var file := FileAccess.open("res://build/fidelity-wave-work/shore/visual-contract.json",FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report,"\t"))
	shore.free()
	print("FIDELITY_SHORE_VISUAL_CONTRACT assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures > 0 else 0)
