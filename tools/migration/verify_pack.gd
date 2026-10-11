extends SceneTree
## Run from an empty directory, with --main-pack and this external script.
## Example: Godot --headless --main-pack <absolute.pck> --script <absolute.gd>
##          -- --pack=<absolute.pck> --proof=<absolute.json>
## Optional actual-renderer capture: --capture-dir=<absolute directory>

var failures: Array[String] = []
var assertions := 0
var resources: Array = []
var models: Array = []
var simulation: Dictionary = {}
var entrypoint: Dictionary = {"readyExecuted": false}
var enhancements: Dictionary = {"textures": [], "damageBindings": [], "waterBindings": [], "world": {}}
var reference_textures: Dictionary = {}
var pack_path := ""
var proof_path := ""
var capture_dir := ""
var captures: Array = []
var working_directory := ""

func _initialize() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--pack="): pack_path = argument.trim_prefix("--pack=")
		if argument.begins_with("--proof="): proof_path = argument.trim_prefix("--proof=")
		if argument.begins_with("--capture-dir="): capture_dir = argument.trim_prefix("--capture-dir=")
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
	for excluded in ["res://docs", "res://tests", "res://tools", "res://assets/provenance", "res://.superpowers", "res://build"]:
		check(not DirAccess.dir_exists_absolute(excluded), "excluded directory absent: " + excluded)
	for excluded in ["res://tests/fixtures/naval-reference.json", "res://tests/fixtures/legacy-reference.json", "res://docs/migration/progress.md", "res://tools/migration/verify_pack.gd"]:
		check(not FileAccess.file_exists(excluded) and not ResourceLoader.exists(excluded), "excluded file absent: " + excluded)
	probe_collation()
	probe_models()
	probe_reference_resources()
	probe_reference_damage()
	probe_reference_water()
	probe_wave_height_contract()
	probe_encounter()
	await probe_menu_entrypoint(main_scene)
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
		"resources": resources, "models": models, "simulation": simulation, "referenceEnhancements": enhancements,
		"scope": "Native PCK resource reads and imported-model instantiation; 11 dynamic damage PNG loads/material bindings, four new water texture loads/presenter bindings, terrain/optics shader and helper loads; one deterministic naval tick; default-menu initialization and actual 1650 startup/authority-clock advancement, pause and terrain/ocean/ship synchronization through menu route. Full PASS also requires engine log without SCRIPT ERROR/ERROR. Default sail subtype0 uses up to damage080; sail100 is load/bind capability checked, not claimed visible in that route. Not a Windows EXE launch, GPU compilation/pixels or performance acceptance."
	}
	if not capture_dir.is_empty():
		result.rendererCapture = {"requestedDirectory": capture_dir, "displayServer": DisplayServer.get_name(), "suppliedExecutable": OS.get_executable_path(), "captures": captures, "skippedHeadless": DisplayServer.get_name() == "headless"}
		if DisplayServer.get_name() != "headless":
			result.scope = String(result.scope).trim_suffix("Not a Windows EXE launch, GPU compilation/pixels or performance acceptance.") + "Actual supplied executable renderer capture was requested: " + OS.get_executable_path() + ". PNGs and per-frame GPU metadata record the menu and actual 1650 route after frame_post_draw. This does not establish original-game GPU parity or wall-time performance; visual acceptance requires inspecting the captured pixels and engine log."
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

func probe_wave_height_contract() -> void:
	var paths := ["res://modules/physics_engine/ocean/wave_field.gd", "res://modules/physics_engine/ocean/coastal_wave_field.gd"]
	var wave_instances: Array = []
	for path in paths:
		var script = load(path) if ResourceLoader.exists(path) else null
		check(script is GDScript and script.can_instantiate(), "PCK scalar wave script loads: " + path)
		var wave = script.new() if script is GDScript and script.can_instantiate() else null
		check(wave != null and wave.has_method("sample_height") and wave.has_method("sample"), "PCK wave supplies scalar and full contracts: " + path)
		wave_instances.append(wave)
		resources.append({"path": path, "nativeResourcePresent": ResourceLoader.exists(path), "scalarHeightPresent": wave != null and wave.has_method("sample_height")})
	var equality_checks := 0
	for wave in wave_instances:
		if wave == null or not wave.has_method("sample_height"): continue
		for point in [[0.0, 0.0, 0.0], [93.75, -102.625, 16.25], [-503.125, 216.75, 842.0625]]:
			check(wave.sample_height(point[0], point[1], point[2]) == wave.sample(point[0], point[1], point[2]).height, "PCK scalar wave equals full height exactly")
			equality_checks += 1
	var coastal = wave_instances[1]
	if coastal != null and coastal.has_method("sample_height"):
		for ground_height in [-20.0, -8.0, -4.0, -0.125, 0.0, 2.0, NAN]:
			coastal.configure(func(_x: float, _z: float) -> float: return ground_height)
			check(coastal.sample_height(93.75, -102.625, 16.25) == coastal.sample(93.75, -102.625, 16.25).height, "PCK scalar coastal height equals full height for depth/fallback " + str(ground_height))
			equality_checks += 1
	var runtime_paths := ["res://game/runtime/legacy_runtime.gd", "res://game/runtime/mingqi_runtime.gd", "res://game/runtime/naval_practice_runtime.gd", "res://game/runtime/sailing_runtime.gd", "res://game/runtime/visual_qa_runtime.gd"]
	for path in runtime_paths:
		var script = load(path) if ResourceLoader.exists(path) else null
		check(script is GDScript and script.can_instantiate(), "PCK updated runtime script loads: " + path)
		var runtime = script.new() if script is GDScript and script.can_instantiate() else null
		check(runtime != null and runtime.has_method("sample_water_height"), "PCK runtime retains public water-height route: " + path)
		resources.append({"path": path, "nativeResourcePresent": ResourceLoader.exists(path), "waterHeightApiPresent": runtime != null and runtime.has_method("sample_water_height")})
	enhancements.waveHeightContract = {"wavePaths": paths, "runtimePaths": runtime_paths, "exactScalarFullHeightChecks": equality_checks, "scope": "Actual PCK script loading and scalar/full sample equality, including coast, land, deep-water and invalid-terrain fallbacks. Five runtime APIs load; the real 1650 route is additionally executed. No performance claim."}

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

func probe_reference_resources() -> void:
	var shader_paths := ["res://game/presentation/ships/ship_damage.gdshader", "res://modules/scene_engine/terrain/terrain_surface.gdshader", "res://modules/scene_engine/ocean/original_water_optics.gdshader", "res://game/presentation/water/splash_volume.gdshader"]
	for path: String in shader_paths:
		check(ResourceLoader.exists(path), "PCK enhancement shader exists: " + path)
		var shader = load(path) if ResourceLoader.exists(path) else null
		check(shader is Shader, "PCK enhancement shader loads as native Shader: " + path)
		resources.append({"path": path, "kind": "Shader", "loaded": shader is Shader})
	var helper_path := "res://modules/scene_engine/ocean/surface_optics.gd"
	var helper = load(helper_path) if ResourceLoader.exists(helper_path) else null
	check(helper is GDScript and helper.can_instantiate(), "PCK optics helper and dependencies load")
	resources.append({"path": helper_path, "kind": "GDScript", "loaded": helper is GDScript and helper.can_instantiate()})
	var damage_shader = load(shader_paths[0]) if ResourceLoader.exists(shader_paths[0]) else null
	for surface: String in ["hull", "sail"]:
		for suffix in ([0, 20, 40, 60, 80, 100] if surface == "hull" else [20, 40, 60, 80, 100]):
			var path := "res://assets/textures/pirates_damage_reference/ship_%s_damage%03d.dds.png" % [surface, suffix]
			var texture = probe_texture(path, "dynamic-damage")
			if texture is Texture2D and damage_shader is Shader:
				var material := ShaderMaterial.new()
				material.shader = damage_shader
				material.set_shader_parameter("reference_damage", texture)
				material.set_shader_parameter("use_reference_damage", true)
				check(material.get_shader_parameter("reference_damage") == texture and material.get_shader_parameter("use_reference_damage") == true, "PCK damage texture can bind to real damage material: " + path)
				enhancements.damageBindings.append({"path": path, "binding": "ShaderMaterial.reference_damage", "scope": "native-resource-binding-capability", "bound": material.get_shader_parameter("reference_damage") == texture})
	for filename: String in ["fx_water_splash_004.dds.png", "fx_streakin_001.dds.png", "fx_mist_01.dds.png", "wake3unique.dds.png"]:
		probe_texture("res://assets/textures/pirates_reference/" + filename, "new-water")

func probe_texture(path: String, category: String) -> Variant:
	check(ResourceLoader.exists(path), "PCK imported texture exists: " + path)
	var texture = load(path) if ResourceLoader.exists(path) else null
	check(texture is Texture2D and texture.get_width() > 0 and texture.get_height() > 0, "PCK imported texture actually loads: " + path)
	var info := {"path": path, "category": category, "loaded": texture is Texture2D, "rawPngPresent": FileAccess.file_exists(path), "width": texture.get_width() if texture is Texture2D else 0, "height": texture.get_height() if texture is Texture2D else 0}
	resources.append(info); enhancements.textures.append(info)
	if texture is Texture2D: reference_textures[path] = texture
	return texture

func probe_reference_damage() -> void:
	var path := "res://game/presentation/ships/ship_damage.gd"
	var script = load(path) if ResourceLoader.exists(path) else null
	check(script is GDScript and script.can_instantiate(), "PCK dynamic damage presenter loads")
	if not script is GDScript or not script.can_instantiate(): return
	var library = load("res://modules/scene_engine/assets/asset_library.gd").new()
	var model = library.instantiate_model("res://assets/models/ships/fuchuan-lod0.glb")
	if not model is Node3D: check(false, "PCK damage probe has actual imported model"); library.dispose(); return
	var presenter = script.new()
	var damage_models: Array[Node3D] = [model]
	presenter.configure(damage_models)
	var cache = presenter.get("_textures")
	check(cache is Dictionary and cache.size() == 11, "PCK dynamic filename loading resolves all 11 damage textures")
	var now := 1.0
	for suffix in [0, 20, 40, 60, 80, 100]:
		presenter.apply_snapshot({"id": "pack-damage", "hull": 100.0 - suffix, "maxHull": 100.0, "sail": 100.0, "maxSail": 100.0}, now)
		now += 1.0
		probe_damage_entries(presenter, false, suffix)
	for damage in [0, 24, 48, 66, 84]:
		presenter.apply_snapshot({"id": "pack-damage", "hull": 100.0, "maxHull": 100.0, "sail": 100.0 - damage, "maxSail": 100.0}, now)
		now += 1.0
		var diagnostics: Dictionary = presenter.diagnostics()
		probe_damage_entries(presenter, true, int(diagnostics.sail_stage) * 20)
	presenter.dispose(); model.free(); library.dispose()

func probe_damage_entries(presenter: RefCounted, sail: bool, suffix: int) -> void:
	var entries: Array = presenter.get("_materials")
	var matched := 0
	var all_bound := true
	var path := "res://assets/textures/pirates_damage_reference/ship_%s_damage%03d.dds.png" % ["sail" if sail else "hull", suffix]
	for entry: Dictionary in entries:
		if bool(entry.sail) != sail: continue
		matched += 1
		var texture = entry.material.get_shader_parameter("reference_damage")
		var active = entry.material.get_shader_parameter("use_reference_damage")
		all_bound = all_bound and (texture == reference_textures.get(path) and active == true if suffix > 0 else texture == null and active == false)
	check(matched > 0 and all_bound, "PCK actual presenter binds %s stage %d to imported model materials" % ["sail" if sail else "hull", suffix])
	enhancements.damageBindings.append({"path": path if suffix > 0 else "", "surface": "sail" if sail else "hull", "stage": suffix, "materials": matched, "scope": "actual-dynamic-presenter", "bound": all_bound, "stageZeroRestoresDefault": suffix == 0})

func probe_reference_water() -> void:
	var splash_path := "res://game/presentation/water/water_splashes.gd"
	var splash_script = load(splash_path) if ResourceLoader.exists(splash_path) else null
	check(splash_script is GDScript and splash_script.can_instantiate(), "PCK splash presenter loads volume dependencies")
	if splash_script is GDScript and splash_script.can_instantiate():
		var splash = splash_script.new(); root.add_child(splash)
		splash.configure(func(_x: float, _z: float, _time: float) -> float: return 0.0)
		splash.apply_snapshot(1.0)
		splash.add_event({"type": "splash", "id": "pack-splash", "time": 1.0, "position": {"x": 0.0, "y": 0.0, "z": 0.0}})
		var column = splash.find_child("WaterColumn", true, false)
		var shell = splash.find_child("UmbrellaShell", true, false)
		var mist = splash.find_child("WeakMist", true, false)
		var drops = splash.find_child("WorldDroplets", true, false)
		check(column is MeshInstance3D and shell is MeshInstance3D and mist is MeshInstance3D and drops is MultiMeshInstance3D, "PCK splash builds actual column, shell, mist and droplets")
		for item in [[column, "fx_water_splash_004.dds.png", "column"], [shell, "fx_water_splash_004.dds.png", "shell"], [mist, "fx_mist_01.dds.png", "mist"]]:
			var material = item[0].material_override if item[0] is MeshInstance3D else null
			probe_water_binding(material, item[1], item[2])
		var drop_material = drops.multimesh.mesh.surface_get_material(0) if drops is MultiMeshInstance3D and drops.multimesh and drops.multimesh.mesh else null
		probe_water_binding(drop_material, "fx_streakin_001.dds.png", "world-droplets")
		splash.dispose(); root.remove_child(splash); splash.free()
	var wake_path := "res://game/presentation/water/wake_trails.gd"
	var wake_script = load(wake_path) if ResourceLoader.exists(wake_path) else null
	check(wake_script is GDScript and wake_script.can_instantiate(), "PCK wake presenter loads wave geometry dependencies")
	if wake_script is GDScript and wake_script.can_instantiate():
		var wake = wake_script.new(); root.add_child(wake)
		wake.configure(func(_x: float, _z: float, _time: float) -> float: return 0.0)
		var materials = wake.get("_materials")
		check(materials is Array and materials.size() == 1, "PCK wake uses one selected history material")
		if materials is Array and materials.size() == 1: probe_water_binding(materials[0], "wake3unique.dds.png", "history-wake")
		wake.dispose(); root.remove_child(wake); wake.free()

func probe_water_binding(material: Variant, filename: String, role: String) -> void:
	var path := "res://assets/textures/pirates_reference/" + filename
	var bound: bool = material is ShaderMaterial and material.get_shader_parameter("foam_texture") == reference_textures.get(path) and reference_textures.has(path)
	check(bound, "PCK actual water presenter binds " + role + ": " + path)
	enhancements.waterBindings.append({"path": path, "role": role, "bound": bound})

func probe_menu_entrypoint(path: String) -> void:
	entrypoint = {"mainScene":path,"readyExecuted":false,"processFrames":0}
	var packed = load(path)
	check(packed is PackedScene,"configured PCK main scene loads as PackedScene")
	if not packed is PackedScene: return
	var scene = packed.instantiate()
	check(scene is Node,"configured menu instantiates native Node")
	if not scene is Node:
		if scene: scene.free()
		return
	root.add_child(scene)
	for frame in 8: await process_frame; entrypoint.processFrames += 1
	check(scene.is_node_ready() and scene.is_inside_tree(),"configured menu completed ready")
	check(scene.menu is Control and scene.menu.visible and scene.current_scene == null,"default menu mounted before any career starts")
	check(scene.router is RefCounted and scene.menu._buttons.has("mingqi"),"menu owns native router and 1650 entry control")
	entrypoint.readyExecuted = scene.is_node_ready()
	await capture_frame("menu-ready")
	scene.menu._buttons.mingqi.pressed.emit()
	for frame in 24:
		await process_frame; entrypoint.processFrames += 1
		if scene.current_scene: break
	check(scene.current_scene != null,"PCK menu button signal enters real 1650 scene")
	if scene.current_scene:
		var play: Node = scene.current_scene
		check(play.startup_receipt.get("ok",false),"PCK 1650 terrain/native startup confirmed")
		var packet: Dictionary = play.runtime.snapshot()
		check(packet.runtime.status == "ready" and packet.campaign.currentPortId == "xiamen","PCK 1650 runtime and business authorities ready")
		check(play.world is Node3D and play.world.get_chunk_count() > 0,"PCK 1650 world built real terrain")
		var flagship: String = packet.campaign.flagshipId
		var ship = play.ships.get(flagship)
		var crew = play.sailors.get(flagship)
		check(ship is Node3D and ship.is_inside_tree() and is_instance_valid(ship.get_model()),"PCK menu route built imported flagship")
		check(crew is Node3D and crew.get_visible_count() > 0 and crew.get_visible_count() <= 24,"PCK menu route built bounded actual deck sailors")
		check(play.camera is Camera3D and play.camera.current,"PCK menu route mounted current native camera")
		if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
			# Keep the accepted runtime snapshot fixed while waiting for the GPU frame.
			play.set_physics_process(false)
			packet = play.runtime.snapshot()
			await capture_frame("mingqi-ready", packet)
		var ocean = play.world.get_ocean()
		check(ocean is MeshInstance3D and ocean.material_override is ShaderMaterial,"PCK menu route configured original ocean shader")
		if ocean is MeshInstance3D and ocean.material_override is ShaderMaterial:
			var material: ShaderMaterial = ocean.material_override
			var normal = material.get_shader_parameter("normal_texture")
			check(normal is Texture2D and normal.get_width() > 0,"PCK original ocean normal texture loaded")
			check(material.get_shader_parameter("has_shore_field") == true and material.get_shader_parameter("has_coast_distance") == true,"PCK real coastal height/distance fields bound")
			probe_world_enhancements(play, ocean, packet)
		entrypoint.route = {"scene":play.get_script().resource_path,"tick":packet.naval.tick,"campaignId":packet.campaign.campaignId,"ships":play.ships.keys(),"crew":crew.diagnostics() if crew else {},"terrainChunks":play.world.get_chunk_count()}
	root.remove_child(scene); scene.free()
	for frame in 2: await process_frame
	check(not is_instance_valid(scene),"PCK menu and entered scene disposed")
	entrypoint.disposed = not is_instance_valid(scene)

func capture_frame(label: String, packet: Dictionary = {}) -> void:
	if capture_dir.is_empty() or DisplayServer.get_name() == "headless": return
	check(capture_dir.is_absolute_path(), "renderer capture directory is absolute")
	if not capture_dir.is_absolute_path(): return
	var directory_error := DirAccess.make_dir_recursive_absolute(capture_dir)
	check(directory_error == OK, "renderer capture directory can be prepared")
	if directory_error != OK: return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	check(image != null and not image.is_empty(), "actual renderer viewport has pixels: " + label)
	if image == null or image.is_empty(): return
	var png_path := capture_dir.path_join(label + ".png")
	var png_error := image.save_png(png_path)
	check(png_error == OK, "actual renderer PNG saved: " + label)
	var metadata := {
		"label": label,
		"generatedAtUtc": Time.get_datetime_string_from_system(true),
		"suppliedExecutable": OS.get_executable_path(),
		"suppliedExecutableSha256": FileAccess.get_sha256(OS.get_executable_path()),
		"packPath": pack_path,
		"packSha256": FileAccess.get_sha256(pack_path) if FileAccess.file_exists(pack_path) else "",
		"engine": Engine.get_version_info(),
		"displayServer": DisplayServer.get_name(),
		"gpu": RenderingServer.get_video_adapter_name(),
		"userDataDirectory": OS.get_user_data_dir(),
		"configuredRenderingMethod": ProjectSettings.get_setting("rendering/renderer/rendering_method", ""),
		"viewport": [image.get_width(), image.get_height()],
		"pngPath": png_path,
		"pngSha256": FileAccess.get_sha256(png_path) if png_error == OK else "",
		"runtime": packet,
		"scope": "Actual supplied executable renderer pixels after frame_post_draw. Menu/default 1650 startup route, with gameplay physics stopped before the scene capture to retain its accepted snapshot. No wall-time performance measurement or original-game GPU equivalence claim."
	}
	var metadata_path := capture_dir.path_join(label + ".json")
	var output := FileAccess.open(metadata_path, FileAccess.WRITE)
	check(output != null, "actual renderer frame metadata can be written: " + label)
	if output != null:
		output.store_string(JSON.stringify(metadata, "\t"))
		output.close()
	captures.append(metadata)

func probe_world_enhancements(play: Node, ocean: MeshInstance3D, packet: Dictionary) -> void:
	play.set_physics_process(false)
	check(ocean.has_method("get_surface_optics_diagnostics"), "PCK actual 1650 ocean exposes optical diagnostics")
	if not ocean.has_method("get_surface_optics_diagnostics"): return
	var optics: Dictionary = ocean.get_surface_optics_diagnostics()
	var material: ShaderMaterial = ocean.material_override
	check(optics.get("enabled", false) and optics.get("camera_valid", false) and optics.get("reflection_method") == "screen-space", "PCK 1650 route enables screen/depth optics with actual camera")
	check(optics.get("offscreen_targets", -1) == 0 and optics.get("private_worlds", -1) == 0 and int(optics.get("reflection_steps", 99)) <= 24, "PCK optics has bounded steps and no private render worlds")
	check(material.shader == load("res://modules/scene_engine/ocean/original_water_optics.gdshader") and material.get_shader_parameter("surface_optics_enabled") == true, "PCK real ocean selected native optical shader and bound profile")
	check(material.get_shader_parameter("wave_count") == 5, "PCK optical profile retains original five waves")
	var helper_script = load("res://modules/scene_engine/ocean/surface_optics.gd")
	if helper_script is GDScript and helper_script.can_instantiate():
		var helper = helper_script.new()
		var projection: Projection = play.camera.get_camera_projection()
		var point := Vector3(0.2, 0.1, -10.0)
		var projected: Dictionary = helper.project_view(projection, point)
		var recovered: Vector3 = helper.reconstruct_view(projection.inverse(), projected.get("uv", Vector2.ZERO), float(projected.get("depth", 0.0)))
		check(not projected.is_empty() and recovered.distance_to(point) < 0.0001, "PCK optics helper executes actual projection/inverse-depth mathematics")
	check(play.world.has_method("get_distant_chunks"), "PCK 1650 world exposes bounded distant terrain")
	var distant: Array = play.world.get_distant_chunks() if play.world.has_method("get_distant_chunks") else []
	check(not distant.is_empty() and distant.size() <= 128, "PCK 1650 islands have bounded distant terrain support")
	var details = play.world.get("_island_details")
	var detail_receipt: Dictionary = details.diagnostics() if details != null and details.has_method("diagnostics") else {}
	check(int(detail_receipt.get("instance_count", 0)) > 0 and int(detail_receipt.get("visible_group_count", 0)) > 0, "PCK 1650 world mounts actual island-detail batches")
	var clock_before := float(packet.naval.time)
	var product_waves = play.runtime.get("_waves")
	check(product_waves != null and product_waves.has_method("sample_height"), "PCK actual 1650 runtime owns scalar-height coastal field")
	if product_waves != null and product_waves.has_method("sample_height"):
		var height_point := Vector2(93.75, -102.625)
		var product_height: float = play.runtime.sample_water_height(height_point.x, height_point.y, clock_before)
		check(product_height == product_waves.sample_height(height_point.x, height_point.y, clock_before) and product_height == product_waves.sample(height_point.x, height_point.y, clock_before).height, "PCK actual 1650 runtime height equals scalar and full authority sample exactly")
		enhancements.waveHeightContract.actual1650Height = {"x": height_point.x, "z": height_point.y, "acceptedTime": clock_before, "height": product_height, "exactScalarAndFullEquality": product_height == product_waves.sample(height_point.x, height_point.y, clock_before).height}
	var consumed: float = play.runtime.advance(1.0 / 60.0)
	check(absf(consumed - 1.0 / 60.0) < 1.0e-10, "PCK 1650 authority accepts one requested source tick")
	play._present(consumed)
	var advanced: Dictionary = play.runtime.snapshot()
	check(absf(float(advanced.naval.time) - clock_before - consumed) < 1.0e-10, "PCK product authority advances its unique accepted clock")
	probe_product_clocks(play, float(advanced.naval.time), "advanced")
	check(play.runtime.set_pause("player", true).get("ok", false), "PCK product pause accepted")
	var frozen: Dictionary = play.runtime.snapshot().naval
	var paused_consumed: float = play.runtime.advance(0.2)
	play._present(paused_consumed)
	check(paused_consumed == 0.0 and play.runtime.snapshot().naval == frozen, "PCK paused native authority retains exact snapshot")
	probe_product_clocks(play, float(frozen.time), "paused")
	enhancements.world = {"optics": optics, "distantTerrainChunks": distant.size(), "islandInstances": detail_receipt.get("instance_count", 0), "visibleDetailGroups": detail_receipt.get("visible_group_count", 0), "clockBefore": clock_before, "acceptedSeconds": consumed, "clockAfter": advanced.naval.time, "pausedConsumed": paused_consumed, "pausedSnapshotUnchanged": play.runtime.snapshot().naval == frozen, "terrainClockScope": "all-current-near-and-distant-shader-materials"}

func probe_product_clocks(play: Node, seconds: float, phase: String) -> void:
	var ocean = play.world.get_ocean()
	var material: ShaderMaterial = ocean.material_override
	check(absf(float(material.get_shader_parameter("simulation_time")) - seconds) < 1.0e-10, "PCK ocean clock matches authority: " + phase)
	var chunks: Array = play.world.get_chunks()
	if play.world.has_method("get_distant_chunks"): chunks.append_array(play.world.get_distant_chunks())
	var detailed := 0
	for chunk in chunks:
		var terrain = chunk.material_override
		check(terrain is ShaderMaterial and terrain.shader == load("res://modules/scene_engine/terrain/terrain_surface.gdshader"), "PCK actual near/distant chunk binds detailed land shader: " + String(chunk.name))
		if not terrain is ShaderMaterial: continue
		detailed += 1
		check(absf(float(terrain.get_shader_parameter("simulation_time")) - seconds) < 1.0e-10 and terrain.get_shader_parameter("wave_count") == material.get_shader_parameter("wave_count") and terrain.get_shader_parameter("wave_components") == material.get_shader_parameter("wave_components"), "PCK detailed land time/waves match ocean: " + String(chunk.name) + ":" + phase)
		check(terrain.get_shader_parameter("has_shore_field") == true and terrain.get_shader_parameter("shore_bounds") == material.get_shader_parameter("shore_bounds") and terrain.get_shader_parameter("shore_height_texture") == material.get_shader_parameter("shore_height_texture"), "PCK detailed land shares actual shoreline inputs: " + String(chunk.name))
	check(detailed == chunks.size() and detailed > 0, "PCK all visible terrain uses accepted-clock detailed surface: " + phase)
	for ship in play.ships.values():
		check(absf(float(ship.damage_diagnostics().accepted_time) - seconds) < 1.0e-10, "PCK real ship damage timeline follows authority: " + phase)
		var cache = ship.get("_damage").get("_textures")
		check(cache is Dictionary and cache.size() == 11, "PCK actual product ship resolved all dynamic damage textures")
	check(absf(float(play.sea.wakes.get("_time")) - seconds) < 1.0e-10 and absf(float(play.effects.get("_time")) - seconds) < 1.0e-10, "PCK wake and combat effects share accepted product clock: " + phase)
	var details = play.world.get("_island_details")
	if details != null: check(absf(float(details.diagnostics().simulation_time) - seconds) < 1.0e-10, "PCK island detail clock follows authority: " + phase)

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
		push_error(message)
