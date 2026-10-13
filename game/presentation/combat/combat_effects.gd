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
var _source_prewarm: Dictionary = {}
var _pending_snapshot: Dictionary = {}
var _snapshot_pending := false
func set_camera(camera: Camera3D) -> void:
	finish_snapshot()
	_camera = camera
	if _water_splashes: _water_splashes.configure_reference_backend(camera)
	for effect: Dictionary in _source_fire: effect.node.set_camera(camera)
func set_water_sampler(sampler: Callable) -> void:
	finish_snapshot()
	if _source_prewarm.is_empty():
		_source_prewarm = SourceEffect.prewarm_game_sources()
		if not bool(_source_prewarm.get("ok",false)):
			push_error("Source effects prewarm failed: "+str(_source_prewarm.get("errors",[])))
	if _water_splashes: _water_splashes.free()
	_water_splashes = Splashes.new(); _water_splashes.name = "WaterSplashes"
	add_child(_water_splashes); _water_splashes.configure(sampler)
	if is_instance_valid(_camera): _water_splashes.configure_reference_backend(_camera)
	if _surface_filter.is_valid(): _water_splashes.configure_surface_filter(_surface_filter)
func set_surface_filter(surface_filter: Callable) -> void:
	finish_snapshot()
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
	begin_snapshot(native,_consumed)
	finish_snapshot()

func has_pending_snapshot() -> bool: return _snapshot_pending

func begin_snapshot(native: Dictionary,_consumed: float = 0.0) -> void:
	finish_snapshot()
	var now := float(native.time)
	if not is_finite(now) or now < 0: return
	if now < _time: _clear_transients()
	_time = now
	# This dictionary is borrowed read-only until the matching finish. The Sea
	# completes the pair in this same frame before handling new events.
	_pending_snapshot = native
	_snapshot_pending = true
	if _water_splashes: _water_splashes.begin_snapshot(_time)
	for index in range(_source_fire.size()-1,-1,-1):
		var effect: Dictionary = _source_fire[index]
		var age := _time-float(effect.time)
		if age < 0.0 or age >= float(effect.duration):
			effect.node.dispose(); effect.node.free(); _source_fire.remove_at(index); continue
		effect.node.begin_snapshot(age,_time)

func finish_snapshot() -> void:
	if not _snapshot_pending: return
	_snapshot_pending = false
	var native := _pending_snapshot
	_pending_snapshot = {}
	if _water_splashes: _water_splashes.finish_snapshot()
	for effect: Dictionary in _source_fire: effect.node.finish_snapshot()
	var present: Array = []
	# Settled authority may retain shots that will never advance again. Retire
	# only their drawn carriers; native ballistics and the final hit events stay
	# intact while smoke, crew contacts and sinking effects finish separately.
	var live_projectiles: Array = [] if native.get("status","") in ["victory","defeat","surrendered"] else native.get("projectiles",[])
	for projectile: Dictionary in live_projectiles:
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
func _puff(position: Vector3,color: Color,size: float,duration: float,velocity: Vector3,growth: float,born: float = -1.0,texture_name: String = "",flash: bool = false) -> void:
	if _puffs.size() >= 160: return
	var stamp := _time if born < 0.0 else born
	if not is_finite(stamp) or stamp > _time or _time-stamp >= duration: return
	var mesh := MeshInstance3D.new()
	var material := StandardMaterial3D.new(); material.albedo_color = color; material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if not texture_name.is_empty():
		# Reuse the original DDS and authored mips already owned by the source
		# renderer. These destruction overlays are explicit game presentation.
		var texture: Texture2D = SourceEffect._texture(texture_name)
		if texture == null: return
		mesh.mesh = QuadMesh.new(); mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		material.albedo_texture = texture
		material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		material.billboard_keep_scale = true
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.texture_repeat = false
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		material.render_priority = 3
		if flash:
			material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
			material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			material.emission_enabled = true; material.emission = Color(1.0,0.42,0.08); material.emission_energy_multiplier = 1.8
	else:
		var fragment := BoxMesh.new(); fragment.size = Vector3(0.24,0.18,1.0)
		mesh.mesh = fragment
	mesh.material_override = material; mesh.position = position; mesh.scale = Vector3.ONE*size; add_child(mesh)
	var puff := {"node":mesh,"material":material,"origin":position,"velocity":velocity,"size":size,"growth":growth,"time":stamp,"duration":duration,"alpha":color.a}
	_puffs.append(puff)
	_update_puff(puff,_time-stamp)
func _update_puff(puff: Dictionary, age: float) -> void:
	puff.node.position = puff.origin+puff.velocity*age
	puff.node.scale = Vector3.ONE*(puff.size+age*puff.growth)
	puff.material.albedo_color.a = (1-age/puff.duration)*puff.alpha
func apply_events(events: Array) -> void:
	finish_snapshot()
	for event: Dictionary in events:
		if _seen.has(event.id): continue
		_seen[event.id] = true
		var born := float(event.get("time",_time))
		if not is_finite(born) or born < 0.0 or born > _time: continue
		var point := _vector(event.get("position",{}))
		match event.type:
			"fire":
				# Original hull proportions differ from temporary game ship stats.
				# Smoke uses the actual drawn gun; authority keeps its ballistic muzzle.
				point = _vector(event.get("source_muzzle_position", event.get("position", {})))
				var velocity := _vector(event.velocity).normalized()
				if _time-born < 3.333334:
					var source := SourceEffect.new(); source.name = "CannonSource_"+String(event.id)
					add_child(source)
					if source.configure("fx_cannon_fire_01.nif",{"origin":point,"direction":velocity,"seed":absi(String(event.id).hash()),"camera":_camera,"render_profile":"game_cannon","clock_mode":"native"}):
						_source_fire.append({"node":source,"time":born,"duration":source.get_playback_duration()}); source.apply_snapshot(_time-born,_time)
					else: source.free()
			"hit":
				for i in 6: _puff(point,Color(0.55,0.35,0.15,0.95),0.12,0.9,Vector3(sin(i*2.1)*3,1.5+i*0.3,cos(i*2.1)*3),0.1,born)
			"splash":
				if _water_splashes: _water_splashes.add_event(event)
			"mast-break":
				for i in 8: _puff(point,Color(0.50,0.33,0.17,0.70),0.10,1.2,Vector3(sin(i*2.1)*2.0,1.1+i*.12,cos(i*2.1)*2.0),0.12,born)
			"destruction-explosion":
				point = _vector(event.get("source_effect_position", event.get("position", {})))
				_puff(point,Color(1.0,0.65,0.22,0.85),3.0,0.18,Vector3.UP,4.0,born,"fx_cannon_smoke_03.dds",true)
				for i in 8: _puff(point,Color(0.43,0.42,0.38,0.72),2.8+i*.3,3.0,Vector3(sin(i)*.65,1.5,cos(i)*.65),1.25,born,"fx_cannon_smoke_0%d.dds"%[2+i%2])
			"sinking-froth":
				if _water_splashes:
					var froth := event.duplicate(true); froth.type = "splash"; froth.scale = 1.8; froth.surface_only = true
					_water_splashes.add_event(froth)
	while _seen.size() > 512: _seen.erase(_seen.keys()[0])
func diagnostics() -> Dictionary:
	finish_snapshot()
	var particles := 0
	var sources: Array = []
	for effect: Dictionary in _source_fire:
		var state: Dictionary = effect.node.diagnostics(); sources.append(state)
		particles += int(state.get("particles",state.get("active",0)))
	return {"projectiles":_balls.size(),"puffs":_puffs.size(),"events":_seen.size(),"splashes":_water_splashes.diagnostics().splashes if _water_splashes else 0,"source_fire":_source_fire.size(),"source_particles":particles,"source_effects":sources,"sourcePrewarm":_source_prewarm.duplicate(true),"water":_water_splashes.diagnostics() if _water_splashes else {}}

func _clear_transients() -> void:
	# Source disposal joins its exclusive CPU job and discards the old draw
	# payload. Do not render a frame whose providers may be being destroyed.
	_snapshot_pending = false
	_pending_snapshot = {}
	for ball: Node in _balls.values(): ball.free()
	for puff: Dictionary in _puffs: puff.node.free()
	for effect: Dictionary in _source_fire:
		effect.node.dispose(); effect.node.free()
	_source_fire.clear()
	_balls.clear(); _puffs.clear(); _seen.clear(); _velocities.clear()

func dispose() -> void:
	_clear_transients()
	if _water_splashes: _water_splashes.free(); _water_splashes = null
	_time = 0.0
	_surface_filter = Callable()
	_camera = null
	_source_prewarm.clear()

func _exit_tree() -> void: dispose()
