extends SceneTree
## Run from an empty directory, with --main-pack and this external script.
## Example: Godot --headless --main-pack <absolute.pck> --script <absolute.gd>
##          -- --pack=<absolute.pck> --proof=<absolute.json>

var failures: Array[String] = []
var assertions := 0
var resources: Array = []
var models: Array = []
var simulation: Dictionary = {}
var entrypoint: Dictionary = {"readyExecuted": false}
var pack_path := ""
var proof_path := ""
var working_directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pack="): pack_path = argument.trim_prefix("--pack=")
		if argument.begins_with("--proof="): proof_path = argument.trim_prefix("--proof=")
	var working_dir_access = DirAccess.open(".")
	if working_dir_access != null: working_directory = working_dir_access.get_current_dir()
	check(not pack_path.is_empty() and FileAccess.file_exists(pack_path), "explicit PCK exists")
	check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "resource root contains exported binary project settings, not loose source settings")
	check(not working_directory.is_empty() and not FileAccess.file_exists(working_directory.path_join("project.godot")), "working directory has no loose Godot project")
	check(ProjectSettings.get_setting("application/config/name", "") == "MingArmada", "project settings loaded from PCK")
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene", "")
	check(not main_scene.is_empty() and ResourceLoader.exists(main_scene), "configured main scene is present as a native resource")
	var geography = read_json("res://game/data/mingqi_geography.json")
	check(geography is Array and geography.size() == 3, "runtime geography has three native ports")
	var vegetation = read_json("res://assets/reference/vegetation-geometry.json")
	check(vegetation is Dictionary and vegetation.get("geometry", {}).has("palm"), "runtime vegetation geometry has authored palm mesh")
	var catalog = read_json("res://game/domain/mingqi/catalog.json")
	check(catalog is Dictionary and catalog.get("ports", {}).has("xiamen"), "source campaign catalog JSON readable")
	var collation = read_json("res://modules/naval_simulation/id-collation.json")
	check(collation is Dictionary and not collation.get("weights", {}).is_empty(), "runtime collation weights readable")
	read_json("res://assets/models/ships/ships-manifest.json")
	read_json("res://assets/models/sailors/sailors-manifest.json")
	for excluded in ["res://docs", "res://tests", "res://tools", "res://assets/provenance", "res://.superpowers"]:
		check(not DirAccess.dir_exists_absolute(excluded), "excluded directory absent: " + excluded)
	for excluded in ["res://tests/fixtures/naval-reference.json", "res://tests/fixtures/legacy-reference.json", "res://docs/migration/progress.md", "res://tools/migration/verify_pack.gd"]:
		check(not FileAccess.file_exists(excluded) and not ResourceLoader.exists(excluded), "excluded file absent: " + excluded)
	probe_collation()
	probe_models()
	probe_encounter()
	await probe_entrypoint(main_scene)
	var result = {
		"status": "PASS" if failures.is_empty() else "FAIL",
		"assertions": assertions, "failures": failures,
		"engine": Engine.get_version_info().string,
		"generatedAtUtc": Time.get_datetime_string_from_system(true),
		"workingDirectory": working_directory,
		"resourceRoot": ProjectSettings.globalize_path("res://"),
		"engineArguments": OS.get_cmdline_args(),
		"packPath": pack_path,
		"packSha256": FileAccess.get_sha256(pack_path) if FileAccess.file_exists(pack_path) else "",
		"entrypoint": entrypoint,
		"resources": resources, "models": models, "simulation": simulation,
		"scope": "Native PCK resource reads, imported-model instantiation, one deterministic naval tick and configured default-scene initialization over eight process frames. Full PASS also requires engine log without SCRIPT ERROR/ERROR. Not a Windows EXE launch or GPU/performance acceptance."
	}
	if not proof_path.is_empty():
		var output = FileAccess.open(proof_path, FileAccess.WRITE)
		check(output != null, "proof file can be written")
		result.assertions = assertions
		result.failures = failures.duplicate()
		result.status = "PASS" if failures.is_empty() else "FAIL"
		if output != null:
			output.store_string(JSON.stringify(result, "\t"))
			output.close()
	print("PACK_RESOURCE_PROBE_%s assertions=%d resources=%d models=%d failures=%d" % [result.status, assertions, resources.size(), models.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func read_json(path: String) -> Variant:
	check(FileAccess.file_exists(path), "PCK JSON file exists: " + path)
	if not FileAccess.file_exists(path): return null
	var raw = FileAccess.get_file_as_string(path)
	var parser = JSON.new()
	var error = parser.parse(raw)
	check(error == OK, "PCK JSON parses: " + path)
	resources.append({"path": path, "byteLength": raw.to_utf8_buffer().size(), "sha256": raw.sha256_text(), "parseError": error})
	return parser.data if error == OK else null

func probe_collation() -> void:
	var script = load("res://modules/naval_simulation/id_collator.gd")
	check(script is GDScript and script.can_instantiate(), "PCK collation script loads with remapping")
	if not script is GDScript or not script.can_instantiate(): return
	var collator = script.new()
	check(collator.supports("player") and collator.compare("enemy-1", "enemy-2") < 0, "PCK-backed collator executes actual weights")

func probe_models() -> void:
	var library_script = load("res://modules/scene_engine/assets/asset_library.gd")
	check(library_script is GDScript and library_script.can_instantiate(), "PCK AssetLibrary script loads")
	if not library_script is GDScript or not library_script.can_instantiate(): return
	var library = library_script.new()
	for kind in ["fuchuan", "voc", "merchant", "fisherman", "patrol", "heavy", "sailor"]:
		for lod in 3:
			var group = "sailors" if kind == "sailor" else "ships"
			var path = "res://assets/models/%s/%s-lod%d.glb" % [group, kind, lod]
			var raw_present = FileAccess.file_exists(path)
			check(ResourceLoader.exists(path), "imported GLB resource exists: " + path)
			var instance = library.instantiate_model(path)
			check(instance is Node3D, "AssetLibrary instantiates PCK model: " + path)
			models.append({"path": path, "rawGlbPresent": raw_present, "nativeResourcePresent": ResourceLoader.exists(path), "instantiated": instance is Node3D})
			if instance != null: instance.free()
	library.dispose()

func probe_encounter() -> void:
	var script = load("res://modules/naval_simulation/encounter.gd")
	check(script is GDScript and script.can_instantiate(), "PCK NavalEncounter script and dependencies load")
	if not script is GDScript or not script.can_instantiate(): return
	var encounter = script.new({
		"playerId": "pack-player", "seed": 1661, "oceanWaves": [],
		"ships": [{"id": "pack-player", "kind": "fuchuan", "team": "player", "position": {"x": 0.0, "z": 0.0}, "sailDeployment": 0.0}]
	})
	check(encounter.last_error.is_empty(), "PCK NavalEncounter configures real native physics")
	check(encounter.command({"type": "controls", "rudder": 0.25, "sailDeployment": 0.5}).get("ok", false), "PCK native helm command accepted")
	encounter.step(1.0 / 60.0)
	var snapshot: Dictionary = encounter.snapshot()
	check(snapshot.tick == 1 and absf(snapshot.time - 1.0 / 60.0) < 1e-12, "PCK native simulator consumes exactly one source tick")
	check(snapshot.ships.size() == 1 and is_finite(snapshot.ships[0].visual.position.x) and is_finite(snapshot.ships[0].visual.position.y) and is_finite(snapshot.ships[0].visual.position.z), "PCK native physics pose finite")
	simulation = {"tick": snapshot.tick, "time": snapshot.time, "shipId": snapshot.ships[0].id, "pose": snapshot.ships[0].visual, "lastError": encounter.last_error}

func probe_entrypoint(path: String) -> void:
	entrypoint = {"mainScene": path, "readyExecuted": false, "processFrames": 0, "excludedTerrainFixturePresent": FileAccess.file_exists("res://tests/fixtures/water-probe-terrain.json")}
	var packed = load(path)
	check(packed is PackedScene, "configured PCK main scene loads as PackedScene")
	if not packed is PackedScene: return
	var scene = packed.instantiate()
	check(scene is Node3D, "configured PCK main scene instantiates native Node3D")
	if not scene is Node3D:
		if scene != null: scene.free()
		return
	root.add_child(scene)
	for frame in 8:
		await process_frame
		entrypoint.processFrames += 1
	check(is_instance_valid(scene) and scene.is_inside_tree() and scene.is_node_ready(), "configured scene completed ready and remains mounted after eight frames")
	if not is_instance_valid(scene): return
	var runtime = scene.get("runtime")
	var world = scene.get("world")
	var ship = scene.get("ship")
	var crew = scene.get("crew")
	var camera = scene.get("camera")
	check(runtime is RefCounted and runtime.has_method("snapshot") and runtime.get("_configured") == true, "default scene has configured sailing physics runtime")
	check(world is Node3D and world.is_inside_tree() and world.has_method("get_ocean") and world.get_chunk_count() > 0, "default scene built real world and terrain chunks")
	check(ship is Node3D and ship.is_inside_tree() and ship.has_method("get_model") and is_instance_valid(ship.get_model()), "default scene built original flagship model")
	check(crew is Node3D and crew.is_inside_tree() and crew.has_method("diagnostics") and crew.get_visible_count() > 0 and crew.get_visible_count() <= 24, "default scene built actual deck sailors")
	check(camera is Camera3D and camera.is_inside_tree() and camera.current, "default scene has mounted current camera")
	entrypoint.readyExecuted = scene.is_node_ready()
	if runtime is RefCounted and runtime.has_method("snapshot"):
		var snapshot: Dictionary = runtime.snapshot()
		var state: Dictionary = snapshot.get("ship", {})
		var position: Dictionary = state.get("position", {})
		check(not position.is_empty() and [position.get("x"), position.get("y"), position.get("z"), state.get("heading"), state.get("heel"), state.get("pitch")].all(_finite_number), "default runtime yields finite flagship pose")
		entrypoint.runtime = {"configured": runtime.get("_configured"), "acceptedTime": snapshot.get("time"), "pose": state}
	if ship is Node3D:
		check(ship.global_position.is_finite() and ship.global_transform.basis.is_finite(), "default rendered flagship transform finite")
		entrypoint.ship = {"position": {"x": ship.global_position.x, "y": ship.global_position.y, "z": ship.global_position.z}, "modelPresent": is_instance_valid(ship.get_model())}
	if crew is Node3D and crew.has_method("diagnostics"):
		entrypoint.crew = crew.diagnostics()
		check(is_instance_valid(crew.get_impact_pool()), "default deck sailors have native impact pool")
	if world is Node3D and world.has_method("get_ocean"):
		var ocean = world.get_ocean()
		check(ocean is MeshInstance3D and ocean.is_inside_tree() and ocean.mesh != null and ocean.material_override is ShaderMaterial, "default scene has configured projected ocean mesh and shader")
		entrypoint.world = {"terrainChunks": world.get_chunk_count(), "oceanPresent": ocean is MeshInstance3D}
		if ocean is MeshInstance3D and ocean.material_override is ShaderMaterial:
			var material: ShaderMaterial = ocean.material_override
			var normal_texture = material.get_shader_parameter("normal_texture")
			var shore_texture = material.get_shader_parameter("shore_height_texture")
			var coast_texture = material.get_shader_parameter("coast_distance_texture")
			var has_shore = material.get_shader_parameter("has_shore_field") == true
			var has_coast = material.get_shader_parameter("has_coast_distance") == true
			var spray = world.get("_shore_spray")
			check(normal_texture is Texture2D and normal_texture.get_width() > 0 and normal_texture.get_height() > 0, "default ocean uses nonempty PCK normal texture")
			check(has_shore and has_coast and shore_texture is Texture2D and coast_texture is Texture2D, "default ocean built real coastal depth and signed distance fields")
			check(spray is Node3D and spray.is_inside_tree(), "default scene mounted dynamic shore spray")
			entrypoint.world.merge({"normalTextureWidth": normal_texture.get_width() if normal_texture is Texture2D else 0, "normalTextureHeight": normal_texture.get_height() if normal_texture is Texture2D else 0, "hasShoreField": has_shore, "hasCoastDistance": has_coast, "shoreSprayMounted": spray is Node3D and spray.is_inside_tree()})
	root.remove_child(scene)
	scene.free()
	for frame in 2: await process_frame
	check(not is_instance_valid(scene), "default scene disposed after package probe")
	entrypoint.disposed = not is_instance_valid(scene)

func _finite_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value)

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)
