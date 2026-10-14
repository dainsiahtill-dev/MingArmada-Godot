extends SceneTree
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const DIMENSIONS="res://tests/fixtures/ship_water_interaction_dimensions.json"
var assertions:=0
var failures:=0
var producer:Script
var water_calls:=0
func check(ok:bool,label:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL ship water interaction: ",label)
func near(a:float,b:float)->bool:return absf(a-b)<0.001
func flat(_x:float,_z:float,_t:float)->float:return 0.0
func current(_x:float,_z:float,_t:float)->Dictionary:return {"height":0.0,"flow":Vector2(1,-2)}
func invalid_water(_x:float,_z:float,_t:float)->float:
	water_calls+=1
	return NAN if water_calls==3 else 0.0
func _initialize()->void:run.call_deferred()
func run()->void:
	var file:="res://modules/scene_engine/water/ship_water_interaction.gd"
	if not ResourceLoader.exists(file):check(false,"actual3D interaction producer exists; yaw-only trail cannot supply heave");finish();return
	producer=load(file)
	var dimensions:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(DIMENSIONS))
	var metrics:Array=[]
	for kind:String in ["fuchuan","fisherman","merchant","heavy"]:
		var ship:=Ship.new();root.add_child(ship);check(ship.configure(kind),"real model configures: "+kind)
		var input:RefCounted=producer.new();var attachment:Dictionary=ship.source_water_attachment()
		var born:Dictionary=input.sample(kind,attachment,10.0,flat)
		check(born.diagnostics.accepted and born.emitters.size()==5,"five valid actual-profile probes: "+kind)
		check(near(born.diagnostics.beam_m,dimensions[kind].beam_m) and near(born.diagnostics.length_m,dimensions[kind].length_m),"world metres match measured original models: "+kind)
		check(born.wake.is_empty(),"new actor cannot create wake from unknown velocity")
		var total_weight:=0.0
		for emitter:Dictionary in born.emitters:
			check(emitter.velocity==Vector3.ZERO and near(emitter.wetness,1.0),"first accepted pose has no invented velocity and meets water")
			check(emitter.radius>0.0 and is_finite(emitter.radius),"finite world-metre probe radius")
			total_weight+=emitter.weight
		check(near(total_weight,1.0),"five weights sum to one")
		ship.position.y=.1
		var lifted:Dictionary=input.sample(kind,ship.source_water_attachment(),10.1,flat)
		for emitter:Dictionary in lifted.emitters:
			check(emitter.velocity.distance_to(Vector3(0,1,0))<.001,"stationaryXZ risingY supplies actual1m/s vertical rate: "+kind)
			check(emitter.wetness>0 and emitter.weight>0,"stationary heave remains a live local interaction")
		check(lifted.wake.is_empty(),"stationary heave emits no long wake foam")
		ship.position+=Vector3(.3,.1,-.4)
		var moving:Dictionary=input.sample(kind,ship.source_water_attachment(),10.2,flat)
		check(near(moving.wake.speed,5.0) and near(moving.wake.beam,dimensions[kind].beam_m),"wake speed5m/s and realbeam retained")
		for emitter:Dictionary in moving.emitters:check(emitter.velocity.distance_to(Vector3(3,1,-4))<.001,"three-axis accepted finite difference")
		check(moving.wake.stern.y>.19 and ship.source_water_attachment().flowStern.y==0,"full-pose stern independent of legacy yaw-only attachment")
		ship.position.y+=.02
		var stopped:Dictionary=input.sample(kind,ship.source_water_attachment(),10.3,flat)
		check(stopped.wake.is_empty(),"stop suppresses freshwake source")
		check(stopped.emitters[0].velocity.y>.19 and stopped.emitters[0].wetness>0,"stopped ship still pushes water vertically")
		ship.position.y=20
		var dry:Dictionary=input.sample(kind,ship.source_water_attachment(),10.4,flat)
		for emitter:Dictionary in dry.emitters:check(emitter.wetness==0.0,"fully dry sphere has exactly zero strength")
		check(dry.wake.is_empty(),"dry ship emits no newwake")
		ship.position=Vector3.ZERO;ship.scale=Vector3(2,2,2)
		input.clear()
		var scaled:Dictionary=input.sample(kind,ship.source_water_attachment(),11.0,flat)
		check(near(scaled.diagnostics.beam_m,dimensions[kind].beam_m*2) and near(scaled.diagnostics.length_m,dimensions[kind].length_m*2),"model scale changes physical beam and length exactly")
		ship.rotation=Vector3(.18,.41,-.14);input.clear()
		var rotated_attachment:Dictionary=ship.source_water_attachment()
		var rotated:Dictionary=input.sample(kind,rotated_attachment,12.0,flat)
		for probe:Dictionary in rotated.diagnostics.probes:
			check(probe.position.distance_to(rotated_attachment.surfaceProfile.hullToWorld*probe.local_position)<.0001,"each probe uses complete pitch/yaw/roll/scale transform")
		check(near(rotated.diagnostics.beam_m,dimensions[kind].beam_m*2),"roll does not incorrectly shrink world beam")
		metrics.append({"kind":kind,"beam_m":born.diagnostics.beam_m,"length_m":born.diagnostics.length_m,"radius_m":born.emitters[0].radius,"vy":lifted.emitters[0].velocity.y,"speed":moving.wake.speed,"dryWetness":dry.emitters[0].wetness})
		input.clear();ship.dispose();ship.free()
	lifecycle()
	boundaries()
	print("SHIP_WATER_INTERACTION_MODELS ",JSON.stringify(metrics))
	finish()
func lifecycle()->void:
	var ship:=Ship.new();root.add_child(ship);ship.configure("fuchuan")
	var input:RefCounted=producer.new();input.sample("a",ship.source_water_attachment(),1.0,flat)
	ship.position=Vector3(100,100,100)
	var duplicate:Dictionary=input.sample("a",ship.source_water_attachment(),1.0,flat)
	check(not duplicate.diagnostics.accepted and duplicate.emitters.is_empty() and duplicate.wake.is_empty(),"same-time changed pose yields no input and no baseline mutation")
	ship.position=Vector3(.2,.1,0)
	var next:Dictionary=input.sample("a",ship.source_water_attachment(),1.1,flat)
	check(next.emitters[0].velocity.distance_to(Vector3(2,1,0))<.001,"duplicate ignored by next derivative")
	next.emitters[0].position=Vector3(1000,1000,1000)
	ship.position=Vector3(.4,.2,0)
	var bad:Dictionary=ship.source_water_attachment().duplicate(true);bad.surfaceProfile.sections[3].left=NAN
	var rejected:Dictionary=input.sample("a",bad,1.2,flat)
	check(not rejected.diagnostics.accepted and rejected.emitters.is_empty(),"invalid geometry rejected atomically")
	water_calls=0
	var rejected_water:Dictionary=input.sample("a",ship.source_water_attachment(),1.2,invalid_water)
	check(not rejected_water.diagnostics.accepted and rejected_water.emitters.is_empty(),"late invalid water sample rejects whole packet")
	var after_invalid:Dictionary=input.sample("a",ship.source_water_attachment(),1.2,flat)
	check(after_invalid.emitters[0].velocity.distance_to(Vector3(2,1,0))<.001,"invalid input and caller mutation cannot poison history")
	ship.position=Vector3(500,.2,0)
	var warped:Dictionary=input.sample("a",ship.source_water_attachment(),1.3,flat)
	check(warped.diagnostics.reason=="teleport" and warped.emitters[0].velocity==Vector3.ZERO and warped.wake.is_empty(),"largewarp clears derivative and no connecting wake")
	ship.position.x+=.2
	var after_warp:Dictionary=input.sample("a",ship.source_water_attachment(),1.4,flat)
	check(near(after_warp.emitters[0].velocity.x,2.0),"next accepted pose recovers afterwarp")
	var rewound:Dictionary=input.sample("a",ship.source_water_attachment(),.5,flat)
	check(rewound.diagnostics.reason=="rewind" and rewound.emitters[0].velocity==Vector3.ZERO,"rewind resets derivative")
	input.forget("a");var forgotten:Dictionary=input.sample("a",ship.source_water_attachment(),.6,flat)
	check(forgotten.diagnostics.reason=="first" and forgotten.emitters[0].velocity==Vector3.ZERO,"forget bounds lifetime and newidentity starts stationary")
	input.sample("b",ship.source_water_attachment(),.6,flat)
	var dead:Dictionary=input.sample("a",{},.6,flat,false)
	check(dead.emitters.is_empty() and dead.wake.is_empty() and dead.diagnostics.actor_count==1,"dead hull removes only its own state even same time")
	input.clear();var reset:Dictionary=input.sample("a",ship.source_water_attachment(),.7,flat)
	check(reset.diagnostics.actor_count==1 and reset.diagnostics.reason=="first","clear removes all actors")
	input.clear();ship.position=Vector3.ZERO;input.sample("c",ship.source_water_attachment(),2.0,current)
	ship.position=Vector3(.3,.1,.2)
	var relative:Dictionary=input.sample("c",ship.source_water_attachment(),2.1,current)
	check(relative.emitters[0].velocity.distance_to(Vector3(2,1,4))<.001,"subtract horizontal ambientflow only; preserve actualvy")
	check(near(relative.wake.speed,sqrt(20.0)),"wake speed uses horizontal relative flow in metres per second")
	input.clear();ship.position=Vector3.ZERO;ship.rotation=Vector3.ZERO
	input.sample("bobbing",ship.source_water_attachment(),3.0,flat)
	ship.rotation.x=.4
	var frame:Transform3D=ship.source_water_attachment().surfaceProfile.hullToWorld
	var tilted_water:Callable=func(x:float,z:float,_t:float)->float:return frame.origin.y-(frame.basis.y.x*(x-frame.origin.x)+frame.basis.y.z*(z-frame.origin.z))/frame.basis.y.y
	var bobbing:Dictionary=input.sample("bobbing",ship.source_water_attachment(),3.1,tilted_water)
	check(bobbing.diagnostics.advanced and bobbing.emitters[0].velocity.length()>0,"fixed origin pitching generates real local motion")
	check(bobbing.wake.is_empty() and near(bobbing.diagnostics.speed_mps,0),"fixed origin pitching alone cannot pretend forward travel for fresh longwake")
	ship.dispose();ship.free();input.clear()
func boundaries()->void:
	var ship:=Ship.new();root.add_child(ship);ship.configure("fuchuan")
	var input:RefCounted=producer.new();var first:Dictionary=input.sample("wet",ship.source_water_attachment(),0.0,flat)
	var radius:float=first.diagnostics.radius_m
	ship.position.y=radius*.5
	var half:Dictionary=input.sample("wet",ship.source_water_attachment(),.1,flat)
	check(near(half.emitters[0].wetness,.75),"sphere/plane intersection area has explicit .75 support at half radius")
	ship.position.y=radius
	var tangent:Dictionary=input.sample("wet",ship.source_water_attachment(),.2,flat)
	check(tangent.emitters[0].wetness<=.000001,"sphere tangent abovewater has no surface support")
	ship.position.y=-radius*1.1
	var submerged:Dictionary=input.sample("wet",ship.source_water_attachment(),.3,flat)
	check(submerged.emitters[0].wetness==0.0,"deeply submerged sphere has no local interface source; not a buoyancy model")
	var gap:Dictionary=input.sample("wet",ship.source_water_attachment(),2.0,flat)
	check(gap.diagnostics.reason=="gap" and gap.emitters[0].velocity==Vector3.ZERO,"long acceptedtime gap resets derivative")
	ship.position.y+=.000001
	var tiny:Dictionary=input.sample("wet",ship.source_water_attachment(),2.0000001,flat)
	check(tiny.diagnostics.reason=="small-interval" and tiny.emitters[0].velocity==Vector3.ZERO,"tiny accepted interval cannot amplify noisy displacement")
	var valid:Dictionary=ship.source_water_attachment()
	var invalid:Dictionary=valid.duplicate(true);invalid.surfaceProfile.hullToWorld=Transform3D(Basis(Vector3.ZERO,Vector3.ZERO,Vector3.ZERO),Vector3.ZERO)
	check(not input.sample("wet",invalid,2.1,flat).diagnostics.accepted,"singular fullpose rejected")
	check(not input.sample("wet",valid,NAN,flat).diagnostics.accepted,"nonfinite time rejected")
	check(not input.sample("wet",valid,-1.0,flat).diagnostics.accepted,"negative time rejected")
	check(not input.sample("wet",valid,2.1,Callable()).diagnostics.accepted,"missing water callback rejected")
	input.clear();ship.position=Vector3.ZERO;input.sample("limited",ship.source_water_attachment(),3.0,flat)
	ship.position.x=3.0
	var limited:Dictionary=input.sample("limited",ship.source_water_attachment(),3.1,flat)
	check(limited.diagnostics.reason=="advance" and limited.diagnostics.clamped_velocities==5,"finite highspeed clamps rather than treating30m/s as warp")
	check(near(limited.emitters[0].velocity.length(),20.0) and near(limited.wake.speed,20.0),"declared20m/s numerical input ceiling")
	input.clear();valid=ship.source_water_attachment()
	for i in 64:input.sample("actor%d"%i,valid,0.0,flat)
	var full:Dictionary=input.sample("overflow",valid,0.0,flat)
	check(not full.diagnostics.accepted and full.diagnostics.actor_count==64,"bounded actor history rejectsoverflow without eviction")
	input.forget("actor0")
	check(input.sample("overflow",valid,0.0,flat).diagnostics.accepted,"forget releases capacity for newactor")
	input.clear();ship.dispose();ship.free()
func finish()->void:
	print("SHIP_WATER_INTERACTION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
