extends SceneTree
## A descriptor accepted by the shared contract must survive the actual GPU
## uniform upload; failed reconfiguration must preserve prior physical water.
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const Uniforms = preload("res://modules/scene_engine/ocean/wave_uniforms.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(value: bool,message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func flat(_x: float,_z: float) -> float: return -24.0
func run() -> void:
	var physical := Waves.new(); physical.configure()
	var coastal := Coastal.new(); coastal.configure(flat)
	var before: float = physical.sample_height(3.0,-5.0,11.0)
	for patch: Dictionary in [{"amplitude":1e60},{"amplitude":-1e60},{"speed":1e60},{"wavelength":1e-60}]:
		var descriptor := {"amplitude":1.0,"direction":{"x":3.0,"z":4.0},"wavelength":TAU,"speed":0.5}
		descriptor.merge(patch,true)
		check(not Descriptor.valid_descriptors([descriptor]),"shared contract rejects non-finite Float32 component "+str(patch))
		check(Uniforms.components([descriptor]).is_empty(),"real GPU adapter rejects the same overflow "+str(patch))
		check(not physical.configure([descriptor]) and physical.sample_height(3.0,-5.0,11.0)==before,"CPU rejection preserves previously accepted physical profile "+str(patch))
		check(not coastal.configure(flat,[descriptor]) and coastal.sample_height(3.0,-5.0,11.0)==before,"Coastal rejection preserves previously accepted field "+str(patch))
	for descriptor: Dictionary in [{"amplitude":1e37,"direction":{"x":3.0,"z":4.0},"wavelength":TAU,"speed":1e37},{"amplitude":1.0,"direction":{"x":1e308,"z":-1e308},"wavelength":1e-4,"speed":-0.75}]:
		check(Descriptor.valid_descriptors([descriptor]),"finite Float32 payload and large normalized direction remain legal")
		check(not Uniforms.components([descriptor]).is_empty() and physical.configure([descriptor]),"real CPU and GPU accept the same finite payload")
	physical.configure()
	for point: Vector2 in [Vector2.ZERO,Vector2(3,-5),Vector2(-530.40888,-723.265)]:
		for seconds: float in [0.0,1.25,17.25,80.0]:
			var source := 0.0
			for component: Array in Descriptor.ORIGINAL_COMPONENTS:
				source += component[0]*sin(component[1]*point.x+component[2]*point.y+component[3]*seconds)
			check(physical.sample_height(point.x,point.y,seconds)==source,"default five waves retain exact original double phase and summation order")
	print("WAVE_DESCRIPTOR_FLOAT32_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
