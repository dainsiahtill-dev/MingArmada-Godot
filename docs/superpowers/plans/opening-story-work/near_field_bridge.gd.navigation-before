extends RefCounted
## Business/native handoff from NearFieldBridge.ts. A context is a single-use fence.
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
var campaign: RefCounted
var simulation: RefCounted
var _near_ids: Array = []
var _pending_events: Array = []
var _previous_native: Dictionary = {}
var _observer: Callable

func _init(session: RefCounted, native_simulation: RefCounted, on_events: Callable = Callable()) -> void:
	campaign = session; simulation = native_simulation; _observer = on_events
	_near_ids = simulation.snapshot().ships.map(func(ship): return ship.id)
static func _ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships",[]):
		if ship.id == id: return ship
	return {}
static func _distance(a: Dictionary, b: Dictionary) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
static func ordinary_heritage_berth(state: Dictionary) -> bool:
	var id: String = state.campaignId+"-heritage"; var v: Dictionary = state.vessels.get(id,{})
	if v.is_empty() or v.ownerId != "captain" or v.voyageId != null or v.damage.hull <= 0 or _distance(v.pose.position,Catalog.DATA.spawn.heritage) > 10 or v.pose.speed > 0.05 or v.controls.rudder != 0 or v.controls.sailDeployment != 0: return false
	for b: Dictionary in state.boardings.values():
		if b.status == "active" and id in [b.attackerId,b.targetId]+b.participants: return false
	for w: Dictionary in state.works.values():
		if w.status == "active" and w.shipId == id: return false
	return true
func near_ids() -> Array: return _near_ids.duplicate()
func set_observer(observer: Callable) -> void: _observer = observer
func capture() -> Dictionary:
	simulation.refresh_snapshot()
	var events: Array = simulation.drain_events()
	_pending_events.append_array(events)
	if _observer.is_valid() and not events.is_empty(): _observer.call(events.duplicate(true))
	return simulation.snapshot()
func _team(vessel: Dictionary) -> String:
	if vessel.ownerId == "enemy": return "hostile"
	return "player" if vessel.profileId in ["flagship","fast"] or vessel.ownerId == "captain" else "neutral"
func _retired(state: Dictionary,id: String) -> bool: return campaign.prize_state(id,state).get("status") == "sold"
func _apply(vessels: Array,state: Dictionary,anchors: Array = [],fresh_startup: bool = false) -> Dictionary:
	var retained: Array = vessels.filter(func(v): return not _retired(state,v.id))
	var policy: Dictionary = campaign.native_policy(retained.map(func(v): return v.id),state)
	var navigation: Dictionary = {}
	var setups: Array = []
	for vessel: Dictionary in retained:
		var setup: Dictionary = campaign.near_field_setup(vessel,_team(vessel))
		if setup.is_empty(): return {"ok":false,"reason":"invalid-near-field-setup"}
		setups.append(setup)
		if fresh_startup: navigation[vessel.id] = null
		elif vessel.voyageId != null:
			var voyage: Dictionary = state.voyages.get(vessel.voyageId,{})
			if voyage.get("status") == "underway":
				var route: Dictionary = Catalog.DATA.routes.get(voyage.routeId,{})
				if route.is_empty(): return {"ok":false,"reason":"unknown-route"}
				var location: Dictionary = campaign.locate_route(vessel,route)
				navigation[vessel.id] = route.points[location.leg+1].duplicate()
			else: navigation[vessel.id] = null
	policy.navigation = navigation; policy.anchorShipIds = anchors.duplicate()
	if fresh_startup: policy.orders = []
	return simulation.encounter.reconcileShips(setups,policy)
func command_context() -> Dictionary:
	var native := capture()
	var encounter: RefCounted = simulation.encounter
	var fence := {"consumed":false,"battleId":native.battleId,"tick":native.tick,"sequences":{}}
	for ship: Dictionary in native.ships: fence.sequences[ship.id] = ship.controlsSequence
	var validate := func() -> Dictionary:
		if fence.consumed or simulation.encounter != encounter: return {"ok":false,"reason":"stale-native-context"}
		var current: Dictionary = encounter.snapshot()
		if current.battleId != fence.battleId or current.tick != fence.tick or current.ships.size() != fence.sequences.size(): return {"ok":false,"reason":"stale-native-context"}
		for ship: Dictionary in current.ships:
			if not fence.sequences.has(ship.id) or fence.sequences[ship.id] != ship.controlsSequence: return {"ok":false,"reason":"stale-native-context"}
		return {"ok":true}
	var consume := func() -> Dictionary:
		var valid: Dictionary = validate.call()
		if valid.ok: fence.consumed = true
		return valid
	var project := func(state: Dictionary,anchors: Array,phase: String) -> Dictionary:
		var valid: Dictionary = consume.call()
		if not valid.ok: return valid
		var ids := _near_ids.duplicate()
		for id in anchors:
			if not id in ids: ids.append(id)
		ids = ids.filter(func(id): return state.vessels.has(id) and not _retired(state,id))
		var vessels := ids.map(func(id): return state.vessels[id])
		var result := _apply(vessels,state,anchors,phase == "fresh-startup")
		if not result.ok: return result
		_near_ids = ids; _pending_events.clear(); simulation.refresh_snapshot()
		return {"ok":true,"snapshot":simulation.snapshot()}
	return {"applyOrder":func(order: Dictionary) -> Dictionary:
		var valid: Dictionary = consume.call()
		return encounter.issueOrder(order) if valid.ok else valid,
		"native":{"snapshot":native,"events":_pending_events.duplicate(true),"pendingAttacks":encounter.hasPendingAttacks(),"validateCurrent":validate,
		"isAnchored":func(id: String) -> bool: return encounter.isAnchored(id),
		"hasActiveOrder":func(id: String) -> bool: return not validate.call().ok or encounter.hasActiveOrder(id),
		"supportsPrizeRetirement":true,"project":project}}
func _unsafe(ship: Dictionary,native: Dictionary,state: Dictionary) -> bool:
	var encounter: RefCounted = simulation.encounter
	if encounter.hasPendingAttacks() or ship.cooldownSeconds.port > 0 or ship.cooldownSeconds.starboard > 0: return true
	if ship.id in campaign.active_boarding_ship_ids(): return true
	for work: Dictionary in state.works.values():
		if work.status == "active" and work.shipId == ship.id: return true
	for order: Dictionary in state.orders:
		if order.intent.kind != "prepare-boarding": continue
		for status: Dictionary in encounter.orderStatus():
			if status.id == order.id and status.state == "active" and (ship.id in order.shipIds or ship.id == order.intent.get("targetId")): return true
	var v: Dictionary = ship.visual.velocity
	var lateral: float = -v.x*sin(ship.visual.heading)+v.z*cos(ship.visual.heading)
	if absf(lateral) > 0.75 or absf(ship.visual.heel) > 0.7 or absf(ship.visual.pitch) > 0.7: return true
	var previous := _ship(_previous_native,ship.id)
	var elapsed: float = native.time-_previous_native.get("time",native.time)
	if not previous.is_empty() and elapsed > 0:
		var turn: float = atan2(sin(ship.visual.heading-previous.visual.heading),cos(ship.visual.heading-previous.visual.heading))/elapsed
		if absf(turn) > 0.1: return true
	for other: Dictionary in native.ships:
		if other.id == ship.id or other.hull <= 0: continue
		var separation := _distance(ship.visual.position,other.visual.position)
		if other.team == "hostile" and separation <= 600: return true
		var radius: float = Vector2(ship.dimensions.length,ship.dimensions.width).length()/2+Vector2(other.dimensions.length,other.dimensions.width).length()/2+10
		var relative: float = Vector2(v.x-other.visual.velocity.x,v.z-other.visual.velocity.z).length()
		if separation <= radius+relative*2: return true
	return false
func reconcile() -> Dictionary:
	var before := capture(); var state: Dictionary = campaign.snapshot()
	var flagship := _ship(before,state.flagshipId)
	if flagship.is_empty(): return {"ok":false,"reason":"flagship-not-near"}
	var pinned: Array = [state.flagshipId,state.campaignId+"-fast"]
	var ordinary := ordinary_heritage_berth(state)
	var heritage := _ship(before,state.campaignId+"-heritage")
	if ordinary and not heritage.is_empty() and (_distance(heritage.visual.position,Catalog.DATA.spawn.heritage) > 10 or not simulation.encounter.isAnchored(heritage.id)): pinned.append(heritage.id)
	for vessel: Dictionary in state.vessels.values():
		if vessel.ownerId == "captain" and vessel.damage.hull > 0 and not (ordinary and vessel.id == state.campaignId+"-heritage") and not vessel.id in pinned: pinned.append(vessel.id)
	for contract: Dictionary in state.contracts.values():
		if contract.status == "active":
			for id in contract.voyageIds:
				var voyage: Dictionary = state.voyages.get(id,{})
				if not voyage.is_empty() and not voyage.vesselId in pinned: pinned.append(voyage.vesselId)
	for id in campaign.active_boarding_ship_ids():
		if not id in pinned: pinned.append(id)
	for work: Dictionary in state.works.values():
		if work.status == "active" and not work.shipId in pinned: pinned.append(work.shipId)
	var policy: Dictionary = campaign.native_policy(state.vessels.keys(),state)
	var next: Array = []
	for vessel: Dictionary in state.vessels.values():
		if _retired(state,vessel.id): continue
		if ordinary and vessel.id == state.campaignId+"-heritage" and not vessel.id in pinned: continue
		if vessel.ownerId == "enemy" and state.currentPortId != null and not vessel.id in policy.capturedShipIds: continue
		var live := _ship(before,vessel.id)
		if vessel.damage.hull <= 0 or not live.is_empty() and live.hull <= 0:
			if not live.is_empty(): next.append(vessel.id)
			continue
		var separation := _distance(live.visual.position if not live.is_empty() else vessel.pose.position,flagship.visual.position)
		if vessel.id in pinned or separation <= 600 or not live.is_empty() and (separation <= 800 or _unsafe(live,before,state)): next.append(vessel.id)
	var result: Dictionary = campaign.reconcile_near(before,_pending_events,next,func(vessels: Array,candidate: Dictionary) -> Dictionary: return _apply(vessels,candidate))
	if result.ok: _near_ids = next; _pending_events.clear(); _previous_native = before; simulation.refresh_snapshot()
	return result
func sync() -> Dictionary:
	var before := capture(); var state: Dictionary = campaign.snapshot()
	var ids := _near_ids.filter(func(id): return not _retired(state,id))
	var result: Dictionary = campaign.reconcile_near(before,_pending_events,ids,func(vessels: Array,candidate: Dictionary) -> Dictionary: return _apply(vessels,candidate))
	if result.ok: _near_ids = ids; _pending_events.clear(); _previous_native = before; simulation.refresh_snapshot()
	return result
func dispose() -> void:
	_observer = Callable(); _pending_events.clear(); _previous_native.clear()
	campaign = null; simulation = null
