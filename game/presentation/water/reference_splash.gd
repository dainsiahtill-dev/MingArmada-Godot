extends Node3D
## Additional source layer; the existing readable impact volume stays intact.
## Source shapes, controller keys and eight emitter profiles are imported once.
## Deterministic slots are reconstructed from absolute accepted event age.

const DATA_PATH := "res://assets/data/reference_cannon_splash.json"
const ShaderSource = preload("res://game/presentation/water/reference_splash.gdshader")
const Volume = preload("res://game/presentation/water/splash_volume.gd")
const METRES_PER_UNIT := .01
const COLUMN_GAIN := 18.0
const RING_GAIN := .35
const PARTICLE_GAIN := .40
static var _asset: Dictionary = {}
var _geometry: Node3D
var _particles: Node3D
var _meshes: Array[Dictionary] = []
var _systems: Array[Dictionary] = []
var _origin := Vector3.ZERO
var _size := 1.0
var _seed := 0
var _water: Callable
var _sea: Callable
var _age := -1.0
var _accepted_time := -1.0
var _positions: Array[Vector3] = []

func configure(origin: Vector3, size: float, seed: int, water: Callable, sea: Callable = Callable()) -> bool:
	if not origin.is_finite() or not is_finite(size) or size <= 0.0 or not water.is_valid(): return false
	if _asset.is_empty():
		var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
		if not value is Dictionary or value.get("meshes",[]).size()!=7 or value.get("systems",[]).size()!=8: return false
		_asset = value
	dispose()
	_origin=origin; _size=size; _seed=seed; _water=water; _sea=sea
	_geometry=Node3D.new(); _geometry.name="SourceGeometry"; add_child(_geometry)
	_particles=Node3D.new(); _particles.name="SourceParticles"; add_child(_particles)
	for profile: Dictionary in _asset.meshes:
		var node := MeshInstance3D.new()
		node.name=profile.name if profile.name.begins_with("Cylinder") else "SourceRing_%d"%int(profile.block_id)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := _material(profile.texture)
		material.render_priority=4 if profile.name.begins_with("Cylinder") else 3
		node.material_override=material; _geometry.add_child(node)
		_meshes.append({"node":node,"material":material,"profile":profile})
	for profile: Dictionary in _asset.systems:
		var node := MultiMeshInstance3D.new()
		node.name="AuthoredSystem_%d"%int(profile.id)
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var material := _material(profile.texture)
		var mist: bool=String(profile.texture).contains("mist")
		material.set_shader_parameter("billboard",mist)
		material.set_shader_parameter("opacity",PARTICLE_GAIN)
		material.render_priority=5
		var mesh: ArrayMesh=_particle_carrier(mist)
		mesh.surface_set_material(0,material)
		var pool := MultiMesh.new()
		pool.transform_format=MultiMesh.TRANSFORM_3D; pool.use_colors=true
		pool.mesh=mesh; pool.instance_count=int(profile.capacity)
		node.multimesh=pool; _particles.add_child(node)
		_systems.append({"node":node,"pool":pool,"profile":profile,"births":_births(profile),"mist":mist})
	return true

func configure_surface_filter(sea_at: Callable) -> void:
	_sea=sea_at

func _material(texture_name: String) -> ShaderMaterial:
	var material := ShaderMaterial.new(); material.shader=ShaderSource
	material.set_shader_parameter("foam_texture",load("res://assets/textures/pirates_reference/"+texture_name))
	material.set_shader_parameter("foam_tint",Color(.83,.96,1))
	return material

func apply_snapshot(age: float, accepted_time: float) -> bool:
	if _geometry==null or not is_finite(age) or age < 0.0 or not is_finite(accepted_time) or accepted_time < 0.0: return false
	if age==_age and accepted_time==_accepted_time: return true
	_age=age; _accepted_time=accepted_time; _positions.clear()
	for entry: Dictionary in _meshes: _update_mesh(entry,age,accepted_time)
	for entry: Dictionary in _systems: _update_system(entry,age,accepted_time)
	return true

func _update_mesh(entry: Dictionary, age: float, now: float) -> void:
	var profile: Dictionary=entry.profile
	var local: Dictionary=profile.local_transform
	var transform := _matrix(local.rotation)
	var translation := _array_vector(local.translation)
	var parent := Transform3D.IDENTITY
	if not profile.animation.is_empty():
		var animation: Dictionary=profile.animation
		var angles := Vector3(_scalar(animation.rotations[0],age),_scalar(animation.rotations[1],age),_scalar(animation.rotations[2],age))
		parent=Transform3D(Basis.from_euler(angles,EULER_ORDER_XYZ).scaled(Vector3.ONE*_scalar(animation.scales,age)),_vector_keys(animation.translations,age))
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var colors := PackedColorArray(); var wet: Array[bool]=[]
	var ring: bool=profile.name != "Cylinder01" and profile.name != "Cylinder02"
	for index: int in profile.vertices.size():
		var point: Vector3=parent*(transform*_array_vector(profile.vertices[index])*float(local.scale)+translation)
		point=_origin+_to_godot(point)*METRES_PER_UNIT*_size
		if ring: point.y=Volume.height(_water,Vector2(point.x,point.z),now)+.14
		vertices.append(point)
		uvs.append(Vector2(profile.uv_sets[0][index][0],profile.uv_sets[0][index][1]))
		colors.append(Color.WHITE); wet.append(Volume.sea(_sea,Vector2(point.x,point.z)))
	var indices := PackedInt32Array()
	for triangle: Array in profile.triangles:
		var a: int=int(triangle[0]); var b: int=int(triangle[1]); var c: int=int(triangle[2])
		if wet[a] and wet[b] and wet[c]: indices.append_array(PackedInt32Array([a,c,b]))
	entry.node.mesh=Volume.mesh_from(vertices,uvs,colors,indices)
	var alpha: float=_scalar(profile.alphaKeys,age,float(profile.alpha))
	entry.material.set_shader_parameter("opacity",alpha*(RING_GAIN if ring else COLUMN_GAIN))
	var uv := Vector2.ZERO
	if not profile.uvKeys.is_empty():
		var scroll: float=_scalar(profile.uvKeys,age)
		if int(profile.uvOperation)==1: uv.y=scroll
		else: uv.x=scroll
	entry.material.set_shader_parameter("uv_offset",uv)
	entry.node.visible=entry.node.mesh!=null and alpha>0.00001

func _update_system(entry: Dictionary, age: float, now: float) -> void:
	var profile: Dictionary=entry.profile
	var emitter: Dictionary=profile.emitter
	var emit_matrix := _matrix(profile.emitterMatrix)
	var base: Vector3=_origin+_to_godot(_array_vector(profile.emitterTranslation))*METRES_PER_UNIT*_size
	var acceleration: Vector3=_to_godot(_array_vector(profile.acceleration))*METRES_PER_UNIT
	for slot: int in int(profile.capacity):
		var elapsed: float=age-float(entry.births[slot]) if slot<entry.births.size() else -1.0
		var lifetime: float=float(emitter.life_span)
		var seed: int=_seed+int(profile.id)*977+slot*71
		# The asset does not establish its random distribution. Stable uniform
		# variation is a documented game choice; life variation is not invented.
		var speed: float=maxf(0,float(emitter.speed)+(2*_random(seed)-1)*float(emitter.speed_variation))
		var cone: float=float(emitter.declination)+(2*_random(seed+1)-1)*float(emitter.declination_variation)
		var angle: float=float(emitter.planar_angle)+(2*_random(seed+2)-1)*float(emitter.planar_angle_variation)
		var direction := Vector3(sin(cone)*cos(angle),sin(cone)*sin(angle),cos(cone))
		var velocity: Vector3=_to_godot(emit_matrix*direction)*speed*METRES_PER_UNIT*sqrt(_size)
		var t: float=maxf(0,elapsed)
		var point: Vector3=base+velocity*t+.5*acceleration*t*t
		var color: Color=_color_keys(profile.colorKeys,t)
		var grow: float=float(profile.grow.grow_time)
		var growth: float=minf(1,t/grow) if grow>0 else 1.0
		var fade: float=float(profile.grow.fade_time)
		if fade>0: growth*=clampf((lifetime-t)/fade,0,1)
		var radius: float=float(emitter.initial_radius)*METRES_PER_UNIT*_size*growth
		var alive: bool=elapsed>=0 and elapsed<lifetime and color.a>0.00001 and radius>0.00001 and Volume.sea(_sea,Vector2(point.x,point.z))
		if elapsed>.15 and point.y<Volume.height(_water,Vector2(point.x,point.z),now): alive=false
		var current_velocity: Vector3=velocity+acceleration*t
		var basis: Basis=Basis.IDENTITY if entry.mist else Basis(Quaternion(Vector3.UP,current_velocity.normalized()))
		basis=basis.scaled(Vector3.ONE*radius if alive else Vector3.ZERO)
		entry.pool.set_instance_transform(slot,Transform3D(basis,point))
		entry.pool.set_instance_color(slot,color if alive else Color(1,1,1,0))
		if alive: _positions.append(point)

static func _births(profile: Dictionary) -> Array[float]:
	var result: Array[float]=[]
	var keys: Array=profile.enabledKeys
	for index: int in keys.size()-1:
		if int(keys[index].value)!=1: continue
		var begin: float=float(keys[index].time)
		var end: float=float(keys[index+1].time)
		var rate: float=_scalar(profile.birthRateKeys,begin)
		if rate<=0: continue
		for slot: int in int(ceil((end-begin)*rate)):
			var born: float=begin+slot/rate
			if born<end and result.size()<int(profile.capacity): result.append(born)
	return result

static func _scalar(keys: Array, time: float, fallback: float = 0.0) -> float:
	if keys.is_empty(): return fallback
	if time<=float(keys[0].time): return float(keys[0].value)
	for index: int in range(1,keys.size()):
		if time<=float(keys[index].time):
			var a: Dictionary=keys[index-1]; var b: Dictionary=keys[index]
			return lerpf(float(a.value),float(b.value),(time-float(a.time))/(float(b.time)-float(a.time)))
	return float(keys.back().value)

static func _vector_keys(keys: Array, time: float) -> Vector3:
	if keys.is_empty(): return Vector3.ZERO
	if time<=float(keys[0].time): return _named_vector(keys[0].value)
	for index: int in range(1,keys.size()):
		if time<=float(keys[index].time):
			var a: Dictionary=keys[index-1]; var b: Dictionary=keys[index]
			return _named_vector(a.value).lerp(_named_vector(b.value),(time-float(a.time))/(float(b.time)-float(a.time)))
	return _named_vector(keys.back().value)

static func _color_keys(keys: Array, time: float) -> Color:
	if keys.is_empty(): return Color.WHITE
	if time<=float(keys[0].time): return _named_color(keys[0].value)
	for index: int in range(1,keys.size()):
		if time<=float(keys[index].time):
			var a: Dictionary=keys[index-1]; var b: Dictionary=keys[index]
			return _named_color(a.value).lerp(_named_color(b.value),(time-float(a.time))/(float(b.time)-float(a.time)))
	return _named_color(keys.back().value)

static func _random(seed: int) -> float:
	var value: float=sin(float(seed)*12.9898)*43758.5453
	return value-floor(value)
static func _named_vector(value: Dictionary) -> Vector3: return Vector3(value.x,value.y,value.z)
static func _named_color(value: Dictionary) -> Color: return Color(value.r,value.g,value.b,value.a)
static func _array_vector(value: Array) -> Vector3: return Vector3(value[0],value[1],value[2])
static func _to_godot(value: Vector3) -> Vector3: return Vector3(value.x,value.z,-value.y)
static func _matrix(rows: Array) -> Basis:
	return Basis(Vector3(rows[0][0],rows[1][0],rows[2][0]),Vector3(rows[0][1],rows[1][1],rows[2][1]),Vector3(rows[0][2],rows[1][2],rows[2][2]))

static func _particle_carrier(mist: bool) -> ArrayMesh:
	if not mist:
		var vertices := PackedVector3Array([Vector3(-.18,-1,0),Vector3(.18,-1,0),Vector3(-.18,1,0),Vector3(.18,1,0),Vector3(0,-1,-.18),Vector3(0,-1,.18),Vector3(0,1,-.18),Vector3(0,1,.18)])
		var uvs := PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,0)])
		var colors := PackedColorArray(); colors.resize(8); colors.fill(Color.WHITE)
		return Volume.mesh_from(vertices,uvs,colors,PackedInt32Array([0,2,1,1,2,3,4,6,5,5,6,7]))
	var vertices := PackedVector3Array([Vector3.ZERO]); var uvs := PackedVector2Array([Vector2(.5,.5)])
	var colors := PackedColorArray([Color.WHITE]); var indices := PackedInt32Array()
	for band: int in range(1,5):
		var radius: float=band/4.0
		for segment: int in 24:
			var angle: float=TAU*segment/24.0
			var p := Vector2(cos(angle),sin(angle))*radius
			vertices.append(Vector3(p.x,p.y,0)); uvs.append(Vector2(.5,.5)+p*.5)
			colors.append(Color(1,1,1,1-smoothstep(.25,1,radius)))
			var a: int=1+(band-1)*24+segment
			var b: int=1+(band-1)*24+(segment+1)%24
			if band==1: indices.append_array(PackedInt32Array([0,a,b]))
			else: indices.append_array(PackedInt32Array([a-24,a,b-24,b-24,a,b]))
	return Volume.mesh_from(vertices,uvs,colors,indices)

func diagnostics() -> Dictionary:
	var capacity := 0
	for entry: Dictionary in _systems: capacity+=int(entry.profile.capacity)
	return {"meshes":_meshes.size(),"systems":_systems.size(),"capacity":capacity,"particles":_positions.size(),"positions":_positions.duplicate(),"age":_age,"accepted_time":_accepted_time}

func dispose() -> void:
	if is_instance_valid(_geometry): _geometry.free()
	if is_instance_valid(_particles): _particles.free()
	_geometry=null; _particles=null; _meshes.clear(); _systems.clear(); _positions.clear()
	_water=Callable(); _sea=Callable(); _age=-1.0; _accepted_time=-1.0

func _exit_tree() -> void: dispose()
