extends RefCounted
## Experimental rules only. Host owns time; no campaign, save or audio dependencies.

const STEP := 1.0 / 32.0
const ROLES := ["cook", "musician", "carpenter", "gunner", "rest"]
const PRESETS := ["balanced", "scarce", "emergency"]
const SEA_REPAIR_CAP := 80.0
const RATION_CAP := 12.0
const BALANCE_VERSION := "crew-lab-r3-contract-pressure"
const REPAIR_MODELS := ["legacy_cap", "workstations"]
const REPAIR_SLOTS := 3
const SPECIALIST_EFFICIENCY := 1.5
const HULL_PER_LABOR_SECOND := 0.75
const WOOD_PER_HULL := 0.5
var _state: Dictionary = {}
var _next_diner := 0

func configure(options: Dictionary = {}) -> Dictionary:
	for key in options:
		if key not in ["preset", "specialists", "repair_model", "hired_ids", "qualified_ids", "tick_hz", "transfer_seconds", "casualty_seed"]:
			return {"ok":false,"error":"unknown option"}
	var preset = options.get("preset", "balanced")
	var specialists = options.get("specialists", true)
	var repair_model = options.get("repair_model", "workstations")
	if not preset is String or preset not in PRESETS or not specialists is bool or not repair_model is String or repair_model not in REPAIR_MODELS:
		return {"ok":false,"error":"invalid option value"}
	var tick_hz = options.get("tick_hz",32)
	var transfer_seconds = options.get("transfer_seconds",0.0)
	var casualty_seed = options.get("casualty_seed",0)
	if not tick_hz is int or tick_hz not in [32,60] or not _number(transfer_seconds) or transfer_seconds < 0.0 or transfer_seconds > 30.0 or not casualty_seed is int or casualty_seed < 0 or casualty_seed > 2147483647:
		return {"ok":false,"error":"invalid clock or transfer options"}
	var available: Array = []
	for i in range(12): available.append("crew%02d" % (i+1))
	var hired = options.get("hired_ids",available)
	if not _ids(hired,available) or hired.is_empty(): return {"ok":false,"error":"invalid hired roster"}
	var qualified = options.get("qualified_ids",hired.filter(func(id):return available.find(id)<7) if specialists else [])
	if not _ids(qualified,hired): return {"ok":false,"error":"invalid qualifications"}
	hired = hired.duplicate(); hired.sort()
	qualified = qualified.duplicate(); qualified.sort()
	var workers: Array = []
	var initial_roles := ["cook", "musician", "carpenter", "gunner", "gunner", "gunner", "gunner", "rest", "rest", "rest", "rest", "rest"]
	var names := ["庖师", "乐师", "木匠", "炮手甲", "炮手乙", "炮手丙", "炮手丁", "水手甲", "水手乙", "水手丙", "水手丁", "水手戊"]
	for i in range(12):
		var id := "crew%02d" % (i+1)
		if id not in hired: continue
		var role: String = initial_roles[i]
		workers.append({"id":id,"name":names[i],"specialty":role if role != "rest" else "sailor","qualified":specialists and id in qualified,"role":"carpenter" if preset == "emergency" and i in [3,4] else role,"fatigue":60.0,"health":1.0,"pending_role":"","transfer_remaining_ticks":0})
	var casualty_order: Array = hired.duplicate()
	var rng := RandomNumberGenerator.new(); rng.seed = casualty_seed
	for i in range(casualty_order.size()-1,0,-1):
		var j := rng.randi_range(0,i)
		var swap = casualty_order[i]; casualty_order[i] = casualty_order[j]; casualty_order[j] = swap
	_state = {"tick":0,"time":0.0,"tick_hz":tick_hz,"workers":workers,"casualty_order":casualty_order,"grain":0.5 if preset == "scarce" else 24.0,"cooked_rations":0.0,"wood":1.0 if preset == "scarce" else 16.0,"hull":54.0,"sea_repair_cap":SEA_REPAIR_CAP,"morale":40.0,"balance_version":BALANCE_VERSION,"options":{"preset":preset,"specialists":specialists,"repair_model":repair_model,"hired_ids":hired,"qualified_ids":qualified,"tick_hz":tick_hz,"transfer_seconds":float(transfer_seconds),"casualty_seed":casualty_seed},"ledger":{"grain_used":0.0,"meals_cooked":0.0,"meals_eaten":0,"wood_used":0.0,"hull_repaired":0.0,"hull_damage":0.0,"crew_lost":0.0}}
	_next_diner = 0
	return {"ok":true}

func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

func _ids(value: Variant, allowed: Array) -> bool:
	if not value is Array: return false
	var seen := {}
	for id in value:
		if not id is String or id not in allowed or seen.has(id): return false
		seen[id] = true
	return true

func _crew_total() -> float:
	var total := 0.0
	for worker: Dictionary in _state.get("workers",[]): total += float(worker.health)
	return total

func assignment_status(worker_id: String, role: String) -> Dictionary:
	if role not in ROLES: return {"ok":false,"error":"unknown role"}
	for worker: Dictionary in _state.get("workers",[]):
		if worker.id == worker_id:
			if _state.hull <= 0.0 or worker.health <= 0.0: return {"ok":false,"error":"worker unavailable"}
			if not worker.pending_role.is_empty() and worker.pending_role != role: return {"ok":false,"error":"transfer already in progress"}
			return {"ok":true}
	return {"ok":false,"error":"unknown worker"}

func assign(worker_id: String, role: String) -> Dictionary:
	var receipt := assignment_status(worker_id,role)
	if not receipt.ok: return receipt
	for worker: Dictionary in _state.workers:
		if worker.id != worker_id: continue
		if worker.role == role or worker.pending_role == role: return {"ok":true}
		var ticks := int(ceil(_state.options.transfer_seconds*_state.tick_hz))
		worker.role = role if ticks == 0 else "transit"
		worker.pending_role = "" if ticks == 0 else role
		worker.transfer_remaining_ticks = ticks
	return {"ok":true}

func observe_combat(hull: Variant, effective_crew: Variant) -> Dictionary:
	if _state.is_empty() or not _number(hull) or not _number(effective_crew) or hull < 0.0 or hull > _state.hull+0.0000001 or effective_crew < 0.0 or effective_crew > _crew_total()+0.0000001:
		return {"ok":false,"error":"combat observation must be finite actual loss"}
	var hull_loss := maxf(0.0,_state.hull-float(hull))
	var remaining := maxf(0.0,_crew_total()-float(effective_crew))
	_state.hull -= hull_loss
	_state.ledger.hull_damage += hull_loss
	_state.ledger.crew_lost += remaining
	for id in _state.casualty_order:
		if remaining <= 0.0: break
		for worker: Dictionary in _state.workers:
			if worker.id != id: continue
			var loss := minf(worker.health,remaining)
			worker.health = maxf(0.0,worker.health-loss)
			remaining = maxf(0.0,remaining-loss)
			if worker.health <= 0.0:
				worker.pending_role = ""
				worker.transfer_remaining_ticks = 0
	return {"ok":true}

func _labor() -> Dictionary:
	var labor := {"cook":0.0,"musician":0.0,"carpenter":0.0,"gunner":0.0,"rest":0.0}
	for worker: Dictionary in _state.get("workers",[]):
		if worker.health <= 0.0 or worker.role == "transit" or _state.hull <= 0.0: continue
		var skilled: bool = worker.qualified and worker.specialty == worker.role
		labor[worker.role] += (SPECIALIST_EFFICIENCY if skilled else 1.0)*worker.health
	return labor

func _repair_staffing() -> Dictionary:
	var candidates: Array = []
	for worker: Dictionary in _state.workers:
		if worker.role == "carpenter" and worker.health > 0.0:
			candidates.append({"id":worker.id,"labor":(SPECIALIST_EFFICIENCY if worker.qualified and worker.specialty == "carpenter" else 1.0)*worker.health})
	candidates.sort_custom(func(a: Dictionary,b: Dictionary) -> bool:
		return a.id < b.id if a.labor == b.labor else a.labor > b.labor)
	var legacy: bool = _state.options.repair_model == "legacy_cap"
	var count: int = candidates.size() if legacy else mini(candidates.size(),REPAIR_SLOTS)
	if _state.wood <= 0.0 or _state.hull >= SEA_REPAIR_CAP or _state.hull <= 0.0: count = 0
	var ids: Array = []
	var labor := 0.0
	for i in range(count):
		ids.append(candidates[i].id)
		labor += float(candidates[i].labor)
	if legacy: labor = minf(labor,2.0)
	return {"model":_state.options.repair_model,"assigned":candidates.size(),"active":count,"waiting":candidates.size()-count,"worker_ids":ids,"labor":labor}

func _rates(labor: Dictionary) -> Dictionary:
	return {"cooking":minf(labor.cook,2.0)*0.5 if _state.grain > 0.0 and _state.cooked_rations < RATION_CAP else 0.0,"repair":float(_repair_staffing().labor)*HULL_PER_LABOR_SECOND,"morale":minf(labor.musician,1.5)*0.7*float(labor.rest)/12.0 if _state.morale < 100.0 else 0.0}

func step() -> void:
	if _state.is_empty(): return
	_state.tick += 1
	var step_seconds := 1.0 / float(_state.tick_hz)
	_state.time = float(_state.tick) / float(_state.tick_hz)
	if _state.hull <= 0.0 or _crew_total() <= 0.0: return
	var labor := _labor()
	var rates := _rates(labor)
	var cooked := minf(rates.cooking*step_seconds,minf(_state.grain,RATION_CAP-_state.cooked_rations))
	_state.grain = maxf(0.0,_state.grain-cooked)
	_state.cooked_rations += cooked
	_state.ledger.grain_used += cooked
	_state.ledger.meals_cooked += cooked
	var repaired := maxf(0.0,minf(rates.repair*step_seconds,minf(_state.wood/WOOD_PER_HULL,SEA_REPAIR_CAP-_state.hull)))
	_state.wood = maxf(0.0,_state.wood-repaired*WOOD_PER_HULL)
	_state.hull += repaired
	_state.ledger.wood_used += repaired*WOOD_PER_HULL
	_state.ledger.hull_repaired += repaired
	_state.morale = minf(100.0,_state.morale+rates.morale*step_seconds)
	for worker: Dictionary in _state.workers:
		if worker.role == "rest" and worker.health > 0.0: worker.fatigue = maxf(0.0,worker.fatigue-0.2*step_seconds)
	if int(_state.tick) % int(_state.tick_hz) == 0 and _state.cooked_rations >= 1.0:
		_serve_meal()
	for worker: Dictionary in _state.workers:
		if worker.health > 0.0 and worker.transfer_remaining_ticks > 0:
			worker.transfer_remaining_ticks -= 1
			if worker.transfer_remaining_ticks == 0:
				worker.role = worker.pending_role
				worker.pending_role = ""

func _serve_meal() -> void:
	# A stable cursor prevents the first resting sailor monopolising every meal.
	for offset in range(_state.workers.size()):
		var index: int = (_next_diner+offset) % _state.workers.size()
		var worker: Dictionary = _state.workers[index]
		if worker.role == "rest" and worker.health > 0.0 and worker.fatigue > 0.0:
			worker.fatigue = maxf(0.0,worker.fatigue-6.0)
			_state.cooked_rations -= 1.0
			_state.ledger.meals_eaten += 1
			_next_diner = (index+1) % _state.workers.size()
			return

func snapshot() -> Dictionary:
	if _state.is_empty(): return {}
	var result := _state.duplicate(true)
	var counts := {"cook":0,"musician":0,"carpenter":0,"gunner":0,"rest":0,"transit":0,"incapacitated":0}
	for worker: Dictionary in result.workers:
		worker.transfer_remaining_seconds = float(worker.transfer_remaining_ticks)/float(_state.tick_hz)
		counts[worker.role if worker.health > 0.0 else "incapacitated"] += 1
	var labor := _labor()
	result.counts = counts
	result.rates = _rates(labor)
	result.gun_efficiency = minf(labor.gunner/4.0,1.0)
	result.repair_staffing = _repair_staffing()
	result.next_diner = _next_diner
	result.crew_equivalent = _crew_total()
	return result
