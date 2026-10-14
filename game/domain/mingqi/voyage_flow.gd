extends RefCounted
## Read-only voyage presentation. Campaign receipts remain the only payment authority.
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const CONTRACTS := ["convoy-001", "convoy-002"]

static func project(state: Dictionary) -> Dictionary:
	var contracts: Array = []
	var settlements: Array = []
	var branches: Array = []
	var active: Dictionary = {}
	for id: String in CONTRACTS:
		var contract: Dictionary = state.get("contracts", {}).get(id, {})
		if contract.is_empty(): continue
		var progress := _progress(state, contract)
		contracts.append(progress)
		if active.is_empty() or active.stage == "closed": active = progress
		var receipt: Dictionary = state.get("settlements", {}).get(str(contract.get("receiptId", "")), {})
		var details: Dictionary = receipt.get("details", {})
		if receipt.get("id") != str(state.get("campaignId", "")) + ":" + id + ":claim" or receipt.get("kind") != "claim-convoy" or details.get("kind") != "convoy" or details.get("contractId") != id: continue
		var dead := 0
		var wounded := 0
		for ship: Dictionary in details.get("ships", []):
			dead += int(ship.get("dead", 0))
			wounded += int(ship.get("wounded", 0))
		settlements.append({"contractId": id, "delivered": int(details.get("delivered", 0)), "lost": int(details.get("lost", 0)), "baseReward": int(details.get("baseReward", 0)), "bonus": int(details.get("bonus", 0)), "paid": int(details.get("baseReward", 0)) + int(details.get("bonus", 0)), "leasePaid": int(details.get("leasePaid", 0)), "dead": dead, "wounded": wounded})
	for event: Dictionary in state.get("chronicle", []):
		var receipt: Dictionary = state.get("settlements", {}).get(event.get("id", ""), {})
		if receipt.get("kind") != "story-choice": continue
		var details: Dictionary = receipt.get("details", {})
		branches.append({"sceneId": details.get("sceneId", ""), "choiceId": details.get("choiceId", ""), "silverCost": int(details.get("silverCost", 0)), "message": receipt.get("message", ""), "time": event.get("simTime", 0)})
	return {"active": active, "contracts": contracts, "settlements": settlements, "branches": branches, "upgrade": _upgrade(state)}.duplicate(true)

static func _progress(state: Dictionary, contract: Dictionary) -> Dictionary:
	var counts := {"loading": 0, "underway": 0, "arrived": 0, "lost": 0, "interrupted": 0}
	for id in contract.get("voyageIds", []):
		var status: String = state.get("voyages", {}).get(id, {}).get("status", "interrupted")
		if counts.has(status): counts[status] += 1
	var status: String = contract.get("status", "")
	var closed := status in ["settled", "failed"]
	var stage := "closed" if closed else "offered" if status == "offered" else "claim" if counts.arrived + counts.lost == contract.get("voyageIds", []).size() and not contract.get("voyageIds", []).is_empty() else "loading" if counts.loading > 0 else "underway"
	var deadline := float(contract.get("deadlineAt", 0))
	var remaining := deadline - float(state.get("simulationSeconds", 0))
	var mode := "closed" if closed else "on-acceptance" if deadline <= 0 else "overdue" if remaining < 0 else "remaining"
	return {"contractId": contract.get("id", ""), "stage": stage, "counts": counts, "deadlineMode": mode, "remainingSeconds": maxf(0, remaining) if mode == "remaining" else 0.0, "overdueSeconds": -remaining if mode == "overdue" else 0.0}

static func _upgrade(state: Dictionary) -> Dictionary:
	for vessel: Dictionary in state.get("vessels", {}).values():
		if vessel.get("ownerId") != "captain" or float(vessel.get("damage", {}).get("hull", 0)) <= 0: continue
		var profile: Dictionary = Catalog.DATA.profiles.get(vessel.get("profileId", ""), {})
		for work: Dictionary in state.get("works", {}).values():
			if work.get("shipId") == vessel.get("id") and work.get("kind") == "refit" and work.get("status") == "active":
				return {"shipId": vessel.id, "name": vessel.get("name", "自有船"), "portId": "xiamen", "status": "working", "cost": work.get("cost", 0), "remainingSeconds": maxf(0, float(work.get("completeAt", 0)) - float(state.get("simulationSeconds", 0))), "speedMultiplier": profile.get("speedMultiplier", 1)}
		var target: Dictionary = Catalog.DATA.profiles.get(str(profile.get("refitProfileId", "")), {})
		if not target.is_empty():
			return {"shipId": vessel.id, "name": vessel.get("name", "自有船"), "portId": "xiamen", "status": "available", "cost": 150, "durationSeconds": 120, "speedMultiplier": profile.get("speedMultiplier", 1), "targetSpeedMultiplier": target.get("speedMultiplier", 1)}
		if float(profile.get("speedMultiplier", 1)) > 1:
			return {"shipId": vessel.id, "name": vessel.get("name", "自有船"), "portId": "xiamen", "status": "completed", "speedMultiplier": profile.get("speedMultiplier", 1)}
	return {}
