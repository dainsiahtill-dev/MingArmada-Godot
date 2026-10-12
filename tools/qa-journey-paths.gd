extends RefCounted
## QA-only evidence paths. No Storage, Runtime, directories or output creation.
const ROOT := "res://docs/migration/evidence/opening-story/"
static func _argument(args: Array, name: String) -> Dictionary:
	var values: Array = []
	for arg: String in args:
		if arg.begins_with(name + "="): values.append(arg.substr(name.length() + 1))
	return {"ok":true,"path":values[0]} if values.size() == 1 else {"ok":false,"reason":"one-explicit-" + name + "-required"}
static func _confined(path: String) -> Dictionary:
	if not path.begins_with(ROOT) or not path.ends_with(".json") or "\\" in path: return {"ok":false,"reason":"workspace-evidence-json-required"}
	var suffix := path.substr(ROOT.length())
	var components := suffix.split("/", true)
	for part: String in components:
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "): return {"ok":false,"reason":"ambiguous-path"}
		for forbidden: String in [":","<",">","\"","|","?","*"]:
			if forbidden in part: return {"ok":false,"reason":"ambiguous-path"}
		var stem: String = part.get_slice(".",0).to_upper()
		if stem in ["CON","PRN","AUX","NUL","COM1","COM2","COM3","COM4","COM5","COM6","COM7","COM8","COM9","LPT1","LPT2","LPT3","LPT4","LPT5","LPT6","LPT7","LPT8","LPT9"]: return {"ok":false,"reason":"reserved-device-path"}
	# Junctions/symlinks must not turn a workspace path into an outside write.
	var cursor := ProjectSettings.globalize_path("res://").trim_suffix("/")
	for part: String in path.trim_prefix("res://").split("/"):
		var directory := DirAccess.open(cursor)
		if directory != null and directory.is_link(part): return {"ok":false,"reason":"linked-evidence-path"}
		cursor = cursor.path_join(part)
	return {"ok":true,"path":path}
static func output(args: Array) -> Dictionary:
	var selected := _argument(args, "--output")
	if not selected.ok: return selected
	var confined := _confined(selected.path)
	if not confined.ok: return confined
	if FileAccess.file_exists(selected.path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(selected.path)): return {"ok":false,"reason":"evidence-already-exists"}
	return selected
static func input_journey(args: Array) -> Dictionary:
	var selected := _argument(args, "--journey")
	if not selected.ok: return selected
	var confined := _confined(selected.path)
	if not confined.ok: return confined
	if not FileAccess.file_exists(selected.path): return {"ok":false,"reason":"journey-not-found"}
	return selected
