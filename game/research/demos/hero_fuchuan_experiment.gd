extends Node3D
## Controlled rig and geometry comparison. Host owns time; no gameplay/save writes.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Hero=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
const DEFAULTS={"model":"vintage","paused":false,"animated":true,"camera_mode":"follow"}
const STEP:=1.0/32.0
var _options:=DEFAULTS.duplicate(true)
var _world:Node3D
var _ship:Node3D
var _camera:Camera3D
var _time:=0.0
var _remainder:=0.0
var _yaw:=.8
var _pitch:=.32
var _radius:=50.0
var _configured:=false
var _disposed:=true
var _snapshot:Dictionary={}
func _ready()->void:
	set_process(false);set_physics_process(false)
	if _configured and not _disposed:_build()
func get_default_options()->Dictionary:return DEFAULTS.duplicate(true)
func configure(options:Dictionary)->Dictionary:
	var next:=DEFAULTS.duplicate(true);next.merge(options,true)
	if next.model not in ["hero","vintage","baseline"] or not next.paused is bool or not next.animated is bool:return {"ok":false,"reason":"invalid-model-options"}
	dispose();_options=next;_configured=true;_disposed=false;_time=0;_remainder=0
	if is_inside_tree():_build()
	return {"ok":true,"ready":is_instance_valid(_ship),"pending":not is_inside_tree()}
func reset_experiment(options:Dictionary={})->Dictionary:
	var next:=_options.duplicate(true);next.merge(options,true)
	return configure(next)
func control_spec()->Array:
	return [{"id":"model","label":"船模对照（重置）","type":"choice","value":_options.model,"choices":[{"value":"vintage","label":"复古生图材质"},{"value":"hero","label":"Blender 初版材质"},{"value":"baseline","label":"原有参考船"}]},{"id":"animated","label":"固定收帆／转舵序列","type":"toggle","value":_options.animated}]
func set_parameter(id:String,value:Variant)->Dictionary:
	if id=="model" and value in ["hero","vintage","baseline"]:return {"ok":true,"id":id,"value":value,"reset_required":value!=_options.model}
	if id=="animated" and value is bool:
		_options.animated=value;_present();return {"ok":true,"id":id,"value":value,"reset_required":false}
	return {"ok":false,"reason":"invalid-parameter"}
func _build()->void:
	_world=Node3D.new();add_child(_world)
	_ship=Ship.new();_world.add_child(_ship)
	_ship.configure("fuchuan",null,Reference.new() if _options.model=="baseline" else Hero.new("vintage" if _options.model=="vintage" else "original"))
	_camera=Camera3D.new();_world.add_child(_camera);_camera.current=true;_camera.fov=48;_camera.near=.1;_camera.far=500
	var light:=DirectionalLight3D.new();light.rotation_degrees=Vector3(-40,-30,0);light.light_energy=1.7;light.shadow_enabled=true;_world.add_child(light)
	var environment:=WorldEnvironment.new();environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR;environment.environment.background_color=Color("9aafb4")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR;environment.environment.ambient_light_color=Color("e9e0cd");environment.environment.ambient_light_energy=.65;_world.add_child(environment)
	var plane:=MeshInstance3D.new();var surface:=PlaneMesh.new();surface.size=Vector2(300,300);plane.mesh=surface;plane.position.y=-2.25
	var material:=StandardMaterial3D.new();material.albedo_color=Color("334a51");material.roughness=.8;plane.material_override=material;_world.add_child(plane)
	_present();_update_camera()
func _present()->void:
	if not is_instance_valid(_ship):return
	var phase:=sin(_time*.8) if _options.animated else 1.0
	_snapshot={"id":"hero","time":_time,"kind":"fuchuan","sailAngle":phase*.42,"sailDeployment":.62+phase*.38,"rudder":phase,"hull":100,"sail":100,"crew":100,"visual":{"position":{"x":0,"y":0,"z":0},"heading":PI/2,"pitch":0,"heel":0,"velocity":{"x":0,"z":0}}}
	_ship.apply_snapshot(_snapshot,{"direction":{"x":1,"y":0},"speed":14},0)
func advance(seconds:float)->void:
	if _disposed or _options.paused or not is_finite(seconds) or seconds<=0:return
	_remainder+=seconds
	while _remainder+1e-9>=STEP:_time+=STEP;_remainder-=STEP
	_present()
func set_paused(value:bool)->void:_options.paused=value
func set_camera_mode(value:String)->void:
	_options.camera_mode=value;_pitch=.85 if value=="high" else .32;_update_camera()
func orbit_camera(yaw_delta:float,pitch_delta:float)->void:
	_yaw+=yaw_delta;_pitch=clampf(_pitch+pitch_delta,-.05,1.35);_update_camera()
func zoom_camera(amount:float)->void:
	_radius=clampf(_radius*exp(-amount),18,95);_update_camera()
func _update_camera()->void:
	if not is_instance_valid(_camera):return
	var target:=Vector3(0,8,0)
	_camera.position=target+Vector3(sin(_yaw)*cos(_pitch),sin(_pitch),cos(_yaw)*cos(_pitch))*_radius
	_camera.look_at(target)
func inspection_snapshot()->Dictionary:
	return {"ready":is_instance_valid(_ship),"disposed":_disposed,"paused":_options.paused,"time":_time,"tick":roundi(_time/STEP),"seed":1650,"fixed_step":STEP,"parameters":_options.duplicate(true),"snapshot":_snapshot.duplicate(true),"resources":{"ship":1 if is_instance_valid(_ship) else 0},"scope":"Fixed authoritative-shaped snapshot sequence; geometry/rig experiment, not gameplay or full-game FPS proof."}
func dispose()->void:
	if is_instance_valid(_ship):_ship.dispose()
	_ship=null;_camera=null
	if is_instance_valid(_world):_world.free()
	_world=null;_disposed=true
func _exit_tree()->void:dispose()
