extends RefCounted
## Interpret the actual ShadowRenderer/TargetRigid diagnostics. A successful
## fullscreen quad alone is not evidence that any caster volume was drawn.

func expected_source_paths(model:String)->Array[String]:
	if model=="baseline":
		var raw:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_naval/ships-manifest.json"))
		if not raw is Dictionary:return []
		var original:String=str(raw.get("mappings",{}).get("fuchuan",{}).get("modelPath",""))
		return [original,original,original] if not original.is_empty() else []
	var family:String={"hero":"hero_fuchuan","vintage":"hero_fuchuan_v2","art":"hero_fuchuan_v3","art_r6":"hero_fuchuan_v3_r6","art_r7a":"hero_fuchuan_v3_r7a","art_r7b":"hero_fuchuan_v3_r7b","art_r7c":"hero_fuchuan_v3_r7c","art_r8b":"hero_fuchuan_v3_r8b","art_r9":"hero_fuchuan_v3_r9","art_r9b":"hero_fuchuan_v3_r9b","art_r11":"hero_fuchuan_v3_r11"}.get(model,"")
	if family.is_empty():return []
	var result:Array[String]=[]
	for lod in 3:result.append("res://assets/models/%s/fuchuan-lod%d.glb"%[family,lod])
	return result

func r9_asset_paths(variant:String="r9")->Array[String]:
	# Track both the actual runtime package and the explicit authoring chain.
	# Both candidates use R7c GLBs; R9b's image edits the R9 image.
	if variant not in ["r9","r9b"]:return []
	var paths:Array[String]=["res://assets/models/hero_fuchuan_v3_%s/manifest.json"%variant,"res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-%s.blend"%variant,"res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend","res://assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png","res://assets/textures/hero_fuchuan_r9/provenance.json","res://assets/textures/hero_fuchuan_v2/antique-hemp-sail.png","res://docs/design/2026-10-26-ming-maritime/reference/menu-direction.png","res://tools/blender/build_hero_fuchuan_r9.py","res://tools/blender/create_hero_r9_blend.py","res://tools/research/verify_hero_r9_texture_delta.py"]
	if variant=="r9b":paths.append_array(["res://assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png","res://assets/textures/hero_fuchuan_r9/provenance-sunfaded.json","res://tools/blender/build_hero_fuchuan_r9b.py","res://tools/research/verify_hero_r9b_texture_delta.py"])
	for family:String in ["hero_fuchuan_v3_r7c","hero_fuchuan_v3_"+variant]:
		for lod in 3:paths.append("res://assets/models/%s/fuchuan-lod%d.glb"%[family,lod])
	return paths

func r9_asset_hashes(variant:String="r9")->Dictionary:
	var paths:=r9_asset_paths(variant)
	if paths.is_empty():return {"unsupported-variant":"MISSING"}
	var hashes:Dictionary={}
	for path:String in paths:hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return hashes

func r11_asset_paths()->Array[String]:
	var paths:=r9_asset_paths("r9b")
	paths.append_array(["res://assets/models/hero_fuchuan_v3_r11/manifest.json","res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r11.blend","res://tools/blender/build_hero_fuchuan_r11.py","res://tools/research/verify_hero_r11_delta.py"])
	for lod in 3:paths.append("res://assets/models/hero_fuchuan_v3_r11/fuchuan-lod%d.glb"%lod)
	return paths

func r11_asset_hashes()->Dictionary:
	var hashes:Dictionary={}
	for path:String in r11_asset_paths():hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	return hashes

func watched_source_hashes(model:String)->Dictionary:
	var hashes:Dictionary={}
	for path:String in ["res://project.godot","res://tools/verify-hero-fuchuan-gpu.gd","res://tools/research/hero_gpu_evidence_gate.gd","res://game/research/demos/hero_fuchuan_experiment.gd","res://game/research/fixtures/hero_palette_provider.gd","res://game/research/fixtures/hero_rig_shadow_probe.gd","res://game/presentation/ships/ship_view.gd","res://game/presentation/ships/ship_damage.gd","res://game/presentation/crew/deck_stations.gd","res://game/presentation/world/target_rigid_shadow_caster.gd","res://game/presentation/world/target_shadow_boundary.gd","res://modules/scene_engine/assets/hero_ship_provider.gd","res://modules/scene_engine/assets/ship_model_provider.gd","res://modules/scene_engine/assets/asset_library.gd","res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd","res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd","res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd","res://modules/scene_engine/fidelity_fx/source_shadow_math.gd","res://modules/scene_engine/fidelity_fx/prepared_rigid_shadow.gd","res://modules/scene_engine/fidelity_fx/prepared_shadow_frame.gd","res://modules/environment_engine/weather_state.gd","res://assets/data/fidelity_naval/ships-manifest.json","res://tools/blender/build_hero_fuchuan_v3.py","res://game/presentation/ships/ship_damage.gdshader","res://game/presentation/ships/ship_damage_alpha.gdshader","res://game/presentation/ships/ship_damage_surface.gdshaderinc"]:
		hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	for surface:String in ["hull","sail"]:
		for suffix:int in ([0,20,40,60,80,100] if surface=="hull" else [20,40,60,80,100]):
			var path:String="res://assets/textures/pirates_damage_reference/ship_%s_damage%03d.dds.png"%[surface,suffix]
			hashes[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "MISSING"
	if model in ["art_r9","art_r9b"]:hashes.merge(r9_asset_hashes(model.trim_prefix("art_")),true)
	if model=="art_r11":hashes.merge(r11_asset_hashes(),true)
	return hashes

func _resource_path(path:Variant)->String:
	return "res://"+str(path).replace("\\","/")

func _matches_hash(hashes:Dictionary,path:String,digest:Variant)->bool:
	return digest is String and digest.length()==64 and hashes.get(path,"")==digest

func _provenance_evidence(hashes:Dictionary,path:String,image_path:String,asset_name:String,required:Array[String],errors:Array[String])->void:
	var provenance:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
	if not provenance is Dictionary:
		errors.append("image provenance unavailable: "+path);return
	if not _matches_hash(hashes,path,FileAccess.get_sha256(path)):errors.append("image provenance hash missing or changed: "+path)
	if provenance.get("asset")!=asset_name or provenance.get("sha256")!=hashes.get(image_path):errors.append("image provenance or generated texture mismatch: "+path)
	var inputs:Variant=provenance.get("inputs")
	if not inputs is Array or inputs.size()!=required.size():
		errors.append("image provenance inputs missing: "+path);return
	var seen:Dictionary={}
	for input:Variant in inputs:
		if not input is Dictionary:
			errors.append("image provenance input invalid");continue
		var input_path:=_resource_path(input.get("path",""))
		if input_path not in required or seen.has(input_path) or not _matches_hash(hashes,input_path,input.get("sha256")):errors.append("image provenance input hash mismatch: "+input_path)
		seen[input_path]=true

func r9_asset_evidence(hashes:Dictionary,variant:String="r9")->Dictionary:
	var errors:Array[String]=[]
	if variant not in ["r9","r9b"]:return {"ok":false,"errors":["unsupported candidate variant"]}
	var manifest_path:="res://assets/models/hero_fuchuan_v3_%s/manifest.json"%variant
	var provenance_path:="res://assets/textures/hero_fuchuan_r9/provenance-sunfaded.json" if variant=="r9b" else "res://assets/textures/hero_fuchuan_r9/provenance.json"
	var image_name:="sunfaded-cinnabar-hemp-sail.png" if variant=="r9b" else "cinnabar-hemp-sail.png"
	var image_path:="res://assets/textures/hero_fuchuan_r9/"+image_name
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:return {"ok":false,"errors":["candidate manifest unavailable"]}
	if not FileAccess.file_exists(manifest_path) or not _matches_hash(hashes,manifest_path,FileAccess.get_sha256(manifest_path)):errors.append("candidate manifest hash missing or changed")
	if manifest.get("asset")!="hero-fuchuan-v3-"+variant or manifest.get("baseline")!="hero-fuchuan-v3-r7c":errors.append("candidate identity or baseline mismatch")
	for item:Array in [["authorBlend","authorBlendSha256","res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-%s.blend"%variant],["sourceBlend","sourceBlendSha256","res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend"],["png","pngSha256",image_path]]:
		var declared:=_resource_path(manifest.get(item[0],""))
		if declared!=item[2] or not _matches_hash(hashes,declared,manifest.get(item[1])):errors.append("candidate manifest source mismatch: "+str(item[0]))
	var prior_image:="res://assets/textures/hero_fuchuan_r9/cinnabar-hemp-sail.png"
	var visual_reference:="res://docs/design/2026-10-26-ming-maritime/reference/menu-direction.png"
	var original_inputs:Array[String]=["res://assets/textures/hero_fuchuan_v2/antique-hemp-sail.png",visual_reference]
	_provenance_evidence(hashes,"res://assets/textures/hero_fuchuan_r9/provenance.json",prior_image,"cinnabar-hemp-sail.png",original_inputs,errors)
	if variant=="r9b":
		var faded_inputs:Array[String]=[prior_image,visual_reference]
		_provenance_evidence(hashes,provenance_path,image_path,image_name,faded_inputs,errors)
	var lods:Variant=manifest.get("lods")
	var seen:Dictionary={}
	if not lods is Array or lods.size()!=3:errors.append("R9 three LOD entries required")
	else:
		for item:Variant in lods:
			if not item is Dictionary or not item.has("lod"):
				errors.append("invalid R9 LOD entry");continue
			if not (item.lod is int or item.lod is float) or not is_finite(float(item.lod)) or float(int(item.lod))!=float(item.lod):
				errors.append("non-integral R9 LOD index");continue
			var lod:=int(item.lod)
			if lod<0 or lod>2 or seen.has(lod):
				errors.append("invalid or duplicate R9 LOD index");continue
			seen[lod]=true
			var candidate:="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod%d.glb"%[variant,lod]
			var baseline:="res://assets/models/hero_fuchuan_v3_r7c/fuchuan-lod%d.glb"%lod
			if _resource_path(item.get("candidate",""))!=candidate or not _matches_hash(hashes,candidate,item.get("candidateSha256")):errors.append("R9 candidate LOD%d mismatch"%lod)
			if _resource_path(item.get("source",""))!=baseline or not _matches_hash(hashes,baseline,item.get("sourceSha256")):errors.append("R7c baseline LOD%d mismatch"%lod)
	return {"ok":errors.is_empty(),"errors":errors,"variant":variant,"manifest":manifest_path,"provenance":provenance_path,"r9TextureSha256":manifest.get("pngSha256",""),"authorBlendSha256":manifest.get("authorBlendSha256","")}

func r11_asset_evidence(hashes:Dictionary)->Dictionary:
	var errors:Array[String]=[]
	for path:String in r11_asset_paths():
		var value:Variant=hashes.get(path,"")
		if not value is String or value.length()!=64:errors.append("missing dependency hash: "+path)
	var baseline:=r9_asset_evidence(hashes,"r9b")
	if not baseline.ok:errors.append_array(baseline.errors)
	var manifest_path:="res://assets/models/hero_fuchuan_v3_r11/manifest.json"
	var manifest:Variant=JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not manifest is Dictionary:return {"ok":false,"errors":["R11 manifest unavailable"]}
	if not _matches_hash(hashes,manifest_path,FileAccess.get_sha256(manifest_path)):errors.append("R11 manifest hash missing or changed")
	if manifest.get("asset")!="hero-fuchuan-v3-r11" or manifest.get("baseline")!="hero-fuchuan-v3-r9b":errors.append("R11 identity or baseline mismatch")
	for item:Array in [["authorBlend","authorBlendSha256","res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r11.blend"],["sourceBlend","sourceBlendSha256","res://assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend"],["png","pngSha256","res://assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png"]]:
		if _resource_path(manifest.get(item[0],""))!=item[2] or not _matches_hash(hashes,item[2],manifest.get(item[1])):errors.append("R11 manifest source mismatch: "+str(item[0]))
	for item:Array in [["builderSha256","res://tools/blender/build_hero_fuchuan_r11.py"],["checkerSha256","res://tools/research/verify_hero_r11_delta.py"]]:
		if not _matches_hash(hashes,item[1],manifest.get(item[0])):errors.append("R11 tool hash mismatch: "+str(item[0]))
	var lods:Variant=manifest.get("lods")
	var seen:Dictionary={}
	if not lods is Array or lods.size()!=3:errors.append("R11 three LOD entries required")
	else:
		for item:Variant in lods:
			if not item is Dictionary or not (item.get("lod") is int or item.get("lod") is float):errors.append("invalid R11 LOD entry");continue
			var value:float=float(item.lod)
			if not is_finite(value) or value!=floor(value) or value<0 or value>2 or seen.has(int(value)):errors.append("invalid or duplicate R11 LOD index");continue
			var lod:=int(value);seen[lod]=true
			for pair:Array in [["candidate","candidateSha256","r11"],["source","sourceSha256","r9b"]]:
				var path:="res://assets/models/hero_fuchuan_v3_%s/fuchuan-lod%d.glb"%[pair[2],lod]
				if _resource_path(item.get(pair[0],""))!=path or not _matches_hash(hashes,path,item.get(pair[1])):errors.append("R11 LOD%d %s mismatch"%[lod,pair[0]])
	return {"ok":errors.is_empty(),"errors":errors,"variant":"r11","manifest":manifest_path,"baseline":baseline,"authorBlendSha256":manifest.get("authorBlendSha256","")}

func shadow_evidence(before: Dictionary, after: Dictionary) -> Dictionary:
	var errors: Array[String]=[]
	var old_renderer: Variant=before.get("renderer")
	var renderer: Variant=after.get("renderer")
	var adapter: Variant=after.get("adapter")
	if not old_renderer is Dictionary or not renderer is Dictionary or not adapter is Dictionary:
		return {"ok":false,"errors":["missing renderer or caster diagnostics"]}
	var old_gpu: Variant=old_renderer.get("gpu")
	var gpu: Variant=renderer.get("gpu")
	if not old_gpu is Dictionary or not gpu is Dictionary:
		return {"ok":false,"errors":["missing compositor diagnostics"]}
	if gpu.get("initialized") != true: errors.append("compositor not initialized")
	if not gpu.has("error") or not gpu.error is String or not gpu.error.is_empty(): errors.append("compositor error or missing error status")
	if not renderer.has("errors") or not renderer.errors is Array or not renderer.errors.is_empty(): errors.append("renderer errors or missing error status")
	if not adapter.has("errors") or not adapter.errors is Array or not adapter.errors.is_empty(): errors.append("caster errors or missing error status")
	if not renderer.get("volumeCount") is int or renderer.volumeCount<1: errors.append("no submitted shadow volumes")
	if not adapter.get("activeCasters") is int or adapter.activeCasters<1: errors.append("no active rigid casters")
	if not gpu.get("cachedMeshes") is int or gpu.cachedMeshes<1: errors.append("no cached caster meshes")
	if not old_gpu.get("frames") is int or not gpu.get("frames") is int or old_gpu.frames<0 or gpu.frames<=old_gpu.frames:
		errors.append("no newly completed compositor frame")
	# The verifier explicitly requires a single-view viewport. Each successful
	# callback draws one fullscreen quad; a caster adds two volume draws.
	# Compare against the number of callbacks so several quads alone cannot
	# masquerade as a geometry contribution.
	var valid_frames:bool=old_gpu.get("frames") is int and gpu.get("frames") is int
	var frame_delta:int=gpu.frames-old_gpu.frames if valid_frames else 0
	if not old_gpu.get("draws") is int or not gpu.get("draws") is int or old_gpu.draws<0 or gpu.draws-old_gpu.draws<=frame_delta:
		errors.append("no newly submitted caster geometry draws")
	return {"ok":errors.is_empty(),"errors":errors}

func caster_evidence(demo:Node,model:String,shadows:String)->Dictionary:
	var rows:Array[Dictionary]=[]
	var actual:Node=demo._ship.get_model()
	if not is_instance_valid(actual):return {"ok":false,"reason":"model missing","casters":rows}
	var complete:=true
	for node:Node in actual.find_children("*","MeshInstance3D",true,false):
		var caster:=node as MeshInstance3D
		if not caster.get_meta("target_rigid_shadow_caster",false) or not caster.is_visible_in_tree() or caster.mesh==null:continue
		var sibling:=caster.get_parent().get_node_or_null("shadow_"+str(caster.name)) as MeshInstance3D
		var selected:Variant=caster.get_meta("target_shadow_geometry",null)
		var authored:bool=sibling!=null and sibling.mesh!=null and selected==sibling.mesh and sibling.mesh!=caster.mesh and not sibling.visible
		var stencil_only:=caster.cast_shadow==GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var ok:=stencil_only and (shadows!="authored" or authored)
		rows.append({"name":str(caster.name),"sourcePath":str(actual.get_meta("source_path","")),"nativeCastOff":stencil_only,"authoredProxySelected":authored})
		complete=complete and ok
	if rows.is_empty():return {"ok":false,"reason":"no visible target rigid casters","casters":rows}
	if model in ["art_r6","art_r7a","art_r7b","art_r7c","art_r8b","art_r9","art_r9b","art_r11"] and rows.size()!=5:
		return {"ok":false,"reason":"expected five rigid hull/deck/mast casters","casters":rows}
	return {"ok":complete,"reason":"" if complete else "native fallback or authored proxy not selected","casters":rows}

func canvas_color_evidence(demo:Node)->Dictionary:
	var errors:Array[String]=[]
	var rows:Array[Dictionary]=[]
	var names:Dictionary={}
	var damage:Variant=demo._ship.get("_damage")
	if not is_instance_valid(damage):return {"ok":false,"errors":["damage binding missing"],"sails":rows}
	for entry:Dictionary in damage.get("_materials"):
		if not entry.get("sail",false):continue
		var node:MeshInstance3D=entry.node
		if not is_instance_valid(node) or not node.is_visible_in_tree():continue
		var original:Variant=entry.original
		var shader:Variant=entry.material
		var surface:int=entry.surface
		if not original is StandardMaterial3D or original.resource_name!="canvas" or not shader is ShaderMaterial or node.mesh==null:
			errors.append("invalid canvas damage binding");continue
		if surface<0 or surface>=node.mesh.get_surface_count():errors.append("invalid canvas surface");continue
		var colors:Variant=node.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
		if not colors is PackedColorArray:errors.append("missing canvas vertex colors: "+str(node.name));continue
		var active:bool=node.get_active_material(surface)==shader and original.vertex_color_use_as_albedo and shader.get_shader_parameter("use_original_vertex_color")==true and shader.get_shader_parameter("original_albedo")==original.albedo_texture and original.albedo_texture!=null
		if colors.is_empty() or not active:errors.append("canvas vertex color or original texture not consumed: "+str(node.name))
		if names.has(str(node.name)):errors.append("duplicate canvas role: "+str(node.name))
		names[str(node.name)]=true
		rows.append({"name":str(node.name),"vertices":colors.size(),"vertexColorConsumed":active})
	if rows.size()!=3 or not names.has("sail_0") or not names.has("sail_1") or not names.has("sail_2"):errors.append("expected three visible canvas damage bindings")
	return {"ok":errors.is_empty(),"errors":errors,"sails":rows}

func pose_evidence(demo:Node,model:String,snapshot:Dictionary)->Dictionary:
	if model=="baseline":return {"ok":true,"scope":"reference rig has a different contract"}
	var deployment:float=float(snapshot.get("sailDeployment",-1))
	var rudder:float=float(snapshot.get("rudder",2))
	var sails:Array[Dictionary]=[]
	var rudders:Array[Dictionary]=[]
	var valid:=true
	for role:Dictionary in demo._ship.get("_pose_sails"):
		var sail:MeshInstance3D=role.node
		if not is_instance_valid(sail) or not sail.is_visible_in_tree() or int(role.furl)<0:continue
		var observed:=sail.get_blend_shape_value(int(role.furl))
		sails.append({"name":str(sail.name),"furl":observed})
		valid=valid and absf(observed-(1.0-deployment))<0.0001
	for role:Dictionary in demo._ship.get("_pose_rudders"):
		var pivot:Node3D=role.node
		if not is_instance_valid(pivot) or not pivot.is_visible_in_tree():continue
		var observed:=pivot.rotation.y
		rudders.append({"name":str(pivot.name),"yaw":observed,"rest":float(role.rest)})
		valid=valid and absf(observed-(float(role.rest)+clampf(rudder,-1,1)*0.42))<0.0001
	valid=valid and sails.size()>=3 and not rudders.is_empty()
	return {"ok":valid,"sailCount":sails.size(),"rudderCount":rudders.size(),"sails":sails,"rudders":rudders}

func lod_evidence(demo:Node,model:String,lod:int)->Dictionary:
	var errors:Array[String]=[]
	var paths:=expected_source_paths(model)
	if lod<0 or lod>2 or paths.size()!=3:return {"ok":false,"errors":["invalid expected LOD or model"],"lod":lod}
	var ship:Node=demo.get("_ship")
	if not is_instance_valid(ship):return {"ok":false,"errors":["ship unavailable"],"lod":lod}
	var active:Node=ship.get_model()
	if ship.get_lod()!=lod or not is_instance_valid(active):errors.append("wrong active LOD")
	var source:=str(active.get_meta("source_path","")) if is_instance_valid(active) else ""
	if source!=paths[lod]:errors.append("active LOD source does not match candidate")
	var visible:Array[int]=[]
	for index in 3:
		var node:=ship.get_node_or_null("LOD%d"%index) as Node3D
		if not is_instance_valid(node):errors.append("missing LOD%d node"%index);continue
		if node.visible:visible.append(index)
	if visible!=[lod]:errors.append("expected exactly one visible LOD")
	return {"ok":errors.is_empty(),"errors":errors,"lod":lod,"sourcePath":source,"visibleLODs":visible}

func deployment_evidence(demo:Node,model:String,snapshot:Dictionary,wind:Dictionary,expected_inflation:float)->Dictionary:
	if model=="baseline":return {"ok":true,"supported":false,"scope":"reference rig has a different sail assembly contract"}
	var errors:Array[String]=[]
	var ship:Node=demo.get("_ship")
	if not is_instance_valid(ship):return {"ok":false,"errors":["ship unavailable"]}
	if ship.get("_snapshot")!=snapshot or ship.get("_wind")!=wind:errors.append("actual applied snapshot or wind differs")
	var pose:=pose_evidence(demo,model,snapshot)
	if not pose.ok:errors.append("actual sail or rudder pose differs")
	var deployment:=float(snapshot.get("sailDeployment",-1.0))
	if not is_finite(deployment) or deployment<0.0 or deployment>1.0 or not is_finite(expected_inflation):errors.append("invalid deployment or expected inflation")
	var sail_rows:Array[Dictionary]=[]
	for role:Dictionary in ship.get("_pose_sails"):
		var sail:MeshInstance3D=role.node
		if not is_instance_valid(sail) or not sail.is_visible_in_tree():continue
		var furl:=int(role.furl);var inflate:=int(role.inflate)
		var mesh:=sail.mesh as ArrayMesh
		if mesh==null or furl<0 or inflate<0:
			errors.append("sail lacks shared furl/inflate morph: "+str(sail.name));continue
		if absf(sail.get_blend_shape_value(furl)-(1.0-deployment))>0.0001 or absf(sail.get_blend_shape_value(inflate)-expected_inflation)>0.0001:
			errors.append("sail morph weights differ: "+str(sail.name))
		var material_rows:Array[Dictionary]=[]
		var found:Dictionary={"canvas":false,"bamboo":false}
		for surface in mesh.get_surface_count():
			var material:=mesh.surface_get_material(surface)
			var name:=str(material.resource_name) if material!=null else ""
			if not found.has(name):continue
			var base:PackedVector3Array=mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
			var shapes:=mesh.surface_get_blend_shape_arrays(surface)
			if shapes.size()<=maxi(furl,inflate):
				errors.append("surface lacks shared morph arrays: "+str(sail.name)+"/"+name);continue
			var furled:PackedVector3Array=shapes[furl][Mesh.ARRAY_VERTEX]
			var inflated:PackedVector3Array=shapes[inflate][Mesh.ARRAY_VERTEX]
			if base.is_empty() or furled.size()!=base.size() or inflated.size()!=base.size():
				errors.append("surface morph topology mismatch: "+str(sail.name)+"/"+name);continue
			var furl_delta:=0.0;var inflate_delta:=0.0
			for index in base.size():
				var furl_change:=furled[index]-base[index] if mesh.get_blend_shape_mode()==Mesh.BLEND_SHAPE_MODE_NORMALIZED else furled[index]
				var inflate_change:=inflated[index]-base[index] if mesh.get_blend_shape_mode()==Mesh.BLEND_SHAPE_MODE_NORMALIZED else inflated[index]
				furl_delta=maxf(furl_delta,furl_change.length());inflate_delta=maxf(inflate_delta,inflate_change.length())
			if furl_delta<=0.000001 or inflate_delta<=0.000001:errors.append("surface has no actual shared morph displacement: "+str(sail.name)+"/"+name)
			found[name]=true
			material_rows.append({"material":name,"vertices":base.size(),"maxFurlDelta":furl_delta,"maxInflateDelta":inflate_delta})
		if not found.canvas or not found.bamboo:errors.append("canvas or batten surface absent: "+str(sail.name))
		sail_rows.append({"name":str(sail.name),"furl":sail.get_blend_shape_value(furl),"inflate":sail.get_blend_shape_value(inflate),"surfaces":material_rows})
	if sail_rows.size()<3:errors.append("three active sails required")
	return {"ok":errors.is_empty(),"errors":errors,"supported":true,"deployment":deployment,"expectedInflation":expected_inflation,"pose":pose,"sails":sail_rows}

func action_capture_evidence(deployments:Array,lods:Array,files:Array,shadow_frames:Array,model:String,shadows:String,wind:Dictionary,output:String)->Dictionary:
	var errors:Array[String]=[]
	var values:Array[float]=[0.0,0.25,0.5,0.75,1.0]
	var paths:=expected_source_paths(model)
	if paths.size()!=3:return {"ok":false,"errors":["candidate LOD paths unavailable"]}
	if deployments.size()!=5:errors.append("five deployment frames required")
	if lods.size()!=3:errors.append("three LOD frames required")
	var image_hashes:Dictionary={}
	for entry:Variant in files:
		if entry is Dictionary:image_hashes[str(entry.get("path",""))]=str(entry.get("sha256",""))
	var frame_by_phase:Dictionary={}
	for entry:Variant in shadow_frames:
		if not entry is Dictionary:continue
		var phase:=str(entry.get("phase",""))
		if phase in frame_by_phase:errors.append("duplicate shadow phase: "+phase)
		frame_by_phase[phase]=entry
	var reference:Dictionary={}
	var reference_set:=false
	for group:int in 2:
		var entries:Array=deployments if group==0 else lods
		var required_count:=5 if group==0 else 3
		for index in mini(required_count,entries.size()):
			var row:Variant=entries[index]
			if not row is Dictionary:
				errors.append("invalid action frame record");continue
			var expected_deployment:float=values[index] if group==0 else 1.0
			var expected_lod:=0 if group==0 else index
			var phase:="deployment-%03d"%roundi(expected_deployment*100) if group==0 else "lod-%d"%index
			if row.get("phase")!=phase:errors.append("action frame phase mismatch: "+phase)
			if group==0 and float(row.get("deployment",-1))!=expected_deployment:errors.append("deployment value mismatch: "+phase)
			if group==1 and int(row.get("lod",-1))!=expected_lod:errors.append("LOD value mismatch: "+phase)
			if row.get("wind")!=wind:errors.append("action wind mismatch: "+phase)
			var state:Variant=row.get("snapshot")
			if not state is Dictionary:
				errors.append("action snapshot missing: "+phase)
			else:
				if float(state.get("sailDeployment",-1))!=expected_deployment:errors.append("action deployment snapshot mismatch: "+phase)
				var invariant:Dictionary=state.duplicate(true);invariant.erase("sailDeployment")
				if not reference_set:reference=invariant;reference_set=true
				elif invariant!=reference:errors.append("action snapshots differ beyond deployment: "+phase)
			var selected:Variant=row.get("lodEvidence")
			if not selected is Dictionary or not selected.get("ok",false) or int(selected.get("lod",-1))!=expected_lod or selected.get("sourcePath")!=paths[expected_lod]:errors.append("actual LOD evidence mismatch: "+phase)
			var components:Variant=row.get("components")
			if not components is Dictionary or not components.get("ok",false) or (model!="baseline" and not components.get("supported",false)):errors.append("canvas/batten evidence missing: "+phase)
			var file:Variant=row.get("file")
			var expected_path:=output.path_join(phase+".png")
			if not file is Dictionary or file.get("path")!=expected_path or file.get("label")!=phase or str(file.get("sha256","")).length()!=64 or image_hashes.get(expected_path,"")!=file.get("sha256"):errors.append("PNG record or SHA mismatch: "+phase)
			if shadows!="native":
				var shadow:Variant=frame_by_phase.get(phase)
				if not shadow is Dictionary or not shadow.get("counterCheck",{}).get("ok",false) or not shadow.get("casterBinding",{}).get("ok",false):errors.append("active compositor/caster evidence missing: "+phase)
	return {"ok":errors.is_empty(),"errors":errors,"deploymentFrames":deployments.size(),"lodFrames":lods.size(),"fixedWind":wind,"scope":"Controlled fixed snapshot, fixed wind; LOD selected by distance API at a fixed camera. Not real-distance or native gameplay evidence."}

func reset_capture_evidence(reset:Dictionary,initial:Dictionary,wind:Dictionary,files:Array,shadow_frames:Array,model:String,shadows:String,output:String)->Dictionary:
	var errors:Array[String]=[]
	var paths:=expected_source_paths(model)
	if paths.size()!=3:return {"ok":false,"errors":["candidate LOD paths unavailable"]}
	if reset.get("phase")!="reset-initial" or reset.get("snapshot")!=initial or reset.get("wind")!=wind:errors.append("reset snapshot or wind differs from initial")
	var selected:Variant=reset.get("lodEvidence")
	if not selected is Dictionary or not selected.get("ok",false) or int(selected.get("lod",-1))!=0 or selected.get("sourcePath")!=paths[0]:errors.append("reset LOD0/source not restored")
	var pose:Variant=reset.get("poseEvidence")
	if not pose is Dictionary or not pose.get("ok",false):errors.append("reset sail/rudder pose not restored")
	var file:Variant=reset.get("file")
	var path:=output.path_join("reset-initial.png")
	var actual_digest:=""
	for entry:Variant in files:
		if entry is Dictionary and entry.get("path")==path:actual_digest=str(entry.get("sha256",""))
	if not file is Dictionary or file.get("path")!=path or file.get("label")!="reset-initial" or str(file.get("sha256","")).length()!=64 or file.get("sha256")!=actual_digest:errors.append("reset PNG record or SHA mismatch")
	if shadows!="native":
		var matching:Array=[]
		for entry:Variant in shadow_frames:
			if entry is Dictionary and entry.get("phase")=="reset-initial":matching.append(entry)
		if matching.size()!=1 or not matching[0].get("counterCheck",{}).get("ok",false) or not matching[0].get("casterBinding",{}).get("ok",false):errors.append("reset compositor/caster evidence missing")
	return {"ok":errors.is_empty(),"errors":errors,"scope":"Reset to recorded initial snapshot, wind and LOD0; frame validated through same selected shadow mode."}

func save_png(pixels:Image,path:String,label:String,time:float,expected_size:Vector2i)->Dictionary:
	if pixels==null or pixels.is_empty():return {"ok":false,"reason":"empty viewport image"}
	if pixels.get_size()!=expected_size:return {"ok":false,"reason":"viewport dimensions mismatch"}
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(path):return {"ok":false,"reason":"image destination already exists"}
	var error:=pixels.save_png(path)
	if error!=OK or not FileAccess.file_exists(path):return {"ok":false,"reason":"PNG write failed: "+str(error)}
	var handle:=FileAccess.open(path,FileAccess.READ)
	if handle==null:return {"ok":false,"reason":"PNG could not be reopened"}
	var length:=handle.get_length();handle.close()
	if length<=0:return {"ok":false,"reason":"PNG is empty"}
	var digest:=FileAccess.get_sha256(path)
	if digest.length()!=64:return {"ok":false,"reason":"PNG SHA256 unavailable"}
	return {"ok":true,"entry":{"label":label,"path":path,"sha256":digest,"size":[pixels.get_width(),pixels.get_height()],"time":time}}

func file_evidence(records:Array)->Dictionary:
	var seen:Dictionary={}
	var errors:Array[String]=[]
	for value:Variant in records:
		if not value is Dictionary:
			errors.append("invalid image record");continue
		var path:String=str(value.get("path",""))
		var digest:String=str(value.get("sha256",""))
		if path.is_empty() or digest.length()!=64:
			errors.append("image path or SHA256 missing");continue
		if seen.has(path):
			errors.append("duplicate image path: "+path);continue
		seen[path]=true
		if not FileAccess.file_exists(path) or FileAccess.get_sha256(path)!=digest:
			errors.append("image missing or changed: "+path)
	return {"ok":errors.is_empty(),"errors":errors}
