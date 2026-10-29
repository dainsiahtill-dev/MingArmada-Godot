extends RefCounted
## Shared read-only capture guards and paired timeline contract.
const Demo = preload("res://game/research/demos/broadside_receipt_experiment.gd")
const LAST_TICK := 112
const STEP := 1.0 / 32.0

static func normal(path: String) -> String:
	return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()

static func inside(path: String, parent: String) -> bool:
	var p := normal(path); var root := normal(parent)
	return not p.is_empty() and not root.is_empty() and p.begins_with(root+"/")

static func profile_ok(app: String, local: String, profile: String, original: String, user_dir: String) -> bool:
	if [app,local,profile,original,user_dir].any(func(s): return str(s).is_empty()): return false
	return inside(app,profile) and inside(local,profile) and normal(app) != normal(local) and not inside(app,local) and not inside(local,app) and inside(user_dir,app) and not inside(profile,original) and not inside(original,profile) and normal(profile) != normal(original)

static func output_ok(output: String, expected: String) -> bool:
	if output.is_empty() or expected.is_empty() or output.contains("..") or output.contains("\\"): return false
	if not output.begins_with("res://docs/research/evidence/broadside-receipt-readability/") or not output.ends_with("/frames"): return false
	if normal(ProjectSettings.globalize_path(output)) != normal(expected): return false
	return not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected)

static func fixture_events(tick: int) -> Array:
	var result: Array = []
	for row: Dictionary in Demo.EVENTS:
		if int(row.tick) == tick: result.append(row.event.duplicate(true))
	return result

static func input_fixture() -> Array: return Demo.EVENTS.duplicate(true)

static func pair_ok(baseline: Dictionary, candidate: Dictionary) -> bool:
	for key: String in ["tick","time","step_seconds","fixture_events","receipt","naive_text"]:
		if baseline.get(key) != candidate.get(key): return false
	return baseline.get("visible_receipt") == "" and candidate.get("visible_receipt") == candidate.get("receipt",{}).get("text","")
