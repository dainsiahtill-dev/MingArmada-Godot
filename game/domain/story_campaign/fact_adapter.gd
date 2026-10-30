extends RefCounted
## Fact adapter: the only bridge between real settlements and progress facts.
## Pure functions over catalog stage + scenario bindings + live world/native
## snapshots. Every witness is re-evaluated at settle time against the CURRENT
## world: being alive at observation time, once stocked or once arrived never
## grants success on its own. No caller may pass an outcome.

const GOODS := ["grain", "wood", "iron", "silk", "porcelain", "spices"]
const KIND_SOURCES := {
	"arrive": "naval-snapshot", "deliver": "business-receipt", "trade-profit": "business-receipt",
	"capture": "encounter-result", "escort-arrived": "naval-snapshot", "recruit": "business-receipt",
	"charter": "business-receipt", "neutralize": "naval-snapshot", "protect": "naval-snapshot",
	"rescue": "world-snapshot", "handoff": "world-snapshot", "dispatch-returned": "world-snapshot",
	"withdraw": "world-snapshot", "stockpile": "world-snapshot", "land-control": "encounter-result",
	"hold-blockade": "world-snapshot", "accept-terms": "business-receipt",
	"evacuation-complete": "business-receipt", "port-handover": "business-receipt"
}

static func evaluate(stage: Dictionary, scenario: Dictionary, world: Dictionary, native: Dictionary) -> Dictionary:
	var objectives := {}
	if stage.is_empty() or scenario.is_empty() or not scenario.has("settlements"):
		return {"objectives": objectives, "safe": _safe(world)}
	for objective: Dictionary in stage.objectives:
		var binding: Dictionary = scenario.settlements.get(objective.id, {})
		var witness: Dictionary = _witness(str(objective.kind), binding, objective, world, native)
		objectives[objective.id] = {"progress": int(witness.progress), "required": int(objective.required), "source": KIND_SOURCES.get(str(objective.kind), "world-snapshot"), "ok": int(witness.progress) >= int(objective.required), "note": str(witness.get("note", ""))}
	return {"objectives": objectives, "safe": _safe(world)}

static func facts(stage: Dictionary, scenario: Dictionary, world: Dictionary, native: Dictionary, run_id: String, attempt: int) -> Array:
	var evaluation := evaluate(stage, scenario, world, native)
	var batch: Array = []
	for objective: Dictionary in stage.objectives:
		var entry: Dictionary = evaluation.objectives[objective.id]
		if int(entry.progress) <= 0:
			continue
		# Progress values are absolute milestones; each observed value gets its
		# own immutable fact id so late growth never rewrites accepted evidence.
		batch.append({"id": "%s:%s:%s:%d:%d" % [stage.id, objective.id, "witness", attempt, int(entry.progress)], "runId": run_id, "stageId": str(stage.id), "attempt": int(attempt), "objectiveId": str(objective.id), "progress": int(entry.progress), "source": str(entry.source)})
	return batch

static func settle(stage: Dictionary, scenario: Dictionary, world: Dictionary, native: Dictionary, retreat: bool = false) -> Dictionary:
	var evaluation := evaluate(stage, scenario, world, native)
	var all_met := true
	var any_met := false
	for objective: Dictionary in stage.objectives:
		var entry: Dictionary = evaluation.objectives[objective.id]
		all_met = all_met and bool(entry.ok)
		any_met = any_met or int(entry.progress) > 0
	var outcome := "failure"
	if retreat:
		outcome = "retreat"
	elif all_met and bool(evaluation.safe):
		outcome = "success"
	elif bool(stage.partialAllowed) and any_met:
		outcome = "partial"
	return {"outcome": outcome, "safe": bool(evaluation.safe), "witnesses": evaluation.objectives}

static func _safe(world: Dictionary) -> bool:
	if bool(world.get("battleActive", true)):
		return false
	var ship := _fleet_ship(world, str(world.get("flagshipId", "")))
	return not ship.is_empty() and int(ship.get("hull", 0)) > 0

static func _witness(kind: String, binding: Dictionary, objective: Dictionary, world: Dictionary, native: Dictionary) -> Dictionary:
	match kind:
		"arrive":
			var at_port: bool = str(world.get("currentPortId", "")) == str(binding.get("portId", ""))
			return {"progress": 1 if at_port and not bool(world.get("battleActive", true)) else 0}
		"deliver":
			var matched := 0
			for receipt: Dictionary in world.get("receipts", []):
				if str(receipt.kind) != "deliver":
					continue
				var details: Dictionary = receipt.details
				if str(details.get("portId", "")) == str(binding.get("portId", "")) and str(details.get("good", "")) == str(binding.get("good", "")) and int(details.get("quantity", 0)) >= int(binding.get("quantity", 0)):
					matched += 1
			return {"progress": mini(matched, int(objective.required))}
		"trade-profit":
			var contract: Dictionary = world.get("contracts", {}).get(str(binding.get("contractId", "")), {})
			var net := 0
			for entry: Dictionary in contract.get("ledger", []):
				net += int(entry.get("delta", 0))
			return {"progress": clampi(net, 0, int(objective.required))}
		"capture":
			var target := str(binding.get("targetId", ""))
			for record: Dictionary in world.get("captures", []):
				if str(record.get("targetId", "")) == target:
					var prize := _fleet_ship(world, str(record.get("shipId", "")))
					if not prize.is_empty() and int(prize.get("hull", 0)) > 0:
						return {"progress": 1}
					return {"progress": 1, "note": "captured-vessel-lost"}
			return {"progress": 0}
		"escort-arrived":
			var ship := _native_ship(native, str(binding.get("targetId", "")))
			if ship.is_empty() or int(ship.get("hull", 0)) <= 0:
				return {"progress": 0}
			var destination: Dictionary = world.get("ports", {}).get(str(binding.get("destinationPortId", "")), {})
			if destination.is_empty():
				return {"progress": 0}
			var position: Dictionary = ship.get("visual", {}).get("position", {})
			var arrived: bool = _distance(position, {"x": float(destination.get("x", 0.0)), "z": float(destination.get("z", 0.0))}) <= 90.0
			return {"progress": 1 if arrived else 0}
		"recruit":
			for person: Dictionary in world.get("people", []):
				if str(person.get("id", "")) == str(binding.get("personId", "")):
					return {"progress": 1}
			return {"progress": 0}
		"charter":
			var permit_id := str(binding.get("permitId", ""))
			for permit: Dictionary in world.get("permits", []):
				if str(permit.get("id", "")) == permit_id:
					return {"progress": 1}
			for agreement: Dictionary in world.get("agreements", []):
				if str(agreement.get("id", "")) == permit_id:
					return {"progress": 1}
			return {"progress": 0}
		"neutralize":
			var cleared := true
			for target: Variant in binding.get("targetIds", []):
				if not _neutralized(world, native, str(target)):
					cleared = false
			return {"progress": 1 if cleared else 0}
		"protect":
			var all_alive := true
			for target: Variant in binding.get("targetIds", []):
				if not _alive(world, native, str(target)):
					all_alive = false
			return {"progress": 1 if all_alive else 0}
		"rescue":
			var all_rescued := true
			for target: Variant in binding.get("targetIds", []):
				if not _rescued(world, str(target)):
					all_rescued = false
			return {"progress": 1 if all_rescued else 0}
		"handoff":
			var transfers: Array = world.get("transfers", [])
			if transfers.size() != 1:
				return {"progress": 0}
			var record: Dictionary = transfers[0]
			var manifest: Dictionary = record.get("manifest", {})
			var valid: bool = str(record.get("to", "")) == str(objective.get("target", "")) and not (manifest.get("ships", []) as Array).is_empty()
			return {"progress": 1 if valid else 0}
		"dispatch-returned":
			for record: Dictionary in world.get("dispatches", []):
				if str(record.get("id", "")) == str(binding.get("dispatchId", "")) and str(record.get("status", "")) == "returned" and not str(record.get("returnReceiptId", "")).is_empty():
					return {"progress": 1}
			return {"progress": 0}
		"withdraw":
			var docked_at: bool = str(world.get("currentPortId", "")) == str(binding.get("rendezvousPortId", ""))
			if not docked_at:
				return {"progress": 0}
			for receipt: Dictionary in world.get("receipts", []):
				if str(receipt.kind) == "withdraw" and str(receipt.details.get("groupId", "")) == str(binding.get("groupId", "")):
					return {"progress": 1}
			return {"progress": 0}
		"stockpile":
			if str(binding.get("via", "")) == "load-manifest":
				var manifest_id := str(binding.get("manifestId", ""))
				var loaded := false
				for receipt: Dictionary in world.get("receipts", []):
					if str(receipt.kind) == "load-manifest" and str(receipt.details.get("manifestId", "")) == manifest_id:
						loaded = true
				if not loaded:
					return {"progress": 0}
				var cargo: Dictionary = binding.get("cargo", {})
				for good: Variant in cargo:
					if _inventory(world, str(good)) < int(cargo[good]):
						return {"progress": 0}
				return {"progress": 1}
			var good := str(binding.get("good", ""))
			var have: int = _inventory(world, good)
			return {"progress": clampi(have, 0, int(objective.required))}
		"land-control":
			var record: Dictionary = world.get("landPositions", {}).get(str(binding.get("siteId", "")), {})
			if record.is_empty() or str(record.get("controller", "")) != "player":
				return {"progress": 0}
			return {"progress": 1}
		"hold-blockade":
			var watch: Dictionary = world.get("blockades", {}).get(str(binding.get("watchId", "")), {})
			if watch.is_empty() or int(watch.get("breaches", -1)) != 0:
				return {"progress": 0}
			for ship_id: Variant in watch.get("stationShipIds", []):
				var ship := _fleet_ship(world, str(ship_id))
				if ship.is_empty() or int(ship.get("hull", 0)) <= 0:
					return {"progress": 0}
			return {"progress": 1}
		"accept-terms":
			for agreement: Dictionary in world.get("agreements", []):
				if str(agreement.get("id", "")) == str(binding.get("agreementId", "")) and not str(agreement.get("termsDigest", "")).is_empty():
					return {"progress": 1}
			return {"progress": 0}
		"evacuation-complete":
			var manifest_id := str(binding.get("manifestId", ""))
			var loaded := false
			for receipt: Dictionary in world.get("receipts", []):
				if str(receipt.kind) == "load-manifest" and str(receipt.details.get("manifestId", "")) == manifest_id:
					loaded = true
			if not loaded:
				return {"progress": 0}
			var source: Dictionary = world.get("entities", {}).get(str(binding.get("fromId", "")), {})
			if source.is_empty() or int(source.get("people", 1)) > 0:
				return {"progress": 0}
			for good: Variant in binding.get("cargo", {}):
				if int(source.get("inventory", {}).get(good, -1)) != 0:
					return {"progress": 0}
			if not str(world.get("currentPortId", "")).is_empty():
				return {"progress": 0}
			return {"progress": 1}
		"port-handover":
			var handed := false
			for receipt: Dictionary in world.get("receipts", []):
				if str(receipt.kind) == "handover" and str(receipt.details.get("handoverId", "")) == str(binding.get("handoverId", "")):
					handed = true
			if not handed:
				return {"progress": 0}
			var facility: Dictionary = world.get("entities", {}).get(str(binding.get("facilityId", "")), {})
			if facility.is_empty():
				return {"progress": 0}
			for good: String in GOODS:
				if int(facility.get("inventory", {}).get(good, 0)) != 0:
					return {"progress": 0}
			return {"progress": 1}
	return {"progress": 0}

static func _neutralized(world: Dictionary, native: Dictionary, target_id: String) -> bool:
	for record: Dictionary in world.get("captures", []):
		if str(record.get("targetId", "")) == target_id:
			return true
	var ship := _native_ship(native, target_id)
	if ship.is_empty():
		return false
	return int(ship.get("hull", 1)) <= 0

static func _alive(world: Dictionary, native: Dictionary, target_id: String) -> bool:
	var ship := _native_ship(native, target_id)
	if not ship.is_empty():
		return int(ship.get("hull", 0)) > 0
	var entity: Dictionary = world.get("entities", {}).get(target_id, {})
	if entity.is_empty():
		return false
	return not bool(entity.get("compromised", false))

static func _rescued(world: Dictionary, target_id: String) -> bool:
	for record: Dictionary in world.get("rescued", []):
		if str(record.get("id", "")) == target_id:
			return true
	return false

static func _inventory(world: Dictionary, good: String) -> int:
	var total := 0
	for ship: Dictionary in world.get("fleet", []):
		total += int(ship.get("cargo", {}).get(good, 0))
	return total

static func _fleet_ship(world: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in world.get("fleet", []):
		if str(ship.get("id", "")) == id:
			return ship
	return {}

static func _native_ship(native: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in native.get("ships", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}

static func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a.get("x", 0.0)) - float(b.get("x", 0.0))
	var dz := float(a.get("z", 0.0)) - float(b.get("z", 0.0))
	return sqrt(dx * dx + dz * dz)
