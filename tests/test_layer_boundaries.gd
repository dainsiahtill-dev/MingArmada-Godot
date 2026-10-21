extends SceneTree
## Architecture acceptance: injected callbacks are allowed; concrete reverse imports are not.

const ROOTS := ["res://modules/contracts", "res://modules/physics_engine", "res://modules/scene_engine", "res://modules/environment_engine", "res://modules/naval_simulation", "res://game/domain"]
# Existing source-data algorithms live under the older scene package. The
# authority may reuse only these audited scalar/compiler helpers, never a
# renderer. They also receive the pure-code guard below.
const SHARED_SOURCE_DATA := ["res://modules/scene_engine/fidelity_fx/cloud_native.gd", "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd", "res://modules/scene_engine/fidelity_island/native_math.gd", "res://modules/scene_engine/fidelity_island/daylight.gd"]
# Transitive numerical helpers inherit purity without becoming additional
# environment-layer import entry points.
const SHARED_SOURCE_HELPERS := ["res://modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd", "res://modules/scene_engine/fidelity_fx/cloud_curve_sampler.gd"]
var failures: Array[String] = []
var assertions := 0
var scanned := 0
var project_classes: Dictionary = {}

func _initialize() -> void:
	_self_test()
	for folder in ["res://modules", "res://game"]:
		for file in _files(folder):
			if file.ends_with(".gd"):
				var match_class := _regex("(?m)^\\s*class_name\\s+(\\w+)").search(_without_comments(FileAccess.get_file_as_string(file)))
				if match_class: project_classes[match_class.get_string(1)] = file
	for folder in ROOTS:
		_check(DirAccess.dir_exists_absolute(folder), "Missing guarded root: " + folder)
		for file in _files(folder):
			scanned += 1
			for violation in _violations(file, FileAccess.get_file_as_string(file)):
				failures.append(file + ": " + violation)
	_check(scanned > 0, "Architecture scan must examine actual project files")
	for message in failures: printerr("FAIL: ", message)
	print("LAYER_BOUNDARY_TESTS assertions=", assertions, " files=", scanned, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)

func _self_test() -> void:
	_check(not _violations("res://modules/contracts/fixture.gd", 'extends RefCounted\nconst Bad = preload("res://game/domain/mingqi/campaign.gd")').is_empty(), "Guard rejects reverse game dependency")
	_check(not _violations("res://modules/scene_engine/fixture.gd", 'extends Node3D\nconst Bad = preload("res://modules/physics_engine/ocean/wave_field.gd")').is_empty(), "Guard rejects renderer physics import")
	_check(not _violations("res://modules/physics_engine/ships/fixture.gd", 'extends RefCounted\nvar bad = Node3D.new()').is_empty(), "Numerical physics must not create scene nodes")
	_check(not _violations("res://game/domain/fixture.gd", 'extends RefCounted\nvar bad = Time.get_ticks_msec()').is_empty(), "Domain must not advance from wall clock")
	_check(not _violations("res://modules/scene_engine/ocean/fixture.gdshader", 'shader_type spatial;\nvoid vertex() { VERTEX.y = sin(TIME); }').is_empty(), "Ocean shader must consume supplied game time")
	_check(_violations("res://modules/physics_engine/impacts/fixture.gd", 'extends RigidBody3D\nvar sampler: Callable\nfunc _integrate_forces(state: PhysicsDirectBodyState3D):\n\tvar scale = state.step').is_empty(), "Jolt body adapter and injected sampler are allowed")
	_check(_violations("res://modules/scene_engine/fixture.gd", 'extends Node3D\nconst Contract = preload("res://modules/contracts/wave_descriptor.gd")\nvar sampler: Callable\n# TIME and res://game/ are comments').is_empty(), "Injected renderer and contract dependencies are allowed")
	_check(not _violations("res://modules/physics_engine/ships/fixture.gd", 'extends RefCounted\nconst Bad = preload("../../scene_engine/world/world_view.gd")').is_empty(), "Relative imports cannot bypass layer guard")
	_check(not _violations("res://modules/naval_simulation/fixture.gd", 'extends RefCounted\nconst Bad = preload("res://game/runtime/mingqi_runtime.gd")').is_empty(), "Naval simulation cannot import gameplay runtime")
	_check(not _violations("res://modules/naval_simulation/fixture.gd", 'extends RefCounted\nvar bad = Node3D.new()').is_empty(), "Naval simulation cannot construct render nodes")
	_check(_violations("res://modules/naval_simulation/fixture.gd", 'extends RefCounted\nconst Weather = preload("res://modules/environment_engine/weather_state.gd")').is_empty(), "Naval authority may consume independent environment state")
	_check(not _violations("res://modules/environment_engine/fixture.gd", 'extends RefCounted\nconst Bad = preload("res://modules/scene_engine/world/world_view.gd")').is_empty(), "Environment cannot import a scene renderer")
	_check(not _violations("res://modules/environment_engine/fixture.gd", 'extends RefCounted\nvar bad = Node3D.new()').is_empty(), "Environment must remain independent of scene nodes")
	_check(not _violations(SHARED_SOURCE_DATA[1], 'extends RefCounted\nvar bad = ImageTexture.new()').is_empty(), "Shared scalar compiler cannot acquire GPU presentation resources")
	for helper: String in SHARED_SOURCE_HELPERS:
		_check(not _violations(helper, 'extends RefCounted\nvar bad = Node3D.new()').is_empty(), "Shared numerical helper cannot create scene nodes: " + helper)
		_check(not _violations(helper, 'extends RefCounted\nvar bad = ImageTexture.new()').is_empty(), "Shared numerical helper cannot acquire GPU textures: " + helper)
		_check(not _violations(helper, 'extends RefCounted\nvar bad = Time.get_ticks_usec()').is_empty(), "Shared numerical helper cannot own a wall clock: " + helper)
		_check(_violations(helper, 'extends RefCounted\nvar values = PackedFloat32Array([1.0, 2.0])').is_empty(), "Shared numerical helper retains pure value storage: " + helper)

func _violations(file: String, source: String) -> Array[String]:
	var result: Array[String] = []
	var clean := _without_comments(source)
	var code := _without_strings(clean)
	var dependencies: Array[String] = []
	for literal in _regex('["\']([^"\'\\n]+)["\']').search_all(clean):
		var value: String = literal.get_string(1)
		if value.begins_with("res://"): dependencies.append(value.simplify_path())
	for relative in _regex('(?:\\b(?:preload|load)\\s*\\(\\s*|(?m:^\\s*extends\\s+))["\']([^"\']+)["\']').search_all(clean):
		var value: String = relative.get_string(1)
		if not value.begins_with("res://"):
			dependencies.append(file.get_base_dir().path_join(value).simplify_path())
	for dependency in dependencies:
		if not _dependency_allowed(file, dependency): result.append("forbidden dependency " + dependency)
	var words: Dictionary = {}
	for word in _regex("\\b[A-Za-z_][A-Za-z_0-9]*\\b").search_all(code): words[word.get_string()] = true
	for word: String in words:
		if project_classes.has(word) and not _dependency_allowed(file, project_classes[word]):
			result.append("forbidden project class " + word + " from " + project_classes[word])
		var numerical := file.begins_with("res://modules/physics_engine/") and not file.begins_with("res://modules/physics_engine/impacts/")
		var pure := numerical or file.begins_with("res://modules/contracts/") or file.begins_with("res://game/domain/") or file.begins_with("res://modules/naval_simulation/") or file.begins_with("res://modules/environment_engine/") or file in SHARED_SOURCE_DATA or file in SHARED_SOURCE_HELPERS
		if ClassDB.class_exists(word):
			if pure and (word == "SceneTree" or ClassDB.is_parent_class(word, "Node")):
				result.append("pure code uses native scene type " + word)
			if pure and (ClassDB.is_parent_class(word, "Material") or ClassDB.is_parent_class(word, "Mesh") or ClassDB.is_parent_class(word, "Shader") or ClassDB.is_parent_class(word, "Texture") or ClassDB.is_parent_class(word, "Font") or ClassDB.is_parent_class(word, "AudioStream") or word == "Animation"):
				result.append("pure code uses native presentation resource " + word)
			if file.begins_with("res://modules/physics_engine/") and (ClassDB.is_parent_class(word, "VisualInstance3D") or ClassDB.is_parent_class(word, "Control")):
				result.append("physics adapter uses native presentation type " + word)
		if pure and word.begins_with("PhysicsServer"):
			result.append("pure code uses native physics server " + word)
		if file.begins_with("res://game/domain/") and ClassDB.class_exists(word) and (word.begins_with("Physics") or ClassDB.is_parent_class(word, "Shape3D") or word == "World3D"):
			result.append("domain uses native physics type " + word)
	if _regex("\\b(?:Time|Input|InputMap)\\b|\\bOS\\s*\\.\\s*(?:get_ticks|delay_)|\\bEngine\\s*\\.\\s*get_(?:physics|process)_frames|\\b(?:get_process_delta_time|get_physics_process_delta_time)\\s*\\(|\\bfunc\\s+_(?:process|physics_process)\\s*\\(").search(code):
		result.append("layer owns hidden clock, input, or engine process callback")
	if file.begins_with("res://modules/scene_engine/ocean/") and file.get_extension() in ["gdshader", "gdshaderinc"] and _regex("\\bTIME\\b").search(code):
		result.append("ocean shader uses renderer TIME instead of supplied simulation time")
	return result

func _dependency_allowed(file: String, dependency: String) -> bool:
	var allowed: Array[String] = ["res://modules/contracts/"]
	if file.begins_with("res://modules/physics_engine/"): allowed.append("res://modules/physics_engine/")
	elif file.begins_with("res://modules/naval_simulation/"): allowed.append_array(["res://modules/naval_simulation/", "res://modules/physics_engine/", "res://modules/environment_engine/"])
	elif file.begins_with("res://modules/environment_engine/"):
		allowed.append_array(["res://modules/environment_engine/", "res://assets/"])
		if dependency in SHARED_SOURCE_DATA:return true
	elif file.begins_with("res://modules/scene_engine/"): allowed.append_array(["res://modules/scene_engine/", "res://assets/"])
	elif file.begins_with("res://game/domain/"): allowed.append("res://game/domain/")
	for prefix in allowed:
		if dependency.begins_with(prefix): return true
	return false

func _check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition: failures.append(message)

func _regex(pattern: String) -> RegEx:
	var expression := RegEx.new()
	expression.compile(pattern)
	return expression

func _files(folder: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(folder)
	if not directory: return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var file := folder.path_join(entry)
			if directory.current_is_dir(): result.append_array(_files(file))
			elif file.get_extension() in ["gd", "gdshader", "gdshaderinc", "tscn", "tres"]: result.append(file)
		entry = directory.get_next()
	directory.list_dir_end()
	result.sort()
	return result

func _without_comments(source: String) -> String:
	var result := ""
	var quote := ""
	var escaped := false
	var block := false
	var index := 0
	while index < source.length():
		var character := source.substr(index, 1)
		var pair := source.substr(index, 2)
		if block:
			if pair == "*/": block = false; index += 2; continue
			result += "\n" if character == "\n" else " "
		elif quote != "":
			result += character
			if escaped: escaped = false
			elif character == "\\": escaped = true
			elif character == quote: quote = ""
		elif character in ['"', "'"]:
			quote = character
			result += character
		elif pair == "/*": block = true; index += 2; continue
		elif pair == "//" or (character == "#" and source.substr(index, 8) != "#include"):
			while index < source.length() and source.substr(index, 1) != "\n": index += 1
			continue
		else: result += character
		index += 1
	return result

func _without_strings(source: String) -> String:
	var result := ""
	var quote := ""
	var escaped := false
	for character in source:
		if quote != "":
			result += "\n" if character == "\n" else " "
			if escaped: escaped = false
			elif character == "\\": escaped = true
			elif character == quote: quote = ""
		elif character in ['"', "'"]:
			quote = character
			result += " "
		else: result += character
	return result
