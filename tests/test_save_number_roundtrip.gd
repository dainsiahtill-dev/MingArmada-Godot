extends SceneTree
## Canonical save numbers must preserve exact game state, without weakening guards.
const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const UTC = "2026-10-12T00:00:00.000Z"
const RAW_NUMBER = "__number_roundtrip_raw_token__"
# Hand-pinned binary64 fixtures; clocks, compensation, poses and controls only.
# These are bounded game-scale cases, not a universal decimal-parser contract.
const NUMBER_CASES = [
	["999999999999c93f", "remainder immediately below 0.2"],
	["9a9999999999c93f", "remainder 0.2"],
	["999999999999b93f", "remainder immediately below 0.1"],
	["111111111111913f", "native tick 1/60"],
	["111111111111813f", "half native tick 1/120"],
	["666666666666e63f", "remainder 0.7"],
	["ffffffffffffef3f", "remainder immediately below one"],
	["cdcccccccc0c5540", "clock 84.2"],
	["6666666666f0a640", "clock 2936.2"],
	["cdcccccccc209c40", "clock 1800.2"],
	["0100000000005540", "clock immediately above 84"],
	["000000000000903c", "clock compensation 2^-54"],
	["000000000000703c", "clock compensation 2^-56"],
	["00000000000090bc", "negative clock compensation"],
	["bdd7326b47491ec0", "position -7.571561503389543"],
	["6601839889d41040", "position 4.207556136127414"],
	["c99906e7351e2340", "actual checkpoint flagship z 9.559004993015053"],
	["ffffffffff87c340", "position immediately below 10000"],
	["010000000088c340", "position immediately above 10000"],
	["010000000088c3c0", "negative position beyond 10000"],
	["0000000000046040", "position 128.125"],
	["00000000000460c0", "position -128.125"],
	["182d4454fb21e93f", "heading pi/4"],
	["182d4454fb21e9bf", "heading -pi/4"],
	["ffffffffffffe73f", "speed immediately below 0.75"],
	["010000000000e83f", "speed immediately above 0.75"],
	["ffffffffffff5840", "damage immediately below 100"],
	["9a9999999999a93f", "cooldown 0.05"],
	["9a9999999999b9bf", "rudder -0.1"],
]
var assertions := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)

func from_bits(hex: String) -> float:
	return hex.hex_decode().decode_double(0)

func bits(value: Variant) -> String:
	return PackedFloat64Array([float(value)]).to_byte_array().hex_encode()

func exact(a: Variant, b: Variant, path: String = "state") -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		if bits(a) == bits(b): return true
		printerr("EXACT_NUMBER_DIFF ", path, " expected=", bits(a), " actual=", bits(b))
		return false
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		var same := true
		for key in a:
			if not b.has(key) or not exact(a[key], b[key], path + "." + str(key)): same = false
		return same
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		var same := true
		for i in a.size():
			if not exact(a[i], b[i], path + "[" + str(i) + "]"): same = false
		return same
	return typeof(a) == typeof(b) and a == b

func material(state: Dictionary) -> Dictionary:
	var ships := {}
	for id in state.vessels:
		var ship: Dictionary = state.vessels[id]
		ships[id] = {"crew": ship.crew, "cargo": ship.cargo, "ammo": ship.combat.ammo, "revision": ship.revision, "controlsRevision": ship.controlsRevision}
	return {"captain": state.captain, "debt": state.debt, "revision": state.revision, "nextId": state.nextId, "ships": ships, "settlements": state.settlements, "contracts": state.contracts, "prizes": state.prizes, "casualtyOrdinals": state.casualtyOrdinals}

func envelope(state: Dictionary) -> String:
	return JSON.stringify({"version": 2, "campaignId": state.campaignId, "mode": "mingqi-1650", "savedAtUtc": UTC, "simulationSeconds": state.simulationSeconds, "state": state}, "", false, true)

func roundtrip(state: Dictionary, label: String) -> void:
	var validation := Codec.new()
	check(validation._validate(state, validation._state_schema(), "state") and validation._relations(state), label + " original state is valid: " + validation.error)
	var encoded: String = Codec.encode(state, UTC)
	check(not encoded.is_empty(), label + " real Codec.encode succeeds")
	if encoded.is_empty(): return
	var decoded: Dictionary = Codec.decode(encoded)
	check(decoded.get("ok", false), label + " real Codec.decode succeeds: " + str(decoded.get("code", "")))
	if not decoded.get("ok", false): return
	check(exact(material(state), material(decoded.state), "material"), label + " money, revisions, receipts and crew/counts remain exact")
	check(exact(state, decoded.state), label + " every state field remains exact")
	check(bits(decoded.envelope.simulationSeconds) == bits(state.simulationSeconds), label + " envelope clock remains exact")
	var second: Dictionary = Codec.decode(Codec.encode(decoded.state, UTC))
	check(second.get("ok", false) and exact(state, second.get("state", {})), label + " second save retains original exact state")

func campaign_roundtrips() -> void:
	var campaign := Campaign.new()
	var advanced: Dictionary = campaign.advance(1.0 / 60.0)
	check(advanced.get("ok", false) and advanced.get("acceptedSeconds") == 1.0 / 60.0, "real Campaign.advance accepts one native tick")
	var advanced_state: Dictionary = campaign.snapshot()
	check(bits(advanced_state.macroRemainder) == "111111111111913f", "real campaign clock starts from pinned native tick bits")
	roundtrip(advanced_state, "actual one native tick")
	var state: Dictionary = Campaign.new().snapshot()
	state.macroSeconds = 84
	state.macroRemainder = from_bits("999999999999c93f")
	state.simulationSeconds = state.macroSeconds + state.macroRemainder
	check(JSON.stringify(state.macroRemainder, "", false, true) == "0.19999999999999998", "pinned lower 0.2 has actual checkpoint canonical token")
	roundtrip(state, "84-second lower remainder reproduction")
	state = Campaign.new().snapshot()
	state.macroSeconds = 1800
	state.calendar = {"year": 1650, "month": 1, "day": 2}
	state.macroRemainder = from_bits("999999999999c93f")
	state.simulationSeconds = state.macroSeconds + state.macroRemainder
	state.clockCompensation = from_bits("000000000000903c")
	var flagship: Dictionary = state.vessels[state.flagshipId]
	flagship.pose.position = {"x": from_bits("bdd7326b47491ec0"), "z": from_bits("c99906e7351e2340")}
	flagship.pose.speed = from_bits("ffffffffffffe73f")
	roundtrip(state, "calendar boundary with canonical clock compensation and native pose")

func canonical_parser_numbers() -> void:
	for row in NUMBER_CASES:
		var expected: float = from_bits(row[0])
		var token: String = JSON.stringify(expected, "", false, true)
		var parser := Codec.new()
		var parsed: Variant = parser._parse(token)
		check(parser.error.is_empty() and typeof(parsed) == TYPE_FLOAT, row[1] + " accepted by real codec parser")
		if parser.error.is_empty() and typeof(parsed) == TYPE_FLOAT:
			check(bits(parsed) == row[0], row[1] + " canonical token " + token + " preserves bits " + row[0] + ", got " + bits(parsed))

func fallback_numbers() -> void:
	# Alternate spellings and unsupported extreme ranges keep the String parser.
	# A nearby finite canonical token match remains an exact proof at any scale.
	for token in ["0", "-0", "0.0", "-0.0", "1.9999999999999998e-1", "19.999999999999998e-2", "19999999999999998e-17", "0.20000000000000000", "1e-320", "-1e-320", "2.2250738585072014e-308", "-2.2250738585072014e-308", "1e-400", "-1e-400"]:
		var parser := Codec.new()
		var parsed: Variant = parser._parse(token)
		check(parser.error.is_empty() and typeof(parsed) == TYPE_FLOAT and bits(parsed) == bits(token.to_float()), "noncanonical/zero/subnormal token keeps fallback: " + token)
	for row in [["5e-324", "0100000000000000"], ["-5e-324", "0100000000000080"]]:
		var parser := Codec.new()
		var parsed: Variant = parser._parse(row[0])
		check(parser.error.is_empty() and typeof(parsed) == TYPE_FLOAT and bits(parsed) == row[1], "minimum signed subnormal recovers exact canonical token: " + row[0])
	for token in ["0.125", "-0.125"]:
		var parser := Codec.new()
		var parsed: Variant = parser._parse(token)
		check(parser.error.is_empty() and parsed == (0.125 if token[0] != "-" else -0.125), "signed normal fraction preserves sign: " + token)

func schema_guards() -> void:
	# The old conversion rounded this real fraction to 1. Count validators must
	# reject it at each numeric field, before any later business relation runs.
	for field in ["money", "revision", "crew"]:
		for token in ["0.9999999999999999", "5e-324"]:
			var state: Dictionary = Campaign.new().snapshot()
			var path := "envelope.state.revision"
			match field:
				"money": state.captain.silver = RAW_NUMBER; path = "envelope.state.captain.silver"
				"revision": state.revision = RAW_NUMBER
				"crew": state.vessels[state.flagshipId].crew.able = RAW_NUMBER; path = "envelope.state.vessels." + state.flagshipId + ".crew.able"
			var raw: String = envelope(state).replace('"' + RAW_NUMBER + '"', token)
			var decoded: Dictionary = Codec.decode(raw)
			check(not decoded.get("ok", false) and decoded.get("code") == "invalid-save: " + path, field + " rejects canonical fraction in count validator: " + token)
	for field in ["money", "revision", "crew"]:
		for token in ["0.19999999999999998", "0.016666666666666666", "1.0000000000000002", "-1", "9007199254740992"]:
			var state: Dictionary = Campaign.new().snapshot()
			match field:
				"money": state.captain.silver = RAW_NUMBER
				"revision": state.revision = RAW_NUMBER
				"crew": state.vessels[state.flagshipId].crew.able = RAW_NUMBER
			var raw: String = envelope(state).replace('"' + RAW_NUMBER + '"', token)
			var decoded: Dictionary = Codec.decode(raw)
			check(not decoded.get("ok", false) and str(decoded.get("code", "")).begins_with("invalid-save:"), field + " rejects fractional, negative or unsafe number " + token)
	var count_parser := Codec.new()
	var maximum: Variant = count_parser._parse("9007199254740991")
	check(count_parser.error.is_empty() and Codec._count(maximum) and maximum == 9007199254740991, "largest safe integer remains exact and count-valid")
	var state: Dictionary = Campaign.new().snapshot()
	for i in 129: state.vessels["limit-" + str(i)] = {}
	check(str(Codec.decode(envelope(state)).get("code", "")).begins_with("save-limit:"), "vessel record limit remains enforced")
	state = Campaign.new().snapshot()
	for i in 4097: state.orders.append({})
	check(not Codec.decode(envelope(state)).get("ok", false), "order array limit remains enforced")

func parser_guards() -> void:
	for row in [
		['{"version":2,"version":2}', "duplicate-key:"],
		['{"__proto__":0}', "unsafe-key:"],
		['{"constructor":0}', "unsafe-key:"],
		['{"prototype":0}', "unsafe-key:"],
		['{"x":1e309}', "invalid-save:"],
		['{"x":-1e309}', "invalid-save:"],
		['{"x":NaN}', "invalid-json:"],
		['{"x":Infinity}', "invalid-json:"],
		['{"x":01}', "invalid-json:"],
		['{"x":1} trailing', "invalid-json:"],
		['{"x":1', "invalid-json:"],
	]:
		var decoded: Dictionary = Codec.decode(row[0])
		check(not decoded.get("ok", false) and str(decoded.get("code", "")).begins_with(row[1]), "parser guard retained for " + row[0])
	for row in [
		["[".repeat(33) + "0" + "]".repeat(33), "depth"],
		["[" + "null,".repeat(250000) + "null]", "node"],
		[" ".repeat(16777217), "byte"],
	]:
		var parser := Codec.new()
		parser._parse(row[0])
		check(parser.error.begins_with("save-limit:"), row[1] + " parser limit retained")

func _initialize() -> void:
	campaign_roundtrips()
	canonical_parser_numbers()
	fallback_numbers()
	schema_guards()
	parser_guards()
	print("SAVE_NUMBER_ROUNDTRIP_TESTS assertions=", assertions, " failures=", failures)
	quit(0 if failures == 0 else 1)
