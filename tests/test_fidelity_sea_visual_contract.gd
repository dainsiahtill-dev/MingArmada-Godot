extends SceneTree

const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	# A camera may inspect kilometre-scale native assets without inheriting the
	# game's wave profile. Missing/incorrect preview water must fail explicitly.
	var path := "res://modules/scene_engine/fidelity_island/source_water.gd"
	check(FileAccess.file_exists(path), "completed-demo sea renderer exists independently of gameplay ocean")
	if not FileAccess.file_exists(path):
		_finish(); return
	var Water: Script = load(path)
	check(Water != null, "source sea renderer loads")
	if Water == null:
		_finish(); return
	var manifest := Asset.read_json("res://assets/data/fidelity_island/water-manifest.json")
	var oracle: Dictionary = manifest.get("oracle", {})
	check(not oracle.is_empty(), "external completed-source JavaScript oracle exists")
	for sample: Dictionary in oracle.get("samples", []):
		var actual: Dictionary = Water.ocean_coordinates(Vector2(float(sample.uv[0]), float(sample.uv[1])), float(sample.time), float(sample.scale))
		for key: String in ["bump", "water0", "water1"]:
			for i in 2:
				check(absf(float(actual[key][i])-float(sample[key][i])) < 0.000008, "native UV*45 signed phase at time %s" % sample.time)
	for sample: Dictionary in oracle.get("colors", []):
		var nr: Vector4 = Water.nr_color(Vector3(sample.a[0], sample.a[1], sample.a[2]), Vector3(sample.b[0], sample.b[1], sample.b[2]), Vector3(sample.ambient[0], sample.ambient[1], sample.ambient[2]))
		var color: Vector3 = Water.composite_display_color(nr, Vector3(sample.fogColor[0], sample.fogColor[1], sample.fogColor[2]), float(sample.fog))
		for i in 4:
			check(absf(float(nr[i])-float(sample.nr[i])) < 0.000001, "source NR ambient-product color including .4 alpha")
		for i in 3:
			check(absf(float(color[i])-float(sample.display[i])) < 0.000001, "source display-RGB blending over prior fog clear")
	var camera := Camera3D.new(); root.add_child(camera)
	var water: Node3D = Water.new(); root.add_child(water)
	check(water.configure(camera, Vector3(269925.21875,202766.25,0)), "native source water accepts real original geometry and authored nine mips")
	var info: Dictionary = water.diagnostics()
	check(info.get("meshCount",0) == 9 and info.get("triangles",0) == 18, "original 100000-unit pool tiles retain source topology")
	check(info.get("waterPlaneY",NAN) == 0.0, "source observation water plane is Z0 mapped to Godot Y0")
	check(info.get("textureMipLevels",0) == 9, "complete authored mip chain reaches material")
	check(info.get("nrAlpha",0) == 0.4 and info.get("displayComposition",false), "alpha .4 composes over source display fog, not linear HDR terrain")
	var tile: MeshInstance3D = water.get_child(4)
	var arrays: Array = tile.mesh.surface_get_arrays(0)
	check(arrays[Mesh.ARRAY_TEX_UV][0] == Vector2.ZERO and arrays[Mesh.ARRAY_TEX_UV][3] == Vector2.ONE, "mesh UV preserved rather than physical world .008 normal scales")
	check(arrays[Mesh.ARRAY_VERTEX][0].y == 0.0 and arrays[Mesh.ARRAY_VERTEX][3].y == 0.0, "visual source plane never applies five-wave displacement")
	check(water.apply_snapshot(12.0,{"ambient":[0.4888235628604889,0.5750980377197266,0.7633333802223206],"fogColor":[0.458823561668396,0.6941176652908325,0.8509804606437683]}), "authored noon updates preview material")
	check(water.diagnostics().time == 12.0, "water clock uses caller source time")
	check(water.apply_snapshot(-1.0,{"ambient":[0.2,0.3,0.4],"fogColor":[0.1,0.2,0.3]}) and water.diagnostics().time == -1.0, "direct rewind retains signed original shader phase")
	var previous: Dictionary = water.diagnostics()
	check(not water.apply_snapshot(NAN,{"ambient":[0,0,0],"fogColor":[0,0,0]}) and water.diagnostics().time == previous.time, "invalid clock cannot overwrite valid water state")
	check(not water.apply_snapshot(7.0,{"ambient":[0,0],"fogColor":[0,0,0]}) and water.diagnostics().time == previous.time, "incomplete authored lighting rejected before mutation")
	water.dispose(); check(water.get_child_count() == 0, "preview teardown frees all private tile materials")
	water.free(); camera.free()
	_finish()

func _finish() -> void:
	print("FIDELITY_SEA_VISUAL_CONTRACT assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
