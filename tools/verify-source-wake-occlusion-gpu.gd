extends SceneTree
## Actual SceneWake seam: a transparent depth-writing sea must not cut the
## surface foam, while an opaque foreground hull/terrain still occludes it.
const Surface=preload("res://modules/scene_engine/water/source_surface.gd")
var failures:Array[String]=[]
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	if not ok:failures.append(label);printerr("FAIL wake occlusion GPU: ",label)
func quad(parent:Node3D,material:Material,z:float,left:float=-1.0,right:float=1.0)->MeshInstance3D:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(left,-1,z),Vector3(right,-1,z),Vector3(right,1,z),Vector3(left,1,z)])
	arrays[Mesh.ARRAY_TEX_UV]=PackedVector2Array([Vector2(.5,.5),Vector2(.5,.5),Vector2(.5,.5),Vector2(.5,.5)])
	arrays[Mesh.ARRAY_COLOR]=PackedColorArray([Color.WHITE,Color.WHITE,Color.WHITE,Color.WHITE])
	arrays[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2,0,2,3])
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var node:=MeshInstance3D.new();node.mesh=mesh;node.material_override=material;parent.add_child(node);return node
func pixels(view:SubViewport)->Image:
	for _i in 6:await process_frame
	await RenderingServer.frame_post_draw
	return view.get_texture().get_image()
func run()->void:
	var phase:="current"
	var role:="scene_trail"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="):phase=argument.trim_prefix("--phase=")
		if argument.begins_with("--role="):role=argument.trim_prefix("--role=")
	var output:="res://docs/migration/evidence/wake-regression-2026-10-14/occlusion-gpu/"+phase
	if role=="side":output="res://docs/migration/evidence/froth-closeup-2026-10-14/occlusion-gpu/"+phase
	if role=="bow":output="res://docs/migration/evidence/bow-froth-2026-10-14/occlusion-gpu/"+phase
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	var view:=SubViewport.new();view.size=Vector2i(128,128);view.own_world_3d=true;view.render_target_update_mode=SubViewport.UPDATE_ALWAYS;root.add_child(view)
	var world:=Node3D.new();view.add_child(world)
	var camera:=Camera3D.new();camera.projection=Camera3D.PROJECTION_ORTHOGONAL;camera.size=2.0;camera.near=.1;camera.far=10.0;world.add_child(camera);camera.position=Vector3(0,0,4);camera.look_at(Vector3.ZERO);camera.current=true
	var ocean:=ShaderMaterial.new();var ocean_shader:=Shader.new()
	# Same transparent-pass/depth-writing contract as reference_game_water.
	ocean_shader.code="shader_type spatial; render_mode unshaded,cull_disabled,depth_draw_always; void fragment(){ALBEDO=vec3(0.02,0.12,0.5);ALPHA=1.0;}";ocean.shader=ocean_shader;quad(world,ocean,.2)
	var opaque:=ShaderMaterial.new();var opaque_shader:=Shader.new();opaque_shader.code="shader_type spatial;render_mode unshaded,cull_disabled;void fragment(){ALBEDO=vec3(0.0,1.0,0.0);}"
	opaque.shader=opaque_shader;var hull_node:=quad(world,opaque,.4,-.8,-.2)
	var descriptor:={"texture":"wake3unique.dds","alphaFlags":4333,"clampMode":3,"scene_trail":role=="scene_trail"}
	if role in ["side","bow"]:descriptor.merge({"target_froth_role":role,"target_froth_intensity":1.0,"target_froth_world_to_hull":Transform3D.IDENTITY,"target_froth_time":30.0})
	var surface:=Surface.new(world);var material:=surface.material(descriptor)
	if phase=="red":
		var legacy:=Shader.new();legacy.code=material.shader.code.replace("depth_test_disabled,","");material.shader=legacy;material.set_shader_parameter("soft_depth_distance",0.0)
	var white:=Image.create(4,4,false,Image.FORMAT_RGBA8);white.fill(Color.WHITE);var texture:=ImageTexture.create_from_image(white)
	material.set_shader_parameter("source_texture",texture);material.set_shader_parameter("source_texture_repeat",texture)
	quad(world,material,0.0)
	var result:Image=await pixels(view);result.save_png(output+"/response.png")
	var foam:=result.get_pixel(96,64);var hull:=result.get_pixel(32,64)
	check(foam.r>.95 and foam.g>.95 and foam.b>.95,"surface foam survives transparent sea depth")
	check(hull.r<.05 and hull.g>.95 and hull.b<.05,"opaque hull still occludes surface foam")
	hull_node.position.z=-.8
	var behind:Image=await pixels(view);behind.save_png(output+"/opaque-behind.png")
	var behind_pixel:=behind.get_pixel(32,64)
	check(behind_pixel.r>.95 and behind_pixel.g>.95 and behind_pixel.b>.95,"opaque geometry behind foam does not erase it")
	var report:={"failures":failures,"role":role,"foam":foam.to_html(true),"opaqueHull":hull.to_html(true),"opaqueBehind":behind_pixel.to_html(true),"renderer":RenderingServer.get_current_rendering_method(),"scope":"Actual SourceSurface material, diagnostic transparent sea and opaque hull; original source geometry untouched."}
	var file:=FileAccess.open(output+"/VERIFICATION.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	surface.dispose();view.free();print("SOURCE_WAKE_OCCLUSION_GPU failures=",failures.size()," foam=",foam," hull=",hull);quit(0 if failures.is_empty() else 1)
