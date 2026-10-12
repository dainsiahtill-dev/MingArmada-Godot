extends Node3D
## Presentation only: source projectiles and deduplicated fire/hit/splash events.
const Splashes = preload("res://game/presentation/water/water_splashes.gd")
const SourceEffect = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
var _balls: Dictionary = {}
var _puffs: Array = []
var _seen: Dictionary = {}
var _velocities: Dictionary = {}
var _time := 0.0
var _ball_material: StandardMaterial3D
var _water_splashes: Node3D
var _surface_filter: Callable
var _camera: Camera3D
var _source_fire: Array = []
func set_camera(camera: Camera3D) -> void:
	_camera = camera
	if _water_splashes: _water_splashes.configure_reference_backend(camera)
	for effect: Dictionary in _source_fire: effect.node.set_camera(camera)
func set_water_sampler(sampler: Callable) -> void:
	if _water_splashes: _water_splashes.free()
	_water_splashes = Splashes.new(); _water_splashes.name = "WaterSplashes"
	add_child(_water_splashes); _water_splashes.configure(sampler)
	if is_instance_valid(_camera): _water_splashes.configure_reference_backend(_camera)
	if _surface_filter.is_valid(): _water_splashes.configure_surface_filter(_surface_filter)
func set_surface_filter(surface_filter: Callable) -> void:
	_surface_filter = surface_filter
	if _water_splashes: _water_splashes.configure_surface_filter(surface_filter)
func _ready() -> void:
	_ball_material = StandardMaterial3D.new(); _ball_material.albedo_color = Color("302e26")
static func _vector(value: Dictionary) -> Vector3: return Vector3(value.get("x",0),value.get("y",0),value.get("z",0))
func observe_projectiles(native: Dictionary) -> void:
	for projectile: Dictionary in native.get("projectiles",[]): _velocities[projectile.id] = {"velocity":projectile.velocity.duplicate(),"time":native.time}
func presentation_events(events: Array) -> Array:
	var result := events.duplicate(true)
	for event: Dictionary in result:
		if event.get("type") == "fire": _velocities[event.projectileId] = {"velocity":event.velocity.duplicate(),"time":event.time}
		if event.get("type") == "hit" and _velocities.has(event.get("projectileId")):
			var observed: Dictionary = _velocities[event.projectileId]; event.velocity = observed.velocity.duplicate()
			event.velocity.y -= 9.81*maxf(0,event.time-observed.time)
	return result
func apply_snapshot(native: Dictionary,_consumed: float) -> void:
	var now := float(native.time)
	if not is_finite(now) or now < 0: return
	if now < _time: _clear_transients()
	_time = now
	if _water_splashes: _water_splashes.apply_snapshot(_time)
	for index in range(_source_fire.size()-1,-1,-1):
		var effect: Dictionary = _source_fire[index]
		var age := _time-float(effect.time)
		if age < 0.0 or age >= 3.333334:
			effect.node.free(); _source_fire.remove_at(index); continue
		effect.node.apply_snapshot(age,_time)
	var present: Array = []
	for projectile: Dictionary in native.get("projectiles",[]):
		present.append(projectile.id)
		if not _balls.has(projectile.id):
			var ball := MeshInstance3D.new(); var shape := SphereMesh.new(); shape.radius = 0.18; shape.height = 0.36
			ball.mesh = shape; ball.material_override = _ball_material; add_child(ball); _balls[projectile.id] = ball
		_balls[projectile.id].position = _vector(projectile.position)
	for id in _balls.keys():
		if not id in present: _balls[id].queue_free(); _balls.erase(id)
	for index in range(_puffs.size()-1,-1,-1):
		var puff: Dictionary = _puffs[index]; var age: float = _time-puff.time
		if age >= puff.duration: puff.node.queue_free(); _puffs.remove_at(index); continue
		_update_puff(puff,age)
	for id in _velocities.keys():
		if _time-_velocities[id].time > 10: _velocities.erase(id)
func _puff(position: Vector3,color: Color,size: float,duration: float,velocity: Vector3,growth: float,born: float = -1.0) -> void:
	if _puffs.size() >= 160: return
	var stamp := _time if born < 0.0 else born
	if not is_finite(stamp) or stamp > _time or _time-stamp >= duration: return
	var mesh := MeshInstance3D.new(); var sphere := SphereMesh.new(); sphere.radius = 0.5; sphere.height = 1
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.mesh = sphere; mesh.material_override = material; mesh.position = position; mesh.scale = Vector3.ONE*size; add_child(mesh)
	var puff := {"node":mesh,"material":material,"origin":position,"velocity":velocity,"size":size,"growth":growth,"time":stamp,"duration":duration,"alpha":color.a}
	_puffs.append(puff)
	_update_puff(puff,_time-stamp)
func _update_puff(puff: Dictionary, age: float) -> void:
	puff.node.position = puff.origin+puff.velocity*age
	puff.node.scale = Vector3.ONE*(puff.size+age*puff.growth)
	puff.material.albedo_color.a = (1-age/puff.duration)*puff.alpha
func apply_events(events: Array) -> void:
	for event: Dictionary in events:
		if _seen.has(event.id): continue
		_seen[event.id] = true
		var born := float(event.get("time",_time))
		if not is_finite(born) or born < 0.0 or born > _time: continue
		var point := _vector(event.get("position",{}))
		match event.type:
			"fire":
				var velocity := _vector(event.velocity).normalized()
				if _time-born < 3.333334:
					var source := SourceEffect.new(); source.name = "CannonSource_"+String(event.id)
					add_child(source)
					if source.configure("fx_cannon_fire_01.nif",{"origin":point,"direction":velocity,"seed":absi(String(event.id).hash()),"camera":_camera}):
						_source_fire.append({"node":source,"time":born}); source.apply_snapshot(_time-born,_time)
					else: source.free()
			"hit":
				for i in 6: _puff(point,Color(0.55,0.35,0.15,0.95),0.12,0.9,Vector3(sin(i*2.1)*3,1.5+i*0.3,cos(i*2.1)*3),0.1,born)
			"splash":
				if _water_splashes: _water_splashes.add_event(event)
			"mast-break":
				for i in 8: _puff(point,Color(0.50,0.33,0.17,0.70),0.10,1.2,Vector3(sin(i*2.1)*2.0,1.1+i*.12,cos(i*2.1)*2.0),0.12,born)
			"destruction-explosion":
				_puff(point,Color(1.0,0.65,0.22,0.85),2.2,0.18,Vector3.UP,4.0,born)
				for i in 8: _puff(point,Color(0.43,0.42,0.38,0.38),1.2+i*.15,3.0,Vector3(sin(i)*.5,1.0,cos(i)*.5),0.65,born)
			"sinking-froth":
				if _water_splashes:
					var froth := event.duplicate(true); froth.type = "splash"; froth.scale = 1.8; froth.surface_only = true
					_water_splashes.add_event(froth)
	while _seen.size() > 512: _seen.erase(_seen.keys()[0])
func diagnostics() -> Dictionary:
	var particles := 0
	var sources: Array = []
	for effect: Dictionary in _source_fire:
		var state: Dictionary = effect.node.diagnostics(); sources.append(state)
		particles += int(state.get("particles",state.get("active",0)))
	return {"projectiles":_balls.size(),"puffs":_puffs.size(),"events":_seen.size(),"splashes":_water_splashes.diagnostics().splashes if _water_splashes else 0,"source_fire":_source_fire.size(),"source_particles":particles,"source_effects":sources,"water":_water_splashes.diagnostics() if _water_splashes else {}}

func _clear_transients() -> void:
	for ball: Node in _balls.values(): ball.free()
	for puff: Dictionary in _puffs: puff.node.free()
	for effect: Dictionary in _source_fire: effect.node.free()
	_source_fire.clear()
	_balls.clear(); _puffs.clear(); _seen.clear(); _velocities.clear()

func dispose() -> void:
	_clear_transients()
	if _water_splashes: _water_splashes.free(); _water_splashes = null
	_time = 0.0
	_surface_filter = Callable()
	_camera = null

func _exit_tree() -> void: dispose()
