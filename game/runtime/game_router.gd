extends RefCounted
## Entry/save orchestration only. Scene owner decides when a ready candidate becomes visible.
const Storage = preload("res://game/persistence/save_coordinator.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const MingqiRuntime = preload("res://game/runtime/mingqi_runtime.gd")
const LegacyRuntime = preload("res://game/runtime/legacy_runtime.gd")
const Menu = preload("res://game/ui/menu/main_menu.gd")
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const DevelopmentAccess = preload("res://game/runtime/development_access.gd")
const MODES := ["mingqi","mingqi-continue","career","continue","duel","fleet","sail","qa","ships","laboratory","practice","water-study","fidelity-island","fidelity-source"]
const DEVELOPMENT_MODES := ["career","continue","qa","practice","water-study","fidelity-source"]
var generation := 1
var mingqi_storage: RefCounted
var legacy_storage: RefCounted
var settings_storage: RefCounted
var entry_factory: Callable
var dev := false
var qa := false
var _nonce := 0
var _active: Dictionary = {}
var _operation := 0
var _committed := -1
var _recovery: Dictionary = {}

func _init(dependencies: Dictionary = {}) -> void:
	mingqi_storage = dependencies.get("mingqi_storage",Storage.new("user://saves/mingqi-v2.json"))
	legacy_storage = dependencies.get("legacy_storage",Storage.new("user://saves/legacy-v1.json",LegacyRuntime.validate_save))
	settings_storage = dependencies.get("settings_storage",Settings.new())
	entry_factory = dependencies.get("entry_factory",Callable())
	dev = DevelopmentAccess.host_allows() and bool(dependencies.get("dev",false))
	qa = DevelopmentAccess.host_allows() and bool(dependencies.get("qa",false))

static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func view_model() -> Dictionary:
	var v2: Dictionary = mingqi_storage.read_checkpoint()
	var v1: Dictionary = legacy_storage.read_checkpoint()
	var v1_valid: bool = v1.get("ok",false) and LegacyRuntime.validate_save(v1.get("json","")).ok
	return {"settings":settings_storage.snapshot(),"hasLegacySave":v1_valid,"mingqiSlot":"present" if v2.get("ok",false) else "missing" if v2.get("reason") == "save-not-found" else "unreadable","dev":dev,"qa":qa}

func is_current(candidate: Dictionary) -> bool:
	return not _active.is_empty() and candidate.get("generation",-1) == generation and candidate.get("nonce",-1) == _active.nonce and candidate.get("operation",-1) == _operation

func cancel(next_generation: int = -1) -> void:
	generation = maxi(generation+1,next_generation); _active.clear(); _operation += 1; _recovery.clear()

func _stamp(result: Dictionary) -> Dictionary:
	var next := result.duplicate(true); next.generation = generation; next.nonce = _active.get("nonce",0); next.operation = _operation
	return next

func prepare_entry(request: Dictionary) -> Dictionary:
	if request.get("generation",-1) != generation or not request.get("nonce") is int or request.nonce <= _nonce: return _no("entry-stale")
	_nonce = request.nonce; _active = request.duplicate(true); _operation += 1; _recovery.clear()
	var type: String = request.get("entryType","") if request.get("type") == "retry" else request.get("type","")
	var mode: String = request.get("mode","") if type == "start" else type
	if mode == "quit": return _stamp({"ok":true,"quit":true})
	if mode not in MODES: return _stamp(_no("entry-unknown"))
	if mode in DEVELOPMENT_MODES and not (DevelopmentAccess.host_allows() and (dev or qa)): return _stamp(_no("entry-developer-only"))
	var seed: Variant = request.get("qaSeed",randi())
	if not seed is int or seed < 0 or seed > 4294967295: return _stamp(_no("entry-invalid-seed"))
	var options := {"mode":mode,"captainName":Menu.normalized_name(request.get("name",Menu.DEFAULT_NAME)),"seed":seed,"handlingMode":settings_storage.snapshot().handling,"dev":dev,"qa":qa}
	if mode == "mingqi-continue": return _restore(mingqi_storage.read_checkpoint(),"mingqi",options,true)
	if mode == "continue": return _restore(legacy_storage.read_checkpoint(),"career",options,false)
	return _stamp({"ok":true,"mode":mode,"options":options,"initial_save":"","explicit_import":false,"persist_name":type == "start" and mode != "laboratory"})

func _validate(raw: String, mode: String) -> Dictionary:
	if mode == "career": return LegacyRuntime.validate_save(raw)
	var decoded: Dictionary = Codec.decode(raw)
	if not decoded.ok: return decoded
	var candidate := MingqiRuntime.new()
	var configured: Dictionary = candidate.configure(func(_x: float,_z: float) -> float: return -24.0)
	var adopted: Dictionary = candidate.adopt_save(raw,null) if configured.ok else configured
	candidate.dispose(); return adopted

func _restore(read: Dictionary, mode: String, options: Dictionary, recovery: bool, explicit_import: bool = false) -> Dictionary:
	var raw: String = read.get("json","")
	var validated: Dictionary = _validate(raw,mode) if read.get("ok",false) else _no(read.get("reason","save-read-failed"))
	if not validated.ok:
		if recovery:
			_recovery = {"reason":validated.get("reason","save-invalid"),"raw":raw,"has_raw":read.has("json"),"options":options.duplicate(true)}
		return _stamp({"ok":false,"recovery":recovery,"reason":validated.get("reason","save-invalid")})
	return _stamp({"ok":true,"mode":mode,"options":options.duplicate(true),"initial_save":raw,"explicit_import":explicit_import})

func recovery_snapshot() -> Dictionary: return _recovery.duplicate(true)
func export_recovery() -> Dictionary:
	return {"ok":true,"json":_recovery.raw,"kind":"raw-recovery"} if _recovery.get("has_raw",false) else _no("recovery-bytes-unavailable")
func export_backup() -> Dictionary:
	var read: Dictionary = mingqi_storage.read_backup()
	if not read.get("ok",false): return read
	var validated := _validate(read.json,"mingqi")
	return {"ok":true,"json":read.json,"kind":"verified-checkpoint"} if validated.ok else validated

func prepare_recovery(intent: Dictionary) -> Dictionary:
	if _active.is_empty() or _recovery.is_empty(): return _no("recovery-unavailable")
	_operation += 1
	var options: Dictionary = _recovery.options.duplicate(true)
	var read: Dictionary
	var importing := false
	match intent.get("type",""):
		"retry": read = mingqi_storage.read_checkpoint()
		"read-backup": read = mingqi_storage.read_backup()
		"import-json": read = {"ok":true,"json":intent.get("json","")}; importing = true
		"import-file":
			var file := FileAccess.open(intent.get("path",""),FileAccess.READ)
			if file == null: return _stamp(_no("import-read-failed"))
			if file.get_length() > 16*1024*1024: file.close(); return _stamp(_no("save-too-large"))
			var raw := file.get_as_text(); var failed := file.get_error() not in [OK,ERR_FILE_EOF]; file.close()
			if failed: return _stamp(_no("import-read-failed"))
			read = {"ok":true,"json":raw}; importing = true
		_: return _stamp(_no("recovery-action-unknown"))
	# Failed imports preserve the original recovery evidence, rather than replacing it with attempted input.
	var before := _recovery.duplicate(true)
	var prepared := _restore(read,"mingqi",options,true,importing)
	if not prepared.ok:
		if intent.get("type") != "retry": _recovery = before
		elif not _recovery.get("has_raw",false) and before.get("has_raw",false):
			_recovery.raw = before.raw; _recovery.has_raw = true
	return prepared

func commit_import(candidate: Dictionary) -> Dictionary:
	if not is_current(candidate): return _no("entry-stale")
	if not candidate.get("explicit_import",false): return {"ok":true}
	if _committed == _operation: return _no("import-already-committed")
	var written: Dictionary = mingqi_storage.write_checkpoint(candidate.initial_save)
	if written.ok: _committed = _operation
	return written

func create_scene(candidate: Dictionary) -> Dictionary:
	if not is_current(candidate): return _no("entry-stale")
	var mode: String = candidate.mode
	if mode in DEVELOPMENT_MODES and not (DevelopmentAccess.host_allows() and (dev or qa)): return _no("entry-developer-only")
	var node: Node
	if mode in ["mingqi","career"] or not entry_factory.is_valid() and mode in ["ships","practice","qa","water-study","fidelity-island","fidelity-source"]:
		var paths := {"mingqi":"res://game/scenes/mingqi/mingqi_scene.tscn","career":"res://game/scenes/legacy/legacy_scene.tscn","ships":"res://game/scenes/ship_book/ship_book.tscn","practice":"res://game/scenes/practice/practice.tscn","qa":"res://game/scenes/visual_qa/visual_qa.tscn","water-study":"res://game/scenes/reference_island_water/reference_island_water.tscn","fidelity-island":"res://game/scenes/fidelity_island/fidelity_island.tscn","fidelity-source":"res://game/scenes/fidelity_island/fidelity_source.tscn"}
		var scene_path: String = paths[mode]
		var resource = load(scene_path)
		if not resource is PackedScene: return _no("entry-resource-unavailable")
		node = resource.instantiate()
	elif entry_factory.is_valid():
		var result: Variant = entry_factory.call(mode,candidate.options.duplicate(true))
		if result is Dictionary:
			if not result.get("ok",false): return result
			node = result.get("scene")
		elif result is Node: node = result
	elif mode in ["duel","fleet","sail","laboratory"]:
		var resource = load("res://game/research/laboratory.gd" if mode == "laboratory" else "res://game/scenes/naval_practice/naval_practice.gd")
		if resource is GDScript: node = resource.new()
	if not node: return _no("entry-resource-unavailable")
	for property in node.get_property_list():
		match property.name:
			"startup_options":
				var options: Dictionary = candidate.options.duplicate(true)
				options.staged = true
				if mode == "mingqi": options.captainName = native_captain_name(options.captainName)
				node.set("startup_options",options)
			"initial_save": node.set("initial_save",candidate.initial_save)
			"storage": node.set("storage",mingqi_storage if mode == "mingqi" else legacy_storage)
			"settings_storage": node.set("settings_storage",settings_storage)
	return {"ok":true,"scene":node}

static func native_captain_name(source: String) -> String:
	# Settings/legacy retain reversible JS UTF16 text. Native1650 accepts Unicode scalars.
	var units: Array = Text.utf16_units(source); var native := ""; var index := 0
	while index < units.size():
		var unit: int = units[index]; index += 1
		if unit >= 0xd800 and unit <= 0xdbff and index < units.size() and units[index] >= 0xdc00 and units[index] <= 0xdfff:
			native += String.chr(0x10000+((unit-0xd800)<<10)+(units[index]-0xdc00)); index += 1
		elif unit < 32 or unit == 127 or unit >= 0xd800 and unit <= 0xdfff: native += String.chr(0xfffd)
		else: native += String.chr(unit)
	return native
