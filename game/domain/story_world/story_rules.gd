extends RefCounted
## Story business math copied from the frozen legacy oracle
## (game/domain/legacy/adventure_session.gd lines 83-84, 219-226, 334-338).
## Pure functions only: no state, no I/O. Parity tests in
## tests/test_story_world_session.gd pin every rule against a real legacy Session
## so a drift in either copy fails the suite.

const DOCK_MAX_DISTANCE := 55.0
const DOCK_MAX_SPEED := 1.5
const BOARD_MAX_DISTANCE := 36.0
const BOARD_MAX_RELATIVE_SPEED := 3.0
const BOARD_HULL_WEAKENED := 0.65
const BOARD_CREW_WEAKENED := 0.6
const STOCK_CAPACITY := 100000
const GOODS := ["grain", "wood", "iron", "silk", "porcelain", "spices"]
# Frozen legacy oracle values (game/domain/legacy/catalog.gd SHIP_PROFILES).
const SHIP_PROFILES := {
	"fisherman": {"crew": 24, "capacity": 45, "minCrew": 4, "price": 320},
	"patrol": {"crew": 60, "capacity": 70, "minCrew": 12, "price": 700},
	"fuchuan": {"crew": 100, "capacity": 120, "minCrew": 24, "price": 1000},
	"merchant": {"crew": 70, "capacity": 220, "minCrew": 14, "price": 850},
	"voc": {"crew": 120, "capacity": 180, "minCrew": 30, "price": 1600},
	"heavy": {"crew": 160, "capacity": 150, "minCrew": 40, "price": 2400},
}

static func ship_profile(kind: String) -> Dictionary:
	return SHIP_PROFILES.get(kind, SHIP_PROFILES["merchant"])

static func profile_min_crew(kind: String) -> int:
	return int(ship_profile(kind).minCrew)

# Deterministic market drift: prices breathe around their base as days pass,
# identical across runs and save/restore. Seeded by port+good so each market
# moves on its own line without any RNG state.
static func price_factor(day: int, port_id: String, good: String) -> float:
	var seed_material := "%s|%s" % [port_id, good]
	var hash_value := 0
	for index: int in seed_material.length():
		hash_value = (hash_value * 31 + seed_material.unicode_at(index)) & 0x7fffffff
	var wave := sin(float(day) * 0.7 + float(hash_value % 360) * 0.01745329)
	return clampf(1.0 + 0.25 * wave, 0.7, 1.3)

# Companion specialties (doc heroes-and-companions): a person's role changes
# real outcomes. Every listed specialty maps to a live mechanic; multiple
# specialists stack multiplicatively where applicable, bounded by engine caps.
const ROLE_SPEED := {"navigator": 1.1}
const ROLE_RELOAD := {"gunner": 0.85}
const ROLE_UPKEEP := {"purser": 0.9, "cook": 0.95, "musician": 0.95}
const ROLE_BOARDING_VOLUNTEERS := {"boarder": 0.75}
const ROLE_REPAIR_COST := {"shipwright": 0.5}
const ROLE_CHARTER_COST := {"diplomat": 0.8}
const ROLE_RESCUE_CREW := {"rescuer": 2}
const ROLE_REPAIR_CREW := {"doctor": 10}
const ROLE_IDENTIFY_RADIUS := {"lookout": 180.0}
const ROLE_ESCORT_SPEED := {"signaler": 0.15}

static func _role_factor(table: Dictionary, roles: Array, fallback: float = 1.0) -> float:
	var factor := fallback
	for role: Variant in roles:
		if table.has(str(role)):
			factor *= float(table[str(role)]) if fallback == 1.0 else float(table[str(role)])
	return factor

static func boarding_volunteer_multiplier(roles: Array) -> float:
	for role: Variant in roles:
		if ROLE_BOARDING_VOLUNTEERS.has(str(role)):
			return float(ROLE_BOARDING_VOLUNTEERS[str(role)])
	return 1.0

static func repair_cost_multiplier(roles: Array) -> float:
	for role: Variant in roles:
		if ROLE_REPAIR_COST.has(str(role)):
			return float(ROLE_REPAIR_COST[str(role)])
	return 1.0

static func charter_cost_multiplier(roles: Array) -> float:
	for role: Variant in roles:
		if ROLE_CHARTER_COST.has(str(role)):
			return float(ROLE_CHARTER_COST[str(role)])
	return 1.0

static func rescue_crew_bonus(roles: Array) -> int:
	var bonus := 0
	for role: Variant in roles:
		bonus += int(ROLE_RESCUE_CREW.get(str(role), 0))
	return bonus

static func repair_crew_bonus(roles: Array) -> int:
	var bonus := 0
	for role: Variant in roles:
		bonus += int(ROLE_REPAIR_CREW.get(str(role), 0))
	return bonus

static func identify_radius(roles: Array) -> float:
	for role: Variant in roles:
		if ROLE_IDENTIFY_RADIUS.has(str(role)):
			return float(ROLE_IDENTIFY_RADIUS[str(role)])
	return 120.0

static func escort_speed_bonus(roles: Array) -> float:
	var bonus := 0.0
	for role: Variant in roles:
		bonus += float(ROLE_ESCORT_SPEED.get(str(role), 0.0))
	return bonus

static func speed_multiplier(roles: Array) -> float:
	var factor := 1.0
	for role: Variant in roles:
		factor *= float(ROLE_SPEED.get(str(role), 1.0))
	return factor

static func reload_multiplier(roles: Array) -> float:
	var factor := 1.0
	for role: Variant in roles:
		factor *= float(ROLE_RELOAD.get(str(role), 1.0))
	return factor

static func upkeep_multiplier(roles: Array) -> float:
	var factor := 1.0
	for role: Variant in roles:
		factor *= float(ROLE_UPKEEP.get(str(role), 1.0))
	return factor

# Ship system upgrades (legacy shipyard semantics): four systems, three levels,
# real silver, bounded effects. Hull levels raise both cap and current hull.
const UPGRADE_SYSTEMS := ["hull", "cannons", "sails", "equipment"]
const UPGRADE_MAX_LEVEL := 3

static func upgrade_cost(system: String, level: int) -> int:
	return (int(level) + 1) * (250 if system == "cannons" else 180)

static func upgraded_max_hull(level: int) -> int:
	return int(round(100.0 * pow(1.2, float(clampi(int(level), 0, UPGRADE_MAX_LEVEL)))))

# Sea weather (doc 灾异/风灾 pressure axis): three states with deterministic
# wind. Storm wind is strong and unfriendly; all hands reef sails (cap 0.55).
const WEATHERS := ["calm", "breeze", "storm"]
const WEATHER_WIND := {
	"calm": {"x": 1.0, "y": 0.2, "speed": 4.0},
	"breeze": {"x": 0.86, "y": 0.5, "speed": 7.0},
	"storm": {"x": -1.0, "y": 0.6, "speed": 13.0},
}

static func weather_wind(sea: String) -> Dictionary:
	return (WEATHER_WIND.get(sea, WEATHER_WIND["breeze"]) as Dictionary).duplicate(true)

static func weather_sail_cap(sea: String) -> float:
	return 0.55 if sea == "storm" else 1.0

# Wounds and medicine (doc 救援/照护): failures cost hands to the sick berth,
# not to the sea. Doctors return one hand a day at sea; ports with a repair
# yard (or a doctor ashore) treat paid recoveries.
const BOARDING_FAILURE_WOUNDED := 4
const LAND_FAILURE_WOUNDED := 6
const TREAT_COST_PER_HEAD := 2

# Partnership voyages (doc 半独立合伙人/分利): a partner sails capital to a
# foreign market and back; the yield follows the real price-factor spread
# between the two markets that very day. The partner keeps two fifths.
const PARTNER_PLAYER_SHARE := 0.6
const PARTNER_SPREAD_FLOOR := -0.3
const PARTNER_SPREAD_CEILING := 0.6

static func partner_spread(home_factors: Dictionary, away_factors: Dictionary) -> float:
	var home_average := 0.0
	var away_average := 0.0
	for good: String in GOODS:
		home_average += float(home_factors.get(good, 1.0))
		away_average += float(away_factors.get(good, 1.0))
	return clampf(away_average / float(GOODS.size()) - home_average / float(GOODS.size()), PARTNER_SPREAD_FLOOR, PARTNER_SPREAD_CEILING)

static func partner_player_return(capital: int, spread: float) -> int:
	return int(round(float(capital) * (1.0 + spread) * PARTNER_PLAYER_SHARE))

static func dock_gate(distance: float, speed: float) -> bool:
	return distance <= DOCK_MAX_DISTANCE and speed <= DOCK_MAX_SPEED

static func board_gate(distance: float, relative_speed: float, hull_ratio: float, crew_ratio: float) -> bool:
	if distance > BOARD_MAX_DISTANCE or relative_speed > BOARD_MAX_RELATIVE_SPEED:
		return false
	return not (hull_ratio > BOARD_HULL_WEAKENED and crew_ratio > BOARD_CREW_WEAKENED)

static func capture_volunteers(min_crew: int, target_crew: int) -> int:
	return maxi(0, int(min_crew) - int(floor(float(target_crew) / 2.0)))

static func relation_factor(tax: float, relation: float) -> float:
	return maxf(1.0 - clampf(relation, -100.0, 100.0) * 0.002, sqrt((1.0 - tax) / (1.0 + tax)))

static func ask_bid(tax: float, relation: float) -> Dictionary:
	var factor := relation_factor(tax, relation)
	var ask := factor * (1.0 + tax)
	var bid := minf((1.0 - tax) / factor, ask)
	return {"ask": ask, "bid": bid}

static func trade_value(quantity: int, price: float, stock: int, stock_cap: int, buy: bool) -> float:
	var value := 0.0
	for i in int(quantity):
		var level: int = stock - i if buy else stock + i + 1
		value += price * (1.15 if level < stock_cap * 0.25 else 0.9 if level > stock_cap * 1.5 else 1.0)
	return value

static func quote(buy: bool, quantity: int, price: float, stock: int, stock_cap: int, tax: float, relation: float) -> Dictionary:
	if typeof(quantity) != TYPE_INT or quantity < 1 or quantity > 1000000:
		return {"ok": false, "reason": "数量无效"}
	if buy and stock < quantity:
		return {"ok": false, "reason": "港口库存不足"}
	if not buy and stock + quantity > STOCK_CAPACITY:
		return {"ok": false, "reason": "港口库存容量不足，无法收购这批货物"}
	var rates := ask_bid(tax, relation)
	var value := trade_value(quantity, price, stock, stock_cap, buy)
	if buy:
		return {"ok": true, "cost": int(ceil(value * rates.ask))}
	return {"ok": true, "reward": int(floor(value * rates.bid))}

static func terms_digest(terms: Dictionary) -> String:
	return JSON.stringify(_canonical(terms)).sha256_text()

static func _canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var keys: Array = value.keys()
		keys.sort()
		var ordered := {}
		for key: Variant in keys:
			ordered[key] = _canonical(value[key])
		return ordered
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_canonical(item))
		return items
	return value
