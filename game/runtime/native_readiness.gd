extends RefCounted
## Read-only UI hints. Business commands still validate and commit through the live fence.
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const Bridge = preload("res://game/runtime/near_field_bridge.gd")
static func _ship(native: Dictionary,id: String) -> Dictionary:
	for ship: Dictionary in native.ships:
		if ship.id == id: return ship
	return {}
static func _distance(a: Dictionary,b: Dictionary) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
static func _fact(ok: bool,reason: String) -> Dictionary: return {"ok":ok,"reason":"" if ok else reason}
static func _working(state: Dictionary,id: String) -> bool:
	for work: Dictionary in state.works.values():
		if work.shipId == id and work.status == "active": return true
	return false
static func _boarded(state: Dictionary,id: String) -> bool:
	for board: Dictionary in state.boardings.values():
		if board.status == "active" and (board.attackerId == id or board.targetId == id or id in board.participants): return true
	return false
static func _ordered(encounter: RefCounted,native: Dictionary,id: String) -> bool:
	return _ship(native,id).get("navigation") != null or encounter.hasActiveOrder(id)
static func _idle(state: Dictionary,native: Dictionary,encounter: RefCounted,id: String) -> bool:
	var vessel: Dictionary = state.vessels[id]; var live := _ship(native,id)
	if encounter.hasPendingAttacks() or live.is_empty() or live.hull <= 0 or vessel.damage.hull <= 0 or vessel.damage.fire > 0 or vessel.damage.flooding > 0 or vessel.voyageId != null or _boarded(state,id) or _working(state,id) or _ordered(encounter,native,id): return false
	for contract: Dictionary in state.contracts.values():
		if contract.status in ["active","delivered"]:
			for person_id in contract.criticalPersonIds:
				var person: Dictionary = state.people.get(person_id,{})
				if person.get("shipId") == id and person.get("alive",false): return false
	return true
static func _receiver(state: Dictionary,policy: Dictionary,id: String,owned_only: bool = false) -> bool:
	var vessel: Dictionary = state.vessels[id]
	var lease: bool = not owned_only and id == state.flagshipId and vessel.ownerId == "house-lin" and vessel.profileId == "flagship"
	return (vessel.ownerId == "captain" or lease) and id in policy.controllableShipIds and not id in policy.lockedShipIds and vessel.crew.able >= vessel.crew.minimum
static func _capacity(receiver: Dictionary,added: Dictionary) -> bool:
	var crew: Dictionary = receiver.crew
	return crew.able+crew.wounded+crew.prisoners+added.able+added.wounded+added.prisoners <= Catalog.DATA.profiles[receiver.profileId].maxCrew and crew.able+added.able >= ceil((crew.prisoners+added.prisoners)/5.0)
static func _close(native: Dictionary,a: String,b: String) -> bool:
	var first := _ship(native,a); var second := _ship(native,b)
	return not first.is_empty() and not second.is_empty() and _distance(first.visual.position,second.visual.position) <= 36 and _distance(first.visual.velocity,second.visual.velocity) <= 3
static func _docked(state: Dictionary,native: Dictionary,encounter: RefCounted,docks: Dictionary,id: String) -> bool:
	if state.currentPortId == null or not docks.get(state.currentPortId,{}).get("ok",false): return false
	var live := _ship(native,id)
	var berth: bool = id == state.campaignId+"-heritage" and Bridge.ordinary_heritage_berth(state) and not _ordered(encounter,native,id) and not _boarded(state,id)
	if berth and live.is_empty(): return true
	return not live.is_empty() and live.hull > 0 and encounter.isAnchored(id) and (berth or _distance(live.visual.position,state.ports[state.currentPortId].position) <= 55)
static func facts(state: Dictionary,native: Dictionary,policy: Dictionary,docks: Dictionary,session: RefCounted,encounter: RefCounted) -> Dictionary:
	var result: Dictionary = {}
	var safe: bool = state.currentPortId != null and docks.get(state.currentPortId,{}).get("ok",false)
	for type in ["buy","sell"]: result[type] = _fact(safe,"unsafe-port")
	for vessel: Dictionary in state.vessels.values():
		var id: String = vessel.id
		var docked := _docked(state,native,encounter,docks,id)
		var berth: bool = id == state.campaignId+"-heritage" and Bridge.ordinary_heritage_berth(state)
		var authorized: bool = id in policy.controllableShipIds or berth
		for type in ["repair","refit","treat-wounded","release-prisoners"]:
			var allowed: bool = authorized or type == "treat-wounded" and (vessel.ownerId == "captain" or session.genuine_lease(id,state))
			var ready: bool = docked and allowed and not _working(state,id) and not _boarded(state,id)
			var reason="ship-not-docked" if not docked else "unauthorized-port-service" if not allowed else "ship-unavailable"
			if type == "treat-wounded" and ready:
				var quote: Dictionary=session.quote_port_service({"type":"treat-wounded","shipId":id,"quantity":1})
				ready=quote.get("ok",false)
				if not ready:reason=quote.get("reason","ship-unavailable")
			if type == "release-prisoners": ready = ready and vessel.crew.prisoners > 0
			result[type+":"+id] = _fact(ready,reason)
		var prize: Dictionary = session.prize_state(id,state)
		var unresolved: bool = not prize.is_empty() and prize.get("resolutionReceiptId") == null and not state.settlements.has(state.campaignId+":prize-disposition:"+id)
		var idle := _idle(state,native,encounter,id)
		var held: bool = unresolved and prize.status == "held" and vessel.crew.able == 0 and idle
		var operational: bool = vessel.crew.able >= vessel.crew.minimum and _capacity(vessel,{"able":0,"wounded":0,"prisoners":0})
		var port_prize: bool = unresolved and prize.status == "crewed" and vessel.ownerId == "captain" and id != state.flagshipId and docked and idle and operational and state.currentPortId in ["xiamen","kinmen"]
		result["resolve-prize:"+id] = _fact(held,"prize-unavailable")
		result["incorporate-prize:"+id] = _fact(port_prize,"prize-not-operational")
		for other: Dictionary in state.vessels.values():
			if id == other.id: continue
			var close := _close(native,id,other.id)
			var profile: Dictionary = Catalog.DATA.profiles[other.profileId]
			var won := false
			for board: Dictionary in state.boardings.values():
				if board.targetId == other.id and session.is_winning_boarding(board.id): won = true
			var weakened: bool = other.damage.hull/profile.maxHull <= 0.65 or other.crew.able/float(profile.complement) <= 0.6
			var boarding: bool = state.currentPortId == null and id in policy.controllableShipIds and other.id in policy.hostileTargets.get(id,[]) and close and vessel.crew.able >= vessel.crew.minimum+1 and not _working(state,id) and not _working(state,other.id) and not _boarded(state,id) and not _boarded(state,other.id) and not won
			result["start-boarding:"+id+":"+other.id] = _fact(boarding and weakened,"target-not-weakened" if boarding else "invalid-boarding")
			var target_prize: Dictionary = session.prize_state(other.id,state)
			var allocation: int = maxi(maxi(12,int(other.crew.minimum)),int(ceil(other.crew.prisoners/5.0))-int(other.crew.able))
			var can_allocate: bool = won and target_prize.get("status") == "held" and other.ownerId != "captain" and id in policy.controllableShipIds and not id in policy.lockedShipIds and not other.id in policy.lockedShipIds and close and not encounter.hasPendingAttacks() and not _ordered(encounter,native,id) and not _ordered(encounter,native,other.id) and vessel.crew.able-allocation >= vessel.crew.minimum and other.crew.able+other.crew.wounded+other.crew.prisoners+allocation <= profile.maxCrew
			result["allocate-prize:"+id+":"+other.id] = _fact(can_allocate,"prize-unavailable")
			var receiver: bool = _receiver(state,policy,other.id) and _idle(state,native,encounter,other.id) and close
			result["take-prize-cargo:"+id+":"+other.id] = _fact(held and receiver,"prize-not-close")
			result["resolve-prize:"+id+":"+other.id] = _fact(held and receiver and _capacity(other,{"able":0,"wounded":vessel.crew.wounded,"prisoners":vessel.crew.prisoners}),"prize-not-close")
			var empty_cargo := true
			for quantity in vessel.cargo.values(): empty_cargo = empty_cargo and quantity == 0
			result["sell-prize:"+id+":"+other.id] = _fact(port_prize and empty_cargo and _receiver(state,policy,other.id,true) and _idle(state,native,encounter,other.id) and _docked(state,native,encounter,docks,other.id) and _capacity(other,vessel.crew),"invalid-prize-receiver")
	return result
