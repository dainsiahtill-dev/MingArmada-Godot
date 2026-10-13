extends SceneTree
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Renderer=preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
class ShipActor extends Node3D:
	var model:Node3D
	func get_model()->Node3D:return model
var assertions:=0
var failures:=0
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL target shadow gates: ",detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	var parent:=Node3D.new();root.add_child(parent)
	var ship:=ShipActor.new();parent.add_child(ship)
	ship.model=Node3D.new();ship.add_child(ship.model)
	ship.model.position=Vector3(2,3,4)
	var renderer:=Renderer.new();renderer.configure(parent,null)
	var adapter:=Adapter.new()
	var caster:={"id":"explicit","actorId":"player","positions":[[0,0,0],[1,0,0],[0,1,0]],"edges":[[0,1],[1,2],[2,0]],"capIndices":[0,1,2],"localLight":[0,0,-1],"worldRotation":[1,0,0,0,1,0,0,0,1]}
	for quality:bool in [false,true]:
		for global_gate:bool in [false,true]:
			for local_gate:bool in [false,true]:
				var explicit:=caster.duplicate(true);explicit.displayShadows=local_gate
				var native:={"sourceShadows":{"displayShadows":global_gate,"casters":[explicit],"texturePlanes":{"player":"fluyt"}}}
				var unchanged:=native.duplicate(true)
				var packet:Dictionary=adapter.compose(native,{"player":ship},Vector3.DOWN,false,quality)
				renderer.apply_snapshot(packet.native,{"player":ship.model})
				check(renderer.diagnostics().volumeCount==int(quality and global_gate and local_gate),"quality/global/caster conjunction %s/%s/%s"%[quality,global_gate,local_gate])
				check(native==unchanged,"adapter preserves explicit caller packet")
				check(renderer.diagnostics().texturePlaneCount==int(quality and global_gate),"quality/global also gates explicit texture plane")
	var native:={"sourceShadows":{"casters":[caster],"texturePlanes":{"player":"fluyt"}}}
	var packet:Dictionary=adapter.compose(native,{"player":ship},Vector3.DOWN,false,true)
	check(packet.actors.get("player")==ship.model,"ship actor ID binds actual source model root")
	renderer.apply_snapshot(packet.native,packet.actors)
	check(renderer.diagnostics().volumeCount==1,"explicit actor ID reaches real renderer")
	check(renderer.diagnostics().texturePlaneCount==1,"explicit source resource binds through source model actor registry")
	renderer.dispose();adapter.dispose();parent.free()
	print("TARGET_SHADOW_GATES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
