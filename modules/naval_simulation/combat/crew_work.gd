extends RefCounted
## Pure accepted-interval labour receipts. Caller owns time, state and eligibility.

const VERSION := "crew-work-r1"
const STEP_SECONDS := 1.0 / 60.0
const MAX_SHIPS := 128
const MAX_CREW := 1000
const INT64_EXCLUSIVE_FLOAT_BOUND := 9223372036854775808.0
const INPUT_FIELDS := ["shipId", "able", "launcherCrew", "fireDutyCrew", "operational", "position", "velocity", "hull"]
const ROW_FIELDS := ["shipId", "totalAbleAtStart", "totalAbleAtEnd", "launcherCrew", "fireDutyCrew", "availableCrew", "unavailableCrew", "position", "velocity", "hullAtStart"]
const ROW_COUNTS := ["totalAbleAtStart", "totalAbleAtEnd", "launcherCrew", "fireDutyCrew", "availableCrew", "unavailableCrew"]
const RECEIPT_FIELDS := ["version", "battleId", "tick", "stepSeconds", "ships"]
const CARRY_FIELDS := ["version", "ticks", "attackerPersonTicksByShip", "defenderPersonTicks"]

static func sample(input: Dictionary) -> Dictionary:
	if not _shape(input, INPUT_FIELDS): return _row_result(false, {}, "invalid-input-shape")
	if not _id(input.shipId, 256): return _row_result(false, {}, "invalid-ship-id")
	if not _count(input.able, MAX_CREW) or not _count(input.launcherCrew, 4) or not _count(input.fireDutyCrew, 128):
		return _row_result(false, {}, "invalid-crew-count")
	if int(input.launcherCrew) + int(input.fireDutyCrew) > int(input.able):
		return _row_result(false, {}, "crew-overbooked")
	if typeof(input.operational) != TYPE_BOOL or not _geometry(input.position) or not _geometry(input.velocity) or not _nonnegative(input.hull):
		return _row_result(false, {}, "invalid-ship-context")
	var remaining := int(input.able) - int(input.launcherCrew) - int(input.fireDutyCrew)
	var row := {
		"shipId":input.shipId, "totalAbleAtStart":int(input.able), "totalAbleAtEnd":int(input.able),
		"launcherCrew":int(input.launcherCrew), "fireDutyCrew":int(input.fireDutyCrew),
		"availableCrew":remaining if input.operational else 0,
		"unavailableCrew":0 if input.operational else remaining,
		"position":_copy_geometry(input.position), "velocity":_copy_geometry(input.velocity), "hullAtStart":float(input.hull),
	}
	return _row_result(true, row, "")

static func finish_row(row: Variant, able_end: Variant) -> Dictionary:
	if not valid_row(row): return _row_result(false, {}, "invalid-row")
	if not _count(able_end, int(row.totalAbleAtStart)):
		return _row_result(false, {}, "invalid-end-population")
	var next := _copy_row(row)
	next.totalAbleAtEnd = int(able_end)
	return _row_result(true, next, "")

static func valid_row(row: Variant) -> bool:
	if not _shape(row, ROW_FIELDS) or not _id(row.shipId, 256): return false
	for field: String in ROW_COUNTS:
		if not _count(row[field], MAX_CREW): return false
	if not _count(row.launcherCrew, 4) or not _count(row.fireDutyCrew, 128): return false
	if int(row.totalAbleAtEnd) > int(row.totalAbleAtStart): return false
	if int(row.launcherCrew) + int(row.fireDutyCrew) + int(row.availableCrew) + int(row.unavailableCrew) != int(row.totalAbleAtStart): return false
	# The operational bit in sample makes all unreserved people available or
	# unavailable. Mixed leftovers cannot have come from this version's sample.
	if int(row.availableCrew) > 0 and int(row.unavailableCrew) > 0: return false
	return _geometry(row.position) and _geometry(row.velocity) and _nonnegative(row.hullAtStart)

static func batch(battle_id: Variant, tick: Variant, rows: Variant) -> Dictionary:
	if not _id(battle_id, 4096) or not _tick(tick) or not _rows(rows):
		return {"ok":false, "receipt":{}, "reason":"invalid-batch"}
	var ships: Array = []
	for row: Dictionary in rows: ships.append(_copy_row(row))
	return {"ok":true, "receipt":{"version":VERSION, "battleId":battle_id, "tick":int(tick), "stepSeconds":STEP_SECONDS, "ships":ships}, "reason":""}

static func valid(receipt: Variant) -> bool:
	if not _shape(receipt, RECEIPT_FIELDS): return false
	return typeof(receipt.version) == TYPE_STRING and receipt.version == VERSION and _id(receipt.battleId, 4096) and _tick(receipt.tick) and _finite(receipt.stepSeconds) and receipt.stepSeconds == STEP_SECONDS and _rows(receipt.ships)

static func initial_carry() -> Dictionary:
	return {"version":VERSION, "ticks":0, "attackerPersonTicksByShip":{}, "defenderPersonTicks":0}

static func valid_carry(carry: Variant) -> bool:
	if not _shape(carry, CARRY_FIELDS) or typeof(carry.version) != TYPE_STRING or carry.version != VERSION or not _count(carry.ticks, 59): return false
	var maximum := int(carry.ticks) * MAX_CREW
	if not _count(carry.defenderPersonTicks, maximum): return false
	return _person_ticks(carry.attackerPersonTicksByShip, maximum)

static func accumulate(carry: Dictionary, attackers: Dictionary, defenders: Variant) -> Dictionary:
	if not valid_carry(carry) or not _person_ticks(attackers, MAX_CREW) or not _count(defenders, MAX_CREW):
		return _carry_result(false, carry.duplicate(true), {}, "invalid-work-input")
	var totals := {}
	for id: String in carry.attackerPersonTicksByShip: totals[id] = int(carry.attackerPersonTicksByShip[id])
	for id: String in attackers: totals[id] = int(totals.get(id, 0)) + int(attackers[id])
	if totals.size() > MAX_SHIPS:
		return _carry_result(false, carry.duplicate(true), {}, "too-many-ships")
	var ticks := int(carry.ticks) + 1
	var defender_ticks := int(carry.defenderPersonTicks) + int(defenders)
	if ticks < 60:
		return _carry_result(true, {"version":VERSION, "ticks":ticks, "attackerPersonTicksByShip":totals, "defenderPersonTicks":defender_ticks}, {}, "")
	var attacker_ticks := 0
	for count: int in totals.values(): attacker_ticks += count
	var pulse := {"ticks":60, "attackerPersonTicksByShip":totals, "defenderPersonTicks":defender_ticks, "attackers":float(attacker_ticks) / 60.0, "defenders":float(defender_ticks) / 60.0}
	return _carry_result(true, initial_carry(), pulse, "")

static func _rows(rows: Variant) -> bool:
	if typeof(rows) != TYPE_ARRAY or rows.size() > MAX_SHIPS: return false
	var seen := {}
	for row: Variant in rows:
		if not valid_row(row) or seen.has(row.shipId): return false
		seen[row.shipId] = true
	return true

static func _person_ticks(values: Variant, maximum: int) -> bool:
	if typeof(values) != TYPE_DICTIONARY or values.size() > MAX_SHIPS: return false
	for id: Variant in values:
		if not _id(id, 256) or not _count(values[id], maximum): return false
	return true

static func _shape(value: Variant, fields: Array) -> bool:
	if typeof(value) != TYPE_DICTIONARY or value.size() != fields.size(): return false
	for field: String in fields:
		if not value.has(field): return false
	return true

static func _id(value: Variant, maximum: int) -> bool:
	return typeof(value) == TYPE_STRING and value.length() >= 1 and value.length() <= maximum

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _nonnegative(value: Variant) -> bool:
	return _finite(value) and value >= 0.0

static func _count(value: Variant, maximum: int) -> bool:
	if typeof(value) == TYPE_INT: return value >= 0 and value <= maximum
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value >= 0.0 and value <= maximum and floor(value) == value

static func _tick(value: Variant) -> bool:
	if typeof(value) == TYPE_INT: return value >= 1
	return typeof(value) == TYPE_FLOAT and is_finite(value) and value >= 1.0 and value < INT64_EXCLUSIVE_FLOAT_BOUND and floor(value) == value

static func _geometry(value: Variant) -> bool:
	return _shape(value, ["x", "z"]) and _finite(value.x) and _finite(value.z)

static func _copy_geometry(value: Dictionary) -> Dictionary:
	return {"x":float(value.x), "z":float(value.z)}

static func _copy_row(row: Dictionary) -> Dictionary:
	var result := {"shipId":row.shipId, "position":_copy_geometry(row.position), "velocity":_copy_geometry(row.velocity), "hullAtStart":float(row.hullAtStart)}
	for field: String in ROW_COUNTS: result[field] = int(row[field])
	return result

static func _row_result(ok: bool, row: Dictionary, reason: String) -> Dictionary:
	return {"ok":ok, "row":row, "reason":reason}

static func _carry_result(ok: bool, carry: Dictionary, pulse: Dictionary, reason: String) -> Dictionary:
	return {"ok":ok, "carry":carry, "pulse":pulse, "reason":reason}
