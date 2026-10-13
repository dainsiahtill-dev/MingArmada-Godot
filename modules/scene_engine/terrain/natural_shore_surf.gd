extends Node3D
## Original surf texture and controller math adapted to the current game's
## triangle coastline. Numeric terrain is read once, never changed. All clocks
## come from the caller, and geometry is built once rather than on camera moves.
const Source = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const PreparedSampler = preload("res://modules/scene_engine/fidelity_island/compiled_shore_sampler.gd")
const SHADER = preload("res://modules/scene_engine/terrain/natural_shore_surf.gdshader")
const SOURCE_PATH := "res://assets/data/fidelity_island/shore-scene.json"
const DEFAULT_SPAN := 12.0
const STEP := 1.25
const DISPLAY_CREST_U := 0.80859375 # Strongest mean-alpha column of the original mip0.
const DISPLAY_ALPHA_PEAK := 0.78 # GAME adaptation, not the recovered source alpha.
var _source: Dictionary = {}
var _materials: Array[ShaderMaterial] = []
var _packets: Array[Dictionary] = []
var _states: Array = []
var _field: RefCounted
var _contours: Array = []
var _coast_error := 0.0
var _vertices := 0
var _time := 0.0
var _geometry_builds := 0
var _surface_wave_count := 0
var _configured := false
var _sampler: RefCounted
var _has_applied_time := false
var _surface_state: Dictionary = {}
var _native_uv := Vector4(0.0,0.0,3.0,1.0)
var _authored_aspect := 1.0
var _patch_length := 12.0
var _wave_span := DEFAULT_SPAN

func configure(field: RefCounted, options: Dictionary = {}) -> bool:
	if _configured or field==null or not field.has_method("get_grid") or not field.has_method("sample_triangle_height"): return false
	var requested_span: Variant=options.get("wave_span",DEFAULT_SPAN)
	if not (requested_span is float or requested_span is int) or not is_finite(float(requested_span)) or float(requested_span)<4.0 or float(requested_span)>24.0: return false
	_wave_span=float(requested_span)
	var grid: Dictionary=field.get_grid()
	var side: int=int(grid.get("side",0))
	var heights: Variant=grid.get("heights")
	var bounds: Variant=grid.get("bounds")
	if side<3 or not heights is PackedFloat32Array or heights.size()!=side*side or not bounds is Rect2 or not bounds.size.is_finite() or bounds.size.x<=0.0 or bounds.size.y<=0.0: return false
	for h: float in heights:
		if not is_finite(h): return false
	_source=Source.read_json(SOURCE_PATH)
	if _source.get("meshes",[]).size()!=8: return false
	_sampler=PreparedSampler.new()
	if not _sampler.configure(_source): return false
	var texture: Texture2D=Source.texture_from_entry(_source.texture)
	if texture==null: return false
	# The source is authored as separate short quads. Preserve its UV bounds
	# AND metre-per-UV aspect; a 64m continuous ribbon stretched the 128px
	# alpha wrinkles and extrapolated short triangle gradients into folds.
	var source_mesh: Dictionary=_source.meshes[0]
	var raw: Array=source_mesh.vertices; var raw_uv: Array=source_mesh.uv
	var a:=Vector3(float(raw[0]),float(raw[1]),float(raw[2]))
	var b:=Vector3(float(raw[3]),float(raw[4]),float(raw[5]))
	var c:=Vector3(float(raw[6]),float(raw[7]),float(raw[8]))
	_native_uv=Vector4(float(raw_uv[4]),float(raw_uv[1]),float(raw_uv[0]),float(raw_uv[3]))
	_authored_aspect=(a.distance_to(b)/(_native_uv.w-_native_uv.y))/(a.distance_to(c)/(_native_uv.z-_native_uv.x))
	_patch_length=_wave_span/(_native_uv.z-_native_uv.x)*(_native_uv.w-_native_uv.y)*_authored_aspect
	_field=field; _contours=_extract_contours(grid)
	if _contours.is_empty(): dispose(); return false
	var image:=Image.create_from_data(side,side,false,Image.FORMAT_RF,heights.to_byte_array())
	var ground:=ImageTexture.create_from_image(image)
	var random:=RandomNumberGenerator.new()
	# Accepted terrain data is the seed authority. Reload and pause cannot move
	# packets, and no global/random wall-clock state enters the presentation.
	random.seed=hash([bounds.position,bounds.size,side,heights])
	var pair_id:=0
	for contour: PackedVector2Array in _contours:
		var arcs:=PackedFloat32Array([0.0])
		for i in contour.size()-1: arcs.append(arcs[-1]+contour[i].distance_to(contour[i+1]))
		var length: float=arcs[-1]
		var gap_before: float=random.randf_range(0.8,3.2)
		var cursor: float=gap_before
		while cursor<length:
			var source_index: int=random.randi_range(0,3)
			var source_quad: int=random.randi_range(0,int(_source.meshes[source_index].vertices.size()/12)-1)
			var metrics:=_quad_metrics(_source.meshes[source_index],source_quad)
			var dimension_scale: float=random.randf_range(0.72,1.0)
			var span: float=_wave_span*dimension_scale
			var patch_length: float=span*metrics.lengthRatio
			var gap: float=random.randf_range(0.8,3.2)
			var distance: float=cursor+patch_length*0.5
			if distance+patch_length*0.5>length: break
			var center:=_arc_point(contour,arcs,distance)
			var tangent:=(_arc_point(contour,arcs,distance+patch_length*0.5)-_arc_point(contour,arcs,distance-patch_length*0.5)).normalized()
			cursor=distance+patch_length*0.5+gap
			if tangent.length_squared()<0.5: continue
			var outward:=Vector2(-tangent.y,tangent.x)
			var left: float=_field.sample_triangle_height(center.x+outward.x*4.0,center.y+outward.y*4.0)
			var right: float=_field.sample_triangle_height(center.x-outward.x*4.0,center.y-outward.y*4.0)
			if left>right: outward=-outward
			var packet: Dictionary={"pairId":pair_id,"sourceIndex":source_index,"sourceQuad":source_quad,"center":center,"tangent":tangent,"outward":outward,"alongDistance":distance,"length":patch_length,"span":span,"uvBounds":metrics.uvBounds,"authoredAspect":metrics.aspect,"dimensionScale":dimension_scale,"gapBefore":gap_before,"clockOffset":random.randf_range(0.0,30.0),"clockSpeed":random.randf_range(0.82,1.19),"offshoreStart":random.randf_range(0.12,1.35)}
			gap_before=gap
			# Original meshes 0/4, 1/5, 2/6 and 3/7 occupy the SAME quad.
			# A pair shares placement/dimensions/speed; its recovered controller
			# phases alone produce the staggered front and following wave.
			_build_patch(packet,texture,ground,grid.bounds)
			var following: Dictionary=packet.duplicate(true); following.sourceIndex=source_index+4
			_build_patch(following,texture,ground,grid.bounds)
			pair_id+=1
	_configured=not _materials.is_empty(); _geometry_builds=1 if _configured else 0
	apply_snapshot({"time":0.0},0.0)
	return _configured

func _quad_metrics(mesh: Dictionary,index: int) -> Dictionary:
	var raw: Array=mesh.vertices; var uv: Array=mesh.uv
	var v:=index*12; var t:=index*8
	var a:=Vector3(raw[v],raw[v+1],raw[v+2])
	var b:=Vector3(raw[v+3],raw[v+4],raw[v+5])
	var c:=Vector3(raw[v+6],raw[v+7],raw[v+8])
	var extent:=Vector4(uv[t+4],uv[t+1],uv[t],uv[t+3])
	var ratio: float=a.distance_to(b)/a.distance_to(c)
	return {"uvBounds":extent,"lengthRatio":ratio,"aspect":ratio*(extent.z-extent.x)/(extent.w-extent.y)}

func _arc_point(points: PackedVector2Array,arcs: PackedFloat32Array,distance: float) -> Vector2:
	var wrapped:=fposmod(distance,float(arcs[-1]))
	var low:=0; var high:=arcs.size()-1
	while high-low>1:
		var middle: int=int((low+high)/2)
		if arcs[middle]<=wrapped: low=middle
		else: high=middle
	return points[low].lerp(points[high],(wrapped-arcs[low])/maxf(arcs[high]-arcs[low],0.000001))

func _extract_contours(grid: Dictionary) -> Array:
	# Intersect the same two triangles submitted by natural_island_mesh.
	# Shared edge IDs stitch exactly; no rounded coordinates or ambiguous
	# marching-square diagonals can move the coast off its authority surface.
	var side: int=grid.side; var heights: PackedFloat32Array=grid.heights
	var bounds: Rect2=grid.bounds
	var points: Dictionary={}; var adjacency: Dictionary={}
	for z in side-1:
		for x in side-1:
			var a:=z*side+x; var b:=a+1; var c:=a+side; var d:=c+1
			for triangle: Array in [[a,b,c],[c,b,d]]:
				var crossings: Array=[]
				for e in 3:
					var left: int=triangle[e]; var right: int=triangle[(e+1)%3]
					if (heights[left]>0.0)==(heights[right]>0.0): continue
					var key:=Vector2i(mini(left,right),maxi(left,right))
					if not points.has(key):
						var lp:=bounds.position+bounds.size*Vector2(left%side,int(left/side))/float(side-1)
						var rp:=bounds.position+bounds.size*Vector2(right%side,int(right/side))/float(side-1)
						points[key]=lp.lerp(rp,float(heights[left])/(float(heights[left])-float(heights[right])))
					crossings.append(key)
				if crossings.size()!=2: continue
				for i in 2:
					var key: Vector2i=crossings[i]
					if not adjacency.has(key): adjacency[key]=[]
					adjacency[key].append(crossings[1-i])
	var visited: Dictionary={}; var loops: Array=[]
	for first: Vector2i in adjacency:
		if visited.has(first): continue
		var loop:=PackedVector2Array(); var current:=first; var previous:=Vector2i(-1,-1)
		while not visited.has(current):
			visited[current]=true; var point: Vector2=points[current]; loop.append(point)
			_coast_error=maxf(_coast_error,absf(_field.sample_triangle_height(point.x,point.y)))
			var neighbours: Array=adjacency[current]
			if neighbours.size()!=2: break
			var next: Vector2i=neighbours[0] if neighbours[0]!=previous else neighbours[1]
			previous=current; current=next
		if current==first and loop.size()>8: loop.append(loop[0]); loops.append(loop)
	return loops

func _build_patch(packet: Dictionary,texture: Texture2D,ground: Texture2D,bounds: Rect2) -> void:
	var center: Vector2=packet.center; var tangent: Vector2=packet.tangent; var outward: Vector2=packet.outward
	var span: float=packet.span; var patch_length: float=packet.length; var extent: Vector4=packet.uvBounds
	var vertices:=PackedVector3Array(); var uv:=PackedVector2Array(); var indices:=PackedInt32Array()
	var across_count: int=int(ceil(span/STEP))+1
	var along_count: int=int(ceil(patch_length/STEP))+1
	for i in along_count:
		var along_fraction:=float(i)/float(along_count-1)
		# Each original-style short wave has one stable frame. Extrapolating
		# separate per-triangle gradients offshore made adjacent rows invert.
		var point:=center+tangent*(along_fraction-0.5)*patch_length
		for j in across_count:
			var fraction:=float(j)/float(across_count-1)
			var position:=point+outward*(float(packet.offshoreStart)+span*fraction)
			vertices.append(Vector3(position.x,0.055,position.y))
			# Native U increases as translation advances. Invert distance so this
			# is visibly an offshore-to-shore front, not alongshore UV scrolling.
			uv.append(Vector2(lerpf(extent.z,extent.x,fraction),lerpf(extent.y,extent.w,along_fraction)))
			if i>0 and j>0:
				var d:=vertices.size()-1; var c:=d-1; var b:=d-across_count; var a:=b-1
				indices.append_array(PackedInt32Array([a,b,c,c,b,d]))
	var arrays: Array=[]; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX]=vertices; arrays[Mesh.ARRAY_TEX_UV]=uv; arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	var material:=ShaderMaterial.new(); material.shader=SHADER
	material.set_shader_parameter("shore_texture",texture)
	material.set_shader_parameter("source_uv_bounds",extent)
	material.set_shader_parameter("source_alpha_threshold",float(_source.meshes[packet.sourceIndex].alphaProperty.threshold)/255.0)
	material.set_shader_parameter("source_crest_u",DISPLAY_CREST_U)
	material.set_shader_parameter("crest_half_width",0.40*float(packet.dimensionScale))
	material.set_shader_parameter("foam_tail_length",1.35*float(packet.dimensionScale))
	material.set_shader_parameter("reference_near_height_texture",ground)
	material.set_shader_parameter("reference_near_bounds",Vector4(bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y))
	material.set_shader_parameter("has_reference_near_field",true)
	material.render_priority=4
	var node:=MeshInstance3D.new(); node.name="NaturalSurf_%d"%_materials.size(); node.mesh=mesh; node.material_override=material
	node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF; add_child(node)
	_materials.append(material); _packets.append(packet); _vertices+=vertices.size()
	_states.append({})

func apply_snapshot(snapshot: Dictionary,_consumed: float = 0.0) -> void:
	var value: Variant=snapshot.get("time")
	if not _configured or not (value is float or value is int) or not is_finite(float(value)): return
	if _has_applied_time and float(value)==_time: return
	_has_applied_time=true
	_time=float(value)
	# Each configured patch owns one mutable state; diagnostics detach their
	# public snapshot. No packet/controller output is shared between patches.
	var sample_in_place := _sampler.has_method("sample_into")
	for i in _materials.size():
		var packet: Dictionary=_packets[i]
		var packet_time: float=_time*float(packet.clockSpeed)+float(packet.clockOffset)
		var state: Dictionary=_states[i]
		if sample_in_place: _sampler.sample_into(int(packet.sourceIndex),packet_time,state)
		else:
			# Existing injected samplers retain their sample() protocol and side
			# effects. Merge its fresh result into this patch's owned state.
			state.merge(_sampler.sample(int(packet.sourceIndex),packet_time),true)
		var phase: float=_sampler.alpha_phase
		# GAME adaptation: the recovered alpha has a 47.7% full-bright plateau.
		# Grow then erode during that approach; keep the exact source sample
		# separately so this envelope is never mistaken for recovered evidence.
		var envelope: float=smoothstep(0.07,0.29,phase)*(1.0-smoothstep(0.32,0.88,phase))
		var visible_alpha: float=clampf(state.alpha,0.0,1.0)*envelope*DISPLAY_ALPHA_PEAK
		_materials[i].set_shader_parameter("texture_matrix",_sampler.texture_matrix)
		_materials[i].set_shader_parameter("controller_alpha",visible_alpha)
		var extent: Vector4=packet.uvBounds
		_materials[i].set_shader_parameter("packet_u_metres",float(packet.span)/(extent.z-extent.x)/float(state.scaleU))
		# Source evidence only: invert the recovered transform at Native U=.75.
		# The game's rendered head is separately reanchored to the ocean phase
		# and strongest texture column; this is not its rendered trajectory.
		state.frontDistance=float(packet.offshoreStart)+float(packet.span)*(extent.z-(0.5+state.translationU+0.25/state.scaleU))/(extent.z-extent.x)
		state.nativeFrontDistance=state.frontDistance
		state.nativeAlpha=state.alpha; state.visibleAlpha=visible_alpha; state.lifeEnvelope=envelope
		state.lifePhase=phase; state.packetTime=packet_time; state.sourceIndex=packet.sourceIndex; state.pairId=packet.pairId

func sync_surface_state(ocean_material: ShaderMaterial,_state: Dictionary = {}) -> bool:
	if not _configured or ocean_material==null or ocean_material.shader==null: return false
	var components: Variant=ocean_material.get_shader_parameter("wave_components")
	var count: Variant=ocean_material.get_shader_parameter("wave_count")
	var time: Variant=ocean_material.get_shader_parameter("simulation_time")
	if not components is PackedVector4Array or not (count is int or count is float) or not (time is int or time is float) or not is_finite(float(time)): return false
	if not is_finite(float(count)) or int(count)!=float(count) or int(count)<0 or int(count)>8 or components.size()<int(count): return false
	for component: Vector4 in components:
		if not component.is_finite(): return false
	_surface_wave_count=int(count)
	for key: String in ["wave_components","wave_count","simulation_time","shore_height_texture","shore_bounds","has_shore_field","coastal_attenuation","coast_distance_texture","has_coast_distance","normal_texture","surface_visual_scale","surface_tide"]:
		var current: Variant=ocean_material.get_shader_parameter("u_tide" if key=="surface_tide" else key)
		if _surface_state.has(key) and _surface_state[key]==current: continue
		# ShaderMaterial retains PackedArray references. Snapshot changed wave
		# values so caller mutations cannot make the cache appear already current.
		if key=="wave_components": current=current.duplicate()
		for material: ShaderMaterial in _materials: material.set_shader_parameter(key,current)
		_surface_state[key]=current
	return true

func diagnostics() -> Dictionary:
	return {"layout":"authored_short_patches","authoredUvAspect":_authored_aspect,"patchLength":_patch_length,"waveSpan":_wave_span,"contourCount":_contours.size(),"patchCount":_materials.size(),"pairCount":int(_packets.size()/2),"vertices":_vertices,"geometryBuilds":_geometry_builds,"maxCoastHeightError":_coast_error,"originalTexture":"surf_bart3.dds","originalControllers":true,"frontDriver":"ocean_phase_reanchor","surfaceWaveCount":_surface_wave_count,"time":_time,"packets":_packets.duplicate(true),"states":_states.duplicate(true),"scope":"Co-located authored pairs with exact source controller diagnostics. GAME adapter reanchors texture heads to the primary ocean arc; native scale controls texture width and native alpha receives a grow/erosion envelope. Native translation/frontDistance is source evidence, not a second rendered trajectory; no terrain edits"}
func dispose() -> void:
	for child: Node in get_children(): remove_child(child); child.free()
	_materials.clear(); _packets.clear(); _states.clear(); _contours.clear(); _source.clear(); _field=null
	_sampler=null; _has_applied_time=false; _surface_state.clear()
	_vertices=0; _geometry_builds=0; _surface_wave_count=0; _coast_error=0.0; _configured=false
