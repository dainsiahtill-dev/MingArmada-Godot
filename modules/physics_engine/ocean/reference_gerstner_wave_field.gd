extends RefCounted
## Direct CPU port of island-water/demo/model.mjs. Original five-wave profiles
## remain independent. Parametric XZ and displaced world XZ are explicit APIs.

const Q := .42
const WAVES := [
	{"direction":[1.0,.2],"amplitude":.32,"length":18.0,"speed":1.4},
	{"direction":[-.3,1.0],"amplitude":.18,"length":11.0,"speed":1.8},
	{"direction":[.7,.7],"amplitude":.14,"length":7.0,"speed":2.2},
	{"direction":[-1.0,.4],"amplitude":.09,"length":4.2,"speed":2.8},
]
var tide := 0.0
var strength := 1.0
var footprint := 0.0
var enabled := true

func configure(state: Dictionary = {}) -> bool:
	for key: String in ["tide","strength","footprint"]:
		if state.has(key) and not is_finite(float(state[key])): return false
	tide=float(state.get("tide",tide))
	strength=clampf(float(state.get("strength",strength)),0.0,2.0)
	footprint=maxf(0.0,float(state.get("footprint",footprint)))
	enabled=bool(state.get("waves",enabled))
	return true

static func wave_visibility(length: float, spacing: float = 0.0) -> float:
	var a := clampf((spacing-length*.25)/(length*.25),0.0,1.0)
	return 1.0-a*a*(3.0-2.0*a)

static func descriptors() -> Array[Vector4]:
	var result: Array[Vector4] = []
	for w: Dictionary in WAVES:
		var length := sqrt(float(w.direction[0])*float(w.direction[0])+float(w.direction[1])*float(w.direction[1]))
		result.append(Vector4(float(w.direction[0])/length,float(w.direction[1])/length,w.amplitude,TAU/float(w.length)))
	return result

static func _evaluate(x: float,z: float,seconds: float,sea_tide: float,wave_strength: float,spacing: float) -> Dictionary:
	var power := clampf(wave_strength,0.0,2.0)
	var p: Array[float] = [x,sea_tide,z]
	var dx: Array[float] = [1.0,0.0,0.0]
	var dz: Array[float] = [0.0,0.0,1.0]
	for w: Dictionary in WAVES:
		var dir_x: float = w.direction[0]
		var dir_z: float = w.direction[1]
		var length := sqrt(dir_x*dir_x+dir_z*dir_z)
		var a := dir_x/length
		var b := dir_z/length
		var k := TAU/float(w.length)
		var amplitude := float(w.amplitude)*power*wave_visibility(w.length,spacing)
		var phase := k*(a*x+b*z)-float(w.speed)*seconds
		var s := sin(phase)
		var c := cos(phase)
		p[0] += Q*amplitude*a*c; p[1] += amplitude*s; p[2] += Q*amplitude*b*c
		dx[0] -= Q*amplitude*k*a*a*s; dx[1] += amplitude*k*a*c; dx[2] -= Q*amplitude*k*a*b*s
		dz[0] -= Q*amplitude*k*a*b*s; dz[1] += amplitude*k*b*c; dz[2] -= Q*amplitude*k*b*b*s
	var normal: Array[float] = [dz[1]*dx[2]-dz[2]*dx[1],dz[2]*dx[0]-dz[0]*dx[2],dz[0]*dx[1]-dz[1]*dx[0]]
	var normal_length := sqrt(normal[0]*normal[0]+normal[1]*normal[1]+normal[2]*normal[2])
	for axis in 3: normal[axis]/=normal_length
	return {"position":p,"normal":normal,"dx":dx,"dz":dz}

static func wave_at(x: float,z: float,seconds: float,sea_tide: float=0.0,wave_strength: float=1.0,spacing: float=0.0) -> Dictionary:
	var result := _evaluate(x,z,seconds,sea_tide,wave_strength,spacing)
	return {"position":result.position,"normal":result.normal}

func sample(x: float,z: float,seconds: float) -> Dictionary:
	if not is_finite(x) or not is_finite(z) or not is_finite(seconds):
		return {"height":NAN,"normal":Vector3.UP,"gradient":Vector2.ZERO,"residual":INF}
	var base_x := x
	var base_z := z
	var result: Dictionary
	var residual := INF
	# Max steepness at strength 2 remains below one: this smooth surface has a
	# unique local inverse. Newton uses the same analytic derivatives as the normal.
	for _iteration in 12:
		result=_evaluate(base_x,base_z,seconds,tide,strength if enabled else 0.0,footprint)
		var rx: float = float(result.position[0])-x
		var rz: float = float(result.position[2])-z
		residual=maxf(absf(rx),absf(rz))
		if residual <= 1.0e-12: break
		var ax: float = result.dx[0]
		var az: float = result.dz[0]
		var bx: float = result.dx[2]
		var bz: float = result.dz[2]
		var det := ax*bz-az*bx
		base_x -= (bz*rx-az*rz)/det
		base_z -= (-bx*rx+ax*rz)/det
	var normal := Vector3(result.normal[0],result.normal[1],result.normal[2])
	return {"height":float(result.position[1]),"normal":normal,"gradient":Vector2(-normal.x/normal.y,-normal.z/normal.y),"residual":residual,"base":Vector2(base_x,base_z)}

func sample_height(x: float,z: float,seconds: float) -> float: return sample(x,z,seconds).height
