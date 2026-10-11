extends RefCounted
## Presentation-only analytic shapes. All positions derive from accepted event
## age; no particle process, Timer, wall clock, or accumulated integration.
const SEGMENTS := 32
const BANDS := 8
const DROPLETS := 24

static func mesh_from(vertices: PackedVector3Array, uvs: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array) -> ArrayMesh:
	if indices.is_empty(): return null
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func height(water: Callable, p: Vector2, time: float) -> float:
	var value := float(water.call(p.x,p.y,time))
	return value if is_finite(value) else 0.0

static func sea(filter: Callable, p: Vector2) -> bool:
	return not filter.is_valid() or bool(filter.call(p.x,p.y))

static func droplet_mesh() -> ArrayMesh:
	# Two crossed, thin strips retain the streak texture from every azimuth.
	# They move in world space; camera rotation never rotates this geometry.
	var vertices := PackedVector3Array([Vector3(-0.075,-0.17,0),Vector3(0.075,-0.17,0),Vector3(-0.075,0.17,0),Vector3(0.075,0.17,0),Vector3(0,-0.17,-0.075),Vector3(0,-0.17,0.075),Vector3(0,0.17,-0.075),Vector3(0,0.17,0.075)])
	var uvs := PackedVector2Array([Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,0),Vector2(0,1),Vector2(1,1),Vector2(0,0),Vector2(1,0)])
	var colors := PackedColorArray(); colors.resize(8); colors.fill(Color.WHITE)
	return mesh_from(vertices,uvs,colors,PackedInt32Array([0,2,1,1,2,3,4,6,5,5,6,7]))

static func surface_froth(origin: Vector2, radius: float, now: float, water: Callable, filter: Callable) -> ArrayMesh:
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var colors := PackedColorArray(); var indices := PackedInt32Array(); var wet: Array[bool] = []
	for band in BANDS+1:
		var t := float(band)/BANDS
		for segment in SEGMENTS+1:
			var angle := TAU*segment/SEGMENTS; var offset := Vector2(cos(angle),sin(angle))*t
			var p := origin+offset*radius*(0.94+0.06*sin(angle*7.0))
			vertices.append(Vector3(p.x,height(water,p,now)+0.12,p.y)); uvs.append((offset+Vector2.ONE)*1.5)
			colors.append(Color(1,1,1,1.0-smoothstep(0.30,1.0,t))); wet.append(sea(filter,p))
	for band in BANDS:
		for segment in SEGMENTS:
			var a := band*(SEGMENTS+1)+segment; var b := a+SEGMENTS+1
			if wet[a] and wet[b] and wet[a+1]: indices.append_array(PackedInt32Array([a,b,a+1]))
			if wet[a+1] and wet[b] and wet[b+1]: indices.append_array(PackedInt32Array([a+1,b,b+1]))
	return mesh_from(vertices,uvs,colors,indices)

static func build(origin: Vector3, age: float, now: float, umbrella: bool, water: Callable, filter: Callable, size: float = 1.0) -> ArrayMesh:
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var colors := PackedColorArray(); var indices := PackedInt32Array(); var wet: Array[bool] = []
	var rise := smoothstep(0.0,0.18,age)
	var collapse := 1.0-smoothstep(0.25,0.95,age)
	var top := (0.18+4.0*rise*collapse)*size
	var spread := (0.3+age*3.7)*size
	for band in BANDS+1:
		var t := float(band)/BANDS
		for segment in SEGMENTS+1:
			var u := float(segment)/SEGMENTS; var angle := TAU*u
			var irregular := 1.0+0.09*sin(angle*5.0+age*3.0)+0.04*cos(angle*9.0)
			var radius := spread*t if umbrella else (0.30+0.18*sin(t*PI)+0.36*pow(t,5.0))*irregular*size
			var p := Vector2(origin.x,origin.z)+Vector2(cos(angle),sin(angle))*radius
			var y := origin.y+top*(1.0-0.46*t*t)+0.14*sin(angle*7.0)*t*size if umbrella else origin.y+top*t
			if not umbrella and band == 0: y = height(water,p,now)+0.10
			var alpha := smoothstep(0.0,0.13,t)*(1.0-smoothstep(0.83,1.0,t)) if umbrella else 0.55+0.35*sin(t*PI)
			vertices.append(Vector3(p.x,y,p.y)); uvs.append(Vector2(u*3.0,t))
			colors.append(Color(1.0,1.0,1.0,alpha)); wet.append(sea(filter,p))
			if band < BANDS and segment < SEGMENTS:
				var a := band*(SEGMENTS+1)+segment; var b := a+SEGMENTS+1
				indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	# Drop land-touching triangles rather than masking only their center.
	var valid := PackedInt32Array()
	for i in range(0,indices.size(),3):
		if wet[indices[i]] and wet[indices[i+1]] and wet[indices[i+2]]:
			valid.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
	return mesh_from(vertices,uvs,colors,valid)

static func update_droplets(pool: MultiMesh, origin: Vector3, age: float, seed: int, now: float, water: Callable, filter: Callable, size: float = 1.0) -> Dictionary:
	var active := 0
	var positions: Array[Vector3] = []
	for index in DROPLETS:
		# Deterministic slots also reconstruct births skipped by large accepted dt.
		var fraction := float(index)/DROPLETS
		var birth := 0.033+fraction*0.067; var elapsed := age-birth
		var lifetime := (0.55+0.18*float(index%5)/4.0)*sqrt(size)
		var angle := TAU*fraction+float(seed%97)*0.071
		var horizontal := (1.7+float(index%7)*0.22)*sqrt(size)
		var velocity := Vector3(cos(angle)*horizontal,(5.1+float(index%4)*0.55)*sqrt(size),sin(angle)*horizontal)
		var p := origin+velocity*maxf(0.0,elapsed)+Vector3(0.0,-4.905*elapsed*elapsed,0.0)
		var wet := sea(filter,Vector2(p.x,p.z))
		var alive := elapsed >= 0.0 and elapsed < lifetime and wet
		if elapsed > 0.15 and p.y < height(water,Vector2(p.x,p.z),now): alive = false
		var fade := (1.0-smoothstep(lifetime*0.45,lifetime,elapsed)) if alive else 0.0
		var scale := Vector3(0.8,1.2,0.8)*(0.55+float(index%3)*0.18)*size if alive else Vector3.ZERO
		var direction := velocity+Vector3(0,-9.81*maxf(0.0,elapsed),0)
		var basis := Basis(Quaternion(Vector3.UP,direction.normalized())).scaled(scale)
		pool.set_instance_transform(index,Transform3D(basis,p))
		pool.set_instance_color(index,Color(0.86,0.97,1.0,fade*0.80))
		if alive: active += 1; positions.append(p)
	return {"active":active,"positions":positions}
