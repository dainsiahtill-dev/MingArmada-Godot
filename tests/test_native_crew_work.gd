extends SceneTree
## Native producer contract. Default is production for an explicit missing-method RED.
## The sole --candidate switch selects the isolated, hardcoded research candidate.
const PRODUCTION_PATH: String = "res://modules/naval_simulation/encounter.gd"
const CANDIDATE_PATH: String = "res://game/research/candidates/crew_work_encounter.gd"
const STEP: float = 1.0 / 60.0
const RECEIPT_KEYS: Array[String] = ["version", "battleId", "tick", "stepSeconds", "ships"]
const ROW_KEYS: Array[String] = ["shipId", "totalAbleAtStart", "totalAbleAtEnd", "launcherCrew", "fireDutyCrew", "availableCrew", "unavailableCrew", "position", "velocity", "hullAtStart"]
var failures: Array[String] = []
var assertions: int = 0
var encounter_script: Script

func _initialize() -> void:
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var valid_arguments: bool = arguments.is_empty() or (arguments.size() == 1 and arguments[0] == "--candidate")
	check(valid_arguments, "only the single --candidate argument is supported")
	if not valid_arguments:
		_finish()
		return
	var path: String = CANDIDATE_PATH if arguments.size() == 1 else PRODUCTION_PATH
	var resource: Resource = load(path)
	check(resource is Script, "selected native Encounter script loads: " + path)
	if not resource is Script:
		_finish()
		return
	encounter_script = resource as Script
	# This gate intentionally precedes every crewWorkAccounting flag assertion.
	var probe: RefCounted = _new(_config(_pair(false, false), false))
	check(probe.has_method("crew_work_receipt"), "NATIVE_CREW_WORK_MISSING: Encounter must expose crew_work_receipt()")
	if not probe.has_method("crew_work_receipt"):
		_finish()
		return
	_test_optional_flag_and_snapshot()
	_test_configuration_bounds()
	_test_start_witness_and_casualty_end()
	_test_launcher_intervals()
	_test_transfer_intervals()
	_test_reconcile_and_reset()
	_test_ai_launcher_right_boundary()
	_test_ai_transfer_right_boundary()
	_test_auxiliary_policy()
	_finish()

func _fire() -> Dictionary:
	return {"version":"ship-fire-r1", "heat":0.0, "fuelSeconds":0.0, "wetness":0.0, "crewDamageCarry":0.0,
		"assignedFirefighters":0, "pendingFirefighters":0, "transferTicks":0, "supplies":60, "workCarry":0.0}

func _setup(id: String, team: String, position: Dictionary, extended: bool = true) -> Dictionary:
	var setup: Dictionary = {"id":id, "kind":"fuchuan", "team":team, "position":position.duplicate(true),
		"heading":0.0, "speed":0.0, "hull":10000.0, "sail":0.0, "crew":40,
		"sailDeployment":0.0, "rudder":0.0, "sailAngle":0.0, "autoTrim":true,
		"ammo":{"solid":0, "chain":0, "grape":0}, "stats":{"maxHull":10000, "maxCrew":100}}
	if extended:
		setup.fireControl = _fire()
		setup.fireLauncher = {"ammo":{"fire-ball":4, "thorn-ball":0}, "cooldownSeconds":0.0, "operationSeconds":0.0}
	return setup

func _pair(player_extended: bool = true, enemy_extended: bool = false, distance: float = 50.0) -> Array:
	return [_setup("p", "player", {"x":0.0, "z":0.0}, player_extended), _setup("e", "hostile", {"x":0.0, "z":distance}, enemy_extended)]

func _config(setups: Array, accounting: bool = true, ai: bool = false, player: String = "p") -> Dictionary:
	var targets: Dictionary = {}
	var identities: Array[String] = []
	for setup: Dictionary in setups:
		identities.append(setup.id)
		targets[setup.id] = []
	if identities.has("p") and identities.has("e"):
		targets.p = ["e"]
		targets.e = ["p"] if ai else []
	var config: Dictionary = {"mode":"continuous", "playerId":player, "seed":1650, "ships":setups.duplicate(true),
		"oceanWaves":[], "referenceGunnery":true, "wind":{"direction":{"x":1.0, "y":0.0}, "speed":0.0},
		"controllableShipIds":[player], "hostileTargets":targets}
	if accounting:
		config.crewWorkAccounting = true
	return config

func _new(config: Dictionary) -> RefCounted:
	var game: RefCounted = encounter_script.new(config)
	return game

func _receipt(game: RefCounted) -> Dictionary:
	var value: Variant = game.call("crew_work_receipt")
	check(value is Dictionary, "crew_work_receipt returns a detached Dictionary")
	return value if value is Dictionary else {}

func _ship(native: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in native.get("ships", []):
		if ship.id == id:
			return ship
	return {}

func _row(receipt: Dictionary, id: String) -> Dictionary:
	for row: Dictionary in receipt.get("ships", []):
		if row.get("shipId") == id:
			return row
	return {}

func _keys(value: Dictionary, keys: Array[String]) -> bool:
	return value.size() == keys.size() and value.has_all(keys)

func _shape(receipt: Dictionary, game: RefCounted, expected_tick: int, roster: Array[String]) -> bool:
	var shaped: bool = _keys(receipt, RECEIPT_KEYS)
	check(shaped, "receipt has exactly five declared keys")
	if not shaped:
		return false
	check(receipt.version == "crew-work-r1" and receipt.battleId == game.battle_id, "receipt version and actual battle identity match")
	check(typeof(receipt.tick) == TYPE_INT and receipt.tick == expected_tick and receipt.tick >= 1, "receipt uses the actual accepted positive integer tick")
	check(typeof(receipt.stepSeconds) == TYPE_FLOAT and receipt.stepSeconds == STEP, "receipt stepSeconds is the exact native 1/60 second")
	check(receipt.ships is Array and receipt.ships.size() == roster.size(), "receipt covers the complete starting roster")
	if not receipt.ships is Array:
		return false
	var seen: Array[String] = []
	for entry: Variant in receipt.ships:
		check(entry is Dictionary, "each receipt row is a Dictionary")
		if not entry is Dictionary:
			return false
		var row: Dictionary = entry
		var row_shaped: bool = _keys(row, ROW_KEYS)
		check(row_shaped, "row has exactly ten declared keys")
		if not row_shaped:
			return false
		check(row.shipId is String and roster.has(row.shipId) and not seen.has(row.shipId), "row IDs are known and unique")
		seen.append(str(row.shipId))
		for field: String in ["totalAbleAtStart", "totalAbleAtEnd", "launcherCrew", "fireDutyCrew", "availableCrew", "unavailableCrew"]:
			check(typeof(row[field]) == TYPE_INT and row[field] >= 0 and row[field] <= 1000, field + " is a bounded integer count")
		check(row.launcherCrew <= 4 and row.fireDutyCrew <= 128, "row obeys launcher and fire-duty staffing bounds")
		check(row.launcherCrew + row.fireDutyCrew + row.availableCrew + row.unavailableCrew == row.totalAbleAtStart, "row conserves starting people exactly")
		check(row.totalAbleAtEnd <= row.totalAbleAtStart, "same-step casualty endpoint cannot invent starting people")
		check(row.position is Dictionary and row.position.size() == 2 and row.position.has_all(["x", "z"]), "row position is a two-coordinate start witness")
		check(row.velocity is Dictionary and row.velocity.size() == 2 and row.velocity.has_all(["x", "z"]), "row velocity is a two-coordinate start witness")
	return true

func _authority(game: RefCounted) -> Dictionary:
	return {"snapshot":game.snapshot(), "receipt":_receipt(game), "events":game.events.duplicate(true),
		"volleys":game.volleys.duplicate(true), "damage":game.projectile_damage.duplicate(true),
		"policy":game.policy.duplicate(true), "config":game.config.duplicate(true), "sequence":game.sequence, "epoch":game.epoch}

func _launch(game: RefCounted, source: String = "p", target: String = "e") -> Dictionary:
	var result: Dictionary = game.command({"type":"launch-fire", "shipId":source, "targetId":target, "payload":"fire-ball"})
	return result

func _step(game: RefCounted, ticks: int) -> void:
	for index: int in range(ticks):
		game.step_fixed()

func _from_snapshot(ship: Dictionary) -> Dictionary:
	var setup: Dictionary = {"id":ship.id, "name":ship.name, "kind":ship.kind, "team":ship.team,
		"position":{"x":ship.visual.position.x, "z":ship.visual.position.z}, "heading":ship.visual.heading,
		"speed":Vector2(ship.visual.velocity.x, ship.visual.velocity.z).length()}
	for field: String in ["hull", "sail", "crew", "rudder", "sailDeployment", "sailAngle", "autoTrim", "ammo", "ammoType", "cooldownSeconds", "stats", "fireControl", "fireLauncher"]:
		if ship.has(field):
			setup[field] = ship[field].duplicate(true) if ship[field] is Dictionary else ship[field]
	return setup

func _setups(native: Dictionary) -> Array:
	var setups: Array = []
	for ship: Dictionary in native.ships:
		setups.append(_from_snapshot(ship))
	return setups

func _test_optional_flag_and_snapshot() -> void:
	var plain_config: Dictionary = _config(_pair(false, false), false)
	var false_config: Dictionary = plain_config.duplicate(true)
	false_config.crewWorkAccounting = false
	var enabled_config: Dictionary = plain_config.duplicate(true)
	enabled_config.crewWorkAccounting = true
	var plain: RefCounted = _new(plain_config)
	var disabled: RefCounted = _new(false_config)
	var enabled: RefCounted = _new(enabled_config)
	check(plain.last_error.is_empty() and disabled.last_error.is_empty() and enabled.last_error.is_empty(), "absent, false and true accounting flags configure")
	check(_receipt(plain).is_empty() and _receipt(disabled).is_empty() and _receipt(enabled).is_empty(), "tick zero has no fabricated receipt")
	check(plain.snapshot() == disabled.snapshot() and plain.snapshot() == enabled.snapshot(), "accounting does not alter initial ordinary snapshot shape or values")
	for index: int in range(3):
		plain.step_fixed()
		disabled.step_fixed()
		enabled.step_fixed()
		check(_receipt(plain).is_empty() and _receipt(disabled).is_empty(), "absent/false accounting continues to expose an empty peek")
		check(plain.snapshot() == disabled.snapshot() and plain.snapshot() == enabled.snapshot(), "opt-in accounting leaves an unextended accepted snapshot identical")
		_shape(_receipt(enabled), enabled, index + 1, ["p", "e"])
	var snapshot: Dictionary = enabled.snapshot()
	check(not snapshot.has("crewWork") and not snapshot.has("crewWorkReceipt"), "receipt is not inserted in the Native snapshot")
	check(not _ship(snapshot, "p").has("availableCrew"), "unextended source snapshot gains no derived crew field")
	var plain_events: Array = plain.drain_events()
	var disabled_events: Array = disabled.drain_events()
	var enabled_events: Array = enabled.drain_events()
	check(plain_events == disabled_events and plain_events == enabled_events, "accounting adds no ordinary event or changes an existing event")
	var invalid_flags: Array = [0, 1, "true", null, {}, []]
	for flag: Variant in invalid_flags:
		var before: Dictionary = _authority(enabled)
		var invalid: Dictionary = enabled_config.duplicate(true)
		invalid.crewWorkAccounting = flag
		check(not enabled.reset(invalid), "non-bool accounting flag rejects: " + str(flag))
		check(_authority(enabled) == before, "invalid accounting flag leaves prior authority and receipt atomic")

func _test_configuration_bounds() -> void:
	var setups: Array = [_setup("p", "player", {"x":0.0, "z":0.0}, false)]
	for index: int in range(1, 128):
		setups.append(_setup("n-" + str(index), "neutral", {"x":float(index) * 200.0, "z":0.0}, false))
	var accepted: RefCounted = _new(_config(setups))
	check(accepted.last_error.is_empty() and accepted.snapshot().ships.size() == 128, "accounting accepts its exact 128-ship roster bound")
	accepted.step_fixed()
	var roster: Array[String] = []
	for setup: Dictionary in setups:
		roster.append(setup.id)
	_shape(_receipt(accepted), accepted, 1, roster)
	var before: Dictionary = _authority(accepted)
	setups.append(_setup("n-128", "neutral", {"x":25600.0, "z":0.0}, false))
	check(not accepted.reset(_config(setups)), "accounting rejects a 129-ship roster")
	check(_authority(accepted) == before, "oversized roster rejection preserves current authority and receipt")
	var valid_id: String = "p".repeat(256)
	var id_config: Dictionary = _config([_setup(valid_id, "player", {"x":0.0, "z":0.0}, false)], true, false, valid_id)
	var id_game: RefCounted = _new(id_config)
	check(id_game.last_error.is_empty(), "accounting accepts a 256-character real ship ID")
	id_game.step_fixed()
	_shape(_receipt(id_game), id_game, 1, [valid_id])
	before = _authority(id_game)
	var too_long: String = "p".repeat(257)
	var invalid_id: Dictionary = _config([_setup(too_long, "player", {"x":0.0, "z":0.0}, false)], true, false, too_long)
	check(not id_game.reset(invalid_id), "accounting rejects a 257-character real ship ID")
	check(_authority(id_game) == before, "invalid accounting ship ID leaves the current authority atomic")
	var battle_config: Dictionary = _config(_pair(false, false))
	battle_config.battleId = "b".repeat(4096)
	var battle_game: RefCounted = _new(battle_config)
	check(battle_game.last_error.is_empty(), "accounting preserves the original 4096-character battle-ID bound")
	battle_game.step_fixed()
	check(_receipt(battle_game).get("battleId") == battle_config.battleId, "long valid battle identity is preserved in the real receipt")
	before = _authority(battle_game)
	battle_config.battleId = "b".repeat(4097)
	check(not battle_game.reset(battle_config), "accounting rejects battle IDs beyond the original 4096-character bound")
	check(_authority(battle_game) == before, "invalid battle identity leaves authority and receipt atomic")

func _test_start_witness_and_casualty_end() -> void:
	var setups: Array = _pair(true, false, 500.0)
	var player: Dictionary = setups[0]
	player.position = {"x":15.0, "z":-25.0}
	player.speed = 2.0
	player.fireControl.heat = 100.0
	player.fireControl.fuelSeconds = 72.0
	player.fireControl.crewDamageCarry = 0.99
	var game: RefCounted = _new(_config(setups))
	check(game.command({"type":"fire-control", "shipId":"p", "crew":4}).ok, "start-witness fixture reserves four real workers")
	var start: Dictionary = _ship(game.snapshot(), "p")
	game.step_fixed()
	var receipt: Dictionary = _receipt(game)
	if not _shape(receipt, game, 1, ["p", "e"]):
		return
	var row: Dictionary = _row(receipt, "p")
	var end: Dictionary = _ship(game.snapshot(), "p")
	check(row.totalAbleAtStart == 40 and row.totalAbleAtEnd == 39 and end.crew == 39, "real same-tick DOT records starting forty and ending thirty-nine")
	check(row.launcherCrew == 0 and row.fireDutyCrew == 4 and row.availableCrew == 36, "casualty endpoint cannot rewrite the past four duty and thirty-six free person-ticks")
	check(row.position == {"x":start.visual.position.x, "z":start.visual.position.z}, "receipt freezes position before the accepted physics step")
	check(row.velocity == {"x":start.visual.velocity.x, "z":start.visual.velocity.z} and row.hullAtStart == start.hull, "receipt freezes pre-step velocity and hull")
	check(end.fireControl.transferTicks == 119 and end.fireControl.supplies == 60 and end.fireControl.workCarry == 0.0, "real transfer progresses without invented suppression resource work")
	var committed: Dictionary = _authority(game)
	receipt.ships[0].position.x = 999999.0
	receipt.ships[0].totalAbleAtStart = 0
	receipt.ships.clear()
	check(_authority(game) == committed, "mutating every returned nested receipt layer cannot affect authority or stored receipt")
	game.step_fixed()
	check(_row(_receipt(game), "p").get("totalAbleAtStart") == 39, "the following tick starts from actual surviving people")
	var sink_setups: Array = _pair(true, false, 500.0)
	sink_setups[0].hull = 1.0
	sink_setups[0].fireControl.heat = 100.0
	sink_setups[0].fireControl.fuelSeconds = 72.0
	sink_setups[0].fireControl.crewDamageCarry = 0.99
	var sinking: RefCounted = _new(_config(sink_setups))
	sinking.step_fixed()
	var sunk_row: Dictionary = _row(_receipt(sinking), "p")
	var sunk_ship: Dictionary = _ship(sinking.snapshot(), "p")
	check(sunk_ship.hull == 0.0 and sunk_ship.crew > 0.0, "sink fixture reaches the real existing hull-zero transition without rewriting legacy crew")
	check(sunk_row.get("totalAbleAtStart") == 40 and sunk_row.get("totalAbleAtEnd") == 0, "a same-tick sink has no operational ending crew despite retained native crew bucket")
	check(sunk_row.get("hullAtStart") == 1.0 and sunk_row.get("availableCrew") == 40, "same-tick sink does not retroactively erase the real starting interval")

func _test_launcher_intervals() -> void:
	var game: RefCounted = _new(_config(_pair()))
	check(_launch(game).ok, "external tick-zero auxiliary launch succeeds")
	check(_receipt(game).is_empty(), "same-tick launch creates no elapsed work receipt")
	var stock: int = int(_ship(game.snapshot(), "p").fireLauncher.ammo["fire-ball"])
	var person_ticks: int = 0
	for accepted_tick: int in range(1, 121):
		game.step_fixed()
		var row: Dictionary = _row(_receipt(game), "p")
		check(row.get("launcherCrew") == 4 and row.get("availableCrew") == 36, "external launch reserves four throughout accepted interval " + str(accepted_tick))
		person_ticks += int(row.get("launcherCrew", 0))
		check(_ship(game.snapshot(), "p").fireLauncher.ammo["fire-ball"] == stock, "elapsed work never consumes another payload")
	check(person_ticks == 480, "tick-zero two-second launcher occupies exactly 480 person-ticks")
	check(_ship(game.snapshot(), "p").fireLauncher.operationSeconds == 0.0, "tick 120 endpoint operation has finished")
	check(_row(_receipt(game), "p").get("launcherCrew") == 4, "finished endpoint cannot erase tick 120 operator labour")
	game.step_fixed()
	var released: Dictionary = _row(_receipt(game), "p")
	check(released.get("launcherCrew") == 0 and released.get("availableCrew") == 40, "operators first become free for the tick 121 interval")

func _test_transfer_intervals() -> void:
	var setups: Array = _pair(true, false, 500.0)
	setups[0].fireControl.heat = 28.0
	setups[0].fireControl.fuelSeconds = 72.0
	var game: RefCounted = _new(_config(setups))
	check(game.command({"type":"fire-control", "shipId":"p", "crew":4}).ok, "external tick-zero transfer accepted")
	for accepted_tick: int in range(1, 121):
		game.step_fixed()
		check(_row(_receipt(game), "p").get("fireDutyCrew") == 4, "outbound workers remain occupied through tick " + str(accepted_tick))
		check(_ship(game.snapshot(), "p").fireControl.workCarry == 0.0, "outbound transfer cannot suppress before full 120 tick arrival")
	var arrived: Dictionary = _ship(game.snapshot(), "p")
	check(arrived.fireControl.transferTicks == 0 and arrived.fireControl.assignedFirefighters == 4, "external workers arrive at tick 120 endpoint")
	game.step_fixed()
	check(_ship(game.snapshot(), "p").fireControl.workCarry > 0.0, "external assigned workers first suppress during tick 121")
	check(_row(_receipt(game), "p").get("fireDutyCrew") == 4, "working suppression remains occupied duty")

func _test_reconcile_and_reset() -> void:
	var game: RefCounted = _new(_config(_pair()))
	check(_launch(game).ok, "reconciliation fixture launches externally")
	game.step_fixed()
	var receipt: Dictionary = _receipt(game)
	var before_sequence: int = int(_ship(game.snapshot(), "p").controlsSequence)
	var result: Dictionary = game.reconcile_ships(_setups(game.snapshot()), game.policy.duplicate(true))
	check(result.ok, "same-tick actual Native batch reconciliation succeeds")
	check(_ship(game.snapshot(), "p").controlsSequence > before_sequence, "reconciliation really advances controlsSequence")
	check(_receipt(game) == receipt, "same-tick reconciliation cannot recalculate or clear the frozen work receipt")
	check(_receipt(game) == receipt, "repeated receipt peeks never drain it")
	var old_battle: String = str(receipt.get("battleId", ""))
	check(game.reset(), "configured Native reset succeeds")
	check(game.tick == 0 and _receipt(game).is_empty(), "reset clears old-epoch receipt rather than replaying it at tick zero")
	game.step_fixed()
	check(_receipt(game).get("tick") == 1 and _receipt(game).get("battleId") != old_battle, "new epoch produces its own first real tick receipt")

func _test_ai_launcher_right_boundary() -> void:
	var game: RefCounted = _new(_config(_pair(false, true), true, true))
	game.step_fixed()
	var first: Dictionary = _receipt(game)
	check(_row(first, "e").get("launcherCrew") == 0, "AI tick-one auxiliary launch cannot occupy its already elapsed first interval")
	var enemy: Dictionary = _ship(game.snapshot(), "e")
	check(enemy.fireLauncher.ammo["fire-ball"] == 3 and enemy.fireLauncher.operationSeconds == 2.0, "AI tick-one boundary really commits one fresh two-second launcher operation")
	var launched: Array = game.snapshot().projectiles
	check(launched.size() == 1, "AI boundary creates exactly one auxiliary projectile with no ordinary ammunition")
	if launched.size() == 1:
		check(launched[0].get("kind") == "fire-payload" and launched[0].age == 0.0, "new AI boundary projectile has not moved during the past interval")
	var person_ticks: int = 0
	for accepted_tick: int in range(2, 122):
		game.step_fixed()
		var row: Dictionary = _row(_receipt(game), "e")
		check(row.get("launcherCrew") == 4, "AI launcher occupies subsequent interval " + str(accepted_tick))
		person_ticks += int(row.get("launcherCrew", 0))
	check(person_ticks == 480, "AI tick-one launch reserves exactly 480 person-ticks across ticks two through 121")
	check(_ship(game.snapshot(), "e").fireLauncher.operationSeconds == 0.0 and _row(_receipt(game), "e").get("launcherCrew") == 4, "AI tick 121 endpoint cannot erase its last occupied interval")
	game.step_fixed()
	check(_row(_receipt(game), "e").get("launcherCrew") == 0, "AI operators first release for tick 122")

func _test_ai_transfer_right_boundary() -> void:
	# The target is outside launcher range; no incidental auxiliary impact can
	# consume crew or mix a second operation into this transfer measurement.
	var setups: Array = _pair(false, true, 500.0)
	setups[1].fireControl.heat = 28.0
	setups[1].fireControl.fuelSeconds = 72.0
	var game: RefCounted = _new(_config(setups, true, true))
	game.step_fixed()
	var enemy: Dictionary = _ship(game.snapshot(), "e")
	check(_row(_receipt(game), "e").get("fireDutyCrew") == 0, "AI boundary assignment does not backdate its first duty interval")
	check(enemy.fireControl.pendingFirefighters == 4 and enemy.fireControl.transferTicks == 120, "AI tick-one boundary starts a fresh full 120-tick transfer")
	check(enemy.fireControl.workCarry == 0.0 and enemy.fireLauncher.operationSeconds == 0.0, "isolated AI transfer has neither work nor a hidden in-range launcher budget")
	for accepted_tick: int in range(2, 122):
		game.step_fixed()
		check(_row(_receipt(game), "e").get("fireDutyCrew") == 4, "AI transfer reserves actual workers during subsequent interval " + str(accepted_tick))
		check(_ship(game.snapshot(), "e").fireControl.workCarry == 0.0, "AI transfer never suppresses before tick 122")
	enemy = _ship(game.snapshot(), "e")
	check(enemy.fireControl.transferTicks == 0 and enemy.fireControl.assignedFirefighters == 4, "AI workers arrive only at tick 121 endpoint")
	game.step_fixed()
	check(_ship(game.snapshot(), "e").fireControl.workCarry > 0.0, "AI workers first suppress during tick 122")

func _test_auxiliary_policy() -> void:
	var game: RefCounted = _new(_config(_pair()))
	var blocked: Dictionary = game.policy.duplicate(true)
	blocked.auxiliaryWorkBlockedShipIds = ["p"]
	var result: Dictionary = game.reconcile_ships(_setups(game.snapshot()), blocked)
	check(result.ok, "validated optional auxiliary-work block policy commits")
	game.step_fixed()
	var blocked_row: Dictionary = _row(_receipt(game), "p")
	check(blocked_row.get("availableCrew") == 0 and blocked_row.get("unavailableCrew") == 40, "policy-blocked starting roster is explicitly unavailable, preserving all forty people")
	var before: Dictionary = _authority(game)
	check(not _launch(game).ok, "blocked old-boarding ship cannot start new auxiliary launch duty")
	check(_authority(game) == before, "blocked launch rejects without stock, event, control, projectile or receipt mutation")
	check(not game.command({"type":"fire-control", "shipId":"p", "crew":4}).ok, "blocked old-boarding ship cannot start positive transfer duty")
	check(_authority(game) == before, "blocked positive transfer rejects without authority mutation")
	check(game.command({"type":"fire-control", "shipId":"p", "crew":0}).ok, "zero-person withdrawal remains allowed under auxiliary-work block")
	var invalid_lists: Array = [["ghost"], ["p", "p"], [12], "p"]
	for identities: Variant in invalid_lists:
		before = _authority(game)
		var invalid: Dictionary = game.policy.duplicate(true)
		invalid.auxiliaryWorkBlockedShipIds = identities
		var rejected: Dictionary = game.reconcile_ships(_setups(game.snapshot()), invalid)
		check(not rejected.ok, "invalid optional policy ID list rejects: " + str(identities))
		check(_authority(game) == before, "invalid optional policy is atomic across controls, live state and receipt")

func check(value: bool, message: String) -> void:
	assertions += 1
	if not value:
		failures.append(message)

func _finish() -> void:
	for failure: String in failures:
		print("NATIVE_CREW_WORK_FAIL ", failure)
	print("NATIVE_CREW_WORK assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
