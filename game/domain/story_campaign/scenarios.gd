extends RefCounted
## Strict scenario loader. Scenario content only parameterizes the per-mode
## executors; loading it grants no world assets or victories. Every stage must
## bind its settlements 1:1 to the catalog objectives of the same stage id.

const SCENARIO_PATH := "res://game/domain/story_campaign/data/scenarios_v1.json"
const GEOGRAPHY_PATH := "res://game/domain/story_campaign/data/geography_v1.json"
const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
const OPENING_KEYS := ["silver", "day", "yearMarker", "homePort", "relations", "fleet", "log"]
const STAGE_KEYS := ["mode", "transition", "entities", "settlements", "misstepPolicy", "limits", "weather"]
const REQUIRED_STAGE_KEYS := ["mode", "entities", "settlements", "limits"]
const SHIP_KINDS := ["fisherman", "patrol", "fuchuan", "merchant", "voc", "heavy"]
const WORLD_KINDS := ["garrison", "facility", "group", "route", "watch", "depot"]
const GOODS := ["grain", "wood", "iron", "silk", "porcelain", "spices"]
const SETTLEMENT_REQUIRED := {
	"arrive": ["kind", "portId"],
	"deliver": ["kind", "portId", "good", "quantity"],
	"trade-profit": ["kind", "contractId"],
	"capture": ["kind", "targetId"],
	"escort-arrived": ["kind", "targetId", "destinationPortId"],
	"recruit": ["kind", "personId", "name", "role", "cost", "wage"],
	"charter": ["kind", "permitId", "scope", "issuer", "cost", "conditions"],
	"neutralize": ["kind", "targetIds"],
	"protect": ["kind", "targetIds"],
	"rescue": ["kind", "targetIds"],
	"handoff": ["kind"],
	"dispatch-returned": ["kind", "dispatchId", "route"],
	"withdraw": ["kind", "groupId", "rendezvousPortId", "people"],
	"stockpile": [],
	"land-control": ["kind", "siteId"],
	"hold-blockade": ["kind", "watchId"],
	"accept-terms": ["kind", "agreementId", "termsTemplate"],
	"evacuation-complete": ["kind", "manifestId", "fromId", "people", "cargo", "thenDepartTo"],
	"port-handover": ["kind", "handoverId", "facilityId", "portId"]
}

static func load_content() -> Dictionary:
	var scenario := _load_json(SCENARIO_PATH)
	if not scenario.ok:
		return {"ok": false, "data": {}, "reason": scenario.reason}
	var result := validate(scenario.data)
	if not result.ok:
		return {"ok": false, "data": {}, "reason": result.reason}
	return {"ok": true, "data": scenario.data, "reason": ""}

static func geography() -> Dictionary:
	var loaded := _load_json(GEOGRAPHY_PATH)
	if not loaded.ok:
		return {"ok": false, "data": {}, "reason": loaded.reason}
	var reason := _geography_reason(loaded.data)
	if not reason.is_empty():
		return {"ok": false, "data": {}, "reason": reason}
	return {"ok": true, "data": loaded.data.duplicate(true), "reason": ""}

static func validate(content: Variant) -> Dictionary:
	var reason := _content_reason(content)
	return {"ok": reason.is_empty(), "reason": reason}

static func stage_ids() -> Array:
	var loaded := load_content()
	if not loaded.ok:
		return []
	return (loaded.data.stages as Dictionary).keys()

static func scenario(stage_id: String) -> Dictionary:
	var loaded := load_content()
	if not loaded.ok:
		return {}
	return (loaded.data.stages as Dictionary).get(stage_id, {}).duplicate(true)

static func opening() -> Dictionary:
	var loaded := load_content()
	var geo := geography()
	if not loaded.ok or not geo.ok:
		return {}
	var ports := []
	for entry: Dictionary in geo.data.ports:
		ports.append({"id": entry.id, "x": entry.x, "z": entry.z, "tax": entry.tax, "faction": entry.faction, "services": entry.services.duplicate(true), "prices": entry.prices.duplicate(true), "stockCaps": entry.stockCaps.duplicate(true), "stock": entry.stock.duplicate(true)})
	var opening: Dictionary = loaded.data.opening.duplicate(true)
	opening.ports = ports
	return opening

static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"ok": false, "data": {}, "reason": "content-not-found"}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"ok": false, "data": {}, "reason": "content-unreadable"}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"ok": false, "data": {}, "reason": "invalid-json"}
	return {"ok": true, "data": parser.data, "reason": ""}

static func _text(value: Variant) -> bool:
	return typeof(value) == TYPE_STRING and not value.strip_edges().is_empty()

static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value)) and value == floor(value) and value >= minimum and value <= maximum

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _stable_id(value: Variant) -> bool:
	if not _text(value) or value.length() > 96:
		return false
	for character: String in value:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_":
			return false
	return true

static func _goods_map(value: Variant, allow_empty: bool = true) -> bool:
	if not value is Dictionary or (not allow_empty and value.is_empty()):
		return false
	for good: Variant in value:
		if not good in GOODS or not _integer(value[good], 0, 1000000):
			return false
	return true

static func _geography_reason(content: Variant) -> String:
	if not content is Dictionary or content.size() != 5 or not content.has("schemaVersion") or not content.has("id") or not content.has("scaleNote") or not content.has("ports") or not content.has("tradeRoutes"):
		return "invalid-geography-fields"
	if not _integer(content.schemaVersion, 1, 1) or content.id != "zheng-family-geography-v1" or not _text(content.scaleNote) or not content.ports is Array or content.ports.size() < 10:
		return "invalid-geography-identity"
	if not content.tradeRoutes is Array or content.tradeRoutes.size() > 8:
		return "invalid-geography-routes"
	var seen := {}
	for entry: Variant in content.ports:
		if not entry is Dictionary:
			return "invalid-geography-port"
		for key: String in ["id", "name", "region", "displayKind", "islandX", "islandZ", "radius", "peak", "x", "z", "tax", "faction", "services", "prices", "stockCaps", "stock"]:
			if not entry.has(key):
				return "invalid-geography-port-fields"
		if not _stable_id(entry.id) or seen.has(entry.id) or not _text(entry.name) or not _text(entry.region):
			return "invalid-geography-port-identity"
		seen[entry.id] = true
		for key: String in ["islandX", "islandZ", "radius", "peak", "x", "z", "tax"]:
			if not _number(entry[key]):
				return "invalid-geography-port-numbers"
		if not _text(entry.faction) or not entry.services is Array or not _goods_map(entry.prices, false) or not _goods_map(entry.stockCaps, false) or not _goods_map(entry.stock, false):
			return "invalid-geography-port-economy"
		for good: String in GOODS:
			if not entry.prices.has(good) or not entry.stockCaps.has(good) or not entry.stock.has(good):
				return "incomplete-geography-goods"
	for pair: Variant in content.tradeRoutes:
		if not pair is Array or pair.size() != 2 or not seen.has(str(pair[0])) or not seen.has(str(pair[1])) or str(pair[0]) == str(pair[1]):
			return "invalid-geography-routes"
	return ""

static func _content_reason(content: Variant) -> String:
	if not content is Dictionary or content.size() != 4 or not content.has("schemaVersion") or not content.has("id") or not content.has("opening") or not content.has("stages"):
		return "invalid-scenario-fields"
	if not _integer(content.schemaVersion, 1, 1) or content.id != "zheng-family-scenarios-v1":
		return "invalid-scenario-identity"
	var geo := geography()
	if not geo.ok:
		return str(geo.reason)
	var catalog_script: GDScript = load(CATALOG_PATH) as GDScript
	if catalog_script == null:
		return "mainline-catalog-unavailable"
	var stages: Array = catalog_script.call("stages")
	if stages.size() != 30:
		return "mainline-catalog-stages-invalid"
	var port_ids := {}
	for entry: Dictionary in geo.data.ports:
		port_ids[entry.id] = true
	var opening_reason := _opening_reason(content.opening, port_ids)
	if not opening_reason.is_empty():
		return opening_reason
	if not content.stages is Dictionary or content.stages.size() != stages.size():
		return "invalid-scenario-stage-count"
	var seen := {}
	for stage: Dictionary in stages:
		if not content.stages.has(stage.id) or seen.has(stage.id):
			return "scenario-stages-must-match-catalog"
		seen[stage.id] = true
		var reason := _stage_reason(content.stages[stage.id], stage, port_ids)
		if not reason.is_empty():
			return reason
	return ""

static func _opening_reason(opening: Variant, port_ids: Dictionary) -> String:
	if not opening is Dictionary or opening.size() != OPENING_KEYS.size():
		return "invalid-opening-fields"
	for key: String in OPENING_KEYS:
		if not opening.has(key):
			return "invalid-opening-fields"
	if not _integer(opening.silver, 0, 100000000) or not _integer(opening.day, 1, 1000000) or not _integer(opening.yearMarker, 1600, 1700) or not _stable_id(opening.homePort) or not port_ids.has(opening.homePort):
		return "invalid-opening-counters"
	if not opening.relations is Dictionary or not opening.fleet is Array or opening.fleet.is_empty() or not _text(opening.log):
		return "invalid-opening-world"
	for entry: Variant in opening.fleet:
		if not entry is Dictionary or not _stable_id(entry.get("id")) or not entry.get("kind") in SHIP_KINDS or not _text(entry.get("name")) or not _integer(entry.get("crew"), 0, 1000) or not _goods_map(entry.get("cargo")):
			return "invalid-opening-ship"
	return ""

static func _stage_reason(entry: Variant, stage: Dictionary, port_ids: Dictionary) -> String:
	if not entry is Dictionary:
		return "invalid-scenario-stage"
	for key: Variant in entry:
		if not key in STAGE_KEYS:
			return "unknown-scenario-stage-field"
	for key: String in REQUIRED_STAGE_KEYS:
		if not entry.has(key):
			return "missing-scenario-stage-field"
	if entry.mode != stage.mode or not entry.entities is Array or not entry.settlements is Dictionary or not entry.limits is Dictionary or not entry.limits.has("maxTicks") or not _integer(entry.limits.maxTicks, 1, 10000000):
		return "invalid-scenario-stage-definition"
	var entity_ids := {}
	for entity: Variant in entry.entities:
		var reason := _entity_reason(entity, entity_ids)
		if not reason.is_empty():
			return reason
		entity_ids[str(entity.id)] = true
	var objectives: Dictionary = {}
	for objective: Dictionary in stage.objectives:
		objectives[objective.id] = objective
	if entry.settlements.size() != objectives.size():
		return "scenario-settlements-must-match-objectives"
	for objective_id: Variant in entry.settlements:
		if not objectives.has(objective_id):
			return "scenario-settlements-must-match-objectives"
		var settlement: Dictionary = entry.settlements[objective_id]
		var objective: Dictionary = objectives[objective_id]
		var reason := _settlement_reason(settlement, str(objective.kind), entity_ids, port_ids)
		if not reason.is_empty():
			return reason
	if entry.has("transition"):
		var transition: Dictionary = entry.transition
		if not transition is Dictionary or (transition.size() != 3 and transition.size() != 4) or not _integer(transition.get("yearMarker"), 1600, 1700) or not _stable_id(transition.get("to")) or not port_ids.has(transition.get("to")) or not _text(transition.get("note")):
			return "invalid-scenario-transition"
		if transition.has("meeting") and not _text(transition.meeting):
			return "invalid-scenario-transition"
	if entry.has("misstepPolicy"):
		var policy: Dictionary = entry.misstepPolicy
		if not policy is Dictionary or policy.size() != 3 or not entity_ids.has(policy.get("wrongTargetId")) or not _text(policy.get("consequence")) or not policy.get("objectiveCredit") is bool:
			return "invalid-scenario-misstep"
	if entry.has("weather") and not entry.weather in ["calm", "breeze", "storm"]:
		return "invalid-scenario-weather"
	var pin := _pin_reason(str(stage.id), entry)
	if not pin.is_empty():
		return pin
	return ""

static func _pin_reason(stage_id: String, entry: Dictionary) -> String:
	var entity_ids := {}
	for entity: Variant in entry.entities:
		entity_ids[str(entity.id)] = true
	if stage_id == "CH-09-S1":
		if not entity_ids.has("ryukyu-envoy-vessel"):
			return "missing-ryukyu-envoy-entity"
		for objective_id: String in ["ch09-rescue", "ch09-escort"]:
			var settlement: Dictionary = entry.settlements.get(objective_id, {})
			if str(settlement.get("targetId", "")) != "ryukyu-envoy-vessel" and (settlement.get("targetIds") is Array and not "ryukyu-envoy-vessel" in settlement.targetIds):
				return "ryukyu-envoy-settlement-unbound"
	if stage_id == "T10":
		var terms: Dictionary = entry.settlements.get("t10-terms", {})
		var evacuation: Dictionary = entry.settlements.get("t10-evacuation", {})
		var handover: Dictionary = entry.settlements.get("t10-handover", {})
		if not terms.get("agreementId") is String or not evacuation.get("manifestId") is String or not handover.get("handoverId") is String:
			return "incomplete-ending-bindings"
	return ""

static func _entity_reason(entity: Variant, seen: Dictionary) -> String:
	if not entity is Dictionary or not entity.has("id") or not entity.has("kind") or not entity.has("team") or not entity.has("name"):
		return "invalid-scenario-entity"
	if not _stable_id(entity.id) or seen.has(entity.id) or not _text(entity.name) or not entity.team in ["player", "neutral", "hostile"]:
		return "invalid-scenario-entity-identity"
	var kind := str(entity.kind)
	if kind in SHIP_KINDS:
		if not entity.has("spawn") or not entity.has("setup") or not entity.spawn is Dictionary or not entity.setup is Dictionary:
			return "scenario-ship-needs-spawn-and-setup"
		if not entity.setup.has("hull") or not _integer(entity.setup.hull, 1, 100) or not entity.setup.has("crew") or not _integer(entity.setup.crew, 0, 1000):
			return "invalid-scenario-ship-setup"
		var spawn: Dictionary = entity.spawn
		var point: Variant = spawn.get("point")
		if point is Dictionary and (not _number(point.get("x")) or not _number(point.get("z"))):
			return "invalid-scenario-ship-spawn"
		if not point is Dictionary and not _stable_id(spawn.get("portId")):
			return "invalid-scenario-ship-spawn"
		if entity.has("setup") and entity.setup.has("cargo") and not _goods_map(entity.setup.cargo):
			return "invalid-scenario-ship-cargo"
		return ""
	if kind in WORLD_KINDS:
		if entity.has("inventory") and not _goods_map(entity.inventory):
			return "invalid-scenario-entity-inventory"
		if entity.has("people") and not _integer(entity.people, 0, 100000):
			return "invalid-scenario-entity-people"
		return ""
	return "unknown-scenario-entity-kind"

static func _settlement_reason(settlement: Variant, kind: String, entity_ids: Dictionary, port_ids: Dictionary) -> String:
	if not settlement is Dictionary or not SETTLEMENT_REQUIRED.has(kind) or str(settlement.get("kind", "")) != kind:
		return "invalid-scenario-settlement"
	if kind == "stockpile":
		if settlement.has("via") and str(settlement.via) == "load-manifest":
			for key: String in ["kind", "via", "manifestId", "fromId", "people", "cargo"]:
				if not settlement.has(key):
					return "incomplete-stockpile-binding"
			if settlement.size() != 6 or not _stable_id(settlement.manifestId) or not entity_ids.has(str(settlement.fromId)) or not _integer(settlement.people, 0, 100000) or not _goods_map(settlement.cargo):
				return "invalid-stockpile-binding"
			return ""
		for key: String in ["kind", "good", "quantity"]:
			if not settlement.has(key):
				return "incomplete-stockpile-binding"
		if settlement.size() != 3 or not settlement.good in GOODS or not _integer(settlement.quantity, 1, 1000000):
			return "invalid-stockpile-binding"
		return ""
	for key: String in SETTLEMENT_REQUIRED[kind]:
		if not settlement.has(key):
			return "incomplete-settlement-binding"
	if kind == "charter":
		if settlement.size() != 6 and settlement.size() != 7:
			return "invalid-scenario-settlement"
		if settlement.has("options"):
			var options: Variant = settlement.options
			if not options is Array or options.is_empty() or options.size() > 4:
				return "invalid-charter-options"
			for option: Variant in options:
				if not option is Dictionary or option.size() != 4 or not _stable_id(option.get("id")) or not _text(option.get("label")) or not _integer(option.get("cost"), 0, 1000000) or not option.get("conditions") is Array or (option.conditions as Array).is_empty():
					return "invalid-charter-options"
				for condition: Variant in option.conditions:
					if not _text(condition):
						return "invalid-charter-options"
	elif settlement.size() != SETTLEMENT_REQUIRED[kind].size():
		return "invalid-scenario-settlement"
	for key: String in ["targetId", "siteId", "fromId", "facilityId"]:
		if settlement.has(key) and not entity_ids.has(str(settlement[key])):
			return "settlement-target-entity-missing"
	if settlement.has("targetIds"):
		if not settlement.targetIds is Array or settlement.targetIds.is_empty():
			return "invalid-settlement-targets"
		for target: Variant in settlement.targetIds:
			if not entity_ids.has(str(target)):
				return "settlement-target-entity-missing"
	for key: String in ["portId", "destinationPortId", "rendezvousPortId"]:
		if settlement.has(key) and not port_ids.has(str(settlement[key])):
			return "settlement-port-missing"
	if kind == "deliver" and (not settlement.good in GOODS or not _integer(settlement.quantity, 1, 1000000)):
		return "invalid-deliver-binding"
	if kind == "charter" and not _integer(settlement.cost, 0, 1000000):
		return "invalid-charter-binding"
	return ""
