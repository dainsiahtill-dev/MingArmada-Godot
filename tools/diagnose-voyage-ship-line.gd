extends SceneTree
const Main=preload("res://game/scenes/main/main_scene.tscn")
var output:="res://docs/research/evidence/playable-voyage-2026-10-14/ship-line-baseline"
var captures:Array=[]
var failures:Array[String]=[]
var frozen:Dictionary={}
const SOURCES=["game/presentation/world/target_shadow_boundary.gd","game/presentation/world/target_rigid_shadow_caster.gd","game/presentation/world/prepared_rigid_shadow.gd","modules/scene_engine/fidelity_fx/source_shadow_math.gd","modules/scene_engine/fidelity_fx/source_shadow_rd.gd","tools/diagnose-voyage-ship-line.gd"]
func hashes()->Dictionary:
	var result:Dictionary={}
	for path:String in SOURCES:result[path]=FileAccess.get_sha256("res://"+path)
	return result
func _initialize()->void:run.call_deferred()
func frames(count:int)->void:
	for _i in count:await process_frame
func capture(scene:Control,name:String)->void:
	await frames(3);await RenderingServer.frame_post_draw
	var image:Image=scene.view.get_texture().get_image()
	image.save_png(output+"/"+name+".png")
	var status:Dictionary=scene.sea.source_shadow_status()
	if not status.get("casterAdapter",{}).get("errors",[]).is_empty():failures.append("caster adapter errors: "+str(status.casterAdapter.errors))
	captures.append({"image":name+".png","sha256":FileAccess.get_sha256(output+"/"+name+".png"),"time":scene.seconds,"camera":scene.camera.global_transform,"shadow":status})
func run()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):printerr("FAIL fresh output required");quit(1);return
	frozen=hashes()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	root.size=Vector2i(1600,1000);root.content_scale_size=root.size
	var main:Node=Main.instantiate();root.add_child(main);await frames(4)
	main.menu.find_child("fidelity-island",true,false).pressed.emit()
	for _i in 150:
		await process_frame
		if is_instance_valid(main.current_scene):break
	var scene:Control=main.current_scene
	if not is_instance_valid(scene) or not scene.startup_receipt.ok:printerr("FAIL no actual shared world");quit(1);return
	scene.set_process(false);scene.paused=true;scene.seconds=24.0;scene._render();await frames(4)
	var sea:Node3D=scene.sea
	var bounds:Array=[]
	for ship:Node3D in sea.ships.values():
		for node:Node in ship.find_children("*","MeshInstance3D",true,false):
			var mesh:=node as MeshInstance3D
			if mesh.mesh==null or not mesh.is_visible_in_tree():continue
			var aabb:AABB=mesh.global_transform*mesh.get_aabb()
			bounds.append({"path":str(mesh.get_path()),"size":[aabb.size.x,aabb.size.y,aabb.size.z],"max_extent":maxf(aabb.size.x,maxf(aabb.size.y,aabb.size.z)),"blend_count":mesh.mesh.get_blend_shape_count() if mesh.mesh is ArrayMesh else 0})
	bounds.sort_custom(func(a:Dictionary,b:Dictionary):return a.max_extent>b.max_extent)
	await capture(scene,"all-retained")
	var effect:CompositorEffect=sea.source_shadows._effect
	if effect:effect.enabled=false
	await capture(scene,"stencil-off")
	if effect:effect.enabled=true
	var hidden:Array=[]
	for ship:Node3D in sea.ships.values():
		for node:Node in ship.find_children("*","MeshInstance3D",true,false):
			if node.visible and ("rig" in str(node.name).to_lower() or "rope" in str(node.name).to_lower()):hidden.append(node);node.hide()
	await capture(scene,"rigging-hidden")
	for node:Node3D in hidden:node.show()
	for ship:Node3D in sea.ships.values():ship.hide()
	await capture(scene,"ship-hidden")
	for ship:Node3D in sea.ships.values():ship.show()
	if hashes()!=frozen:failures.append("source changed during GPU capture")
	var proof:={"valid":captures.size()==4 and failures.is_empty(),"failures":failures,"sources":frozen,"captures":captures,"meshBounds":bounds,"diagnosticHiddenRiggingNodes":hidden.size(),"scope":"Same-time native world diagnostic only. Temporary visibility gates are not production changes or performance claims."}
	var file:=FileAccess.open(output+"/DIAGNOSIS.json",FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	main.free();await frames(2);print("VOYAGE_SHIP_LINE captures=",captures.size()," failures=",failures.size());quit(0 if proof.valid else 1)
