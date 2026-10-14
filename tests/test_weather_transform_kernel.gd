extends SceneTree
const Compiler = preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const Native = preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
var assertions := 0
var failures := 0
class StoreProbe extends Compiler:
	var scalar_stores := 0
	func _f32(value: float) -> float:
		scalar_stores += 1
		return super._f32(value)
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL weather transform: ", message)
func _initialize() -> void:
	var path := "res://modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd"
	check(ResourceLoader.exists(path), "independent exact batched transform kernel exists")
	if failures: finish(); return
	var kernel = load(path)
	var old := Compiler.new()
	var rng := RandomNumberGenerator.new(); rng.seed = 1661
	for sample in 1024:
		var a: Array = []; var b: Array = []; var v: Array = []
		for component in 9:
			a.append(rng.randf_range(-3, 3)); b.append(rng.randf_range(-3, 3))
		for component in 3: v.append(rng.randf_range(-10000, 10000))
		var actual: Array = kernel.multiply(a, b)
		check(var_to_bytes(actual) == var_to_bytes(old._multiply_matrix(a, b)), "matrix multiply preserves every binary32 result")
		check(var_to_bytes(actual) == var_to_bytes(Native.multiply_matrix(a, b)), "matrix retains untouched Native oracle")
		check(var_to_bytes(kernel.transform(a, v)) == var_to_bytes(old._transform_vector(a, v)), "vector transform preserves every binary32 result")
		check(var_to_bytes(kernel.transform(a, v)) == var_to_bytes(Native.transform_vector(a, v)), "vector retains untouched Native oracle")
		check(var_to_bytes(kernel.transpose_transform(a, v)) == var_to_bytes(old._transform_transpose(a, v)), "transpose preserves reversed addition order")
		check(var_to_bytes(kernel.transpose_transform(a, v)) == var_to_bytes(Native.transform_transpose(a, v)), "transpose retains untouched Native oracle")
		var held := var_to_bytes(actual)
		kernel.multiply(b, a); b[0] = 123
		check(var_to_bytes(actual) == held, "later transforms and input edits cannot mutate published output")
	var z := [0.0, -0.0, 0.0, -0.0, 0.0, -0.0, 0.0, -0.0, 0.0]
	for a in [z, Native.identity(), [1e-20, -1e-20, 1e20, -1e20, 1.0, 0.0, -0.0, 1e-30, 1e30]]:
		check(var_to_bytes(kernel.multiply(a, z)) == var_to_bytes(old._multiply_matrix(a, z)), "signed zero and large finite scales remain exact")
	var production := StoreProbe.new()
	production._multiply_matrix(Native.identity(), Native.identity())
	production._transform_vector(Native.identity(), [1.0, 2.0, 3.0])
	production._transform_transpose(Native.identity(), [1.0, 2.0, 3.0])
	check(production.scalar_stores == 0, "production matrix/vector dispatch avoids fifteen separate scalar scratch-store calls")
	finish()
func finish() -> void:
	print("WEATHER_TRANSFORM_KERNEL_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
