extends RefCounted
## Authored goal definitions. Loading this catalog grants no world assets or victories.

const CONTENT_PATH := "res://assets/data/story_campaign/zheng_family_v1.json"
const PROTAGONISTS := ["zheng-zhilong", "zheng-chenggong"]
const REGIONS := ["REG-01", "REG-02", "REG-03", "REG-04", "REG-05", "REG-06", "REG-07"]
const MODES := ["sailing", "trade", "escort", "naval", "boarding", "land", "port", "handoff"]
const KINDS := ["arrive", "deliver", "trade-profit", "capture", "escort-arrived", "recruit", "charter", "neutralize", "protect", "rescue", "handoff", "dispatch-returned", "withdraw", "stockpile", "land-control", "hold-blockade", "accept-terms", "evacuation-complete", "port-handover"]
const TAIWAN := [["T01", "T02", "T03"], ["T04", "T05"], ["T06", "T07", "T08"], ["T09", "T10"]]

static func load_content() -> Dictionary:
	if not FileAccess.file_exists(CONTENT_PATH):
		return {"ok": false, "data": {}, "reason": "content-not-found"}
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "reason": "content-unreadable"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "data": {}, "reason": "invalid-json"}
	var result := validate(parser.data)
	if not result.ok:
		return {"ok": false, "data": {}, "reason": result.reason}
	return {"ok": true, "data": parser.data.duplicate(true), "reason": ""}

static func validate(content: Variant) -> Dictionary:
	var reason := _content_reason(content)
	return {"ok": reason.is_empty(), "reason": reason}

static func stages() -> Array:
	var loaded := load_content()
	if not loaded.ok:
		return []
	var result: Array = []
	for definition: Dictionary in loaded.data.chapters:
		for entry: Dictionary in definition.stages:
			var row: Dictionary = entry.duplicate(true)
			row.merge({"chapterId": definition.id, "protagonistId": definition.protagonistId, "year": definition.year, "act": definition.act, "difficulty": definition.difficulty.duplicate(true)})
			result.append(row)
	return result

static func stage(id: String) -> Dictionary:
	for entry: Dictionary in stages():
		if entry.id == id:
			return entry.duplicate(true)
	return {}

static func chapter(id: String) -> Dictionary:
	var loaded := load_content()
	if loaded.ok:
		for entry: Dictionary in loaded.data.chapters:
			if entry.id == id:
				return entry.duplicate(true)
	return {}

static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == floor(float(value)) and value >= minimum and value <= maximum

static func _keys(value: Variant, expected: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != expected.size():
		return false
	for key: String in expected:
		if not value.has(key):
			return false
	return true

static func _texts(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) != TYPE_ARRAY or value.size() < minimum or value.size() > maximum:
		return false
	for item: Variant in value:
		if not _text(item):
			return false
	return true

static func _stable_id(value: Variant) -> bool:
	if not _text(value) or value.length() > 128:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
			return false
	return true

static func _content_reason(content: Variant) -> String:
	if not _keys(content, ["schemaVersion", "id", "title", "protagonists", "chapters"]):
		return "invalid-campaign-fields"
	if not _integer(content.schemaVersion, 1, 1) or content.id != "zheng-family-v1" or not _text(content.title):
		return "invalid-campaign-identity"
	if typeof(content.protagonists) != TYPE_ARRAY or content.protagonists.size() != 2:
		return "invalid-protagonists"
	for index in range(2):
		var person: Variant = content.protagonists[index]
		if not _keys(person, ["id", "name", "birthYear"]):
			return "invalid-protagonist-fields"
		if person.id != PROTAGONISTS[index] or not _text(person.name) or not _integer(person.birthYear, 1500, 1650):
			return "invalid-protagonist"
	if typeof(content.chapters) != TYPE_ARRAY or content.chapters.size() != 24:
		return "invalid-chapter-count"
	var objective_ids: Dictionary = {}
	var stage_ids: Dictionary = {}
	var modes: Dictionary = {}
	var last_year := 1600
	for index in range(24):
		var definition: Variant = content.chapters[index]
		var reason := _chapter_reason(definition, index, objective_ids, stage_ids, modes)
		if not reason.is_empty():
			return reason
		if definition.year < last_year or definition.year < content.protagonists[0 if index < 12 else 1].birthYear:
			return "invalid-chapter-chronology"
		last_year = int(definition.year)
	if stage_ids.size() != 30 or modes.size() != MODES.size():
		return "incomplete-executor-coverage"
	return ""

static func _chapter_reason(definition: Variant, index: int, objective_ids: Dictionary, stage_ids: Dictionary, modes: Dictionary) -> String:
	if not _keys(definition, ["id", "order", "act", "title", "protagonistId", "year", "regionIds", "drama", "teaches", "reuses", "difficulty", "stages"]):
		return "invalid-chapter-fields"
	var act := int(index / 4) + 1
	if definition.id != "CH%02d" % (index + 1) or not _integer(definition.order, index + 1, index + 1) or not _integer(definition.act, act, act):
		return "invalid-chapter-order"
	if not _text(definition.title) or definition.protagonistId != PROTAGONISTS[0 if index < 12 else 1] or not _integer(definition.year, 1623, 1662):
		return "invalid-chapter-identity"
	if not _texts(definition.regionIds, 1, 7):
		return "invalid-chapter-regions"
	var regions: Dictionary = {}
	for region: String in definition.regionIds:
		if not region in REGIONS or regions.has(region):
			return "invalid-chapter-region"
		regions[region] = true
	if not _keys(definition.drama, ["want", "conflict", "turn"]):
		return "invalid-drama-fields"
	for field: String in ["want", "conflict", "turn"]:
		if not _text(definition.drama[field]):
			return "invalid-drama"
	if not _texts(definition.teaches, 1, 1) or not _texts(definition.reuses, 0, 12):
		return "invalid-learning-objectives"
	var difficulty: Variant = definition.difficulty
	if not _keys(difficulty, ["tier", "newRules", "simultaneousObjectives", "pressure"]):
		return "invalid-difficulty-fields"
	if not _integer(difficulty.tier, act, act) or not _integer(difficulty.newRules, 1, 1) or not _integer(difficulty.simultaneousObjectives, 1, 3) or not difficulty.pressure in ["none", "low", "medium", "high"]:
		return "invalid-difficulty"
	var expected_ids: Array = ["CH-%02d-S1" % (index + 1)] if index < 20 else TAIWAN[index - 20]
	if typeof(definition.stages) != TYPE_ARRAY or definition.stages.size() != expected_ids.size():
		return "invalid-chapter-stages"
	for position in range(expected_ids.size()):
		var entry: Variant = definition.stages[position]
		var reason := _stage_reason(entry, expected_ids[position], index, difficulty.simultaneousObjectives, objective_ids, stage_ids)
		if not reason.is_empty():
			return reason
		modes[entry.mode] = true
	return ""

static func _stage_reason(entry: Variant, expected_id: String, chapter_index: int, simultaneous: int, objective_ids: Dictionary, stage_ids: Dictionary) -> String:
	if not _keys(entry, ["id", "mode", "title", "briefing", "objectives", "recovery", "partialAllowed"]):
		return "invalid-stage-fields"
	if entry.id != expected_id or stage_ids.has(entry.id):
		return "invalid-stage-identity"
	if not entry.mode in MODES or not _text(entry.title) or not _text(entry.briefing) or not _text(entry.recovery):
		return "invalid-stage-definition"
	if typeof(entry.partialAllowed) != TYPE_BOOL or ((chapter_index == 11 or chapter_index >= 20) and entry.partialAllowed):
		return "invalid-partial-policy"
	if chapter_index == 11 and entry.mode != "handoff":
		return "invalid-handoff-mode"
	if chapter_index != 11 and entry.mode == "handoff":
		return "unexpected-handoff-mode"
	if typeof(entry.objectives) != TYPE_ARRAY or entry.objectives.is_empty() or entry.objectives.size() > simultaneous:
		return "invalid-stage-objectives"
	var kinds: Array = []
	var envoy_arrived := false
	for objective: Variant in entry.objectives:
		if not _keys(objective, ["id", "kind", "target", "required", "unit"]):
			return "invalid-objective-fields"
		if not _stable_id(objective.id) or objective_ids.has(objective.id) or not objective.kind in KINDS or not _stable_id(objective.target) or not _integer(objective.required, 1, 1000000000) or not _text(objective.unit):
			return "invalid-objective"
		if (objective.kind == "handoff") != (entry.mode == "handoff"):
			return "invalid-handoff-objective"
		if entry.mode == "handoff" and (objective.target != "zheng-chenggong" or not _integer(objective.required, 1, 1) or objective.unit != "manifest"):
			return "invalid-handoff-manifest"
		if objective.kind == "escort-arrived" and objective.target == "ryukyu-envoy-vessel" and _integer(objective.required, 1, 1) and objective.unit == "vessel":
			envoy_arrived = true
		objective_ids[objective.id] = true
		kinds.append(objective.kind)
	if entry.id == "CH-09-S1" and not envoy_arrived:
		return "missing-ryukyu-envoy-arrival"
	if entry.id == "T10" and kinds != ["accept-terms", "evacuation-complete", "port-handover"]:
		return "incomplete-ending-objectives"
	stage_ids[entry.id] = true
	return ""
