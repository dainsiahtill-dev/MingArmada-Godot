extends "res://tools/profile-hull-dynamics-world.gd"
## Prepared research driver, not a production option. Do not run during fullsuite/GPU capture.
const Prototype=preload("res://tools/research-shore-culling-prototype.gd")
var baseline:Array=[]
var candidates:Array=[]
var probes:Array[Camera3D]=[]
var records:Array=[]
var surface:ShaderMaterial
var ocean:Node3D
var surface_overrides:Dictionary={}
var research_assertions:=0
var comparisons:Array=[]

func check(ok:bool,message:String)->bool:
	research_assertions+=1
	return super.check(ok,message)

func _source_equal(left:Dictionary,right:Dictionary)->bool:
	left=left.duplicate(true);right=right.duplicate(true)
	left.erase("research");right.erase("research")
	return var_to_bytes(left)==var_to_bytes(right)

func _fingerprint(value:Variant)->String:return var_to_bytes(value).hex_encode().sha256_text()

func _set_camera(view:Camera3D,eye:Vector3,target:Vector3)->void:
	view.global_position=eye;view.look_at(target,Vector3.UP)

func _views(main:Camera3D,mirror:Camera3D=null,enabled:bool=false,complete:bool=true)->void:
	for shore:Node3D in candidates:shore.research_set_views(main,mirror,enabled,complete)

func _step(time:float,label:String)->void:
	ocean.set_simulation_time(time);ocean.update_projection()
	for key:String in surface_overrides:surface.set_shader_parameter(key,surface_overrides[key])
	var before:Array=[]
	for shore:Node3D in candidates:before.append({"samples":shore.research_samples,"writes":shore.research_writes})
	for shore:Node3D in baseline:shore.sync_surface_state(surface);shore.apply_snapshot({"time":time})
	for shore:Node3D in candidates:shore.sync_surface_state(surface);shore.apply_snapshot({"time":time})
	var work:Array=[]
	for index in candidates.size():
		var shore:Node3D=candidates[index]
		work.append({"owner":index,"visible":shore.research_visible,"reason":shore.research_reason,"samples":shore.research_samples-int(before[index].samples),"writes":shore.research_writes-int(before[index].writes),"accepted":shore.research_accepted_time,"evaluated":shore.get("_time"),"submitted":shore.research_submitted_time,"viewHits":shore.research_view_hits.duplicate()})
	records.append({"case":label,"time":time,"work":work})

func _compare(label:String,materials:bool=true)->void:
	for index in candidates.size():
		var expected:Dictionary=baseline[index].diagnostics();var actual:Dictionary=candidates[index].diagnostics()
		check(_source_equal(actual,expected),label+" complete source/packet/state dictionary bytes owner "+str(index))
		var plain:=actual.duplicate(true);plain.erase("research")
		comparisons.append({"case":label,"owner":index,"source":_fingerprint(expected),"candidate":_fingerprint(plain),"time":expected.time,"patches":expected.patchCount,"materialsCompared":materials})
		if materials:
			var left:Array=baseline[index].get("_materials");var right:Array=candidates[index].get("_materials")
			for patch in left.size():
				for key:String in ["texture_matrix","controller_alpha","packet_u_metres","wave_components","wave_count","simulation_time","surface_tide","shore_bounds","has_shore_field","coastal_attenuation","coast_distance_texture","has_coast_distance","surface_visual_scale"]:
					check(left[patch].get_shader_parameter(key)==right[patch].get_shader_parameter(key),label+" actual material value "+str([index,patch,key]))

func run()->void:
	output=""
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name()=="headless","research proof is headless only; no concurrent GPU measurement"):quit(1);return
	if not check(not output.is_empty() and not FileAccess.file_exists(output),"fresh explicit output path"):quit(1);return
	var script:=Prototype.make_script()
	if not check(script.reload()==OK,"source-derived culling prototype compiles"):quit(1);return
	main=Main.new();main.router=Router.new({"mingqi_storage":MemorySlot.new(),"legacy_storage":MemorySlot.new(),"settings_storage":Settings.new("user://verification/shore-culling-no-write-%d.json"%OS.get_process_id())});root.add_child(main)
	for frame in 5:await process_frame
	main.menu.find_child("sail",true,false).pressed.emit()
	for frame in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and main.current_scene.get("startup_receipt").get("ok",false):break
	if not check(is_instance_valid(main.current_scene),"actual public sail scene ready"):quit(1);return
	game=main.current_scene;freeze_callbacks(main);game._present(0.0)
	var natural:Node3D=game.sea.world.get("_natural_world")
	if not check(is_instance_valid(natural),"actual NaturalWorld exists"):main.free();quit(1);return
	baseline=natural.get("_dynamic_shore").duplicate();ocean=game.sea.world.get_ocean();surface=ocean.get("material_override")
	check(baseline.size()==6,"actual six island owners, no population reduction")
	var patches:=0;var geometry:Array=[]
	for original:Node3D in baseline:
		var candidate:Node3D=script.new();natural.add_child(candidate)
		check(candidate.configure(original.get("_field"),{"wave_span":original.get("_wave_span")}),"same terrain configures derived island")
		candidate.research_enable(surface);candidates.append(candidate)
		check(_fingerprint(candidate.get("_packets"))==_fingerprint(original.get("_packets")),"actual packet order/RNG/placement unchanged")
		var old_meshes:Array=[];var new_meshes:Array=[]
		for node:Node in original.get_children():
			if node is MeshInstance3D:old_meshes.append(node.mesh.surface_get_arrays(0))
		for node:Node in candidate.get_children():
			if node is MeshInstance3D:new_meshes.append(node.mesh.surface_get_arrays(0))
		check(var_to_bytes(old_meshes)==var_to_bytes(new_meshes),"actual full mesh topology/vertex/UV arrays unchanged")
		geometry.append(_fingerprint(old_meshes));patches+=original.get("_materials").size()
	check(patches==1704,"actual 1704 shoreline patches retained")
	for index in 2:
		var view:=Camera3D.new();view.near=0.1;view.far=1000000.0;natural.add_child(view);probes.append(view)
	_views(null);_step(.25,"no-camera-fallback");_compare("no-camera")
	for shore:Node3D in candidates:check(shore.research_visible and shore.research_reason=="missing-main-camera","no camera conservatively updates all patches")
	# Observe current actual production main+reflection input, independently of
	# synthetic camera fixtures. This records work only, never CPU/GPU timing.
	ocean.set_simulation_time(.5);ocean.update_projection()
	var reflection:Camera3D=ocean.get_reflection_camera();var viewport:SubViewport=ocean.get_reflection_viewport()
	var reflection_enabled:=is_instance_valid(viewport) and viewport.render_target_update_mode!=SubViewport.UPDATE_DISABLED
	_views(game.sea.camera,reflection,reflection_enabled);_step(.5,"actual-production-main-reflection");_compare("actual production views",false)
	var first:Node3D=candidates[0];first.research_test_bounds();var bounds:AABB=first.research_bound;var center:=bounds.get_center();var extent:=maxf(bounds.size.length(),100.0)
	# Explicit supplied Camera3D union fixture. The second camera is deliberately
	# independent to prove mirror-only visibility; actual mirror sync remains game-owned.
	_set_camera(probes[0],center+Vector3(0,extent,extent*2),center+Vector3(0,extent*2,extent*4))
	_set_camera(probes[1],center+Vector3(0,extent,extent*2),center)
	_views(probes[0]);_step(.4,"main-away");check(not first.research_visible,"first owner completely outside main frustum")
	_views(probes[0],probes[1],true);_step(.4,"mirror-only-same-time-reenter")
	check(first.research_view_hits==[false,true] and first.research_visible,"reflection-only union restores same accepted time")
	_compare("mirror-only",false)
	# Whole scene outside a narrow camera far from every actual island.
	probes[0].far=10000.0;_set_camera(probes[0],Vector3(10000000,100,10000000),Vector3(10000000,100,10001000))
	for time:float in [0.0,.1,12.0,33.333335876464844,66.8,.25,99.1234567]:
		_views(probes[0]);var before:=0
		for shore:Node3D in candidates:before+=shore.research_samples
		_step(time,"offscreen-arbitrary-time")
		var after:=0
		for shore:Node3D in candidates:after+=shore.research_samples;check(not shore.research_visible,"all actual islands proven outside complete view")
		check(after==before,"hidden absolute-time trajectories do not evaluate samples or matrix")
		# Missing camera is an explicit conservative full-visible recovery adapter.
		_views(null);_step(time,"paused-same-time-recovery");_compare("arbitrary-reentry "+str(time))
	_views(probes[0]);_step(123.456789,"hidden-diagnostics-current")
	var writes:=0
	for shore:Node3D in candidates:writes+=shore.research_writes
	_compare("hidden diagnostic current",false)
	var writes_after:=0;var samples_after:=0
	for shore:Node3D in candidates:writes_after+=shore.research_writes;samples_after+=shore.research_samples
	check(writes_after==writes,"diagnostic numeric refresh never writes hidden materials")
	_views(null);_step(123.456789,"diagnostic-same-time-material-recovery");_compare("diagnostic cached value recovery")
	var samples_recovered:=0
	for shore:Node3D in candidates:samples_recovered+=shore.research_samples
	check(samples_recovered==samples_after,"diagnostic staging restores actual matrices without resampling same time")
	# Exact near-plane touching fixture against conservative displaced geometry.
	probes[0].near=2.0;probes[0].far=maxf(10000.0,extent*4.0)
	_set_camera(probes[0],Vector3(center.x,center.y,bounds.position.z-2.0),center)
	_views(probes[0]);_step(123.456789,"near-plane-touch")
	check(first.research_visible,"near-plane touching bounds conservatively remain visible")
	_views(probes[0],null,true);_step(123.456789,"missing-reflection-fallback")
	for shore:Node3D in candidates:check(shore.research_visible,"enabled but missing reflection keeps unknown union visible")
	_compare("missing reflection fallback")
	# Use the actual surface material as source: bound follows current amplitudes
	# and tide, never only the flat mesh AABB or a hard-coded 3.5 m default.
	surface_overrides={"wave_components":PackedVector4Array([Vector4(4.0,.1,.2,.3),Vector4(-5.0,.2,.1,.5)]),"wave_count":2,"u_tide":3.0}
	_views(null);_step(123.456789,"same-clock-displacement-and-tide-edit")
	check(first.research_bound.position.y<=3.0+0.055-9.0 and first.research_bound.end.y>=3.0+0.055+9.0,"conservative bound follows full actual shader amplitude sum and tide")
	_compare("same-clock changed surface")
	var proof:Dictionary={"status":"research-only prototype; no production option installed","scope":"Actual public sail terrain/packets/mesh arrays plus source-derived apply/sync wrappers; headless functional/counter proof only, no GPU/framerate claim. Independent Camera3D mirror-only fixture tests supplied-frustum union; does not claim actual mirrored capture equivalence.","engine":Engine.get_version_info(),"productionSourceSHA256":FileAccess.get_file_as_string(Prototype.SOURCE).sha256_text(),"prototypeFactorySHA256":FileAccess.get_file_as_string("res://tools/research-shore-culling-prototype.gd").sha256_text(),"driverSHA256":FileAccess.get_file_as_string("res://tools/research-shore-frustum-culling.gd").sha256_text(),"instrumentedSHA256":script.source_code.sha256_text(),"patches":patches,"assertions":research_assertions,"meshHashes":geometry,"comparisons":comparisons,"rows":records,"failures":failures}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()));var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(proof,"\t"));file.close()
	for shore:Node3D in candidates:shore.dispose();shore.free()
	for view:Camera3D in probes:view.free()
	main.free();print("SHORE_FRUSTUM_RESEARCH_TESTS ",JSON.stringify({"assertions":research_assertions,"failures":failures,"patches":patches,"output":output}));quit(0 if failures.is_empty() else 1)
