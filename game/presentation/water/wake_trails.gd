extends Node3D
## Curved surface ribbons from observed stern positions. No separate clock or physics.
const Foam = preload("res://game/presentation/water/pirates_foam.gdshader")
const ShipWave = preload("res://game/presentation/water/ship_wave_geometry.gd")
const Volume = preload("res://game/presentation/water/splash_volume.gd")
const WAKE_DDS := "res://assets/textures/pirates_reference/wake3.dds.png"
const WAKE_TGA := "res://assets/textures/pirates_reference/wake3.tga.png"
const FROTH := "res://assets/textures/pirates_reference/fx_waterfroth_003.dds.png"
const WAKE_UNIQUE := "res://assets/textures/pirates_reference/wake3unique.dds.png"
const MAX_TRAILS := 32
const MAX_SAMPLES := 64
const LIFETIME := 6.5
const SURFACE_OFFSET := 0.10
const CROSS_SECTIONS := [-1.0, -0.55, 0.0, 0.55, 1.0]
var _water: Callable
var _time := -1.0
var _poses: Dictionary = {}
var _trails: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _wave_material: ShaderMaterial
var _surface_filter: Callable

func configure_surface_filter(sea_at: Callable) -> void: _surface_filter = sea_at

func configure(water_sampler: Callable) -> void:
	dispose(); _water = water_sampler
	for path: String in [WAKE_UNIQUE]:
		var material := ShaderMaterial.new(); material.shader = Foam
		material.render_priority = 3 # Above transparent ocean (1) and shore foam (2).
		material.set_shader_parameter("foam_texture", load(path))
		material.set_shader_parameter("detail_texture", load(FROTH))
		material.set_shader_parameter("ribbon", true)
		material.set_shader_parameter("alpha_floor", 0.018)
		_materials.append(material)
	_wave_material = ShaderMaterial.new(); _wave_material.shader = Foam; _wave_material.render_priority = 3
	_wave_material.set_shader_parameter("foam_texture",load(FROTH))
	_wave_material.set_shader_parameter("detail_texture",load(FROTH)); _wave_material.set_shader_parameter("ribbon",true)

func apply_snapshot(native: Dictionary) -> void:
	var now := float(native.get("time", _time))
	if not is_finite(now) or now < 0.0 or not _water.is_valid(): return
	if _time >= 0.0 and now < _time:
		_clear_trails(); _poses.clear(); _time = -1.0
	if now == _time: return
	var advancing := now > _time and _time >= 0.0
	var live: Dictionary = {}
	for ship: Dictionary in native.get("ships", []):
		var id := String(ship.get("id", ""))
		var visual: Dictionary = ship.get("visual", {})
		var point: Dictionary = visual.get("position", {})
		var dimensions: Dictionary = ship.get("dimensions", {})
		var length := float(dimensions.get("length", 0.0)); var width := float(dimensions.get("width", 0.0))
		var position := Vector2(float(point.get("x", NAN)), float(point.get("z", NAN)))
		var heading := float(visual.get("heading", NAN))
		var forward := Vector2(cos(heading), sin(heading))
		var velocity: Dictionary = visual.get("velocity", {})
		var speed := Vector2(float(velocity.get("x", 0.0)), float(velocity.get("z", 0.0))).dot(forward)
		if id.is_empty() or not position.is_finite() or not is_finite(heading) or not is_finite(speed) or length <= 0 or width <= 0: continue
		live[id] = true
		var pose := {"position":position-forward*length*0.51,"forward":forward,"time":now,"speed":speed,"width":width,"length":length}
		var emitting := float(ship.get("hull", 0.0)) > 0.0 and speed > 0.35
		pose.emitting = emitting; pose.acceleration = 0.0; pose.turn_rate = 0.0
		if advancing and _poses.has(id):
			var prior: Dictionary = _poses[id]; var elapsed := now-float(prior.time)
			if elapsed > 0.0:
				pose.acceleration = clampf((speed-float(prior.speed))/elapsed,-8.0,8.0)
				pose.turn_rate = prior.forward.angle_to(forward)/elapsed
		if advancing and not emitting and _trails.has(id): _trails[id].continuous = false
		if advancing and emitting and _poses.has(id):
			var previous: Dictionary = _poses[id]
			var gap: float = pose.position.distance_to(previous.position)
			if gap > maxf(length*1.8, speed*(now-previous.time)*3.0+width):
				_release(id) # Teleports and authority reconciliation do not paint connecting trails.
			elif gap > 0.001:
				if not _trails.has(id) and _trails.size() < MAX_TRAILS:
					var node := MeshInstance3D.new(); node.name = "Wake_"+id
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
					node.material_override = _materials[absi(id.hash()) % _materials.size()]
					add_child(node); node.top_level = true
					node.global_transform = Transform3D.IDENTITY
					var waves: Dictionary = {}
					for part: String in ["bow","port","starboard"]:
						var wave := MeshInstance3D.new(); wave.name = {"bow":"BowFoam","port":"PortFoam","starboard":"StarboardFoam"}[part]
						wave.material_override = _wave_material; wave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
						node.add_child(wave); waves[part] = wave
					_trails[id] = {"node":node,"samples":[previous.duplicate()],"continuous":true,"waves":waves}
				if _trails.has(id):
					var samples: Array = _trails[id].samples
					if now-float(samples.back().time) >= 0.08:
						var next_sample := pose.duplicate()
						next_sample.break_before = not bool(_trails[id].continuous)
						samples.append(next_sample); _trails[id].continuous = true
					while samples.size() > MAX_SAMPLES: samples.pop_front()
		if now > _time: _poses[id] = pose
	for id: String in _poses.keys():
		if not live.has(id): _poses.erase(id); _release(id)
	if now == _time: return
	_time = now
	for id: String in _trails.keys():
		var trail: Dictionary = _trails[id]; var samples: Array = trail.samples
		while not samples.is_empty() and now-float(samples.front().time) >= LIFETIME: samples.pop_front()
		if samples.is_empty(): _release(id); continue
		trail.node.visible = samples.size() >= 2
		if samples.size() < 2: continue
		_rebuild(trail)
		var pose: Dictionary = _poses.get(id,{})
		# History keeps the observed stern. Attached bow/side waves consume an
		# explicit ship-center pose; never mutate the stored history sample.
		var attachment := pose.duplicate()
		if not pose.is_empty(): attachment.position = pose.position+pose.forward*float(pose.length)*0.51
		for part: String in trail.waves:
			var wave: MeshInstance3D = trail.waves[part]
			wave.visible = bool(pose.get("emitting",false))
			if wave.visible:
				wave.mesh = ShipWave.build(attachment,part,_time,_water,_surface_filter)
				wave.visible = wave.mesh != null

func _rebuild(trail: Dictionary) -> void:
	var samples: Array = trail.samples
	var vertices := PackedVector3Array(); var colors := PackedColorArray()
	var uvs := PackedVector2Array(); var indices := PackedInt32Array()
	var wet: Array[bool] = []
	var tail_distances := PackedFloat32Array(); tail_distances.resize(samples.size())
	for index in samples.size():
		if index > 0 and not bool(samples[index].get("break_before",false)):
			tail_distances[index] = tail_distances[index-1]+samples[index].position.distance_to(samples[index-1].position)
	var distance := 0.0
	for row in samples.size():
		var index := samples.size()-1-row
		var sample: Dictionary = samples[index]
		var connects_newer := row > 0 and not bool(samples[index+1].get("break_before",false))
		var connects_older := index > 0 and not bool(sample.get("break_before",false))
		if connects_newer: distance += sample.position.distance_to(samples[index+1].position)
		else: distance = 0.0
		var tangent: Vector2 = sample.forward
		var newer: Vector2 = samples[index+1].position if connects_newer else sample.position
		var older: Vector2 = samples[index-1].position if connects_older else sample.position
		if newer.distance_to(older) > 0.001: tangent = (newer-older).normalized()
		var side := Vector2(-tangent.y,tangent.x)
		var age := maxf(0.0,_time-float(sample.time))
		var segment_length := distance+float(tail_distances[index])
		var head_fade := smoothstep(0.0,maxf(0.5,minf(float(sample.length)*0.24,segment_length*0.34)),distance)
		var tail_fade := smoothstep(0.0,maxf(0.6,minf(float(sample.length)*0.18,segment_length*0.32)),tail_distances[index])
		var taper := minf(0.20+head_fade*0.80,0.20+tail_fade*0.80)
		var organic := 0.90+0.10*sin(sample.position.x*0.8+sample.position.y*0.7)
		var surge := clampf(float(sample.get("acceleration",0.0))/3.0,0.0,1.0)
		var turn := clampf(absf(float(sample.get("turn_rate",0.0)))/0.65,0.0,1.0)
		var half_width := float(sample.width)*(0.36+age*0.075+surge*0.035+turn*0.05)*taper*organic
		var strength := smoothstep(0.35,3.2,float(sample.speed))*0.46*(1.0+surge*0.30)
		var fade := pow(1.0-age/LIFETIME,1.8)*head_fade*tail_fade
		if not connects_older: fade = 0.0
		for cross: float in CROSS_SECTIONS:
			var p: Vector2 = sample.position+side*half_width*cross
			var height := float(_water.call(p.x,p.y,_time))
			if not is_finite(height): height = 0.0
			vertices.append(Vector3(p.x,height+SURFACE_OFFSET,p.y))
			wet.append(Volume.sea(_surface_filter,p))
			colors.append(Color(1.0,1.0,1.0,strength*fade*pow(maxf(0.0,1.0-cross*cross),2.0)))
			uvs.append(Vector2((cross+1.0)*0.5,distance/maxf(4.0,float(sample.length)*0.72)))
		if connects_newer:
			for column in CROSS_SECTIONS.size()-1:
				var a := (row-1)*CROSS_SECTIONS.size()+column; var b := row*CROSS_SECTIONS.size()+column
				indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	trail.node.visible = not indices.is_empty()
	if indices.is_empty(): trail.node.mesh = null; return
	var valid := PackedInt32Array()
	for i in range(0,indices.size(),3):
		if wet[indices[i]] and wet[indices[i+1]] and wet[indices[i+2]]: valid.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
	trail.node.visible = not valid.is_empty()
	if valid.is_empty(): trail.node.mesh = null; return
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_TEX_UV] = uvs; arrays[Mesh.ARRAY_INDEX] = valid
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	trail.node.mesh = mesh

func _release(id: String) -> void:
	if not _trails.has(id): return
	_trails[id].node.free(); _trails.erase(id)

func _clear_trails() -> void:
	for id: String in _trails.keys(): _release(id)

func diagnostics() -> Dictionary:
	var samples := 0
	var waves := 0
	for trail: Dictionary in _trails.values(): samples += trail.samples.size()
	for trail: Dictionary in _trails.values():
		for node: MeshInstance3D in trail.waves.values():
			if node.visible: waves += 1
	return {"trails":_trails.size(),"samples":samples,"accepted_time":_time,"attached_waves":waves,"wave_budget":MAX_TRAILS*3}

func dispose() -> void:
	_clear_trails(); _poses.clear(); _materials.clear(); _wave_material = null; _water = Callable(); _surface_filter = Callable(); _time = -1.0

func _exit_tree() -> void: dispose()
