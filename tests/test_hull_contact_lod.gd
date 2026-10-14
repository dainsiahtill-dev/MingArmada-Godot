extends SceneTree
## Distance changes sampling/submission density while preserving accepted simulation.
const Contact=preload("res://modules/scene_engine/water/hull_contact_froth.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Packet=preload("res://game/presentation/world/source_water_packet.gd")
var assertions:=0
var failures:=0
var water_calls:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func water(_x:float,_z:float,_time:float)->float:water_calls+=1;return .15
func packet()->Dictionary:
	var sections:=[{"z":-6.0,"left":-.2,"right":.2},{"z":-4.0,"left":-1.0,"right":1.0},{"z":4.0,"left":-1.0,"right":1.0},{"z":6.0,"left":-.2,"right":.2}]
	return {"enabled":true,"targetSpeed":3.0,"targetVelocity":[0.0,0.0,3.0],"sourceToWorld":1.0,"worldOrigin":[0.0,0.0,0.0],"sourceBowPosition":[0.0,-6.0,0.0],"epoch":1,"surfaceProfile":{"sections":sections,"verticalSections":[{"height":-1.0,"sections":sections},{"height":1.0,"sections":sections}],"hullToWorld":Transform3D.IDENTITY,"worldToHull":Transform3D.IDENTITY}}
func simulation(effect:RefCounted)->PackedByteArray:
	return var_to_bytes({"drops":effect._droplets,"flow":effect.diagnostics().flow_distance,"births":effect.diagnostics().target_births,"time":effect.diagnostics().visual_time})
func run()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var effect:=Contact.new();effect.configure(owner,0,77)
	var input:=packet();effect.apply_snapshot(input,0.0,water,Callable())
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==240,"no camera retains48by5 near geometry")
	for tick in range(1,9):effect.apply_snapshot(input,float(tick)/32.0,water,Callable())
	var before:=simulation(effect);var rebuilds:int=effect.diagnostics().get("mesh_rebuilds",0);var uploads:int=effect.diagnostics().get("region_uploads",0)
	effect.apply_snapshot(input,9.0/32.0,water,Callable())
	check(effect.diagnostics().get("mesh_rebuilds",0)==rebuilds and effect.diagnostics().get("region_uploads",0)>uploads,"stable topology uses dynamic regions rather than per-frame surface rebuilds")
	before=simulation(effect)
	water_calls=0;effect.apply_snapshot(input,9.0/32.0,water,Callable());var near_samples:=water_calls
	input.targetCameraDistance=70.0;water_calls=0;effect.apply_snapshot(input,9.0/32.0,water,Callable());var medium_samples:=water_calls
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==72,"medium camera submits24by3 geometry")
	check(simulation(effect)==before,"near-to-medium same-time switch preserves world droplets/flow/births/time")
	input.targetCameraDistance=180.0;water_calls=0;effect.apply_snapshot(input,9.0/32.0,water,Callable());var far_samples:=water_calls
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==36,"far camera submits12by3 geometry")
	check(medium_samples<near_samples*.65 and far_samples<medium_samples*.65,"camera distance reduces actual sea queries at both steps")
	check(simulation(effect)==before,"medium-to-far switch does not reset droplet simulation")
	effect.redraw_camera({"targetDistance":10.0})
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==240 and simulation(effect)==before,"paused camera zoom redraws near detail without advancing owner")
	effect.redraw_camera({"targetDistance":44.0})
	effect.redraw_camera({"targetDistance":46.0})
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==240,"near threshold hysteresis avoids repeated resize at44/46m")
	effect.redraw_camera({"targetDistance":49.0})
	effect.redraw_camera({"targetDistance":44.0})
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==72,"medium threshold hysteresis retains detail until43m")
	input.targetCameraDistance=NAN;effect.apply_snapshot(input,9.0/32.0,water,Callable())
	check(effect._nodes.FlowPort.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()==240,"invalid camera distance safely falls back to near")
	input.enabled=false;input.targetSpeed=0.0;input.targetVelocity=[0.0,0.0,0.0]
	for tick in range(10,75):effect.apply_snapshot(input,float(tick)/32.0,water,Callable())
	water_calls=0;effect.apply_snapshot(input,3.0,water,Callable())
	check(water_calls==0 and effect.diagnostics().target_droplets==0,"fully faded stop has zero sea sampling at all detail levels")
	effect.dispose();owner.free()
	var counts:Array=[]
	for distance:float in [10.0,70.0,180.0]:
		owner=Node3D.new();root.add_child(owner);effect=Contact.new();effect.configure(owner,0,77)
		input=packet();input.targetCameraDistance=distance
		for tick in 65:effect.apply_snapshot(input,float(tick)/32.0,water,Callable())
		counts.append(effect.diagnostics().target_births)
		effect.dispose();owner.free()
	check(counts[0]>counts[1] and counts[1]>counts[2],"medium/far density reduces actual spray births")
	owner=Node3D.new();root.add_child(owner);effect=Contact.new();effect.configure(owner,0,77)
	input=packet();input.surfaceProfile.hullToWorld.origin.y=2.0;input.surfaceProfile.worldToHull=input.surfaceProfile.hullToWorld.affine_inverse();input.sourceBowPosition[2]=2.0
	water_calls=0;effect.apply_snapshot(input,0.0,water,Callable())
	check(effect.diagnostics().target_ribbons==0 and water_calls<=250,"fully dry hull resolves row contact without sampling invisible unsubmitted vertices")
	effect.dispose();owner.free()
	owner=Node3D.new();root.add_child(owner);effect=Contact.new();effect.configure(owner,0,77)
	input=packet();input.surfaceProfile.hullToWorld.origin.x=1000.0;input.surfaceProfile.worldToHull=input.surfaceProfile.hullToWorld.affine_inverse();input.sourceBowPosition[0]=1000.0
	for tick in 9:effect.apply_snapshot(input,float(tick)/32.0,water,Callable())
	var bounds:AABB=effect._nodes.ContactSpray.mesh.custom_aabb
	check(effect.diagnostics().target_droplets>0 and bounds.size.length()<10.0 and bounds.position.x>990.0,"unused spray slots do not stretch distant ship culling bounds to world origin")
	effect.dispose();owner.free()
	var ship:=Ship.new();root.add_child(ship);check(ship.configure("fuchuan"),"native camera-distance packet uses real ship")
	var state:={"id":"player","kind":"fuchuan","hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":20.0,"y":0.0,"z":10.0},"heading":0.0,"velocity":{"x":3.0,"z":0.0}}}
	ship.apply_snapshot(state,{},0.0)
	var camera:=Camera3D.new();root.add_child(camera);camera.global_position=ship.global_position+Vector3(0,0,70)
	var output:Dictionary=Packet.compose({"time":0.0,"ships":[state]},{"player":ship},camera)
	var distance:=float(output.ships[0].sourceWake.froth.get("targetCameraDistance",-1.0))
	check(absf(distance-70.0)<.0001,"production packet supplies world-metre camera distance")
	check(absf(float(output.ships[0].sourceWake.froth.sourceCamera.get("targetDistance",-1.0))-70.0)<.0001,"paused renderer receives distance metadata inside camera packet")
	output=Packet.compose({"time":0.0,"ships":[state]},{"player":ship},null)
	check(not output.ships[0].sourceWake.froth.has("targetCameraDistance"),"null camera retains legacy near default")
	camera.free();ship.dispose();ship.free()
	print("HULL_CONTACT_LOD_EVIDENCE samples=",[near_samples,medium_samples,far_samples]," births=",counts)
	print("HULL_CONTACT_LOD_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
