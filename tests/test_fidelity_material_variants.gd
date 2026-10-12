extends SceneTree
const Asset=preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Profile=preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const Coordinates=preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(value: bool,reason: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",reason)
func _run() -> void:
	var definitions: Array=[{"id":"coastal2","path":"res://assets/data/fidelity_island/coastal2-original.json","width":329,"height":193,"portIndex":0},{"id":"virgin_islands","path":"res://assets/data/fidelity_island/virgin-islands-original.json","width":160,"height":77,"portIndex":2}]
	for entry: Dictionary in definitions: check(FileAccess.file_exists(entry.path),"corresponding original H/N/B/BHI data exists: "+entry.id)
	if failures: _finish(); return
	var Material: Script=load("res://modules/scene_engine/fidelity_island/terrain_material.gd")
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var materials: Array[ShaderMaterial]=[]
	for entry: Dictionary in definitions:
		var source: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(entry.path))
		var raw:=Profile.load_source(entry.id)
		check(source.get("width",0)==entry.width and source.get("height",0)==entry.height,"source-specific dimensions retained: "+entry.id)
		check(source.get("height_indices",[])==raw.values,"all original height bytes identical to existing height authority: "+entry.id)
		check(Material.valid_source(source),"source-specific BHI membership and normal dimensions accepted: "+entry.id)
		check(Material.load_source(entry.id)==source,"loader verifies and returns exact source record by profile ID")
		var weights:=FileAccess.get_file_as_bytes("res://assets/data/fidelity_island/"+entry.id+"-weights-f32.bin")
		var normals:=FileAccess.get_file_as_bytes("res://assets/data/fidelity_island/"+entry.id+"-normals-f32.bin")
		var matched_weights:=0; var matched_normals:=0
		for index in entry.width*entry.height:
			var pixel: Dictionary=Material.decode_pixel(source,index)
			for channel in Material.TEXTURE_IDS.size():
				var slot: int=pixel.ids.find(Material.TEXTURE_IDS[channel])
				var value: float=0.0 if slot<0 else pixel.weights[slot]
				if value==weights.decode_float((index*10+channel)*4): matched_weights+=1
			for axis in 3:
				if pixel.nativeNormal[axis]==normals.decode_float((index*3+axis)*4): matched_normals+=1
		check(matched_weights==entry.width*entry.height*10,"all real material weights equal untouched original JS oracle: "+entry.id)
		check(matched_normals==entry.width*entry.height*3,"all normals preserve original native RGB swizzle and float32 scale: "+entry.id)
		var profile:=Profile.new(); check(profile.configure(ports[entry.portIndex],raw,entry.id),"unchanged authority maps original material profile")
		var mapping: Dictionary=profile.diagnostics(); mapping.material_kind="game_adapted"
		check(Material.create_material(Material.load_source(),mapping)==null,"known profile rejects explicit wrong Cat BHI instead of silently mismapping")
		var material: ShaderMaterial=Material.create_material({},mapping); materials.append(material)
		check(material!=null and material.get_shader_parameter("use_source_material_field")==true,"known original profile uses its own BHI instead of height-based fallback: "+entry.id)
		if material==null: continue
		check(material.get_shader_parameter("source_size")==Vector2(entry.width,entry.height),"material field uses own size rather than Cat width/height")
		check(material.get_shader_parameter("native_texture_scale")==float(source.terrain.texturescale)*float(source.global.navtexturescaling),"material uses own native landscape/nav texture scales")
		check(material.get_shader_parameter("native_texture_offset")==Vector2(float(source.terrain.textureoffx),float(source.terrain.textureoffy)),"material uses own native landscape texture offset")
		check(Material.diagnostics(material).source==entry.path,"diagnostics identify corresponding original source rather than Cat")
		var texture: Texture2D=material.get_shader_parameter("source_weight_0")
		check(texture!=null and texture.get_width()==entry.width and texture.get_height()==entry.height,"cache retains actual corresponding weight field resolution")
		if not material.get_shader_parameter("use_source_material_field"): continue
		var row_x: Vector2=material.get_shader_parameter("source_uv_row_x")
		var row_z: Vector2=material.get_shader_parameter("source_uv_row_z")
		var offset: Vector2=material.get_shader_parameter("source_uv_offset")
		for pixel: Vector2 in [Vector2.ZERO,Vector2(entry.width-1,entry.height-1),Vector2(entry.width*.5,entry.height*.5)]:
			var world:=Coordinates.source_pixel_to_world(pixel,mapping)
			var uv:=Vector2(row_x.dot(world),row_z.dot(world))+offset
			check(uv.distance_to((pixel+Vector2(.5,.5))/Vector2(entry.width,entry.height))<.00001,"own source texture UV centers agree with unchanged world height mapping")
		var clone_mapping: Dictionary=mapping.duplicate(true); clone_mapping.islandCenter+=Vector2(731,121)
		var clone: ShaderMaterial=Material.create_material({},clone_mapping)
		check(clone!=null and clone!=material,"cloned island retains private mutable material")
		if clone!=null:
			check(clone.get_shader_parameter("source_weight_0")==texture,"cloned matching source shares immutable weight cache")
			check(clone.get_shader_parameter("source_uv_offset")!=offset and material.get_shader_parameter("source_uv_offset")==offset,"clone mapping cannot corrupt original material uniforms")
		var float_mapping: Dictionary=mapping.duplicate(true); float_mapping.packed_weights=false
		var float_material: ShaderMaterial=Material.create_material({},float_mapping)
		check(float_material!=null and float_material.get_shader_parameter("source_weight_0")!=texture,"compressed and raw native fields use distinct cache entries")
	if materials.size()==2:
		check(materials[0].get_shader_parameter("source_weight_0")!=materials[1].get_shader_parameter("source_weight_0"),"different profile IDs cannot share Cat cache or each other's weight atlas")
	var cat: Dictionary=Material.load_source()
	check(cat.width==120 and cat.height==140,"existing default Cat source remains unchanged")
	check(Material.load_source("unknown").is_empty(),"unknown source ID never returns Cat data")
	_finish()
func _finish() -> void:
	print("FIDELITY_MATERIAL_VARIANTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
