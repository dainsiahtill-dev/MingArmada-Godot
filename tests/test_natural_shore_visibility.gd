extends SceneTree
## Frozen pre-culling source remains the numerical/material oracle. No GPU/timing assertions.
const Surf=preload("res://modules/scene_engine/terrain/natural_shore_surf.gd")
const Before=preload("res://tests/fixtures/natural_shore_before_visibility.gd")
const Field=preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Ocean=preload("res://modules/scene_engine/ocean/reference_game_water.gdshader")
const Natural=preload("res://modules/scene_engine/terrain/natural_world.gd")
const World=preload("res://modules/scene_engine/world/world_view.gd")
var assertions:=0
var failures:=0
var candidate:Node3D
var baseline:Node3D
var camera:Camera3D
var mirror:Camera3D
var surface:ShaderMaterial
var patches:=0

class StatefulSample extends RefCounted:
	var delegate:RefCounted
	var calls:=0
	var texture_matrix:=Basis.IDENTITY
	var alpha_phase:=0.0
	func sample(index:int,time:float)->Dictionary:
		calls+=1
		var state:Dictionary=delegate.sample(index,time)
		texture_matrix=delegate.texture_matrix;alpha_phase=delegate.alpha_phase
		return state

class StatefulInto extends StatefulSample:
	func sample_into(index:int,time:float,state:Dictionary)->void:
		state.merge(sample(index,time),true)

class StatefulCompiled extends "res://modules/scene_engine/fidelity_island/compiled_shore_sampler.gd":
	var calls:=0
	func sample_into(index:int,time:float,state:Dictionary)->void:
		calls+=1;super.sample_into(index,time,state)

class DeferredInitialSurf extends Surf:
	var suppress_initial:=true
	func apply_snapshot(snapshot:Dictionary,consumed:float=0.0)->void:
		if not suppress_initial:super.apply_snapshot(snapshot,consumed)

class MissingReflectionOcean extends MeshInstance3D:
	var target:SubViewport
	var reflected:Camera3D
	func get_reflection_viewport()->SubViewport:return target
	func get_reflection_camera()->Camera3D:return reflected

class CapturedNatural extends Node3D:
	var main:Camera3D
	var reflected:Camera3D
	var enabled:=false
	func set_view_cameras(view:Camera3D,reflection:Camera3D,reflection_enabled:bool)->void:
		main=view;reflected=reflection;enabled=reflection_enabled
	func sync_surface_state(_surface:ShaderMaterial,_state:Dictionary)->void:pass

func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL shore visibility: ",detail)
func views(main:Camera3D,reflected:Camera3D=null,enabled:bool=false)->void:
	if candidate.has_method("set_view_cameras"):candidate.set_view_cameras(main,reflected,enabled)
func work()->Dictionary:
	if candidate.has_method("presentation_diagnostics"):return candidate.presentation_diagnostics()
	return {"samples":-1,"materialWrites":-1,"visible":true,"bounds":AABB(),"acceptedTime":candidate.get("_time"),"evaluatedTime":candidate.get("_time"),"submittedTime":candidate.get("_time")}
func away(view:Camera3D)->void:
	view.position=Vector3(100000,40,100000);view.look_at(Vector3(100000,40,101000))
func near_island(view:Camera3D)->void:
	view.position=Vector3(0,80,180);view.look_at(Vector3.ZERO)
func step(time:float)->void:
	surface.set_shader_parameter("simulation_time",time)
	baseline.sync_surface_state(surface);baseline.apply_snapshot({"time":time})
	candidate.sync_surface_state(surface);candidate.apply_snapshot({"time":time})
func source_equal(label:String)->void:
	check(var_to_bytes(candidate.diagnostics())==var_to_bytes(baseline.diagnostics()),label+" complete original source dictionaries are byte exact")
func materials_equal(label:String)->void:
	var equal:=true
	for index in patches:
		var a:ShaderMaterial=baseline.get_child(index).material_override
		var b:ShaderMaterial=candidate.get_child(index).material_override
		for key:String in ["texture_matrix","controller_alpha","packet_u_metres","wave_components","wave_count","simulation_time","surface_tide","shore_bounds","has_shore_field","coastal_attenuation","coast_distance_texture","has_coast_distance","surface_visual_scale"]:
			equal=equal and a.get_shader_parameter(key)==b.get_shader_parameter(key)
	check(equal,label+" all submitted controller and shared surface values equal frozen source")

func run()->void:
	var field:=Field.new();check(field.configure({"resolution":33,"radius":60.0}),"accepted numeric field")
	candidate=Surf.new();baseline=Before.new();root.add_child(candidate);root.add_child(baseline)
	check(candidate.configure(field) and baseline.configure(field),"real geometry/source owners configure")
	patches=candidate.get_child_count();check(patches>16 and patches==baseline.get_child_count(),"original seeded patch population retained")
	check(candidate.has_method("set_view_cameras") and candidate.has_method("presentation_diagnostics"),"production exposes view input and detached countable-work diagnostics")
	var original_states:Array=candidate.get("_states").duplicate();var identities:Array=[];var geometry:Array=[]
	for node:MeshInstance3D in candidate.get_children():identities.append([node.mesh,node.material_override]);geometry.append(node.mesh.surface_get_arrays(0))
	var geometry_bytes:=var_to_bytes(geometry);var packet_bytes:=var_to_bytes(candidate.get("_packets"))
	camera=Camera3D.new();mirror=Camera3D.new();root.add_child(camera);root.add_child(mirror)
	camera.near=.1;camera.far=1000;mirror.near=.1;mirror.far=1000;near_island(camera);near_island(mirror)
	surface=ShaderMaterial.new();surface.shader=Ocean
	surface.set_shader_parameter("wave_components",PackedVector4Array([Vector4(1,.1,.2,.3),Vector4(-.5,.2,.1,.5)]))
	surface.set_shader_parameter("wave_count",2);surface.set_shader_parameter("u_tide",0.0)
	views(camera);step(.25);source_equal("visible baseline");materials_equal("visible baseline")
	away(camera);views(camera)
	for time:float in [0.0,.1,12.0,33.333335876464844,66.8,.25,99.1234567]:
		var before:=work();var previous:PackedByteArray=var_to_bytes(candidate.get("_states"))
		step(time);var after:=work()
		check(not after.visible and after.samples==before.samples and after.materialWrites==before.materialWrites,"proven offscreen frame skips source/matrix/material work at "+str(time))
		check(var_to_bytes(candidate.get("_states"))==previous,"hidden native output is deferred until requested")
		check(after.acceptedTime==time,"accepted clock remains current while presentation is deferred")
		var writes:int=after.materialWrites;source_equal("hidden diagnostics "+str(time));var sampled:int=work().samples
		check(work().materialWrites==writes,"current hidden diagnostic evaluates pure source without material upload")
		views(null);step(time);materials_equal("same-time diagnostic replay")
		check(work().samples==sampled,"same-time reentry replays staged values without resampling")
		views(camera)
	# Direct camera motion must recover without another view-registration call.
	step(100.0);near_island(camera);var prior:=work();step(100.0)
	check(work().visible and work().samples-prior.samples==patches,"same-time camera-only reentry immediately evaluates current native frame")
	source_equal("direct camera-only reentry");materials_equal("direct camera-only reentry")
	var paused:=work();step(100.0)
	check(work().samples==paused.samples and work().materialWrites==paused.materialWrites,"unchanged paused source/surface submits nothing")
	away(camera);views(camera,mirror,true);step(101.0)
	check(work().visible,"enabled reflection-only union keeps actual owner current")
	source_equal("mirror-only union");materials_equal("mirror-only union")
	views(camera,null,true);step(102.0)
	check(work().visible,"missing enabled reflection conservatively updates")
	source_equal("missing reflection");materials_equal("missing reflection")
	views(null);step(103.0);check(work().visible,"missing main camera conservatively updates")
	# Incoming bounds alone are insufficient while old uniforms still render.
	near_island(camera);views(camera);step(104.0)
	surface.set_shader_parameter("u_tide",10000.0);var tide_before:=work();step(104.0)
	check(work().materialWrites>tide_before.materialWrites,"old submitted visible tide forces synchronization before incoming displacement is skipped")
	materials_equal("same-clock tide leaves view")
	var tide_after:=work();step(105.0)
	check(not work().visible and work().samples==tide_after.samples and work().materialWrites==tide_after.materialWrites,"once old visible tide is replaced the new offscreen bound can skip")
	surface.set_shader_parameter("u_tide",0.0);step(105.0)
	check(work().visible,"same-clock incoming tide reenters immediately");source_equal("tide return");materials_equal("tide return")
	surface.set_shader_parameter("wave_components",PackedVector4Array([Vector4(4,.1,.2,.3),Vector4(-5,.2,.1,.5)]));step(105.0)
	var bound:AABB=work().bounds
	check(bound.position.y<=.055-9.0 and bound.end.y>=.055+9.0,"world bound includes current full positive/negative shader amplitudes")
	camera.position=Vector3(0,500,180);camera.look_at(Vector3(0,500,0))
	surface.set_shader_parameter("wave_components",PackedVector4Array([Vector4(600,.1,.2,.3)]));surface.set_shader_parameter("wave_count",1);step(105.0)
	var amplitude_before:=work();surface.set_shader_parameter("wave_components",PackedVector4Array([Vector4(0,.1,.2,.3)]));step(105.0)
	check(work().materialWrites>amplitude_before.materialWrites,"old visible amplitude bound forces same-clock shrinking displacement upload")
	materials_equal("same-clock wave amplitude shrinks out of view")
	near_island(camera);surface.set_shader_parameter("wave_components",PackedVector4Array([Vector4(4,.1,.2,.3),Vector4(-5,.2,.1,.5)]));surface.set_shader_parameter("wave_count",2);step(105.0)
	var state_before_invalid:Dictionary=candidate.diagnostics();var work_before_invalid:=work();candidate.apply_snapshot({"time":NAN})
	check(candidate.diagnostics()==state_before_invalid and work()==work_before_invalid,"invalid clock preserves source and presentation state")
	away(camera);views(camera);surface.set_shader_parameter("wave_count",9);var unknown_before:=work();step(106.0)
	check(work().visible and work().samples-unknown_before.samples==patches,"unknown displacement falls back to complete synchronous source work")
	surface.set_shader_parameter("wave_count",2);near_island(camera);step(107.0)
	# Owner movement invalidates the captured geometry; child topology is private/immutable.
	candidate.position=Vector3(100000,0,100000);var moved_before:=work();step(108.0)
	check(not work().visible and work().samples==moved_before.samples,"changed owner transform refreshes world bounds before culling")
	candidate.position=Vector3.ZERO;step(108.0);check(work().visible,"same-time restored owner transform recovers");source_equal("owner transform return");materials_equal("owner transform return")
	away(camera);views(camera)
	for in_place:bool in [false,true]:
		var injected:RefCounted=StatefulInto.new() if in_place else StatefulSample.new();injected.delegate=candidate.get("_sampler");candidate.set("_sampler",injected)
		var calls:int=injected.calls;step(110.0 if not in_place else 111.0)
		check(injected.calls-calls==patches,"unknown injected sampler retains all side-effect calls: "+str(in_place))
		source_equal("injected synchronous fallback");materials_equal("injected synchronous fallback")
		candidate.set("_sampler",injected.delegate)
	var prepared:RefCounted=candidate.get("_sampler");var subclass:=StatefulCompiled.new()
	check(subclass.configure(candidate.get("_source")),"stateful CompiledShoreSampler subclass configures same source")
	candidate.set("_sampler",subclass);step(112.0)
	check(subclass.calls==patches,"CompiledShoreSampler subclass retains all overridden side-effect calls")
	source_equal("compiled subclass synchronous fallback");materials_equal("compiled subclass synchronous fallback")
	candidate.set("_sampler",prepared)
	step(113.0);source_equal("hidden current count baseline")
	surface.set_shader_parameter("wave_count",1);step(113.0);var count_writes:int=work().materialWrites
	source_equal("same-clock hidden surface count diagnostics")
	check(work().materialWrites==count_writes,"same-clock hidden surface diagnostic does not upload materials")
	var touching:AABB=work().bounds
	camera.near=2.0;camera.position=Vector3(touching.get_center().x,touching.get_center().y,touching.position.z-2.0);camera.look_at(touching.get_center())
	step(113.0);check(work().visible,"near-plane touching conservative shore bounds remain visible")
	source_equal("near-plane boundary");materials_equal("near-plane boundary")
	camera.near=.1;near_island(camera)
	away(camera);views(camera);surface.set_shader_parameter("simulation_time",NAN)
	check(not candidate.sync_surface_state(surface) and not baseline.sync_surface_state(surface),"offscreen invalid surface clock preserves original sync rejection")
	candidate.apply_snapshot({"time":114.0});baseline.apply_snapshot({"time":114.0})
	check(work().visible,"unknown surface clock keeps complete native source fallback")
	source_equal("invalid surface clock fallback");materials_equal("invalid surface clock fallback")
	surface.set_shader_parameter("simulation_time",114.0)
	geometry.clear();var retained:=true
	for index in patches:
		var node:MeshInstance3D=candidate.get_child(index);geometry.append(node.mesh.surface_get_arrays(0))
		retained=retained and node.mesh==identities[index][0] and node.material_override==identities[index][1] and is_same(original_states[index],candidate.get("_states")[index])
	check(retained and var_to_bytes(geometry)==geometry_bytes and var_to_bytes(candidate.get("_packets"))==packet_bytes,"all original mesh/material/state owners, geometry arrays, packet RNG and ordering retained")
	candidate.dispose();check(candidate.get_child_count()==0,"dispose releases original geometry")
	check(candidate.configure(field),"same owner reconfigures after visibility cache lifetime")
	check(candidate.diagnostics().time==0.0 and work().acceptedTime==0.0 and work().submittedTime==0.0,"reconfigure resets accepted/evaluated/submitted epochs and stages")
	check(var_to_bytes(candidate.get("_packets"))==packet_bytes,"reconfigure keeps original RNG layout")
	near_island(camera)
	var relocated:=Field.new();check(relocated.configure({"resolution":33,"radius":60.0,"center":Vector2(100000,100000)}),"different configured geometry field")
	candidate.dispose();check(candidate.configure(relocated),"same shore Node accepts new immutable topology in a new lifetime")
	views(camera);candidate.sync_surface_state(surface);candidate.apply_snapshot({"time":.25})
	check(not work().visible and work().bounds.position.x>90000.0,"dispose/configure invalidates old geometry bounds and camera/staging lifetime")
	var deferred:=DeferredInitialSurf.new();root.add_child(deferred)
	check(deferred.configure(field),"first source application can be deferred by an existing caller override")
	var lazy:Dictionary=deferred.diagnostics();var lazy_work:Dictionary=deferred.presentation_diagnostics()
	check(lazy.time==0.0 and lazy.states.size()==patches and lazy_work.materialWrites==0 and not lazy_work.hasSubmittedTime,"diagnostics before first t0 application evaluates without material submission")
	deferred.suppress_initial=false;deferred.apply_snapshot({"time":0.0})
	var t0_ok:=true
	for index in patches:
		var material:ShaderMaterial=deferred.get_child(index).material_override
		t0_ok=t0_ok and material.get_shader_parameter("controller_alpha")==lazy.states[index].visibleAlpha and material.get_shader_parameter("texture_matrix") is Basis
	check(t0_ok and deferred.presentation_diagnostics().materialWrites==patches*3 and deferred.presentation_diagnostics().hasSubmittedTime,"first t0 application uploads all staged values despite numeric zero timestamps")
	deferred.dispose();deferred.free()
	var natural:=Natural.new();root.add_child(natural)
	check(natural.has_method("set_view_cameras"),"NaturalWorld owns scene-local shore camera composition")
	var world_source:=FileAccess.get_file_as_string("res://modules/scene_engine/world/world_view.gd")
	check(world_source.contains("_natural_world.set_view_cameras("),"actual WorldView routes current main/enabled reflection cameras to NaturalWorld")
	var world:=World.new();var missing:=MissingReflectionOcean.new();var captured:=CapturedNatural.new()
	root.add_child(world);world.add_child(missing);world.add_child(captured)
	world.set("_visual_style",1);world.set("_ocean",missing);world.set("_natural_world",captured);world.set("_camera",camera)
	world._sync_terrain_surface()
	check(captured.main==null and captured.enabled,"missing reflection target cannot certify main-only visibility")
	var disabled:=SubViewport.new();missing.add_child(disabled);disabled.render_target_update_mode=SubViewport.UPDATE_DISABLED;missing.target=disabled
	world._sync_terrain_surface()
	check(captured.main==camera and not captured.enabled,"only an actual disabled reflection viewport certifies the main-only path")
	disabled.render_target_update_mode=SubViewport.UPDATE_ALWAYS;world._sync_terrain_surface()
	check(captured.main==camera and captured.enabled and captured.reflected==null,"enabled target with missing camera retains unknown-reflection fallback input")
	world.set("_ocean",null);world.set("_natural_world",null);world.free()
	natural.free();candidate.dispose();baseline.dispose();candidate.free();baseline.free();camera.free();mirror.free()
	print("NATURAL_SHORE_VISIBILITY_TESTS assertions=",assertions," failures=",failures," patches=",patches)
	quit(1 if failures else 0)
