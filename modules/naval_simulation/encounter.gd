extends RefCounted
const Navigation = preload("res://modules/contracts/navigation_contract.gd")
# Native port of frozen naval-core NavalEncounter. Detached scalar snapshots only.
const Physics = preload("res://modules/physics_engine/ships/ship_dynamics.gd")
const Types = preload("res://modules/contracts/physics_types.gd")
const Ocean = preload("res://modules/naval_simulation/ocean_adapter.gd")
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const FireLauncher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const Sweep = preload("res://modules/naval_simulation/combat/projectiles.gd")
const Orders = preload("res://modules/naval_simulation/tactics/order_controller.gd")
const Planner = preload("res://modules/naval_simulation/navigation/wet_route_planner.gd")
const Approach = preload("res://modules/naval_simulation/navigation/approach_clearance.gd")
const Egress = preload("res://modules/naval_simulation/navigation/wet_route_egress.gd")
const Manual = preload("res://modules/physics_engine/ships/manual_handling.gd")
const Casual = preload("res://modules/naval_simulation/controls/casual_sailing.gd")
const Collator = preload("res://modules/naval_simulation/id_collator.gd")
const Weather = preload("res://modules/environment_engine/weather_state.gd")
const DT = 1.0 / 60.0
const GRAVITY = 9.81
const SAFE_INTEGER = 9007199254740991
var config: Dictionary = {}
var ships: Array = []
var ocean = Ocean.new()
var wind: Dictionary = {"direction": {"x": -1.0, "y": 0.0}, "speed": 12.0}
var player_id = "player"
var tick = 0
var accumulator = 0.0
var status = "sailing"
var events: Array = []
var projectiles: Array = []
var projectile_damage: Dictionary = {}
var volleys: Array = []
var sequence = 0
var epoch = 0
var battle_id = ""
var surrender: Dictionary = {}
var policy: Dictionary = {}
var orders: Dictionary = {}
var decisions: Dictionary = {}
var episode = 0
var episode_open = false
var episode_threats: Array = []
var last_error = ""
var _id_collator = Collator.new()
var _environment: RefCounted
func _init(initial: Dictionary = {}) -> void: reset(initial)
func reset(initial: Dictionary = config) -> bool:
	for flag in ["referenceHandling", "referenceGunnery"]:
		if initial.has(flag) and not initial[flag] is bool: last_error = "Invalid reference configuration"; return false
	var next_player = initial.get("playerId", "player")
	var next_wind = initial.get("wind", {"direction": {"x": -1.0, "y": 0.0}, "speed": 12.0})
	if not next_player is String or next_player.is_empty() or not _valid_wind(next_wind) or not _finite(initial.get("seed", 1661)) or not _finite(initial.get("seaLevel", 0)):
		last_error = "Invalid encounter configuration"; return false
	if initial.has("enemyCount") and (not _finite(initial.enemyCount) or initial.enemyCount != floor(initial.enemyCount) or initial.enemyCount < 0 or initial.enemyCount > 2): last_error = "Invalid enemy count"; return false
	if initial.has("battleId") and (not initial.battleId is String or initial.battleId.is_empty()): last_error = "Invalid battle identity"; return false
	if initial.has("mode") and not initial.mode in ["terminal", "continuous"]: last_error = "Invalid encounter mode"; return false
	if initial.has("environmentRoute") and not initial.environmentRoute in ["sailing","battle"]: last_error = "Invalid environment route"; return false
	if not initial.get("environmentOptions",{}) is Dictionary: last_error = "Invalid environment options"; return false
	var next_ocean = Ocean.new()
	next_ocean.sea_level = initial.get("seaLevel", 0.0)
	if initial.has("waveSampler"):
		if not initial.waveSampler is RefCounted or not initial.waveSampler.has_method("sample"): last_error = "Invalid wave sampler"; return false
		next_ocean.sampler = initial.waveSampler
	if initial.has("oceanWaves"):
		if not initial.oceanWaves is Array or initial.oceanWaves.size() > 8: last_error = "At most eight ocean waves are supported"; return false
		var amplitude_sum = 0.0
		for wave in initial.oceanWaves:
			if not wave is Dictionary or not wave.get("direction") is Dictionary or not [wave.direction.get("x"), wave.direction.get("y", wave.direction.get("z")), wave.get("amplitude"), wave.get("speed"), wave.get("wavelength")].all(_finite) or wave.wavelength <= 0 or not is_finite(2 * PI / wave.wavelength): last_error = "Ocean waves need finite values and a positive wavelength"; return false
			amplitude_sum += absf(wave.amplitude)
			var canonical_wave = wave.duplicate(true)
			canonical_wave.direction = {"x": wave.direction.x, "y": wave.direction.get("y", wave.direction.get("z"))}
			next_ocean.waves.append(canonical_wave)
		next_ocean.heave_excursion = 2 * amplitude_sum
		if not is_finite(next_ocean.heave_excursion): last_error = "Ocean wave travel envelope must be finite"; return false
	else: next_ocean.set_heading({"x": -next_wind.direction.x, "y": -next_wind.direction.y})
	var jitter = (fmod(float(initial.get("seed", 1661)), 17.0) - 8) * 0.4
	var setups = initial.get("ships", [{"id": next_player, "name": "逐浪号", "kind": "fuchuan", "team": "player", "position": {"x": 0, "z": 0}}])
	if not initial.has("ships"):
		for i in int(initial.get("enemyCount", 0)):
			setups.append({"id": "enemy-" + str(i + 1), "name": "海盗战船" if i else "VOC武装商船", "kind": "fuchuan" if i else "voc", "team": "hostile", "position": {"x": jitter + i * 12, "z": -105 if i else 105}})
	if not setups is Array: last_error = "Invalid ship collection"; return false
	var ids = []
	for setup in setups:
		var normalized = _normalize(setup)
		if normalized.is_empty(): return false
		if initial.has("oceanWaves") and not is_finite(next_ocean.heave_excursion + normalized.dimensions.draft * 2): last_error = "Ship heave travel limit must be finite"; return false
		if setup.id in ids: last_error = "Duplicate ship identity"; return false
		ids.append(setup.id)
	if not next_player in ids: last_error = "Encounter requires player ship"; return false
	var next_policy = {"controllableShipIds": initial.get("controllableShipIds", [] if initial.get("mode") == "continuous" else setups.filter(func(s): return s.team == "player").map(func(s): return s.id)), "hostileTargets": initial.get("hostileTargets", {})}
	if not _valid_policy(next_policy, ids): return false
	if initial.has("fireEnvironment") and not _valid_fire_environment(initial.fireEnvironment, ids): last_error = "Invalid fire environment"; return false
	var next_environment := Weather.new()
	# Unit/cadence/clone scale are target adapters, distinct from ship physics.
	var weather_options: Dictionary = {"model_scale":10.0}
	weather_options.merge(initial.get("environmentOptions",{}),true)
	weather_options.merge({"epoch":epoch+1,"route":initial.get("environmentRoute","sailing" if initial.get("mode")=="continuous" else "battle"),"crt_seed":posmod(int(fmod(float(initial.get("seed",1661)),4294967296.0)),4294967296)},true)
	if not next_environment.configure(weather_options): last_error = "Invalid environment options"; return false
	var prepared_ships = []
	var environment = initial.duplicate(true)
	environment.wind = next_wind
	for setup in setups:
		var prepared = _create_ship(setup, environment, next_ocean, 0)
		if prepared.is_empty(): return false
		prepared_ships.append(prepared)
	config = initial.duplicate(true); player_id = next_player; wind = next_wind.duplicate(true); ocean = next_ocean
	tick = 0; accumulator = 0.0; events = []; projectiles = []; projectile_damage.clear(); volleys = []; surrender = {}
	policy = next_policy.duplicate(true); orders.clear(); decisions.clear(); episode = 0; episode_open = false; episode_threats = []
	epoch += 1; battle_id = initial.get("battleId", "encounter-" + str(initial.get("seed", 1661)) + "-" + str(epoch))
	ships = prepared_ships
	_environment = next_environment
	status = "active" if ships.any(func(s): return s.state.team == "hostile") else "sailing"
	if _continuous(): _finish()
	last_error = ""
	return true
func _normalize(setup: Variant) -> Dictionary:
	if not setup is Dictionary or not setup.get("id") is String or setup.id.is_empty() or not setup.get("kind") is String or Types.ship_spec(setup.kind).is_empty() or not setup.get("team") in ["player", "hostile", "neutral"]: last_error = "Invalid ship identity"; return {}
	if setup.has("stats") and not setup.stats is Dictionary: last_error = "Invalid ship stats"; return {}
	for key in ["heading", "speed", "hull", "sail", "crew", "sailDeployment", "rudder", "sailAngle"]:
		if setup.has(key) and not _finite(setup[key]): last_error = "Invalid ship numeric field"; return {}
	if setup.has("autoTrim") and not setup.autoTrim is bool: last_error = "Invalid restored trim"; return {}
	if setup.has("ammoType") and not Cannon.BALLISTICS.has(setup.ammoType): last_error = "Invalid restored ammunition"; return {}
	var spec = Types.ship_spec(setup.kind)
	var input: Dictionary = setup.get("stats", {})
	for key in ["hullMultiplier", "cannonMultiplier", "steeringMultiplier", "speedMultiplier", "maxHull", "maxCrew", "reloadMultiplier", "draftMeters"]:
		if input.has(key) and not _finite(input[key]): last_error = "Invalid ship stats"; return {}
	var stats = {"hullMultiplier": 1.0, "cannonMultiplier": 1.0, "steeringMultiplier": 1.0, "speedMultiplier": 1.0, "maxHull": 100.0 * input.get("hullMultiplier", 1.0), "maxCrew": spec.crew, "reloadMultiplier": 1.0, "cargoMass": 0.0, "draftMeters": spec.draft}
	for key in stats:
		if input.has(key): stats[key] = input[key]
	for key in ["hullMultiplier", "cannonMultiplier", "steeringMultiplier", "speedMultiplier", "maxHull", "maxCrew", "reloadMultiplier", "draftMeters"]:
		var maximum = {"hullMultiplier": 100, "cannonMultiplier": 10, "steeringMultiplier": 2, "speedMultiplier": 2, "maxHull": 10000, "maxCrew": 1000, "reloadMultiplier": 10}.get(key, INF)
		if not _finite(stats[key]) or stats[key] <= 0 or stats[key] > maximum or (key == "steeringMultiplier" and stats[key] < 0.001): last_error = "Invalid ship stats"; return {}
	if not is_finite(spec.width * stats.draftMeters) or not is_finite(stats.draftMeters * 2): last_error = "Invalid ship draft"; return {}
	if not _finite(stats.cargoMass) or stats.maxCrew != floor(stats.maxCrew) or stats.cargoMass < 0 or stats.cargoMass > spec.mass: last_error = "Invalid ship capacity"; return {}
	if not Types.valid_draft(stats.draftMeters, spec.width, spec.mass + stats.cargoMass, 2.5, 0.8): last_error = "Draft must be at least 0.05m with finite immersed area, buoyancy stiffness and damping"; return {}
	if not setup.get("position") is Dictionary or not [setup.position.get("x"), setup.position.get("z")].all(_finite): last_error = "Invalid ship initial state"; return {}
	var ammo = {"solid": 40, "chain": 20, "grape": 20}
	if setup.has("ammo"):
		if not setup.ammo is Dictionary: last_error = "Invalid initial ammunition"; return {}
		ammo.merge(setup.ammo, true)
	var state = {"id": setup.id, "name": setup.get("name", setup.id), "kind": setup.kind, "team": setup.team,
		"hull": clampf(setup.get("hull", stats.maxHull), 0, stats.maxHull), "maxHull": stats.maxHull, "sail": clampf(setup.get("sail", 100), 0, 100), "maxSail": 100,
		"crew": clampf(setup.get("crew", stats.maxCrew), 0, stats.maxCrew), "maxCrew": stats.maxCrew, "sailDeployment": setup.get("sailDeployment", 1),
		"ammoType": setup.get("ammoType", "solid"), "ammo": ammo, "dimensions": {"length": spec.length, "width": spec.width, "draft": stats.draftMeters},
		"rudder": setup.get("rudder", 0), "sailAngle": setup.get("sailAngle", 0), "autoTrim": setup.get("autoTrim", true), "cannonsPerSide": spec.guns, "stats": stats, "controlsSequence": 0}
	if absf(state.rudder) > 1 or absf(state.sailAngle) > PI / 2 or state.sailDeployment < 0 or state.sailDeployment > 1: last_error = "Invalid restored controls"; return {}
	if not ammo.values().all(func(v): return _finite(v) and v >= 0 and v == floor(v)): last_error = "Invalid initial ammunition"; return {}
	if setup.has("cooldownSeconds") and (not setup.cooldownSeconds is Dictionary or not [setup.cooldownSeconds.get("port"), setup.cooldownSeconds.get("starboard")].all(func(v): return _finite(v) and v >= 0 and v <= 120)): last_error = "Invalid restored reload"; return {}
	if setup.has("fireControl"):
		if not Fire.valid(setup.fireControl): last_error = "Invalid fire control state"; return {}
		state.fireControl = setup.fireControl.duplicate(true)
	if setup.has("fireLauncher"):
		if not FireLauncher.valid(setup.fireLauncher): last_error = "Invalid fire launcher state"; return {}
		state.fireLauncher = setup.fireLauncher.duplicate(true)
	return state
func _create_ship(setup: Dictionary, environment: Dictionary = config, wave_field: RefCounted = ocean, accepted_tick: int = tick) -> Dictionary:
	var state = _normalize(setup)
	var core = Physics.new()
	var body = {"kind": setup.kind, "position": setup.position, "heading": setup.get("heading", 0), "speed": setup.get("speed", 0), "draft": state.dimensions.draft, "cargoMass": state.stats.cargoMass, "wind": environment.get("wind", wind), "sailDeployment": state.sailDeployment, "sailCondition": state.sail / state.maxSail, "sailPowerScale": pow(state.stats.speedMultiplier, 2), "time": accepted_tick * DT, "config": {}}
	# Old detached source fixtures retain their frozen buoyancy. Every formal
	# game runtime injects the shared coastal wave sampler.
	body.config.waterRelativeBuoyancy = environment.has("waveSampler")
	if environment.has("oceanWaves"): body.config.heaveTravelLimit = wave_field.heave_excursion + state.dimensions.draft * 2
	else: body.baseY = wave_field.sample(setup.position.x, setup.position.z, accepted_tick * DT).height; body.config.heaveTravelLimit = state.dimensions.draft * 2
	if not core.configure(body, environment.get("sampleTerrainHeight", Callable()), wave_field): last_error = "Invalid ship physics configuration"; return {}
	var base_rudder = core.get_config().rudderAreaFactor
	if not core.set_config({"rudderAreaFactor": base_rudder * state.stats.steeringMultiplier}): last_error = "Invalid ship physics configuration"; return {}
	var ship: Dictionary = {"state": state, "core": core, "baseRudderAreaFactor": base_rudder, "reload": {"port": accepted_tick + int(ceil(setup.get("cooldownSeconds", {}).get("port", 0) * 60)), "starboard": accepted_tick + int(ceil(setup.get("cooldownSeconds", {}).get("starboard", 0) * 60))}, "previous": _visual_core(core), "sunk": state.hull <= 0, "statsInput": setup.get("stats", {}).duplicate(true), "lowSpeedTurn": false, "sailRecovery": 1.0}
	if state.has("fireLauncher"):
		ship.launcherTicks = {"ready":accepted_tick + _remaining_ticks(state.fireLauncher.cooldownSeconds), "busy":accepted_tick + _remaining_ticks(state.fireLauncher.operationSeconds)}
	_clip_fire_team(ship, accepted_tick)
	return ship
func _visual_core(core: RefCounted) -> Dictionary:
	var p = core.get_snapshot()
	return {"position": p.position, "heading": p.heading, "velocity": p.velocity, "heel": p.heel, "pitch": p.pitch}
func _visual(ship: Dictionary) -> Dictionary: return _visual_core(ship.core)
func _ship(id: Variant) -> Dictionary:
	if not id is String: return {}
	for ship in ships:
		if ship.state.id == id: return ship
	return {}
func _valid_fire_environment(value: Variant, ids: Array) -> bool:
	if not value is Dictionary or value.size() != 2 or not value.has_all(["rain01", "flammableLoadByShip"]): return false
	var rain: Variant = value.rain01
	var loads: Variant = value.flammableLoadByShip
	if not _finite(rain) or rain < 0.0 or rain > 1.0 or not loads is Dictionary: return false
	for id in loads:
		if not id is String or not id in ids or not _finite(loads[id]) or loads[id] < 0.0 or loads[id] > 1.0: return false
	return true
func _remaining_ticks(seconds: float) -> int:
	# Snapshot seconds are multiples of DT; avoid a new tick from roundoff at restore.
	return maxi(0, int(ceil(seconds * 60.0 - 0.000000001)))
func _launcher_snapshot(ship: Dictionary, accepted_tick: int = tick) -> Dictionary:
	var result: Dictionary = ship.state.fireLauncher.duplicate(true)
	result.cooldownSeconds = maxi(0, int(ship.launcherTicks.ready) - accepted_tick) * DT
	result.operationSeconds = maxi(0, int(ship.launcherTicks.busy) - accepted_tick) * DT
	return result
func _launcher_operators(ship: Dictionary, accepted_tick: int = tick) -> int:
	if not ship.state.has("fireLauncher"): return 0
	return FireLauncher.operators(_launcher_snapshot(ship, accepted_tick), maxi(0, int(floor(ship.state.crew))))
func _has_fire_extension(ship: Dictionary) -> bool:
	return ship.state.has("fireControl") or ship.state.has("fireLauncher")
func _available_crew(ship: Dictionary) -> float:
	# Untouched source encounters retain fractional crew and exact frozen arithmetic.
	if not _has_fire_extension(ship): return ship.state.crew
	var able: int = maxi(0, int(floor(ship.state.crew)))
	var budget: int = maxi(0, able - _launcher_operators(ship))
	return float(budget - Fire.reserved_crew(ship.state.fireControl, budget)) if ship.state.has("fireControl") else float(budget)
func _clip_fire_team(ship: Dictionary, accepted_tick: int = tick) -> void:
	if not ship.state.has("fireControl"): return
	var able: int = maxi(0, int(floor(ship.state.crew)))
	var budget: int = maxi(0, able - _launcher_operators(ship, accepted_tick))
	ship.state.fireControl.assignedFirefighters = mini(int(ship.state.fireControl.assignedFirefighters), budget)
	ship.state.fireControl.pendingFirefighters = mini(int(ship.state.fireControl.pendingFirefighters), budget)
func _assign_fire_control(ship: Dictionary, input: Dictionary) -> Dictionary:
	if ship.state.controlsSequence >= SAFE_INTEGER: return _no("Control sequence exhausted")
	var able: int = maxi(0, int(floor(ship.state.crew)))
	var budget: int = maxi(0, able - _launcher_operators(ship))
	var current: Dictionary = ship.state.get("fireControl", Fire.initial())
	var assigned: Dictionary = Fire.assign(current, input.get("crew"), budget)
	if not assigned.ok: return _no(assigned.reason)
	ship.state.fireControl = assigned.state
	ship.state.controlsSequence += 1
	return _ok()
func preview_fire_launch(ship_id: String, target_id: String, payload: String) -> Dictionary:
	var ship: Dictionary = _ship(ship_id)
	if ship.is_empty() or not _controlled(ship_id): return _no("Ship not authorized")
	if ship.sunk or status in ["victory", "defeat", "surrendered"]: return _no("Encounter ended")
	if ship_id in policy.get("disabledMotionShipIds", []): return _no("motion-disabled")
	if _continuous() and ship_id in policy.get("lockedShipIds", []): return _no("Ship working")
	var quote: Dictionary = _fire_launch_quote(ship, {"payload":payload, "targetId":target_id})
	return _ok() if quote.ok else quote
func _fire_launch_quote(ship: Dictionary, input: Dictionary) -> Dictionary:
	var state: Dictionary = ship.state
	if not state.has("fireLauncher"): return _no("No fire launcher")
	if not input.get("payload") in FireLauncher.PAYLOADS: return _no("Invalid fire payload")
	var intent: Dictionary = _active_order(state.id).get("intent", {})
	if intent.get("kind") in ["prepare-boarding", "rally"]: return _no("order-fire-suppressed")
	var target: Dictionary = _ship(input.get("targetId"))
	if target.is_empty() or target.sunk or not _enemy(ship, target): return _no("target-unavailable")
	if _available_crew(ship) < FireLauncher.OPERATOR_COUNT: return _no("Insufficient fire launcher crew")
	if ship.launcherTicks.ready > tick: return _no("Fire launcher reloading")
	if state.fireLauncher.ammo[input.payload] <= 0: return _no("Out of fire payloads")
	if state.controlsSequence >= SAFE_INTEGER: return _no("Control sequence exhausted")
	var solution: Dictionary = FireLauncher.launch_solution(_gunnery_state(ship), _gunnery_state(target))
	if not solution.ok: return _no(solution.reason)
	if not Cannon.corridor_clear(solution, _gunnery_protected(ship)): return _no("friendly-fire-blocked")
	return {"ok":true, "solution":solution, "targetId":target.state.id}
func _launch_fire_payload(ship: Dictionary, input: Dictionary) -> Dictionary:
	var quote: Dictionary = _fire_launch_quote(ship, input)
	if not quote.ok: return quote
	var solution: Dictionary = quote.solution
	var state: Dictionary = ship.state
	# Every rejection above leaves stock, ordinary reload and pending shots untouched.
	state.controlsSequence += 1
	state.fireLauncher.ammo[input.payload] -= 1
	ship.launcherTicks.ready = tick + _remaining_ticks(FireLauncher.COOLDOWN_SECONDS)
	ship.launcherTicks.busy = tick + _remaining_ticks(FireLauncher.OPERATION_SECONDS)
	sequence += 1
	var projectile: Dictionary = {"id":"shot-" + str(sequence), "shipId":state.id, "kind":"fire-payload", "payload":input.payload,
		"position":solution.position.duplicate(true), "velocity":solution.velocities[0].duplicate(true), "age":0.0, "ttl":solution.ttl}
	projectiles.append(projectile)
	_emit({"type":"fire-payload-launched", "shipId":state.id, "targetId":quote.targetId, "payload":input.payload,
		"projectileId":projectile.id, "position":projectile.position.duplicate(true), "velocity":projectile.velocity.duplicate(true)})
	return _ok()
func _apply_damage(ship: Dictionary, damage: Dictionary) -> void:
	# Callers retain event ordering and then use the original single sink transition.
	for key in ["hull", "sail", "crew"]:
		var next: float = maxf(0.0, ship.state[key] - damage[key])
		ship.state[key] = 0 if next < 1e-8 else next
	_clip_fire_team(ship)
func _advance_fire() -> void:
	var environment: Dictionary = config.get("fireEnvironment", {})
	var rain: float = environment.get("rain01", 0.0)
	var loads: Dictionary = environment.get("flammableLoadByShip", {})
	for ship in ships:
		if ship.sunk or not ship.state.has("fireControl"): continue
		_clip_fire_team(ship)
		# able is total living people, not available workers: operators can also die.
		var context: Dictionary = {"able":maxi(0, int(floor(ship.state.crew))), "maxHull":ship.state.maxHull,
			"maxSail":ship.state.maxSail, "maxCrew":int(ship.state.maxCrew), "rain01":rain,
			"flammableLoad":loads.get(ship.state.id, 0.0)}
		var result: Dictionary = Fire.step(ship.state.fireControl, context)
		assert(result.ok, "Validated native fire state must step")
		ship.state.fireControl = result.state
		_apply_damage(ship, result.damage)
		if ship.state.hull <= 0.0: _sink(ship)
func _continuous() -> bool: return config.get("mode") == "continuous"
func _finite(v: Variant) -> bool: return Types.finite_number(v)
func _wrap(v: float) -> float: return atan2(sin(v), cos(v))
func _compare_ids(a: String, b: String) -> int:
	var supplied: Callable = config.get("idComparer", Callable())
	return int(supplied.call(a, b)) if supplied.is_valid() else _id_collator.compare(a, b)
func _stable_sort(values: Array, less: Callable) -> void:
	for index in range(1, values.size()):
		var candidate = values[index]
		var slot = index
		while slot > 0 and less.call(candidate, values[slot - 1]): values[slot] = values[slot - 1]; slot -= 1
		values[slot] = candidate
func _distance(a: Dictionary, b: Dictionary) -> float: return sqrt(pow(a.x - b.x, 2) + pow(a.z - b.z, 2))
func _speed(v: Dictionary) -> float: return sqrt(v.velocity.x * v.velocity.x + v.velocity.z * v.velocity.z)
func _height(x: float, z: float) -> float: return ocean.sample_height(x, z, tick * DT)
func _ok() -> Dictionary: return {"ok": true}
func _no(reason: String) -> Dictionary: return {"ok": false, "reason": reason}
func _controlled(id: String) -> bool:
	return not id in policy.get("disabledMotionShipIds", []) and (not _continuous() or (id in policy.get("controllableShipIds", []) and not id in policy.get("lockedShipIds", []) and _ship(id).get("state", {}).get("team") != "hostile"))
func _enemy(a: Dictionary, b: Dictionary) -> bool:
	if a.state.id == b.state.id: return false
	if _continuous():
		if a.state.id in policy.get("capturedShipIds", []) or b.state.id in policy.get("capturedShipIds", []): return false
		if policy.get("hostileTargets", {}).has(a.state.id): return b.state.id in policy.hostileTargets[a.state.id]
	return a.state.team != "neutral" and b.state.team != "neutral" and a.state.team != b.state.team
func _valid_wind(value: Variant) -> bool:
	return value is Dictionary and value.get("direction") is Dictionary and [value.direction.get("x"), value.direction.get("y"), value.get("speed")].all(_finite) and value.speed >= 0 and value.speed <= 100
func _valid_list(value: Variant, ids: Array) -> bool:
	if not value is Array: return false
	var seen = []
	for id in value:
		if not id is String or not id in ids or id in seen: return false
		seen.append(id)
	return true
func _valid_policy(value: Variant, ids: Array) -> bool:
	last_error = "Invalid command policy"
	if not value is Dictionary or not _valid_list(value.get("controllableShipIds"), ids) or not value.get("hostileTargets") is Dictionary: return false
	for field in ["capturedShipIds", "disabledMotionShipIds", "anchorShipIds", "lockedShipIds"]:
		if value.has(field) and not _valid_list(value[field], ids): last_error = "Invalid disabled motion identities" if field == "disabledMotionShipIds" else "Invalid service identities" if field in ["anchorShipIds", "lockedShipIds"] else "Invalid command policy"; return false
	for field in ["anchorShipIds", "lockedShipIds"]:
		if value.get(field, []).any(func(id): return not id in value.controllableShipIds): last_error = "Invalid service identities"; return false
	for attacker in value.hostileTargets:
		if not attacker in ids or not _valid_list(value.hostileTargets[attacker], ids) or attacker in value.hostileTargets[attacker]: last_error = "Invalid hostile relation"; return false
	if value.has("navigation"):
		if not value.navigation is Dictionary: last_error = "Invalid route navigation"; return false
		for id in value.navigation:
			var point = value.navigation[id]
			if not id in ids or (point != null and (not point is Dictionary or not [point.get("x"), point.get("z")].all(_finite))): last_error = "Invalid route navigation"; return false
	return true
func snapshot() -> Dictionary:
	var states = []
	for ship in ships:
		var state = ship.state.duplicate(true)
		state.visual = _visual(ship)
		state.cooldownSeconds = {"port": maxf(0, ship.reload.port - tick) * DT, "starboard": maxf(0, ship.reload.starboard - tick) * DT}
		if _has_fire_extension(ship): state.availableCrew = int(_available_crew(ship))
		if state.has("fireLauncher"): state.fireLauncher = _launcher_snapshot(ship)
		states.append(state)
	var result = {"time": tick * DT, "tick": tick, "status": status, "playerId": player_id, "battleId": battle_id, "wind": wind.duplicate(true), "oceanWaves": ocean.waves.duplicate(true), "ships": states, "projectiles": projectiles.duplicate(true)}
	if _environment: result.environment = _environment.snapshot()
	if not surrender.is_empty(): result.surrender = surrender.duplicate(true)
	return result
func drain_events() -> Array:
	var result = events; events = []; return result
func drainEvents() -> Array: return drain_events()
func _emit(data: Dictionary) -> void:
	sequence += 1; data.id = "event-" + str(sequence); data.time = tick * DT; events.append(data)
func _active_order(id: String) -> Dictionary:
	for record in orders.values():
		if record.status.state == "active" and id in record.participants: return record.order
	return {}
func hasActiveOrder(id: String) -> bool: return not _active_order(id).is_empty()
func has_active_order(id: String) -> bool: return hasActiveOrder(id)
func order_status() -> Array: return orders.values().map(func(r): return r.status.duplicate(true))
func orderStatus() -> Array: return order_status()
func navigation_status(id: String) -> Variant:
	if id in policy.get("disabledMotionShipIds", []): return {"points": [], "reason": "motion-disabled"}
	var ship = _ship(id)
	if ship.is_empty() or not ship.has("route"): return null
	var result = {"points": ship.route.points.duplicate(true)}
	if ship.route.has("reason"): result.reason = ship.route.reason
	return result
func navigationStatus(id: String) -> Variant: return navigation_status(id)
func _cancel_order(id: String, reason: String) -> void:
	for record in orders.values():
		if record.status.state == "active" and id in record.participants:
			record.participants.erase(id)
			if record.participants.is_empty(): record.status = {"id": record.order.id, "state": "blocked", "reason": reason}
			else: record.status.reason = reason
			var ship = _ship(id)
			if not ship.is_empty(): ship.state.erase("navigation"); ship.erase("tack")
	decisions.erase(id)
	var stop_ship=_ship(id)
	if not stop_ship.is_empty():_clear_terminal_stop(stop_ship)
func _disable_motion(ship: Dictionary) -> void:
	_cancel_order(ship.state.id, "motion-disabled")
	ship.state.erase("navigation"); ship.erase("tack"); ship.erase("manualHandling"); ship.erase("route")
	ship.state.rudder = 0; ship.state.sailDeployment = 0; ship.sailRecovery = 0; ship.lowSpeedTurn = false
	volleys = volleys.filter(func(v): return v.shipId != ship.state.id)
func _safe_point(ship: Dictionary, point: Dictionary) -> bool:
	if not config.get("sampleTerrainHeight", Callable()).is_valid(): return true
	var p = _visual(ship).position
	return _wet_hull(ship, point.x, point.z, atan2(point.z - p.z, point.x - p.x))
func _wet_hull(ship: Dictionary, x: float, z: float, heading: float) -> bool:
	var sampler: Callable = config.get("sampleTerrainHeight", Callable())
	if not sampler.is_valid(): return true
	var c = cos(heading); var s = sin(heading); var dims = ship.state.dimensions
	for f in [-0.5, 0, 0.5]:
		for side in [-0.5, 0, 0.5]:
			var h = sampler.call(x + c * dims.length * f - s * dims.width * side, z + s * dims.length * f + c * dims.width * side)
			if not _finite(h) or h >= config.get("seaLevel", 0) - dims.draft: return false
	return true
func issue_order(input: Variant) -> Dictionary:
	if not _continuous() or status in ["surrendered", "defeat"]: return _no("Tactical orders unavailable")
	if not Orders.valid_order(input): return _no("Invalid order")
	var order = input.duplicate(true)
	if orders.has(order.id): return _ok() if orders[order.id].order == order else _no("order-id-conflict")
	if orders.size() >= 4096: return _no("Order buffer full")
	var fleet = order.shipIds.map(_ship)
	if fleet.any(func(s): return s.is_empty() or s.sunk or s.state.crew <= 0 or not _controlled(s.state.id)): return _no("Ship not authorized or operational")
	var target = _ship(order.intent.get("targetId", ""))
	if order.intent.has("targetId") and (target.is_empty() or target.sunk or target.state.id in policy.get("capturedShipIds", []) or target.state.id in order.shipIds): return _no("Target unavailable")
	if not target.is_empty() and order.intent.kind != "protect" and fleet.any(func(s): return not _enemy(s, target)): return _no("Target is not hostile")
	if not target.is_empty() and order.intent.kind == "protect" and fleet.any(func(s): return _enemy(s, target)): return _no("Cannot protect hostile target")
	var point = order.intent.point if order.intent.kind == "rally" else _visual(target).position
	if fleet.any(func(s): return not _safe_point(s, point)): return _no("unsafe-depth")
	for ship in fleet: _cancel_order(ship.state.id, "superseded"); ship.erase("manualHandling")
	if order.intent.kind in ["prepare-boarding", "rally"]: volleys = volleys.filter(func(v): return not v.shipId in order.shipIds)
	orders[order.id] = {"order": order, "participants": order.shipIds.duplicate(), "status": {"id": order.id, "state": "active"}}
	return _ok()
func issueOrder(input: Variant) -> Dictionary: return issue_order(input)
func navigate(id: String, waypoint: Variant) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	var ship = _ship(id)
	if ship.is_empty() or ship.sunk: return _no("Unknown or sunk ship")
	if not _controlled(id): return _no("Ship not authorized")
	if waypoint != null and (not waypoint is Dictionary or not [waypoint.get("x"), waypoint.get("z")].all(_finite)): return _no("Invalid waypoint")
	ship.erase("manualHandling"); _cancel_order(id, "manual-navigation" if waypoint != null else "manual-control"); ship.erase("route")
	ship.erase("approachRecovery"); ship.erase("approachManualOverride"); ship.erase("egressRevokedGoal")
	if ship.has("wetRouteEgress"):
		ship.erase("wetRouteEgress"); ship.state.rudder=0; ship.state.sailDeployment=0; ship.sailRecovery=0
	ship.erase("egressRetryAt")
	if waypoint != null:
		if ship.state.has("navigation") and _distance(waypoint, ship.state.navigation) > ship.state.dimensions.length: ship.erase("tack")
		ship.state.navigation = {"x": waypoint.x, "z": waypoint.z}
	else: ship.state.erase("navigation"); ship.erase("tack")
	return _ok()
func command(input: Variant) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	if not input is Dictionary: return _no("Invalid command")
	if input.get("type") == "surrender":
		var request = input.get("request")
		if not request is Dictionary or not request.get("battleId") is String or not _finite(request.get("tick")) or request.tick != floor(request.tick) or not request.get("captorId") is String or request.captorId.is_empty(): return _no("Invalid surrender request")
		if request.battleId != battle_id or request.tick != tick: return _no("Surrender request is stale")
		var preview = preview_surrender(request.captorId)
		if not preview.ok: return _no(preview.reason)
		surrender = preview.offer.request.duplicate(true)
		for ship in ships: ship.erase("manualHandling"); _clear_terminal_stop(ship)
		status = "surrendered"; accumulator = 0; volleys = []; projectiles = []; projectile_damage.clear()
		_emit({"type": "surrender", "shipId": player_id, "captorId": request.captorId, "battleId": battle_id})
		return _ok()
	var id = input.get("shipId", player_id)
	if not id is String: return _no("Invalid ship identity")
	if not _controlled(id): return _no("Ship not authorized")
	var ship = _ship(id)
	var changed = input.get("type") == "controls" and not ship.is_empty() and (input.get("rudder") != ship.state.rudder or input.get("sailDeployment") != ship.state.sailDeployment or input.has("sailAngle") and input.sailAngle != ship.state.sailAngle or input.has("autoTrim") and input.autoTrim != ship.state.autoTrim)
	var result = _ship_command(input)
	if result.ok and changed: _cancel_order(id, "manual-control")
	return result
func _ship_command(input: Dictionary) -> Dictionary:
	var id = input.get("shipId", player_id)
	if not id is String or id.is_empty(): return _no("Invalid ship identity")
	var ship = _ship(id)
	if ship.is_empty(): return _no("Unknown ship")
	if id in policy.get("disabledMotionShipIds", []): return _no("motion-disabled")
	if _continuous() and id in policy.get("lockedShipIds", []): return _no("Ship working")
	if ship.sunk or ship.state.hull <= 0: return _no("Ship sunk")
	if status in ["defeat", "victory"]: return _no("Encounter ended")
	var state = ship.state
	if input.get("type") == "fire-control": return _assign_fire_control(ship, input)
	if input.get("type") == "launch-fire": return _launch_fire_payload(ship, input)
	if input.get("type") == "controls":
		if not [input.get("rudder"), input.get("sailDeployment")].all(_finite) or absf(input.rudder) > 1 or input.sailDeployment < 0 or input.sailDeployment > 1 or input.has("sailAngle") and (not _finite(input.sailAngle) or absf(input.sailAngle) > PI / 2) or input.has("autoTrim") and not input.autoTrim is bool: return _no("Invalid controls")
		if state.controlsSequence >= SAFE_INTEGER: return _no("Control sequence exhausted")
		var changed = input.rudder != state.rudder or input.sailDeployment != state.sailDeployment or input.has("sailAngle") and input.sailAngle != state.sailAngle or input.has("autoTrim") and input.autoTrim != state.autoTrim
		if changed:_clear_terminal_stop(ship)
		if changed and state.has("navigation"):
			if ship.has("wetRouteEgress"):ship.egressRevokedGoal=state.navigation.duplicate(true)
			ship.erase("approachRecovery"); ship.erase("wetRouteEgress"); ship.approachManualOverride = state.navigation.duplicate(true)
		ship.erase("manualHandling"); state.controlsSequence += 1; state.rudder = input.rudder; state.sailDeployment = input.sailDeployment
		if input.has("sailAngle"): state.sailAngle = input.sailAngle
		if input.has("autoTrim"): state.autoTrim = input.autoTrim
		return _ok()
	if input.get("type") == "select-ammo":
		if not Cannon.BALLISTICS.has(input.get("ammo", "")): return _no("Invalid ammunition")
		if state.controlsSequence >= SAFE_INTEGER: return _no("Control sequence exhausted")
		state.controlsSequence += 1; state.ammoType = input.ammo; return _ok()
	if input.get("type") != "fire" or not input.get("side") in ["port", "starboard"]: return _no("Invalid command")
	var intent = _active_order(id).get("intent", {})
	if intent.get("kind") in ["prepare-boarding", "rally"]: return _no("order-fire-suppressed")
	if not intent.is_empty() and intent.kind != "protect" and intent.has("targetId"):
		var target = _ship(intent.targetId)
		if target.is_empty() or target.sunk or not _enemy(ship, target): return _no("target-unavailable")
	if state.cannonsPerSide == 0: return _no("No cannons")
	if _has_fire_extension(ship) and _available_crew(ship) <= 0.0: return _no("Ship not operational")
	if ship.reload[input.side] > tick: return _no("Reloading")
	if state.ammo[state.ammoType] <= 0: return _no("Out of ammunition")
	if state.controlsSequence >= SAFE_INTEGER: return _no("Control sequence exhausted")
	if config.get("referenceGunnery", false):
		if state.crew <= 0: return _no("Ship not operational")
		for cannon in state.cannonsPerSide:
			if not _reference_corridor_clear(ship, input.side, state.ammoType, cannon): return _no("friendly-fire-blocked")
	state.controlsSequence += 1; state.ammo[state.ammoType] -= 1
	var crew_factor = 1.0 + (1.0 - _available_crew(ship) / state.maxCrew) * 1.5
	var reload_seconds: float = Cannon.reload_seconds(_gunnery_state(ship)) if config.get("referenceGunnery", false) else 7.0 * crew_factor * state.stats.reloadMultiplier
	ship.reload[input.side] = tick + int(ceil(reload_seconds * 60.0))
	var aim = _target(ship, input.side, state.ammoType) if _continuous() else {}
	var aim_id = aim.get("state", {}).get("id", "")
	var target_id = intent.targetId if not intent.is_empty() and intent.kind != "protect" and intent.has("targetId") else aim_id
	_launch(ship, input.side, state.ammoType, 0, aim_id)
	var interval: int = Cannon.salvo_interval_ticks(_gunnery_state(ship)) if config.get("referenceGunnery", false) else 5
	for cannon in range(1, state.cannonsPerSide):
		var volley = {"shipId": id, "side": input.side, "ammo": state.ammoType, "due": tick + cannon * interval, "cannon": cannon}
		if not target_id.is_empty(): volley.targetId = target_id
		volleys.append(volley)
	return _ok()
func preview_surrender(captor_id: Variant = null) -> Dictionary:
	if status != "active": return _no("Surrender requires an active encounter")
	var player = _ship(player_id)
	if player.is_empty() or player.state.team != "player" or player.sunk or player.state.hull <= 0: return _no("Flagship must be alive and player-owned")
	if captor_id != null and (not captor_id is String or captor_id.is_empty()): return _no("Invalid captor identity")
	var p = _visual(player).position
	var captors = ships.filter(func(s): return s.state.team == "hostile" and not s.sunk and s.state.hull > 0)
	captors.sort_custom(func(a, b): return _distance(_visual(a).position, p) < _distance(_visual(b).position, p) if _distance(_visual(a).position, p) != _distance(_visual(b).position, p) else a.state.id < b.state.id)
	var captor = captors[0] if captor_id == null and not captors.is_empty() else _ship(captor_id) if captor_id is String else {}
	if captor.is_empty() or not captor in captors: return _no("Captor must be a live hostile ship")
	return {"ok": true, "offer": {"request": {"battleId": battle_id, "tick": tick, "captorId": captor.state.id}, "captorName": captor.state.name}}
func previewSurrender(captor_id: Variant = null) -> Dictionary: return preview_surrender(captor_id)
func step_fixed() -> void:
	# The caller has already budgeted one 60Hz tick. No second wall-time
	# accumulator or catch-up policy belongs inside this authority operation.
	if status == "surrendered":
		for ship in ships:_clear_terminal_stop(ship)
		return
	_fixed_tick()
func step(seconds: float) -> void:
	if not is_finite(seconds) or seconds <= 0: return
	if status == "surrendered":
		for ship in ships:_clear_terminal_stop(ship)
		return
	accumulator += minf(seconds, 0.1)
	var count = 0
	while accumulator + 1e-10 >= DT and count < 6:
		accumulator = maxf(0, accumulator - DT); step_fixed(); count += 1
	if count == 6 and accumulator >= DT: accumulator = fmod(accumulator, DT)
func _target(ship: Dictionary, side: String, ammo: String, constrained: String = "") -> Dictionary:
	var v = _visual(ship)
	var bearing = v.heading + (PI / 2 if side == "starboard" else -PI / 2)
	var intent = _active_order(ship.state.id).get("intent", {})
	var preferred = constrained
	if preferred.is_empty(): preferred = decisions.get(ship.state.id, {}).get("preferredTargetId", intent.get("targetId", "") if intent.get("kind") != "protect" else "")
	var candidates = []
	for target in ships:
		if target.sunk or not _enemy(ship, target) or not preferred.is_empty() and target.state.id != preferred: continue
		var p = _visual(target).position
		if _distance(p, v.position) <= Cannon.BALLISTICS[ammo].range and absf(_wrap(atan2(p.z - v.position.z, p.x - v.position.x) - bearing)) <= Cannon.ARC: candidates.append(target)
	_stable_sort(candidates, func(a, b): return _distance(_visual(a).position, v.position) < _distance(_visual(b).position, v.position) if _distance(_visual(a).position, v.position) != _distance(_visual(b).position, v.position) else _compare_ids(a.state.id, b.state.id) < 0)
	return candidates[0] if not candidates.is_empty() else {}
func _gunnery_state(ship: Dictionary) -> Dictionary:
	var result: Dictionary = ship.state.duplicate()
	result.crew = _available_crew(ship)
	result.visual = _visual(ship)
	return result
func _gunnery_protected(ship: Dictionary) -> Array:
	return ships.filter(func(other): return other.state.id != ship.state.id and not other.sunk and not _enemy(ship, other)).map(_gunnery_state)
func _reference_corridor_clear(ship: Dictionary, side: String, ammo: String, cannon: int, locked: String = "") -> bool:
	var target: Dictionary = _target(ship, side, ammo, locked)
	var solution: Dictionary = Cannon.launch_solution(_gunnery_state(ship), side, ammo, cannon, _gunnery_state(target) if not target.is_empty() else {})
	return Cannon.corridor_clear(solution, _gunnery_protected(ship))
func _launch(ship: Dictionary, side: String, ammo: String, cannon: int, locked: String = "") -> void:
	if _has_fire_extension(ship) and _available_crew(ship) <= 0.0: return
	var v = _visual(ship); var spec = Types.ship_spec(ship.state.kind); var ballistic = Cannon.BALLISTICS[ammo]
	var position = Cannon.muzzle(v, spec, side, cannon)
	var base_bearing = v.heading + (1 if side == "starboard" else -1) * PI / 2.0
	var bearing = base_bearing; var elevation = ballistic.angle
	var target = _target(ship, side, ammo, locked)
	var reference_solution: Dictionary = {}
	if config.get("referenceGunnery", false):
		if ship.state.crew <= 0: return
		reference_solution = Cannon.launch_solution(_gunnery_state(ship), side, ammo, cannon, _gunnery_state(target) if not target.is_empty() else {})
		# Recheck each delayed gun against current authority. A friendly ship can
		# enter the lane after the trigger; suppressed guns never create a shot.
		if not Cannon.corridor_clear(reference_solution, _gunnery_protected(ship)): return
	if not target.is_empty():
		var state = _visual(target)
		var travel = _distance(state.position, position) / ballistic.speed
		var aim = {"x": state.position.x + state.velocity.x * travel, "z": state.position.z + state.velocity.z * travel}
		bearing = base_bearing + clampf(_wrap(atan2(aim.z - position.z, aim.x - position.x) - base_bearing), -Cannon.ARC, Cannon.ARC)
		var distance = maxf(1, _distance(aim, position))
		var aim_y = state.position.y + (11 if ammo == "chain" else Types.ship_spec(target.state.kind).freeboard + 0.5)
		var speed2 = ballistic.speed * ballistic.speed
		var discriminant = speed2 * speed2 - GRAVITY * (GRAVITY * distance * distance + 2 * (aim_y - position.y) * speed2)
		if discriminant >= 0: elevation = atan((speed2 - sqrt(discriminant)) / (GRAVITY * distance))
	var spread = [[0, 0], [-0.036, -0.018], [-0.018, 0.018], [0.018, 0.018], [0.036, -0.018]] if ammo == "grape" else [[0, 0]]
	var muzzle = {}
	for angles in spread:
		var horizontal = ballistic.speed * cos(elevation + angles[1])
		sequence += 1
		var p = {"id": "shot-" + str(sequence), "shipId": ship.state.id, "ammo": ammo, "position": position.duplicate(true), "velocity": {"x": cos(bearing + angles[0]) * horizontal, "y": ballistic.speed * sin(elevation + angles[1]), "z": sin(bearing + angles[0]) * horizontal}, "age": 0.0, "ttl": ballistic.ttl}
		if not reference_solution.is_empty(): p.velocity = reference_solution.velocities[spread.find(angles)].duplicate(true)
		projectiles.append(p)
		if muzzle.is_empty(): muzzle = p
		var scale = ship.state.stats.cannonMultiplier / spread.size()
		projectile_damage[p.id] = {"hull": ballistic.damage.hull * scale, "sail": ballistic.damage.sail * scale, "crew": ballistic.damage.crew * scale}
	_emit({"type": "fire", "shipId": ship.state.id, "side": side, "ammo": ammo, "projectileId": muzzle.id, "position": position.duplicate(true), "velocity": muzzle.velocity.duplicate(true)})
func _advance_projectiles() -> void:
	var keep = []
	for p in projectiles:
		var from = p.position.duplicate(true)
		var to = {"x": from.x + p.velocity.x * DT, "y": from.y + p.velocity.y * DT - GRAVITY * DT * DT / 2.0, "z": from.z + p.velocity.z * DT}
		var earliest = INF; var target = {}
		for ship in ships:
			if ship.sunk or ship.state.id == p.shipId: continue
			var spec = Types.ship_spec(ship.state.kind)
			for box in [{"length": spec.length, "width": spec.width, "bottom": -spec.draft, "top": spec.freeboard + 2}, {"length": spec.length * 0.75, "width": spec.width * 0.85, "bottom": spec.freeboard + 2, "top": spec.length * 0.65}]:
				var t = Sweep.sweep_moving_box(from, to, ship.previous, _visual(ship), box)
				if t != null and t < earliest: earliest = t; target = ship
		var before = from.y - _height(from.x, from.z); var after = to.y - _height(to.x, to.z)
		var water_t = (0.0 if before <= 0 else before / (before - after)) if after <= 0 else INF
		var is_payload: bool = p.get("kind") == "fire-payload"
		if not target.is_empty() and earliest <= water_t:
			var position = _lerp_position(from, to, earliest)
			if is_payload:
				var fire_state: Dictionary = target.state.get("fireControl", Fire.initial())
				var ignition: Dictionary = Fire.ignite(fire_state, p.payload, fire_state.wetness)
				assert(ignition.ok, "Validated payload must ignite a valid fire state")
				target.state.fireControl = ignition.state
				_clip_fire_team(target)
				_emit({"type":"fire-payload-hit", "shipId":p.shipId, "targetId":target.state.id, "payload":p.payload, "projectileId":p.id, "position":position})
			else:
				var damage = projectile_damage.get(p.id, Cannon.BALLISTICS[p.ammo].damage).duplicate(true)
				if p.ammo == "grape" and p.age * Cannon.BALLISTICS.grape.speed > Cannon.BALLISTICS.grape.range:
					for key in damage: damage[key] *= 0.15
				_apply_damage(target, damage)
				var shooter = _ship(p.shipId)
				if not _continuous() and not shooter.is_empty() and shooter.state.team == "player" and target.state.team == "neutral":
					target.state.team = "hostile"; target.state.erase("navigation"); target.erase("tack")
					if status != "defeat": status = "active"
				_emit({"type": "hit", "shipId": p.shipId, "targetId": target.state.id, "ammo": p.ammo, "projectileId": p.id, "position": position, "damage": damage})
			projectile_damage.erase(p.id)
			if target.state.hull <= 0: _sink(target)
		elif water_t != INF or p.age + DT >= p.ttl:
			var position = _lerp_position(from, to, 1.0 if water_t == INF else water_t)
			if is_payload:
				_emit({"type":"fire-payload-splash", "shipId":p.shipId, "payload":p.payload, "projectileId":p.id, "position":position})
			else:
				_emit({"type": "splash", "shipId": p.shipId, "ammo": p.ammo, "projectileId": p.id, "position": position})
			projectile_damage.erase(p.id)
		else:
			p.position = to; p.velocity.y -= GRAVITY * DT; p.age += DT; keep.append(p)
	projectiles = keep
func _lerp_position(a: Dictionary, b: Dictionary, t: float) -> Dictionary: return {"x": a.x + (b.x - a.x) * t, "y": a.y + (b.y - a.y) * t, "z": a.z + (b.z - a.z) * t}
func _sink(ship: Dictionary) -> void:
	if ship.sunk: return
	if ship.state.has("fireControl"):
		ship.state.fireControl.heat = 0.0; ship.state.fireControl.fuelSeconds = 0.0
		ship.state.fireControl.assignedFirefighters = 0; ship.state.fireControl.pendingFirefighters = 0; ship.state.fireControl.transferTicks = 0
	if ship.has("launcherTicks"): ship.launcherTicks.busy = tick
	ship.sunk = true; ship.state.sailDeployment = 0; volleys = volleys.filter(func(v): return v.shipId != ship.state.id)
	_emit({"type": "sink", "shipId": ship.state.id, "position": _visual(ship).position})
func _fixed_tick() -> void:
	tick += 1; ocean.accepted_time = tick * DT
	for ship in ships:
		if ship.state.id in policy.get("disabledMotionShipIds", []): _disable_motion(ship)
	if _continuous(): _tactical_tick()
	if status == "active":
		for ship in ships:
			if not ship.sunk and not hasActiveOrder(ship.state.id) and not ship.state.id in policy.get("lockedShipIds", []) and not ship.state.id in policy.get("disabledMotionShipIds", []):
				if (not _controlled(ship.state.id) and ships.any(func(t): return not t.sunk and _enemy(ship, t))) if _continuous() else ship.state.team == "hostile": _ai(ship)
	var player = _ship(player_id)
	var navigation_assists: Dictionary = {}
	for ship in ships:
		if ship.has("approachRecovery") and (not _approach_authorized(ship) or ship.approachRecovery.goal != ship.state.get("navigation")): ship.erase("approachRecovery")
		if ship.has("wetRouteEgress") and (not _egress_authorized(ship) or ship.wetRouteEgress.goal != ship.state.get("navigation") or ship.wetRouteEgress.draft != ship.state.dimensions.draft):
			ship.egressRevokedGoal=ship.state.get("navigation",{}).duplicate(true)
			ship.erase("wetRouteEgress"); ship.state.rudder=0; ship.state.sailDeployment=0; ship.sailRecovery=0
		var stop_request=_terminal_stop_request(ship)
		if not stop_request.is_empty():
			navigation_assists[ship.state.id]=stop_request
			continue
		if ship.sunk or not ship.state.has("navigation") or ship.state.id in policy.get("lockedShipIds", []) or ship.state.id in policy.get("disabledMotionShipIds", []): continue
		var fighting = ship.state.team == "hostile" and ship.state.cannonsPerSide > 0 and not player.is_empty() and not player.sunk and _distance(_visual(ship).position, _visual(player).position) <= 260
		if not fighting or hasActiveOrder(ship.state.id):
			var assist: Dictionary = _autopilot(ship)
			if not assist.is_empty(): navigation_assists[ship.state.id] = assist
		var decision = decisions.get(ship.state.id, {})
		if decision.has("maxDeployment"): ship.state.sailDeployment = minf(ship.state.sailDeployment, decision.maxDeployment)
		if decision.get("fire", false):
			for side in ["port", "starboard"]:
				if not _target(ship, side, ship.state.ammoType).is_empty(): _ship_command({"type": "fire", "shipId": ship.state.id, "side": side})
	for ship in ships:
		ship.previous = _visual(ship)
		if ship.sunk: ship.erase("manualHandling"); continue
		if ship.state.id in policy.get("disabledMotionShipIds", []): _disable_motion(ship)
		if ship.has("manualHandling") and not _manual_reason(ship).is_empty(): ship.erase("manualHandling")
		if _continuous() and ship.state.id in policy.get("lockedShipIds", []): _stop_service(ship)
		var visual = ship.previous
		if ship.state.autoTrim:
			var wx = wind.direction.x * wind.speed + visual.velocity.x; var wz = wind.direction.y * wind.speed + visual.velocity.z
			ship.state.sailAngle = _wrap(atan2(wz, wx) - visual.heading) / 2.0
		ship.core.set_sail_deployment(ship.state.sailDeployment); ship.core.set_sail_condition(ship.state.sail / ship.state.maxSail); ship.core.set_sail_angle(ship.state.sailAngle)
		var controls = {"throttle": 0.0, "rudderAngleDeg": ship.state.rudder * 30, "crewSteeringForce": minf(ship.state.crew, ship.state.maxCrew) * 200 * ship.state.stats.steeringMultiplier, "time": tick * DT}
		if ship.has("manualHandling"):
			controls.manualAssist = Manual.build(ship.state.kind, ship.manualHandling.turnIntent, _speed(visual), ship.state.crew / ship.state.maxCrew, ship.state.hull / ship.state.maxHull, ship.state.sail / ship.state.maxSail, ship.manualHandling.braking, ship.state.sailDeployment, config.get("referenceHandling", false))
			if not controls.manualAssist.is_empty(): controls.throttle = Casual.throttle(ship.state, visual, wind, ship.manualHandling, controls.manualAssist.powerFraction, ship.core.drive_max_accel)
		elif navigation_assists.has(ship.state.id): controls.manualAssist = navigation_assists[ship.state.id]
		ship.core.step_in_place(DT, controls)
		_shore(ship)
	_contacts()
	for ship in ships:
		if _continuous() and ship.state.id in policy.get("lockedShipIds", []): _stop_service(ship)
		if ship.has("terminalStop") and tick>ship.terminalStop.startedTick and _speed(_visual(ship))<=0.05 and absf(ship.core.get_snapshot().yawRate)<=0.01:
			_clear_terminal_stop(ship)
	var due = volleys.filter(func(v): return v.due <= tick)
	volleys = volleys.filter(func(v): return v.due > tick)
	for volley in due:
		var ship = _ship(volley.shipId); var target = _ship(volley.get("targetId", ""))
		var operational = not ship.is_empty() and not ship.sunk and not ship.state.id in policy.get("disabledMotionShipIds", []) and (not _continuous() or ship.state.crew > 0 and not ship.state.id in policy.get("capturedShipIds", []))
		if operational and (not _has_fire_extension(ship) or _available_crew(ship) > 0.0) and (not volley.has("targetId") or not target.is_empty() and not target.sunk and _enemy(ship, target)): _launch(ship, volley.side, volley.ammo, volley.cannon, volley.get("targetId", ""))
	_advance_projectiles(); _advance_fire(); _finish()
	if _environment:
		var observer: Dictionary = {"epoch":epoch,"route":config.get("environmentRoute","sailing" if _continuous() else "battle")}
		var focus := _ship(player_id)
		if not focus.is_empty():
			var pose := _visual(focus)
			observer.position = Vector3(pose.position.x,pose.position.y,pose.position.z)
			observer.heading = pose.heading
		_environment.advance(tick*DT,observer,wind)
func _ai(ship: Dictionary) -> void:
	# Only explicitly equipped combatants use this additional tactical layer.
	# The original no-extension decisions and RNG remain untouched.
	if ship.state.has("fireControl"):
		var fire_state: Dictionary = ship.state.fireControl
		if fire_state.heat > 0.0 and fire_state.supplies > 0 and fire_state.assignedFirefighters == 0 and fire_state.pendingFirefighters == 0 and fire_state.transferTicks == 0:
			var workers: int = mini(4, maxi(0, int(floor(ship.state.crew)) - _launcher_operators(ship)))
			if workers > 0: _ship_command({"type":"fire-control", "shipId":ship.state.id, "crew":workers})
	var target = _ship(player_id)
	if _continuous():
		var candidates = ships.filter(func(s): return not s.sunk and _enemy(ship, s))
		var p = _visual(ship).position
		_stable_sort(candidates, func(a, b):
			var da = _distance(_visual(a).position, p) - (40 if a.state.cannonsPerSide > 0 else 0)
			var db = _distance(_visual(b).position, p) - (40 if b.state.cannonsPerSide > 0 else 0)
			return da < db if da != db else _compare_ids(a.state.id, b.state.id) < 0)
		target = candidates[0] if not candidates.is_empty() else {}
	if target.is_empty() or target.sunk: return
	if ship.state.has("fireLauncher"):
		var payload: String = "fire-ball" if ship.state.fireLauncher.ammo["fire-ball"] > 0 else "thorn-ball"
		_ship_command({"type":"launch-fire", "shipId":ship.state.id, "targetId":target.state.id, "payload":payload})
	var v = _visual(ship); var q = _visual(target)
	var distance = _distance(q.position, v.position)
	var direction = atan2(q.position.z - v.position.z, q.position.x - v.position.x)
	var relative = _wrap(direction - v.heading)
	var side = "starboard" if relative >= 0 else "port"
	var unarmed = ship.state.cannonsPerSide == 0
	var desired = direction + PI if unarmed else direction if distance > 220 else direction - (PI / 2 if side == "starboard" else -PI / 2)
	if not unarmed and (ship.state.hull < 25 or distance < 55): desired = direction + PI * 0.7
	var wind_from = atan2(wind.direction.y, wind.direction.x)
	if unarmed and wind.speed > 0 and absf(_wrap(desired - wind_from)) < PI / 3: desired = wind_from + (1 if _wrap(desired - wind_from) >= 0 else -1) * PI / 3
	var sampler: Callable = config.get("sampleTerrainHeight", Callable())
	if sampler.is_valid() and sampler.call(v.position.x + cos(desired) * 35, v.position.z + sin(desired) * 35) >= config.get("seaLevel", 0) - ship.state.dimensions.draft: desired += PI / 2
	for other in ships:
		if other.state.id == ship.state.id or other.sunk: continue
		var p = _visual(other).position
		if _distance(p, v.position) < ship.state.dimensions.length + other.state.dimensions.width and absf(_wrap(atan2(p.z - v.position.z, p.x - v.position.x) - v.heading)) < 0.6: desired += (1 if _compare_ids(ship.state.id, other.state.id) > 0 else -1) * PI / 3
	_ship_command({"type": "controls", "shipId": ship.state.id, "rudder": clampf(_wrap(desired - v.heading) * 1.4, -1, 1), "sailDeployment": 1.0 if unarmed or distance > 220 else 0.65, "autoTrim": true})
	if not unarmed and not _target(ship, side, ship.state.ammoType).is_empty(): _ship_command({"type": "fire", "shipId": ship.state.id, "side": side})
func _tactical_tick() -> void:
	decisions.clear()
	var snapshots = snapshot().ships
	for record in orders.values():
		if record.status.state != "active": continue
		var intent = record.order.intent; var target = _ship(intent.get("targetId", ""))
		var reason = ""; var next_state = "blocked"
		if intent.has("targetId"):
			if intent.targetId in policy.get("capturedShipIds", []): reason = "target-captured"; next_state = "blocked" if intent.kind == "protect" else "completed"
			elif target.is_empty(): reason = "target-not-visible"
			elif target.sunk: reason = "target-sunk"; next_state = "blocked" if intent.kind == "protect" else "completed"
		for id in record.participants.duplicate():
			var ship = _ship(id)
			if ship.is_empty() or ship.sunk or ship.state.crew <= 0 or not _controlled(id):
				record.participants.erase(id); record.status.reason = "participant-crew-unavailable" if not ship.is_empty() and ship.state.crew <= 0 else "ship-unavailable"
				if not ship.is_empty(): ship.state.erase("navigation"); ship.erase("tack"); ship.state.sailDeployment = 0; ship.state.rudder = 0; ship.sailRecovery = 0; ship.lowSpeedTurn = false
		if record.participants.is_empty() and reason.is_empty(): reason = record.status.get("reason", "ship-unavailable")
		if not reason.is_empty():
			record.status = {"id": record.order.id, "state": next_state, "reason": reason}
			for id in record.participants:
				var ship = _ship(id)
				if not ship.is_empty(): ship.state.erase("navigation"); ship.erase("tack")
			continue
		var completed = 0; var index = 0
		for id in record.participants:
			var ship = _ship(id)
			var ship_snapshot = snapshots.filter(func(s): return s.id == id)[0]
			var target_snapshot = snapshots.filter(func(s): return s.id == target.state.id)[0] if not target.is_empty() else {}
			var threats = snapshots.filter(func(s): return s.hull > 0 and _enemy(ship, _ship(s.id))) if not target.is_empty() else []
			if not target.is_empty():
				_stable_sort(threats, func(a, b): return _distance(a.visual.position, target_snapshot.visual.position) < _distance(b.visual.position, target_snapshot.visual.position) if _distance(a.visual.position, target_snapshot.visual.position) != _distance(b.visual.position, target_snapshot.visual.position) else _compare_ids(a.id, b.id) < 0)
			var decision = Orders.decision(intent, ship_snapshot, target_snapshot, threats[0] if not threats.is_empty() else {}, index)
			index += 1
			if not _safe_point(ship, decision.point): record.status = {"id": record.order.id, "state": "blocked", "reason": "unsafe-depth"}; break
			if decision.get("completed", false): completed += 1
			ship.state.navigation = decision.point.duplicate(true); decisions[id] = decision
		if record.status.state == "blocked" or completed == record.participants.size():
			if completed == record.participants.size(): record.status = {"id": record.order.id, "state": "completed", "reason": "rally-arrived"}
			for id in record.participants:
				var ship = _ship(id)
				decisions.erase(id); ship.state.erase("navigation"); ship.state.sailDeployment = 0
				if record.status.state == "completed":
					_neutral_navigation_controls(ship)
					for key in ["route","approachRecovery","wetRouteEgress","approachManualOverride","egressRevokedGoal","egressRetryAt"]: ship.erase(key)
					ship.state.navigation=record.order.intent.point.duplicate(true)
					ship.terminalStop={"battleId":battle_id,"shipId":id,"orderId":record.order.id,"goal":record.order.intent.point.duplicate(true),"draft":ship.state.dimensions.draft,"startedTick":tick,"deadlineTick":tick+int(Approach.MAX_HORIZON/DT)}
					if not _terminal_stop_authorized(ship):_clear_terminal_stop(ship)
func _tack_course(ship: Dictionary, bearing: float, visual: Dictionary) -> float:
	var wind_from = atan2(wind.direction.y, wind.direction.x)
	var upwind = absf(_wrap(bearing - wind_from))
	if wind.speed <= 0 or ship.has("tack") and (upwind > 70 * PI / 180 or absf(_wrap(wind_from - ship.tack.windFrom)) > PI / 18): ship.erase("tack")
	if not ship.has("tack") and wind.speed > 0 and upwind < PI / 3:
		var sides = [-1, 1]
		sides.sort_custom(func(a, b): return _wet_ahead(ship, a, wind_from, visual) if _wet_ahead(ship, a, wind_from, visual) != _wet_ahead(ship, b, wind_from, visual) else absf(_wrap(wind_from + a * PI / 3 - visual.heading)) < absf(_wrap(wind_from + b * PI / 3 - visual.heading)))
		ship.tack = {"side": sides[0], "windFrom": wind_from, "settledTicks": 0, "legTicks": 0}
	if not ship.has("tack"): return bearing
	var tack = ship.tack
	var aligned = absf(_wrap(wind_from + tack.side * PI / 3 - visual.heading)) <= PI / 15
	if aligned and _speed(visual) >= 1.2: tack.settledTicks += 1
	else: tack.settledTicks = 0
	var advance = (visual.position.x - ship.previous.position.x) * cos(bearing) + (visual.position.z - ship.previous.position.z) * sin(bearing)
	var moving = _distance(visual.position, ship.previous.position) > 0.001
	if tack.settledTicks >= 2 / DT and moving: tack.legTicks += 1
	if tack.settledTicks >= 2 / DT and (tack.legTicks >= 45 / DT or advance < -0.001):
		if _wet_ahead(ship, -tack.side, wind_from, visual): tack.side = -tack.side
		tack.settledTicks = 0; tack.legTicks = 0
	return wind_from + tack.side * PI / 3
func _wet_ahead(ship: Dictionary, side: int, wind_from: float, visual: Dictionary) -> bool:
	var sampler: Callable = config.get("sampleTerrainHeight", Callable())
	if not sampler.is_valid(): return true
	var angle = wind_from + side * PI / 3
	if config.get("routePlanning", false):
		for ahead in range(0, 151, 5):
			if not _wet_hull(ship, visual.position.x + cos(angle) * ahead, visual.position.z + sin(angle) * ahead, angle): return false
		return true
	var h = sampler.call(visual.position.x + cos(angle) * 45, visual.position.z + sin(angle) * 45)
	return _finite(h) and h < config.get("seaLevel", 0) - ship.state.dimensions.draft
func _ship_ahead(ship: Dictionary, visual: Dictionary, heading: float) -> bool:
	for other in ships:
		if other.state.id == ship.state.id or other.sunk: continue
		var p = _visual(other).position
		if _distance(p, visual.position) < ship.state.dimensions.length * 1.5 and absf(_wrap(atan2(p.z - visual.position.z, p.x - visual.position.x) - heading)) < 0.6: return true
	return false
func _feasible(ship: Dictionary, visual: Dictionary, heading: float, safe_wind: float) -> bool:
	if wind.speed > 0 and absf(_wrap(heading - atan2(wind.direction.y, wind.direction.x))) < safe_wind or _ship_ahead(ship, visual, heading): return false
	for ahead in [0, 15, 30, 45]:
		if not _wet_hull(ship, visual.position.x + cos(heading) * ahead, visual.position.z + sin(heading) * ahead, heading): return false
	return true
func _shore_course(ship: Dictionary,visual: Dictionary,desired: float) -> Dictionary:
	var physics: Dictionary=ship.core.get_config()
	var wind_from=atan2(wind.direction.y,wind.direction.x)
	var safe_wind: float=(physics.noGoZoneDeg+physics.noGoFadeDeg)*PI/180
	var clear=wind.speed<=0 or absf(_wrap(desired-wind_from))>=safe_wind
	for ahead in [0,15,30,45]:
		if not _wet_hull(ship,visual.position.x+cos(desired)*ahead,visual.position.z+sin(desired)*ahead,desired):clear=false;break
	if clear:return {"ok":true,"heading":desired}
	# Shore alternatives must pass the same wind, hull and peer gates as the
	# existing avoidance path. A quarter-turn alone is not a safe course.
	var candidates=[desired+PI/2,desired-PI/2,wind_from+PI/3,wind_from-PI/3].filter(func(h):return _feasible(ship,visual,h,safe_wind))
	candidates.sort_custom(func(a,b):return absf(_wrap(a-visual.heading))<absf(_wrap(b-visual.heading)))
	return {"ok":false,"heading":visual.heading} if candidates.is_empty() else {"ok":true,"heading":candidates[0]}
func _autopilot(ship: Dictionary) -> Dictionary:
	var waypoint = ship.state.navigation
	var visual = _visual(ship)
	var sampler: Callable = config.get("sampleTerrainHeight", Callable())
	if ship.has("wetRouteEgress"):
		if _egress_authorized(ship) and ship.wetRouteEgress.goal==waypoint and ship.wetRouteEgress.draft==ship.state.dimensions.draft:return _egress_tick(ship,visual)
		ship.egressRevokedGoal=waypoint.duplicate(true)
		ship.erase("wetRouteEgress");ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0
		return {}
	if ship.get("egressRevokedGoal")==waypoint and not hasActiveOrder(ship.state.id):return {}
	if config.get("routePlanning", false) and sampler.is_valid():
		var route = ship.get("route", {})
		var distance = _distance(route.points[0], visual.position) if not route.is_empty() and not route.points.is_empty() else INF
		if route.is_empty() or route.target.x != waypoint.x or route.target.z != waypoint.z or route.draft != ship.state.dimensions.draft or route.points.is_empty() and tick >= route.retryAt or not route.points.is_empty() and tick - route.checked > 1800 and distance > route.distance - 5:
			var result = Planner.new().plan(visual.position, waypoint, ship.state.dimensions, sampler, config.get("seaLevel", 0))
			var keep_tack=_keep_tack_after_replan(ship,route,result,waypoint,visual)
			var failures = 0 if result.ok else mini(route.get("failures", 0) + 1, 5)
			ship.route = {"target": waypoint.duplicate(true), "points": result.points if result.ok else [], "checked": tick, "distance": _distance(result.points[0], visual.position) if result.ok else 0, "draft": ship.state.dimensions.draft, "retryAt": tick + mini(1800, int(120 * pow(2, failures))), "failures": failures}
			if not result.ok: ship.route.reason = result.reason
			if not keep_tack:ship.erase("tack")
		var current = ship.route
		while current.points.size() > 1 and _distance(current.points[0], visual.position) < 45: current.points.pop_front(); ship.erase("tack")
		if current.points.is_empty():
			if current.get("reason","")=="unsafe-endpoint" and _egress_authorized(ship) and _speed(visual)<=Egress.SPEED_CAP and tick>=ship.get("egressRetryAt",0):
				var input=_egress_input(ship,visual)
				var result: Dictionary=Egress.plan(input.own,waypoint,input.peers,sampler,config.get("seaLevel",0.0))
				ship.egressClearance=result
				ship.egressRetryAt=tick+120
				if result.ok:
					ship.wetRouteEgress={"goal":waypoint.duplicate(true),"draft":ship.state.dimensions.draft,"node":result.node,"startedTick":tick,"holding":false}
					ship.erase("tack")
					return _egress_tick(ship,visual)
			if ship.has("approachRecovery") and _approach_authorized(ship): return _hold_approach(ship)
			ship.state.rudder = 0; ship.state.sailDeployment = 0; return {}
		waypoint = current.points[0]
		if tick - current.checked > 1800: current.checked = tick; current.distance = _distance(waypoint, visual.position)
	var distance = _distance(waypoint, visual.position)
	var intermediate = config.get("routePlanning", false) and ship.has("route") and ship.route.points.size() > 1
	if _arrival_hold_requested(ship,waypoint,distance,intermediate):
		_neutral_navigation_controls(ship)
		return _arrival_brake(ship)
	var desired = _tack_course(ship, atan2(waypoint.z - visual.position.z, waypoint.x - visual.position.x), visual)
	var shore_course=_shore_course(ship,visual,desired)
	desired=shore_course.heading
	var blocked = not shore_course.ok
	var recovery = false
	if _ship_ahead(ship, visual, visual.heading):
		var physics = ship.core.get_config()
		var safe_wind = (physics.noGoZoneDeg + physics.noGoFadeDeg) * PI / 180
		var candidates = [desired + PI / 3, desired - PI / 3].filter(func(h): return _feasible(ship, visual, h, safe_wind))
		candidates.sort_custom(func(a, b): return absf(_wrap(a - visual.heading)) < absf(_wrap(b - visual.heading)))
		blocked = candidates.is_empty(); desired = visual.heading if blocked else candidates[0]
	if blocked or ship.has("approachRecovery"):
		var owned = ship.has("approachRecovery") and _approach_authorized(ship) and ship.approachRecovery.goal == ship.state.navigation
		if owned:
			var motion: Dictionary=ship.core.get_snapshot()
			if ship.approachRecovery.holding:
				if _speed(visual)>0.05 or absf(motion.yawRate)>0.005: return _hold_approach(ship)
				ship.erase("approachRecovery")
			elif tick-ship.approachRecovery.startedTick >= int(Approach.TURN_SECONDS/DT): return _hold_approach(ship)
		recovery = _final_approach_clear(ship, visual, waypoint, distance)
		if recovery:
			desired = atan2(waypoint.z - visual.position.z, waypoint.x - visual.position.x)
			blocked = false
			if not ship.has("approachRecovery"): ship.approachRecovery = {"goal":ship.state.navigation.duplicate(true),"startedTick":tick,"holding":false}
		elif owned: return _hold_approach(ship)
		else: ship.erase("approachRecovery")
	if blocked:
		ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0
		return {}
	var speed = _speed(visual)
	var yaw = _wrap(visual.heading - ship.previous.heading) / DT
	var error = _wrap(desired - visual.heading)
	ship.state.rudder = clampf(error * 1.8 - yaw * 6, -1, 1)
	var approach = 7 if intermediate else clampf((distance - 10) * 0.02, 0, 7)
	var deployment = 0 if distance <= (Navigation.PLANNED_TARGET_REACH_METERS if config.get("routePlanning", false) else 30) and not intermediate else clampf((approach - speed) * 2, 0, 1)
	if speed >= 1.2: ship.lowSpeedTurn = false; ship.sailRecovery = 1
	elif absf(error) > PI / 3: ship.lowSpeedTurn = true
	elif absf(error) < 40 * PI / 180: ship.lowSpeedTurn = false
	if blocked: ship.sailRecovery = 0; ship.state.sailDeployment = 0
	elif ship.lowSpeedTurn: ship.sailRecovery = 0; ship.state.sailDeployment = maxf(0, ship.state.sailDeployment - DT)
	else: ship.sailRecovery = minf(1, ship.sailRecovery + DT * 0.25); ship.state.sailDeployment = minf(deployment, ship.sailRecovery)
	ship.state.autoTrim = true
	if recovery:
		if absf(error) > PI / 36:
			ship.state.sailDeployment = 0; ship.sailRecovery = 0
			return Manual.build(ship.state.kind,ship.state.rudder,speed,ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0,true)
		ship.erase("approachRecovery")
	return _navigation_steerage(ship,visual,desired,error,blocked,distance,intermediate)
func _neutral_navigation_controls(ship: Dictionary) -> void:
	# Relinquish autonomous outputs, never native momentum or physical pose.
	ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0;ship.lowSpeedTurn=false
	ship.erase("tack")
func _arrival_brake(ship: Dictionary) -> Dictionary:
	if not config.get("referenceHandling",false) or not config.get("routePlanning",false) or has_pending_combat():return {}
	return Manual.build(ship.state.kind,0.0,_speed(_visual(ship)),ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0.0,true)
func _clear_terminal_stop(ship: Dictionary) -> void:
	if not ship.has("terminalStop"):return
	if ship.state.get("navigation")==ship.terminalStop.goal:ship.state.erase("navigation")
	ship.erase("terminalStop")
func _terminal_stop_authorized(ship: Dictionary) -> bool:
	if not ship.has("terminalStop") or not _continuous() or not config.get("referenceHandling",false) or not config.get("routePlanning",false):return false
	var owner: Dictionary=ship.terminalStop;var id: String=ship.state.id
	if owner.battleId!=battle_id or owner.shipId!=id or owner.draft!=ship.state.dimensions.draft or owner.goal!=ship.state.get("navigation"):return false
	var record: Dictionary=orders.get(owner.orderId,{})
	if record.is_empty() or record.status.state!="completed" or record.order.intent.kind!="rally" or record.order.intent.point!=owner.goal or not id in record.participants or hasActiveOrder(id):return false
	if not _controlled(id) or ship.sunk or ship.state.hull<=0 or ship.state.crew<=0 or ship.state.sail<=0 or id in policy.get("capturedShipIds",[]) or status in ["surrendered","defeat","victory"] or has_pending_combat():return false
	if ship.has("manualHandling") or ship.state.rudder!=0 or ship.state.sailDeployment!=0:return false
	var p: Dictionary=_visual(ship);var sampler: Callable=config.get("sampleTerrainHeight",Callable())
	return sampler.is_valid() and _speed(p)<1.2 and _wet_hull(ship,p.position.x,p.position.z,p.heading)
func _terminal_stop_request(ship: Dictionary) -> Dictionary:
	if not ship.has("terminalStop"):return {}
	if tick>=ship.terminalStop.deadlineTick:
		ship.terminalStopResult={"orderId":ship.terminalStop.orderId,"reason":"timeout","tick":tick}
		_clear_terminal_stop(ship);return {}
	if not _terminal_stop_authorized(ship):_clear_terminal_stop(ship);return {}
	return _arrival_brake(ship)
func _arrival_hold_requested(ship: Dictionary,waypoint: Dictionary,distance: float,intermediate: bool) -> bool:
	# Existing recovery owners retain their checked physical hold/handback path.
	if intermediate or ship.has("approachRecovery") or waypoint!=ship.state.navigation:return false
	var id: String=ship.state.id
	if not _controlled(id) or ship.sunk or ship.state.hull<=0 or ship.state.crew<=0 or ship.state.sail<=0 or id in policy.get("capturedShipIds",[]) or status in ["surrendered","defeat","victory"]:return false
	if ship.has("manualHandling") or ship.get("approachManualOverride")==ship.state.navigation:return false
	var order=_active_order(id)
	var reach=Navigation.PLANNED_TARGET_REACH_METERS if config.get("routePlanning",false) else 30
	if order.is_empty():return distance<=reach
	var decision: Dictionary=decisions.get(id,{})
	if decision.get("point")!=ship.state.navigation:return false
	# A completed participant waits without relinquishing a shared Rally that
	# still has ships in transit. The existing decision owns the25m/1mps gate.
	if order.intent.kind=="rally":return decision.get("completed",false)
	if order.intent.kind!="protect" or decision.get("fire",false) or distance>reach or not config.get("routePlanning",false) or not config.get("referenceHandling",false):return false
	return is_anchored(order.intent.targetId)
func _keep_tack_after_replan(ship: Dictionary,old: Dictionary,result: Dictionary,goal: Dictionary,visual: Dictionary) -> bool:
	if not result.ok or not ship.has("tack") or old.is_empty() or old.get("target")!=goal or old.get("draft")!=ship.state.dimensions.draft:return false
	if not _controlled(ship.state.id) or ship.has("manualHandling") or ship.get("approachManualOverride")==goal or hasActiveOrder(ship.state.id):return false
	if old.get("points",[]).is_empty() or result.points.is_empty() or _effective_route_point(old.points,visual.position)!=_effective_route_point(result.points,visual.position):return false
	if old.points.size()>1 and _distance(old.points[0],visual.position)<45:return false
	# Replanning the same leg is not a new tack. Wind and completed-leg gates
	# remain in _tack_course; current depth can still invalidate this side.
	return _wet_ahead(ship,ship.tack.side,atan2(wind.direction.y,wind.direction.x),visual)
func _effective_route_point(points: Array,position: Dictionary) -> Dictionary:
	var index=0
	while index+1<points.size() and _distance(points[index],position)<45:index+=1
	return points[index]
func _egress_authorized(ship: Dictionary) -> bool:
	return _approach_authorized(ship) and ship.state.crew/ship.state.maxCrew>=0.25 and ship.get("egressRevokedGoal")!=ship.state.get("navigation")
func _egress_input(ship: Dictionary,visual: Dictionary) -> Dictionary:
	var physics: Dictionary=ship.core.get_config()
	var motion: Dictionary=ship.core.get_snapshot()
	var spec: Dictionary=Types.ship_spec(ship.state.kind)
	var mass: float=spec.mass+ship.state.stats.cargoMass
	var speed=_speed(visual)
	var budget=Manual.build(ship.state.kind,1.0,speed,ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0,true)
	var crew_acceleration=minf(minf(ship.state.crew,ship.state.maxCrew)*200*ship.state.stats.steeringMultiplier/mass,0.002*(spec.length*spec.length+spec.width*spec.width)/spec.length)
	var rudder_acceleration: float=0.5*1025.0*1.2*1.2*spec.width*ship.state.dimensions.draft*physics.waterAreaFactor*physics.rudderAreaFactor*physics.rudderLiftSlope*minf(30.0,physics.rudderStallDeg)*PI/180/mass
	var braking: float=budget.brakeDeceleration*budget.powerFraction*spec.mass/mass-crew_acceleration-rudder_acceleration
	var cl=4.2*28.0*PI/180
	var coefficient: float=1.4*physics.sailPressureScale+cl+0.08+0.08*cl*cl+0.5
	var acceleration: float=0.5*1.225*pow(wind.speed+1.2,2)*spec.sailArea*coefficient*pow(ship.state.stats.speedMultiplier,2)/mass
	var own={"position":visual.position,"velocity":visual.velocity,"heading":visual.heading,"yawRate":motion.yawRate,"dimensions":ship.state.dimensions,"speed":speed,"brake":braking,"yaw_damping":physics.yawDamp,"sail_acceleration":acceleration,"lateral_acceleration":crew_acceleration+rudder_acceleration,"wind_speed":wind.speed,"wind_from":atan2(wind.direction.y,wind.direction.x),"safe_wind":(physics.noGoZoneDeg+physics.noGoFadeDeg)*PI/180}
	var peers: Array=[]
	for peer: Dictionary in ships:
		if peer.state.id==ship.state.id or peer.sunk:continue
		var p: Dictionary=peer.core.get_snapshot()
		peers.append({"id":peer.state.id,"position":p.position,"velocity":p.velocity,"heading":p.heading,"yawRate":p.yawRate,"dimensions":peer.state.dimensions})
	return {"own":own,"peers":peers}
func _egress_tick(ship: Dictionary,visual: Dictionary) -> Dictionary:
	var owner: Dictionary=ship.wetRouteEgress
	var input=_egress_input(ship,visual)
	ship.egressClearance=Egress.assess(input.own,owner.node,input.peers,config.get("sampleTerrainHeight",Callable()),config.get("seaLevel",0.0))
	# A failed fresh check latches a furled hold. Only a fresh navigation goal
	# can retry, so disappearing hazards cannot automatically reopen sails.
	if owner.holding or not ship.egressClearance.ok or tick-owner.startedTick>int(Egress.HORIZON/DT):
		owner.holding=true
		ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0
		return Manual.build(ship.state.kind,0.0,input.own.speed,ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0,true)
	# This real-position check guards handback. The connector is not a normal
	# waypoint and is never subject to the existing 45m pop or smoothing rule.
	var onward: Dictionary=Planner.new().plan(visual.position,owner.goal,ship.state.dimensions,config.get("sampleTerrainHeight",Callable()),config.get("seaLevel",0.0))
	if onward.ok:
		ship.route={"target":owner.goal.duplicate(true),"points":onward.points,"checked":tick,"distance":_distance(onward.points[0],visual.position),"draft":ship.state.dimensions.draft,"retryAt":tick,"failures":0}
		ship.erase("wetRouteEgress");ship.state.sailDeployment=0;ship.sailRecovery=0
		return _autopilot(ship)
	var error=_wrap(ship.egressClearance.course-visual.heading)
	var yaw: float=ship.core.get_snapshot().yawRate
	ship.state.rudder=clampf(error*1.8-yaw*6.0,-1,1)
	var braking=absf(error)>Egress.COURSE_TOLERANCE or input.own.speed>=Egress.SPEED_CAP or absf(yaw)>0.005
	ship.state.sailDeployment=0.0 if braking else Egress.MAX_SAIL
	ship.sailRecovery=ship.state.sailDeployment;ship.state.autoTrim=true
	return Manual.build(ship.state.kind,ship.state.rudder,input.own.speed,ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,braking,ship.state.sailDeployment,true)
func _hold_approach(ship: Dictionary) -> Dictionary:
	if not ship.has("approachRecovery"): ship.approachRecovery={"goal":ship.state.navigation.duplicate(true),"startedTick":tick,"holding":true}
	ship.approachRecovery.holding=true
	ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0
	return Manual.build(ship.state.kind,0.0,_speed(_visual(ship)),ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0,true)
func _final_approach_clear(ship: Dictionary, visual: Dictionary, waypoint: Dictionary, distance: float) -> bool:
	var id: String = ship.state.id
	if not _approach_authorized(ship) or distance <= 25.0 or distance > 55.0 or _speed(visual) > 0.75: return false
	if not ship.has("route") or ship.route.points.size() != 1 or waypoint != ship.state.navigation: return false
	if ship.has("approachRecovery") and ship.approachRecovery.goal != ship.state.navigation: return false
	var physics: Dictionary = ship.core.get_config()
	var course = atan2(waypoint.z-visual.position.z,waypoint.x-visual.position.x)
	if wind.speed > 0 and absf(_wrap(course-atan2(wind.direction.y,wind.direction.x))) < (physics.noGoZoneDeg+physics.noGoFadeDeg)*PI/180: return false
	var motion: Dictionary = ship.core.get_snapshot()
	var spec: Dictionary = Types.ship_spec(ship.state.kind)
	var speed = _speed(visual)
	var budget = Manual.build(ship.state.kind,1.0,speed,ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,true,0,true)
	var mass: float = spec.mass + ship.state.stats.cargoMass
	var dry_fraction: float = spec.mass/mass
	# Subtract worst lateral crew and hydraulic rudder acceleration from the
	# existing dry-hull brake. No drag credit and no extra physical force.
	var crew_acceleration = minf(minf(ship.state.crew,ship.state.maxCrew)*200*ship.state.stats.steeringMultiplier/mass,0.002*(spec.length*spec.length+spec.width*spec.width)/spec.length)
	var rudder_acceleration: float = 0.5*1025.0*1.2*1.2*spec.width*ship.state.dimensions.draft*physics.waterAreaFactor*physics.rudderAreaFactor*physics.rudderLiftSlope*minf(30.0,physics.rudderStallDeg)*PI/180/mass
	var braking: float = budget.brakeDeceleration*budget.powerFraction*dry_fraction-crew_acceleration-rudder_acceleration
	# Native fixed ship parameters: |CL|<=4.2*28deg, CD=.08+.08*CL²,
	# pressure<=1.4*scale; include parasitic .5 and maximum sail power.
	var cl = 4.2*28.0*PI/180
	var sail_coefficient: float = 1.4*physics.sailPressureScale+cl+0.08+0.08*cl*cl+0.5
	var sail_acceleration: float = 0.5*1.225*pow(wind.speed+1.2,2)*spec.sailArea*sail_coefficient*pow(ship.state.stats.speedMultiplier,2)/mass
	var sail_start: float = ship.get("sailRecovery",1.0) if absf(_wrap(course-visual.heading)) <= PI/36 else 0.0
	var own = {"position":visual.position,"velocity":visual.velocity,"heading":visual.heading,"yawRate":motion.yawRate,"dimensions":ship.state.dimensions,"course":course,"distance":distance,"speed":speed,"brake":braking,"yaw_damping":physics.yawDamp,"sail_acceleration":sail_acceleration,"lateral_acceleration":crew_acceleration+rudder_acceleration,"sail_start":sail_start}
	var peers: Array = []
	for peer in ships:
		if peer.state.id == id or peer.sunk: continue
		var p: Dictionary = peer.core.get_snapshot()
		peers.append({"id":peer.state.id,"position":p.position,"velocity":p.velocity,"heading":p.heading,"yawRate":p.yawRate,"dimensions":peer.state.dimensions})
	ship.approachClearance = Approach.assess(own,peers,config.get("sampleTerrainHeight",Callable()),config.get("seaLevel",0.0))
	return ship.approachClearance.ok
func _approach_authorized(ship: Dictionary) -> bool:
	var id: String = ship.state.id
	if not config.get("routePlanning",false) or not config.get("referenceHandling",false) or not ship.state.has("navigation"): return false
	if ship.has("manualHandling") or ship.get("approachManualOverride") == ship.state.get("navigation") or hasActiveOrder(id): return false
	if ship.sunk or ship.state.hull <= 0 or ship.state.crew <= 0 or ship.state.sail <= 0 or not _controlled(id) or has_pending_combat(): return false
	return not id in policy.get("capturedShipIds",[]) and not status in ["surrendered","defeat","victory"]
func _navigation_steerage(ship: Dictionary,visual: Dictionary,desired: float,error: float,blocked: bool,distance: float,intermediate: bool) -> Dictionary:
	if not config.get("referenceHandling",false) or blocked or _speed(visual)>=1.2 or absf(error)<=PI/36 or ship.state.crew<=0 or ship.state.hull<=0 or ship.state.id in policy.get("capturedShipIds",[]):return {}
	var reach=Navigation.PLANNED_TARGET_REACH_METERS if config.get("routePlanning",false) else 30
	if not intermediate and distance<=reach:return {}
	# Use the existing crew/hull-scaled, bounded steering request. Every hull
	# orientation of the recovery turn and the outgoing course must remain wet.
	var p=visual.position;var steps=maxi(1,int(ceil(absf(error)/(PI/18))))
	for index in steps+1:
		if not _wet_hull(ship,p.x,p.z,visual.heading+error*index/steps):return {}
	for ahead in [15,30,45]:
		if not _wet_hull(ship,p.x+cos(desired)*ahead,p.z+sin(desired)*ahead,desired):return {}
	return Manual.build(ship.state.kind,ship.state.rudder,_speed(visual),ship.state.crew/ship.state.maxCrew,ship.state.hull/ship.state.maxHull,ship.state.sail/ship.state.maxSail,false,ship.state.sailDeployment,true)
func _footprint_height(ship: Dictionary, x: float, z: float, heading: float) -> float:
	var sampler: Callable = config.sampleTerrainHeight
	var highest = -INF; var dims = ship.state.dimensions
	for f in [-0.5, 0, 0.5]:
		for side in [-0.5, 0, 0.5]: highest = maxf(highest, sampler.call(x + cos(heading) * dims.length * f - sin(heading) * dims.width * side, z + sin(heading) * dims.length * f + cos(heading) * dims.width * side))
	return highest
func _shore(ship: Dictionary) -> void:
	var sampler: Callable = config.get("sampleTerrainHeight", Callable())
	if not sampler.is_valid(): return
	var previous = ship.previous; var next = _visual(ship); var dims = ship.state.dimensions
	var dx = next.position.x - previous.position.x; var dz = next.position.z - previous.position.z
	var dh = _wrap(next.heading - previous.heading)
	var steps = maxi(1, int(ceil((sqrt(dx * dx + dz * dz) + sqrt(dims.length * dims.length + dims.width * dims.width) / 2.0 * absf(dh)) / maxf(0.25, dims.width * 0.1))))
	var safe = 0.0
	for i in range(1, steps + 1):
		var t = float(i) / steps
		if not _wet_hull(ship, previous.position.x + dx * t, previous.position.z + dz * t, previous.heading + dh * t): break
		safe = t
	if safe == 1 and _wet_hull(ship, next.position.x + 0.01, next.position.z, next.heading) and _wet_hull(ship, next.position.x - 0.01, next.position.z, next.heading) and _wet_hull(ship, next.position.x, next.position.z + 0.01, next.heading) and _wet_hull(ship, next.position.x, next.position.z - 0.01, next.heading): return
	var low = safe; var high = minf(1, safe + 1.0 / steps)
	for i in 16:
		var t = (low + high) / 2.0
		if _wet_hull(ship, previous.position.x + dx * t, previous.position.z + dz * t, previous.heading + dh * t): low = t
		else: high = t
	var x = previous.position.x + dx * low; var z = previous.position.z + dz * low
	var heading = previous.heading + dh * low
	var epsilon = maxf(0.5, dims.width * 0.2)
	var nx = _footprint_height(ship, x + epsilon, z, heading) - _footprint_height(ship, x - epsilon, z, heading)
	var nz = _footprint_height(ship, x, z + epsilon, heading) - _footprint_height(ship, x, z - epsilon, heading)
	var length = sqrt(nx * nx + nz * nz)
	if not is_finite(length) or length < 1e-8: nx = dx; nz = dz; length = sqrt(nx * nx + nz * nz)
	if length < 1e-8: ship.core.correct_horizontal_motion({"x": x, "z": z}, {"x": 0, "z": 0}, heading); return
	nx /= length; nz /= length
	var highest = -INF; var offset = {"x": 0, "z": 0}
	for f in [-0.5, 0, 0.5]:
		for side in [-0.5, 0, 0.5]:
			var ox = cos(heading) * dims.length * f - sin(heading) * dims.width * side
			var oz = sin(heading) * dims.length * f + cos(heading) * dims.width * side
			var h = sampler.call(x + ox, z + oz)
			if h > highest: highest = h; offset = {"x": ox, "z": oz}
	ship.core.correct_horizontal_motion({"x": x, "z": z}, {"x": next.velocity.x, "z": next.velocity.z}, heading)
	var yaw = 0.0
	if absf(dh) > 1e-12: yaw = ship.core.resolve_horizontal_contact({"x": nx, "z": nz}, offset)
	else:
		var inward = maxf(0, next.velocity.x * nx + next.velocity.z * nz)
		ship.core.correct_horizontal_motion({"x": x, "z": z}, {"x": next.velocity.x - nx * inward, "z": next.velocity.z - nz * inward})
	var velocity = _visual(ship).velocity
	if low < 1: x -= nx * 0.001; z -= nz * 0.001
	var remain = DT * (1 - low); var fraction = 1.0
	if not _wet_hull(ship, x + velocity.x * remain, z + velocity.z * remain, heading + yaw * remain):
		var a = 0.0; var b = 1.0
		for i in 16:
			var t = (a + b) / 2
			if _wet_hull(ship, x + velocity.x * remain * t, z + velocity.z * remain * t, heading + yaw * remain * t): a = t
			else: b = t
		fraction = a
	ship.core.correct_horizontal_motion({"x": x + velocity.x * remain * fraction, "z": z + velocity.z * remain * fraction}, {"x": velocity.x, "z": velocity.z}, heading + yaw * remain * fraction)
func _extent(ship: Dictionary, heading: float, axis: float) -> float: return absf(cos(heading - axis)) * ship.state.dimensions.length / 2.0 + absf(sin(heading - axis)) * ship.state.dimensions.width / 2.0
func _contacts() -> void:
	for i in ships.size():
		for j in range(i + 1, ships.size()):
			var a = ships[i]; var b = ships[j]
			if a.sunk or b.sunk: continue
			var av = _visual(a); var bv = _visual(b)
			var overlap = INF; var nx = 0.0; var nz = 0.0
			for angle in [av.heading, av.heading + PI / 2, bv.heading, bv.heading + PI / 2]:
				var x = cos(angle); var z = sin(angle)
				var separation = (bv.position.x - av.position.x) * x + (bv.position.z - av.position.z) * z
				var depth = _extent(a, av.heading, angle) + _extent(b, bv.heading, angle) - absf(separation)
				if depth <= 0: overlap = 0; break
				if depth < overlap: overlap = depth; nx = x * (1 if separation >= 0 else -1); nz = z * (1 if separation >= 0 else -1)
			if overlap <= 0: continue
			var correction = (overlap + 0.001) / 2
			var impulse = maxf(0, (av.velocity.x - bv.velocity.x) * nx + (av.velocity.z - bv.velocity.z) * nz) / 2
			a.core.correct_horizontal_motion({"x": av.position.x - nx * correction, "z": av.position.z - nz * correction}, {"x": av.velocity.x - nx * impulse, "z": av.velocity.z - nz * impulse})
			b.core.correct_horizontal_motion({"x": bv.position.x + nx * correction, "z": bv.position.z + nz * correction}, {"x": bv.velocity.x + nx * impulse, "z": bv.velocity.z + nz * impulse})
func has_pending_attacks() -> bool: return not volleys.is_empty() or not projectiles.is_empty()
func hasPendingAttacks() -> bool: return has_pending_attacks()
func has_pending_combat() -> bool:
	return status != "surrendered" and (has_pending_attacks() or ships.any(func(s): return not s.sunk and (ships.any(func(t): return not t.sunk and _enemy(s, t)) if _continuous() else s.state.team == "hostile")))
func hasPendingCombat() -> bool: return has_pending_combat()
func is_anchored(id: String) -> bool:
	var ship = _ship(id)
	if ship.is_empty() or ship.sunk or ship.has("terminalStop"): return false
	var motion = ship.core.get_snapshot()
	return _speed(motion) <= 0.05 and absf(motion.yawRate) <= 0.01 and ship.state.rudder == 0 and ship.state.sailDeployment == 0 and not ship.state.has("navigation") and not hasActiveOrder(id)
func isAnchored(id: String) -> bool: return is_anchored(id)
func _stop_service(ship: Dictionary) -> void:
	ship.erase("manualHandling"); _cancel_order(ship.state.id, "service-anchored")
	ship.state.rudder = 0; ship.state.sailDeployment = 0; ship.state.erase("navigation"); ship.erase("tack")
	ship.core.set_sail_deployment(0); ship.core.stop_horizontal_motion(); ship.previous = _visual(ship)
func anchor_fleet(ids: Variant) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	if not ids is Array: return _no("Invalid fleet identities")
	var seen = []
	for id in ids:
		if id in seen: return _no("Invalid fleet identities")
		seen.append(id)
	if not ids.all(func(id): return id is String): return _no("Fleet must be owned and combat settled before anchoring")
	var fleet = ids.map(_ship)
	if fleet.any(func(s): return s.is_empty() or not (_controlled(s.state.id) if _continuous() else s.state.team == "player")) or has_pending_combat(): return _no("Fleet must be owned and combat settled before anchoring")
	if fleet.any(func(s): return s.state.controlsSequence >= SAFE_INTEGER): return _no("Control sequence exhausted")
	for ship in fleet:
		_cancel_order(ship.state.id, "anchored"); ship.state.controlsSequence += 1
		if _continuous(): ship.core.stop_horizontal_motion()
		else:
			var visual = _visual(ship); ship.core.correct_horizontal_motion({"x": visual.position.x, "z": visual.position.z}, {"x": 0, "z": 0})
		ship.state.rudder = 0; ship.state.sailDeployment = 0; ship.state.erase("navigation"); ship.erase("tack"); ship.core.set_sail_deployment(0); ship.previous = _visual(ship)
	return _ok()
func anchorFleet(ids: Variant) -> Dictionary: return anchor_fleet(ids)
func set_player_id(id: String) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	if not _controlled(id): return _no("Ship not authorized")
	var ship = _ship(id)
	if ship.is_empty() or ship.state.team != "player" or ship.sunk: return _no("Flagship must be alive and player-owned")
	if id != player_id:
		for value in ships: value.erase("manualHandling")
	player_id = id; return _ok()
func setPlayerId(id: String) -> Dictionary: return set_player_id(id)
func set_wind(value: Variant) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	if not _valid_wind(value): return _no("Invalid wind")
	wind = value.duplicate(true)
	for ship in ships: ship.core.set_wind(wind)
	if not config.has("oceanWaves"): ocean.set_heading({"x": -wind.direction.x, "y": -wind.direction.y})
	return _ok()
func setWind(value: Variant) -> Dictionary: return set_wind(value)
func _finish() -> void:
	if _continuous():
		if status == "surrendered": return
		var player = _ship(player_id)
		var fighting = ships.filter(func(a): return not a.sunk and ships.any(func(b): return not b.sunk and _enemy(a, b)))
		if not episode_open and not fighting.is_empty() and status != "defeat":
			episode += 1; episode_open = true; episode_threats = fighting.filter(func(s): return not _controlled(s.state.id)).map(func(s): return s.state.id)
		if player.sunk and status != "defeat": status = "defeat"; _emit({"type": "defeat", "shipId": player_id})
		if episode_open and (player.sunk or fighting.is_empty()) and not has_pending_attacks():
			var won = episode_threats.all(func(id): return _ship(id).get("sunk", false) or id in policy.get("capturedShipIds", []))
			_emit({"type": "battle-ended", "shipId": player_id, "battleId": battle_id, "episodeId": battle_id + ":episode-" + str(episode), "outcome": "defeat" if player.sunk else "victory" if won else "disengaged", "reason": "flagship-sunk" if player.sunk else "hostiles-neutralized" if won else "hostiles-left"})
			episode_open = false
		if status != "defeat": status = "active" if not fighting.is_empty() or has_pending_attacks() else "sailing"
		return
	if status in ["defeat", "surrendered"]: return
	var player = _ship(player_id)
	if player.sunk: status = "defeat"; _emit({"type": "defeat", "shipId": player_id})
	elif status == "active" and not ships.any(func(s): return s.state.team == "hostile" and not s.sunk) and not _fire_resolution_pending(): status = "victory"; _emit({"type": "victory", "shipId": player_id})
func _fire_resolution_pending() -> bool:
	# Do not stop damage control or a real airborne incendiary with a result modal.
	# Cold standing teams are allowed: otherwise a deliberate standby assignment
	# would prevent victory forever. Existing unextended terminal battles are exact.
	if projectiles.any(func(p): return p.get("kind") == "fire-payload"): return true
	for ship in ships:
		if ship.sunk or ship.state.team != "player" or not ship.state.has("fireControl"): continue
		if ship.state.fireControl.heat > 0.0 or ship.state.fireControl.transferTicks > 0: return true
	return false
func _validated_update(ship: Dictionary, update: Dictionary) -> Dictionary:
	if ship.state.controlsSequence >= SAFE_INTEGER: last_error = "Control sequence exhausted"; return {}
	if update.has("stats") and not update.stats is Dictionary: last_error = "Invalid ship stats"; return {}
	var state = ship.state
	var visual = _visual(ship)
	var setup = {"id": state.id, "name": state.name, "kind": state.kind, "team": state.team, "position": {"x": visual.position.x, "z": visual.position.z}, "hull": state.hull, "sail": state.sail, "crew": state.crew, "sailDeployment": state.sailDeployment, "ammoType": state.ammoType, "rudder": state.rudder, "sailAngle": state.sailAngle, "autoTrim": state.autoTrim}
	for field in ["fireControl", "fireLauncher"]:
		if state.has(field): setup[field] = _launcher_snapshot(ship) if field == "fireLauncher" else state[field].duplicate(true)
	setup.merge(update, true)
	setup.ammo = state.ammo.duplicate(true)
	if update.has("ammo") and not update.ammo is Dictionary: last_error = "Invalid initial ammunition"; return {}
	setup.ammo.merge(update.get("ammo", {}), true)
	setup.stats = ship.statsInput.duplicate(true); setup.stats.merge(update.get("stats", {}), true)
	var next = _normalize(setup)
	if not next.is_empty() and config.has("oceanWaves") and not is_finite(ocean.heave_excursion + next.dimensions.draft * 2): last_error = "Invalid ship draft travel limit"; return {}
	return next
func _copy_physics_state(from: RefCounted, to: RefCounted) -> void:
	for property in from.get_property_list():
		if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var value = from.get(property.name)
			to.set(property.name, value.duplicate(true) if value is Dictionary or value is Array else value)
func _prepare_physics_update(ship: Dictionary, state: Dictionary) -> RefCounted:
	# Validate every physics setter on a detached numeric clone, before any live
	# authority changes. Commit copies validated scalar state into the same core.
	var probe = Physics.new()
	_copy_physics_state(ship.core, probe)
	var limit = ocean.heave_excursion + state.dimensions.draft * 2 if config.has("oceanWaves") else state.dimensions.draft * 2
	if not probe.set_draft_meters(state.dimensions.draft) or not probe.set_config({"heaveTravelLimit": limit}) or not probe.set_cargo_mass(state.stats.cargoMass) or not probe.set_config({"rudderAreaFactor": ship.baseRudderAreaFactor * state.stats.steeringMultiplier}): last_error = "Invalid ship physics update"; return null
	probe.set_sail_power_scale(pow(state.stats.speedMultiplier, 2)); probe.set_sail_deployment(state.sailDeployment); probe.set_sail_condition(state.sail / state.maxSail)
	return probe
func _apply_update(ship: Dictionary, state: Dictionary, update: Dictionary, prepared_physics: RefCounted) -> void:
	state.controlsSequence = ship.state.controlsSequence + 1
	var owner_changed=["rudder","sailDeployment","sailAngle","autoTrim","crew","hull","sail","maxCrew","maxHull","maxSail","dimensions","stats"].any(func(key):return state[key]!=ship.state[key])
	var navigation = ship.state.get("navigation")
	_copy_physics_state(prepared_physics, ship.core)
	ship.state = state
	if state.has("fireLauncher") and not ship.has("launcherTicks"):
		ship.launcherTicks = {"ready":tick + _remaining_ticks(state.fireLauncher.cooldownSeconds), "busy":tick + _remaining_ticks(state.fireLauncher.operationSeconds)}
	_clip_fire_team(ship)
	if navigation != null: state.navigation = navigation
	ship.statsInput.merge(update.get("stats", {}), true)
	if state.hull <= 0 and not ship.sunk: _sink(ship)
	if ship.has("terminalStop") and (owner_changed or not _terminal_stop_authorized(ship)):_clear_terminal_stop(ship)
func update_ship_stats(id: String, update: Variant) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	var ship = _ship(id)
	if ship.is_empty() or not update is Dictionary: return _no("Unknown ship or invalid update")
	if update.has("id") and update.id != id or update.has("kind") and update.kind != ship.state.kind: return _no("Cannot replace live ship identity or hull")
	if ship.sunk and update.get("hull", 0) > 0: return _no("Cannot resurrect sunk ship")
	var next = _validated_update(ship, update)
	if next.is_empty(): return _no(last_error)
	var physics = _prepare_physics_update(ship, next)
	if physics == null: return _no(last_error)
	_apply_update(ship, next, update, physics); _finish(); return _ok()
func updateShipStats(id: String, update: Variant) -> Dictionary: return update_ship_stats(id, update)
func reconcile_ships(setups: Variant, next_policy: Variant = null) -> Dictionary:
	if status == "surrendered": return _no("Encounter ended")
	if not setups is Array: return _no("Invalid ship batch")
	var prepared = []; var ids = []
	for setup in setups:
		if not setup is Dictionary or setup.get("id") in ids: return _no("Duplicate ship identity")
		ids.append(setup.get("id"))
		var existing = _ship(setup.get("id", ""))
		if not existing.is_empty() and setup.get("kind") != existing.state.kind: return _no("Cannot replace live hull")
		if not existing.is_empty() and existing.sunk and setup.get("hull", 0) > 0: return _no("Cannot resurrect sunk ship")
		var state = _validated_update(existing, setup) if not existing.is_empty() else _normalize(setup)
		if state.is_empty(): return _no(last_error)
		if config.has("oceanWaves") and not is_finite(ocean.heave_excursion + state.dimensions.draft * 2): return _no("Invalid ship draft travel limit")
		var created = _create_ship(setup) if existing.is_empty() else {}
		if existing.is_empty() and created.is_empty(): return _no(last_error)
		var physics = _prepare_physics_update(existing, state) if not existing.is_empty() else null
		if not existing.is_empty() and physics == null: return _no(last_error)
		prepared.append({"setup": setup, "existing": existing, "state": state, "created": created, "physics": physics})
	var candidate_policy = policy if next_policy == null else next_policy
	if next_policy != null and not _valid_policy(next_policy, ids): return _no(last_error)
	if next_policy != null and next_policy.has("fireEnvironment") and not _valid_fire_environment(next_policy.fireEnvironment, ids): return _no("Invalid fire environment")
	if not prepared.any(func(p): return p.setup.id == player_id and p.setup.team == "player"): return _no("Batch must retain player ship")
	var anchors = next_policy.get("anchorShipIds", []) if next_policy != null else []
	if not anchors.is_empty() and not _continuous(): return _no("Atomic service anchor requires continuous mode")
	if not anchors.is_empty() and has_pending_attacks(): return _no("Pending attacks prevent service anchor")
	for id in anchors:
		var entry = prepared.filter(func(p): return p.setup.id == id)[0]
		if entry.state.hull <= 0 or entry.state.team == "hostile": return _no("Service ship is not operational")
		var p = _visual(entry.existing if not entry.existing.is_empty() else entry.created).position
		for other in prepared:
			var s = other.state
			if s.hull > 0 and not s.id in candidate_policy.get("capturedShipIds", []) and id in candidate_policy.get("hostileTargets", {}).get(s.id, []):
				if _distance(_visual(other.existing if not other.existing.is_empty() else other.created).position, p) <= 600: return _no("Hostile threat prevents service anchor")
	if next_policy != null and next_policy.has("orders"):
		if not _continuous() or not next_policy.orders is Array or next_policy.orders.size() > 4096: return _no("Invalid staged orders")
		var order_ids = []
		for order in next_policy.orders:
			if not Orders.valid_order(order): return _no("Invalid staged order")
			if order.id in order_ids: return _no("Invalid staged orders")
			order_ids.append(order.id)
			var fleet = []
			for id in order.shipIds:
				var entries = prepared.filter(func(p): return p.setup.id == id)
				if entries.is_empty() or not id in candidate_policy.controllableShipIds or id in candidate_policy.get("lockedShipIds", []) or id in candidate_policy.get("disabledMotionShipIds", []) or entries[0].state.hull <= 0 or entries[0].state.crew <= 0: return _no("Staged ship not authorized")
				fleet.append(entries[0])
			var targets = prepared.filter(func(p): return p.setup.id == order.intent.get("targetId", ""))
			var target = targets[0] if not targets.is_empty() else {}
			if order.intent.has("targetId") and (target.is_empty() or target.state.hull <= 0 or target.setup.id in candidate_policy.get("capturedShipIds", []) or target.setup.id in order.shipIds): return _no("Staged target unavailable")
			for entry in fleet:
				if not target.is_empty():
					var hostile = target.setup.id in candidate_policy.get("hostileTargets", {}).get(entry.setup.id, [])
					if hostile if order.intent.kind == "protect" else not hostile: return _no("Invalid staged hostile relation")
				var point = order.intent.point if order.intent.kind == "rally" else _visual(target.existing if not target.existing.is_empty() else target.created).position
				var body = (entry.existing if not entry.existing.is_empty() else entry.created).duplicate()
				body.state = entry.state
				if not _safe_point(body, point): return _no("unsafe-depth")
	var next_ships = []
	for entry in prepared:
		if not entry.existing.is_empty(): _apply_update(entry.existing, entry.state, entry.setup, entry.physics); next_ships.append(entry.existing)
		else: next_ships.append(entry.created)
	ships = next_ships
	policy = candidate_policy.duplicate(true); policy.anchorShipIds = []
	if next_policy != null and next_policy.has("fireEnvironment"): config.fireEnvironment = next_policy.fireEnvironment.duplicate(true)
	for ship in ships:
		if ship.has("terminalStop") and not _terminal_stop_authorized(ship):_clear_terminal_stop(ship)
	if next_policy != null and next_policy.has("navigation"):
		for ship in ships:
			if next_policy.navigation.has(ship.state.id) and not hasActiveOrder(ship.state.id) and not ship.state.id in policy.get("lockedShipIds", []):
				var point = next_policy.navigation[ship.state.id]
				_clear_terminal_stop(ship)
				if point != ship.state.get("navigation"):
					if ship.has("wetRouteEgress"):
						ship.erase("wetRouteEgress");ship.state.rudder=0;ship.state.sailDeployment=0;ship.sailRecovery=0
					ship.erase("approachRecovery"); ship.erase("approachManualOverride"); ship.erase("egressRevokedGoal");ship.erase("egressRetryAt")
				if point != null: ship.state.navigation = point.duplicate(true)
				else: ship.state.erase("navigation"); ship.erase("tack")
	for id in anchors + policy.get("lockedShipIds", []): _stop_service(_ship(id))
	if next_policy != null and next_policy.has("orders"):
		for ship in ships:_clear_terminal_stop(ship)
		orders.clear(); decisions.clear()
		for order in next_policy.orders: orders[order.id] = {"order": order.duplicate(true), "participants": order.shipIds.duplicate(), "status": {"id": order.id, "state": "active"}}
	for ship in ships:
		if ship.state.id in policy.get("disabledMotionShipIds", []): _disable_motion(ship)
		if not _manual_reason(ship).is_empty(): ship.erase("manualHandling")
	volleys = volleys.filter(func(v): return v.shipId in ids)
	if not _continuous() and status != "defeat":
		if ships.any(func(s): return s.state.team == "hostile" and not s.sunk): status = "active"
		elif status == "active": status = "sailing"
	_finish(); return _ok()
func reconcileShips(setups: Variant, next_policy: Variant = null) -> Dictionary: return reconcile_ships(setups, next_policy)
func reconcile(setups: Variant, next_policy: Variant = null) -> Dictionary: return reconcile_ships(setups, next_policy)
func _manual_reason(ship: Dictionary, replace_navigation: bool = false) -> String:
	if ship.state.id != player_id or ship.state.team != "player" or not _controlled(ship.state.id) or ship.state.id in policy.get("capturedShipIds", []) or ship.state.id in policy.get("lockedShipIds", []): return "Ship not authorized"
	if ship.sunk or ship.state.hull <= 0 or ship.state.crew <= 0: return "Ship not operational"
	if status in ["surrendered", "defeat", "victory"]: return "Encounter ended"
	if not replace_navigation and (ship.state.has("navigation") or hasActiveOrder(ship.state.id)): return "navigation-active"
	return ""
func manual_control_permission(id: String, replace_navigation: bool = false) -> Dictionary:
	var ship: Dictionary = _ship(id)
	if ship.is_empty(): return _no("Unknown ship")
	var reason: String = _manual_reason(ship, replace_navigation)
	return _ok() if reason.is_empty() else _no(reason)
func set_manual_handling(id: String, request: Variant) -> Dictionary:
	var ship = _ship(id)
	if ship.is_empty(): return _no("Unknown ship")
	ship.erase("manualHandling")
	if request == null: return _ok()
	if not request is Dictionary or request.get("mode") != "assisted" or not [request.get("turnIntent"), request.get("sailIntent")].all(_finite) or absf(request.turnIntent) > 1 or request.sailIntent < 0 or request.sailIntent > 1 or not request.get("braking") is bool or not request.get("recovery") is bool or request.has("casual") and not request.casual is bool: return _no("Invalid manual handling")
	var reason = _manual_reason(ship)
	if not reason.is_empty(): return _no(reason)
	ship.manualHandling = request.duplicate(true); return _ok()
func setManualHandling(id: String, request: Variant) -> Dictionary: return set_manual_handling(id, request)
func find_manual_recovery_heading(id: String) -> Dictionary:
	var ship = _ship(id)
	if ship.is_empty(): return _no("Unknown ship")
	var reason = _manual_reason(ship)
	if not reason.is_empty(): return _no(reason)
	if wind.speed <= 0 or wind.direction.x * wind.direction.x + wind.direction.y * wind.direction.y == 0: return _no("no-wind")
	var v = _visual(ship); var wind_from = atan2(wind.direction.y, wind.direction.x)
	var headings = [wind_from - PI / 3, wind_from + PI / 3]
	headings.sort_custom(func(a, b): return absf(_wrap(a - v.heading)) < absf(_wrap(b - v.heading)))
	for heading in headings:
		var rotation = _wrap(heading - v.heading)
		var steps = maxi(1, int(ceil(absf(rotation) / (PI / 18))))
		var wet = [0, 15, 30, 45].all(func(ahead): return _wet_hull(ship, v.position.x + cos(heading) * ahead, v.position.z + sin(heading) * ahead, heading))
		for index in steps + 1:
			if wet: wet = _wet_hull(ship, v.position.x, v.position.z, v.heading + rotation * index / steps)
		if wet: return {"ok": true, "heading": _wrap(heading)}
	return _no("unsafe-depth")
func findManualRecoveryHeading(id: String) -> Dictionary: return find_manual_recovery_heading(id)
