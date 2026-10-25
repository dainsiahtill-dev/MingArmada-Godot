extends SceneTree
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
const Froth=preload("res://modules/scene_engine/water/hull_contact_froth.gd")
var assertions:=0
var failures:=0
func check(v:bool,why:String)->void:
	assertions+=1
	if not v:failures+=1;printerr("FAIL: ",why)
func _initialize()->void:run.call_deferred()
func run()->void:
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"production flagship configures")
	var state={"id":"hero","kind":"fuchuan","time":0.0,"hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"velocity":{"x":3.086664,"z":0.0},"heading":0.0,"pitch":0.0,"heel":0.0}}
	ship.apply_snapshot(state,{},0)
	var source:Dictionary=Packet.compose({"time":0.0,"environment":{"route":"sailing","acceptedTime":0.0,"sourceCallIndex":0},"ships":[state]},{"hero":ship},null).ships[0].sourceWake
	var packet:Dictionary=source.duplicate(true);packet.merge(source.froth,true);packet.targetSpeed=3.086664
	check(packet.sourceToWorld>.021 and packet.sourceToWorld<.022,"meter-authored mesh preserves the existing effect-coordinate conversion")
	check(packet.family==3,"authored flagship explicitly selects the fuchuan water-effects family")
	check(packet.surfaceProfile.beam>6.5 and packet.surfaceProfile.beam<9,"water contact uses new hull, not the old roughly5m reference profile")
	var owner:=Node3D.new();root.add_child(owner);var froth:=Froth.new()
	check(froth.configure(owner,int(packet.family),1650,str(packet.sourceResourceName)).ok,"production contact accepts original asset identity")
	for i in 17:froth.apply_snapshot(packet,i*.025,func(_x:float,_z:float,_t:float)->float:return 0.0,Callable())
	var diagnostic:Dictionary=froth.diagnostics()
	check(diagnostic.target_births>0 and diagnostic.target_droplets>0 and diagnostic.target_droplets<=48,"level new bow at real waterline emits bounded spray")
	check(diagnostic.target_ribbons==2,"new hull retains both contact ribbons")
	check(absf(diagnostic.flow_distance-3.086664*.4)<.0001,"contact flow keeps accepted speed/time units")
	froth.dispose();check(owner.get_child_count()==0,"contact nodes release")
	owner.free();ship.dispose();ship.free();await process_frame
	print("HERO_FUCHUAN_WATER_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
