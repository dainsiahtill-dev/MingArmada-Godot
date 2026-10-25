extends RefCounted
## Presentation-only stages and finite accepted-clock clips; no damage settlement.

const DamageShader = preload("res://game/presentation/ships/ship_damage.gdshader")
const AlphaDamageShader = preload("res://game/presentation/ships/ship_damage_alpha.gdshader")
const MAST_DURATION := 2.66666698456
const SINK_DURATION := 4.125
const MAST_KEY := 0.041666984558
const EXPLOSION_KEY := 0.25
const FROTH_KEY := 1.41666793823
const TEXTURE_ROOT := "res://assets/textures/pirates_damage_reference/"
var _textures: Dictionary = {}
var _models: Array[Node3D] = []
var _materials: Array[Dictionary] = []
var _masts: Array[Dictionary] = []
var _rigs: Array[Dictionary] = []
var _flags: Array[Dictionary] = []
var _rests: Dictionary = {}
var _time := 0.0
var _initialized := false
var _mast_start := -INF
var _sink_start := -INF
var _sent: Dictionary = {}
var _hull_stage := 0
var _sail_quantized := 0
var _sail_stage := 0
var _mask_stage := -1
var _depth := 20.0

func configure(models: Array[Node3D], texture_root: String = TEXTURE_ROOT) -> void:
	dispose()
	for surface in ["hull", "sail"]:
		for suffix in ([0, 20, 40, 60, 80, 100] if surface == "hull" else [20, 40, 60, 80, 100]):
			var path := texture_root.path_join("ship_%s_damage%03d.dds.png" % [surface, suffix])
			if ResourceLoader.exists(path):
				var texture = load(path)
				if texture is Texture2D:
					_textures["%s:%d" % [surface, suffix]] = texture
	_models = models.duplicate()
	for model in _models:
		_rests[model.get_instance_id()] = model.transform
		var model_masts: Array[Dictionary] = []
		for node in model.find_children("*", "Node3D", true, false):
			var name := String(node.name)
			if name.begins_with("mast_") and name.trim_prefix("mast_").is_valid_int():
				var entry := {"node": node, "rest": node.transform}
				_masts.append(entry)
				model_masts.append(entry)
			if not node is MeshInstance3D or node.mesh == null:
				continue
			var surface_kind := String(node.get_meta("damage_surface", "sail" if name.begins_with("sail_") else ("hull" if name == "hull" or name.begins_with("hull_") else "")))
			if surface_kind not in ["hull", "sail"]:
				continue
			var sail := surface_kind == "sail"
			for surface in node.mesh.get_surface_count():
				# Authored junk sails merge cloth, bamboo and sheets to reef as one
				# mesh. Only canvas tears; solid rig parts retain their own material.
				var authored_material = node.get_active_material(surface)
				if model.get_meta("model_origin","")=="blender_authored" and sail and authored_material is StandardMaterial3D and authored_material.resource_name!="canvas":continue
				var material := ShaderMaterial.new()
				material.shader = DamageShader
				material.set_shader_parameter("sail_surface", sail)
				var original = node.get_active_material(surface)
				if original is StandardMaterial3D:
					material.set_shader_parameter("authored_thin_cloth",model.get_meta("model_origin","")=="blender_authored" and sail and original.resource_name=="canvas")
					material.set_shader_parameter("original_color", original.albedo_color)
					material.set_shader_parameter("original_roughness", original.roughness)
					material.set_shader_parameter("original_albedo", original.albedo_texture)
					material.set_shader_parameter("use_original_albedo", original.albedo_texture != null)
					material.set_shader_parameter("use_original_vertex_color", original.vertex_color_use_as_albedo)
					material.set_shader_parameter("original_uv_scale", Vector2(original.uv1_scale.x, original.uv1_scale.y))
					material.set_shader_parameter("original_uv_offset", Vector2(original.uv1_offset.x, original.uv1_offset.y))
					material.set_shader_parameter("original_alpha_cutoff", original.alpha_scissor_threshold if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
				var layers: Variant = node.get_meta("source_hull_layers", {})
				if layers is Array:
					layers = layers[surface] if surface < layers.size() else {}
				var layered_hull: bool = layers is Dictionary and layers.get("player") is Texture2D and layers.get("upgrade") is Texture2D
				# Blend-only source cloth/rope uses a separate transparent program.
				# The ordinary hull program never writes ALPHA and stays opaque.
				if original is StandardMaterial3D and original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and not layered_hull:
					material.shader = AlphaDamageShader
				if layered_hull:
					material.set_shader_parameter("use_source_hull_layers", true)
					material.set_shader_parameter("original_player", layers.player)
					material.set_shader_parameter("original_upgrade", layers.upgrade)
					material.set_shader_parameter("original_has_damage_uv", bool(layers.get("damage_uv2", false)))
				material.set_shader_parameter("reference_damage_uv2", bool(node.get_meta("damage_uv2", false)))
				# A single override would erase all but one imported material slot.
				if node.mesh.get_surface_count() == 1:
					node.material_override = material
				else:
					node.set_surface_override_material(surface, material)
				_materials.append({"node": node, "material": material, "original": original, "surface": surface, "sail": sail, "seed": int(name.trim_prefix("sail_")) if sail else 0, "bound_stage": -1})
			_depth = maxf(_depth, node.position.y + node.get_aabb().end.y + 3.0)
		_split_rigging(model, model_masts)
		for flag: Node3D in model.find_children("flag_*", "Node3D", true, false):
			if bool(flag.get_meta("source_fixed_attachment", false)): continue
			var already_carried := false
			for mast: Dictionary in model_masts:
				if mast.node.is_ancestor_of(flag): already_carried = true
			if not model_masts.is_empty() and not already_carried:
				_flags.append({"node": flag, "rest": flag.transform, "pivot": _nearest_mast(flag.position, model_masts).rest.origin})

func apply_snapshot(ship: Dictionary, now: float, reduced_motion := false) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if not is_finite(now):
		return events
	var rewind := _initialized and now < _time - 1.0e-8
	var previous := _time
	if rewind:
		_mast_start = -INF
		_sink_start = -INF
		_sent.clear()
	var first := not _initialized or rewind
	var hull_damage := _damage(ship, "hull", "maxHull")
	var sail_damage := _damage(ship, "sail", "maxSail")
	_hull_stage = int(floor(hull_damage / 20.0 + 1.0e-6))
	_sail_quantized = 6 * int(floor(sail_damage / 6.0 + 1.0e-6))
	_sail_stage = int(floor(float(int(_sail_quantized / 5.0)) / 4.0))
	if sail_damage >= 100.0 and not is_finite(_mast_start):
		_mast_start = now - MAST_DURATION if first else now
	if hull_damage >= 100.0 and not is_finite(_sink_start):
		_sink_start = now - SINK_DURATION if first else now
	if sail_damage < 100.0:
		_mast_start = -INF
		_sent.erase("mast-break")
	if hull_damage < 100.0:
		_sink_start = -INF
		_sent.erase("destruction-explosion")
		_sent.erase("sinking-froth")
	_time = now
	_initialized = true
	for entry: Dictionary in _materials:
		var stage := _sail_stage if entry.sail else _hull_stage
		entry.material.set_shader_parameter("damage_stage", float(stage))
		if entry.bound_stage != stage:
			var key := "%s:%d" % ["sail" if entry.sail else "hull", stage * 20]
			var texture: Texture2D = _textures.get(key) if stage > 0 else null
			entry.material.set_shader_parameter("reference_damage", texture)
			entry.material.set_shader_parameter("use_reference_damage", texture != null)
			entry.bound_stage = stage
		if entry.sail and _mask_stage != _sail_stage:
			var tears := sail_tears(_sail_stage, entry.seed)
			entry.material.set_shader_parameter("tear_count", tears.size())
			tears.resize(12)
			entry.material.set_shader_parameter("tears", tears)
	_mask_stage = _sail_stage
	for entry: Dictionary in _masts:
		var progress := clampf((now - _mast_start) / MAST_DURATION, 0.0, 1.0) if is_finite(_mast_start) else 0.0
		# Fall in model space around the actual deck pivot, before healthy trim.
		# Recompose from rest every tick: Euler mutation would retain old fall axes.
		var fall := Basis(Vector3.BACK, progress * progress * 1.45)
		var trim := Basis(Vector3.UP, float(entry.node.get_meta("sail_trim_origin", PI / 2.0)) - clampf(float(ship.get("sailAngle", 0.0)), -PI / 2.0, PI / 2.0))
		entry.node.transform = Transform3D(fall * entry.rest.basis * trim, entry.rest.origin)
	var rig_progress := clampf((now - _mast_start) / MAST_DURATION, 0.0, 1.0) if is_finite(_mast_start) else 0.0
	var rig_fall := Basis(Vector3.BACK, rig_progress * rig_progress * 1.45)
	for entry: Dictionary in _rigs:
		entry.node.transform = Transform3D(rig_fall, entry.pivot - rig_fall * entry.pivot) * entry.rest
	for entry: Dictionary in _flags:
		var rest: Transform3D = entry.rest
		rest.basis *= Basis(Vector3.BACK, 0.0 if reduced_motion else sin(now * 4.0) * 0.025)
		entry.node.transform = Transform3D(rig_fall, entry.pivot - rig_fall * entry.pivot) * rest
	for model in _models:
		model.transform = model_transform_at(model, now)
	for key: Array in [["mast-break", _mast_start, MAST_KEY], ["destruction-explosion", _sink_start, EXPLOSION_KEY], ["sinking-froth", _sink_start, FROTH_KEY]]:
		var at: float = key[1] + key[2]
		if is_finite(at) and now >= at and not _sent.has(key[0]):
			_sent[key[0]] = true
			if not first and previous < at:
				events.append({"type": key[0], "time": at, "id": "%s:%s:%s" % [ship.get("id", ""), key[0], at], "shipId": ship.get("id", ""), "targetId": ship.get("id", "")})
	return events

func model_transform_at(model: Node3D, at: float) -> Transform3D:
	# Rendering and delayed placement share the immutable rest and sink phase.
	var rest: Transform3D = _rests.get(model.get_instance_id(), Transform3D.IDENTITY)
	if not is_finite(at) or not is_finite(_sink_start): return rest
	var progress := clampf((at - _sink_start) / SINK_DURATION, 0.0, 1.0)
	if progress == 0.0: return rest
	var angles := rest.basis.orthonormalized().get_euler(model.rotation_order)
	angles.z += sin(progress * PI * 0.5) * 0.32
	var basis := Basis.from_euler(angles, model.rotation_order).scaled_local(rest.basis.get_scale())
	return Transform3D(basis, rest.origin + Vector3.DOWN * _depth * progress * progress)

static func sail_tears(stage: int, seed: int = 0) -> PackedVector4Array:
	var result := PackedVector4Array()
	stage = clampi(stage, 0, 4)
	var anchors := [Vector2(0.27, 0.26), Vector2(0.69, 0.57), Vector2(0.47, 0.81), Vector2(0.81, 0.19), Vector2(0.21, 0.65), Vector2(0.52, 0.43), Vector2(0.76, 0.85), Vector2(0.09, 0.37), Vector2(0.92, 0.48), Vector2(0.36, 0.09), Vector2(0.61, 0.23)]
	for index in [0, 4, 6, 8, 11][stage]:
		var phase := float(index * 37 + seed * 19)
		var jitter := Vector2(sin(phase * 1.7), cos(phase * 2.3)) * 0.021
		var centre: Vector2 = anchors[index] + jitter
		var radius := (0.025 + stage * 0.008) * (0.8 + (sin(phase * 3.1) + 1.0) * 0.175)
		result.append(Vector4(centre.x, centre.y, radius, sin(phase * 0.9) * 0.75))
	return result

func _nearest_mast(point: Vector3, masts: Array[Dictionary]) -> Dictionary:
	var nearest: Dictionary = masts[0]
	for mast: Dictionary in masts:
		if Vector2(mast.rest.origin.x, mast.rest.origin.z).distance_squared_to(Vector2(point.x, point.z)) < Vector2(nearest.rest.origin.x, nearest.rest.origin.z).distance_squared_to(Vector2(point.x, point.z)):
			nearest = mast
	return nearest

func _find_component(parents: Array[int], index: int) -> int:
	while parents[index] != index:
		parents[index] = parents[parents[index]]
		index = parents[index]
	return index

func _split_rigging(model: Node3D, masts: Array[Dictionary]) -> void:
	# New Blender assets carry explicit standing-rig ownership. Trim rotates
	# cloth around a fixed spar; only damage should move the deck-fixed stays.
	for node: Node3D in model.find_children("*", "Node3D", true, false):
		if not node.has_meta("authored_mast_index"): continue
		var mast_name := "mast_%d" % int(node.get_meta("authored_mast_index"))
		for mast: Dictionary in masts:
			if String(mast.node.name) == mast_name:
				_rigs.append({"node":node,"rest":node.transform,"pivot":mast.rest.origin})
				break
	# Authored exporter merged shrouds/ratlines with deck trim. Recover actual
	# disconnected beam components, with coincident vertices welded for caps/seams.
	var batch := model.find_child("fittings_trim", true, false) as MeshInstance3D
	if batch == null or batch.mesh == null or masts.is_empty():
		return
	var fixed_mesh := ArrayMesh.new()
	var moving: Dictionary = {}
	var rope := Color("786344").srgb_to_linear()
	for surface in batch.mesh.get_surface_count():
		var arrays := batch.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index in vertices.size():
				indices.append(index)
		var parents: Array[int] = []
		var welded: Dictionary = {}
		for index in vertices.size():
			parents.append(index)
			var point := Vector3i((vertices[index] * 10000.0).round())
			if welded.has(point):
				parents[index] = welded[point]
			else:
				welded[point] = index
		for triangle in range(0, indices.size(), 3):
			var leader := _find_component(parents, indices[triangle])
			for corner in [1, 2]:
				parents[_find_component(parents, indices[triangle + corner])] = leader
		var components: Dictionary = {}
		for triangle in range(0, indices.size(), 3):
			var leader := _find_component(parents, indices[triangle])
			if not components.has(leader):
				components[leader] = {"triangles": [], "bounds": AABB(vertices[indices[triangle]], Vector3.ZERO), "color": colors[indices[triangle]] if not colors.is_empty() else Color.WHITE}
			components[leader].triangles.append(triangle)
			for corner in 3:
				components[leader].bounds = components[leader].bounds.expand(vertices[indices[triangle + corner]])
		var fixed := SurfaceTool.new()
		fixed.begin(Mesh.PRIMITIVE_TRIANGLES)
		var fixed_count := 0
		var builders: Dictionary = {}
		for component: Dictionary in components.values():
			var mast := _nearest_mast(component.bounds.get_center(), masts)
			var color: Color = component.color
			var is_rope := Vector3(color.r, color.g, color.b).distance_to(Vector3(rope.r, rope.g, rope.b)) < 0.015
			var is_rig: bool = is_rope and component.bounds.end.y > mast.rest.origin.y + 1.1 and absf(component.bounds.get_center().z - mast.rest.origin.z) <= 3.1
			var key := String(mast.node.name)
			if is_rig and not builders.has(key):
				var builder := SurfaceTool.new()
				builder.begin(Mesh.PRIMITIVE_TRIANGLES)
				builders[key] = {"tool": builder, "pivot": mast.rest.origin}
			var tool: SurfaceTool = builders[key].tool if is_rig else fixed
			for triangle: int in component.triangles:
				for corner in 3:
					_emit_vertex(tool, arrays, indices[triangle + corner])
				if not is_rig:
					fixed_count += 3
		var material := batch.mesh.surface_get_material(surface)
		if fixed_count > 0:
			fixed.set_material(material)
			fixed.commit(fixed_mesh)
		for key: String in builders:
			if not moving.has(key):
				moving[key] = {"mesh": ArrayMesh.new(), "pivot": builders[key].pivot}
			builders[key].tool.set_material(material)
			builders[key].tool.commit(moving[key].mesh)
	if moving.is_empty():
		return
	batch.mesh = fixed_mesh
	for key: String in moving:
		var rig := MeshInstance3D.new()
		rig.name = "rigging_" + key.trim_prefix("mast_")
		rig.mesh = moving[key].mesh
		model.add_child(rig)
		_rigs.append({"node": rig, "rest": rig.transform, "pivot": moving[key].pivot})

func _emit_vertex(tool: SurfaceTool, arrays: Array, index: int) -> void:
	if arrays[Mesh.ARRAY_NORMAL] != null and not arrays[Mesh.ARRAY_NORMAL].is_empty():
		tool.set_normal(arrays[Mesh.ARRAY_NORMAL][index])
	if arrays[Mesh.ARRAY_COLOR] != null and not arrays[Mesh.ARRAY_COLOR].is_empty():
		tool.set_color(arrays[Mesh.ARRAY_COLOR][index])
	if arrays[Mesh.ARRAY_TEX_UV] != null and not arrays[Mesh.ARRAY_TEX_UV].is_empty():
		tool.set_uv(arrays[Mesh.ARRAY_TEX_UV][index])
	tool.add_vertex(arrays[Mesh.ARRAY_VERTEX][index])

func _damage(ship: Dictionary, field: String, maximum: String) -> float:
	var health := float(ship.get(field, 100.0))
	var capacity := float(ship.get(maximum, 100.0))
	if not is_finite(health) or not is_finite(capacity) or capacity <= 0.0:
		return 0.0
	return clampf((1.0 - health / capacity) * 100.0, 0.0, 100.0)

func ended() -> bool:
	return is_finite(_sink_start) and _time >= _sink_start + SINK_DURATION

func diagnostics() -> Dictionary:
	return {"hull_stage": _hull_stage, "sail_quantized": _sail_quantized, "sail_stage": _sail_stage, "mast_age": maxf(0.0, _time - _mast_start) if is_finite(_mast_start) else -1.0, "sinking_age": maxf(0.0, _time - _sink_start) if is_finite(_sink_start) else -1.0, "ended": ended(), "material_count": _materials.size(), "accepted_time": _time}

func dispose() -> void:
	# Detach mutable damage materials while their RIDs are alive. Imported mesh
	# resources are shared; never overwrite their original surface materials.
	for entry: Dictionary in _materials:
		if is_instance_valid(entry.node) and entry.node.mesh != null:
			if entry.node.mesh.get_surface_count() == 1:
				entry.node.material_override = entry.original
			else:
				entry.node.set_surface_override_material(entry.surface, entry.original)
	_models.clear()
	_materials.clear()
	_textures.clear()
	_masts.clear()
	_rigs.clear()
	_flags.clear()
	_rests.clear()
	_sent.clear()
	_initialized = false
	_mast_start = -INF
	_sink_start = -INF
	_time = 0.0
	_depth = 20.0
	_hull_stage = 0
	_sail_quantized = 0
	_sail_stage = 0
	_mask_stage = -1
