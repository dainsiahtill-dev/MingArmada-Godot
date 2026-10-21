extends SceneTree
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void:
	var library := Library.new()
	var path := "res://assets/models/sailors/sailor-lod0.glb"
	var first := library.instantiate_model(path)
	var second := library.instantiate_model(path)
	check(first != null and second != null and first != second, "the cache returns independently owned model Nodes")
	var first_ref: WeakRef = weakref(first)
	var second_ref: WeakRef = weakref(second)
	if library.has_method("get_model_load_diagnostics"):
		var info: Dictionary = library.get_model_load_diagnostics()
		print("ASSET_LIBRARY_LOAD_DIAGNOSTICS ",JSON.stringify(info))
		check(info.runtimeImports == 1 and info.importedScenes == 0 and info.cacheHits == 1 and info.modelInstances == 2 and info.cachedScenes == 1, "diagnostics count actual authoring imports, cache reuse and issued instances")
		check(info.adapters.get(path) == "source-authoring", "diagnostics identify the active compatibility adapter")
		info.adapters.clear()
		check(library.get_model_load_diagnostics().adapters.has(path), "diagnostics do not expose mutable cache metadata")
	else: check(false, "asset library exposes explicit resource adapter and ownership diagnostics")
	library.dispose(); library.dispose()
	check(is_instance_valid(first) and is_instance_valid(second), "cache disposal preserves caller-owned model instances")
	check(library.get_cached_count() == 0 and library.instantiate_model(path) == null, "disposed cache releases resources and rejects late attachments")
	if library.has_method("get_model_load_diagnostics"):
		var info: Dictionary = library.get_model_load_diagnostics()
		check(info.disposed and info.cachedScenes == 0 and info.adapters.is_empty() and info.modelInstances == 2, "disposed diagnostics retain counts without retaining cached resources")
	first.free(); second.free()
	check(first_ref.get_ref() == null and second_ref.get_ref() == null, "consumer disposal leaves no model Nodes retained by the asset cache")
	print("ASSET_LIBRARY_OWNERSHIP_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
