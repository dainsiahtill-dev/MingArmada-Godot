extends SceneTree
## Actual production packets must select the new contact effect without changing
## either the sailing or battle tail history and submitted geometry.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const Renderer=preload("res://modules/scene_engine/water/source_wake_renderer.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func water(_x:float,_z:float,_t:float)->float:return .15
func same_tail(candidate:RefCounted,oracle:RefCounted,label:String)->void:
	var a:Dictionary=candidate._actors.player;var b:Dictionary=oracle._actors.player
	check(a.geometry==b.geometry,label+" tail geometry and draw arguments unchanged")
	check(a.battle_history==b.battle_history,label+" battle history unchanged")
	if a.history!=null:check(a.history.points==b.history.points,label+" scene history unchanged")
	check(a.surface.nodes.keys()==b.surface.nodes.keys(),label+" same submitted tail carriers")
	for key:String in a.surface.nodes:
		var x:MeshInstance3D=a.surface.nodes[key];var y:MeshInstance3D=b.surface.nodes[key]
		check(x.visible==y.visible,label+" visibility "+key)
		if x.mesh==null or y.mesh==null:check(x.mesh==y.mesh,label+" null carrier "+key);continue
		var xa:Array=x.mesh.surface_get_arrays(0);var ya:Array=y.mesh.surface_get_arrays(0)
		for field:int in [Mesh.ARRAY_VERTEX,Mesh.ARRAY_TEX_UV,Mesh.ARRAY_COLOR,Mesh.ARRAY_INDEX]:check(xa[field]==ya[field],label+" exact submitted tail array "+key+" field "+str(field))
func run()->void:
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"real ship configures")
	for route_name:String in ["sailing","battle"]:
		var a:=Node3D.new();var b:=Node3D.new();root.add_child(a);root.add_child(b)
		var candidate:=Renderer.new(a);var tail_oracle:=Renderer.new(b)
		var last:Dictionary={};var last_plain:Dictionary={}
		for tick in 35:
			var now:=float(tick)/32.0
			var state:={"id":"player","kind":"fuchuan","hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":now*3.0,"y":0.0,"z":now*.6},"heading":now*.1,"velocity":{"x":3.0,"z":.6},"pitch":0.0,"heel":0.0}}
			ship.apply_snapshot(state,{},0.0)
			var native:=Packet.compose({"time":now,"environment":{"acceptedTime":now,"sourceCallIndex":tick,"route":route_name,"epoch":3},"ships":[state]},{"player":ship},null)
			var plain:Dictionary=native.duplicate(true)
			plain.ships[0].sourceWake.froth.erase("surfaceProfile")
			candidate.apply_snapshot(native,water,Callable());tail_oracle.apply_snapshot(plain,water,Callable())
			same_tail(candidate,tail_oracle,route_name+" at "+str(tick));last=native;last_plain=plain
		var effect:RefCounted=candidate._actors.player.froth
		check(effect.get_script().resource_path=="res://modules/scene_engine/water/hull_contact_froth.gd","real profile selects new contact-water presentation in "+route_name)
		check(effect.diagnostics().get("target_ribbons",0)==2,"two real waterline ribbons submitted")
		check(absf(float(Packet.compose({"time":2.0,"ships":[{"id":"player","visual":{"velocity":{"x":3.0,"z":4.0}}}]},{"player":ship},null).ships[0].sourceWake.froth.get("targetSpeed",0.0))-5.0)<.00001,"target speed supplied in metres/second independently of native tail input")
		var before:Dictionary=effect.diagnostics().duplicate(true)
		candidate.apply_snapshot(last,water,Callable());tail_oracle.apply_snapshot(last_plain,water,Callable())
		same_tail(candidate,tail_oracle,route_name+" duplicate call")
		check(effect.diagnostics()==before,"duplicate source call does not advance target particles or flow")
		var moved_a:=Node3D.new();var moved_b:=Node3D.new();root.add_child(moved_a);root.add_child(moved_b)
		candidate.transfer_owner(moved_a);tail_oracle.transfer_owner(moved_b)
		candidate.apply_snapshot(last,water,Callable());tail_oracle.apply_snapshot(last_plain,water,Callable())
		same_tail(candidate,tail_oracle,route_name+" quality owner transfer")
		check(effect.diagnostics()==before,"owner transfer preserves the contact effect")
		last.wake.epoch=4;last_plain.wake.epoch=4
		candidate.apply_snapshot(last,water,Callable());tail_oracle.apply_snapshot(last_plain,water,Callable())
		same_tail(candidate,tail_oracle,route_name+" new epoch")
		last.wake.epoch="session-4";last_plain.wake.epoch="session-4"
		candidate.apply_snapshot(last,water,Callable());tail_oracle.apply_snapshot(last_plain,water,Callable())
		same_tail(candidate,tail_oracle,route_name+" changed epoch ID type")
		check(candidate._epoch is String and tail_oracle._epoch is String,"epoch ID type change starts a fresh owner")
		candidate.dispose();tail_oracle.dispose();a.free();b.free()
		moved_a.free();moved_b.free()
	ship.dispose();ship.free()
	print("HULL_CONTACT_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
