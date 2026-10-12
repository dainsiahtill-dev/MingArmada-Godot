extends SceneTree
## Headless Godot acceptance of imported JSON, source records and exact RGBA images.
## Uses Image.load directly; never opens a window or evaluates particles.

var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL reference atmosphere resources: " + message)

func _json(file: String) -> Dictionary:
	var parser := JSON.new()
	var status := parser.parse(FileAccess.get_file_as_string(file))
	_check(status == OK and parser.data is Dictionary, "JSON parse " + file)
	if status != OK or not parser.data is Dictionary:
		return {}
	return parser.data

func _run() -> void:
	var definitions := _json("res://assets/data/reference_atmosphere/definitions/systems.json")
	var coverage := _json("res://assets/data/reference_atmosphere/coverage.json")
	var provenance := _json("res://assets/provenance/reference-atmosphere.json")
	var systems: Array = definitions.get("systems", [])
	_check(systems.size() == 276, "all 276 authored systems")
	_check(definitions.get("effects", []).size() == 16, "16 particle effect roots")
	var ids := {}
	var capacity := 0
	for system in systems:
		var id: String = system.get("id", "")
		_check(not ids.has(id) and not id.is_empty(), "unique source block identity")
		ids[id] = true
		_check(system.get("emitters", []).size() > 0, "authored emitter retained")
		_check(system.get("modifiers", []).size() > 0, "authored modifiers retained")
		_check(system.get("controllers", []).size() > 0, "authored controller flags retained")
		_check(system.get("property_chains", []).size() == system.get("texture_paths", []).size(), "all inheritance paths retained")
		capacity += int(system.get("particle_capacity", 0))
	_check(capacity == 3692, "authored particle capacity")
	for asset in definitions.get("source_assets", []):
		var data := _json(str(asset.resource))
		_check(data.get("raw", "") == asset.raw and data.get("sha256", "") == asset.sha256, "complete source identity")
		_check(data.get("blocks", []).size() == int(asset.block_count), "complete block array")
		_check(data.get("whole_file_consumed", false), "full original asset parsed")
	for texture in provenance.get("textures", []):
		var image := Image.new()
		_check(image.load(str(texture.resource)) == OK, "Godot loads PNG " + str(texture.id))
		if image.is_empty():
			continue
		_check(image.get_width() == int(texture.width) and image.get_height() == int(texture.height), "RGBA dimensions")
		image.convert(Image.FORMAT_RGBA8)
		var hasher := HashingContext.new()
		_check(hasher.start(HashingContext.HASH_SHA256) == OK, "SHA256 available")
		hasher.update(image.get_data())
		_check(hasher.finish().hex_encode() == texture.decoded_rgba_sha256, "Godot exact decoded RGBA " + str(texture.id))
	_check(coverage.runtime.resource_definitions_verified, "resource coverage verified")
	_check(not coverage.runtime.all_276_behaviors_restored, "parameters do not claim a full solver")
	print(JSON.stringify({"test": "reference_atmosphere_resources", "checks": checks, "failures": failures, "systems": systems.size(), "textures": provenance.get("textures", []).size()}))
	print("REFERENCE_ATMOSPHERE_RESOURCES_TESTS assertions=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
