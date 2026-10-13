extends SceneTree
## Actual native source frames against the complete pre-reuse renderer.
## Catches per-frame ArrayMesh allocation without changing sprites/sort/quality.
const SourceFx = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const AGES := [0.0,0.02,0.06,0.1,0.2,0.35,0.4]
const CASES := [{"source":"fx_cannon_fire_01.nif","capacity":435,"systems":11},{"source":"cannon_ball_splash_01.nif","capacity":82,"systems":8},{"source":"cannon_ball_splash_02.nif","capacity":85,"systems":8},{"source":"cannon_ball_splash_03.nif","capacity":79,"systems":8}]

class LegacyRender:
	extends "res://modules/scene_engine/fidelity_fx/presentation.gd"
	# Complete _render copied before the production resource-reuse change.
	# Normalized-LF method SHA256:
	# 68db4b2380eeeec68e99a6f47286f688a66b7b5f72fb105111f542e6e2a3a185
	func _render(meshes: Array) -> void:
		_rendered = 0; _triangles = 0
		_game_flash = 0; _draw_order.clear()
		for key in _geometry: _geometry[key].visible = false
		var ordered: Array = []
		var records := meshes.duplicate()
		if not _expired and _render_profile == "game_cannon": records.append_array(_game_flash_meshes())
		var camera_origin := _camera.global_position if is_instance_valid(_camera) else Vector3.ZERO
		var camera_forward := -_camera.global_basis.z if is_instance_valid(_camera) else Vector3.FORWARD
		for record: Dictionary in records:
			var points: Array = []
			var center := Vector3.ZERO
			var surface_ring: bool = _source.begins_with("cannon_ball") and record.get("kind","") == "authored mesh" and not String(record.get("name","")).begins_with("Cylinder")
			for value: Array in record.vertices:
				var point := _origin+_orientation*native_to_godot(value)*(METRES_PER_UNIT*_size)
				if surface_ring and _water.is_valid():
					var height := float(_water.call(point.x,point.z,_absolute_time))
					if is_finite(height): point.y = height+0.06
				points.append(point); center += point
			if points.is_empty(): continue
			center /= points.size()
			ordered.append({"record":record,"points":points,"center":center,"depth":(center-camera_origin).dot(camera_forward)})
		ordered.sort_custom(func(a,b): return a.depth > b.depth)
		for draw: Dictionary in ordered:
			var record: Dictionary = draw.record
			var material := _material(record)
			if material == null: continue
			var vertices := PackedVector3Array(); var uv := PackedVector2Array()
			var colors := PackedColorArray(); var indices := PackedInt32Array()
			var rgb: Array = record.get("color",[1.0,1.0,1.0])
			var alpha := float(record.get("alpha",1.0))
			var color := Color(float(rgb[0]),float(rgb[1]),float(rgb[2]),alpha)
			var points: Array = draw.points
			for index in points.size():
				vertices.append(points[index]-draw.center)
				uv.append(Vector2(float(record.uvs[index][0]),float(record.uvs[index][1])))
				colors.append(color)
			for triangle: Array in record.triangles:
				var wet := true
				if _source.begins_with("cannon_ball") and _sea.is_valid():
					for index in triangle:
						var point: Vector3 = points[int(index)]
						if not bool(_sea.call(point.x,point.z)): wet = false
				if not wet: continue
				indices.append_array(PackedInt32Array([int(triangle[0]),int(triangle[1]),int(triangle[2])]))
				_triangles += 1
			if indices.is_empty(): continue
			var role := String(record.get("display_role","native"))
			if role == "game_flash": _game_flash += 1
			else: _rendered += 1
			var key := str(_draw_order.size())
			if not _geometry.has(key):
				var node := MeshInstance3D.new(); node.name = "SourceDraw_"+str(_geometry.size())
				node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				add_child(node); _geometry[key] = node
			var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uv
			arrays[Mesh.ARRAY_COLOR]=colors; arrays[Mesh.ARRAY_INDEX]=indices
			var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
			_geometry[key].position = draw.center
			_geometry[key].mesh = mesh; _geometry[key].material_override = material; _geometry[key].visible = true
			_geometry[key].set_meta("display_role",role)
			_draw_order.append({"name":record.get("name",""),"texture":record.texture,"depth":draw.depth,"display_role":role})

var assertions := 0
var failures := 0
var _failure_kinds: Dictionary = {}
var _camera: Camera3D
var _waves: RefCounted
var _filter_mode := 0
var _stable_carriers := 0
var _topology_changes := 0

func check(ok: bool,detail: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		_failure_kinds[detail] = int(_failure_kinds.get(detail,0))+1
		if int(_failure_kinds[detail]) == 1: printerr("FAIL FX mesh reuse: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _height(_x: float,_z: float) -> float: return -80.0
func _sea(x: float,_z: float) -> bool:
	if _filter_mode == 0: return true
	return x < 8.0 if _filter_mode == 1 else false
func _state(effect: Node3D) -> PackedByteArray:
	var replay: RefCounted = effect.get("_replay")
	return var_to_bytes(replay.call("source_state"))

func _material_payload(material: ShaderMaterial) -> Dictionary:
	var parameters: Dictionary = {}
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		var name: String = uniform.name
		var value: Variant = material.get_shader_parameter(name)
		if value is Resource: value = {"class":value.get_class(),"path":value.resource_path,"id":value.get_instance_id()}
		parameters[name] = value
	return {"shader":material.shader.code,"shader_path":material.shader.resource_path,"parameters":parameters,"priority":material.render_priority}

func _effective_aabb(node: MeshInstance3D,mesh: ArrayMesh) -> AABB:
	# Dynamic region updates do not refresh Resource.get_aabb(). Either public
	# custom bounds owner may supply the actual rendering/culling bounds.
	if node.custom_aabb.size != Vector3.ZERO: return node.custom_aabb
	if mesh.custom_aabb.size != Vector3.ZERO: return mesh.custom_aabb
	return mesh.get_aabb()

func _capture(effect: Node3D) -> Dictionary:
	var result: Dictionary = {}
	var geometry: Dictionary = effect.get("_geometry")
	for key: Variant in geometry:
		var node: MeshInstance3D = geometry[key]
		var mesh: ArrayMesh = node.mesh
		var arrays: Array = []
		for index in mesh.get_surface_count(): arrays.append(mesh.surface_get_arrays(index))
		var layout: Array = []
		for surface: Array in arrays:
			layout.append([surface[Mesh.ARRAY_VERTEX].size(),surface[Mesh.ARRAY_TEX_UV].size(),surface[Mesh.ARRAY_COLOR].size(),var_to_bytes(surface[Mesh.ARRAY_INDEX])])
		result[key] = {"node_id":node.get_instance_id(),"mesh_id":mesh.get_instance_id(),"rid":mesh.get_rid(),"layout":layout,
			"payload":{"position":node.position,"global_transform":node.global_transform,"visible":node.visible,"cast_shadow":node.cast_shadow,"role":node.get_meta("display_role",""),"arrays":arrays,"aabb":_effective_aabb(node,mesh),"material":_material_payload(node.material_override)}}
	return result

func _compare(actual: Node3D,legacy: Node3D,label: String,previous: Dictionary = {},require_reuse: bool = true) -> Dictionary:
	var a := _capture(actual)
	var b := _capture(legacy)
	check(_state(actual) == _state(legacy),"all original capacity slots/RNG/world/bounds remain byte-identical: "+label)
	check(a.keys() == b.keys(),"one original spatial carrier per source draw is preserved: "+label)
	check(var_to_bytes(actual.get("_draw_order")) == var_to_bytes(legacy.get("_draw_order")),"transparent far-to-near source order is unchanged: "+label)
	var d: Dictionary = actual.call("diagnostics")
	var r: Dictionary = legacy.call("diagnostics")
	check([d.rendered_meshes,d.rendered_triangles,d.game_flash,d.owned_nodes,d.render_error] == [r.rendered_meshes,r.rendered_triangles,r.game_flash,r.owned_nodes,r.render_error],"all visible source sprites/triangles/profile counts remain unchanged: "+label)
	for key: Variant in a:
		if not b.has(key): continue
		check(var_to_bytes(a[key].payload) == var_to_bytes(b[key].payload),"every spatial position/material/visibility/surface-array/AABB matches frozen renderer: "+label)
		if not previous.has(key): continue
		var old: Dictionary = previous[key]
		var current: Dictionary = a[key]
		if not old.payload.visible or not current.payload.visible: continue
		if old.layout == current.layout:
			if require_reuse:
				_stable_carriers += 1
				check(current.node_id == old.node_id and current.mesh_id == old.mesh_id and current.rid == old.rid,"stable-layout/index carrier retains its mesh instance and RID: "+label)
		else: _topology_changes += 1 # Rebuild is legal; complete legacy payload still required.
	return a

func _weak_owners(effect: Node3D) -> Array:
	var refs: Array = []
	for node: MeshInstance3D in effect.get("_geometry").values():
		refs.append(weakref(node)); refs.append(weakref(node.mesh))
	return refs

func _case(fixture: Dictionary) -> void:
	_filter_mode = 0
	_camera.position = Vector3(31,25,43); _camera.look_at(Vector3(8,2,-12),Vector3.UP)
	var actual := SourceFx.new(); var legacy := LegacyRender.new()
	root.add_child(actual); root.add_child(legacy)
	var options := {"origin":Vector3(8,2,-12),"direction":Vector3(.2,0,-1),"seed":1,"scale":1.0,"camera":_camera,"water":_waves.sample_height,"sea":_sea,"clock_mode":"native","render_profile":"game_cannon" if String(fixture.source).begins_with("fx_cannon") else "native"}
	if not check(actual.configure(fixture.source,options) and legacy.configure(fixture.source,options),"both actual native-clock presentations configure full source "+String(fixture.source)):
		actual.free(); legacy.free(); return
	var previous: Dictionary = {}
	for age: float in AGES:
		var label := String(fixture.source)+"/age"+str(age)
		check(actual.apply_snapshot(age,10.0+age) and legacy.apply_snapshot(age,10.0+age),"both original source frames draw: "+label)
		var d: Dictionary = actual.diagnostics()
		var capacity := 0
		for layer: Dictionary in d.layers: capacity += int(layer.capacity)
		check(capacity == int(fixture.capacity) and int(d.systems) == int(fixture.systems),"all authored system/capacity budgets retained: "+label)
		previous = _compare(actual,legacy,label,previous)
		var native_before := _state(actual)
		_camera.position.x += 1.5; _camera.look_at(Vector3(8,2,-12),Vector3.UP)
		check(actual.apply_snapshot(age,10.0+age) and legacy.apply_snapshot(age,10.0+age),"camera-only redraw accepts the same particle age: "+label)
		previous = _compare(actual,legacy,label+"/camera",previous)
		check(_state(actual) == native_before,"camera redraw changes neither complete source state nor native bounds counter: "+label)
	if String(fixture.source).begins_with("cannon_ball"):
		var before_filter := _state(actual)
		_filter_mode = 1; actual.configure_surface_filter(_sea); legacy.configure_surface_filter(_sea)
		check(actual.apply_snapshot(.4,10.4) and legacy.apply_snapshot(.4,10.4),"changed sea filter recomputes actual authored triangle visibility")
		previous = _compare(actual,legacy,String(fixture.source)+"/partial-filter",previous,false)
		_filter_mode = 2; actual.configure_surface_filter(_sea); legacy.configure_surface_filter(_sea)
		check(actual.apply_snapshot(.4,10.4) and legacy.apply_snapshot(.4,10.4),"dry filter accepts the retained original source frame")
		previous = _compare(actual,legacy,String(fixture.source)+"/dry-filter",previous,false)
		check(actual.diagnostics().rendered_meshes == 0,"dry source renders no stale triangles or billboard carriers")
		_filter_mode = 0; actual.configure_surface_filter(_sea); legacy.configure_surface_filter(_sea)
		check(actual.apply_snapshot(.4,11.4) and legacy.apply_snapshot(.4,11.4),"restored filter reprojects the original authored water meshes at a new absolute wave phase")
		previous = _compare(actual,legacy,String(fixture.source)+"/restored-water",previous,false)
		check(_state(actual) == before_filter,"filter/index and absolute-water changes cannot advance any original particle byte")
	var owners: Array = _weak_owners(actual)
	check(not owners.is_empty(),"fixture actually owns native mesh resources before cleanup")
	var accepted := _state(actual)
	check(not actual.apply_snapshot(NAN,10.4) and _state(actual) == accepted,"invalid display input leaves resource-backed source state intact")
	actual.dispose(); legacy.dispose()
	check(actual.get_child_count() == 0 and actual.get("_geometry").is_empty(),"dispose releases every owned source carrier")
	for retained: WeakRef in owners: check(retained.get_ref() == null,"dispose releases native mesh resources including any reuse cache")
	options.origin = Vector3(18,3,-12)
	check(actual.configure(fixture.source,options) and legacy.configure(fixture.source,options),"disposed source configures a fresh origin and resource lifecycle")
	check(actual.apply_snapshot(.02,20.02) and legacy.apply_snapshot(.02,20.02),"reconfigured source draws without stale resource memo")
	_compare(actual,legacy,String(fixture.source)+"/fresh-lifecycle")
	var duration: float = actual.get_playback_duration()
	check(not actual.apply_snapshot(duration+.01,20.0+duration+.01) and not legacy.apply_snapshot(duration+.01,20.0+duration+.01),"explicit source clip retires visibility at its finite endpoint")
	_compare(actual,legacy,String(fixture.source)+"/expired")
	check(actual.get("_geometry").values().all(func(node: MeshInstance3D): return not node.visible),"expired replay cannot leave a stale last mesh visible")
	actual.dispose(); legacy.dispose(); actual.free(); legacy.free()

func _run() -> void:
	_waves = Waves.new()
	if not check(_waves.configure(_height),"actual CoastalWaveField configures with its original descriptors"):
		print("FIDELITY_FX_MESH_REUSE_TESTS assertions=",assertions," failures=",failures); quit(1); return
	_camera = Camera3D.new(); root.add_child(_camera)
	for fixture: Dictionary in CASES: _case(fixture)
	check(_stable_carriers > 0,"real changing source frames exercise stable-layout/index mesh reuse")
	check(_topology_changes > 0,"real sea filtering exercises changed authored triangle topology")
	_camera.free()
	print("FIDELITY_FX_MESH_REUSE_SCOPE stable_carriers=",_stable_carriers," topology_changes=",_topology_changes," legacy_render_sha256=68db4b2380eeeec68e99a6f47286f688a66b7b5f72fb105111f542e6e2a3a185")
	print("FIDELITY_FX_MESH_REUSE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
