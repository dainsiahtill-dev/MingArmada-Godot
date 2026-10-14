extends Node3D
## Isolated production caster/Math/renderer comparison. Host is the only clock.
const Adapter=preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const Prepared=preload("res://game/presentation/world/prepared_rigid_shadow.gd")
const Math=preload("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
const Renderer=preload("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd")
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const DEFAULTS={"kind":"fuchuan","prepared_enabled":true,"camera_mode":"side","paused":false}
var _options:Dictionary=DEFAULTS.duplicate(true)
var _world:Node3D
var _ship:Node3D
var _camera:Camera3D
var _adapter:RefCounted
var _renderer:RefCounted
var _prepared:Dictionary={}
var _configured:=false
var _disposed:=false
var _ready_experiment:=false
var _tick:=0
var _accumulator:=0.0
var _yaw:=0.55
var _pitch:=0.5
var _radius:=75.0
var _mismatches:=0
var _samples:Array=[]
func _ready()->void:
	set_process(false);set_physics_process(false)
	if _configured and not _disposed:_build()
func get_default_options()->Dictionary:return DEFAULTS.duplicate(true)
func configure(options:Dictionary)->Dictionary:
	var candidate:=DEFAULTS.duplicate(true);candidate.merge(options,true)
	if candidate.kind not in ["fuchuan","merchant","fisherman"] or not candidate.prepared_enabled is bool or not candidate.paused is bool or candidate.camera_mode not in ["side","high"]:return {"ok":false,"reason":"unsupported-shadow-option"}
	if not _configured or candidate.camera_mode!=_options.camera_mode:_pitch=.9 if candidate.camera_mode=="high" else .5
	dispose();_options=candidate;_configured=true;_disposed=false;_tick=0;_accumulator=0;_mismatches=0;_samples=[]
	if is_inside_tree():_build()
	return {"ok":true,"ready":_ready_experiment,"pending":not is_inside_tree()}
func reset_experiment(options:Dictionary={})->Dictionary:
	var candidate:=_options.duplicate(true);candidate.merge(options,true);return configure(candidate)
func control_spec()->Array:
	return [{"id":"kind","label":"真实船型（重置）","type":"choice","value":_options.kind,"choices":[{"value":"fuchuan","label":"福船"},{"value":"merchant","label":"商船"},{"value":"fisherman","label":"渔舟"}]},{"id":"prepared_enabled","label":"不可变准备快路","type":"toggle","value":_options.prepared_enabled},{"id":"camera_mode","label":"镜头","type":"choice","value":_options.camera_mode,"choices":[{"value":"side","label":"船侧"},{"value":"high","label":"俯视"}]}]
func set_parameter(id:String,value:Variant)->Dictionary:
	if id=="kind" and value in ["fuchuan","merchant","fisherman"]:return {"ok":true,"id":id,"value":value,"reset_required":value!=_options.kind}
	if id=="prepared_enabled" and value is bool:_options[id]=value;_update(false);return {"ok":true,"id":id,"value":value,"reset_required":false}
	if id=="camera_mode" and value in ["side","high"]:set_camera_mode(value);return {"ok":true,"id":id,"value":value,"reset_required":false}
	return {"ok":false,"reason":"unsupported-shadow-option"}
func _build()->void:
	_world=Node3D.new();_world.name="ExperimentWorld";add_child(_world)
	_ship=Ship.new();_world.add_child(_ship)
	if not _ship.configure(_options.kind):return
	_camera=Camera3D.new();_camera.current=true;_camera.near=.5;_camera.far=2000;_camera.fov=55;_world.add_child(_camera)
	var plane:=MeshInstance3D.new();var mesh:=PlaneMesh.new();mesh.size=Vector2(500,500);plane.mesh=mesh;plane.position.y=-.5;_world.add_child(plane)
	var material:=StandardMaterial3D.new();material.albedo_color=Color("6d8c8d");plane.material_override=material
	var environment:=WorldEnvironment.new();environment.environment=Environment.new();environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("94acb1");environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color.WHITE;environment.environment.ambient_light_energy=.7;_world.add_child(environment)
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-55,25,0);_world.add_child(light)
	_adapter=Adapter.new();_renderer=Renderer.new();_renderer.configure(_world,_camera);_ready_experiment=true
	_update_camera();_update(false)
func advance(delta:float)->void:
	if not _ready_experiment or _disposed or _options.paused or not is_finite(delta) or delta<=0:return
	_accumulator+=minf(delta,.1)
	while _accumulator+1e-12>=1.0/60:
		_tick+=1;_update(true);_accumulator-=1.0/60
func _update(measure:bool)->void:
	if not _ready_experiment:return
	var time:=_tick/60.0
	_ship.apply_snapshot({"time":time,"position":{"x":0.0,"y":0.0,"z":0.0},"heading":.45+sin(time*.4)*.06,"pitch":sin(time*.7)*.015,"heel":cos(time*.5)*.02,"sailDeployment":1.0,"sailAngle":.8,"hull":100.0},{},0.0)
	var packet:Dictionary=_adapter.compose({}, {"ship":_ship},Vector3(.35+sin(time)*.001,-.8,.5).normalized(),DisplayServer.get_name()!="headless")
	var oracle_usec:=0;var prepared_usec:=0
	for caster:Dictionary in packet.native.sourceShadows.casters:
		var mesh:MeshInstance3D=packet.actors[caster.actorId]
		if not _prepared.has(caster.id):
			var source:Dictionary=_adapter._mesh_geometry(mesh.mesh)
			var component:=Prepared.new();component.configure(source.positions,source.faces);_prepared[caster.id]=component
		var start:=Time.get_ticks_usec()
		var original:Dictionary=Math.build_volume_component(caster.positions,caster.localLight,caster.edges,caster.capIndices)
		oracle_usec+=Time.get_ticks_usec()-start;start=Time.get_ticks_usec()
		var optimized:Dictionary=_prepared[caster.id].build_volume(caster.localLight)
		prepared_usec+=Time.get_ticks_usec()-start
		if original!=optimized:_mismatches+=1
		if _options.prepared_enabled:
			var topology:Dictionary=_prepared[caster.id].select_topology(caster.localLight)
			caster.positions=_prepared[caster.id].source_positions();caster.edges=topology.edges;caster.capIndices=topology.caps;caster.preparedRigid=_prepared[caster.id]
		else:caster.erase("preparedRigid")
	_renderer.apply_snapshot(packet.native,packet.actors)
	if measure and _samples.size()<600:_samples.append({"tick":_tick,"oracleUs":oracle_usec,"preparedUs":prepared_usec,"casters":packet.native.sourceShadows.casters.size()})
func set_paused(value:bool)->void:_options.paused=value
func set_camera_mode(value:String)->void:
	if value not in ["side","high"]:return
	_options.camera_mode=value;_pitch=.9 if value=="high" else .5;_update_camera()
func orbit_camera(yaw_delta:float,pitch_delta:float)->void:
	if not is_finite(yaw_delta) or not is_finite(pitch_delta):return
	_yaw+=yaw_delta;_pitch=clampf(_pitch+pitch_delta,.15,1.3);_update_camera()
func zoom_camera(amount:float)->void:
	if not is_finite(amount):return
	_radius=clampf(_radius*exp(clampf(amount,-1,1)),36,220);_update_camera()
func _update_camera()->void:
	if not is_instance_valid(_camera):return
	_camera.position=Vector3(cos(_yaw)*cos(_pitch),sin(_pitch),sin(_yaw)*cos(_pitch))*_radius+Vector3(0,3,0);_camera.look_at(Vector3(0,3,0))
func inspection_snapshot()->Dictionary:
	var topology_builds:=0;var classifications:=0
	for component:RefCounted in _prepared.values():topology_builds+=component.diagnostics().topologyBuilds;classifications+=component.diagnostics().classifications
	return {"ready":_ready_experiment,"disposed":_disposed,"parameters":_options.duplicate(true),"paused":_options.paused,"tick":_tick,"time":_tick/60.0,"fixed_step":1.0/60.0,"seed":9713,"telemetry":{"mismatches":_mismatches,"casters":_prepared.size(),"topology_builds":topology_builds,"classifications":classifications},"samples":_samples.duplicate(true),"renderer":_renderer.diagnostics() if _renderer else {},"scope":"Independent production rigid Ship/Adapter/Math/Renderer; diagnostic flat receiver. CPU paired volume timings include exact classifier in prepared path. No ocean, crew, motion authority or full-game FPS claim.","camera_position":_camera.position if is_instance_valid(_camera) else Vector3.ZERO,"resources":{"world":1 if is_instance_valid(_world) else 0,"renderer":1 if _renderer else 0}}
func dispose()->void:
	_ready_experiment=false;_disposed=true
	if _renderer:_renderer.dispose()
	if _adapter:_adapter.dispose()
	if is_instance_valid(_ship):_ship.dispose()
	_renderer=null;_adapter=null;_prepared.clear();_ship=null;_camera=null
	if is_instance_valid(_world):_world.free()
	_world=null
func _exit_tree()->void:dispose()
