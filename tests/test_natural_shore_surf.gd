extends SceneTree
const PATH := "res://modules/scene_engine/terrain/natural_shore_surf.gd"
const Field = preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Ocean = preload("res://modules/scene_engine/ocean/reference_game_water.gdshader")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
const Source = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Authored = preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",reason)
func _run() -> void:
	check(ResourceLoader.exists(PATH),"natural shore surf is implemented in the shared terrain presentation")
	if not ResourceLoader.exists(PATH): _finish(); return
	var script: Script=load(PATH)
	if script==null or not script.can_instantiate(): check(false,"shared surf script loads"); _finish(); return
	var field:=Field.new(); check(field.configure({"resolution":129}),"accepted numeric terrain configures")
	var surf: Node3D=script.new(); root.add_child(surf)
	check(surf.configure(field),"actual triangle contour builds source-textured wave ribbons")
	var info: Dictionary=surf.diagnostics()
	check(info.get("layout","")=="authored_short_patches","source surf uses separate short waves rather than a stretched complete ring")
	var packets: Array=info.get("packets",[])
	var source: Dictionary=Source.read_json("res://assets/data/fidelity_island/shore-scene.json")
	check(packets.size()==surf.get_child_count() and packets.size()>16,"each submitted wave retains its source quad and deterministic packet placement")
	var folded:=0; var stretch_error:=0.0
	var lengths: Array[float]=[]; var spans: Array[float]=[]; var gaps: Array[float]=[]
	var clocks: Dictionary={}; var speeds: Dictionary={}; var starts: Dictionary={}
	var submitted_bounds: Array[AABB]=[]; var gap_error:=0.0
	var pair_error:=false
	for n in surf.get_child_count():
		var node: MeshInstance3D=surf.get_child(n)
		submitted_bounds.append(node.mesh.get_aabb())
		var data: Array=node.mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array=data[Mesh.ARRAY_VERTEX]; var indices: PackedInt32Array=data[Mesh.ARRAY_INDEX]; var uv: PackedVector2Array=data[Mesh.ARRAY_TEX_UV]
		var first_sign:=0.0
		for i in range(0,indices.size(),3):
			var sign: float=(vertices[indices[i+1]]-vertices[indices[i]]).cross(vertices[indices[i+2]]-vertices[indices[i]]).y
			if first_sign==0.0: first_sign=sign
			if sign*first_sign<=0.0: folded+=1
		var columns:=1
		while columns<uv.size() and uv[columns].y==uv[0].y: columns+=1
		var u_scale: float=vertices[0].distance_to(vertices[columns-1])/absf(uv[0].x-uv[columns-1].x)
		var v_scale: float=vertices[0].distance_to(vertices[vertices.size()-columns])/absf(uv[0].y-uv[uv.size()-columns].y)
		lengths.append(vertices[0].distance_to(vertices[vertices.size()-columns]))
		spans.append(vertices[0].distance_to(vertices[columns-1]))
		if n<packets.size():
			var packet: Dictionary=packets[n]
			var mesh: Dictionary=source.meshes[packet.sourceIndex]
			var first: int=int(packet.sourceQuad)*12
			var a3:=Vector3(mesh.vertices[first],mesh.vertices[first+1],mesh.vertices[first+2])
			var b3:=Vector3(mesh.vertices[first+3],mesh.vertices[first+4],mesh.vertices[first+5])
			var c3:=Vector3(mesh.vertices[first+6],mesh.vertices[first+7],mesh.vertices[first+8])
			var native_aspect: float=(a3.distance_to(b3)/(uv[-1].y-uv[0].y))/(a3.distance_to(c3)/absf(uv[0].x-uv[columns-1].x))
			stretch_error=maxf(stretch_error,absf(v_scale/u_scale-native_aspect))
			clocks[snappedf(packet.clockOffset,0.01)]=true; speeds[snappedf(packet.clockSpeed,0.001)]=true
			starts[snappedf(packet.offshoreStart,0.01)]=true
			if n%2==0:
				if n>0:
					var preceding: Dictionary=packets[n-2]
					var actual_gap: float=packet.alongDistance-preceding.alongDistance-(packet.length+preceding.length)*0.5
					gaps.append(actual_gap); gap_error=maxf(gap_error,absf(actual_gap-packet.gapBefore))
				if n+1>=packets.size(): pair_error=true; continue
				var back: Dictionary=packets[n+1]
				var back_data: Array=surf.get_child(n+1).mesh.surface_get_arrays(0)
				pair_error=pair_error or back.sourceIndex!=packet.sourceIndex+4 or back.sourceQuad!=packet.sourceQuad or back.pairId!=packet.pairId
				pair_error=pair_error or back_data[Mesh.ARRAY_VERTEX]!=vertices or back_data[Mesh.ARRAY_TEX_UV]!=uv
				pair_error=pair_error or back.clockOffset!=packet.clockOffset or back.clockSpeed!=packet.clockSpeed
				var front_phase: float=source.meshes[packet.sourceIndex].controllers.alpha.phase
				var back_phase: float=source.meshes[back.sourceIndex].controllers.alpha.phase
				pair_error=pair_error or absf(back_phase-front_phase-15.0)>0.151
	check(folded==0,"actual surf triangles never turn inside out as the front moves offshore")
	check(stretch_error<0.002,"actual source alpha is laid out with its authored U/V world aspect, not stretched into a barcode")
	check(not packets.is_empty() and not pair_error,"front/back authored waves share one real coastline patch and original half-cycle staggering")
	check(lengths.size()>0 and lengths.max()-lengths.min()>2.0 and spans.max()-spans.min()>2.0,"submitted wave dimensions vary instead of identical white puffs")
	check(gaps.size()>0 and gaps.max()-gaps.min()>1.0 and gap_error<0.0001,"actual coast locations have irregular gaps matching their submitted dimensions")
	check(clocks.size()>8 and speeds.size()>8 and starts.size()>8,"neighboring packets have distinct native clock offsets, speeds and offshore starts")
	check(info.contourCount==1 and info.patchCount>8 and info.vertices>1000,"real natural coast has one connected contour and subdivided patches")
	check(info.maxCoastHeightError<0.0002,"coast locations agree with the rendered triangle surface")
	check(info.originalTexture=="surf_bart3.dds" and info.originalControllers==true,"original source texture and UV/alpha controllers are reused")
	var builds: int=info.geometryBuilds
	var ocean:=ShaderMaterial.new(); ocean.shader=Ocean
	var components:=PackedVector4Array()
	for c: Array in Waves.original_components(): components.append(Vector4(c[0],c[1],c[2],c[3]))
	ocean.set_shader_parameter("wave_components",components); ocean.set_shader_parameter("wave_count",5)
	ocean.set_shader_parameter("simulation_time",12.0)
	var distance_image:=Image.create(2,2,false,Image.FORMAT_RF); distance_image.fill(Color(2.0,0.0,0.0))
	var coast_texture:=ImageTexture.create_from_image(distance_image)
	ocean.set_shader_parameter("coast_distance_texture",coast_texture); ocean.set_shader_parameter("has_coast_distance",true)
	ocean.set_shader_parameter("shore_height_texture",coast_texture); ocean.set_shader_parameter("has_shore_field",true)
	ocean.set_shader_parameter("shore_bounds",Vector4(-400.0,-400.0,400.0,400.0))
	ocean.set_shader_parameter("surface_visual_scale",0.2)
	check(surf.sync_surface_state(ocean),"surf follows retained ocean five-wave state")
	var coverage: Array=[]
	for seconds: float in [6.0,12.0,18.0,24.0,29.0]:
		surf.apply_snapshot({"time":seconds},0.0)
		var sample: Dictionary=surf.diagnostics(); var visible:=0; var faded:=0; var native_error:=0.0; var binding_error:=false
		for n in sample.states.size():
			var state: Dictionary=sample.states[n]
			if state.get("visibleAlpha",-1.0)>0.12: visible+=1
			if state.get("visibleAlpha",1.0)<20.0/255.0: faded+=1
			if n<packets.size():
				var packet: Dictionary=packets[n]
				var expected: Dictionary=Authored.authored_state(source.meshes[packet.sourceIndex],source.curves,seconds*packet.clockSpeed+packet.clockOffset)
				native_error=maxf(native_error,absf(state.translationU-expected.translationU)+absf(state.scaleU-expected.scaleU)+absf(state.get("nativeAlpha",-1.0)-expected.alpha))
				var actual_material: ShaderMaterial=surf.get_child(n).material_override
				var expected_matrix: Basis=Native.texture_basis(Native.texture_transform(source.meshes[packet.sourceIndex].texture,expected))
				binding_error=binding_error or not actual_material.get_shader_parameter("texture_matrix").is_equal_approx(expected_matrix)
				binding_error=binding_error or absf(float(actual_material.get_shader_parameter("controller_alpha"))-state.visibleAlpha)>0.000001
		check(visible>0 and faded>0,"t=%s has simultaneously visible and faded packets"%seconds)
		check(not packets.is_empty() and native_error<0.00001,"t=%s retains exact recovered UV and alpha curve samples"%seconds)
		check(not packets.is_empty() and not binding_error,"t=%s actual shader matrices and display alpha receive those packet samples"%seconds)
		coverage.append({"time":seconds,"visible":visible,"faded":faded})
	var approach: Array=[]
	if not packets.is_empty():
		var packet: Dictionary=packets[0]
		var controller: Dictionary=source.meshes[packet.sourceIndex].controllers.alpha
		for phase: float in [12.0,18.0,24.0]:
			var seconds: float=(phase+2.0*controller.stop_time-controller.phase-packet.clockOffset)/packet.clockSpeed
			surf.apply_snapshot({"time":seconds},0.0); approach.append(surf.diagnostics().states[0])
	check(approach.size()==3 and approach[0].nativeAlpha>0.99 and approach[2].nativeAlpha>0.99 and approach[2].nativeFrontDistance<approach[0].nativeFrontDistance and approach[0].visibleAlpha-approach[2].visibleAlpha>0.10,"display alpha envelope erodes across the inward Native diagnostic's full-alpha plateau")
	check(approach.size()==3 and approach[0].visibleAlpha>0.70 and approach[0].visibleAlpha<0.75,"game display head keeps the accepted .78 peak adaptation while still fading during approach")
	surf.apply_snapshot({"time":42.0},0.0)
	var repeated: Dictionary=surf.diagnostics()
	surf.apply_snapshot({"time":42.0},50.0)
	check(surf.diagnostics().states==repeated.states,"paused snapshot does not advance on consumed render time")
	surf.apply_snapshot({"time":NAN},0.0)
	check(surf.diagnostics().states==repeated.states,"invalid clock does not poison materials")
	check(surf.diagnostics().geometryBuilds==builds,"time updates never regenerate coastline meshes")
	check(surf.diagnostics().get("packets",[])==packets,"injected time never mutates submitted placement or bounds")
	var bounds_stable:=true
	for n in surf.get_child_count(): bounds_stable=bounds_stable and surf.get_child(n).mesh.get_aabb()==submitted_bounds[n]
	check(bounds_stable,"actual submitted mesh bounds stay fixed through time, pause and invalid clock")
	check(surf.diagnostics().surfaceWaveCount==5,"same retained five physical waves follow the surf vertices")
	var material: ShaderMaterial=surf.get_child(0).material_override
	check(material.get_shader_parameter("has_coast_distance")==true and material.get_shader_parameter("coast_distance_texture")==coast_texture and material.get_shader_parameter("simulation_time")==12.0 and absf(float(material.get_shader_parameter("surface_visual_scale"))-0.2)<0.00001,"fusion uses the same actual ocean distance, injected phase clock and visual noise scale")
	check(surf.diagnostics().get("frontDriver","")=="ocean_phase_reanchor","source texture enhances one primary ocean arc instead of adding an independent advancing ellipse")
	check(not packets.is_empty() and absf(float(material.get_shader_parameter("crest_half_width"))-0.40*float(packets[0].dimensionScale))<0.000001,"game head half-width uses the accepted .40m adaptation per source quad scale")
	var threshold: Variant=material.get_shader_parameter("source_alpha_threshold")
	check((threshold is float or threshold is int) and absf(float(threshold)-20.0/255.0)<0.00001,"source alpha threshold removes low-opacity sprite halo instead of drawing cloud-like tails")
	var source_bounds: Variant=material.get_shader_parameter("source_uv_bounds")
	var actual_uv: PackedVector2Array=surf.get_child(0).mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV]
	var minimum:=Vector2(INF,INF); var maximum:=Vector2(-INF,-INF)
	for point: Vector2 in actual_uv: minimum=minimum.min(point); maximum=maximum.max(point)
	check(source_bounds is Vector4 and source_bounds.is_equal_approx(Vector4(minimum.x,minimum.y,maximum.x,maximum.y)),"edge feather is bound to submitted authored UV extent, preventing faint cut straight borders")
	check(info.get("waveSpan",1000.0)<=12.0,"default source wave scale stays within the near-shore wash instead of an oversized offshore puff")
	var original_image: Image=material.get_shader_parameter("shore_texture").get_image()
	check(original_image.has_mipmaps() and original_image.get_mipmap_count()==7 and original_image.get_width()==128 and original_image.get_height()==128,"original foam texture retains all eight authored mip levels")
	var decoded: Image=original_image.duplicate(); check(decoded.decompress()==OK,"original DXT3 texture can be inspected independently on CPU")
	var strongest_column:=0; var strongest_mean: float=-1.0
	for x in decoded.get_width():
		var energy:=0.0
		for y in decoded.get_height(): energy+=decoded.get_pixel(x,y).a
		energy/=float(decoded.get_height())
		if energy>strongest_mean: strongest_mean=energy; strongest_column=x
	var strongest_u: float=(float(strongest_column)+0.5)/float(decoded.get_width())
	var display_u: Variant=material.get_shader_parameter("source_crest_u")
	check(display_u is float and absf(float(display_u)-strongest_u)<0.000001 and strongest_mean>0.40,"actual display anchor follows the original texture's strongest alpha column instead of a weaker arbitrary slice")
	check(material.get_shader_parameter("has_reference_near_field"),"surf dry-land clip uses its own exact numeric grid")
	var reload: Node3D=script.new(); root.add_child(reload)
	check(reload.configure(field),"same accepted terrain can rebuild wave presentation")
	reload.apply_snapshot({"time":42.0},0.0)
	check(reload.diagnostics().get("packets",[])==packets and reload.diagnostics().states==repeated.states,"reload reproduces packet dimensions, locations and paused native phase")
	var reload_bounds:=reload.get_child_count()==submitted_bounds.size()
	for n in reload.get_child_count(): reload_bounds=reload_bounds and reload.get_child(n).mesh.get_aabb()==submitted_bounds[n]
	check(reload_bounds,"reload submits identical actual mesh bounds")
	reload.dispose(); reload.free()
	print("NATURAL_SHORE_SURF_PACKET_EVIDENCE ",JSON.stringify({"lengthRange":[lengths.min(),lengths.max()],"spanRange":[spans.min(),spans.max()],"gapRange":[gaps.min() if gaps.size() else 0.0,gaps.max() if gaps.size() else 0.0],"clockOffsets":clocks.size(),"clockSpeeds":speeds.size(),"offshoreStarts":starts.size(),"coverage":coverage,"approach":approach}))
	surf.dispose(); check(surf.get_child_count()==0,"dispose clears all owned ribbons")
	surf.free(); await process_frame
	_finish()
func _finish() -> void:
	print("NATURAL_SHORE_SURF assertions=%d failures=%d"%[assertions,failures]); quit(1 if failures else 0)
