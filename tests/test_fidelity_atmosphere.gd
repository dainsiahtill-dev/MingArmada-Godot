extends SceneTree
## Tests source draw order/float stores, authored mesh replay and owned lifecycle.
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL fidelity atmosphere: ",reason)

func json(path: String) -> Dictionary:
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return result if result is Dictionary else {}

func array_near(actual: Variant, expected: Array, reason: String, tolerance: float = 0.000001) -> void:
	check(actual.size() == expected.size(), reason+" length")
	if actual.size() != expected.size(): return
	for i in expected.size():
		check(absf(float(actual[i])-float(expected[i])) <= tolerance,reason+" component "+str(i))

func _run() -> void:
	var native_path := "res://modules/scene_engine/fidelity_fx/cloud_native.gd"
	var atmosphere_path := "res://modules/scene_engine/fidelity_fx/atmosphere.gd"
	check(FileAccess.file_exists(native_path),"source cloud solver exists")
	check(FileAccess.file_exists(atmosphere_path),"snapshot-owned atmosphere renderer exists")
	if failures > 0:
		finish()
		return
	var Native: Script = load(native_path)
	var Atmosphere: Script = load(atmosphere_path)
	var oracle := json("res://build/fidelity-fx-work/atmosphere/source-oracle.json")
	for seed: Dictionary in oracle.crtSeeds:
		var rng = Native.OriginalCrtRand.new(int(seed.seed))
		for value: Variant in seed.values:
			check(rng.next() == int(value),"CRT uint32 overflow and 15-bit output match original DLL fixture")
	var ring: Dictionary = Native.create_cloud_ring(1)
	var zero_ring: Dictionary = Native.create_cloud_ring_from_rand(func()->int:return 0)
	check(zero_ring.nodes.size() == 36 and zero_ring.draws == 144 and zero_ring.nodes[-1].azimuthDegrees == 350,"ten-degree source spacing stops at360 without forcing30 clones")
	var four_values := [1499,4,9,4]
	var cursor := [0]
	var widest_ring: Dictionary = Native.create_cloud_ring_from_rand(func()->int:
		var value: int = four_values[cursor[0]%4]
		cursor[0] += 1
		return value)
	check(widest_ring.nodes.size() == 26 and widest_ring.draws == 104 and widest_ring.nodes[0].name == "-1499" and widest_ring.nodes[0].prototype == "domecloud5.nif" and widest_ring.nodes[0].tiltDegrees == -9,"four ordered draws retain widest spacing, name, prototype and negative tilt")
	check(ring.nodes.size() == 30 and ring.draws == 120,"CRT seed1 ring consumes exactly four ordered draws per clone")
	for i in ring.nodes.size():
		var actual: Dictionary = ring.nodes[i]
		var wanted: Dictionary = oracle.ring.nodes[i]
		check(actual.name == wanted.name and actual.prototype == wanted.prototype,"original name determines angular speed and original prototype selection")
		check(actual.azimuthDegrees == wanted.azimuthDegrees and actual.tiltDegrees == wanted.tiltDegrees,"original ring stop and tilt")
		array_near(actual.rotation,wanted.rotation,"original cloud construction float matrix")
	for step: Dictionary in oracle.steps:
		Native.advance_clouds(ring,float(step.delta))
		check(ring.updates == int(step.updates),"strict threshold and one subtraction per original call")
		check(ring.accumulator == Native.f32(float(step.accumulator)),"binary32 accumulated native time at delta "+str(step.delta))
		array_near(ring.nodes[0].rotation,step.firstRotation,"original delta rotation",0.0000002)
	for sample: Dictionary in oracle.billboards:
		array_near(Native.billboard_mode0(sample.rotation,sample.camera),sample.expected,"original mode0 branches")
	var manifest := json("res://assets/data/fidelity_fx/manifest.json")
	var sources := {}
	for entry: Dictionary in manifest.get("atmosphere",{}).get("assets",[]):
		sources[str(entry.file)] = json(str(entry.data_path))
	check(sources.size() == 6,"five original domecloud prototypes plus one twenty-mesh fog prototype")
	for sample: Dictionary in oracle.samples:
		if not sources.has(sample.asset): continue
		var camera := {"direction":[0,1,0],"up":[0,0,1],"right":[1,0,0]} if str(sample.asset).begins_with("domecloud") else {}
		var meshes: Array = Native.original_meshes(sources[sample.asset],float(sample.time),{},not str(sample.asset).begins_with("domecloud"),camera)
		check(meshes.size() == sample.meshes.size(),"every authored mesh and source traversal order retained")
		for i in mini(meshes.size(),sample.meshes.size()):
			var actual: Dictionary = meshes[i]
			var wanted: Dictionary = sample.meshes[i]
			check(actual.block == wanted.block and actual.texture == wanted.texture,"original block and inherited texture")
			check(actual.triangles == wanted.triangles,"original topology unchanged")
			check(absf(float(actual.alpha)-float(wanted.alpha)) < 0.000002,"original fog alpha controller")
			array_near(actual.world.translation,wanted.world.translation,"original animated translation",0.0001)
			for j in actual.vertices.size():
				array_near(actual.vertices[j],wanted.vertices[j],"original vertex world transform",0.0002)
				array_near(actual.uvs[j],wanted.uvs[j],"original texture controller transform",0.000002)
	var host := Node3D.new()
	root.add_child(host)
	var camera := Camera3D.new()
	host.add_child(camera)
	camera.position = Vector3(10,8,14)
	camera.look_at(Vector3(0,2,0))
	var atmosphere = Atmosphere.new()
	var configured: Dictionary = atmosphere.configure(host,manifest,{"crt_seed":1,"cloud_sky_radius":160.0,"cloud_sky_height":36.0,"fog_placements":[Transform3D.IDENTITY]})
	check(configured.get("ok",false),"actual source DDS mip textures and meshes configure")
	var atmosphere_container: Node3D = host.get_node("OriginalCloudAndFog")
	check(not atmosphere_container.get_child(0).visible,"configure cannot display opaque defaults before first authoritative snapshot")
	atmosphere.apply_snapshot({"time":0.0},camera,Vector3.ZERO)
	var first: Dictionary = atmosphere.diagnostics()
	check(first.cloudClones == 30 and first.cloudMeshes == 161 and first.fogMeshes == 20,"ring authored meshes plus one original fog prototype")
	atmosphere.apply_snapshot({"time":12.0},camera,Vector3(2,0,3))
	var playing: Dictionary = atmosphere.diagnostics()
	atmosphere.apply_snapshot({"time":12.0},camera,Vector3(2,0,3))
	check(atmosphere.diagnostics().firstCloudRotation == playing.firstCloudRotation,"paused snapshot never advances cloud rotation")
	check(atmosphere.diagnostics().cloudAccumulator == playing.cloudAccumulator,"paused snapshot never advances native threshold accumulator")
	atmosphere.apply_snapshot({"time":0.0},camera,Vector3.ZERO)
	check(atmosphere.diagnostics().firstCloudRotation == first.firstCloudRotation,"rewind restores source ring state")
	atmosphere.apply_snapshot({"time":12.0},camera,Vector3.ZERO)
	check(atmosphere.diagnostics().firstCloudRotation == playing.firstCloudRotation,"rewind replay retains explicit native input sequence")
	var changed_camera := camera.global_transform
	changed_camera.origin += Vector3(8,0,1)
	camera.global_transform = changed_camera
	atmosphere.apply_snapshot({"time":12.0},camera,Vector3.ZERO)
	check(atmosphere.diagnostics().skyOrigin == camera.global_position+Vector3(0,36,0),"camera-follow sky placement is explicit target adaptation")
	check(atmosphere.diagnostics().time == 12.0,"camera changes cannot invent simulation time")
	var placements: Array = []
	for i in 20: placements.append(Transform3D(Basis.IDENTITY,Vector3(i*20.0,0.1,0)))
	check(atmosphere.configure(host,manifest,{"crt_seed":1,"fog_placements":placements}).get("ok",false),"source prototype plus19 clones accepts explicit presentation transforms")
	check(atmosphere.diagnostics().fogMeshes == 400 and atmosphere.diagnostics().fogInstances == 20,"twenty authored meshes per prototype are not misreported as twenty instances")
	array_near(atmosphere.diagnostics().fogPhases,oracle.fogPhases,"original clone phase offset",0.000002)
	placements.append(Transform3D.IDENTITY)
	check(not atmosphere.configure(host,manifest,{"fog_placements":placements}).get("ok",true),"unrecovered twenty-first original fog instance rejected")
	check(host.get_child_count() == 1,"failed configuration removes only its partial owned resources")
	check(atmosphere.configure(host,manifest,{}).get("ok",false) and atmosphere.diagnostics().fogMeshes == 0,"unsupplied target placement does not invent fog world layout")
	check(not atmosphere.configure(host,{},{}).get("ok",true),"missing originals fail explicitly instead of substituting generated effects")
	atmosphere.dispose()
	check(host.get_child_count() == 1,"dispose removes only owned atmosphere nodes")
	check(atmosphere.diagnostics().cloudMeshes == 0 and atmosphere.diagnostics().fogMeshes == 0,"dispose clears owned mutable meshes and state")
	host.free()
	finish()

func finish() -> void:
	print("FIDELITY_ATMOSPHERE_VERIFY assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures else 0)
