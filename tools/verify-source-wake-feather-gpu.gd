extends SceneTree
## GPU readback at the actual SourceSurface material seam. No game entry.
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL wake feather GPU: ",label)
func pixels(view:SubViewport)->Image:
	for _i in 5:await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run()->void:
	var output:="res://docs/migration/evidence/wake-regression-2026-10-14/feather-gpu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var view:=SubViewport.new();view.size=Vector2i(128,128);view.transparent_bg=true;view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var world:=Node3D.new();view.add_child(world)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0;world.add_child(camera);camera.position=Vector3(0,4,0);camera.look_at(Vector3.ZERO,Vector3.FORWARD);camera.current=true
	var surface:=Surface.new(world)
	var descriptor:={"texture":"wake3unique.dds","alphaFlags":4333,"clampMode":3,"scene_trail":true,"tail_v":0.0,"tail_span_v":-1.0}
	var material:ShaderMaterial=surface.material(descriptor)
	# A constant source texture isolates fragment edge/terminal response from
	# the original coarse mip's nonzero border alpha. Actual production material.
	var white:=Image.create(4,4,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE)
	var texture:=ImageTexture.create_from_image(white)
	material.set_shader_parameter("source_texture",texture);material.set_shader_parameter("source_texture_repeat",texture)
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(-1,0,-1),Vector3(1,0,-1),Vector3(1,0,1),Vector3(-1,0,1)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(0,-1),Vector2(1,-1),Vector2(1,0),Vector2(0,0)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,2,1,0,3,2])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;world.add_child(node)
	var image:Image=await pixels(view)
	check(image.save_png(output+"/response.png")==OK,"response capture")
	var center:=image.get_pixel(64,64).a
	var left:=image.get_pixel(0,64).a;var right:=image.get_pixel(127,64).a
	var top:=image.get_pixel(64,0).a;var bottom:=image.get_pixel(64,127).a
	check(center>.45 and center<.55,"body retains graded opacity")
	check(left<.02 and right<.02,"coarse-mip side boundaries feather to transparent")
	check(minf(top,bottom)<.02 and maxf(top,bottom)>.95,"terminal end fades while the body remains visible")
	# Updating a reused material must move the cap rather than retain stale UVs.
	descriptor.tail_v=-1.0;descriptor.tail_span_v=1.0
	check(surface.material(descriptor)==material,"material reused with current cap parameters")
	var reverse:Image=await pixels(view)
	var reversed_top:=reverse.get_pixel(64,0).a;var reversed_bottom:=reverse.get_pixel(64,127).a
	check(absf(top-reversed_bottom)<.02 and absf(bottom-reversed_top)<.02,"reused material receives new signed terminal range")
	var report:={"failures":failures,"centerAlpha":center,"leftAlpha":left,"rightAlpha":right,"topAlpha":top,"bottomAlpha":bottom,"reversedTopAlpha":reversed_top,"reversedBottomAlpha":reversed_bottom,"renderer":RenderingServer.get_current_rendering_method(),"scope":"Actual SourceSurface shader GPU readback; diagnostic constant texture, not original DX9 pixels."}
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	surface.dispose();view.free()
	print("SOURCE_WAKE_FEATHER_GPU failures=",failures.size()," center=",center," edges=",left,",",right)
	quit(0 if failures.is_empty() else 1)
