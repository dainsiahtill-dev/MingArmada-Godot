extends RefCounted
## Isolated composition of paid workers and the production naval encounter.
## Native projectiles own loss. Only paid, material-backed repair returns to hull.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
const Rules = preload("res://game/research/demos/crew_role_rules.gd")
const Contract = preload("res://game/research/demos/crew_contract.gd")
const STEP := 1.0/60.0
const MAX_TICKS := 3600
const DEFAULTS := {"roster":"ordinary","repair_helpers":0,"pressure":"duel","seed":1661,"supplies":"normal"}
var _options: Dictionary = {}
var _encounter: RefCounted
var _crew: RefCounted
var _contract: RefCounted
var _native: Dictionary = {}
var _events: Array = []
var _metrics: Dictionary = {}
var _finished := false
var _outcome := "running"
var _error := ""

func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason,"error":reason}

func configure(options: Dictionary = {}) -> Dictionary:
	var candidate := DEFAULTS.duplicate(true)
	for key in options:
		if not candidate.has(key): return _no("unknown battle option")
	candidate.merge(options,true)
	if not candidate.roster is String or candidate.roster not in Contract.ROSTERS or not candidate.pressure is String or candidate.pressure not in ["duel","incoming","calm"] or not candidate.supplies is String or candidate.supplies not in ["normal","scarce"]:
		return _no("invalid battle fixture")
	if not candidate.repair_helpers is int or candidate.repair_helpers < 0 or candidate.repair_helpers > 2 or not candidate.seed is int or candidate.seed < 0 or candidate.seed > 2147483647: return _no("invalid helpers or seed")
	var contract := Contract.new()
	var funded: Dictionary = contract.configure({"roster":candidate.roster})
	if not funded.ok: return _no(funded.error)
	var account: Dictionary = contract.snapshot()
	var crew := Rules.new()
	var staffed: Dictionary = crew.configure({"preset":"scarce" if candidate.supplies == "scarce" else "balanced","hired_ids":account.hired_ids,"qualified_ids":account.qualified_ids,"tick_hz":60,"transfer_seconds":2.0,"casualty_seed":candidate.seed})
	if not staffed.ok: return _no(staffed.error)
	for i in range(candidate.repair_helpers):
		var moved: Dictionary = crew.assign("crew%02d" % (i+4),"carpenter")
		if not moved.ok: return _no(moved.error)
	var config := {"mode":"continuous","referenceGunnery":true,"seed":candidate.seed,"battleId":"crew-role-pressure","playerId":"player","controllableShipIds":["player","enemy"],"hostileTargets":{"player":["enemy"],"enemy":["player"]},"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],"sampleTerrainHeight":flat_terrain,"ships":[
		{"id":"player","name":"试航福船","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0},"heading":0.0,"sailDeployment":0.0,"hull":54.0,"crew":account.hired_count,"stats":{"maxCrew":12.0}},
		{"id":"enemy","name":"压力对手","kind":"fuchuan","team":"player","position":{"x":0.0,"z":110.0},"heading":0.0,"sailDeployment":0.0,"hull":100.0,"crew":12.0,"stats":{"maxCrew":12.0}}
	]}
	var encounter := Encounter.new(config)
	if not encounter.last_error.is_empty(): return _no(encounter.last_error)
	_options = candidate
	_encounter = encounter
	_crew = crew
	_contract = contract
	_native = encounter.snapshot()
	_events.clear()
	_metrics = {"fire_count":0,"hit_count":0,"player_fire_count":0,"enemy_fire_count":0,"player_hit_count":0,"enemy_hit_count":0,"hull_damage_taken":0.0,"hull_repaired":0.0,"crew_lost":0.0,"ammo_spent":0,"enemy_ammo_spent":0,"accepted_volleys":0,"events_count":0,"gun_block_reason":""}
	_finished = false
	_outcome = "running"
	_error = ""
	return {"ok":true}

static func flat_terrain(_x: float,_z: float) -> float: return -80.0

func _ship(id: String, native: Dictionary) -> Dictionary:
	for ship: Dictionary in native.get("ships",[]):
		if ship.id == id: return ship
	return {}

func _operational(ship: Dictionary) -> bool:
	return not ship.is_empty() and ship.hull > 0.0 and ship.crew > 0.0

func assign_helpers(count: Variant) -> Dictionary:
	if _crew == null or _finished or not count is int or count < 0 or count > 2: return _no("experiment ended or invalid helper count")
	var available: Array = []
	for worker: Dictionary in _crew.snapshot().workers:
		if worker.id in ["crew04","crew05"] and worker.health > 0.0: available.append(worker.id)
	if count > available.size(): return _no("可用支援人数不足")
	# Validate both requests before changing either worker.
	for i in range(available.size()):
		var receipt: Dictionary = _crew.assignment_status(available[i],"carpenter" if i < count else "gunner")
		if not receipt.ok: return _no(receipt.error)
	for i in range(available.size()): _crew.assign(available[i],"carpenter" if i < count else "gunner")
	_options.repair_helpers = count
	return {"ok":true}

func _try_fire(ship: Dictionary, side: String, efficiency: float = 1.0) -> void:
	if not _operational(ship) or ship.cooldownSeconds[side] > 0.0 or ship.ammo.solid <= 0: return
	if ship.id == "player":
		var quote := _gunnery(ship,efficiency)
		if not quote.can_work:
			_metrics.gun_block_reason = quote.reason
			return
		var update: Dictionary = _encounter.update_ship_stats("player",{"stats":{"reloadMultiplier":quote.multiplier}})
		if not update.ok: _fail(update.reason); return
		_metrics.gun_block_reason = ""
	var fired: Dictionary = _encounter.command({"type":"fire","shipId":ship.id,"side":side})
	if fired.ok and ship.id == "player": _metrics.accepted_volleys += 1

func _gunnery(ship: Dictionary, efficiency: float) -> Dictionary:
	var result := {"current_cooldown":float(ship.get("cooldownSeconds",{}).get("starboard",0.0)),"next_reload_seconds":0.0,"can_work":false,"reason":"没有可用炮手","multiplier":0.0}
	if not _operational(ship) or efficiency <= 0.0: return result
	# Health is already reflected in individual job labor. Do not penalize it twice.
	var native_factor := 1.0+(1.0-clampf(ship.crew/ship.maxCrew,0.0,1.0))*1.5
	var multiplier := 1.0/(efficiency*native_factor)
	if multiplier > 10.0:
		result.reason = "炮手劳动不足以完成本轮装填"
		return result
	var forecast := ship.duplicate(true)
	forecast.stats.reloadMultiplier = multiplier
	result.can_work = true
	result.reason = ""
	result.multiplier = multiplier
	result.next_reload_seconds = Cannon.reload_seconds(forecast)
	return result

func step() -> void:
	if _encounter == null or _finished: return
	var before_player := _ship("player",_native)
	var before_enemy := _ship("enemy",_native)
	if _operational(before_player) and _operational(before_enemy):
		if _options.pressure == "duel": _try_fire(before_player,"starboard",float(_crew.snapshot().gun_efficiency))
		if _finished: return
		if _options.pressure in ["duel","incoming"]: _try_fire(before_enemy,"port")
	_encounter.step_fixed()
	var after_fire: Dictionary = _encounter.snapshot()
	var player := _ship("player",after_fire)
	var enemy := _ship("enemy",after_fire)
	var observed: Dictionary = _crew.observe_combat(player.hull,player.crew)
	if not observed.ok: _fail(observed.error); return
	_metrics.hull_damage_taken += maxf(0.0,before_player.hull-player.hull)
	_metrics.crew_lost += maxf(0.0,before_player.crew-player.crew)
	_metrics.ammo_spent += maxi(0,int(before_player.ammo.solid)-int(player.ammo.solid))
	_metrics.enemy_ammo_spent += maxi(0,int(before_enemy.ammo.solid)-int(enemy.ammo.solid))
	_crew.step()
	var worked: Dictionary = _crew.snapshot()
	var repair := maxf(0.0,worked.hull-player.hull)
	if repair > 0.0:
		var repaired: Dictionary = _encounter.update_ship_stats("player",{"hull":worked.hull})
		if not repaired.ok: _fail(repaired.reason); return
		_metrics.hull_repaired += repair
	_native = _encounter.snapshot()
	for event: Dictionary in _encounter.drain_events():
		_events.append(event.duplicate(true))
		_metrics.events_count += 1
		if event.type == "fire":
			_metrics.fire_count += 1
			_metrics["player_fire_count" if event.shipId == "player" else "enemy_fire_count"] += 1
		elif event.type == "hit":
			_metrics.hit_count += 1
			_metrics["player_hit_count" if event.shipId == "player" else "enemy_hit_count"] += 1
	var player_up := _operational(_ship("player",_native))
	var enemy_up := _operational(_ship("enemy",_native))
	if int(worked.tick) >= MAX_TICKS or ((not player_up or not enemy_up) and not _encounter.has_pending_attacks()):
		_finished = true
		_outcome = "mutual_loss" if not player_up and not enemy_up else "defeat" if not player_up else "victory" if not enemy_up else "time_limit"

func _fail(reason: String) -> void:
	_error = reason
	_finished = true
	_outcome = "error"

func snapshot() -> Dictionary:
	if _crew == null: return {"ready":false,"finished":false}
	var crew: Dictionary = _crew.snapshot()
	return {"ready":true,"tick":crew.tick,"time":crew.time,"fixed_step":STEP,"finished":_finished,"outcome":_outcome,"error":_error,"options":_options.duplicate(true),"native":_native.duplicate(true),"crew":crew,"contract":_contract.snapshot(),"metrics":_metrics.duplicate(true),"gunnery":_gunnery(_ship("player",_native),float(crew.gun_efficiency)),"events_count":_metrics.events_count,"scope":"Paid crew in deterministic production projectile encounter; fixed positions, abstract casualty assignment, not campaign economy or manual combat acceptance."}

func drain_events() -> Array:
	var result := _events.duplicate(true)
	_events.clear()
	return result
