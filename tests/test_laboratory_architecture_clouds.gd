extends SceneTree
## Optional paired clouds must not become another physics or clock owner.
const Catalog=preload("res://game/research/catalog.gd")
const Demo=preload("res://game/research/demos/architecture_convergence_experiment.gd")
const BillboardContracts=preload("res://tests/test_cloud_billboard_reuse.gd")
const TOPIC="architecture-convergence-2026-10-21"
const STEP=1.0/60.0
var assertions:=0
var failures:=0

func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL architecture cloud laboratory: ",message)

func _initialize()->void:run.call_deferred()

func physical(state:Dictionary)->PackedByteArray:
	return var_to_bytes([state.tick,state.time,state.seed,state.baseline,state.candidate,state.counts])

func source_time(state:Dictionary)->float:
	var environment:Dictionary=state.get("candidate",{}).get("environment",{})
	return float(environment.acceptedTime) if environment.has("acceptedTime") else float(state.render_time)

func cloud_contract(state:Dictionary,context:String)->bool:
	var clouds:Dictionary=state.get("clouds",{})
	var shape:=clouds.has_all(["enabled","ready","variant","exact","baselineHash","candidateHash","sourceTime","resources"])
	check(shape,"public cloud inspection is complete "+context)
	if not shape:return false
	check(clouds.enabled and clouds.ready and clouds.exact,"both real cloud observers are ready and byte-exact "+context)
	check(clouds.baselineHash is String and clouds.candidateHash is String and clouds.baselineHash.length()==64 and clouds.baselineHash==clouds.candidateHash,"complete published baseline/candidate state hashes match "+context)
	check(clouds.resources.get("renderers",-1)==2 and clouds.resources.get("parents",-1)==2,"paired renderers keep distinct owned scene parents "+context)
	check(is_finite(float(clouds.sourceTime)) and clouds.sourceTime==source_time(state),"cloud source time follows accepted environment packet or supplied render time "+context)
	return true

func viewport()->SubViewport:
	var view:=SubViewport.new();view.own_world_3d=true;view.size=Vector2i(800,450);root.add_child(view)
	return view

func run()->void:
	var catalog:=Catalog.new()
	check(catalog.load_catalog().ok,"existing bundled catalog loads")
	check(catalog.demo_path(TOPIC)=="res://game/research/demos/architecture_convergence_experiment.gd" and catalog.read_paper(TOPIC).get("ok",false),"home laboratory retains the existing topic, paper and demo")
	var demo:Node3D=Demo.new()
	var configured:Dictionary=demo.configure({"clouds":true,"billboard_variant":"candidate","paused":true})
	check(configured.get("ok",false),"existing architecture demo accepts optional clouds and billboard candidate factors")
	# RED stops at unsupported optional factor, rather than emitting secondary errors.
	if not configured.get("ok",false):demo.free();finish();return
	check(configured.get("pending",false) and not configured.get("ready",true) and demo.get_child_count()==0,"detached cloud configure validates without allocating scene owners")
	var pending:Dictionary=demo.inspection_snapshot().get("clouds",{})
	check(pending.get("enabled",false) and not pending.get("ready",true),"cloud observation remains pending before mount")
	check(demo.get_default_options().get("clouds",true)==false,"cloud experiment stays disabled by default")
	var view:=viewport();view.add_child(demo)
	var initial:Dictionary=demo.inspection_snapshot()
	print("ARCHITECTURE_CLOUD_COMPILERS ",JSON.stringify(initial.get("clouds",{}).get("compilerPaths",{})))
	if not cloud_contract(initial,"mounted origin"):
		demo.dispose();view.free();finish();return
	check(initial.clouds.get("compilerPaths",{}).get("baseline","")=="res://game/research/fixtures/cloud_billboard_baseline.gd","cloud baseline reports the actual frozen compiler binding")
	check(initial.clouds.get("compilerPaths",{}).get("candidate","")=="res://game/research/demos/architecture_billboard_candidate.gd","cloud candidate reports the actual research compiler binding")
	var visible_carrier_id:int=initial.clouds.get("visibleCarrierId",0)
	check(visible_carrier_id>0 and initial.clouds.get("visibleCarrierCount",0)==1,"cloud comparison exposes exactly one real visible carrier")
	check(initial.ready and initial.tick==0 and initial.time==0.0 and initial.seed==1661,"cloud option retains declared physical origin")
	check(initial.resources.simulations==2 and initial.resources.ship==1 and initial.resources.ocean==1,"cloud factor preserves original physics, ship and ocean workload")
	check(initial.clouds.variant=="candidate" and initial.parameters.clouds and initial.parameters.billboard_variant=="candidate","selected observer is reported independently of physics variant")
	check(not demo.is_processing() and not demo.is_physics_processing(),"laboratory host remains sole elapsed-time caller")
	var controls:Dictionary={}
	for specification:Dictionary in demo.control_spec():controls[specification.id]=specification
	check(controls.has("clouds") and controls.clouds.type=="toggle","host exposes cloud factor toggle")
	var variants:Array=[]
	if controls.has("billboard_variant"):
		for choice:Dictionary in controls.billboard_variant.get("choices",[]):variants.append(choice.value)
	check(controls.has("billboard_variant") and controls.billboard_variant.type=="choice" and variants==["baseline","candidate"],"host exposes both billboard observation choices")
	var before:=var_to_bytes(initial)
	var requested:Dictionary=demo.set_parameter("clouds",false)
	check(requested.get("ok",false) and requested.get("reset_required",false) and var_to_bytes(demo.inspection_snapshot())==before,"cloud allocation factor requests explicit reset without mutating live owners or options")
	demo.set_paused(false);demo.advance(STEP)
	var first:Dictionary=demo.inspection_snapshot()
	check(first.tick==1 and first.time==STEP and first.baseline==first.candidate and first.telemetry.exact,"one accepted host step advances exactly two matching simulation authorities")
	check(first.counts.full_terrain==25 and first.counts.scalar_terrain==5 and first.counts.full_samples==5 and first.counts.scalar_samples==5 and first.counts.candidate_full_samples==0,"optional cloud observation preserves original production sampler workload")
	cloud_contract(first,"first accepted tick")
	demo.set_paused(true)
	var authority:=physical(demo.inspection_snapshot())
	var cloud_bytes:=var_to_bytes(demo.inspection_snapshot().clouds)
	demo.advance(30.0)
	check(physical(demo.inspection_snapshot())==authority and var_to_bytes(demo.inspection_snapshot().clouds)==cloud_bytes,"paused elapsed time cannot advance cloud source or physical authority")
	for variant:String in ["baseline","candidate","baseline","candidate"]:
		var changed:Dictionary=demo.set_parameter("billboard_variant",variant)
		var selected:Dictionary=demo.inspection_snapshot()
		check(changed.get("ok",false) and not changed.get("reset_required",true) and selected.clouds.variant==variant,"billboard selection changes observation immediately "+variant)
		check(visible_carrier_id>0 and selected.clouds.get("visibleCarrierId",0)==visible_carrier_id and selected.clouds.get("visibleCarrierCount",0)==1,"billboard variant keeps the same single visible carrier "+variant)
		check(physical(selected)==authority,"billboard selection does not advance either simulation or counters "+variant)
		cloud_contract(selected,"selection "+variant)
	var camera_before:Array=demo.inspection_snapshot().camera_transform
	var hash_before:String=demo.inspection_snapshot().clouds.baselineHash
	demo.orbit_camera(.37,.11);demo.zoom_camera(-.14)
	var camera_changed:Dictionary=demo.inspection_snapshot()
	check(camera_changed.camera_transform!=camera_before and physical(camera_changed)==authority,"paused camera changes only observation")
	check(camera_changed.clouds.baselineHash!=hash_before,"camera motion actually reevaluates billboard output")
	cloud_contract(camera_changed,"paused changed camera")
	var replay_physics:=physical(camera_changed)
	var replay_hash:String=camera_changed.clouds.baselineHash
	var replay_time:float=camera_changed.clouds.sourceTime
	var observer:Dictionary=camera_changed.camera_controls.duplicate(true)
	var stable:=var_to_bytes(camera_changed)
	for invalid:Dictionary in [{"clouds":1},{"billboard_variant":"unknown"},{"clouds":true,"paused":1},{"unknown":true}]:
		check(not demo.configure(invalid).get("ok",true) and var_to_bytes(demo.inspection_snapshot())==stable,"invalid configuration preserves every live cloud and physical resource "+str(invalid))
	for invalid:Array in [["billboard_variant","unknown"],["clouds",1]]:
		check(not demo.set_parameter(invalid[0],invalid[1]).get("ok",true) and var_to_bytes(demo.inspection_snapshot())==stable,"invalid live cloud parameter is atomic "+str(invalid))
	check(demo.reset_experiment().get("ok",false),"same-options reset rebuilds paired cloud observation")
	var reset:Dictionary=demo.inspection_snapshot()
	check(reset.tick==0 and reset.time==0.0 and reset.camera_controls==observer,"reset restores origin while preserving current observer camera")
	cloud_contract(reset,"reset origin")
	demo.set_paused(false);demo.advance(STEP);demo.set_paused(true)
	var replay:Dictionary=demo.inspection_snapshot()
	check(physical(replay)==replay_physics and replay.clouds.baselineHash==replay_hash and replay.clouds.sourceTime==replay_time,"reset replays first accepted tick and complete cloud source at same camera")
	test_real_helper_work(demo)
	demo.dispose();demo.dispose()
	var disposed:Dictionary=demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and demo.get_child_count()==0,"idempotent dispose releases experiment scene")
	check(disposed.get("clouds",{}).get("resources",{}).get("renderers",-1)==0 and disposed.get("clouds",{}).get("resources",{}).get("parents",-1)==0,"idempotent dispose releases both cloud renderers and parents")
	view.free()
	test_default_workload(first)
	test_existing_host()
	finish()

func test_real_helper_work(demo:Node3D)->void:
	# Spy beneath the real helper/adapter seam; no production test-only API.
	var pair:RefCounted=demo.get("_cloud_pair")
	var old_baseline:RefCounted=pair.get("_baseline_impl")
	var old_candidate:RefCounted=pair.get("_candidate_impl")
	if old_baseline==null or old_candidate==null:
		check(false,"real helper allows owned compiler probes")
		return
	var frozen:RefCounted=BillboardContracts.BaselineProbe.new()
	var candidate:RefCounted=BillboardContracts.CandidateProbe.new()
	pair.set("_baseline_impl",frozen);pair.set("_candidate_impl",candidate)
	pair.select_variant("baseline")
	pair.apply_snapshot(demo.inspection_snapshot().candidate,demo.get("_camera"),demo.get("_ocean").get_reflection_camera())
	var observed:Dictionary=pair.inspection_snapshot()
	check(frozen.transpose_calls>candidate.transpose_calls and candidate.transpose_calls>0,"actual helper delegates billboard work baseline=%d candidate=%d"%[frozen.transpose_calls,candidate.transpose_calls])
	check(observed.get("exact",false) and observed.get("baselineHash","")!="" and observed.get("baselineHash","")==observed.get("candidateHash",""),"actual observed work reduction retains matching complete cloud state hashes")
	print("ARCHITECTURE_CLOUD_WORK_WITNESS baselineTransposeCalls=",frozen.transpose_calls," candidateTransposeCalls=",candidate.transpose_calls)
	pair.set("_baseline_impl",old_baseline);pair.set("_candidate_impl",old_candidate)
	pair.select_variant("candidate")
	pair.apply_snapshot(demo.inspection_snapshot().candidate,demo.get("_camera"),demo.get("_ocean").get_reflection_camera())

func test_default_workload(cloud_tick:Dictionary)->void:
	var demo:Node3D=Demo.new();var view:=viewport()
	check(demo.configure({"paused":true}).get("ok",false),"original default experiment still configures")
	view.add_child(demo)
	var initial:Dictionary=demo.inspection_snapshot()
	check(not initial.get("clouds",{}).get("enabled",true) and initial.get("clouds",{}).get("resources",{}).get("renderers",-1)==0,"default physics demo allocates no optional cloud renderer")
	demo.set_paused(false);demo.advance(STEP)
	check(physical(demo.inspection_snapshot())==physical(cloud_tick),"enabling clouds leaves complete first-tick physical snapshots and counts unchanged")
	demo.dispose();view.free()

func test_existing_host()->void:
	var lab:Control=load("res://game/research/laboratory.gd").new();root.add_child(lab);lab.set_process(false)
	check(lab.select_topic(TOPIC),"existing home laboratory selects same architecture topic")
	var started:Dictionary=lab.start_demo({"clouds":true,"billboard_variant":"baseline","paused":true})
	check(started.get("ok",false),"existing laboratory host accepts optional cloud factors")
	if started.get("ok",false):
		var initial:Dictionary=lab.inspection_snapshot().demo
		cloud_contract(initial,"laboratory host origin")
		check(initial.clouds.variant=="baseline" and lab.step_demo().get("ok",false),"shared host single-step accepts selected baseline cloud observation")
		var stepped:Dictionary=lab.inspection_snapshot().demo
		check(stepped.tick==1 and stepped.time==STEP and stepped.paused and stepped.baseline==stepped.candidate,"host step accepts exactly one original sixty-Hz tick then stays paused")
		cloud_contract(stepped,"laboratory host single step")
	lab.dispose();lab.free()

func finish()->void:
	print("LABORATORY_ARCHITECTURE_CLOUDS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
