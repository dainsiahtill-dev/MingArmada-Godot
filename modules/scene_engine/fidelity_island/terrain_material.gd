extends RefCounted
## Original per-island BHI texture/weight inputs, mapped to existing Godot terrain.
## Default lighting retains the game's present scene. Source-light diagnostics
## are optional; this does not claim original D3D draw or framebuffer parity.

const Coordinates = preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const TerrainShader = preload("res://modules/scene_engine/fidelity_island/terrain.gdshader")
const SOURCE_PATH := "res://assets/data/fidelity_island/cat-island-original.json"
const MANIFEST_PATH := "res://assets/data/fidelity_island/manifest.json"
const TERRAIN_SCENE_PATH := "res://assets/data/fidelity_island/terrain-scene.json"
const SOURCE_PATHS := {
	"cat_island": SOURCE_PATH,
	"coastal2": "res://assets/data/fidelity_island/coastal2-original.json",
	"virgin_islands": "res://assets/data/fidelity_island/virgin-islands-original.json"
}
const SOURCE_HASHES := {
	"cat_island": "3b5fdc5b3b4bff1be775b869bb338bcdcaf46518755f1353bf036423c33a11ca",
	"coastal2": "b70f93a85b7dcad6fa9e9f1ab8b0e7a91cd498ccdf3f13c92c4414af0cef0b57",
	"virgin_islands": "bbd6fb2ac950e44ee2b7758be51ef29c5ac81744983e1eafbbc5cfec2bb39c09"
}
const TEXTURE_IDS := [1, 2, 3, 16, 17, 32, 33, 64, 48, 49]
const NIBBLE_SCALE := 0.06666667014360428
const NORMAL_SCALE := 0.007874015718698502
const TEXTURE_UNIFORMS := {
	1: "tex_ocean_1", 2: "tex_ocean_2", 3: "tex_ocean_3", 16: "tex_grass_patch",
	17: "tex_grass_beach", 32: "tex_rock", 33: "tex_rock_forest", 64: "tex_forest"
}
static var _default_source: Dictionary = {}
static var _source_cache: Dictionary = {}
static var _field_cache: Dictionary = {}
static var _textures: Dictionary = {}

static func load_source(id: String = "cat_island") -> Dictionary:
	if not SOURCE_PATHS.has(id):
		return {}
	if _source_cache.has(id):
		return _source_cache[id]
	var path: String = SOURCE_PATHS[id]
	if not FileAccess.file_exists(path) or FileAccess.get_sha256(path) != SOURCE_HASHES[id]:
		return {}
	var result: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if result is Dictionary and valid_source(result):
		_source_cache[id] = result
		if id == "cat_island":
			_default_source = result
		return result
	return {}

static func valid_source(source: Dictionary) -> bool:
	for key: String in ["width", "height"]:
		var value: Variant = source.get(key)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 2.0 or float(value) != floor(float(value)):
			return false
	var count := int(source.width) * int(source.height)
	if not source.get("height_indices") is Array or source.height_indices.size() != count:
		return false
	if not source.get("normal_rgb") is Array or source.normal_rgb.size() != count*3:
		return false
	if not source.get("blend_u32") is Array or source.blend_u32.size() != count:
		return false
	if not source.get("bhi_groups") is Dictionary or not source.get("terrain") is Dictionary or not source.get("textures") is Array or not source.get("global") is Dictionary:
		return false
	var fade_start := float(source.terrain.get("fadestart", NAN))
	var fade_end := float(source.terrain.get("fadeend", NAN))
	if not is_finite(fade_start) or not is_finite(fade_end) or fade_start <= fade_end:
		return false
	for index in count:
		var height: Variant = source.height_indices[index]
		var word: Variant = source.blend_u32[index]
		if not (height is int or height is float) or not is_finite(float(height)) or float(height) < 0.0 or float(height) > 255.0 or float(height) != floor(float(height)):
			return false
		if not (word is int or word is float) or not is_finite(float(word)) or float(word) < 0.0 or float(word) > 4294967295.0 or float(word) != floor(float(word)):
			return false
		var group: Variant = source.bhi_groups.get(str(int(word) & 4095))
		if not group is Array or group.size() != 5:
			return false
		for id: Variant in group:
			if not (id is int or id is float) or int(id) != float(id) or (int(id) != 0 and int(id) not in TEXTURE_IDS):
				return false
	for value: Variant in source.normal_rgb:
		if not (value is int or value is float) or not is_finite(float(value)) or float(value) < 0.0 or float(value) > 255.0 or float(value) != floor(float(value)):
			return false
	return true

static func _f32(value: float) -> float:
	return PackedFloat32Array([value])[0]

static func native_pack_byte(value: float) -> int:
	var scaled := value * 255.0
	var integer := int(scaled)
	var fraction := scaled - float(integer)
	return (integer + (1 if fraction > 0.5 else (-1 if fraction < -0.5 else 0))) & 255

static func decode_pixel(source: Dictionary, index: int) -> Dictionary:
	if index < 0 or not source.has("height_indices") or index >= source.height_indices.size():
		return {}
	var word := int(source.blend_u32[index])
	var group: Array = source.bhi_groups.get(str(word & 4095), [])
	if group.size() != 5:
		return {}
	var ids: Array[int] = []
	for id: Variant in group:
		if int(id) != 0:
			ids.append(int(id))
	var height := float(source.height_indices[index])
	var fade_start := float(source.terrain.fadestart)
	var fade_end := float(source.terrain.fadeend)
	var fade := 1.0 if height > fade_start else (0.0 if height < fade_end else (height-fade_end)/(fade_start-fade_end))
	var weights := PackedFloat32Array()
	var packed := PackedByteArray()
	var nibble_scale := _f32(NIBBLE_SCALE)
	for slot in ids.size():
		var weight := _f32(_f32(float((word >> (12+4*slot)) & 15)*nibble_scale)*fade)
		weights.append(weight)
		packed.append(native_pack_byte(weight))
	# The source scale is a stored float32. GDScript's decimal literal parser
	# may yield a nearby double; restore the exact f32 operand before an x87-style
	# product/store. Pixel858's 44*scale is a real halfway tie; approximation
	# incorrectly moved its normal from c662b13e to c562b13e.
	var normal_scale := _f32(NORMAL_SCALE)
	var normal := Vector3(_f32((float(source.normal_rgb[index*3+1])-128.0)*normal_scale),
		_f32((float(source.normal_rgb[index*3])-128.0)*normal_scale),
		_f32((float(source.normal_rgb[index*3+2])-128.0)*normal_scale))
	return {"group": word & 4095, "ids": ids, "weights": weights,
		"packedWeights": packed, "fade": fade, "height": height, "nativeNormal": normal}

static func build_material_field(source: Dictionary, packed_weights: bool = true) -> Dictionary:
	if not valid_source(source):
		return {}
	var width := int(source.width)
	var height := int(source.height)
	var weight_images: Array[Image] = []
	for _layer in 3:
		var image := Image.create(width, height, false, Image.FORMAT_RGBAF)
		image.fill(Color(0.0, 0.0, 0.0, 0.0))
		weight_images.append(image)
	var normals := Image.create(width, height, false, Image.FORMAT_RGBAF)
	var heights := Image.create(width, height, false, Image.FORMAT_RF)
	for index in width*height:
		var decoded := decode_pixel(source, index)
		var channels := PackedFloat32Array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
		for slot in decoded.ids.size():
			var target := TEXTURE_IDS.find(decoded.ids[slot])
			channels[target] = float(decoded.packedWeights[slot])/255.0 if packed_weights else decoded.weights[slot]
		var x := index % width
		var y := int(index / width)
		for layer in 3:
			var start := layer*4
			weight_images[layer].set_pixel(x, y, Color(channels[start], channels[start+1], channels[start+2], channels[start+3]))
		var normal: Vector3 = decoded.nativeNormal
		if packed_weights:
			# The original compressed VS decodes these three UBYTE channels.
			normal = Vector3(float(native_pack_byte((normal.x+1.0)*0.5))/255.0*2.0-1.0,
				float(native_pack_byte((normal.y+1.0)*0.5))/255.0*2.0-1.0,
				float(native_pack_byte((normal.z+1.0)*0.5))/255.0*2.0-1.0)
		normals.set_pixel(x, y, Color(normal.x, normal.y, normal.z, 1.0))
		heights.set_pixel(x, y, Color(float(decoded.height), 0.0, 0.0, 1.0))
	return {"weightImages": weight_images, "normalImage": normals, "heightImage": heights,
		"width": width, "height": height, "packedWeights": packed_weights,
		"identity": "Original per-island BHI independent nibble weights, original height fade, original normal swizzle; no normalization."}

static func _source_color(source: Dictionary, id: int) -> Vector3:
	for texture: Dictionary in source.textures:
		if int(texture.get("textureid", -1)) == id:
			var parts: PackedStringArray = str(texture.get("color", "")).split(",")
			if parts.size() == 3:
				return Vector3(float(parts[0]), float(parts[1]), float(parts[2]))/255.0
	return Vector3.ZERO

static func _load_textures() -> Dictionary:
	if not _textures.is_empty():
		return _textures
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
	if not manifest is Dictionary or not manifest.get("textures") is Array:
		return {}
	var next: Dictionary = {}
	for entry: Dictionary in manifest.textures:
		# The combined registry also contains coast/vegetation textures, whose
		# IDs legitimately are null. They are not terrain slots.
		if str(entry.get("group", "")) != "terrain":
			continue
		var raw_id: Variant = entry.get("id")
		if not (raw_id is int or raw_id is float) or not is_finite(float(raw_id)) or float(raw_id) != floor(float(raw_id)):
			return {}
		var id := int(raw_id)
		if not TEXTURE_UNIFORMS.has(id):
			continue
		var image: Image
		var compressed_path := str(entry.get("compressedMipPath", ""))
		var compressed_format := str(entry.get("godotCompressedImageFormat", ""))
		var formats := {"FORMAT_DXT1": Image.FORMAT_DXT1, "FORMAT_DXT3": Image.FORMAT_DXT3, "FORMAT_DXT5": Image.FORMAT_DXT5}
		var mip_path := str(entry.get("rgbaMipPath", ""))
		if formats.has(compressed_format) and FileAccess.file_exists(compressed_path):
			image = Image.create_from_data(int(entry.width), int(entry.height), bool(entry.get("mipmaps", false)), formats[compressed_format], FileAccess.get_file_as_bytes(compressed_path))
		elif FileAccess.file_exists(mip_path):
			var bytes := FileAccess.get_file_as_bytes(mip_path)
			image = Image.create_from_data(int(entry.width), int(entry.height), int(entry.get("mipLevels", 1)) > 1, Image.FORMAT_RGBA8, bytes)
		else:
			# Explicit preview fallback only; full mip registry is preferred.
			image = Image.load_from_file(str(entry.get("texturePath", "")))
		if image == null or image.is_empty():
			return {}
		next[id] = ImageTexture.create_from_image(image)
	for id: int in TEXTURE_UNIFORMS:
		if not next.has(id):
			return {}
	_textures = next
	return _textures

static func create_material(field: Dictionary = {}, mapping: Dictionary = {}) -> ShaderMaterial:
	var source_id := str(mapping.get("id", "cat_island"))
	var known_profile := SOURCE_PATHS.has(source_id)
	var source := load_source(source_id if known_profile else "cat_island") if field.is_empty() else field
	if source.is_empty() or not valid_source(source):
		return null
	if not field.is_empty() and known_profile and mapping.has("id") and source != load_source(source_id):
		return null
	if mapping.has("sourceCenter") and not Coordinates.valid_mapping(mapping):
		return null
	var textures := _load_textures()
	if textures.is_empty():
		return null
	# Height authority's source ID selects its matching BHI and native parameters.
	# Legacy "game_adapted" is a fallback request only when no known ID is supplied.
	var use_source := Coordinates.valid_mapping(mapping) and (known_profile and mapping.has("id") or str(mapping.get("material_kind", "cat_bhi")) != "game_adapted")
	if not known_profile and field.is_empty():
		use_source = false
	var material := ShaderMaterial.new()
	material.shader = TerrainShader
	if not use_source:
		var height_gain := clampf(float(mapping.get("heightGain",1.0)),0.1,1.0)
		# Compact source islands have real inland ground just above sea level.
		# Vegetation begins before distant mountain heights; otherwise a lowered
		# height profile incorrectly paints most habitable land as white beach.
		material.set_shader_parameter("game_land_start",1.0*height_gain)
		material.set_shader_parameter("game_land_end",5.0*height_gain)
	material.set_shader_parameter("native_sand_color", _source_color(source, 48))
	material.set_shader_parameter("native_wet_color", _source_color(source, 49))
	material.set_shader_parameter("native_texture_scale", float(source.terrain.texturescale)*float(source.global.navtexturescaling))
	material.set_shader_parameter("native_texture_offset", Vector2(float(source.terrain.textureoffx), float(source.terrain.textureoffy)))
	material.set_shader_parameter("native_cell_span", float(source.terrain.cellwidth)-1.0)
	for id: int in TEXTURE_UNIFORMS:
		material.set_shader_parameter(TEXTURE_UNIFORMS[id], textures[id])
	material.set_shader_parameter("use_source_material_field", use_source)
	if use_source:
		var packed := bool(mapping.get("packed_weights", true))
		var loaded_source: Dictionary = _source_cache.get(source_id, {})
		var cache_key := str(SOURCE_HASHES[source_id]) + (":packed" if packed else ":float") if known_profile and source == loaded_source else ""
		var maps: Dictionary = _field_cache.get(cache_key, {}) if not cache_key.is_empty() else {}
		if maps.is_empty():
			maps = build_material_field(source, packed)
			if maps.is_empty():
				return null
			maps["weightTextures"] = []
			for image: Image in maps.weightImages:
				maps.weightTextures.append(ImageTexture.create_from_image(image))
			maps["normalTexture"] = ImageTexture.create_from_image(maps.normalImage)
			maps["heightTexture"] = ImageTexture.create_from_image(maps.heightImage)
			if not cache_key.is_empty():
				_field_cache[cache_key] = maps
		for layer in 3:
			material.set_shader_parameter("source_weight_"+str(layer), maps.weightTextures[layer])
		material.set_shader_parameter("source_normal_texture", maps.normalTexture)
		material.set_shader_parameter("source_height_texture", maps.heightTexture)
		var uniforms := Coordinates.shader_mapping(mapping, int(source.width), int(source.height))
		for key: String in uniforms:
			material.set_shader_parameter(key, uniforms[key])
	material.set_shader_parameter("enable_source_lighting", bool(mapping.get("enable_source_lighting", false)))
	material.set_shader_parameter("use_source_normals", bool(mapping.get("use_source_normals", true)))
	material.set_shader_parameter("source_normal_strength", clampf(float(mapping.get("source_normal_strength", 0.35)), 0.0, 1.0))
	for key: String in ["source_light_direction", "source_light_color", "source_ambient"]:
		if mapping.get(key) is Vector3 and mapping[key].is_finite():
			material.set_shader_parameter(key, mapping[key])
	material.set_meta("fidelity_island_source", SOURCE_PATHS.get(source_id, SOURCE_PATH) if field.is_empty() else "custom source field")
	material.set_meta("fidelity_island_source_id", source_id if known_profile else "")
	material.set_meta("fidelity_island_scope", "Original "+source_id+" source BHI mapped to unchanged game terrain" if use_source else "Game terrain height/slope adaptation using original Cat material textures")
	return material

static func configure_chunk(chunk: MeshInstance3D, field: Dictionary = {}, mapping: Dictionary = {}) -> bool:
	if not is_instance_valid(chunk):
		return false
	var material := create_material(field, mapping)
	if material == null:
		return false
	chunk.material_override = material
	return true

static func diagnostics(material: ShaderMaterial) -> Dictionary:
	if material == null or material.shader != TerrainShader:
		return {}
	return {"scope": material.get_meta("fidelity_island_scope", ""),
		"source": material.get_meta("fidelity_island_source", SOURCE_PATH), "sourceId": material.get_meta("fidelity_island_source_id", ""), "originalMipRegistry": MANIFEST_PATH,
		"usesSourceBhi": material.get_shader_parameter("use_source_material_field"),
		"sourceLighting": material.get_shader_parameter("enable_source_lighting"),
		"nativeIds": TEXTURE_IDS.duplicate(), "normalAxes": "native[G,R,B] -> Godot[column,up,-row]",
		"normalization": false, "terrainGeometryModified": false}
