extends SceneTree
## The compiled hot path must use its existing owner-local float32 store while
## preserving the untouched native clock/scalar/UV oracle and output ownership.
const Compiler = preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const SourceMath = preload("res://modules/scene_engine/fidelity_island/native_math.gd")

class StoredCompiler:
	extends "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
	var stores := 0
	func _f32(value: float) -> float:
		stores += 1
		return super._f32(value)

var assertions := 0
var failures := 0
var _seen: Dictionary = {}

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		if not _seen.has(detail): printerr("FAIL atmosphere scalar kernel: ",detail)
		_seen[detail] = true
	return ok

func _initialize() -> void: _run.call_deferred()
func _same(actual: Variant, expected: Variant) -> bool: return var_to_bytes(actual) == var_to_bytes(expected)
func _clock_state(clock: RefCounted) -> Dictionary:
	return {"last":clock.last,"accumulated":clock.accumulated,"started":clock.started,"controller":clock.controller}

func _clock_path(compiler: RefCounted) -> void:
	# Existing seam: current compiler delegates every store to the allocating
	# source clock. This assertion fails even before new helper API checks.
	var fields := {"flags":9,"frequency":.7,"phase":.125,"start_time":-.3,"stop_time":2.1}
	var prepared: Dictionary = compiler.call("_controller",{"fields":fields},{})
	compiler.stores = 0
	var actual: float = compiler.call("_clock_time",prepared,.37)
	var expected := SourceMath.ControllerClock.new(fields); expected.advance(0.0)
	var wanted := expected.advance(.37)
	check(_same(actual,wanted) and _same(_clock_state(prepared.clock),_clock_state(expected)),"prepared actual clock output and complete mutable state equal untouched source oracle")
	check(int(compiler.stores) > 0,"compiled clock sample uses owner-local float32 storage instead of allocating source f32 calls")

func _all_clock_sequences(compiler: RefCounted) -> void:
	for flags: int in [0,1,8,9,10,11,12,13,14,15,24,25,26,27,28,29]:
		for span: Array in [[-.3,2.1],[2.0,2.0],[33.333335876464844,66.8]]:
			var fields := {"flags":flags,"frequency":-.75 if flags&16 else .7,"phase":.125,"start_time":span[0],"stop_time":span[1]}
			var actual := SourceMath.ControllerClock.new(fields); var expected := SourceMath.ControllerClock.new(fields)
			for time: float in [0.0,.1,.1,.37,2.1,33.333335876464844,66.8,.1,-.2,0.0]:
				var value: float = compiler.call("_advance_clock",actual,time)
				var want := expected.advance(time)
				check(_same(value,want) and _same(_clock_state(actual),_clock_state(expected)),"compiled clock preserves every source store, reverse/cycle, repeated-time and rewind mutable field")
			var prepared: Dictionary = compiler.call("_controller",{"fields":fields},{})
			for time: float in [.1,66.8,.1,0.0]:
				prepared.clock.last = 103.25; prepared.clock.accumulated = -19.0; prepared.clock.started = true
				var value: float = compiler.call("_clock_time",prepared,time)
				var fresh := SourceMath.ControllerClock.new(fields)
				if flags&1: fresh.advance(0.0)
				var want := fresh.advance(time)
				check(_same(value,want) and _same(_clock_state(prepared.clock),_clock_state(fresh)),"compiled per-sample reset preserves optional native zero-epoch and cannot leak previous fog phase")

func _scalar_and_uv(compiler: RefCounted) -> void:
	var groups := [
		{"keys":[],"interpolation":1},
		{"keys":[{"time":0.0,"value":.2},{"time":1.0,"value":.8},{"time":2.0,"value":.1}],"interpolation":1},
		{"keys":[{"time":0.0,"value":.2,"backward":.3,"forward":-.6},{"time":1.0,"value":.8,"backward":.05,"forward":.7},{"time":2.0,"value":.1,"backward":-.2,"forward":.15}],"interpolation":2},
		{"keys":[{"time":0.0,"value":.2},{"time":1.0,"value":.8}],"interpolation":0},
		{"keys":[{"time":0.0,"value":{"x":.1,"y":-.2,"z":.3}},{"time":2.0,"value":{"x":-1.3,"y":2.5,"z":.7}}],"interpolation":1}
	]
	for group: Dictionary in groups:
		for time: float in [-.2,0.0,.1,.3333333,.9999999,1.0,1.25,2.0,2.1]:
			check(_same(compiler.call("_sample",group,time),Native._sample(group,time)),"compiled scalar/vector sample preserves source linear/cubic/endpoints/null/NAN contract")
	compiler.stores = 0
	compiler.call("_sample",groups[2],.37)
	check(int(compiler.stores) > 0,"compiled scalar interpolation consumes owner-local float32 stores")
	for kind: int in [0,1]:
		var desc := {"transform_type":kind,"translation":{"u":.3,"v":-.4},"tiling":{"u":1.5,"v":.7},"center_offset":{"u":.25,"v":.75},"w_rotation":.67}
		for values: Dictionary in [{},{"translationU":-.6,"translationV":.2,"rotation":-.18,"scaleU":.4,"scaleV":2.3}]:
			check(_same(compiler.call("_texture_transform",desc,values),SourceMath.texture_transform(desc,values)),"compiled UV matrix preserves native cosine/sine/center expression store order")
	check(_same(compiler.call("_texture_transform",{"transform_type":7},{}),SourceMath.texture_transform({"transform_type":7},{})),"unsupported UV transform keeps original empty matrix result")
	compiler.stores = 0
	compiler.call("_texture_transform",{"transform_type":0,"w_rotation":.17},{})
	check(int(compiler.stores) > 0,"compiled UV transform consumes owner-local float32 stores")

func _all_source_frames(compiler: RefCounted) -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var camera := {"direction":[.36085122,-.43081242,.82719978],"up":[.17228565,.90244198,.3949131],"right":[-.91659197,0.0,.39982493]}
	var ring: Dictionary = Native.create_cloud_ring(77)
	var frozen_ring: PackedByteArray = var_to_bytes(ring)
	var assets := 0; var live_controllers := 0
	for entry: Dictionary in manifest.atmosphere.assets:
		var asset: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
		var graph: Dictionary = compiler.compile_asset(asset); var animate: bool = entry.file == "fx_groundfog01.nif"
		var outer := {"rotation":ring.nodes[assets%ring.nodes.size()].rotation,"translation":[.1,.2,.3],"scale":1.15}
		for block: Dictionary in asset.blocks:
			if block.type in ["NiAlphaController","NiTextureTransformController","NiKeyframeController"]: live_controllers += 1
		for time: float in [0.0,.1,12.0,33.333335876464844,33.5,66.8,.1,0.0]:
			var actual: Array = compiler.render_states(graph,time,outer,animate,camera,true)
			var expected: Array = Native.original_meshes(asset,time,outer,animate,camera)
			check(actual.size() == expected.size(),"all source cloud/fog geometry order/count remains complete")
			for index in mini(actual.size(),expected.size()):
				for field: String in ["asset","block","texture","world","billboard","alpha","color","uvMatrix","alphaFlags","threshold","clampMode","filterMode","localVertices","sourceUV","triangles","vertices"]:
					check(_same(actual[index].get(field),expected[index].get(field)),"compiled complete native frame exact: "+String(entry.file)+"/"+field)
			var held: PackedByteArray = var_to_bytes(actual)
			compiler.render_states(graph,time+13.37,outer,animate,camera,false)
			check(var_to_bytes(actual) == held,"later source phase cannot mutate retained cloud/fog output arrays or descriptors")
		assets += 1
	check(assets == 6 and live_controllers > 20,"real corpus exercises all six atmosphere assets and authored scalar/UV/keyframe controllers")
	check(var_to_bytes(ring) == frozen_ring,"compiled scalar/control rendering consumes no original cloud CRT or native ring state")

func _independent_owners() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	var fog_asset: Dictionary = {}
	for entry: Dictionary in manifest.atmosphere.assets:
		if entry.file == "fx_groundfog01.nif": fog_asset = JSON.parse_string(FileAccess.get_file_as_string(entry.data_path))
	var a := Compiler.new(); var b := Compiler.new()
	var ag: Dictionary = a.compile_asset(fog_asset); var bg: Dictionary = b.compile_asset(fog_asset)
	var held: Array = a.render_states(ag,.37,{},true,{},true); var bytes := var_to_bytes(held)
	b.render_states(bg,66.8,{},true,{},true); a.render_states(ag,12.1,{},true,{},true)
	check(var_to_bytes(held) == bytes,"different owners and later same-owner frames retain independent immutable published state")
	check(_same(a.render_states(ag,.37,{},true,{},true),b.render_states(bg,.37,{},true,{},true)),"independent owner-local float/clock buffers produce identical complete native phase")

func _run() -> void:
	var compiler := StoredCompiler.new()
	_clock_path(compiler)
	var ready := true
	for method: String in ["_advance_clock","_sample","_interpolate_float_keys","_texture_transform"]:
		var present := check(compiler.has_method(method),"private compiled owner-buffer scalar/control kernel exists: "+method)
		ready = ready and present
	if ready: _all_clock_sequences(compiler); _scalar_and_uv(compiler); _all_source_frames(compiler); _independent_owners()
	print("ATMOSPHERE_SCALAR_KERNEL_TESTS assertions=",assertions," failures=",failures," scope=untouched Native/SourceMath oracle, exact scalar/clock/UV stores, all source frames and owner independence; native FPS attribution owned by root")
	quit(1 if failures else 0)
