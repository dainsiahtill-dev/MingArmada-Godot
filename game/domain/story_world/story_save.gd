extends RefCounted
## Story save codec. One save restores world and progress together.
## World validation is strict; progress is revalidated by a scratch Progress
## restore (its own prefix replay rejects skips and fabrication), and the CH12
## transfer record must agree with the progress handoff marker.

const World = preload("res://game/domain/story_world/story_world_session.gd")
const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const SAVE_KEYS := ["version", "world", "progress"]
const MAX_SAVE_BYTES := 16777216

static func encode(world_state: Dictionary, progress_json: String) -> String:
	return JSON.stringify({"version": 1, "world": world_state.duplicate(true), "progress": progress_json})

static func validate(raw: String) -> Dictionary:
	if raw.is_empty() or raw.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return {"ok": false, "reason": "save is empty or exceeds limit"}
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return {"ok": false, "reason": "invalid save JSON"}
	var decoded: Variant = parser.data
	if not decoded is Dictionary or decoded.size() != SAVE_KEYS.size():
		return {"ok": false, "reason": "save fields do not match story save schema"}
	for key: String in SAVE_KEYS:
		if not decoded.has(key):
			return {"ok": false, "reason": "save fields do not match story save schema"}
	if not _int(decoded.version, 1, 1) or not decoded.progress is String:
		return {"ok": false, "reason": "save version or progress payload invalid"}
	var world: Dictionary = World.validate_world(decoded.world)
	if not world.ok:
		return {"ok": false, "reason": "world: " + str(world.reason)}
	if not FileAccess.file_exists(PROGRESS_PATH):
		return {"ok": false, "reason": "mainline progress contract unavailable"}
	var script: GDScript = load(PROGRESS_PATH) as GDScript
	if script == null:
		return {"ok": false, "reason": "mainline progress contract cannot load"}
	var scratch: RefCounted = script.new()
	var restored: Dictionary = scratch.call("restore", decoded.progress)
	if not restored.get("ok", false):
		return {"ok": false, "reason": "progress: " + str(restored.get("reason", "invalid"))}
	var progress_state: Dictionary = scratch.call("snapshot")
	var state: Dictionary = world.state
	if str(progress_state.runId) != str(state.runId):
		return {"ok": false, "reason": "save run identity mismatch"}
	var transfers: Array = state.transfers
	var handoff_done: bool = bool(progress_state.handoff.done)
	if handoff_done != (transfers.size() == 1):
		return {"ok": false, "reason": "handoff marker contradicts world transfer record"}
	return {"ok": true, "reason": ""}

static func decode(raw: String) -> Dictionary:
	var validated := validate(raw)
	if not validated.ok:
		return validated
	var parser := JSON.new()
	parser.parse(raw)
	var decoded: Dictionary = parser.data
	return {"ok": true, "reason": "", "world": decoded.world.duplicate(true), "progress": str(decoded.progress)}

static func _int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false
