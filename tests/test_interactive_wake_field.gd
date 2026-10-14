extends SceneTree
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool, why: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", why)
func centroids(reference) -> Vector3:
	var left:=0.0;var right:=0.0;var left_mass:=0.0;var right_mass:=0.0
	for y in reference.resolution:
		for x in reference.resolution:
			var amount:float=reference.foam[y*reference.resolution+x]
			if x<reference.resolution/2:left+=amount*x;left_mass+=amount
			else:right+=amount*x;right_mass+=amount
	return Vector3(left/maxf(left_mass,0.000001),right/maxf(right_mass,0.000001),left_mass+right_mass)
func run() -> void:
	var Reference = load("res://tests/helpers/interactive_wake_reference.gd")
	var reference = Reference.new(9)
	reference.h[40] = 0.1; reference.foam[40] = 1.0
	reference.step(0.1, 1.0, 1.0, 0.0, 1.0, 0.1)
	check(abs(reference.h[40] - 0.096) < 0.00000001, "impulse loses height to four neighbors by the wave equation")
	check(abs(reference.h[41] - 0.001) < 0.00000001, "impulse reaches adjacent water")
	check(abs(reference.foam[40] - 0.96*exp(-0.1)) < 0.00000001, "foam diffuses then decays by accepted dt")
	check(abs(reference.foam[41] - 0.01*exp(-0.1)) < 0.00000001, "foam spreads beyond the original source")
	var transported = Reference.new(9)
	transported.foam[40]=1.0
	transported.step(0.5,1.0,0.0,0.0,0.0,0.0,Vector2.ZERO,Vector2(1,0))
	check(abs(transported.foam[40]-0.5)<0.000001 and abs(transported.foam[41]-0.5)<0.000001,"positive water flow transports stored density downflow")
	transported.step(0.0,1.0,0.0,0.0,0.0,0.0,Vector2(1,0))
	check(abs(transported.foam[39]-0.5)<0.000001,"window origin advances while water history keeps world position")
	var drifting=Reference.new(33)
	drifting.foam[16*33+10]=0.5;drifting.foam[16*33+22]=0.5
	for y in 33:
		for x in 33:drifting.drift_x[y*33+x]=-0.5 if x<16 else 0.5
	var born:=centroids(drifting)
	for i in 20:drifting.step(0.1,1.0,0.0,0.0,0.214,0.04)
	var aged:=centroids(drifting)
	check(aged.x<born.x-0.5 and aged.y>born.y+0.5,"stored left/right foam continues separating after birth sources stop")
	check(aged.z>0.0 and aged.z<born.z,"outward-moving foam persists while density decays")
	check(drifting.drift_x[16*33+10]<-0.2 and abs(drifting.drift_z[16*33+10])<0.000001,"old world drift direction is retained without current ship heading")
	var path := "res://modules/scene_engine/water/interactive_wake_field.gd"
	check(ResourceLoader.exists(path), "interactive field owner must exist instead of a static trail")
	if ResourceLoader.exists(path):
		var field = load(path).new()
		check(not field.diagnostics().ready, "unconfigured field cannot claim a valid sea surface")
		check(field.has_method("acquire_surface") and field.has_method("acknowledge_surface"),"surface publication requires consumer binding acknowledgement before slot reuse")
		if field.has_method("acquire_surface"):
			check(field.acquire_surface().is_empty(),"no surface lease before GPU readiness")
			field.acknowledge_surface(100)
			check(not field.diagnostics().pending,"stale ACK on unconfigured owner does not submit GPU work")
		var saved_texture: Texture2D=field.surface_texture()
		check(not field.configure({"resolution":3}).get("ok",true),"invalid grid rejected before allocating GPU resources")
		var invalid_mask: Dictionary=field.configure({"wet_mask":{"resolution":2,"bounds":Vector4(0,0,2,2),"data":PackedByteArray([255])}})
		check("wet_mask" in str(invalid_mask.get("error","")),"malformed static R8 terrain mask rejected before device access")
		var es: Array=[]
		for i in 20:es.append({"position":Vector3(i,0,0),"velocity":Vector3(0,1,0),"radius":1.0,"wetness":1.0,"weight":0.2,"id":str(i)})
		var selected: Dictionary=field.prepare_request(1.0,Vector2.ZERO,es,[])
		check(selected.emitters.size()==16 and selected.omitted_emitters==4,"near-view emitter upload bounded to16")
		check(selected.emitters[0].id=="0" and selected.emitters[15].id=="15","closest inputs chosen deterministically")
		es[0].position=Vector3(100,0,0)
		check(selected.emitters[0].position==Vector3.ZERO,"queued inputs own immutable copies")
		var candidates: Array=[]
		for pair in [["z",400.0],["m",400.003],["a",400.006]]:
			candidates.append({"position":Vector3(sqrt(pair[1]),0,0),"velocity":Vector3.ZERO,"radius":1.0,"wetness":1.0,"weight":0.2,"id":pair[0]})
		for order in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]]:
			var near: Array=[]
			for i in 15:near.append({"position":Vector3(i,0,0),"velocity":Vector3.ZERO,"radius":1.0,"wetness":1.0,"weight":0.2,"id":str(i)})
			for index in order:near.append(candidates[index])
			check(field.prepare_request(1.0,Vector2.ZERO,near,[]).emitters[15].id=="z","near-boundary selection is independent of input permutation")
		es[2].wetness=NAN
		check(field.prepare_request(2.0,Vector2.ZERO,es,[]).has("error"),"invalid emitter rejects whole snapshot")
		check(field.prepare_request(NAN,Vector2.ZERO,[],[]).has("error"),"invalid clock rejected")
		check(field.prepare_request(1e300,Vector2.ZERO,[],[]).has("error"),"finite but unrepresentable simulation gap rejected before integer step conversion")
		var shape: Dictionary=field._load_shape()
		check(not shape.is_empty() and shape.data.size()==shape.size.x*shape.size.y*4,"native DDS shape decoded onCPU without GPU readback")
		var planner=load("res://modules/scene_engine/water/interactive_wake_field_rd.gd").new()
		planner.options={"resolution":256,"extent_m":96.0,"fixed_step":1.0/60.0}
		var first: Dictionary=planner.plan_advance({"seconds":10.0,"center":Vector2.ZERO})
		check(first.reset and first.steps==0,"first timestamp resets instead of simulating from wall-clock0")
		var step: Dictionary=planner.plan_advance({"seconds":10.03125,"center":Vector2.ZERO})
		check(step.steps==1 and planner.tick==1,"accepted32Hz motion advances fixed60Hz with remainder")
		var paused: Dictionary=planner.plan_advance({"seconds":10.03125,"center":Vector2(0.375,0)})
		check(paused.steps==0 and not paused.reset and paused.origin==Vector2(-47.625,-48),"pause permits world remap without time or force")
		var rewind: Dictionary=planner.plan_advance({"seconds":9.0,"center":Vector2.ZERO})
		check(rewind.reset and rewind.steps==0,"rewind resets history and fractional accumulator")
		var overload: Dictionary=planner.plan_advance({"seconds":10.0,"center":Vector2.ZERO})
		check(overload.steps==8 and planner.dropped_steps==52,"catchup bounded8 and dropped simulation steps explicit")
		check(planner.plan_advance({"seconds":10.0,"center":Vector2(200,0)}).reset,"teleported window resets rather than stitching distant history")
		check(planner.plan_advance({"seconds":1e18,"center":Vector2.ZERO}).has("error") and planner.time==10.0,"oversized finite gap cannot overflow step count or mutate clock")
		field.dispose(); field.dispose()
		check(field.diagnostics().disposed, "disposal is idempotent before GPU creation")
		check(field.surface_texture()==saved_texture,"stable texture wrapper survives lifecycle")
	print("INTERACTIVE_WAKE_FIELD assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
