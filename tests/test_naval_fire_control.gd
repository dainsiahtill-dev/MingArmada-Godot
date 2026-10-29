extends SceneTree
## Pending native integration contract. Run only after the isolated lab gate.
## Missing authority support must fail explicitly, rather than indexing absent fields.
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Sailing = preload("res://game/runtime/sailing_simulation.gd")
var failures: Array[String] = []
var assertions: int = 0

func _initialize() -> void:
	var legacy: RefCounted = _game(false)
	check(legacy.last_error.is_empty(), "legacy encounter still configures")
	check(not _ship(legacy.snapshot(), "p").has("fireControl"), "legacy setup adds no fireControl snapshot key")
	check(not _ship(legacy.snapshot(), "p").has("fireLauncher"), "legacy setup adds no fireLauncher snapshot key")
	check(not _ship(legacy.snapshot(), "p").has("availableCrew"), "legacy setup adds no derived crew snapshot key")
	check(_ship(legacy.snapshot(), "p").ammo.keys().size() == 3, "ordinary ammo remains the frozen three types")
	var probe: RefCounted = _game()
	check(probe.last_error.is_empty(), "explicit native fire extension configures")
	var player: Dictionary = _ship(probe.snapshot(), "p")
	var has_state: bool = player.get("fireControl") is Dictionary and player.get("fireLauncher") is Dictionary
	check(has_state, "NATIVE_FIRE_CONTROL_MISSING: normalize/snapshot must expose explicit extension")
	if not has_state:
		_finish()
		return
	var command: Dictionary = probe.command({"type":"fire-control", "shipId":"p", "crew":0})
	check(command.get("ok", false), "NATIVE_FIRE_CONTROL_MISSING: fire-control command must be accepted")
	if not command.get("ok", false):
		_finish()
		return
	_test_assignment_and_queue()
	_test_independent_launcher()
	_test_launcher_crew_reservation()
	_test_lazy_target_and_corridor()
	_test_miss_has_no_fire()
	_test_authority_damage_and_reconcile()
	_test_cannon_commitments()
	_test_validation_is_atomic()
	_test_fire_environment()
	_test_deterministic_clock()
	_finish()

func _fire(supplies: int = 60) -> Dictionary:
	return {"version":"ship-fire-r1", "heat":0.0, "fuelSeconds":0.0, "wetness":0.0, "crewDamageCarry":0.0,
		"assignedFirefighters":0, "pendingFirefighters":0, "transferTicks":0, "supplies":supplies, "workCarry":0.0}

func _setup(id: String, team: String, position: Dictionary, extended: bool = true) -> Dictionary:
	var setup: Dictionary = {"id":id, "kind":"fuchuan", "team":team, "position":position, "heading":0.0, "speed":0.0,
		"hull":100.0, "sail":100.0, "crew":100, "sailDeployment":0.0, "rudder":0.0, "sailAngle":0.0, "autoTrim":true,
		"ammo":{"solid":10, "chain":10, "grape":10}, "stats":{"maxHull":100, "maxCrew":100}}
	if extended:
		setup.fireControl = _fire()
		setup.fireLauncher = {"ammo":{"fire-ball":12, "thorn-ball":8}, "cooldownSeconds":0.0, "operationSeconds":0.0}
	return setup

func _config(setups: Array) -> Dictionary:
	return {"mode":"continuous", "playerId":"p", "seed":1650, "ships":setups, "oceanWaves":[], "referenceGunnery":true,
		"wind":{"direction":{"x":1.0, "y":0.0}, "speed":0.0}, "controllableShipIds":["p"], "hostileTargets":{"p":["e"], "e":[]}}

func _game(extended: bool = true, target_distance: float = 50.0) -> RefCounted:
	return Encounter.new(_config([_setup("p", "player", {"x":0.0, "z":0.0}, extended), _setup("e", "hostile", {"x":0.0, "z":target_distance}, extended)]))

func _ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships", []):
		if ship.id == id: return ship
	return {}

func _launch(game: RefCounted, payload: String = "fire-ball", target: String = "e", source: String = "p") -> Dictionary:
	return game.command({"type":"launch-fire", "shipId":source, "targetId":target, "payload":payload})

func _step(game: RefCounted, ticks: int) -> void:
	for tick in ticks: game.step_fixed()

func _test_assignment_and_queue() -> void:
	var game: RefCounted = _game()
	var before: Dictionary = _ship(game.snapshot(), "p")
	check(game.command({"type":"fire-control", "shipId":"p", "crew":20}).ok, "assignment accepted through native command")
	var assigned: Dictionary = _ship(game.snapshot(), "p")
	check(assigned.crew == before.crew, "assignment never subtracts living population")
	check(assigned.get("availableCrew") == 80, "derived availableCrew reflects transfer reservation without a second authority")
	check(assigned.fireControl.pendingFirefighters == 20 and assigned.fireControl.transferTicks == 120, "assignment enters declared 120 tick transfer")
	check(assigned.controlsSequence == before.controlsSequence+1 and game.tick == 0, "same tick assignment advances command fence only")
	check(not game.command({"type":"fire-control", "shipId":"e", "crew":10}).ok, "hostile crew cannot be reassigned by player")
	_step(game, 119)
	check(_ship(game.snapshot(), "p").fireControl.assignedFirefighters == 0, "no firefighting before transfer completes")
	_step(game, 1)
	check(_ship(game.snapshot(), "p").fireControl.assignedFirefighters == 20, "standby assignment arrives on tick 120")
	check(_ship(game.snapshot(), "p").crew == 100, "arrival never creates or removes people")
	var queued_game: RefCounted = _game()
	var sailing: RefCounted = Sailing.new(queued_game)
	sailing.action({"type":"fire-control", "crew":10})
	check(_ship(queued_game.snapshot(), "p").fireControl.pendingFirefighters == 0, "queued assignment waits for accepted tick")
	sailing.advance_fixed()
	check(_ship(queued_game.snapshot(), "p").fireControl.pendingFirefighters == 10, "command queue delivers pinned ship assignment")
	check(sailing.drain_results().all(func(result): return result.result.ok), "queued assignment reports real native acceptance")

func _test_independent_launcher() -> void:
	var game: RefCounted = _game()
	var before: Dictionary = _ship(game.snapshot(), "p")
	check(_launch(game).ok, "auxiliary fire-ball launch accepted")
	var after: Dictionary = _ship(game.snapshot(), "p")
	check(after.ammo == before.ammo and after.ammoType == before.ammoType, "auxiliary payload consumes no ordinary cannon ammunition")
	check(after.cooldownSeconds == before.cooldownSeconds and game.volleys.is_empty(), "auxiliary launch commits no ordinary broadside cooldown or volley")
	check(after.fireLauncher.ammo["fire-ball"] == before.fireLauncher.ammo["fire-ball"]-1, "one launch consumes exactly one matching payload")
	check(after.fireLauncher.ammo["thorn-ball"] == before.fireLauncher.ammo["thorn-ball"], "other payload stock unchanged")
	check(is_equal_approx(after.fireLauncher.cooldownSeconds, 12.0), "payloads share declared 12 second launcher cooldown")
	check(is_equal_approx(after.fireLauncher.operationSeconds, 2.0), "real launch reserves four operators for two seconds")
	check(after.get("availableCrew") == 96, "derived working crew excludes four active launcher operators")
	check(game.snapshot().projectiles.size() == 1 and game.has_pending_attacks(), "one auxiliary projectile participates in existing pending attack guard")
	var projectile: Dictionary = game.snapshot().projectiles[0]
	check(projectile.get("kind") == "fire-payload" and projectile.get("payload") == "fire-ball", "auxiliary projectile has an independent payload discriminator")
	check(not projectile.has("ammo"), "auxiliary projectile is not relabeled ordinary ammunition")
	var committed: Dictionary = game.snapshot()
	check(not _launch(game, "thorn-ball").ok and game.snapshot() == committed, "shared cooldown rejects a second payload without mutation")
	_step(game, 60)
	check(is_equal_approx(_ship(game.snapshot(), "p").fireLauncher.operationSeconds, 1.0), "operator reservation consumes accepted seconds")
	_step(game, 60)
	check(_ship(game.snapshot(), "p").fireLauncher.operationSeconds == 0.0, "operators return after exactly 120 accepted ticks")
	_step(game, 60)
	var target: Dictionary = _ship(game.snapshot(), "e")
	check(target.fireControl.heat > 0 and target.fireControl.fuelSeconds > 0, "real projectile sweep ignites actual target")
	check(target.hull < 100 and target.sail < 100, "native accepted time applies sustained hull and sail damage")
	var events: Array = game.drain_events()
	check(not events.any(func(event): return event.type in ["fire", "hit"]), "auxiliary launch and DOT emit no ordinary cannon fire or cargo hit event")
	check(not _launch(_game(true, 70.01)).ok, "target beyond declared launcher range is rejected")
	check(not _launch(_game(), "solid").ok, "ordinary ammo cannot be used as auxiliary payload")
	check(not _launch(_game(), "fire-ball", "p").ok, "self is not an authorized auxiliary target")
	var empty: RefCounted = _game()
	empty.ships[0].state.fireLauncher.ammo["fire-ball"] = 0
	var empty_before: Dictionary = empty.snapshot()
	check(not _launch(empty).ok and empty.snapshot() == empty_before, "empty payload stock rejects atomically")
	var merchant: Dictionary = _setup("p", "player", {"x":0.0, "z":0.0})
	merchant.kind = "merchant"
	merchant.crew = 20
	merchant.stats.maxCrew = 30
	var unarmed: RefCounted = Encounter.new(_config([merchant, _setup("e", "hostile", {"x":0.0, "z":50.0})]))
	check(_ship(unarmed.snapshot(), "p").cannonsPerSide == 0 and _launch(unarmed).ok, "equipped auxiliary launcher does not require broadside cannon hardware")

func _test_launcher_crew_reservation() -> void:
	var game: RefCounted = _game()
	check(_launch(game).ok, "operator fixture launch accepted")
	var before: Dictionary = game.snapshot()
	check(not game.command({"type":"fire-control", "shipId":"p", "crew":97}).ok and game.snapshot() == before, "four active operators cannot also be assigned to firefighting")
	check(game.command({"type":"fire-control", "shipId":"p", "crew":96}).ok, "remaining crew can enter firefighting transfer")
	check(_ship(game.snapshot(), "p").crew == 100, "combined reservations retain the complete living population")
	before = game.snapshot()
	check(not game.command({"type":"fire", "shipId":"p", "side":"starboard"}).ok and game.snapshot() == before, "operators plus transfer reserve leave no free cannon crew")
	var partial: RefCounted = _game()
	check(_launch(partial).ok and partial.command({"type":"fire", "shipId":"p", "side":"starboard"}).ok, "independent launcher and remaining crew can operate cannon")
	var plain: RefCounted = _game()
	plain.command({"type":"fire", "shipId":"p", "side":"starboard"})
	check(_ship(partial.snapshot(), "p").cooldownSeconds.starboard > _ship(plain.snapshot(), "p").cooldownSeconds.starboard, "new cannon reload accounts for four active launcher operators")

func _test_lazy_target_and_corridor() -> void:
	var p: Dictionary = _setup("p", "player", {"x":0.0, "z":0.0})
	p.erase("fireControl")
	var e: Dictionary = _setup("e", "hostile", {"x":0.0, "z":50.0}, false)
	var game: RefCounted = Encounter.new(_config([p, e]))
	check(not _ship(game.snapshot(), "p").has("fireControl") and not _ship(game.snapshot(), "e").has("fireControl"), "launcher and fire state are independently optional")
	check(_launch(game).ok, "launcher-only source can commit real auxiliary shot")
	_step(game, 180)
	var target: Dictionary = _ship(game.snapshot(), "e")
	check(target.get("fireControl") is Dictionary and target.get("fireControl", {}).get("heat", 0.0) > 0.0, "first real impact lazily creates target fire state")
	check(target.get("fireControl", {}).get("supplies", -1) == 0 and not target.has("fireLauncher"), "lazy target gains neither free supplies nor weapon hardware")
	check(not _ship(game.snapshot(), "p").has("fireControl"), "outgoing shot does not equip unrelated source fire state")
	var friend: Dictionary = _setup("friend", "neutral", {"x":0.0, "z":25.0}, false)
	var blocked: RefCounted = Encounter.new(_config([_setup("p", "player", {"x":0.0, "z":0.0}), _setup("e", "hostile", {"x":0.0, "z":50.0}), friend]))
	var before: Dictionary = blocked.snapshot()
	check(not _launch(blocked).ok and blocked.snapshot() == before and blocked.drain_events().is_empty(), "protected ship corridor rejects payload before stock, cooldown, event or projectile mutation")
	var thin: Dictionary = _setup("p", "player", {"x":0.0, "z":0.0})
	thin.crew = 3
	var understaffed: RefCounted = Encounter.new(_config([thin, _setup("e", "hostile", {"x":0.0, "z":50.0})]))
	before = understaffed.snapshot()
	check(not _launch(understaffed).ok and understaffed.snapshot() == before, "fewer than four free living operators cannot launch")

func _test_miss_has_no_fire() -> void:
	var game: RefCounted = _game()
	check(_launch(game).ok, "miss fixture launches toward initial real target")
	# Test fixture changes the actual numeric body after launch. The shot retains
	# its committed trajectory; this is not a second target-following damage path.
	game.ships[1].core.correct_horizontal_motion({"x":200.0, "z":200.0}, {"x":0.0, "z":0.0})
	_step(game, 300)
	var target: Dictionary = _ship(game.snapshot(), "e")
	check(target.fireControl.heat == 0 and target.hull == 100 and target.sail == 100 and target.crew == 100, "missed payload never authorizes fire or damage")
	check(game.snapshot().projectiles.is_empty() and not game.has_pending_attacks(), "water or TTL removes missed payload and pending attack")

func _from_snapshot(ship: Dictionary) -> Dictionary:
	var setup: Dictionary = {"id":ship.id, "name":ship.name, "kind":ship.kind, "team":ship.team,
		"position":{"x":ship.visual.position.x, "z":ship.visual.position.z}, "heading":ship.visual.heading,
		"speed":Vector2(ship.visual.velocity.x, ship.visual.velocity.z).length()}
	for field in ["hull", "sail", "crew", "rudder", "sailDeployment", "sailAngle", "autoTrim", "ammo", "ammoType", "cooldownSeconds", "stats", "fireControl", "fireLauncher"]:
		setup[field] = ship[field].duplicate(true) if ship[field] is Dictionary else ship[field]
	return setup

func _test_authority_damage_and_reconcile() -> void:
	var p: Dictionary = _setup("p", "player", {"x":0.0, "z":0.0})
	p.fireControl.heat = 28.0
	p.fireControl.fuelSeconds = 18.0
	p.fireControl.supplies = 0
	var game: RefCounted = Encounter.new(_config([p, _setup("e", "hostile", {"x":0.0, "z":500.0})]))
	game.step_fixed()
	check(_ship(game.snapshot(), "p").crew == 100, "sub-person fire damage remains in carry and does not floor away a person per tick")
	_step(game, 59)
	var state: Dictionary = _ship(game.snapshot(), "p")
	check(state.crew == 100 and state.fireControl.crewDamageCarry > 0, "one second low DOT preserves integer crew and persistent fraction")
	var native: Dictionary = game.snapshot()
	var fire_before: Dictionary = state.fireControl.duplicate(true)
	var setups: Array = native.ships.map(_from_snapshot)
	check(game.reconcile_ships(setups).ok, "explicit fire extension survives validated native batch")
	check(_ship(game.snapshot(), "p").fireControl == fire_before, "same tick reconciliation preserves every fire accumulator")
	_step(game, 60)
	check(_ship(game.snapshot(), "p").hull < state.hull, "DOT continues after a round trip through native reconcile")
	var detached: Dictionary = game.snapshot()
	detached.ships[0].fireControl.heat = 0
	detached.ships[0].fireLauncher.ammo["fire-ball"] = 999
	check(_ship(game.snapshot(), "p").fireControl.heat > 0 and _ship(game.snapshot(), "p").fireLauncher.ammo["fire-ball"] == 12, "nested fire snapshots are detached")
	var restored: RefCounted = Encounter.new(_config(game.snapshot().ships.map(_from_snapshot)))
	check(restored.last_error.is_empty() and _ship(restored.snapshot(), "p").fireControl == _ship(game.snapshot(), "p").fireControl, "new epoch restores all persistent fire state")
	var active: RefCounted = _game()
	_launch(active)
	_step(active, 60)
	var active_ship: Dictionary = _ship(active.snapshot(), "p")
	var launcher_restore: RefCounted = Encounter.new(_config(active.snapshot().ships.map(_from_snapshot)))
	check(_ship(launcher_restore.snapshot(), "p").fireLauncher == active_ship.fireLauncher, "new epoch preserves remaining launcher cooldown and operation seconds")
	_step(game, 1200)
	state = _ship(game.snapshot(), "p")
	check(state.fireControl.heat == 0 and state.fireControl.fuelSeconds == 0, "finite fuel eventually stops authority fire")
	var extinguished: Dictionary = state.duplicate(true)
	_step(game, 120)
	state = _ship(game.snapshot(), "p")
	check(state.hull == extinguished.hull and state.sail == extinguished.sail and state.crew == extinguished.crew, "extinguished fire neither repairs nor deals further DOT")
	check(not game.drain_events().any(func(event): return event.type == "hit"), "fire progression never generates ordinary cargo-damage hits")

func _test_cannon_commitments() -> void:
	var game: RefCounted = _game()
	check(game.command({"type":"fire", "shipId":"p", "side":"starboard"}).ok, "ordinary reference broadside commits first")
	var ship: Dictionary = _ship(game.snapshot(), "p")
	var reload: Dictionary = ship.cooldownSeconds.duplicate(true)
	var due: Array = game.volleys.map(func(volley): return volley.due)
	check(game.command({"type":"fire-control", "shipId":"p", "crew":100}).ok, "all crew may be reserved for emergency damage control")
	check(_ship(game.snapshot(), "p").crew == 100 and _ship(game.snapshot(), "p").cooldownSeconds == reload, "reservation preserves population and committed cannon reload deadlines")
	check(game.volleys.map(func(volley): return volley.due) == due, "reservation never retimes already scheduled cannon mouths")
	check(not _launch(game).ok, "reserved crew cannot simultaneously operate auxiliary launcher")
	_step(game, 90)
	var events: Array = game.drain_events()
	check(events.filter(func(event): return event.type == "fire" and event.shipId == "p").size() == 1, "delayed cannon mouths are suppressed while their crew are reserved")
	check(_ship(game.snapshot(), "p").ammo.solid == 9, "suppressed delayed mouths do not refund already committed ammunition")
	check(game.command({"type":"fire-control", "shipId":"p", "crew":0}).ok, "return from damage control accepted")
	var deadline: float = _ship(game.snapshot(), "p").cooldownSeconds.starboard
	check(deadline > 0 and deadline < reload.starboard, "return does not reset or complete prior reload")
	var partial: RefCounted = _game()
	check(partial.command({"type":"fire-control", "shipId":"p", "crew":50}).ok, "half crew standby assignment accepted")
	check(partial.command({"type":"fire", "shipId":"p", "side":"starboard"}).ok, "remaining half crew can commit a new broadside")
	check(_ship(partial.snapshot(), "p").cooldownSeconds.starboard > reload.starboard, "new broadside reload reflects reserved crew")
	check(partial.volleys.size() > 1 and partial.volleys[1].due-partial.volleys[0].due > due[1]-due[0], "new delayed salvo spacing reflects reserved crew")

func _test_validation_is_atomic() -> void:
	var game: RefCounted = _game()
	for crew in [-1, 0.5, 101, NAN]:
		var before: Dictionary = game.snapshot()
		check(not game.command({"type":"fire-control", "shipId":"p", "crew":crew}).ok and game.snapshot() == before, "malformed or excess assignment rejects atomically " + str(crew))
	var prior: Dictionary = game.snapshot()
	var invalid: Array = prior.ships.map(_from_snapshot)
	invalid[0].fireControl.heat = NAN
	check(not game.reconcile_ships(invalid).ok and game.snapshot() == prior, "invalid fire state rejects complete native batch atomically")
	invalid = prior.ships.map(_from_snapshot)
	invalid[0].fireLauncher.ammo["fire-ball"] = -1
	check(not game.reconcile_ships(invalid).ok and game.snapshot() == prior, "invalid independent stock rejects native batch atomically")
	invalid = prior.ships.map(_from_snapshot)
	invalid[0].fireLauncher.operationSeconds = 2.01
	check(not game.reconcile_ships(invalid).ok and game.snapshot() == prior, "excess launcher operation time rejects native batch atomically")
	var invalid_reset: Array = prior.ships.map(_from_snapshot)
	invalid_reset[0].fireControl.version = "unknown"
	check(not game.reset(_config(invalid_reset)) and game.snapshot() == prior, "unknown fire profile rejects reset without destroying live encounter")

func _test_fire_environment() -> void:
	var game: RefCounted = _game()
	var original: Dictionary = game.snapshot()
	var setups: Array = original.ships.map(_from_snapshot)
	var invalid_contexts: Array = [
		{}, {"rain01":0.0}, {"rain01":true, "flammableLoadByShip":{}},
		{"rain01":NAN, "flammableLoadByShip":{}}, {"rain01":1.01, "flammableLoadByShip":{}},
		{"rain01":0.0, "flammableLoadByShip":{"unknown":0.5}},
		{"rain01":0.0, "flammableLoadByShip":{"p":true}},
		{"rain01":0.0, "flammableLoadByShip":{"p":INF}},
		{"rain01":0.0, "flammableLoadByShip":{"p":-0.01}},
		{"rain01":0.0, "flammableLoadByShip":[], "extra":0},
	]
	for context: Dictionary in invalid_contexts:
		var config: Dictionary = _config(setups)
		config.fireEnvironment = context
		check(not game.reset(config) and game.snapshot() == original, "invalid reset environment is atomic " + str(context))
		var policy: Dictionary = {"controllableShipIds":["p"], "hostileTargets":{"p":["e"], "e":[]}, "fireEnvironment":context}
		check(not game.reconcile_ships(setups, policy).ok and game.snapshot() == original, "invalid projected environment is atomic " + str(context))
	var valid_policy: Dictionary = {"controllableShipIds":["p"], "hostileTargets":{"p":["e"], "e":[]},
		"fireEnvironment":{"rain01":1.0, "flammableLoadByShip":{"p":0.5}}}
	check(game.reconcile_ships(setups, valid_policy).ok, "strict explicit environment commits with native projection")
	game.step_fixed()
	check(_ship(game.snapshot(), "p").fireControl.wetness > 0.0, "declared rain reaches accepted fire rules")

func _test_deterministic_clock() -> void:
	var results: Array = []
	for hz in [30, 60, 120]:
		var p: Dictionary = _setup("p", "player", {"x":0.0, "z":0.0})
		p.fireControl.heat = 28.0
		p.fireControl.fuelSeconds = 18.0
		var game: RefCounted = Encounter.new(_config([p, _setup("e", "hostile", {"x":0.0, "z":500.0})]))
		game.command({"type":"fire-control", "shipId":"p", "crew":8})
		for frame in hz*5: game.step(1.0/hz)
		results.append(_ship(game.snapshot(), "p"))
	check(results[0].fireControl == results[1].fireControl and results[1].fireControl == results[2].fireControl, "30/60/120Hz callers produce exact accepted fire state")
	check(results[0].hull == results[1].hull and results[1].hull == results[2].hull and results[0].crew == results[2].crew, "caller frame rate cannot alter fire damage")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures.append(message)

func _finish() -> void:
	for failure: String in failures: print("NAVAL_FIRE_CONTROL_FAIL ", failure)
	print("NAVAL_FIRE_CONTROL assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
