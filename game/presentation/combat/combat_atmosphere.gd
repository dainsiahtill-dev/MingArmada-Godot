extends Node3D
## Original game presentation. Event births and accepted time are read-only;
## smoke is world-space and wreck flames follow an explicitly current deck.
const SMOKE_PATH := "res://assets/textures/combat_atmosphere/r1/smoke-puff.png"
const FLAME_PATH := "res://assets/textures/combat_atmosphere/r1/flame.png"
const MAX_LIFETIME := 9.0
const MAX_SEEN := 4096
const KINDS := ["smoke", "flame", "ember"]
var _ready_state := false
var _enabled := true
var _capacity := 384
var _time := 0.0
var _epoch := "scene"
var _has_snapshot := false
var _wind := Vector3.ZERO
var _camera: Camera3D
var _water: Callable
var _anchor_provider: Callable
var _items: Array[Dictionary] = []
var _seen: Dictionary = {}
var _wrecks: Dictionary = {}
var _batches: Dictionary = {}
var _textures: Dictionary = {}
var _visible: Array[Dictionary] = []
var _bounds := AABB()
var _draw_calls := 0
var _dropped := 0
var _underwater_stopped := 0

func configure(options: Dictionary = {}, camera: Camera3D = null, water_sampler: Callable = Callable(), anchor_provider: Callable = Callable()) -> Dictionary:
	dispose()
	_enabled = bool(options.get("enabled", true))
	_capacity = 192 if str(options.get("quality", "balanced")) == "low" else 384
	_camera = camera
	_water = water_sampler
	_anchor_provider = anchor_provider
	# Carriers contain accepted world coordinates, independent of the host pose.
	top_level = true
	transform = Transform3D.IDENTITY
	if not _enabled:
		_ready_state = true
		return {"ok": true, "enabled": false, "capacity": _capacity}
	var smoke := _load_texture(SMOKE_PATH)
	var flame := _load_texture(FLAME_PATH)
	if smoke == null or flame == null:
		return {"ok": false, "reason": "combat-atmosphere-texture-unavailable"}
	_textures = {"smoke": smoke, "flame": flame, "ember": flame}
	for kind: String in KINDS: _create_batch(kind, _textures[kind])
	_ready_state = true
	return {"ok": true, "enabled": true, "capacity": _capacity}

static func _load_texture(path: String) -> Texture2D:
	# Development may receive a generated PNG before the editor imports it.
	# Original pixels stay untouched; mip generation is an owned runtime copy.
	# Exported PCKs can contain only .png.remap plus .ctex, without either the
	# editor's .import sidecar or original PNG. Resolve native resources first.
	if ResourceLoader.exists(path):
		var resource: Resource = ResourceLoader.load(path)
		if resource is Texture2D: return resource
	if not FileAccess.file_exists(path): return null
	var pixels := Image.new()
	if pixels.load(path) != OK or pixels.is_empty(): return null
	if not pixels.has_mipmaps(): pixels.generate_mipmaps()
	return ImageTexture.create_from_image(pixels)

func _create_batch(kind: String, texture: Texture2D) -> void:
	var carrier := MultiMeshInstance3D.new()
	carrier.name = "Atmosphere" + kind.capitalize()
	carrier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mesh := QuadMesh.new()
	mesh.size = Vector2.ONE
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.vertex_color_use_as_albedo = true
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	material.billboard_keep_scale = true
	material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_repeat = false
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	if kind != "smoke": material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	carrier.material_override = material
	var instances := MultiMesh.new()
	instances.transform_format = MultiMesh.TRANSFORM_3D
	instances.use_colors = true
	instances.mesh = mesh
	instances.instance_count = _capacity
	instances.visible_instance_count = 0
	carrier.multimesh = instances
	add_child(carrier)
	_batches[kind] = carrier

func set_camera(camera: Camera3D) -> void:
	_camera = camera
	_render()

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _point(value: Variant) -> Variant:
	if value is Vector3: return value if value.is_finite() else null
	if not value is Dictionary or not value.has_all(["x", "y", "z"]): return null
	if not _number(value.x) or not _number(value.y) or not _number(value.z): return null
	return Vector3(float(value.x), float(value.y), float(value.z))

static func _wind_from(packet: Variant) -> Vector3:
	if not packet is Dictionary or not _number(packet.get("speed")): return Vector3.ZERO
	var direction: Variant = packet.get("direction")
	if not direction is Dictionary or not _number(direction.get("x")) or not _number(direction.get("y")): return Vector3.ZERO
	var horizontal := Vector3(float(direction.x), 0.0, float(direction.y))
	if horizontal.length_squared() < 1.0e-12: return Vector3.ZERO
	# Existing naval wind direction means where the wind comes FROM.
	return -horizontal.normalized() * clampf(float(packet.speed), 0.0, 100.0)

func apply_snapshot(native: Dictionary) -> void:
	if not _ready_state or not _number(native.get("time")) or float(native.time) < 0.0: return
	var next_time := float(native.time)
	var next_epoch: String = str(native.get("battleId", "scene"))
	if next_epoch.is_empty(): next_epoch = "scene"
	if _has_snapshot and (next_epoch != _epoch or next_time < _time): _clear_timeline()
	_time = next_time
	_epoch = next_epoch
	_has_snapshot = true
	_wind = _wind_from(native.get("wind", {}))
	_prune()
	# An anchor from the previous displayed ship frame cannot move a flame now.
	# The world explicitly refreshes after all ship transforms are submitted.
	for wreck: Dictionary in _wrecks.values():
		if float(wreck.anchor_time) != _time: wreck.available = false
	_render()

func apply_events(events: Array) -> void:
	if not _ready_state or not _enabled or not _has_snapshot: return
	for value: Variant in events:
		if not value is Dictionary: continue
		var receipt: Dictionary = value
		var kind: Variant = receipt.get("type")
		var id: Variant = receipt.get("id")
		if kind not in ["fire", "hit", "destruction-explosion"] or not id is String or id.is_empty(): continue
		if not _number(receipt.get("time")): continue
		var born := float(receipt.time)
		# Validate time and coordinates before dedupe: a future delivery may later
		# be accepted, and invalid payloads must not poison a legitimate event ID.
		if born < 0.0 or born > _time: continue
		var field: String = "source_muzzle_position" if kind == "fire" else "source_effect_position" if kind == "destruction-explosion" else "position"
		var origin: Variant = _point(receipt.get(field, receipt.get("position")))
		if not origin is Vector3: continue
		if _seen.has(id) or _time - born >= MAX_LIFETIME: continue
		if _seen.size() >= MAX_SEEN:
			_dropped += 1
			continue
		_seen[id] = born
		var rng := RandomNumberGenerator.new()
		rng.seed = absi(String(id).hash())
		match kind:
			"fire": _cannon(String(id), born, origin, receipt, rng)
			"hit": _impact(String(id), born, origin, rng)
			"destruction-explosion": _destruction(String(id), born, origin, str(receipt.get("shipId", "")), rng)
	_render()

func _add(id: String, kind: String, born: float, duration: float, origin: Vector3, velocity: Vector3, size: float, growth: float, color: Color, extra: Dictionary = {}) -> void:
	var expires := born + duration
	if _time >= expires: return
	if _items.size() >= _capacity:
		_dropped += 1
		return
	var item := {"id": id, "kind": kind, "born": born, "expires": expires, "origin": origin, "velocity": velocity, "size": size, "growth": growth, "color": color, "wind": _wind * 0.28, "phase": float(absi(id.hash()) % 6283) / 1000.0}
	item.merge(extra, true)
	_items.append(item)

func _cannon(id: String, born: float, origin: Vector3, receipt: Dictionary, rng: RandomNumberGenerator) -> void:
	var shot: Variant = _point(receipt.get("velocity"))
	var forward := Vector3.ZERO
	if shot is Vector3 and shot.length_squared() > 1.0e-8: forward = shot.normalized()
	for index in 11:
		var spread := Vector3(rng.randf_range(-0.42, 0.42), rng.randf_range(0.45, 1.0), rng.randf_range(-0.42, 0.42))
		var velocity := spread + forward * rng.randf_range(0.35, 1.5)
		_add(id + ":smoke:%d" % index, "smoke", born, rng.randf_range(6.5, 8.8), origin, velocity, rng.randf_range(1.0, 2.3), rng.randf_range(0.55, 0.9), Color(0.74, 0.72, 0.67, rng.randf_range(0.13, 0.23)))
	for index in 2:
		_add(id + ":flame:%d" % index, "flame", born, 0.14, origin, forward * (1.0 + index), 1.8 + index * 0.7, 1.3, Color(1.0, 0.76, 0.42, 0.68), {"wind": Vector3.ZERO})
	for index in 3:
		_add(id + ":ember:%d" % index, "ember", born, 0.45, origin, forward * rng.randf_range(4.0, 7.0) + Vector3.UP * rng.randf_range(0.5, 2.0), 0.12, 0.0, Color(1.0, 0.58, 0.2, 0.68), {"wind": _wind * 0.08})

func _impact(id: String, born: float, origin: Vector3, rng: RandomNumberGenerator) -> void:
	for index in 7:
		var velocity := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.7, 1.8), rng.randf_range(-1.0, 1.0))
		_add(id + ":dust:%d" % index, "smoke", born, rng.randf_range(1.2, 2.0), origin, velocity, rng.randf_range(0.55, 1.25), 0.65, Color(0.46, 0.35, 0.23, 0.25))
	for index in 3:
		var velocity := Vector3(rng.randf_range(-2.4, 2.4), rng.randf_range(1.0, 3.0), rng.randf_range(-2.4, 2.4))
		_add(id + ":ember:%d" % index, "ember", born, rng.randf_range(0.28, 0.5), origin, velocity, 0.10, 0.0, Color(1.0, 0.55, 0.18, 0.55), {"wind": _wind * 0.08})

func _destruction(id: String, born: float, origin: Vector3, ship_id: String, rng: RandomNumberGenerator) -> void:
	for index in 23:
		var velocity := Vector3(rng.randf_range(-0.7, 0.7), rng.randf_range(0.85, 1.75), rng.randf_range(-0.7, 0.7))
		_add(id + ":smoke:%d" % index, "smoke", born, rng.randf_range(7.0, MAX_LIFETIME), origin, velocity, rng.randf_range(2.2, 4.2), rng.randf_range(0.8, 1.3), Color(0.24, 0.23, 0.21, rng.randf_range(0.18, 0.3)))
	# No point exists until the owner supplies the actual current drawn deck.
	# Historical smoke above remains valid even when the ship is unavailable.
	if not ship_id.is_empty() and _time < born + 3.5:
		_wrecks[id] = {"ship_id": ship_id, "born": born, "expires": born + 3.5, "available": false, "anchor_time": -INF, "point": Vector3.ZERO, "stopped": false}
		for index in 4:
			var offset := Vector3(rng.randf_range(-0.65, 0.65), rng.randf_range(0.2, 0.8), rng.randf_range(-0.5, 0.5))
			_add(id + ":flame:%d" % index, "flame", born, 3.5, origin, Vector3.ZERO, rng.randf_range(2.8, 4.2), 0.0, Color(1.0, 0.72, 0.36, 0.72), {"wreck": id, "offset": offset, "wind": Vector3.ZERO})
	for index in 5:
		var velocity := Vector3(rng.randf_range(-1.8, 1.8), rng.randf_range(1.8, 4.0), rng.randf_range(-1.8, 1.8))
		_add(id + ":ember:%d" % index, "ember", born, rng.randf_range(0.7, 1.25), origin, velocity, 0.14, 0.0, Color(1.0, 0.55, 0.17, 0.65), {"wind": _wind * 0.1})

func refresh_anchors() -> void:
	if not _ready_state or not _enabled: return
	for wreck: Dictionary in _wrecks.values():
		wreck.available = false
		if wreck.stopped or not _anchor_provider.is_valid() or _time >= float(wreck.expires): continue
		var supplied: Variant = _anchor_provider.call(String(wreck.ship_id))
		if not supplied is Dictionary or not _number(supplied.get("time")) or float(supplied.time) != _time: continue
		if str(supplied.get("shipId", "")) != String(wreck.ship_id): continue
		var point: Variant = _point(supplied.get("position"))
		if not point is Vector3: continue
		if not _water.is_valid(): continue
		var height: Variant = _water.call(point.x, point.z, _time)
		if not _number(height): continue
		if point.y <= float(height):
			wreck.stopped = true
			_underwater_stopped += 1
			continue
		wreck.point = point
		wreck.anchor_time = _time
		wreck.available = true
	_render()

func _prune() -> void:
	for index in range(_items.size() - 1, -1, -1):
		if _time >= float(_items[index].expires): _items.remove_at(index)
	for id: String in _wrecks.keys():
		if _time >= float(_wrecks[id].expires): _wrecks.erase(id)
	# IDs become irrelevant only after every supported event kind has expired.
	for id: String in _seen.keys():
		if _time - float(_seen[id]) >= MAX_LIFETIME: _seen.erase(id)

func _sample(item: Dictionary) -> Dictionary:
	var age := _time - float(item.born)
	var lifetime := float(item.expires) - float(item.born)
	if age < 0.0 or age >= lifetime: return {}
	var progress := age / lifetime
	var point: Vector3 = item.origin + (item.velocity + item.wind) * age
	var size := float(item.size) + float(item.growth) * age
	var color: Color = item.color
	var alpha := color.a * pow(1.0 - progress, 1.35)
	if item.kind == "smoke":
		# A bounded deterministic curl begins at zero and cannot advance on pause.
		point += Vector3(sin(age * 0.72 + float(item.phase)) - sin(float(item.phase)), 0.05 * age * age, cos(age * 0.63 + float(item.phase)) - cos(float(item.phase))) * 0.22
	elif item.kind == "ember":
		point.y -= 1.7 * age * age
	elif item.has("wreck"):
		var wreck: Dictionary = _wrecks.get(String(item.wreck), {})
		if wreck.is_empty() or not wreck.available or wreck.stopped or float(wreck.anchor_time) != _time: return {}
		point = wreck.point + item.offset
		point.x += sin(age * 7.0 + float(item.phase)) * 0.13
		point.y += sin(age * 9.0 + float(item.phase)) * 0.12
		size *= 0.9 + 0.12 * sin(age * 11.0 + float(item.phase))
		alpha *= 0.82 + 0.18 * sin(age * 13.0 + float(item.phase))
	if not point.is_finite() or not is_finite(size) or not is_finite(alpha): return {}
	return {"id": item.id, "kind": item.kind, "position": [point.x, point.y, point.z], "size": size, "alpha": alpha, "born": item.born, "expires": item.expires, "_color": color}

func _depth(particle: Dictionary) -> float:
	var coordinates: Array = particle.position
	var point := Vector3(float(coordinates[0]), float(coordinates[1]), float(coordinates[2]))
	return (point - _camera.global_position).dot(-_camera.global_basis.z) if is_instance_valid(_camera) and _camera.is_inside_tree() else 0.0

func _render() -> void:
	_visible.clear()
	_draw_calls = 0
	_bounds = AABB()
	var grouped := {"smoke": [], "flame": [], "ember": []}
	if _ready_state and _enabled:
		for item: Dictionary in _items:
			var particle := _sample(item)
			if particle.is_empty(): continue
			grouped[String(item.kind)].append(particle)
			var public := particle.duplicate()
			public.erase("_color")
			_visible.append(public)
	var bounds_initialized := false
	for kind: String in KINDS:
		if not _batches.has(kind): continue
		var rows: Array = grouped[kind]
		if kind == "smoke" and is_instance_valid(_camera):
			rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
				var left := _depth(a)
				var right := _depth(b)
				return left > right if left != right else String(a.id) < String(b.id))
		var carrier: MultiMeshInstance3D = _batches[kind]
		var instances: MultiMesh = carrier.multimesh
		instances.visible_instance_count = rows.size()
		carrier.visible = not rows.is_empty()
		if rows.is_empty():
			instances.custom_aabb = AABB()
			continue
		_draw_calls += 1
		var batch_bounds := AABB()
		for index in rows.size():
			var row: Dictionary = rows[index]
			var point := Vector3(float(row.position[0]), float(row.position[1]), float(row.position[2]))
			var size := float(row.size)
			var color: Color = row._color
			color.a = float(row.alpha)
			instances.set_instance_transform(index, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), point))
			instances.set_instance_color(index, color)
			# Full orientation-independent quad radius prevents camera orbit culling.
			var extent := Vector3.ONE * size * 0.75
			var bound := AABB(point - extent, extent * 2.0)
			batch_bounds = bound if index == 0 else batch_bounds.merge(bound)
		instances.custom_aabb = batch_bounds
		_bounds = batch_bounds if not bounds_initialized else _bounds.merge(batch_bounds)
		bounds_initialized = true

func diagnostics() -> Dictionary:
	var counts := {"smoke": 0, "flame": 0, "ember": 0}
	for particle: Dictionary in _visible: counts[String(particle.kind)] += 1
	return {"ready": _ready_state, "enabled": _enabled, "time": _time, "epoch": _epoch, "active_smoke": counts.smoke, "active_flames": counts.flame, "active_embers": counts.ember, "capacity": _capacity, "seen_events": _seen.size(), "particles": _visible.duplicate(true), "draw_calls": _draw_calls, "bounds": {"position": [_bounds.position.x, _bounds.position.y, _bounds.position.z], "size": [_bounds.size.x, _bounds.size.y, _bounds.size.z]}, "underwater_stopped": _underwater_stopped, "dropped": _dropped, "reserved_particles": _items.size(), "renderer": "three textured MultiMesh sprite batches; smoke sorted within its batch, no volumetric backend"}

func _clear_timeline() -> void:
	_items.clear()
	_seen.clear()
	_wrecks.clear()
	_visible.clear()
	_underwater_stopped = 0
	_dropped = 0
	_draw_calls = 0
	_bounds = AABB()

func dispose() -> void:
	_clear_timeline()
	for carrier: MultiMeshInstance3D in _batches.values():
		if is_instance_valid(carrier): carrier.free()
	_batches.clear()
	_textures.clear()
	_ready_state = false
	_has_snapshot = false
	_time = 0.0
	_epoch = "scene"
	_wind = Vector3.ZERO
	_camera = null
	_water = Callable()
	_anchor_provider = Callable()

func _exit_tree() -> void: dispose()
