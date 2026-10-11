extends RefCounted
## Direct port of island-water/demo/model.mjs. The palette indices remain
## original data; extent/heightScale/seaIndex are explicit demo display choices.

const DEFAULT_DATA := "res://assets/data/reference_cat_island_h.json"
const DEFAULT_RESOLUTION := 160
const OUTSIDE_HEIGHT := -20.0

static func load_field(path: String = DEFAULT_DATA) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return {}
	var field: Dictionary = parsed
	field.extent = 160.0
	field.heightScale = 0.35
	field.seaIndex = 128.0
	field.terrainResolution = DEFAULT_RESOLUTION
	return field if is_valid_field(field) else {}

static func is_valid_field(field: Dictionary) -> bool:
	if not _dimensions_valid(field):
		return false
	for value in field.values:
		if not _number(value) or not is_finite(float(value)) or value < 0 or value > 255 or floor(float(value)) != float(value):
			return false
	return true

static func _number(value: Variant) -> bool:
	return value is int or value is float

static func _dimensions_valid(field: Dictionary) -> bool:
	for key: String in ["width", "height", "extent", "heightScale", "seaIndex"]:
		if not field.has(key) or not _number(field[key]) or not is_finite(float(field[key])):
			return false
	if field.width < 2 or field.height < 2 or floor(float(field.width)) != float(field.width) or floor(float(field.height)) != float(field.height):
		return false
	if field.extent <= 0 or field.heightScale < 0:
		return false
	return field.has("values") and field.values is Array and field.values.size() == int(field.width) * int(field.height)

static func _resolution_valid(resolution: int) -> bool:
	return resolution >= 1 and resolution <= 254

static func height_at(field: Dictionary, x: float, z: float) -> float:
	if not _dimensions_valid(field) or not is_finite(x) or not is_finite(z):
		return OUTSIDE_HEIGHT
	var u: float = x / float(field.extent) + 0.5
	var v: float = z / float(field.extent) + 0.5
	if u < 0 or u > 1 or v < 0 or v > 1:
		return OUTSIDE_HEIGHT
	var width: int = int(field.width)
	var height: int = int(field.height)
	var px: float = u * (width - 1)
	var py: float = v * (height - 1)
	var ix: int = int(floor(px))
	var iy: int = int(floor(py))
	var ax: float = px - ix
	var ay: float = py - iy
	var values: Array = field.values
	var a: float = float(values[mini(iy,height-1)*width+mini(ix,width-1)])
	var b: float = float(values[mini(iy,height-1)*width+mini(ix+1,width-1)])
	var c: float = float(values[mini(iy+1,height-1)*width+mini(ix,width-1)])
	var d: float = float(values[mini(iy+1,height-1)*width+mini(ix+1,width-1)])
	var raw: float = (a*(1-ax)+b*ax)*(1-ay)+(c*(1-ax)+d*ax)*ay
	return (raw-float(field.seaIndex))*float(field.heightScale)

static func mesh_height_at(field: Dictionary, x: float, z: float, resolution: int = DEFAULT_RESOLUTION) -> float:
	if not _dimensions_valid(field) or not _resolution_valid(resolution) or not is_finite(x) or not is_finite(z):
		return OUTSIDE_HEIGHT
	var u: float = x/float(field.extent)+0.5
	var v: float = z/float(field.extent)+0.5
	if u < 0 or u > 1 or v < 0 or v > 1:
		return OUTSIDE_HEIGHT
	var px: float = u*resolution
	var py: float = v*resolution
	var ix: int = mini(int(floor(px)),resolution-1)
	var iy: int = mini(int(floor(py)),resolution-1)
	var ax: float = px-ix
	var ay: float = py-iy
	# R32F lookup stores the drawn Float32 vertex heights, as renderer.mjs does.
	var a: float = _vertex_height(field,ix,iy,resolution)
	var b: float = _vertex_height(field,ix+1,iy,resolution)
	var c: float = _vertex_height(field,ix,iy+1,resolution)
	var d: float = _vertex_height(field,ix+1,iy+1,resolution)
	return a+(b-a)*ax+(c-a)*ay if ax+ay <= 1 else d+(c-d)*(1-ax)+(b-d)*(1-ay)

static func _vertex_height(field: Dictionary, x: int, z: int, resolution: int) -> float:
	return PackedFloat32Array([height_at(field,(float(x)/resolution-0.5)*float(field.extent),(float(z)/resolution-0.5)*float(field.extent))])[0]

static func terrain_arrays(field: Dictionary, resolution: int = DEFAULT_RESOLUTION) -> Dictionary:
	if not is_valid_field(field) or not _resolution_valid(resolution):
		return {}
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	var count: int = (resolution+1)*(resolution+1)
	positions.resize(count)
	normals.resize(count)
	uv.resize(count)
	indices.resize(resolution*resolution*6)
	var extent: float = float(field.extent)
	var step: float = extent/resolution
	for z: int in range(resolution+1):
		for x: int in range(resolution+1):
			var wx: float = (float(x)/resolution-0.5)*extent
			var wz: float = (float(z)/resolution-0.5)*extent
			var index: int = z*(resolution+1)+x
			positions[index] = Vector3(wx,height_at(field,wx,wz),wz)
			uv[index] = Vector2(float(x)/resolution,float(z)/resolution)
			var nx: float = (_clamped_height(field,wx-step*0.5,wz)-_clamped_height(field,wx+step*0.5,wz))/step
			var nz: float = (_clamped_height(field,wx,wz-step*0.5)-_clamped_height(field,wx,wz+step*0.5))/step
			var length: float = sqrt(nx*nx+1+nz*nz)
			normals[index] = Vector3(nx/length,1/length,nz/length)
	for z: int in range(resolution):
		for x: int in range(resolution):
			var a: int = z*(resolution+1)+x
			var b: int = a+1
			var c: int = a+resolution+1
			var d: int = c+1
			var offset: int = (z*resolution+x)*6
			for i: int in range(6):
				indices[offset+i] = [a,c,b,b,c,d][i]
	return {"positions":positions,"normals":normals,"uv":uv,"indices":indices}

static func _clamped_height(field: Dictionary, x: float, z: float) -> float:
	var extent: float = float(field.extent)*0.5
	return height_at(field,clampf(x,-extent,extent),clampf(z,-extent,extent))

static func terrain_mesh(field: Dictionary, resolution: int = DEFAULT_RESOLUTION) -> ArrayMesh:
	return _array_mesh(terrain_arrays(field,resolution))

static func seabed_arrays(field: Dictionary, segments: int = 64) -> Dictionary:
	if not is_valid_field(field) or segments < 1 or segments > 3276:
		return {}
	var rings := [0.5,0.65,0.9,1.5,3.0]
	var count: int = segments*4
	var raw_positions := PackedFloat64Array()
	var raw_normals := PackedFloat64Array()
	var indices := PackedInt32Array()
	raw_positions.resize(rings.size()*count*3)
	raw_normals.resize(raw_positions.size())
	for ring: int in range(rings.size()):
		for i: int in range(count):
			var edge: int = i/segments
			var s: float = float(i%segments)/segments*2-1
			var r: float = float(field.extent)*float(rings[ring])
			var p: Array = [[s*r,-r],[r,s*r],[-s*r,r],[-r,-s*r]][edge]
			var h: float = height_at(field,float(p[0])/r*float(field.extent)*0.5,float(p[1])/r*float(field.extent)*0.5) if ring == 0 else [0.0,-16.0,-30.0,-60.0,-80.0][ring]
			var offset: int = (ring*count+i)*3
			raw_positions[offset] = p[0]
			raw_positions[offset+1] = h
			raw_positions[offset+2] = p[1]
	for ring: int in range(rings.size()-1):
		for i: int in range(count):
			var a: int = ring*count+i
			var b: int = ring*count+(i+1)%count
			var d: int = (ring+1)*count+i
			var c: int = (ring+1)*count+(i+1)%count
			indices.append_array(PackedInt32Array([a,b,d,b,c,d]))
	for i: int in range(0,indices.size(),3):
		var a: int = indices[i]*3
		var b: int = indices[i+1]*3
		var c: int = indices[i+2]*3
		var vx: float = raw_positions[b]-raw_positions[a]
		var vy: float = raw_positions[b+1]-raw_positions[a+1]
		var vz: float = raw_positions[b+2]-raw_positions[a+2]
		var wx: float = raw_positions[c]-raw_positions[a]
		var wy: float = raw_positions[c+1]-raw_positions[a+1]
		var wz: float = raw_positions[c+2]-raw_positions[a+2]
		var n: Array = [vy*wz-vz*wy,vz*wx-vx*wz,vx*wy-vy*wx]
		for index: int in [a,b,c]:
			for k: int in range(3):
				raw_normals[index+k] += n[k]
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	positions.resize(rings.size()*count)
	normals.resize(positions.size())
	for i: int in range(positions.size()):
		var k: int = i*3
		positions[i] = Vector3(raw_positions[k],raw_positions[k+1],raw_positions[k+2])
		var nx: float = raw_normals[k]
		var ny: float = raw_normals[k+1]
		var nz: float = raw_normals[k+2]
		var length: float = sqrt(nx*nx+ny*ny+nz*nz)
		if length == 0:
			length = 1
		normals[i] = Vector3(nx/length,ny/length,nz/length)
	return {"positions":positions,"normals":normals,"indices":indices}

static func seabed_mesh(field: Dictionary, segments: int = 64) -> ArrayMesh:
	return _array_mesh(seabed_arrays(field,segments))

static func _array_mesh(data: Dictionary) -> ArrayMesh:
	if data.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = data.positions
	arrays[Mesh.ARRAY_NORMAL] = data.normals
	if data.has("uv"):
		arrays[Mesh.ARRAY_TEX_UV] = data.uv
	arrays[Mesh.ARRAY_INDEX] = data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func height_texture(field: Dictionary, resolution: int = DEFAULT_RESOLUTION) -> ImageTexture:
	var terrain: Dictionary = terrain_arrays(field,resolution)
	if terrain.is_empty():
		return null
	var heights := PackedFloat32Array()
	heights.resize(terrain.positions.size())
	for i: int in range(heights.size()):
		heights[i] = terrain.positions[i].y
	var image := Image.create_from_data(resolution+1,resolution+1,false,Image.FORMAT_RF,heights.to_byte_array())
	return ImageTexture.create_from_image(image)
