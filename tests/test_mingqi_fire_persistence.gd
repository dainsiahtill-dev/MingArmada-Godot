extends SceneTree
## Persistence boundary only. Root runs RED before applying the staged codec patch.
## No native work receipts or proposed boarding carry fields belong in this schema.

const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const UTC := "2026-10-29T00:00:00.000Z"
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL Mingqi fire persistence: ", label)
	return ok

func raw_save(state: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":state.campaignId,"mode":"mingqi-1650","savedAtUtc":UTC,"simulationSeconds":state.simulationSeconds,"state":state}, "", false, true)

func has_fields(value: Variant, fields: Array) -> bool:
	return value is Dictionary and value.has_all(fields)

func fire_fixture() -> Dictionary:
	# Literal expectations catch lost carry, defaults, rounding, and restarted clocks.
	return {"version":"ship-fire-r1","heat":20.0,"fuelSeconds":17.25,"wetness":0.375,
		"crewDamageCarry":0.875,"assignedFirefighters":3,"pendingFirefighters":2,
		"transferTicks":17,"supplies":4,"workCarry":1.75}

func launcher_fixture() -> Dictionary:
	return {"ammo":{"fire-ball":2,"thorn-ball":1},"cooldownSeconds":7.5,"operationSeconds":1.5}

func state_with_fire() -> Dictionary:
	var state: Dictionary = Campaign.new().snapshot()
	var vessel: Dictionary = state.vessels[state.flagshipId]
	vessel.crew.able = 7
	vessel.crew.wounded = 2
	vessel.crew.prisoners = 1
	vessel.fireControl = fire_fixture()
	vessel.fireLauncher = launcher_fixture()
	vessel.damage.fire = 20.0
	vessel.combat.ammo = {"solid":13,"chain":9,"grape":7}
	vessel.combat.cooldownSeconds = {"port":0.3125,"starboard":1.03125}
	return state

func reject(session: RefCounted, state: Dictionary, label: String) -> void:
	var before: Dictionary = session.snapshot()
	check(not Codec.decode(raw_save(state)).get("ok",false), "decode rejects " + label)
	check(not session.restore(raw_save(state)) and session.snapshot() == before, "restore rejects atomically " + label)
	check(Codec.encode(state,UTC).is_empty(), "encode rejects " + label)

func run() -> void:
	_legacy_absence()
	var session = Campaign.new()
	if not check(session.has_method("near_field_setup") and session.has_method("restore") and session.has_method("serialize"), "Campaign exposes persistence and native setup APIs"):
		finish()
		return
	var state := state_with_fire()
	check(Fire.valid(fire_fixture()) and Launcher.valid(launcher_fixture()), "literal fixture meets both frozen rules contracts")
	# Behavioral capability guard: missing optional support produces a clean RED,
	# never an invalid Dictionary access or a missing-method runtime exception.
	var decoded: Dictionary = Codec.decode(raw_save(state))
	if not check(decoded.get("ok",false), "codec accepts exact optional FireControl and FireLauncher objects"):
		finish()
		return
	var vessel: Variant = decoded.get("state",{}).get("vessels",{}).get(state.flagshipId)
	if not check(has_fields(vessel,["fireControl","fireLauncher"]), "decode retains both optional objects"):
		finish()
		return
	_round_trip_and_setup(session,state)
	_independently_optional(session,state)
	_strict_shapes_and_numbers(session,state)
	_population_and_operator_budget(session,state)
	_nonfinite_json(session,state)
	finish()

func _legacy_absence() -> void:
	var legacy := FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")
	var session = Campaign.new()
	if not check(session.restore(legacy), "unchanged old web save remains readable"):
		return
	var old: Dictionary = session.snapshot()
	for vessel: Dictionary in old.vessels.values():
		check(not vessel.has("fireControl") and not vessel.has("fireLauncher") and not vessel.has("availableCrew"), "old save grants no stock or persisted derived population: " + vessel.id)
		var setup: Dictionary = session.near_field_setup(vessel,"neutral")
		check(not setup.has("fireControl") and not setup.has("fireLauncher") and not setup.has("availableCrew"), "old setup retains extension absence: " + vessel.id)
	var legacy_round_trip: Dictionary = Codec.decode(session.serialize(UTC))
	check(legacy_round_trip.get("ok",false) and legacy_round_trip.get("state") == old, "old save round trip neither invents state nor changes quantities")
	var unresolved := old.duplicate(true)
	unresolved.vessels[unresolved.flagshipId].damage.fire = 9.0
	if check(session.restore(raw_save(unresolved)), "legacy positive fire remains structurally readable"):
		var restored: Dictionary = session.snapshot().vessels[unresolved.flagshipId]
		check(restored.damage.fire == 9.0 and not restored.has("fireControl") and not restored.has("fireLauncher"), "unresolved legacy fire survives without invented fuel or stock")
		check(Codec.decode(session.serialize(UTC)).get("state",{}).get("vessels",{}).get(unresolved.flagshipId,{}).get("damage",{}).get("fire") == 9.0, "unresolved legacy fire survives a second save")
	var fresh: Dictionary = Campaign.new().snapshot()
	for vessel: Dictionary in fresh.vessels.values():
		check(not vessel.has("fireControl") and not vessel.has("fireLauncher"), "new campaign grants no fire stock: " + vessel.id)

func _round_trip_and_setup(session: RefCounted, state: Dictionary) -> void:
	if not check(session.restore(raw_save(state)), "Campaign restores exact optional state"):
		return
	var restored: Dictionary = session.snapshot().vessels[state.flagshipId]
	check(restored.fireControl == fire_fixture() and restored.fireLauncher == launcher_fixture(), "restore retains every stock, carry, lifetime, travel tick and remaining launcher second")
	check(restored.damage.fire == 20.0 and restored.damage.fire == restored.fireControl.heat, "fire damage remains heat projection")
	check(restored.crew.able == 7 and restored.crew.wounded == 2 and restored.crew.prisoners == 1 and not restored.has("availableCrew"), "real crew buckets survive occupied duty without derived count replacing able")
	check(restored.combat.ammo == {"solid":13,"chain":9,"grape":7} and restored.combat.cooldownSeconds == {"port":0.3125,"starboard":1.03125}, "fire persistence preserves ordinary ammunition and both reload clocks")
	var encoded: String = session.serialize(UTC)
	var decoded: Dictionary = Codec.decode(encoded)
	check(not encoded.is_empty() and decoded.get("ok",false) and decoded.get("state") == session.snapshot(), "full precision encode/decode preserves entire Campaign state")
	var second = Campaign.new()
	check(second.restore(encoded) and second.snapshot() == session.snapshot(), "a second restore retains the same exact state")
	var setup: Dictionary = session.near_field_setup(restored,"player")
	if not check(has_fields(setup,["fireControl","fireLauncher"]), "native setup forwards both explicit optional objects"):
		return
	check(setup.fireControl == fire_fixture() and setup.fireLauncher == launcher_fixture() and setup.crew == 7 and not setup.has("availableCrew"), "native setup forwards total population and exact fire objects")
	setup.fireControl.workCarry = 0.0
	setup.fireLauncher.ammo["fire-ball"] = 60
	check(session.snapshot().vessels[state.flagshipId].fireControl == fire_fixture() and session.snapshot().vessels[state.flagshipId].fireLauncher == launcher_fixture(), "setup deep copy cannot change owned carry or stock")

func _independently_optional(session: RefCounted, state: Dictionary) -> void:
	var control_only := state.duplicate(true)
	control_only.vessels[control_only.flagshipId].erase("fireLauncher")
	if check(session.restore(raw_save(control_only)), "fireControl may exist without fireLauncher"):
		var setup: Dictionary = session.near_field_setup(session.snapshot().vessels[state.flagshipId])
		check(setup.get("fireControl") == fire_fixture() and not setup.has("fireLauncher"), "control-only setup creates no free launcher")
	var launcher_only := state.duplicate(true)
	launcher_only.vessels[launcher_only.flagshipId].erase("fireControl")
	launcher_only.vessels[launcher_only.flagshipId].damage.fire = 0.0
	if check(session.restore(raw_save(launcher_only)), "fireLauncher may exist without fireControl"):
		var setup: Dictionary = session.near_field_setup(session.snapshot().vessels[state.flagshipId])
		check(setup.get("fireLauncher") == launcher_fixture() and not setup.has("fireControl"), "launcher-only setup creates no free suppression object")
	check(session.restore(raw_save(state)), "strict-rejection baseline restores")

func _strict_shapes_and_numbers(session: RefCounted, state: Dictionary) -> void:
	for field: String in ["version","heat","fuelSeconds","wetness","crewDamageCarry","assignedFirefighters","pendingFirefighters","transferTicks","supplies","workCarry"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireControl.erase(field)
		reject(session,bad,"missing fireControl." + field)
	for field: String in ["ammo","cooldownSeconds","operationSeconds"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireLauncher.erase(field)
		reject(session,bad,"missing fireLauncher." + field)
	for payload: String in ["fire-ball","thorn-ball"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireLauncher.ammo.erase(payload)
		reject(session,bad,"missing launcher ammo " + payload)
	for mutation: String in ["extra-vessel-key","extra-fire-key","extra-launcher-key","extra-ammo-key","persisted-derived-crew","wrong-version","heat-mismatch","null-fire","null-launcher","empty-work-stock","fractional-assigned","fractional-pending","fractional-transfer","fractional-supplies","fractional-ammo","over-stock","over-ammo","over-cooldown","over-operation","carry-one","work-two","fuel-over","negative-ammo"]:
		var bad := state.duplicate(true)
		var vessel: Dictionary = bad.vessels[bad.flagshipId]
		match mutation:
			"extra-vessel-key": vessel.unowned = 1
			"extra-fire-key": vessel.fireControl.unowned = 1
			"extra-launcher-key": vessel.fireLauncher.unowned = 1
			"extra-ammo-key": vessel.fireLauncher.ammo.solid = 1
			"persisted-derived-crew": vessel.availableCrew = 0
			"wrong-version": vessel.fireControl.version = "ship-fire-r2"
			"heat-mismatch": vessel.damage.fire = 19.0
			"null-fire": vessel.fireControl = null
			"null-launcher": vessel.fireLauncher = null
			"empty-work-stock": vessel.fireControl.supplies = 0
			"fractional-assigned": vessel.fireControl.assignedFirefighters = 1.5
			"fractional-pending": vessel.fireControl.pendingFirefighters = 1.5
			"fractional-transfer": vessel.fireControl.transferTicks = 17.5
			"fractional-supplies": vessel.fireControl.supplies = 4.5
			"fractional-ammo": vessel.fireLauncher.ammo["fire-ball"] = 2.5
			"over-stock": vessel.fireControl.supplies = 601
			"over-ammo": vessel.fireLauncher.ammo["thorn-ball"] = 61
			"over-cooldown": vessel.fireLauncher.cooldownSeconds = 120.01
			"over-operation": vessel.fireLauncher.operationSeconds = 2.01
			"carry-one": vessel.fireControl.crewDamageCarry = 1.0
			"work-two": vessel.fireControl.workCarry = 2.0
			"fuel-over": vessel.fireControl.fuelSeconds = 72.01
			"negative-ammo": vessel.fireLauncher.ammo["fire-ball"] = -1
		reject(session,bad,mutation)
	for field: String in ["heat","fuelSeconds","wetness","crewDamageCarry","assignedFirefighters","pendingFirefighters","transferTicks","supplies","workCarry"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireControl[field] = true
		reject(session,bad,"bool fireControl." + field)
	for field: String in ["cooldownSeconds","operationSeconds"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireLauncher[field] = true
		reject(session,bad,"bool fireLauncher." + field)
	for payload: String in ["fire-ball","thorn-ball"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireLauncher.ammo[payload] = true
		reject(session,bad,"bool launcher ammo " + payload)

func _population_and_operator_budget(session: RefCounted, state: Dictionary) -> void:
	for field: String in ["assignedFirefighters","pendingFirefighters"]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireControl[field] = 4
		reject(session,bad,field + " exceeds seven able minus four active launcher operators")
		bad = state.duplicate(true)
		bad.vessels[bad.flagshipId].fireControl[field] = 8
		bad.vessels[bad.flagshipId].fireLauncher.operationSeconds = 0.0
		reject(session,bad,field + " exceeds total able even without launcher operation")
	var boundary := state.duplicate(true)
	boundary.vessels[boundary.flagshipId].fireControl.pendingFirefighters = 3
	check(session.restore(raw_save(boundary)), "assigned and pending are overlapping reservation teams; max three fits remaining three")
	boundary.vessels[boundary.flagshipId].fireLauncher.operationSeconds = 0.0
	boundary.vessels[boundary.flagshipId].fireControl.assignedFirefighters = 7
	boundary.vessels[boundary.flagshipId].fireControl.pendingFirefighters = 7
	check(session.restore(raw_save(boundary)), "idle launcher reserves no operators while positive cooldown persists")
	var empty := state.duplicate(true)
	var vessel: Dictionary = empty.vessels[empty.flagshipId]
	vessel.crew.able = 0
	vessel.fireControl.assignedFirefighters = 0
	vessel.fireControl.pendingFirefighters = 0
	check(session.restore(raw_save(empty)), "zero-able population with zero fire team remains structurally valid")
	check(session.restore(raw_save(state)), "population tests leave original fixture restored")

func _nonfinite_json(session: RefCounted, state: Dictionary) -> void:
	var original := raw_save(state)
	var before: Dictionary = session.snapshot()
	for token: String in ["1e999","-1e999","NaN","Infinity","-Infinity"]:
		var malformed := original.replace('"fuelSeconds":17.25','"fuelSeconds":' + token)
		check(malformed != original, "nonfinite JSON fixture targets fuel field")
		check(not Codec.decode(malformed).get("ok",false), "decode rejects nonfinite fuel token " + token)
		check(not session.restore(malformed) and session.snapshot() == before, "nonfinite restore stays atomic " + token)
	for value: float in [NAN,INF,-INF]:
		var bad := state.duplicate(true)
		bad.vessels[bad.flagshipId].fireLauncher.cooldownSeconds = value
		check(Codec.encode(bad,UTC).is_empty(), "encode refuses nonfinite launcher clock")

func finish() -> void:
	print("Mingqi fire persistence: ","PASS" if failures == 0 else "FAIL"," (",checks," checks, ",failures," failures)")
	quit(0 if failures == 0 else 1)
