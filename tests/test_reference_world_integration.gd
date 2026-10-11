extends SceneTree
## Formal terrain/water coupling: inspect real Float32 meshes and RF fields.
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func height(x: float, z: float) -> float:
	return 0.0017*x*x+0.0009*z*z+sin(x*0.017)*2.0-18.0
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var camera := Camera3D.new(); root.add_child(camera)
	camera.position=Vector3(70,100,140); camera.look_at(Vector3.ZERO); camera.current=true
	var world := World.new(); root.add_child(world)
	var unrelated := Node3D.new(); world.add_child(unrelated)
	var options := {"camera":camera,"chunk_size":100,"resolution":8,"chunk_radius":1,"vegetation":false,"island_details":false,"collision":false,"visual_style":1}
	check(world.configure(height,Waves.original_descriptors(),options),"formal world composes with reference sea optics")
	check(world.get_chunk_count()==9,"authored near terrain window remains intact")
	check(world._near_shore_texture!=null,"formal water receives actual near-mesh height field")
	if world._near_shore_texture:
		var field: Image=world._near_shore_texture.get_image()
		check(field.get_size()==Vector2i(25,25) and field.get_format()==Image.FORMAT_RF,"RF lattice contains every real near-mesh vertex")
		var material: ShaderMaterial=world.get_ocean().material_override
		check(material.get_shader_parameter("has_reference_near_field")==true,"shader uses near terrain optics rather than global coarse coast")
		check(material.get_shader_parameter("reference_near_bounds")==Vector4(-150,-150,150,150),"RF bounds use actual tile centers and extents")
		check(material.get_shader_parameter("reference_near_height_texture")==world._near_shore_texture,"water holds the owned near field")
		for row in 25:
			for column in 25:
				var point:=Vector2(-150,-150)+Vector2(column,row)*12.5
				var expected:=PackedFloat32Array([height(point.x,point.y)])[0]
				check(absf(field.get_pixel(column,row).r-expected)<1e-5,"near RF is authored mesh Float32 vertex %d,%d" % [column,row])
		for chunk in world.get_chunks():
			var origin: Vector3=chunk.global_position
			for local in [Vector2(-43,-41),Vector2(6,8),Vector2(41,37)]:
				var point: Vector2=Vector2(origin.x,origin.z)+local
				var texel: Vector2=(point-Vector2(-150,-150))/12.5
				var cell:=Vector2i(floori(texel.x),floori(texel.y)); var fraction:=texel-Vector2(cell)
				var a:=field.get_pixel(cell.x,cell.y).r; var b:=field.get_pixel(cell.x+1,cell.y).r
				var c:=field.get_pixel(cell.x,cell.y+1).r; var d:=field.get_pixel(cell.x+1,cell.y+1).r
				var expected:=a+(b-a)*fraction.x+(c-a)*fraction.y if fraction.x+fraction.y<=1.0 else d+(c-d)*(1.0-fraction.x)+(b-d)*(1.0-fraction.y)
				check(absf(expected-chunk.sample_mesh_height(point.x,point.y))<1e-5,"near-field triangles match actual terrain surface")
	var initial: Texture2D=world._near_shore_texture
	world.apply_snapshot({"time":17.25,"focus":Vector2(95,10)},0.0)
	check(world._near_shore_texture==initial,"accepted time and same tile do not rebuild static coast")
	check(world.get_ocean()._simulation_time==17.25,"formal sea uses authority clock with zero wall delta")
	world.apply_snapshot({"time":17.25,"focus":Vector2(100,10)},0.0)
	check(world._near_shore_texture!=initial,"crossing terrain tile rebuilds local shoreline field")
	check(world.get_ocean().material_override.get_shader_parameter("reference_near_bounds")==Vector4(-50,-150,250,150),"new field follows actual active mesh window")
	var moved: Texture2D=world._near_shore_texture
	world.apply_snapshot({"time":3.0,"focus":Vector2(NAN,0)},0.0)
	check(world._near_shore_texture==moved and world.get_ocean()._simulation_time==3.0,"invalid focus cannot corrupt coastline; accepted rewind remains authoritative")
	var old_ocean: WeakRef=weakref(world.get_ocean())
	world.dispose(); world.dispose()
	check(world._near_shore_texture==null and world.get_chunk_count()==0 and old_ocean.get_ref()==null,"disposal clears ocean, terrain and field ownership")
	check(is_instance_valid(unrelated) and unrelated.get_parent()==world,"world disposal preserves caller additions")
	check(world.configure(height,Waves.original_descriptors(),options),"reference world can reenter after full disposal")
	check(world._near_shore_texture!=null and world._near_shore_texture!=moved,"reentry allocates fresh near-field ownership")
	world.dispose(); world.free(); camera.free()
	await process_frame
	print("REFERENCE_WORLD_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
