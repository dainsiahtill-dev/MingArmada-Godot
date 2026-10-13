extends SceneTree
const Renderer=preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
var renderer:RefCounted
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();world.add_child(camera);camera.current=true
	var receiver:=MeshInstance3D.new();var mesh:=QuadMesh.new();mesh.size=Vector2(10,10);receiver.mesh=mesh;receiver.position.z=-5
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color.WHITE;receiver.material_override=material;world.add_child(receiver)
	var actor:=Node3D.new();world.add_child(actor)
	renderer=Renderer.new();renderer.configure(world,camera)
	# Finite volume made by the tested source CPU component. Source triangle
	# projects into the camera and its apex extends away through the receiver.
	var caster:Dictionary={"id":"c","actorId":"a","positions":[[-1,-1,-2],[1,-1,-2],[0,1,-2]],"edges":[[0,1],[1,2],[2,0]],"capIndices":[0,1,2],"localLight":[0,0,-1],"worldRotation":[1,0,0,0,1,0,0,0,1]}
	renderer.apply_snapshot({"sourceShadows":{"casters":[caster]}},{"a":actor})
	for i in 10:await process_frame
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png("C:/Users/dains/AppData/Local/Temp/source-shadow-gpu-compositor.png")
	var center:=image.get_pixel(image.get_width()/2,image.get_height()/2)
	renderer.apply_snapshot({}, {})
	for i in 3:await process_frame
	await RenderingServer.frame_post_draw
	var baseline:=root.get_texture().get_image().get_pixel(image.get_width()/2,image.get_height()/2)
	print("COMPOSITOR_GPU ",renderer.diagnostics()," center=",center," baseline=",baseline)
	var ok:bool=renderer.diagnostics().gpu.frames>0 and renderer.diagnostics().gpu.error.is_empty() and center.r<baseline.r-0.05 and baseline.r>0.99
	renderer.dispose()
	for i in 3:await process_frame
	world.free()
	print("SOURCE_SHADOW_COMPOSITOR_GPU passed=",ok)
	quit(0 if ok else 1)
