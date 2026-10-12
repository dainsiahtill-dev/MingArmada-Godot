extends RefCounted
## Deterministic game adapter for complete authored particle resources.
## Resource preservation is exact; distribution/color-age/cycle/gravity policies below
## are explicit game choices, not a reconstruction of the original NIF runtime.

const DEFINITIONS := "res://assets/data/reference_atmosphere/definitions/systems.json"
const RAW_TO_GAME := Basis(Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0))
const DEFAULTS := {"metres_per_unit": 0.01, "particles_per_layer": 128, "births_per_cycle": 512, "density": 1.0, "wind_drag": 0.12, "alpha_gain": 1.0, "radius_gain": 1.0}

var _options := DEFAULTS.duplicate()
var _layers := {}
var _effects := {}
var _events := {}
var _seen := {}
var _time := 0.0
var _wind := Vector3.ZERO
var _ready := false
var _rewinds := 0
var _late_expired := 0
var _snapshot: Array = []

func configure(definitions_path: String = DEFINITIONS, options: Dictionary = {}) -> bool:
	dispose()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(definitions_path))
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1 or parsed.get("systems", []).size() != 276:
		return false
	_options = DEFAULTS.duplicate()
	_options.merge(options, true)
	if not _valid_options():
		return false
	for source in parsed.systems:
		_layers[source.id] = _compile(source)
	for effect in parsed.effects:
		_effects[_name(effect.name)] = effect.system_ids.duplicate()
	_ready = true
	return true

func _valid_options() -> bool:
	for key in ["metres_per_unit", "density", "radius_gain", "alpha_gain", "wind_drag"]:
		if not _options[key] is float and not _options[key] is int:
			return false
		if not is_finite(float(_options[key])) or float(_options[key]) < 0.0:
			return false
	return float(_options.metres_per_unit) > 0.0 and int(_options.particles_per_layer) > 0 and int(_options.births_per_cycle) > 0

static func _name(value: String) -> String:
	return value.get_file().trim_suffix(".nif").to_lower()

static func scalar_key(group: Dictionary, time: float, fallback: float = 0.0) -> float:
	var keys: Array = group.get("keys", [])
	if keys.is_empty():
		return fallback
	if time <= float(keys[0].time):
		return float(keys[0].value)
	for i in range(1, keys.size()):
		if time <= float(keys[i].time):
			var span := float(keys[i].time) - float(keys[i - 1].time)
			if span <= 0.0:
				return float(keys[i].value)
			return lerpf(float(keys[i - 1].value), float(keys[i].value), clampf((time - float(keys[i - 1].time)) / span, 0.0, 1.0))
	return float(keys[-1].value)

static func rate_integral(group: Dictionary, start: float, stop: float) -> float:
	if stop <= start:
		return 0.0
	var breaks: Array[float] = [start, stop]
	for key in group.get("keys", []):
		if float(key.time) > start and float(key.time) < stop:
			breaks.append(float(key.time))
	breaks.sort()
	var total := 0.0
	for i in range(1, breaks.size()):
		var lo := maxf(0.0, scalar_key(group, breaks[i - 1]))
		var hi := maxf(0.0, scalar_key(group, breaks[i]))
		total += (lo + hi) * (breaks[i] - breaks[i - 1]) * 0.5
	return total

static func _active(keys: Array, time: float) -> bool:
	var active := true if keys.is_empty() else false
	for key in keys:
		if float(key.time) > time:
			break
		active = bool(key.value)
	return active

static func birth_schedule(controller: Dictionary, density: float, limit: int) -> Array[float]:
	var result: Array[float] = []
	var fields: Dictionary = controller.get("fields", {})
	var data: Dictionary = controller.get("data", {}).get("fields", {})
	var frequency := float(fields.get("frequency", 1.0))
	var phase := float(fields.get("phase", 0.0))
	if frequency <= 0.0 or density <= 0.0 or limit <= 0:
		return result
	var start := maxf(phase, float(fields.get("start_time", 0.0)))
	var stop := float(fields.get("stop_time", 0.0))
	if stop <= start or not controller.get("flags_decoded", {}).get("active", true):
		return result
	var rate: Dictionary = data.get("float_keys", {})
	var visibility: Array = data.get("visibility_keys", [])
	var breaks: Array[float] = [start, stop]
	for key in visibility + rate.get("keys", []):
		if float(key.time) > start and float(key.time) < stop:
			breaks.append(float(key.time))
	breaks.sort()
	var mass := 0.0
	var next := 0.5 # Deterministic midpoint quantization, an explicit game sampling policy.
	for i in range(1, breaks.size()):
		var a := breaks[i - 1]
		var b := breaks[i]
		if not _active(visibility, (a + b) * 0.5):
			continue
		var amount := rate_integral(rate, a, b) * density / frequency
		while next <= mass + amount and result.size() < limit:
			var lo := a
			var hi := b
			for iteration in 40:
				var mid := (lo + hi) * 0.5
				if mass + rate_integral(rate, a, mid) * density / frequency < next:
					lo = mid
				else:
					hi = mid
			result.append(((lo + hi) * 0.5 - phase) / frequency)
			next += 1.0
		mass += amount
	return result

static func _vec(value: Dictionary) -> Vector3:
	return Vector3(float(value.get("x", 0.0)), float(value.get("y", 0.0)), float(value.get("z", 0.0)))

static func _color(value: Dictionary, alpha: float = 1.0) -> Color:
	return Color(float(value.get("r", 1.0)), float(value.get("g", 1.0)), float(value.get("b", 1.0)), float(value.get("a", alpha)))

static func color_key(group: Dictionary, time: float) -> Color:
	var keys: Array = group.get("keys", [])
	if keys.is_empty():
		return Color.WHITE
	if time <= float(keys[0].time):
		return _color(keys[0].value)
	for i in range(1, keys.size()):
		if time <= float(keys[i].time):
			var span := float(keys[i].time) - float(keys[i - 1].time)
			return _color(keys[i - 1].value).lerp(_color(keys[i].value), clampf((time - float(keys[i - 1].time)) / maxf(span, 0.0000001), 0.0, 1.0))
	return _color(keys[-1].value)

static func grow_fade(age: float, life: float, fields: Dictionary, generation: int = 0) -> float:
	var grow := 1.0
	var fade := 1.0
	var grow_time := float(fields.get("grow_time", 0.0))
	var fade_time := float(fields.get("fade_time", 0.0))
	if int(fields.get("grow_generation", 0)) == generation and age < grow_time and grow_time > 0.0:
		grow = age / grow_time
	if int(fields.get("fade_generation", 0)) == generation and life - age < fade_time and fade_time > 0.0:
		fade = (life - age) / fade_time
	return maxf(minf(grow, fade), 0.0001)

static func raw_transform(chain: Array) -> Transform3D:
	var result := Transform3D.IDENTITY
	for node in chain:
		var t: Dictionary = node.get("transform", {})
		var r: Dictionary = t.get("rotation", {})
		var basis := Basis(Vector3(float(r.get("m_11", 1)), float(r.get("m_21", 0)), float(r.get("m_31", 0))), Vector3(float(r.get("m_12", 0)), float(r.get("m_22", 1)), float(r.get("m_32", 0))), Vector3(float(r.get("m_13", 0)), float(r.get("m_23", 0)), float(r.get("m_33", 1))))
		result = result * Transform3D(basis.scaled(Vector3.ONE * float(t.get("scale", 1.0))), _vec(t.get("translation", {})))
	return result

func _compile(source: Dictionary) -> Dictionary:
	var layer := {"source": source, "emitters": [], "color": {}, "grow": {}, "gravity": [], "texture": "", "glow": "", "blend": "alpha", "material": Color.WHITE, "alpha_threshold": 0.0, "uv_tiling": Vector2.ONE, "uv_offset": Vector2.ZERO, "uv_rotation": 0.0}
	for emitter in source.emitters:
		var schedules: Array = []
		var period := 0.0
		for controller in emitter.emission_controllers:
			schedules.append_array(birth_schedule(controller, float(_options.density), int(_options.births_per_cycle)))
			var frequency := float(controller.fields.get("frequency", 1.0))
			period = maxf(period, (float(controller.fields.get("stop_time", 0.0)) - float(controller.fields.get("phase", 0.0))) / maxf(frequency, 0.000001))
		var chain: Array = emitter.get("emitter_transform_chains", [])
		var transform := raw_transform(chain[0] if not chain.is_empty() else [])
		var f: Dictionary = emitter.fields
		layer.emitters.append({"source": emitter, "schedule": schedules, "period": maxf(period, 0.0001), "transform": transform, "max_life": maxf(float(f.get("life_span", 0.0)) + absf(float(f.get("life_span_variation", 0.0))) * 0.5, 0.001)})
	for modifier in source.modifiers:
		if not modifier.fields.get("active", true):
			continue
		match modifier.type:
			"NiPSysColorModifier": layer.color = modifier.get("data_resolved", {}).get("fields", {}).get("data", {})
			"NiPSysGrowFadeModifier": layer.grow = modifier.fields
			"NiPSysGravityModifier": layer.gravity.append(modifier)
	var paths: Array = source.get("texture_paths", [])
	if not paths.is_empty():
		for property in paths[0].properties:
			var p: Dictionary = property.property
			match p.type:
				"NiAlphaProperty":
					var decoded: Dictionary = p.get("decoded_flags", {})
					layer.blend = "add" if decoded.get("destination_blend", "INV_SRC_ALPHA") == "ONE" else "alpha"
					layer.alpha_threshold = float(p.fields.get("threshold", 0)) / 255.0 if decoded.get("alpha_test_enabled", false) else 0.0
				"NiMaterialProperty": layer.material = _color(p.fields.get("diffuse_color", {}), float(p.fields.get("alpha", 1.0)))
				"NiTexturingProperty":
					for slot in ["base_texture", "glow_texture"]:
						var bind: Dictionary = property.texture_bindings.get(slot, {})
						if not bind.get("files", []).is_empty():
							layer["texture" if slot == "base_texture" else "glow"] = bind.files[0].resource
					var desc: Dictionary = p.fields.get("base_texture", {})
					layer.uv_tiling = Vector2(float(desc.get("tiling", {}).get("u", 1.0)), float(desc.get("tiling", {}).get("v", 1.0)))
					layer.uv_offset = Vector2(float(desc.get("translation", {}).get("u", 0.0)), float(desc.get("translation", {}).get("v", 0.0)))
					layer.uv_rotation = float(desc.get("w_rotation", 0.0))
	return layer

func spawn(effect_name: String, event_id: String, born: float, world_position: Vector3, world_basis: Basis = Basis.IDENTITY, seed: int = 1, options: Dictionary = {}) -> bool:
	var effect := _name(effect_name)
	if not _ready or event_id.is_empty() or _seen.has(event_id) or not _effects.has(effect) or not is_finite(born) or born < 0.0 or not world_position.is_finite() or not world_basis.is_finite() or absf(world_basis.determinant()) < 0.00001:
		return false
	for key in ["scale", "alpha_gain", "radius_gain"]:
		if options.has(key):
			if not options[key] is float and not options[key] is int:
				return false
			if not is_finite(float(options[key])) or float(options[key]) < 0.0:
				return false
	if options.has("source_origin") and (not options.source_origin is Vector3 or not options.source_origin.is_finite()):
		return false
	var continuous := bool(options.get("continuous", effect.contains("burning_smoke") or effect == "smoketrail"))
	var event := {"id": event_id, "effect": effect, "born": born, "seed": seed, "continuous": continuous, "stop": INF, "options": options.duplicate(true), "poses": [{"time": born, "pose": Transform3D(world_basis, world_position)}]}
	_seen[event_id] = true
	_events[event_id] = event
	_refresh()
	return true

func set_emitter_transform(event_id: String, world_position: Vector3, world_basis: Basis, at_time: float = -1.0) -> bool:
	if not _ready or not _events.has(event_id) or not world_position.is_finite() or not world_basis.is_finite() or absf(world_basis.determinant()) < 0.00001:
		return false
	if at_time < 0.0:
		at_time = _time
	if not is_finite(at_time) or at_time < float(_events[event_id].born):
		return false
	var poses: Array = _events[event_id].poses
	if at_time < float(poses[-1].time):
		return false
	var next := {"time": at_time, "pose": Transform3D(world_basis, world_position)}
	if is_equal_approx(at_time, float(poses[-1].time)):
		poses[-1] = next
	else:
		poses.append(next)
	return true

func stop(event_id: String) -> bool:
	if not _events.has(event_id):
		return false
	_events[event_id].stop = _time
	return true

func set_time(accepted_time: float, wind: Variant = Vector3.ZERO) -> bool:
	if not _ready or not is_finite(accepted_time) or accepted_time < 0.0:
		return false
	var new_wind := Vector3.ZERO
	if wind is Vector3:
		new_wind = wind
	elif wind is Vector2:
		new_wind = Vector3(wind.x, 0, wind.y)
	else:
		return false
	if not new_wind.is_finite():
		return false
	if accepted_time < _time - 0.0000001:
		_events.clear()
		_seen.clear()
		_rewinds += 1
	_time = accepted_time
	_wind = new_wind
	_refresh()
	return true

static func _pose(event: Dictionary, time: float) -> Transform3D:
	var poses: Array = event.poses
	for i in range(1, poses.size()):
		if time < float(poses[i].time):
			var weight := clampf((time - float(poses[i - 1].time)) / maxf(float(poses[i].time) - float(poses[i - 1].time), 0.000001), 0.0, 1.0)
			return poses[i - 1].pose.interpolate_with(poses[i].pose, weight)
	return poses[-1].pose

func _particle(event: Dictionary, layer: Dictionary, emitter: Dictionary, born_local: float, ordinal: int) -> Dictionary:
	var born := float(event.born) + born_local
	var age := _time - born
	var rng := RandomNumberGenerator.new()
	rng.seed = int(event.seed) ^ int(layer.source.id.hash()) ^ (ordinal * 1103515245)
	var f: Dictionary = emitter.source.fields
	var life := maxf(float(f.get("life_span", 0.0)) + rng.randf_range(-0.5, 0.5) * float(f.get("life_span_variation", 0.0)), 0.001)
	if age < 0.0 or age >= life:
		return {}
	var theta := float(f.get("declination", 0.0)) + rng.randf_range(-0.5, 0.5) * float(f.get("declination_variation", 0.0))
	var phi := float(f.get("planar_angle", 0.0)) + rng.randf_range(-0.5, 0.5) * float(f.get("planar_angle_variation", 0.0))
	var raw_direction := Vector3(sin(theta) * cos(phi), sin(theta) * sin(phi), cos(theta))
	var speed := float(f.get("speed", 0.0)) + rng.randf_range(-0.5, 0.5) * float(f.get("speed_variation", 0.0))
	var offset := Vector3(rng.randf_range(-0.5, 0.5) * float(f.get("width", 0.0)), rng.randf_range(-0.5, 0.5) * float(f.get("height", 0.0)), rng.randf_range(-0.5, 0.5) * float(f.get("depth", 0.0)))
	var raw_tr: Transform3D = emitter.transform
	var root_pose := _pose(event, born)
	var scale := float(_options.metres_per_unit) * float(event.options.get("scale", 1.0))
	var raw_origin: Vector3 = event.options.get("source_origin", Vector3.ZERO)
	var start := root_pose * (RAW_TO_GAME * (raw_tr * offset - raw_origin) * scale)
	var velocity := root_pose.basis * RAW_TO_GAME * raw_tr.basis * raw_direction * speed * scale
	var acceleration := Vector3.ZERO
	for modifier in layer.gravity:
		var gf: Dictionary = modifier.fields
		var chains: Array = modifier.get("gravity_object_transform_chains", [])
		var gt := raw_transform(chains[0] if not chains.is_empty() else [])
		var axis := root_pose.basis * RAW_TO_GAME * gt.basis * _vec(gf.get("gravity_axis", {}))
		var center := root_pose * (RAW_TO_GAME * (gt.origin - raw_origin) * scale)
		var direction := (center - start).normalized() if int(gf.get("force_type", 0)) == 1 else -axis.normalized()
		var decay := exp(-maxf(float(gf.get("decay", 0.0)), 0.0) * center.distance_to(start) / maxf(scale, 0.000001))
		acceleration += direction * float(gf.get("strength", 0.0)) * scale * decay
	var position := start + velocity * age + acceleration * (0.5 * age * age) + _wind * age * float(_options.wind_drag)
	var color: Color = color_key(layer.color, age / life) * _color(f.get("initial_color", {})) * layer.material
	color.a = clampf(color.a * float(_options.alpha_gain) * float(event.options.get("alpha_gain", 1.0)), 0.0, 1.0)
	var radius := float(f.get("initial_radius", 1.0)) * scale * raw_tr.basis.x.length() * float(_options.radius_gain) * float(event.options.get("radius_gain", 1.0)) * grow_fade(age, life, layer.grow)
	return {"id": "%s:%s:%d" % [event.id, layer.source.id, ordinal], "event_id": event.id, "layer_id": layer.source.id, "position": position, "radius": radius, "color": color, "age": age, "life": life, "born": born, "texture": layer.texture, "glow": layer.glow, "blend": layer.blend, "alpha_threshold": layer.alpha_threshold, "uv_tiling": layer.uv_tiling, "uv_offset": layer.uv_offset, "uv_rotation": layer.uv_rotation}

func _refresh() -> void:
	_snapshot.clear()
	var expired: Array[String] = []
	for event_id in _events:
		var event: Dictionary = _events[event_id]
		var local_time := _time - float(event.born)
		var expiry := 0.0
		for layer_id in _effects[event.effect]:
			var layer: Dictionary = _layers[layer_id]
			var layer_particles: Array = []
			for emitter in layer.emitters:
				var period: float = emitter.period
				expiry = maxf(expiry, period + float(emitter.max_life))
				var first_cycle := maxi(0, int(floor((local_time - float(emitter.max_life)) / period))) if event.continuous else 0
				var last_cycle := maxi(0, int(floor(local_time / period))) if event.continuous else 0
				for cycle in range(first_cycle, last_cycle + 1):
					for i in emitter.schedule.size():
						var local_birth: float = emitter.schedule[i] + float(cycle) * period
						if local_birth > local_time or float(event.born) + local_birth > float(event.stop):
							continue
						var particle := _particle(event, layer, emitter, local_birth, cycle * int(_options.births_per_cycle) + i)
						if not particle.is_empty():
							layer_particles.append(particle)
			# Explicit game bound, not the original static num_vertices as a dynamic maximum.
			if layer_particles.size() > int(_options.particles_per_layer):
				layer_particles = layer_particles.slice(layer_particles.size() - int(_options.particles_per_layer))
			_snapshot.append_array(layer_particles)
		if (not event.continuous and local_time > expiry) or (is_finite(float(event.stop)) and _time > float(event.stop) + expiry):
			expired.append(event_id)
	for id in expired:
		_events.erase(id)
		_late_expired += 1

func snapshot() -> Array:
	return _snapshot.duplicate(true)

func diagnostics() -> Dictionary:
	var counts := {}
	for effect in _effects:
		counts[effect] = _effects[effect].size()
	return {"ready": _ready, "accepted_time": _time, "source_systems": _layers.size(), "effects": _events.size(), "alive_particles": _snapshot.size(), "dedup_ids": _seen.size(), "rewinds": _rewinds, "expired": _late_expired, "effect_layers": counts, "game_particles_per_layer": int(_options.particles_per_layer), "native_runtime_equivalent": false}

func dispose() -> void:
	_ready = false
	_layers.clear()
	_effects.clear()
	_events.clear()
	_seen.clear()
	_snapshot.clear()
	_time = 0.0
	_wind = Vector3.ZERO
	_rewinds = 0
	_late_expired = 0
