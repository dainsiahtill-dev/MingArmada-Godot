extends RefCounted
## Story campaign runtime. Domain owns money/ships/cargo; Native owns sea
## motion/combat; Progress owns stage contracts. The runtime binds scenario
## entities, routes operation intents (never outcomes), re-attaches native
## state for settle-time gate checks, and feeds the fact adapter.
const World = preload("res://game/domain/story_world/story_world_session.gd")
const Rules = preload("res://game/domain/story_world/story_rules.gd")
const StorySave = preload("res://game/domain/story_world/story_save.gd")
const Scenarios = preload("res://game/domain/story_campaign/scenarios.gd")
const FactAdapter = preload("res://game/domain/story_campaign/fact_adapter.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const Coordinator = preload("res://game/runtime/story_encounter_coordinator.gd")
const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const PAUSES := ["player", "panel", "menu", "encounter", "result", "error"]
const BUSINESS := ["dock", "depart", "buy", "sell", "deliver", "repair", "recruit", "buy-ship", "transfer-cargo", "transfer-crew", "sign-on", "identify-target", "resolve-boarding", "resolve-land", "sign-charter", "sign-terms", "load-manifest", "handover-facilities", "transfer-manifest", "dispatch-convoy", "return-dispatch", "withdraw", "rescue", "open-blockade", "breach-blockade", "verify-blockade", "close-blockade", "relations-delta", "mint-grant", "advance-day", "open-contract", "close-contract", "store-goods", "withdraw-goods", "upgrade", "attend-banquet", "gather-intel", "set-formation", "assign-escort", "release-escort", "set-weather", "treat-wounded"]
const SEA := ["set-sails", "trim", "navigate", "native-action", "set-held"]
const PROGRESS_INTENTS := ["begin-stage", "settle-stage", "continue-story", "retry-stage", "transition"]

var world: RefCounted
var progress: RefCounted
var simulation: RefCounted
var encounter_coordinator: RefCounted
var _traffic_setups: Dictionary = {}
var _traffic_routes: Dictionary = {}
var _traffic_targets: Dictionary = {}
# Fixture-only acceleration so headless voyages fit runner budgets. Gameplay
# keeps 1.0; walkthroughs and category tests raise it and document the fact.
var fixture_speed_multiplier := 1.0
# Fixture-only reload acceleration for headless live-fire engagements; the
# ballistics, arcs, reloads and damage remain the real native gunnery.
var fixture_reload_multiplier := 1.0
# Fixture-only calm sea (no wave drift) so posed fleets meet the real dock gate.
var fixture_calm_sea := false
# Fixture-only: skip ambient route traders in tick-heavy tests (they have a
# dedicated traffic test; production keeps them on).
var fixture_no_traffic := false
var _height: Callable
var _waves: RefCounted
var _generation := 0
var _revision := 0
var _pauses: Dictionary = {}
var _notice := ""
var _disposed := false
var _entity_setups: Dictionary = {}
var _nav_targets: Dictionary = {}
var _run_id := "story"

static func _no(reason: String) -> Dictionary: return {"ok": false, "reason": reason}
static func validate_save(raw: String) -> Dictionary: return StorySave.validate(raw)

func configure(height_sampler: Callable, options: Dictionary = {}) -> Dictionary:
	if not height_sampler.is_valid(): return _no("invalid-terrain-sampler")
	_run_id = str(options.get("runId", "story"))
	var seed_value: int = int(options.get("seed", 1661)) & 0x7FFFFFFF
	var opening: Dictionary = Scenarios.opening()
	if opening.is_empty(): return _no("scenario-opening-unavailable")
	var candidate: RefCounted = World.new()
	var configured: Dictionary = candidate.call("configure", opening, seed_value, _run_id)
	if not configured.ok: return _no(str(configured.reason))
	var script: GDScript = load(PROGRESS_PATH)
	var contract: RefCounted = script.new()
	if not contract.call("configure", seed_value, _run_id).get("ok", false): return _no("progress-configure-failed")
	_height = height_sampler
	_waves = Waves.new()
	_waves.configure(_height)
	world = candidate
	progress = contract
	_generation += 1
	_revision = 0
	_pauses.clear()
	_disposed = false
	_notice = ""
	encounter_coordinator = Coordinator.new(self)
	_build_traffic()
	_bind_stage()
	var built := _build()
	if not built.ok: return built
	simulation = built.simulation
	if not str(world.state.currentPortId).is_empty():
		simulation.encounter.anchorFleet(world.state.fleet.map(func(s): return s.id))
		simulation.refresh_snapshot()
		world.call("attach_native", simulation.snapshot())
	return {"ok": true}

# --- scenario binding -------------------------------------------------------

func _current_stage() -> Dictionary:
	var inspection: Dictionary = progress.call("inspection_snapshot")
	return inspection.currentStage

func _current_scenario() -> Dictionary:
	var stage := _current_stage()
	return Scenarios.scenario(str(stage.get("id", ""))) if not stage.is_empty() else {}

func _bind_stage() -> Dictionary:
	var scenario := _current_scenario()
	var stage := _current_stage()
	_entity_setups.clear()
	_nav_targets.clear()
	_restore_traffic_targets()
	if scenario.is_empty(): return _no("scenario-unavailable")
	# Difficulty axis: the chapter's pressure tier scales hostile composition
	# and world upkeep (doc 38 four-axis difficulty).
	var tier := 1
	if stage.has("difficulty"):
		tier = clampi(int(stage.difficulty.get("tier", 1)), 1, 6)
	world.call("command", {"type": "set-difficulty", "tier": tier})
	if scenario.has("weather"):
		world.call("command", {"type": "set-weather", "sea": str(scenario.get("weather", "breeze"))})
	var escort_bonus: float = Rules.escort_speed_bonus(world.call("_roles"))
	var sail_cap: float = Rules.weather_sail_cap(str(scenario.get("weather", world.state.weather.get("sea", "breeze"))))
	for entity: Dictionary in scenario.entities:
		var kind := str(entity.kind)
		if ["garrison", "facility", "group", "route", "watch", "depot"].has(kind):
			var spawned: Dictionary = world.call("command", {"type": "spawn-entity", "entity": entity})
			if not spawned.ok: return spawned
			continue
		var position: Dictionary = _spawn_position(entity)
		var profile: Dictionary = {"hull": 100, "crew": 0, "sail": 100}
		profile.merge(entity.get("setup", {}), true)
		var hull := int(profile.hull)
		var crew := int(profile.crew)
		if str(entity.team) == "hostile":
			hull = clampi(hull + tier * 3, 1, 100)
			crew += tier * 2
		_entity_setups[str(entity.id)] = {"id": str(entity.id), "name": str(entity.name), "kind": kind, "team": str(entity.team), "position": position, "heading": float(entity.spawn.get("heading", 0.0)), "speed": float(entity.spawn.get("speed", 0.0)), "hull": hull, "sail": int(profile.sail), "crew": crew, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "stats": {"maxHull": 100, "maxCrew": 100, "cannonMultiplier": 1.0, "speedMultiplier": minf(fixture_speed_multiplier + escort_bonus, 2.0)}, "sailDeployment": minf(1.0, sail_cap)}
		var identity: Dictionary = entity.get("identity", {})
		if not identity.is_empty():
			_entity_setups[str(entity.id)].identity = identity.duplicate(true)
	for objective_id: Variant in scenario.settlements:
		var settlement: Dictionary = scenario.settlements[objective_id]
		if str(settlement.kind) == "escort-arrived" and _entity_setups.has(str(settlement.targetId)):
			var destination: Dictionary = world.state.ports.get(str(settlement.destinationPortId), {})
			if not destination.is_empty():
				_nav_targets[str(settlement.targetId)] = {"x": float(destination.x), "z": float(destination.z)}
		if str(settlement.kind) == "trade-profit":
			world.call("command", {"type": "open-contract", "contractId": str(settlement.contractId), "kind": "trade-profit"})
	return {"ok": true}

func _spawn_position(entity: Dictionary) -> Dictionary:
	var spawn: Dictionary = entity.get("spawn", {})
	if spawn.has("point"):
		return {"x": float(spawn.point.x), "z": float(spawn.point.z)}
	var port: Dictionary = world.state.ports.get(str(spawn.get("portId", world.state.currentPortId)), {})
	if port.is_empty():
		return {"x": 0.0, "z": 0.0}
	return {"x": float(port.x) + 40.0, "z": float(port.z) + 40.0}

# --- native composition -----------------------------------------------------

func _fleet_setup(ship: Dictionary) -> Dictionary:
	# Companion specialties and ship upgrades shape the live stats: navigators
	# master passages, gunners crew batteries faster, shipyard levels raise
	# hull caps, guns, speed and steering (bounded by the native engine caps).
	var roles: Array = []
	for person: Dictionary in world.state.people:
		roles.append(str(person.get("role", "")))
	var upgrades: Dictionary = ship.get("upgrades", {})
	var speed_factor: float = minf(fixture_speed_multiplier * Rules.speed_multiplier(roles) * pow(1.08, float(int(upgrades.get("sails", 0)))), 2.0)
	var reload_factor: float = fixture_reload_multiplier * Rules.reload_multiplier(roles)
	var sail_cap: float = Rules.weather_sail_cap(str(world.state.weather.get("sea", "breeze")))
	return {"id": ship.id, "name": ship.name, "kind": ship.kind, "team": "player", "position": ship.position.duplicate(true), "heading": float(ship.heading), "speed": float(ship.speed), "hull": int(ship.hull), "sail": int(ship.sail), "crew": int(ship.crew), "ammo": {"solid": 40, "chain": 24, "grape": 24}, "stats": {"hullMultiplier": pow(1.2, float(int(upgrades.get("hull", 0)))), "maxHull": int(ship.maxHull), "maxCrew": int(ship.maxCrew), "cannonMultiplier": pow(1.15, float(int(upgrades.get("cannons", 0)))), "reloadMultiplier": reload_factor, "steeringMultiplier": 1.0 + 0.15 * float(int(upgrades.get("equipment", 0))), "speedMultiplier": speed_factor}, "sailDeployment": 0.0 if not str(world.state.currentPortId).is_empty() else minf(1.0, sail_cap)}

func _sync_entity_damage() -> void:
	# Live native state is battle authority: a roster rebuild must carry real
	# hull/sail/crew damage forward or sunk ships would resurrect at departures.
	if not simulation or _entity_setups.is_empty():
		return
	var native: Dictionary = simulation.snapshot()
	for entry: Dictionary in native.ships:
		var id := str(entry.id)
		if _entity_setups.has(id):
			_entity_setups[id].hull = int(entry.hull)
			_entity_setups[id].sail = int(entry.sail)
			_entity_setups[id].crew = int(entry.crew)

func _setups() -> Array:
	var setups: Array = []
	for ship: Dictionary in world.state.fleet:
		setups.append(_fleet_setup(ship))
	for id: Variant in _entity_setups:
		setups.append((_entity_setups[id] as Dictionary).duplicate(true))
	for id: Variant in _traffic_setups:
		setups.append((_traffic_setups[id] as Dictionary).duplicate(true))
	return setups

func _build_traffic() -> void:
	# Living sea traffic: one trader per declared route, endlessly plying
	# between its two ports (positions reset on roster rebuild — the traders
	# simply resume their run).
	_traffic_setups.clear()
	_traffic_routes.clear()
	_traffic_targets.clear()
	if fixture_no_traffic:
		return
	var geo: Dictionary = Scenarios.geography()
	for pair: Array in geo.get("data", {}).get("tradeRoutes", []):
		var from_port: Dictionary = world.state.ports.get(str(pair[0]), {})
		var to_port: Dictionary = world.state.ports.get(str(pair[1]), {})
		if from_port.is_empty() or to_port.is_empty():
			continue
		var id := "traffic-%s-%s" % [str(pair[0]), str(pair[1])]
		_traffic_setups[id] = {"id": id, "name": "商路客舟", "kind": "merchant", "team": "neutral", "position": {"x": float(from_port.x) + 30.0, "z": float(from_port.z) + 30.0}, "heading": 0.0, "speed": 0.0, "hull": 100, "sail": 100, "crew": 20, "ammo": {"solid": 0, "chain": 0, "grape": 0}, "stats": {"maxHull": 100, "maxCrew": 70, "cannonMultiplier": 1.0, "speedMultiplier": fixture_speed_multiplier}, "sailDeployment": minf(1.0, Rules.weather_sail_cap(str(world.state.weather.get("sea", "breeze"))))}
		_traffic_routes[id] = {"a": {"x": float(from_port.x), "z": float(from_port.z)}, "b": {"x": float(to_port.x), "z": float(to_port.z)}}
		_traffic_targets[id] = _traffic_routes[id].b.duplicate(true)
		_nav_targets[id] = _traffic_targets[id].duplicate(true)

func _restore_traffic_targets() -> void:
	for id: Variant in _traffic_targets:
		_nav_targets[id] = (_traffic_targets[id] as Dictionary).duplicate(true)

func _build(sync_damage: bool = true) -> Dictionary:
	if sync_damage and simulation != null:
		_sync_entity_damage()
	var descriptors: Array = Descriptor.original_descriptors()
	for wave: Dictionary in descriptors: wave.direction = {"x": wave.direction.x, "y": wave.direction.z}
	if fixture_calm_sea:
		descriptors = []
	var wind: Dictionary = Rules.weather_wind(str(world.state.weather.get("sea", "breeze")))
	if fixture_calm_sea:
		wind = {"x": 1.0, "y": 0.2, "speed": 4.0}
	var native := Encounter.new({"playerId": str(world.state.flagshipId), "ships": _setups(), "seed": int(world.state.seed), "wind": {"direction": {"x": float(wind.x), "y": float(wind.y)}, "speed": float(wind.speed)}, "battleId": "story-%d-%d" % [_generation, Time.get_ticks_usec()], "sampleTerrainHeight": _height, "oceanWaves": descriptors, "waveSampler": _waves})
	if not native.last_error.is_empty(): return _no(str(native.last_error))
	return {"ok": true, "simulation": Simulation.new(native)}

func _reconcile() -> Dictionary:
	if not simulation: return _no("runtime-disposed")
	var result: Dictionary = simulation.encounter.reconcileShips(_setups())
	if not result.ok: return result
	result = simulation.encounter.setPlayerId(str(world.state.flagshipId))
	simulation.refresh_snapshot()
	_update_navigation(true)
	world.call("attach_native", simulation.snapshot())
	return result

func _update_navigation(force: bool = false) -> void:
	if not simulation: return
	var native: Dictionary = simulation.snapshot()
	var player_id := str(world.state.flagshipId)
	var player: Dictionary = {}
	for entry: Dictionary in native.ships:
		if str(entry.id) == player_id: player = entry
	if player.is_empty(): return
	var formation := str(world.state.orders.get("formation", "line"))
	var escorts: Dictionary = world.state.orders.get("escorts", {})
	var ally := 0
	for ship: Dictionary in native.ships:
		if str(ship.id) == player_id or int(ship.hull) <= 0: continue
		var target = null
		if _traffic_routes.has(str(ship.id)):
			# Living traffic: flip to the far endpoint on arrival.
			var goal: Dictionary = _traffic_targets[str(ship.id)]
			var here: Dictionary = ship.visual.position
			if _distance(here, goal) <= 90.0:
				var route: Dictionary = _traffic_routes[str(ship.id)]
				var next_stop: Dictionary = route.a if _distance(here, route.a) > 90.0 else route.b
				_traffic_targets[str(ship.id)] = next_stop.duplicate(true)
				goal = next_stop
			target = goal
		elif escorts.has(str(ship.id)):
			# Fleet order: shadow the assigned ship's live position.
			var charge := _native_entry(native, str(escorts[str(ship.id)]))
			if not charge.is_empty():
				target = {"x": float(charge.visual.position.x), "z": float(charge.visual.position.z)}
		elif _nav_targets.has(str(ship.id)):
			target = _nav_targets[str(ship.id)]
		elif str(ship.team) == "player":
			ally += 1
			var lateral: float
			var behind: float
			match formation:
				"abreast":
					lateral = 48.0 * ally * (1 if ally % 2 else -1)
					behind = 0.0
				"convoy":
					lateral = 20.0 * (1 if ally % 2 else -1)
					behind = 30.0 * int(ceil(ally / 2.0))
				_:
					lateral = 32.0 * (1 if ally % 2 else -1)
					behind = 48.0 * int(ceil(ally / 2.0))
			var heading: float = float(player.visual.heading)
			target = {"x": float(player.visual.position.x) - cos(heading) * behind - sin(heading) * lateral, "z": float(player.visual.position.z) - sin(heading) * behind + cos(heading) * lateral}
		if target != null:
			simulation.encounter.navigate(str(ship.id), target)
	simulation.refresh_snapshot()

func _native_entry(native: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in native.get("ships", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}

static func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a.get("x", 0.0)) - float(b.get("x", 0.0))
	var dz := float(a.get("z", 0.0)) - float(b.get("z", 0.0))
	return sqrt(dx * dx + dz * dz)

# --- intent surface ---------------------------------------------------------

func set_pause(reason: String, active: bool) -> Dictionary:
	if _disposed or not simulation: return _no("runtime-disposed")
	if not reason in PAUSES: return _no("invalid-pause-reason")
	if active: _pauses[reason] = true
	else: _pauses.erase(reason)
	simulation.set_paused(is_paused() or not str(world.state.currentPortId).is_empty())
	return {"ok": true}

func is_paused() -> bool: return not _pauses.is_empty()
func pause_reasons() -> Array: return _pauses.keys()
func notify(message: String) -> void: _notice = message

func set_handling_mode(mode: String) -> Dictionary:
	if not mode in ["assisted", "realistic"]:
		return _no("invalid-handling-mode")
	if simulation:
		simulation.set_handling_mode(mode)
	return {"ok": true}

func set_held(code: String, active: bool) -> Dictionary:
	return command({"type": "set-held", "code": code, "active": active})

func preview_command(input: Dictionary) -> Dictionary:
	if _disposed or not world: return _no("runtime-disposed")
	if not input is Dictionary or not input.get("type") is String: return _no("无效操作")
	return {"ok": true}

func command(input: Dictionary) -> Dictionary:
	if _disposed or not world or not simulation: return _no("runtime-disposed")
	if not input is Dictionary or not input.get("type") is String: return _no("无效操作")
	for forged: String in ["outcome", "success", "score", "reward"]:
		if input.has(forged): return _no("forged-world-result")
	var type: String = str(input.type)
	if type == "pause": return set_pause(str(input.get("reason", "player")), bool(input.get("value", true)))
	if type in SEA: return _sea(type, input)
	if type == "start-encounter": return encounter_coordinator.start(input)
	if type.begins_with("encounter-"): return encounter_coordinator.command(input)
	if type in PROGRESS_INTENTS: return _progress_intent(type, input)
	if type in BUSINESS: return _business(input)
	return _no("未知操作")

func _sea(type: String, input: Dictionary) -> Dictionary:
	if type == "set-held" and not bool(input.get("active", true)):
		# Releasing a held control must always land, even while docked/paused.
		simulation.set_held(str(input.get("code", "")), false)
		return {"ok": true}
	if not str(world.state.currentPortId).is_empty(): return _no("请先出港并继续航程")
	if type == "set-sails":
		var value = input.get("value")
		if not value is float and not value is int: return _no("invalid-sails")
		simulation.set_sails(clampf(float(value), 0.0, 1.0))
		return {"ok": true}
	if type == "trim":
		simulation.toggle_trim()
		return {"ok": true}
	if type == "set-held":
		if not input.get("code") is String or not input.get("active") is bool: return _no("invalid-held-control")
		simulation.set_held(str(input.code), input.active)
		return {"ok": true}
	if type == "navigate":
		var result: Dictionary = simulation.encounter.navigate(str(world.state.flagshipId), input.get("point"))
		if result.ok: simulation.refresh_snapshot(); _flush()
		return result
	var action = input.get("action", input.get("command"))
	if not action is Dictionary: return _no("invalid-native-action")
	# Fire/ammo/controls need no immediate world flush; the throttled clock
	# flush keeps gate state fresh without a full snapshot per shot.
	return simulation.encounter.command(action)

func _business(input: Dictionary) -> Dictionary:
	if encounter_coordinator and encounter_coordinator.has_active() and not str(input.type).begins_with("resolve-"): return _no("请先完成当前挑战")
	if str(input.type) == "identify-target":
		return _identify(str(input.get("shipId", "")))
	_flush()
	var request := input.duplicate(true)
	request.erase("type")
	request["type"] = input.type
	# Misstep policy: capturing the wrong designated target earns no credit and
	# costs standing; the fact adapter already refuses objective credit.
	var result: Dictionary = world.call("command", request)
	if not result.ok: return result
	if str(input.type) == "resolve-boarding" and bool(input.get("captured", false)):
		var scenario := _current_scenario()
		var policy: Dictionary = scenario.get("misstepPolicy", {})
		if not policy.is_empty() and str(input.get("targetId", "")) == str(policy.get("wrongTargetId", "")):
			world.call("command", {"type": "relations-delta", "faction": "voc", "delta": -10})
			_notice = "误认目标：此船不计本阶段战果"
	if str(input.type) in ["dock"]:
		var reconciled := _reconcile()
		if not reconciled.ok: return reconciled
		simulation.encounter.anchorFleet(world.state.fleet.map(func(s): return s.id))
		simulation.refresh_snapshot()
	elif str(input.type) in ["depart", "buy-ship", "recruit", "transfer-crew", "repair", "resolve-boarding", "transfer-cargo", "set-weather"]:
		# Business changes crew/cargo/ships; the native roster is rebuilt from
		# the world so stale native values cannot clobber the domain (legacy
		# rebuilds on depart for the same reason).
		var reseated := _reseat()
		if not reseated.ok: return reseated
	simulation.set_paused(is_paused() or not str(world.state.currentPortId).is_empty())
	_revision += 1
	_flush()
	return result

func settle_encounter(request: Dictionary) -> Dictionary:
	return _business(request)

func _reseat() -> Dictionary:
	var built := _build()
	if not built.ok: return built
	simulation = built.simulation
	if not str(world.state.currentPortId).is_empty():
		simulation.encounter.anchorFleet(world.state.fleet.map(func(s): return s.id))
	simulation.refresh_snapshot()
	world.call("attach_native", simulation.snapshot())
	return {"ok": true}

func _identify(ship_id: String) -> Dictionary:
	var setup: Dictionary = _entity_setups.get(ship_id, {})
	if setup.is_empty(): return _no("目标不在视野内")
	var native: Dictionary = native_snapshot()
	var own: Dictionary = {}
	var target: Dictionary = {}
	for entry: Dictionary in native.ships:
		if str(entry.id) == str(world.state.flagshipId): own = entry
		if str(entry.id) == ship_id: target = entry
	if own.is_empty() or target.is_empty(): return _no("目标不在视野内")
	var dx := float(own.visual.position.x) - float(target.visual.position.x)
	var dz := float(own.visual.position.z) - float(target.visual.position.z)
	if sqrt(dx * dx + dz * dz) > Rules.identify_radius(world.call("_roles")): return _no("距离过远，无法核认目标")
	return {"ok": true, "shipId": ship_id, "name": str(setup.name), "team": str(setup.team), "identity": (setup.get("identity", {}) as Dictionary).duplicate(true)}

func _progress_intent(type: String, input: Dictionary) -> Dictionary:
	var state: Dictionary = progress.call("snapshot")
	var revision: int = int(state.revision)
	if type == "begin-stage":
		var begun: Dictionary = progress.call("begin", revision)
		if not begun.ok: return begun
		var rebound := _bind_stage()
		if not rebound.ok: return rebound
		_revision += 1
		return begun
	if type == "settle-stage":
		_flush()
		var stage := _current_stage()
		var scenario := _current_scenario()
		var settled: Dictionary = FactAdapter.settle(stage, scenario, world.call("snapshot"), simulation.snapshot(), bool(input.get("retreat", false)))
		var batch: Array = FactAdapter.facts(stage, scenario, world.call("snapshot"), simulation.snapshot(), _run_id, int(state.attempt))
		if not batch.is_empty():
			progress.call("observe", batch)
		var result: Dictionary = progress.call("settle", progress.call("snapshot").revision, str(settled.outcome), bool(settled.safe))
		if result.ok:
			result.witnesses = settled.witnesses
			result.outcome = settled.outcome
		_revision += 1
		return result
	if type == "continue-story":
		var continued: Dictionary = progress.call("continue_story", revision)
		if not continued.ok: return continued
		_revision += 1
		return continued
	if type == "retry-stage":
		var retried: Dictionary = progress.call("retry", revision)
		if not retried.ok: return retried
		var rebound := _bind_stage()
		if not rebound.ok: return rebound
		_revision += 1
		return retried
	if type == "transition":
		var scenario := _current_scenario()
		var transition: Dictionary = scenario.get("transition", {})
		if transition.is_empty(): return _no("本章没有转场")
		var year: int = int(transition.get("yearMarker", world.state.yearMarker))
		var applied: Dictionary = world.call("command", {"type": "transition", "yearMarker": year, "to": str(transition.get("to", "")), "note": str(transition.get("note", ""))})
		if not applied.ok: return applied
		simulation.encounter.anchorFleet(world.state.fleet.map(func(s): return s.id))
		simulation.refresh_snapshot()
		world.call("attach_native", simulation.snapshot())
		_revision += 1
		return {"ok": true, "transition": transition.duplicate(true)}
	return _no("unknown-progress-intent")

# --- clocks -----------------------------------------------------------------

func _flush() -> void:
	if not simulation or not world: return
	simulation.refresh_snapshot()
	var native: Dictionary = simulation.snapshot()
	world.call("attach_native", native)
	var state: Dictionary = progress.call("snapshot")
	if str(state.get("phase", "")) == "active":
		var stage := _current_stage()
		var scenario := _current_scenario()
		if not stage.is_empty() and not scenario.is_empty():
			var batch: Array = FactAdapter.facts(stage, scenario, world.state, native, _run_id, int(state.attempt))
			if not batch.is_empty():
				progress.call("observe", batch)

var _last_flush := -INF
var _last_nav := -INF
var _sim_time := 0.0

func advance(seconds: float) -> float:
	if _disposed or not simulation or not is_finite(seconds) or seconds <= 0: return 0
	if encounter_coordinator and encounter_coordinator.has_active():
		return encounter_coordinator.advance(seconds)
	if is_paused() or not str(world.state.currentPortId).is_empty(): return 0
	simulation.advance(seconds)
	_sim_time += seconds
	if _sim_time - _last_flush >= 0.25:
		_flush()
		_last_flush = _sim_time
	if _sim_time - _last_nav >= 0.5:
		_update_navigation()
		_last_nav = _sim_time
	return seconds

func step_fixed() -> float:
	return advance(1.0 / 60.0)

# --- snapshots & persistence ------------------------------------------------

func native_snapshot() -> Dictionary: return simulation.snapshot() if simulation else {}
func render_snapshot() -> Dictionary: return simulation.render_snapshot() if simulation else {}

func voyage_summary() -> Dictionary:
	# The epilogue ledger: what the two generations actually left behind,
	# assembled from the live world and the real settlement receipts.
	if world == null or progress == null:
		return {}
	var packet: Dictionary = world.call("snapshot")
	var state: Dictionary = progress.call("snapshot")
	var receipts: Array = state.get("receipts", [])
	var battles := 0
	var wounded := 0
	var crew := 0
	for record: Dictionary in packet.get("captures", []):
		battles += 1
	for ship: Dictionary in packet.get("fleet", []):
		crew += int(ship.get("crew", 0))
		wounded += int(ship.get("wounded", 0))
	var successes := 0
	for receipt: Dictionary in receipts:
		if str(receipt.get("outcome", "")) == "success":
			successes += 1
	# Six-act retrospective: which acts the two generations actually finished.
	var catalog: GDScript = load("res://game/domain/story_campaign/catalog.gd")
	var act_done := {}
	for receipt: Dictionary in receipts:
		if str(receipt.get("outcome", "")) == "success":
			var act := 0
			for row: Dictionary in catalog.call("stages"):
				if str(row.id) == str(receipt.get("stageId", "")):
					act = int(row.get("act", 0))
			if act > 0:
				act_done[act] = bool(act_done.get(act, true)) and _act_complete(catalog, act, receipts)
	var acts: Array = []
	for act in range(1, 7):
		var title := ""
		for row: Dictionary in catalog.call("stages"):
			if int(row.get("act", 0)) == act and str(row.get("chapterId", "")) != "":
				var chapter: Dictionary = catalog.call("chapter", str(row.chapterId))
				title = str(chapter.get("title", ""))
				break
		acts.append({"act": act, "title": title, "done": bool(act_done.get(act, false))})
	return {"days": int(packet.get("day", 0)), "silver": int(packet.get("silver", 0)), "fleet": (packet.get("fleet", []) as Array).size(), "crew": crew, "wounded": wounded, "people": (packet.get("people", []) as Array).size(), "battles": battles, "permits": (packet.get("permits", []) as Array).size(), "agreements": (packet.get("agreements", []) as Array).size(), "stages": successes, "attempts": receipts.size(), "acts": acts, "protagonist": str(state.get("protagonistId", "")), "handoff": bool(state.get("handoff", {}).get("done", false)), "phase": str(state.get("phase", ""))}

static func _act_complete(catalog: GDScript, act: int, receipts: Array) -> bool:
	var needed := {}
	for row: Dictionary in catalog.call("stages"):
		if int(row.get("act", 0)) == act:
			needed[str(row.id)] = true
	for receipt: Dictionary in receipts:
		if str(receipt.get("outcome", "")) == "success":
			needed.erase(str(receipt.get("stageId", "")))
	return needed.is_empty()

func voyage_journal() -> Array:
	# The voyage memory: the opening line plus every real settlement receipt,
	# in order. This is the journey's own record — nothing decorative.
	var lines: Array = []
	if world == null or progress == null:
		return lines
	var packet: Dictionary = world.call("snapshot")
	for entry: Variant in packet.get("log", []):
		lines.append(str(entry))
	for receipt: Dictionary in progress.call("snapshot").get("receipts", []):
		var marks: Array = []
		for objective_id: Variant in receipt.get("objectiveProgress", {}):
			marks.append("%s=%s" % [str(objective_id), str(receipt.objectiveProgress[objective_id])])
		lines.append("%s · %s · 第%s次 · %s" % [str(receipt.get("stageId", "?")), str(receipt.get("outcome", "?")), str(receipt.get("attempt", 0)), " ".join(marks)])
	return lines
func sample_water_height(x: float, z: float, seconds: float = NAN) -> float:
	if _waves == null:
		return 0.0
	var time: float = seconds
	if is_nan(time):
		time = _sim_time
	return _waves.sample_height(x, z, time)

func snapshot() -> Dictionary:
	if not world or not progress: return {}
	_flush()
	return {"world": world.call("snapshot"), "native": native_snapshot(), "progress": progress.call("snapshot"), "runtime": {"generation": _generation, "revision": _revision, "paused": is_paused(), "pauseReasons": pause_reasons(), "notice": _notice, "stage": _current_stage(), "scenario": _current_scenario(), "summary": voyage_summary(), "journal": voyage_journal(), "encounter": encounter_coordinator.snapshot() if encounter_coordinator else null, "witnesses": FactAdapter.evaluate(_current_stage(), _current_scenario(), world.state, native_snapshot())}}.duplicate(true)

func save_checkpoint(_storage: RefCounted = null) -> Dictionary:
	_flush()
	var encoded: String = StorySave.encode(world.call("snapshot"), progress.call("serialize"))
	return {"ok": true, "json": encoded, "bytes": encoded.to_utf8_buffer().size()}

func adopt_save(raw: String, _storage: RefCounted = null, _persist: bool = true) -> Dictionary:
	var decoded: Dictionary = StorySave.decode(raw)
	if not decoded.ok: return decoded
	var candidate: RefCounted = World.new()
	if not candidate.call("restore", JSON.stringify(decoded.world)).ok: return _no("world-restore-failed")
	var script: GDScript = load(PROGRESS_PATH)
	var contract: RefCounted = script.new()
	if not contract.call("restore", decoded.progress).get("ok", false): return _no("progress-restore-failed")
	world = candidate
	progress = contract
	# The restored run identity governs fact binding: a restored session must
	# observe under the checkpoint's runId or every fact is refused.
	_run_id = str(world.state.runId)
	_entity_setups.clear()
	_nav_targets.clear()
	_bind_stage()
	var built := _build()
	if not built.ok: return built
	simulation = built.simulation
	if not str(world.state.currentPortId).is_empty():
		simulation.encounter.anchorFleet(world.state.fleet.map(func(s): return s.id))
	simulation.refresh_snapshot()
	world.call("attach_native", simulation.snapshot())
	_generation += 1
	_revision += 1
	return {"ok": true, "bytes": raw.to_utf8_buffer().size()}

func dispose() -> void:
	_disposed = true
	_generation += 1
	if encounter_coordinator: encounter_coordinator.dispose()
	if simulation: simulation.set_paused(true)
	encounter_coordinator = null
	simulation = null
	world = null
	progress = null
