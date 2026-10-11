extends RefCounted
## Bounded optical profile and diagnostic mathematics; never owns a clock/world.

var camera: Camera3D
var enabled := false
var reflection_enabled := true
var refraction_enabled := true
var quality := "balanced"
var visual_style := 1

func apply(material: ShaderMaterial) -> void:
	if material == null: return
	var active := enabled and visual_style == 1 and is_instance_valid(camera) and camera.is_inside_tree()
	var steps := _steps()
	material.set_shader_parameter("surface_optics_enabled", active)
	material.set_shader_parameter("surface_reflection_enabled", active and reflection_enabled and steps > 0)
	material.set_shader_parameter("surface_refraction_enabled", active and refraction_enabled)
	material.set_shader_parameter("surface_reflection_steps", steps)
	material.set_shader_parameter("surface_reflection_strength", 0.34 if quality == "high" else 0.26)
	material.set_shader_parameter("surface_refraction_strength", 0.54 if quality == "high" else 0.42)

func diagnostics() -> Dictionary:
	var valid := is_instance_valid(camera) and camera.is_inside_tree()
	return {"enabled": enabled and visual_style == 1 and valid, "requested": enabled,
		"camera_valid": valid, "quality": quality, "reflection_method": "screen-space",
		"reflection_enabled": enabled and reflection_enabled and _steps() > 0 and valid and visual_style == 1,
		"refraction_enabled": enabled and refraction_enabled and valid and visual_style == 1,
		"reflection_steps": _steps(), "offscreen_targets": 0, "private_worlds": 0,
		"screen_source": "current-viewport-opaque-copy", "depth_source": "current-viewport-inverse-projection",
		"includes_transparent_objects": false, "includes_offscreen_objects": false}

func _steps() -> int:
	return int({"low": 0, "balanced": 16, "high": 24}.get(quality, 16))

static func project_view(projection: Projection, point: Vector3) -> Dictionary:
	if not point.is_finite() or point.z >= -0.000001: return {}
	var clip := projection * Vector4(point.x, point.y, point.z, 1.0)
	if not clip.is_finite() or absf(clip.w) < 0.000001: return {}
	return {"uv": Vector2(clip.x, clip.y) / clip.w * 0.5 + Vector2.ONE * 0.5, "depth": clip.z / clip.w}

static func reconstruct_view(inverse_projection: Projection, uv: Vector2, depth: float, compatibility: bool = false) -> Vector3:
	if not uv.is_finite() or not is_finite(depth): return Vector3.ZERO
	var ndc := Vector4(uv.x * 2.0 - 1.0, uv.y * 2.0 - 1.0, depth * 2.0 - 1.0 if compatibility else depth, 1.0)
	var view := inverse_projection * ndc
	if not view.is_finite() or absf(view.w) < 0.000001: return Vector3.ZERO
	return Vector3(view.x, view.y, view.z) / view.w

static func transmittance(thickness: float) -> Vector3:
	var distance := clampf(thickness, 0.0, 80.0) if is_finite(thickness) else 80.0
	return Vector3(exp(-0.16 * distance), exp(-0.065 * distance), exp(-0.028 * distance))

static func reflection_direction(view_position: Vector3, normal_in_view: Vector3) -> Vector3:
	if not view_position.is_finite() or not normal_in_view.is_finite() or view_position.length_squared() < 0.000001 or normal_in_view.length_squared() < 0.000001:
		return Vector3.ZERO
	return view_position.normalized().bounce(normal_in_view.normalized())

static func reflection_probe(projection: Projection, view_position: Vector3, normal_in_view: Vector3, distance: float) -> Dictionary:
	if not is_finite(distance) or distance <= 0.0: return {}
	var direction := reflection_direction(view_position, normal_in_view)
	if direction == Vector3.ZERO: return {}
	return project_view(projection, view_position + direction * distance)

static func trace_reflection(projection: Projection, origin: Vector3, normal: Vector3, steps: int, depth_at: Callable, inverse_view: Transform3D) -> Dictionary:
	# Diagnostic oracle for GPU acceptance: same ray/depth contract, no scene mutation.
	var result := {"hit": false, "queries": 0, "distance": 0.0, "uv": Vector2.ZERO, "scene_position": Vector3.ZERO}
	if not depth_at.is_valid(): return result
	var ray := reflection_direction(origin, normal)
	if ray == Vector3.ZERO: return result
	var inverse_projection := projection.inverse()
	var water_y := (inverse_view * origin).y
	var distance := 0.45
	var stride := 0.55
	for _index in clampi(steps, 0, 24):
		var position_view := origin + normal.normalized() * 0.075 + ray * distance
		var projected := project_view(projection, position_view)
		if projected.is_empty(): break
		var uv: Vector2 = projected.uv
		if uv.x < 0.002 or uv.y < 0.002 or uv.x > 0.998 or uv.y > 0.998: break
		result.queries += 1
		var raw_depth := float(depth_at.call(uv))
		if is_finite(raw_depth):
			var scene_view := reconstruct_view(inverse_projection, uv, raw_depth)
			var difference := -position_view.z + scene_view.z
			var scene_world := inverse_view * scene_view
			if difference >= 0.0 and difference < 1.3 + distance * 0.012 and scene_world.y > maxf(0.04, water_y + 0.03):
				result.hit = true
				result.distance = distance
				result.uv = uv
				result.scene_position = scene_world
				return result
		distance += stride
		stride *= 1.22
	return result
