extends RefCounted
## Direct spread grid/Float32 footprint port of demo/model.mjs oceanMesh().

const SOURCE_RENDER_WAVES := [[1.0,.2,.32,18.0],[-.3,1.0,.18,11.0],[.7,.7,.14,7.0],[-1.0,.4,.09,4.2]]

static func wave_uniforms() -> Array[Vector4]:
	# Render data is owned by this layer. CPU physics independently implements
	# the same source profile; fixture tests guard the exact Float32 upload contract.
	var result: Array[Vector4] = []
	for wave: Array in SOURCE_RENDER_WAVES:
		var direction_length := sqrt(float(wave[0])*float(wave[0])+float(wave[1])*float(wave[1]))
		result.append(Vector4(float(wave[0])/direction_length,float(wave[1])/direction_length,wave[2],TAU/float(wave[3])))
	return result

static func _spread(value: float) -> float:
	var x := absf(value)/400.0
	return signf(value)*(x/.7*120.0 if x<=.7 else 120.0+pow((x-.7)/.3,2.0)*880.0)

static func ocean_arrays(resolution: int = 192) -> Dictionary:
	if resolution<1 or resolution>254: return {}
	var side := resolution+1
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var footprint := PackedFloat32Array()
	var uv := PackedVector2Array()
	var indices := PackedInt32Array()
	positions.resize(side*side); normals.resize(side*side); footprint.resize(side*side); uv.resize(side*side)
	for z in side:
		for x in side:
			# Original terrainMesh stores the regular positions in Float32 before spread.
			var regular := Vector3((float(x)/resolution-.5)*800.0,0.0,(float(z)/resolution-.5)*800.0)
			positions[z*side+x]=Vector3(_spread(regular.x),0.0,_spread(regular.z))
			normals[z*side+x]=Vector3.UP
	for z in side:
		for x in side:
			var center := positions[z*side+x]
			var spacing := maxf(maxf(absf(positions[z*side+mini(x+1,resolution)].x-center.x),absf(center.x-positions[z*side+maxi(x-1,0)].x)),maxf(absf(positions[mini(z+1,resolution)*side+x].z-center.z),absf(center.z-positions[maxi(z-1,0)*side+x].z)))
			footprint[z*side+x]=spacing
			# Godot UV.x substitutes the standalone aFootprint vertex attribute.
			uv[z*side+x]=Vector2(spacing,0.0)
	for z in resolution:
		for x in resolution:
			var a := z*side+x
			var b := a+1
			var c := a+side
			var d := c+1
			indices.append_array(PackedInt32Array([a,c,b,b,c,d]))
	return {"positions":positions,"normals":normals,"footprint":footprint,"uv":uv,"indices":indices}

static func ocean_mesh(resolution: int=192) -> ArrayMesh:
	var data := ocean_arrays(resolution)
	if data.is_empty(): return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=data.positions
	arrays[Mesh.ARRAY_NORMAL]=data.normals
	arrays[Mesh.ARRAY_TEX_UV]=data.uv
	arrays[Mesh.ARRAY_INDEX]=data.indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh
