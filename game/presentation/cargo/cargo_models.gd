extends RefCounted
## Original cargo assets only. Cached scenes are immutable; callers own new nodes.
const AssetLibrary = preload("res://modules/scene_engine/assets/asset_library.gd")
const GOODS := ["grain", "water", "wood", "iron", "powder", "cloth", "silk", "porcelain", "tea", "sugar", "salt", "spices"]
const DIRECTORY := "res://assets/models/cargo_pack/r1/"
const MANIFEST := DIRECTORY + "manifest.json"
# AssetLibrary uses GLTFDocument append_from_file/generate_scene and PackedScene
# caching when original GLBs exist, including a checkout without .import files.
# Its imported PackedScene adapter also supports exported projects without GLBs.
static var _library = AssetLibrary.new()
var _paths: Dictionary = {}
var _checked := false
var _catalog_error := ""
var _last_error := ""

func get_model(good: String) -> Node3D:
	_last_error = ""
	if not good in GOODS:
		_last_error = "unsupported_good"
		return null
	if not _read_catalog():
		_last_error = _catalog_error
		return null
	var path: String = _paths[good]
	var model: Node3D = _library.instantiate_model(path)
	if model == null:
		_last_error = "asset_load_failed:" + good
		return null
	model.name = "Cargo_" + good
	model.set_meta("cargo_good", good)
	model.set_meta("cargo_asset_path", path)
	model.set_meta("cargo_model_origin", "original_blender_cargo_pack_r1")
	return model

func diagnostics() -> Dictionary:
	return {"catalog_valid": _checked and _catalog_error.is_empty(), "catalog_error": _catalog_error, "last_error": _last_error, "paths": _paths.duplicate(true), "cache": _library.get_model_load_diagnostics()}

func _read_catalog() -> bool:
	if _checked: return _catalog_error.is_empty()
	_checked = true
	if not FileAccess.file_exists(MANIFEST):
		_catalog_error = "cargo_manifest_missing"
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST))
	if not parsed is Dictionary:
		_catalog_error = "cargo_manifest_invalid"
		return false
	var manifest: Dictionary = parsed
	if manifest.get("goods", []) != GOODS or not manifest.get("assets", []) is Array:
		_catalog_error = "cargo_manifest_good_ids_mismatch"
		return false
	var found: Dictionary = {}
	for entry in manifest.assets:
		if not entry is Dictionary:
			_catalog_error = "cargo_manifest_entry_invalid"
			return false
		var good := str(entry.get("id", ""))
		var file := str(entry.get("file", ""))
		if not good in GOODS or found.has(good) or file != good + ".glb":
			_catalog_error = "cargo_manifest_asset_mismatch"
			return false
		found[good] = DIRECTORY + file
	if found.size() != GOODS.size():
		_catalog_error = "cargo_manifest_incomplete"
		return false
	_paths = found
	return true
