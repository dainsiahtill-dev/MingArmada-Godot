extends SceneTree
# Read-only numeric audit of the real shared modules, no render/capture.
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
const World=preload("res://modules/scene_engine/world/world_view.gd")
const Waves=preload("res://modules/contracts/wave_descriptor.gd")
var camera: Camera3D
var ocean: MeshInstance3D
var material: ShaderMaterial
var ground: Image
var near_ground: Image
var ground_bounds: Vector4
var near_bounds: Vector4
var wave_components: PackedVector4Array
var water_vertices: PackedVector3Array
var screen_vertices: PackedVector2Array
var view_depths: PackedFloat32Array
const SIZE=Vector2(1600,838)
const SEGMENTS=80
func _initialize() -> void: _run.call_deferred()

func rf_height(image: Image,bounds: Vector4,p: Vector2,triangular: bool) -> float:
	var uv: Vector2=(p-Vector2(bounds.x,bounds.y))/Vector2(bounds.z-bounds.x,bounds.w-bounds.y)
	if uv.x<0 or uv.y<0 or uv.x>1 or uv.y>1: return -20.0
	var q:=uv*Vector2(image.get_width()-1,image.get_height()-1)
	var x:=mini(floori(q.x),image.get_width()-2); var y:=mini(floori(q.y),image.get_height()-2)
	var f:=q-Vector2(x,y)
	var a:=image.get_pixel(x,y).r; var b:=image.get_pixel(x+1,y).r; var c:=image.get_pixel(x,y+1).r; var d:=image.get_pixel(x+1,y+1).r
	if triangular: return a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<=1.0 else d+(c-d)*(1-f.x)+(b-d)*(1-f.y)
	return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)
func wave(p: Vector2) -> float:
	var value:=0.0
	for w: Vector4 in wave_components: value+=w.x*sin(p.dot(Vector2(w.y,w.z))+w.w*24.0)
	return value*smoothstep(0.0,8.0,-rf_height(ground,ground_bounds,p,false))
func barycentric(p: Vector2,a: Vector2,b: Vector2,c: Vector2) -> Vector3:
	var determinant: float=(b-a).cross(c-a)
	if absf(determinant)<1e-8: return Vector3(NAN,NAN,NAN)
	var v: float=(p-a).cross(c-a)/determinant; var w: float=(b-a).cross(p-a)/determinant
	return Vector3(1-v-w,v,w)
func sampled_alpha(image: Image,uv: Vector2) -> float:
	var q:=uv.clamp(Vector2.ZERO,Vector2.ONE)*Vector2(image.get_width(),image.get_height())-Vector2(.5,.5)
	var x:=floori(q.x); var y:=floori(q.y); var f:=q-Vector2(x,y)
	var a:=image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y,0,image.get_height()-1)).a
	var b:=image.get_pixel(clampi(x+1,0,image.get_width()-1),clampi(y,0,image.get_height()-1)).a
	var c:=image.get_pixel(clampi(x,0,image.get_width()-1),clampi(y+1,0,image.get_height()-1)).a
	var d:=image.get_pixel(clampi(x+1,0,image.get_width()-1),clampi(y+1,0,image.get_height()-1)).a
	return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)
func water_depth_at(screen: Vector2) -> float:
	var original:=((screen/SIZE-Vector2(.5,.5))/1.2+Vector2(.5,.5))*80.0
	var column:=floori(original.x); var row:=floori(80.0-original.y)
	for y in range(maxi(0,row-2),mini(80,row+3)):
		for x in range(maxi(0,column-2),mini(80,column+3)):
			var a:=y*81+x; var b:=a+81; var c:=b+1; var d:=a+1
			for triangle: Array in [[a,b,d],[b,c,d]]:
				var weights:=barycentric(screen,screen_vertices[triangle[0]],screen_vertices[triangle[1]],screen_vertices[triangle[2]])
				if not weights.is_finite() or weights.x<-.00001 or weights.y<-.00001 or weights.z<-.00001: continue
				return 1.0/(weights.x/view_depths[triangle[0]]+weights.y/view_depths[triangle[1]]+weights.z/view_depths[triangle[2]])
	return NAN

func _run() -> void:
	var geography: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/mingqi-geography.json"))
	var heights:=Height.new(); assert(heights.configure_ports(geography.ports,true,Geography.options()))
	var viewport:=SubViewport.new(); viewport.size=Vector2i(SIZE); root.add_child(viewport)
	camera=Camera3D.new(); viewport.add_child(camera); camera.fov=55; camera.near=.5; camera.far=4000
	camera.position=Vector3(-114.0844,191.0088,201.916); camera.look_at(Vector3(-60,5,390))
	var world:=World.new(); viewport.add_child(world)
	assert(world.configure(heights.sample_height,Waves.original_descriptors(),{"camera":camera,"ports":geography.ports,"visual_style":1,"vegetation":false,"island_details":false,"quality":"high","resolution":96,"chunk_radius":4}))
	world.apply_snapshot({"time":24.0,"focus":Vector2(-60,390)})
	ocean=world.get_ocean(); material=ocean.material_override
	ground=material.get_shader_parameter("shore_height_texture").get_image()
	near_ground=material.get_shader_parameter("reference_near_height_texture").get_image()
	ground_bounds=material.get_shader_parameter("shore_bounds"); near_bounds=material.get_shader_parameter("reference_near_bounds")
	wave_components=material.get_shader_parameter("wave_components")
	var water_arrays: Array=ocean.mesh.surface_get_arrays(0); water_vertices=water_arrays[Mesh.ARRAY_VERTEX]
	screen_vertices.resize(water_vertices.size()); view_depths.resize(water_vertices.size())
	var inverse_camera:=camera.global_transform.affine_inverse()
	for i in water_vertices.size():
		var p:=ocean.global_transform*water_vertices[i]; p.y=wave(Vector2(p.x,p.z))
		screen_vertices[i]=camera.unproject_position(p); view_depths[i]=-(inverse_camera*p).z
	var surf: Node3D=world.get_node("StaticNaturalWorld/AdvancingSurf_forward-supply")
	var field: RefCounted=heights.natural_islands()[2].field
	var counts:={"triangles":0,"folded_triangles":0,"front_cells":0,"front_folded_cells":0,"visible_alpha_samples":0,"potential_ocean_occluded":0,"potential_ocean_clip":0,"left_samples":0,"left_occluded":0,"left_clip":0}
	var min_depth_gap:=INF; var max_depth_gap:=-INF; var maximum_height_error:=0.0
	var sign_count:={"positive":0,"negative":0}; var left_rows: Array=[]; var patch_stats: Array=[]
	var centre_screen:=camera.unproject_position(Vector3(-60,0,390))
	var states: Array=surf.diagnostics().states
	for patch_index in surf.get_child_count():
		var node: MeshInstance3D=surf.get_child(patch_index)
		var arrays: Array=node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]; var uv: PackedVector2Array=arrays[Mesh.ARRAY_TEX_UV]; var indices: PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		var mat: ShaderMaterial=node.material_override
		var source_image: Image=mat.get_shader_parameter("shore_texture").get_image(); if source_image.is_compressed(): source_image.decompress()
		var transform: Basis=mat.get_shader_parameter("texture_matrix")
		var alpha_strength: float=mat.get_shader_parameter("controller_alpha")
		var front_j:=clampi(roundi((float(states[patch_index].frontDistance)-.2)/24.0*20.0),1,19)
		var reversed_progress:=0; var segment_count:=0; var positive_front_triangles:=0; var positive_first_triangles:=0
		var stretch_ratios: Array=[]
		for index in range(0,indices.size(),3):
			var a:=vertices[indices[index]]; var b:=vertices[indices[index+1]]; var c:=vertices[indices[index+2]]
			var cross:=Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z)); counts.triangles+=1
			if cross>0: sign_count.positive+=1
			else: sign_count.negative+=1
			var cell_j:=maxi(indices[index]%21,maxi(indices[index+1]%21,indices[index+2]%21))
			if cross>0 and cell_j in [front_j,front_j+1]: positive_front_triangles+=1
			if cross>0 and cell_j==1: positive_first_triangles+=1
			# Built [a,b,c,c,b,d] triangles have a consistent expected winding.
			if cross<0: counts.folded_triangles+=1
		for row in vertices.size()/21-1:
			var i: int=int(row)*21+front_j; var a:=vertices[i]; var b:=vertices[i+21]; var c:=vertices[i-1]; var d:=vertices[i+20]
			var coast_a:=vertices[int(row)*21]; var coast_b:=vertices[(int(row)+1)*21]
			var coast_delta:=Vector2(coast_b.x-coast_a.x,coast_b.z-coast_a.z)
			var front_delta:=Vector2(b.x-a.x,b.z-a.z)
			segment_count+=1
			if front_delta.dot(coast_delta)<0: reversed_progress+=1
			if coast_delta.length()>.00001: stretch_ratios.append(front_delta.length()/coast_delta.length())
			var one:=Vector2(b.x-a.x,b.z-a.z).cross(Vector2(c.x-a.x,c.z-a.z))
			var two:=Vector2(b.x-c.x,b.z-c.z).cross(Vector2(d.x-c.x,d.z-c.z))
			counts.front_cells+=1
			if one*two<0: counts.front_folded_cells+=1
		for row in vertices.size()/21:
			var i: int=int(row)*21+front_j; var v:=vertices[i]; var p:=Vector2(v.x,v.z)
			var transformed_uv:=transform*Vector3(uv[i].x,uv[i].y,1)
			var alpha:=sampled_alpha(source_image,Vector2(transformed_uv.x,transformed_uv.y))*alpha_strength
			if alpha<.02: continue
			var h:=wave(p); var screen:=camera.unproject_position(Vector3(p.x,h+.055,p.y))
			if screen.x<0 or screen.x>1600 or screen.y<0 or screen.y>838: continue
			counts.visible_alpha_samples+=1
			var sample_depth:=water_depth_at(screen)
			var surf_depth:=-(inverse_camera*Vector3(p.x,h+.055,p.y)).z
			var gap:=surf_depth-sample_depth
			min_depth_gap=minf(min_depth_gap,gap); max_depth_gap=maxf(max_depth_gap,gap)
			var local_height: float=field.sample_triangle_height(p.x,p.y)
			var ocean_ground:=rf_height(near_ground,near_bounds,p,true)
			maximum_height_error=maxf(maximum_height_error,absf(local_height-ocean_ground))
			var ocean_clip:=ocean_ground>.035
			if gap>0: counts.potential_ocean_occluded+=1
			if ocean_clip: counts.potential_ocean_clip+=1
			if screen.x<centre_screen.x:
				counts.left_samples+=1
				if gap>0: counts.left_occluded+=1
				if ocean_clip: counts.left_clip+=1
				if left_rows.size()<10: left_rows.append({"patch":patch_index,"screen":screen,"depthGap":gap,"alpha":alpha,"groundError":ocean_ground-local_height})
		stretch_ratios.sort()
		patch_stats.append({"patch":patch_index,"frontDistance":states[patch_index].frontDistance,"front_j":front_j,"segments":segment_count,"reversedProgress":reversed_progress,"frontPositiveTriangles":positive_front_triangles,"firstCellPositiveTriangles":positive_first_triangles,"frontStretchMinMedianMax":[stretch_ratios[0],stretch_ratios[int(stretch_ratios.size()/2)],stretch_ratios[-1]]})
	# Majority winding is negative, established by the first coast-side cell.
	counts.folded_triangles=sign_count.positive
	var patch_node: MeshInstance3D=surf.get_child(4)
	var patch_arrays: Array=patch_node.mesh.surface_get_arrays(0)
	var patch_vertices: PackedVector3Array=patch_arrays[Mesh.ARRAY_VERTEX]
	var original_points:=PackedVector2Array()
	for row in patch_vertices.size()/21:
		var v:=patch_vertices[int(row)*21]; var outer:=patch_vertices[int(row)*21+20]
		var out:=Vector2(outer.x-v.x,outer.z-v.z)/24.0
		original_points.append(Vector2(v.x,v.z)-out*.2)
	var gradient_span_ab: Array=[]
	for span: float in [1.0,2.0,4.0,6.0,8.0,12.0]:
		var front:=PackedVector2Array(); var reversals:=0; var ratios: Array=[]
		for p: Vector2 in original_points:
			var gradient:=Vector2(field.sample_triangle_height(p.x+span,p.y)-field.sample_triangle_height(p.x-span,p.y),field.sample_triangle_height(p.x,p.y+span)-field.sample_triangle_height(p.x,p.y-span))
			front.append(p-gradient.normalized()*12.2)
		for i in front.size()-1:
			var base_delta:=original_points[i+1]-original_points[i]; var front_delta:=front[i+1]-front[i]
			if front_delta.dot(base_delta)<0: reversals+=1
			if base_delta.length()>.00001: ratios.append(front_delta.length()/base_delta.length())
		ratios.sort(); gradient_span_ab.append({"span":span,"reversedSegments":reversals,"stretchMinMedianMax":[ratios[0],ratios[int(ratios.size()/2)],ratios[-1]]})
	print("SHORE_BARCODE_MATH ",JSON.stringify({"counts":counts,"winding":sign_count,"patches":patch_stats,"gradientSpanABPatch4":gradient_span_ab,"depthGapRange":[min_depth_gap,max_depth_gap],"maxNearRFHeightError":maximum_height_error,"globalRFCell":Vector2(ground_bounds.z-ground_bounds.x,ground_bounds.w-ground_bounds.y)/511.0,"nearRFCell":Vector2(near_bounds.z-near_bounds.x,near_bounds.w-near_bounds.y)/511.0,"leftRows":left_rows}))
	world.dispose(); world.free(); camera.free(); viewport.free(); quit()
