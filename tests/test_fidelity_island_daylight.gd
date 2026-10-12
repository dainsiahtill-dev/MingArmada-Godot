extends SceneTree

const Daylight = preload("res://modules/scene_engine/fidelity_island/daylight.gd")
const Asset = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
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
	var source := Asset.read_json("res://assets/data/fidelity_island/timeofday-original.json")
	var fixture := Asset.read_json("res://assets/data/fidelity_island/native-light-fixtures.json")
	var blocks := {}
	for block: Dictionary in source.blocks:
		blocks[int(block.id)] = block.fields
	var coefficients := 0
	for item: Dictionary in fixture.coefficient_cases:
		var curve: Dictionary = blocks[int(item.group)].data
		var actual: Array = Daylight.vector_coefficients(curve)
		for i in item.segments.size():
			for key: String in ["p","out","c2","c3"]:
				for axis in 3:
					check(float(actual[i][key][axis]) == Native.f32(float(item.segments[i][key][axis])), "original axis-specific x87 coefficient store")
			coefficients += 1
	check(coefficients == 21, "all original Bezier coefficient segments were checked")
	var scalars := 0
	for item: Dictionary in fixture.vector_cases:
		var curve: Dictionary = blocks[int(item.group)].data
		var value := Daylight.vector_value(curve, int(item.segment), float(item.t))
		var derivative := Daylight.vector_derivative(curve, int(item.segment), float(item.t))
		for axis in 3:
			check(float(value[axis]) == Native.f32(float(item.value[axis])), "original real vector value oracle")
			check(float(derivative[axis]) == Native.f32(float(item.derivative[axis])), "original real vector derivative oracle")
			scalars += 2
	check(scalars == 630, "all630 machine-code vector scalars checked")
	var path_curve: Dictionary = blocks[31].data
	var expected_lengths: Array = fixture.path_lengths.map(func(v: Variant) -> float: return Native.f32(float(v)))
	check(Daylight.path_lengths(path_curve) == expected_lengths, "original five-point quadrature arc lengths match")
	for item: Dictionary in fixture.path_cases:
		var expected_position: Array = item.position.map(func(v: Variant) -> float: return Native.f32(float(v)))
		check(Daylight.path_sample(path_curve, float(item.fraction)).position == expected_position, "original constant-speed32-Newton-bound path position")
	for item: Dictionary in fixture.lookat_cases:
		var expected_direction: Array = item.direction.map(func(v: Variant) -> float: return Native.f32(float(v)))
		check(Daylight.light_direction(item.position,item.target) == expected_direction, "original LookAt axis2/flip0 light first-column direction")
	var snapshots := Asset.read_json("res://assets/data/fidelity_island/daylight-samples.json")
	check(snapshots.samples.size() == 97, "separate JS importer has97 authoring-time samples")
	for expected: Dictionary in snapshots.samples:
		var actual := Daylight.sample(float(expected.time))
		for key: String in ["lightDirection","lightColor","ambient","palmLightColor","palmAmbient","fogColor","ambientColor"]:
			for axis in 3:
				check(float(actual[key][axis]) == Native.f32(float(expected[key][axis])), "original source-bound daylight " + key + " at " + str(expected.time))
		check(float(actual.ambientAlpha) == Native.f32(float(expected.ambientAlpha)), "source binding average1/6 ambient alpha")
	check(Daylight.sample(-100.0).time == 0.0 and Daylight.sample(100.0).time == 24.0, "viewer clamps authoring-time input; no civil-time reinterpretation")
	var expected_fog: Array = fixture.fog_case.bindings.f3FogValues.map(func(v: Variant) -> float: return Native.f32(float(v)))
	check(Daylight.initial_fog_values(30000.0) == expected_fog, "original float.01 fog40 bind remains source-bound")
	print("FIDELITY_ISLAND_DAYLIGHT_VERIFY assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
