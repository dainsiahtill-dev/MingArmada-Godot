extends SceneTree
## Independent GPU receiver fixture: shadow on opaque quad, no shadow on empty depth.
const Renderer=preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
class ReceiverBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	func _compile(vertex:String,fragment:String)->RID:
		if fragment==FRAGMENT_SOURCE:fragment=fragment.replace("if(gl_FragCoord.z < receiver) discard;","if(receiver <= 0.0 || gl_FragCoord.z < receiver) discard;")
		return super._compile(vertex,fragment)
var output:="res://docs/research/evidence/shadow-edges/receiver-contract"
var samples:Array=[]
func _initialize()->void:run.call_deferred()
func frames(count:int)->void:
	for tick in count:await process_frame
func capture(label:String,renderer:RefCounted)->Dictionary:
	await frames(4);await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image();image.save_png(output+"/"+label+".png")
	var center:=image.get_pixel(image.get_width()/2,image.get_height()/2)
	var background:=image.get_pixel(image.get_width()/2,int(image.get_height()*.35))
	var sample:={"label":label,"center":[center.r,center.g,center.b],"background":[background.r,background.g,background.b],"gpu":renderer.diagnostics().gpu,"image":label+".png","sha256":FileAccess.get_sha256(output+"/"+label+".png")}
	samples.append(sample);return sample
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(640,480);root.content_scale_size=root.size
	var world:=Node3D.new();root.add_child(world)
	var camera:=Camera3D.new();camera.current=true;camera.near=.5;camera.far=4000;world.add_child(camera)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color.WHITE;world.add_child(environment)
	var receiver:=MeshInstance3D.new();var quad:=QuadMesh.new();quad.size=Vector2(.7,.7);receiver.mesh=quad;receiver.position.z=-5;world.add_child(receiver)
	var material:=StandardMaterial3D.new();material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED;material.albedo_color=Color.WHITE;receiver.material_override=material
	var actor:=Node3D.new();world.add_child(actor)
	var renderer:=Renderer.new();renderer.configure(world,camera)
	if renderer._effect==null:printerr("FAIL actual GPU compositor unavailable");renderer.dispose();world.free();quit(1);return
	var caster:={"id":"c","actorId":"a","positions":[[-1,-1,-2],[1,-1,-2],[0,1,-2]],"edges":[[0,1],[1,2],[2,0]],"capIndices":[0,1,2],"localLight":[0,0,-1],"worldRotation":[1,0,0,0,1,0,0,0,1]}
	renderer.apply_snapshot({"sourceShadows":{"casters":[caster]}},{"a":actor})
	var baseline:Dictionary=await capture("baseline",renderer)
	var effect:CompositorEffect=renderer._effect
	RenderingServer.call_on_render_thread(func():
		if effect._backend:effect._backend.dispose()
		var candidate:=ReceiverBackend.new();candidate.initialize(RenderingServer.get_rendering_device());effect._backend=candidate)
	var candidate:Dictionary=await capture("receiver-guard",renderer)
	effect.enabled=false
	var disabled:Dictionary=await capture("stencil-off",renderer)
	var valid:bool=candidate.gpu.initialized and candidate.gpu.error.is_empty() and candidate.center[0]<disabled.center[0]-.05 and candidate.background[0]>disabled.background[0]-.01 and disabled.background[0]>.99
	var proof:={"valid":valid,"samples":samples,"baselineShowsEmptyDepthLeak":baseline.background[0]<disabled.background[0]-.05,"scope":"Independent opaque quad and empty-depth receiver contract; real GPU. No ship/ocean FPS claim.","utc":Time.get_datetime_string_from_system(true)}
	var file:=FileAccess.open(output+"/RECEIVER_CONTRACT.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	renderer.dispose();await frames(3);world.free()
	print("SHADOW_RECEIVER_GPU_CONTRACT passed=",valid)
	quit(0 if valid else 1)
