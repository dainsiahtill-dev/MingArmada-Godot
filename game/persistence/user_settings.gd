extends RefCounted
## Detached source-compatible settings; disk write must succeed before live adoption.
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const SourceJSON = preload("res://game/domain/legacy/json_numbers.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
const VERSION := 1
const NUMERIC := ["soundVolume","musicVolume","cameraShake","horizonStability"]
const BOOLEAN := ["sound","music","reducedMotion","cameraFollow"]
var path: String
var load_reason := "settings-not-loaded"
var _settings: Dictionary

func _init(settings_path: String = "user://settings.json") -> void:
	path = settings_path; _settings = defaults()

static func defaults() -> Dictionary:
	return {"handling":"assisted","quality":"balanced","sound":true,"music":true,"soundVolume":1.0,"musicVolume":0.7,"reducedMotion":false,"cameraShake":0.0,"cameraFollow":true,"horizonStability":1.0,"captainName":"沈沧海"}

static func _finite(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _captain(value: String) -> String:
	var units: Array = Text.utf16_units(Text.source_trim(value))
	var collapsed: Array = []; var in_space := false
	for unit in units:
		if Text.whitespace(unit):
			if not in_space: collapsed.append(32)
			in_space = true
		else: collapsed.append(unit); in_space = false
	return Text.from_units(collapsed.slice(0,24)) if not collapsed.is_empty() else "沈沧海"

static func normalise_settings(input: Dictionary) -> Dictionary:
	var result := defaults()
	var mode: Variant = input.get("handling",input.get("handlingMode","assisted"))
	result.handling = "realistic" if mode == "realistic" else "assisted"
	if input.get("quality") in ["low","high"]: result.quality = input.quality
	for key in BOOLEAN:
		if input.get(key) is bool: result[key] = input[key]
	for key in NUMERIC:
		if _finite(input.get(key)): result[key] = clampf(float(input[key]),0,1)
	if input.get("captainName") is String: result.captainName = _captain(input.captainName)
	return result

func snapshot() -> Dictionary: return _settings.duplicate(true)

func _receipt(ok: bool, reason: String) -> Dictionary:
	return {"ok":ok,"reason":reason,"settings":snapshot()}

func _decode(json: String) -> Dictionary:
	var parsed: Dictionary = SourceJSON.new().decode(json)
	if not parsed.ok or not parsed.value is Dictionary: return {"ok":false,"reason":"settings-invalid-json"}
	var payload: Dictionary = parsed.value
	if payload.get("version") != VERSION: return {"ok":false,"reason":"settings-unsupported-version"}
	if not payload.get("settings") is Dictionary: return {"ok":false,"reason":"settings-invalid-data"}
	var normalized := normalise_settings(payload.settings)
	return {"ok":true,"settings":normalized,"reason":"settings-loaded" if normalized == payload.settings else "settings-normalized"}

func load_settings() -> Dictionary:
	_settings = defaults()
	var actual := path
	if not FileAccess.file_exists(path) and FileAccess.file_exists(path+".rollback"): actual = path+".rollback"
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(actual)):
		load_reason = "settings-read-failed"; return _receipt(false,load_reason)
	if not FileAccess.file_exists(actual):
		load_reason = "settings-not-found"; return _receipt(true,load_reason)
	var file := FileAccess.open(actual,FileAccess.READ)
	if file == null: load_reason = "settings-read-failed"; return _receipt(false,load_reason)
	var json := file.get_as_text(); var failed := file.get_error() not in [OK,ERR_FILE_EOF]; file.close()
	if failed: load_reason = "settings-read-failed"; return _receipt(false,load_reason)
	var decoded := _decode(json)
	load_reason = decoded.reason
	if decoded.ok: _settings = decoded.settings
	return _receipt(decoded.ok,load_reason)

func _serialize(candidate: Dictionary) -> String:
	var members: PackedStringArray = []
	for key in candidate:
		var value: Variant = candidate[key]
		members.append(Text.json_string(key)+":"+(Text.json_string(value) if value is String else JSON.stringify(value)))
	return '{"version":1,"settings":{'+",".join(members)+'}}'

func update_settings(patch: Dictionary) -> Dictionary:
	var normalized_patch := patch.duplicate(true)
	if normalized_patch.has("handlingMode"):
		if normalized_patch.has("handling") and normalized_patch.handling != normalized_patch.handlingMode: return _receipt(false,"settings-invalid-handling")
		normalized_patch.handling = normalized_patch.handlingMode; normalized_patch.erase("handlingMode")
	for key in normalized_patch:
		var value: Variant = normalized_patch[key]
		if not _settings.has(key): return _receipt(false,"settings-unknown-field")
		if key in BOOLEAN and not value is bool: return _receipt(false,"settings-invalid-"+key)
		if key in NUMERIC and not _finite(value): return _receipt(false,"settings-invalid-"+key)
		if key == "handling" and value not in ["assisted","realistic"]: return _receipt(false,"settings-invalid-handling")
		if key == "quality" and value not in ["low","balanced","high"]: return _receipt(false,"settings-invalid-quality")
		if key == "captainName" and not value is String: return _receipt(false,"settings-invalid-captainName")
	var candidate := snapshot(); candidate.merge(normalized_patch,true); candidate = normalise_settings(candidate)
	var storage := Storage.new(path,_decode)
	var result: Dictionary = storage.write_checkpoint(_serialize(candidate))
	if not result.ok: return _receipt(false,String(result.reason).replace("save-","settings-"))
	_settings = candidate
	var receipt := _receipt(true,"settings-saved")
	if result.has("warning"): receipt.warning = String(result.warning).replace("save-","settings-")
	return receipt
