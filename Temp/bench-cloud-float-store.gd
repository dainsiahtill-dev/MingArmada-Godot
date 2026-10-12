extends SceneTree
## CPU-only actual compiler comparison; no WorldView, render surfaces or GPU.
## Prebuilt source/camera input is identical for both independently compiled graphs.
const Baseline = preload("res://Temp/cloud-render-compiler-byte-store-oracle.gd")
const Candidate = preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const Atmosphere = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const BASELINE_SHA := "c31203ece107f2a288bba6e867398ca1a789f963848cfa03b89abf7e0da8ced1"
const REPORT := "res://Temp/cloud-float-store-ab.json"
var assertions := 0
var failures := 0
var old_compiler := Baseline.new()
var new_compiler := Candidate.new()
var old_graphs: Dictionary = {}
var new_graphs: Dictionary = {}

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL cloud float store: ", detail)

func bits(value: float) -> int:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_float(0, value)
	return bytes.decode_u32(0)

func equal_bits(a: Variant, b: Variant) -> bool:
	if a is Dictionary:
		if not b is Dictionary or a.size() != b.size(): return false
		for key in a:
			if not b.has(key) or not equal_bits(a[key], b[key]): return false
		return true
	if a is Array:
		if not b is Array or a.size() != b.size(): return false
		for i in a.size():
			if not equal_bits(a[i], b[i]): return false
		return true
	if a is PackedFloat32Array:
		return b is PackedFloat32Array and a.to_byte_array() == b.to_byte_array()
	if a is float or a is int:
		return (b is float or b is int) and bits(float(a)) == bits(float(b))
	return a == b

func _initialize() -> void:
	_run.call_deferred()

func inputs(count: int) -> Array:
	var result: Array = []
	var ring: Dictionary = Native.create_cloud_ring(1)
	var camera := Camera3D.new()
	root.add_child(camera)
	for frame in count:
		Native.advance_clouds(ring, 1.0 / 60.0)
		# Position and basis change on every frame; both ordinary and grazing
		# views consume actual mode-0 billboard and source minimum-Z calculations.
		var angle := float(frame) * 0.031 + 0.21
		camera.position = Vector3(sin(angle) * 39.0, 8.0 + fmod(frame * 0.73, 27.0), cos(angle) * 47.0)
		camera.look_at(Vector3(0.0, 3.0, 0.0))
		var view: Dictionary = Atmosphere._camera_basis(camera)
		var groups: Array = []
		for clone: Dictionary in ring.nodes:
			groups.append({"prototype":clone.prototype,"outer":{"rotation":clone.rotation.duplicate(),"translation":Native.transform_vector(clone.rotation,[0,1,0]),"scale":1.0}})
		# Sixth actual source asset is included as a kernel input. Live atmosphere
		# animates fog separately; this probe is explicitly the minimum-state kernel.
		groups.append({"prototype":"fx_groundfog01.nif","outer":{"rotation":Native.identity(),"translation":[.1,.2,.3],"scale":1.15}})
		result.append({"camera":view,"groups":groups})
	camera.free()
	return result

func verify_sources(frames: Array) -> void:
	for frame in frames.size():
		var input: Dictionary = frames[frame]
		for group: Dictionary in input.groups:
			var expected: Array = old_compiler.render_minimum_states(old_graphs[group.prototype], group.outer, input.camera)
			var actual: Array = new_compiler.render_minimum_states(new_graphs[group.prototype], group.outer, input.camera)
			check(actual.size() == expected.size(), "actual prototype leaf count: " + group.prototype)
			for i in mini(actual.size(), expected.size()):
				# Whole source geometry/UV/material fields are checked on the first
				# view; every changing view checks every dynamic/store-dependent field.
				if frame == 0:
					check(equal_bits(actual[i], expected[i]), "all source fields and f32 bits: " + group.prototype + "/" + str(actual[i].block))
				else:
					for field in ["world","billboard","minimumZ"]:
						check(equal_bits(actual[i].get(field), expected[i].get(field)), "changing-view exact " + field + ": " + group.prototype + "/" + str(actual[i].block))

func measure(compiler: RefCounted, graphs: Dictionary, frames: Array) -> Dictionary:
	var leaves := 0
	var checksum := 0.0
	var started := Time.get_ticks_usec()
	for input: Dictionary in frames:
		for group: Dictionary in input.groups:
			var states: Array = compiler.render_minimum_states(graphs[group.prototype], group.outer, input.camera)
			leaves += states.size()
			for state: Dictionary in states: checksum += float(state.minimumZ)
	var elapsed := Time.get_ticks_usec() - started
	return {"elapsed_us":elapsed,"ms_per_frame":float(elapsed)/float(frames.size())/1000.0,"leaves":leaves,"checksum":checksum}

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var assets: Array = []
	for entry: Dictionary in manifest.atmosphere.assets:
		var asset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
		old_graphs[entry.file] = old_compiler.compile_asset(asset)
		new_graphs[entry.file] = new_compiler.compile_asset(asset)
		assets.append({"file":entry.file,"mesh_count":entry.mesh_count,"source_sha256":entry.sha256})
	check(assets.size() == 6, "all five original cloud prototypes and the real fog asset are present")
	var edge_values: Array = [0.0,-0.0,INF,-INF,NAN,pow(2.0,-149.0),-pow(2.0,-149.0),pow(2.0,-150.0),pow(2.0,-126.0),1.0+pow(2.0,-24.0),1.0+pow(2.0,-24.0)+pow(2.0,-52.0),16777217.0,-16777217.0,3.4028234663852886e38,3.5e38]
	for value: float in edge_values:
		check(bits(new_compiler._f32(value)) == bits(old_compiler._f32(value)), "original store bits including signed zero, subnormals, ties and overflow: " + str(value))
	var cases: Dictionary = {32:inputs(32),48:inputs(48)}
	for frames: Array in cases.values(): verify_sources(frames)
	# Warm both actual implementations without JSON parsing/compilation in timing.
	var warm: Array = cases[32].slice(0, 4)
	measure(old_compiler, old_graphs, warm)
	measure(new_compiler, new_graphs, warm)
	var runs: Array = []
	for round_index in 5:
		for count: int in [32,48]:
			var order: Array = ["baseline","packed"] if round_index % 2 == 0 else ["packed","baseline"]
			var sample: Dictionary = {"round":round_index+1,"frames":count,"order":order}
			for name: String in order:
				var compiler: RefCounted = old_compiler if name == "baseline" else new_compiler
				var graphs: Dictionary = old_graphs if name == "baseline" else new_graphs
				sample[name] = measure(compiler, graphs, cases[count])
			check(sample.baseline.leaves == sample.packed.leaves and sample.baseline.checksum == sample.packed.checksum, "both timed paths consume the same actual source results")
			sample.ratio = float(sample.packed.elapsed_us) / maxf(1.0, float(sample.baseline.elapsed_us))
			runs.append(sample)
			print("CLOUD_FLOAT_STORE_AB frames=",count," round=",round_index+1," byte_ms=",sample.baseline.ms_per_frame," packed_ms=",sample.packed.ms_per_frame," ratio=",sample.ratio)
	var report := {"scope":"CPU-only render_minimum_states; 30 actual seeded ring clones plus original fog input; no WorldView/GPU/FPS claim","baseline_sha256":BASELINE_SHA,"assets":assets,"assertions":assertions,"failures":failures,"runs":runs}
	var output := FileAccess.open(REPORT, FileAccess.WRITE)
	if output:
		output.store_string(JSON.stringify(report, "  "))
		output.close()
	else: check(false, "isolated Temp report opens without touching unified verification")
	print("CLOUD_FLOAT_STORE_AB_COMPLETE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
