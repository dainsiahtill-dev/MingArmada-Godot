extends RefCounted
## Hero roster loader: the twelve named heroes from the design roster, strict
## shape, domain-local data. Recruiting is a world sign-on; specialty effects
## live in story_rules and apply when the person is aboard.

const HEROES_PATH := "res://game/domain/story_campaign/data/heroes_v1.json"
const ROLES := ["rescuer", "boarder", "purser", "signaler", "cook", "musician", "shipwright", "gunner", "lookout", "doctor", "navigator", "diplomat"]
const HERO_KEYS := ["id", "name", "role", "homePort", "cost", "wage", "note"]

static func load_content() -> Dictionary:
	if not FileAccess.file_exists(HEROES_PATH):
		return {"ok": false, "data": {}, "reason": "content-not-found"}
	var file := FileAccess.open(HEROES_PATH, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "reason": "content-unreadable"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "data": {}, "reason": "invalid-json"}
	var reason := _reason(parser.data)
	if not reason.is_empty():
		return {"ok": false, "data": {}, "reason": reason}
	return {"ok": true, "data": parser.data, "reason": ""}

static func heroes() -> Array:
	var loaded := load_content()
	if not loaded.ok:
		return []
	return (loaded.data.heroes as Array).map(func(entry): return (entry as Dictionary).duplicate(true))

static func heroes_at(port_id: String, signed: Array = []) -> Array:
	var found: Array = []
	for hero: Dictionary in heroes():
		if str(hero.homePort) == str(port_id) and not str(hero.id) in signed and not str(hero.name) in signed:
			found.append(hero)
	return found

static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()

static func _stable_id(value: Variant) -> bool:
	if not _text(value) or value.length() > 64:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
			return false
	return true

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

static func _reason(content: Variant) -> String:
	if not content is Dictionary or content.size() != 4 or not content.has("schemaVersion") or not content.has("id") or not content.has("note") or not content.has("heroes"):
		return "invalid-heroes-fields"
	if not _integer(content.schemaVersion, 1, 1) or content.id != "zheng-family-heroes-v1" or not _text(content.note):
		return "invalid-heroes-identity"
	if not content.heroes is Array or content.heroes.size() != 12:
		return "invalid-heroes-count"
	var seen := {}
	for entry: Variant in content.heroes:
		if not entry is Dictionary or entry.size() != HERO_KEYS.size():
			return "invalid-hero-fields"
		for key: String in HERO_KEYS:
			if not entry.has(key):
				return "invalid-hero-fields"
		if not _stable_id(entry.id) or seen.has(entry.id) or not _text(entry.name) or not entry.role in ROLES or not _stable_id(entry.homePort) or not _integer(entry.cost, 0, 1000000) or not _integer(entry.wage, 0, 10000) or not _text(entry.note):
			return "invalid-hero-entry"
		seen[entry.id] = true
	return ""
