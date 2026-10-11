extends RefCounted
## Facts may be parameterized for policy tests; every production caller uses host_allows.
static func environment_allows(debug_build: bool, editor: bool) -> bool:
	return debug_build or editor
static func host_allows() -> bool:
	return environment_allows(OS.is_debug_build(),OS.has_feature("editor"))
static func startup_flags(arguments: PackedStringArray) -> Dictionary:
	var allowed := host_allows()
	return {"dev":allowed and "--dev" in arguments,"qa":allowed and "--qa" in arguments}
