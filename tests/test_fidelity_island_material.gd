extends SceneTree

const FidelityMaterial = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const Profile = preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const SOURCE_SHA := "3b5fdc5b3b4bff1be775b869bb338bcdcaf46518755f1353bf036423c33a11ca"
var assertions := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, reason: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", reason)

func _run() -> void:
	check(FileAccess.get_sha256(FidelityMaterial.SOURCE_PATH) == SOURCE_SHA, "source copy retains the exact newest original Cat/BHI/normal record")
	var source := FidelityMaterial.load_source()
	check(FidelityMaterial.valid_source(source), "real imported source validates")
	if source.is_empty():
		_finish()
		return
	check(int(source.width) == 120 and int(source.height) == 140, "source keeps the original rectangular 120 by 140 samples")
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FidelityMaterial.MANIFEST_PATH))
	var original_weights := FileAccess.get_file_as_bytes(str(manifest.terrain.rawWeightsPath))
	var native_ids: Array = manifest.terrain.weightIds
	check(original_weights.size() == 120*140*10*4, "independently imported native weight stream is complete")
	var matched := 0
	var max_error := 0.0
	for index in 120*140:
		var decoded := FidelityMaterial.decode_pixel(source, index)
		for channel in native_ids.size():
			var slot: int = decoded.ids.find(int(native_ids[channel]))
			var actual: float = 0.0 if slot < 0 else decoded.weights[slot]
			var expected := original_weights.decode_float((index*10+channel)*4)
			max_error = maxf(max_error, absf(actual-expected))
			if actual == expected:
				matched += 1
	check(matched == 168000 and max_error == 0.0, "all 168000 float layer values equal the separate original-JS importer, not a regenerated Godot oracle")
	# Fixed observations from collect-native-fixtures.mjs -> untouched reference
	# terrain-native.mjs (51C690 / 4ED150 / 52FCF0), never produced by this GDScript.
	var fade := FidelityMaterial.decode_pixel(source, 858)
	check(fade.group == 2 and fade.ids == [3, 2] and fade.height == 110.0, "real underwater pixel retains BHI group and slot order")
	check(fade.weights[0] == 0.36666667461395264 and fade.weights[1] == 0.13333334028720856 and fade.fade == 0.5, "real height110 applies half fade to each independent nibble")
	check(fade.packedWeights == PackedByteArray([94, 34]), "compressed alpha uses original strict-tie byte conversion")
	check(absf(fade.weights[0]+fade.weights[1]-0.5) < 0.0000001, "underwater weights remain half coverage instead of being normalized to one")
	check(fade.nativeNormal == Vector3(0.03937007859349251, 0.34645670652389526, 0.9370078444480896), "real TGA sample preserves G,R,B axes and original float1/127")
	var five := FidelityMaterial.decode_pixel(source, 3998)
	check(five.group == 26 and five.ids == [64,49,48,33,17], "all five BHI material slots retain forest/wet/sand/rock-forest/beach roles")
	check(five.packedWeights == PackedByteArray([102,51,17,51,34]), "all five source packed weights match the real sample")
	check(FidelityMaterial.decode_pixel(source, 617).weights[0] == 0.0 and FidelityMaterial.decode_pixel(source, 618).packedWeights[0] == 10, "height100 and101 straddle the original fade boundary")
	check(FidelityMaterial.native_pack_byte(0.5) == 127, "original .5 byte tie truncates rather than modern nearest-rounding")
	var field := FidelityMaterial.build_material_field(source, false)
	var wx: int = 858 % 120
	var wy: int = int(858 / 120)
	var w0: Color = field.weightImages[0].get_pixel(wx, wy)
	check(w0.r == 0.0 and w0.g == fade.weights[1] and w0.b == fade.weights[0], "shader texture channels carry actual material IDs rather than BHI slot positions")
	var sand_pixel: Color = field.weightImages[2].get_pixel(3998 % 120, int(3998 / 120))
	check(sand_pixel.r == five.weights[2] and sand_pixel.g == five.weights[1], "48 dry sand and49 wet sand stay separate channels")
	check(field.normalImage.get_pixel(wx, wy).r == fade.nativeNormal.x and field.heightImage.get_pixel(wx, wy).r == 110.0, "data textures preserve source normal and raw height without sRGB conversion")
	var profile := Profile.new()
	var port := {"x":0.0, "z":0.0, "islandX":-96.0, "islandZ":-30.0, "radius":120.0, "peak":48.0}
	check(profile.configure(port, Profile.load_source("cat_island"), "cat_island"), "mapping is obtained from the actual retained port height authority")
	var mapping: Dictionary = profile.diagnostics()
	check(Coordinates.valid_mapping(mapping), "actual authority diagnostics establish an accepted rigid map")
	var center: Vector2 = mapping.sourceCenter
	check(Coordinates.source_pixel_to_world(center, mapping).distance_to(mapping.islandCenter) < 0.00001, "source center aligns with existing island center")
	for pixel: Vector2 in [Vector2.ZERO, Vector2(119,139), Vector2(13,21), center]:
		var world := Coordinates.source_pixel_to_world(pixel, mapping)
		check(Coordinates.world_to_source_pixel(world, mapping).distance_to(pixel) < 0.0001, "both source axes round trip through the retained port orientation")
	var uniforms := Coordinates.shader_mapping(mapping, 120, 140)
	var sample_world := Coordinates.source_pixel_to_world(Vector2(13,21), mapping)
	var sample_uv: Vector2 = Vector2(uniforms.source_uv_row_x.dot(sample_world), uniforms.source_uv_row_z.dot(sample_world)) + uniforms.source_uv_offset
	check(sample_uv.distance_to(Vector2(13.5/120.0,21.5/140.0)) < 0.000001, "shader uses original pixel centers, including rotation and source row direction")
	var scene: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FidelityMaterial.TERRAIN_SCENE_PATH))
	var native := Coordinates.source_pixel_to_native_components(Vector2(13,21),110.0,scene,true)
	check(Coordinates.native_to_source_pixel(native,scene,true).distance_to(Vector2(13,21)) < 0.0002, "native root translation is subtracted once in double components before final Vector2 conversion")
	var display_native := Coordinates.source_pixel_to_native(Vector2(13,21),110.0,scene,true)
	check(Coordinates.native_to_source_pixel(display_native,scene,true) != Vector2(13,21), "large-origin Vector3 display coordinates are explicitly quantized and not mislabeled as a lossless source transport")
	check(Coordinates.native_direction_to_world(Vector3(3,5,7),{"sourceCenter":Vector2.ZERO,"sourceOutward":Vector2.DOWN,"islandCenter":Vector2.ZERO,"inward":Vector2.UP,"scale":1.0}) == Vector3(-3,7,-5), "mapped viewer directions share original normal basis instead of using an unrelated canonical axis map")
	check(Coordinates.native_to_godot(Vector3(3,5,7)) == Vector3(3,7,-5), "native to Godot axes are explicit and handedness preserving")
	var before_height := profile.sample_height(sample_world.x,sample_world.y)
	var material := FidelityMaterial.create_material({}, mapping)
	check(material != null, "real original DDS/mip registry creates the Godot terrain material")
	if material != null:
		check(material.get_shader_parameter("native_sand_color") == Vector3(1.0,251.0/255.0,1.0), "48 uses original landscape color instead of a guessed sand tint")
		check(material.get_shader_parameter("native_wet_color") == Vector3(222.0/255.0,205.0/255.0,160.0/255.0), "49 uses original landscape wet-sand color")
		check(bool(material.get_shader_parameter("use_source_material_field")), "Cat BHI is used only with a valid source-to-port map")
		check(not bool(material.get_shader_parameter("enable_source_lighting")), "existing formal-world lighting remains the default")
		var other := FidelityMaterial.create_material({}, {"material_kind":"game_adapted"})
		check(other != null and not bool(other.get_shader_parameter("use_source_material_field")), "other ports use real textures without pretending their BHI was recovered")
		check(FidelityMaterial.diagnostics(other).scope.contains("height/slope adaptation"), "non-Cat port material carries explicit adaptation identity")
		check(other != material, "materials and mutable scene uniforms remain private per profile")
		for id: int in FidelityMaterial.TEXTURE_UNIFORMS:
			var tex: Texture2D = material.get_shader_parameter(FidelityMaterial.TEXTURE_UNIFORMS[id])
			check(tex != null and tex.get_width() == 512 and tex.get_height() == 512, "each original material texture is present at native dimensions")
			check(tex.get_image().has_mipmaps() and tex.get_image().get_format() in [Image.FORMAT_DXT1,Image.FORMAT_DXT3,Image.FORMAT_DXT5], "original compressed DDS mip chain is used without Godot regenerated mips")
		var chunk := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		chunk.mesh = mesh
		var collider := StaticBody3D.new()
		chunk.add_child(collider)
		check(FidelityMaterial.configure_chunk(chunk,{},mapping), "chunk accepts the new independent material")
		check(chunk.mesh == mesh and chunk.get_child(0) == collider, "material integration does not mutate visual geometry or collider ownership")
		var accepted := chunk.material_override
		check(not FidelityMaterial.configure_chunk(chunk,{"width":120},{}) and chunk.material_override == accepted, "invalid source fails atomically and retains the working material")
		chunk.free()
	check(profile.sample_height(sample_world.x,sample_world.y) == before_height, "port sampling is unchanged by all material operations")
	var shader := FileAccess.get_file_as_string("res://modules/scene_engine/fidelity_island/terrain.gdshader")
	check(not shader.contains("TIME") and not shader.contains("VERTEX ="), "shader neither owns a wall clock nor displaces terrain")
	check(not shader.contains("ALPHA =") and shader.contains("underdark*clamp(weight_sum"), "opaque Godot adapter keeps UnderDark weighted alpha RGB without transparent land sorting")
	check(shader.contains("enable_source_lighting") and shader.contains("source_normal.x - source_row_axis*source_normal.y"), "source lighting path and native normal axes remain explicitly available")
	_finish()

func _finish() -> void:
	print("FIDELITY_ISLAND_MATERIAL_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
