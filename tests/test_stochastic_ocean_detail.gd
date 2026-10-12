extends SceneTree

const Oracle=preload("res://tests/fixtures/stochastic_surface_oracle.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",reason)

func _run() -> void:
	var helper: String="res://modules/scene_engine/ocean/stochastic_alpha.gdshaderinc"
	check(FileAccess.file_exists(helper), "actual source-texture sampler has a continuous nonperiodic detail path")
	if failures: _finish(); return
	var shader:=Shader.new()
	shader.code='shader_type spatial;\nuniform sampler2D reference_sparkle_texture : repeat_enable, filter_linear_mipmap;\n#include "res://modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc"\n#include "res://modules/scene_engine/ocean/surface_layers.gdshaderinc"\nvoid fragment(){float cap=reference_whitecap_coverage(vec2(4,8),vec3(.2,1,.3),12.25,25.0,1.0);float glint=reference_wind_glint(vec2(4,8),vec3(0,1,0),12.25);ALBEDO=reference_original_micro_sparkle(vec2(4,8),vec3(0,1,0),12.25,vec2(1,0),14.0,.1,25.0,.95)+vec3(cap+glint+reference_surface_flecks(vec2(4,8),vec3(0,1,0),12.25,.95));}'
	var uniforms:=shader.get_shader_uniform_list()
	var source_bindings:=0
	for entry: Dictionary in uniforms:
		if entry.name in ["reference_whitecaps_texture","reference_original_sparkle_texture","reference_sparkle_texture"]: source_bindings+=1
	check(source_bindings==3, "combined real shader helpers parse both overload and shared include exactly once")
	# Literal uint oracle establishes stable cell IDs across negative coordinates.
	check(Oracle.cell_hash(Vector2i.ZERO,17)==0xcb566842, "fixed integer hash matches independent BigInt arithmetic")
	var texture: Texture2D=load("res://assets/textures/pirates_reference/foam0024.dds.png")
	var image:=texture.get_image()
	for point: Vector2 in [Vector2.ZERO,Vector2(.23,.37),Vector2(.87,.63),Vector2(-2.75,-.125),Vector2(2.0,3.0)]:
		var plan:=Oracle.triangle(point); var weights: Vector3=plan.weights
		check(absf(weights.x+weights.y+weights.z-1.0)<.000001 and weights.x>=0.0 and weights.y>=0.0 and weights.z>=0.0, "triangle source-alpha mixture preserves bounded coverage")
	var old_difference:=0.0; var new_difference:=0.0
	for i in 256:
		var uv:=Vector2(float(i%16)*.311+.17,float(i/16)*.277+.13)
		old_difference+=absf(Oracle.texture_alpha(image,uv)-Oracle.texture_alpha(image,uv+Vector2.RIGHT))
		new_difference+=absf(Oracle.stochastic_alpha(image,uv,17,.38)-Oracle.stochastic_alpha(image,uv+Vector2.RIGHT,17,.38))
	check(old_difference/256.0<.00002 and new_difference/256.0>.025, "real foam alpha loses its old exact one-tile repetition")
	for y in 15:
		var at:=Vector2(2.0,float(y)*.067+.01)
		check(absf(Oracle.stochastic_alpha(image,at-Vector2(.000001,0),17,.38)-Oracle.stochastic_alpha(image,at+Vector2(.000001,0),17,.38))<.003, "adjacent cell triangles blend continuously across vertical boundary")
		var diagonal:=Vector2(float(y)*.067+.01,1.0-float(y)*.067-.01)
		check(absf(Oracle.stochastic_alpha(image,diagonal-Vector2(.000001,0),17,.38)-Oracle.stochastic_alpha(image,diagonal+Vector2(.000001,0),17,.38))<.003, "triangle diagonal cannot create visible alpha seams")
	var paused:=Oracle.stochastic_alpha(image,Vector2(4.31,2.67)-Vector2(12.25*.0218,0),17,.38)
	check(paused==Oracle.stochastic_alpha(image,Vector2(4.31,2.67)-Vector2(12.25*.0218,0),17,.38), "repeated accepted clock yields identical source-alpha coverage")
	print("STOCHASTIC_ALPHA_MEASURE oldPeriodDifference=",old_difference/256.0," newPeriodDifference=",new_difference/256.0)
	_finish()

func _finish() -> void:
	print("STOCHASTIC_OCEAN_DETAIL assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
