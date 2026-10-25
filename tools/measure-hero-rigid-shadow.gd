extends SceneTree
## Headless CPU microbenchmark only. No GPU work, gameplay, or FPS inference.
const Hero = preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Adapter = preload("res://game/presentation/world/target_rigid_shadow_caster.gd")
const ROLE_NAMES := ["hull", "deck", "mast_timber_0", "mast_timber_1", "mast_timber_2"]
const SOURCE_PATHS := ["res://tools/measure-hero-rigid-shadow.gd", "res://tools/blender/build_hero_fuchuan_v3.py", "res://modules/scene_engine/assets/hero_ship_provider.gd", "res://game/presentation/world/target_rigid_shadow_caster.gd", "res://game/presentation/world/target_shadow_boundary.gd", "res://modules/scene_engine/fidelity_fx/prepared_rigid_shadow.gd", "res://assets/models/hero_fuchuan_v3/fuchuan-lod0.glb"]
const WARMUP := 8
const SAMPLES := 40
const ROTATION_STEP := 0.001
var _output := ""
var _proxy := "visible"
var _model: Node3D
var _roles: Array[MeshInstance3D] = []
var _fixture_geometry: Array = []
var _errors: Array[String] = []

class ShipStub:
	extends RefCounted
	var model: Node3D
	func _init(value: Node3D) -> void: model = value
	func get_model() -> Node3D: return model

func _initialize() -> void: _run.call_deferred()

func _hashes() -> Dictionary:
	var result := {}
	for path: String in SOURCE_PATHS: result[path] = FileAccess.get_sha256(path)
	return result

func _stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"n": 0}
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0
	for value in sorted: total += float(value)
	return {"n": sorted.size(), "unit": "microseconds", "min": sorted[0], "max": sorted[-1], "mean": total / sorted.size(), "p50": sorted[int(ceil(0.50 * sorted.size())) - 1], "p95": sorted[int(ceil(0.95 * sorted.size())) - 1], "quantile": "nearest-rank ceil(q*n)-1"}

func _mesh_counts(mesh: Mesh) -> Dictionary:
	var vertices := 0; var triangles := 0
	for surface in mesh.get_surface_count():
		if mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES: continue
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		vertices += points.size()
		triangles += (indices.size() if not indices.is_empty() else points.size()) / 3
	return {"renderVerticesBeforeExactWeld": vertices, "trianglesBeforeDegenerateFilter": triangles}

func _configure_fixture() -> bool:
	_model = Hero.new("art", _proxy == "authored").instantiate_ship("fuchuan", 0)
	if _model == null: _errors.append("art v3 LOD0 failed to instantiate"); return false
	root.add_child(_model)
	_model.transform = Transform3D.IDENTITY
	# Isolate these five full-mesh roles even when production gains other casters.
	for node in _model.find_children("*", "MeshInstance3D", true, false): node.set_meta("target_rigid_shadow_caster", false)
	for role: String in ROLE_NAMES:
		var mesh := _model.find_child(role, true, false) as MeshInstance3D
		if mesh == null or mesh.mesh == null: _errors.append("missing fullMesh role " + role); continue
		var visible_geometry := mesh.mesh
		var selected: Mesh = visible_geometry
		if _proxy == "authored":
			var authored: Variant = mesh.get_meta("target_shadow_geometry") if mesh.has_meta("target_shadow_geometry") else null
			if not authored is Mesh: _errors.append(role + " missing target_shadow_geometry:Mesh"); continue
			selected = authored
		# Select only fixture-local CPU geometry; never rewrite an asset/resource.
		# Both legacy and metadata-aware adapters now see the requested same Mesh.
		mesh.mesh = selected
		if _proxy == "visible": mesh.remove_meta("target_shadow_geometry")
		else: mesh.set_meta("target_shadow_geometry", selected)
		mesh.visible = true
		mesh.set_meta("target_rigid_shadow_caster", true)
		_roles.append(mesh)
		_fixture_geometry.append({"role": role, "visibleMesh": _mesh_counts(visible_geometry), "selectedShadowMesh": _mesh_counts(selected), "mode": _proxy})
	return _errors.is_empty() and _roles.size() == ROLE_NAMES.size()

func _observe(packet: Dictionary, adapter: RefCounted) -> Dictionary:
	var rows: Array = []; var errors: Array = adapter.diagnostics().get("errors", []).duplicate()
	var started := Time.get_ticks_usec()
	for caster: Dictionary in packet.native.sourceShadows.casters:
		var prepared: RefCounted = caster.preparedRigid
		var volume: Dictionary = prepared.build_volume(caster.localLight)
		var diagnostic: Dictionary = prepared.diagnostics()
		var row := {"id": caster.id, "sourceTriangles": diagnostic.faces, "sourcePoints": diagnostic.sourceVertices, "selectedCapTriangles": caster.capIndices.size() / 3, "parityEdges": caster.edges.size(), "dirty": caster.dirty, "localLight": caster.localLight, "prepared": diagnostic}
		if volume.has("error"):
			row.error = volume.error; errors.append(str(caster.id) + ": " + str(volume.error))
		else:
			row.volumeVertices = volume.vertexCount; row.volumeTriangles = volume.triangleCount
		rows.append(row)
	if rows.size() != ROLE_NAMES.size(): errors.append("expected five caster roles; emitted " + str(rows.size()))
	var volume_usec := Time.get_ticks_usec() - started
	return {"casters": rows, "adapterErrors": errors, "volumeBuildAndInspectionUsec": volume_usec, "adapter": adapter.diagnostics()}

func _one(adapter: RefCounted, ships: Dictionary, light: Vector3, index: int) -> Dictionary:
	var started := Time.get_ticks_usec()
	var packet: Dictionary = adapter.compose({}, ships, light, false, true)
	var elapsed := Time.get_ticks_usec() - started
	var result := _observe(packet, adapter)
	result.sample = index; result.composeUsec = elapsed; result.worldLight = [light.x, light.y, light.z]
	return result

func _group(rotating: bool, ships: Dictionary) -> Dictionary:
	var adapter := Adapter.new()
	# Same declared world direction as -sun in the original native source-light setup.
	# Ship identity pose is controlled here, not claimed to replay a native snapshot.
	var base := Vector3(0.5, -0.8, -0.3).normalized()
	var cold := _one(adapter, ships, base, -1)
	var warmups: Array = []
	for index in WARMUP:
		var angle := (index + 1) * ROTATION_STEP if rotating else 0.0
		warmups.append(_one(adapter, ships, Basis(Vector3.UP, angle) * base, -index - 2))
	var samples: Array = []; var times: Array = []; var volume_times: Array = []
	for index in SAMPLES:
		var angle := (WARMUP + index + 1) * ROTATION_STEP if rotating else 0.0
		var sample := _one(adapter, ships, Basis(Vector3.UP, angle) * base, index)
		samples.append(sample); times.append(sample.composeUsec); volume_times.append(sample.volumeBuildAndInspectionUsec)
	var result := {"name": "slow_rotating_light" if rotating else "identical_stationary_light", "warmupCount": WARMUP, "sampleCount": SAMPLES, "rotationStepRadians": ROTATION_STEP if rotating else 0.0, "cold": cold, "warmupRaw": warmups, "raw": samples, "composeUsec": _stats(times), "volumeBuildAndInspectionUsec": _stats(volume_times), "finalAdapter": adapter.diagnostics()}
	adapter.dispose()
	return result

func _write(result: Dictionary) -> bool:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	if error != OK: printerr("Cannot create output directory: ", error); return false
	var file := FileAccess.open(_output.path_join("measurement.json"), FileAccess.WRITE)
	if file == null: printerr("Cannot write measurement.json"); return false
	file.store_string(JSON.stringify(result, "\t")); file.close()
	return true

func _run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="): _output = argument.trim_prefix("--output=")
		elif argument.begins_with("--proxy="): _proxy = argument.trim_prefix("--proxy=")
	if _output.is_empty() or _proxy not in ["visible", "authored"]:
		printerr("Required: --output=res://new-directory --proxy=visible|authored"); quit(2); return
	if DisplayServer.get_name() != "headless":
		printerr("CPU-only benchmark requires --headless"); quit(2); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(_output)):
		printerr("Output already exists; choose a new directory: ", _output); quit(2); return
	var sources := _hashes()
	var result := {"schemaVersion": 1, "scope": "headless CPU rigid-shadow compose microbenchmark; not GPU time, native gameplay, or game FPS", "proxy": _proxy, "engine": Engine.get_version_info(), "processor": OS.get_processor_name(), "displayServer": DisplayServer.get_name(), "sourceSha256Before": sources, "controls": {"lod": 0, "shipCount": 1, "shipPose": "identity", "roles": ROLE_NAMES, "warmupPerGroup": WARMUP, "samplesPerGroup": SAMPLES, "slowRotationStepRadians": ROTATION_STEP, "stencilActive": false, "timingBoundary": "TargetRigidShadowCaster.compose only; volume build plus inspection is separate"}, "groups": []}
	if _configure_fixture():
		var ships := {"hero-cpu": ShipStub.new(_model)}
		result.groups.append(_group(false, ships))
		result.groups.append(_group(true, ships))
		for group: Dictionary in result.groups:
			for sample: Dictionary in group.raw:
				if not sample.adapterErrors.is_empty():
					_errors.append(group.name + " sample " + str(sample.sample) + ": " + str(sample.adapterErrors))
	result.fixtureGeometry = _fixture_geometry
	result.sourceSha256After = _hashes()
	result.sourcesChangedDuringMeasurement = sources != result.sourceSha256After
	if result.sourcesChangedDuringMeasurement: _errors.append("source files changed during measurement; timing inputs are not frozen")
	result.errors = _errors
	result.status = "completed" if _errors.is_empty() else "failed_or_completed_with_caster_errors"
	if _model != null: _model.free()
	var written := _write(result)
	for group: Dictionary in result.groups: print("HERO_RIGID_SHADOW_CPU ", group.name, " compose_usec=", JSON.stringify(group.composeUsec))
	print("HERO_RIGID_SHADOW_CPU_MEASURE status=", result.status, " mode=", _proxy, " errors=", _errors.size(), " output=", _output)
	quit(0 if written and _errors.is_empty() else 1)
