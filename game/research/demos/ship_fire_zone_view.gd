extends "res://game/presentation/combat/combat_atmosphere.gd"
## Research-only projection of canonical r2 zones on current, supplied deck poses.
## One real ship owns one observed-slot budget; zones never become pseudo-ships.
const Spread = preload("res://modules/naval_simulation/combat/fire_spread.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const MAX_LIVE_FIRES: int = 16
const EMISSION_SECONDS: float = 0.25
const ZONES: Array[String] = ["bow", "mid", "stern"]
var _live: Dictionary = {}
var _records: Dictionary = {}
var _capacity_smoke_evictions: int = 0

func apply_snapshot(native: Dictionary) -> void:
	if not _ready_state or not _number(native.get("time")) or float(native.time) < 0.0 or not native.get("ships", []) is Array:
		return
	super.apply_snapshot(native)
	var accepted: Dictionary = {}
	if _enabled:
		for value: Variant in native.get("ships", []):
			if not value is Dictionary: continue
			var ship: Dictionary = value
			if not ship.get("id") is String or String(ship.id).is_empty() or not _number(ship.get("hull")): continue
			if float(ship.hull) <= 0.0 or not Spread.valid(ship.get("fireSpread")) or not Fire.valid(ship.get("fireControl")): continue
			var summary: Dictionary = Spread.summary(ship.fireSpread)
			if summary != ship.fireControl or float(summary.heat) <= 0.0: continue
			var id: String = ship.id
			if accepted.has(id) or accepted.size() >= MAX_LIVE_FIRES: continue
			var previous: Dictionary = _live.get(id, {})
			var zones: Dictionary = {}
			for index: int in range(3):
				var heat: float = float(ship.fireSpread.heatByZone[index])
				if heat <= 0.0: continue
				var zone: String = ZONES[index]
				var old_zone: Dictionary = previous.get("zones", {}).get(zone, {})
				zones[zone] = {"heat": heat, "available": bool(old_zone.get("available", false)) and float(old_zone.get("anchor_time", -1.0)) == _time,
					"point": old_zone.get("point", Vector3.ZERO), "anchor_time": float(old_zone.get("anchor_time", -1.0))}
			accepted[id] = {"zones": zones, "heat": float(summary.heat)}
			if not _records.has(id):
				_records[id] = {"slot": -1, "emitted_smoke": 0, "emitted_flames": 0, "last_slot": {"slot": -1, "time": -1.0, "smoke": 0, "flame": 0, "zones": {}}}
	_live = accepted
	_remove_cold_flames()
	_render()

func refresh_anchors() -> void:
	super.refresh_anchors()
	if not _ready_state or not _enabled: return
	for id: String in _live:
		var ship: Dictionary = _live[id]
		var has_current_anchor: bool = false
		for zone: String in ship.zones:
			var row: Dictionary = ship.zones[zone]
			row.available = false
			if not _anchor_provider.is_valid() or not _water.is_valid(): continue
			var source: Variant = _anchor_provider.call(id + "|" + zone)
			if not source is Dictionary or not _number(source.get("time")) or float(source.time) != _time: continue
			if source.get("shipId") != id or source.get("zone") != zone: continue
			# The provider must supply its actual transformed Vector3, never a hull center.
			var point: Variant = source.get("position")
			if not point is Vector3 or not point.is_finite(): continue
			var height: Variant = _water.call(point.x, point.z, _time)
			if not _number(height) or point.y <= float(height): continue
			row.point = point
			row.anchor_time = _time
			row.available = true
			has_current_anchor = true
		if not has_current_anchor: continue
		var slot: int = int(floor(_time / EMISSION_SECONDS + 0.00000001))
		var record: Dictionary = _records[id]
		if slot <= int(record.slot): continue
		# A partially unavailable ship loses those allocations. Neither another zone
		# nor a later same-slot refresh may claim the unavailable zone's share.
		record.slot = slot
		_emit_slot(id, ship, record, slot)
	_render()

func _allocation(active: Array[String], budget: int, slot: int) -> Dictionary:
	var allocation: Dictionary = {}
	for zone: String in active: allocation[zone] = 1
	for extra: int in range(budget - active.size()):
		var zone: String = active[(slot + extra) % active.size()]
		allocation[zone] = int(allocation[zone]) + 1
	return allocation

func _emit_slot(id: String, ship: Dictionary, record: Dictionary, slot: int) -> void:
	var active: Array[String] = []
	for zone: String in ZONES:
		if ship.zones.has(zone): active.append(zone)
	if active.is_empty(): return
	var smoke: Dictionary = _allocation(active, 3, slot)
	var flame: Dictionary = _allocation(active, 4, slot)
	var wanted: int = 0
	for zone: String in active:
		if bool(ship.zones[zone].available): wanted += int(smoke[zone]) + int(flame[zone])
	_make_room(wanted)
	var last: Dictionary = {"slot": slot, "time": _time, "smoke": 0, "flame": 0, "zones": {}}
	for zone: String in active:
		var row: Dictionary = ship.zones[zone]
		var emitted: Dictionary = {"smoke": 0, "flame": 0}
		last.zones[zone] = emitted
		if not bool(row.available): continue
		var strength: float = clampf(float(row.heat) / 100.0, 0.0, 1.0)
		var token: String = "zone-live:" + id + ":" + zone + ":" + str(slot)
		var point: Vector3 = row.point
		for index: int in range(int(smoke[zone])):
			var phase: float = float(absi((token + ":s:" + str(index)).hash()) % 6283) / 1000.0
			var offset: Vector3 = Vector3(sin(phase) * 0.45, 0.15, cos(phase) * 0.45)
			var velocity: Vector3 = Vector3(sin(phase) * 0.25, 1.1 + strength, cos(phase) * 0.25)
			var before: int = _items.size()
			_add(token + ":smoke:" + str(index), "smoke", _time, 6.0, point + offset, velocity,
				1.1 + strength * 1.8, 0.65, Color(0.34, 0.32, 0.28, 0.22 + strength * 0.22), {"zone_ship": id, "zone": zone})
			if _items.size() > before: emitted.smoke = int(emitted.smoke) + 1
		for index: int in range(int(flame[zone])):
			var offset: Vector3 = Vector3(sin(float(index) * 1.7) * 0.65, 0.2, cos(float(index) * 1.7) * 0.55)
			var before: int = _items.size()
			_add(token + ":flame:" + str(index), "flame", _time, 0.5, point, Vector3.ZERO,
				1.8 + strength * 2.5, 0.0, Color(1.0, 0.75, 0.38, 0.8), {"zone_ship": id, "zone": zone, "zone_offset": offset, "wind": Vector3.ZERO})
			if _items.size() > before: emitted.flame = int(emitted.flame) + 1
		last.smoke = int(last.smoke) + int(emitted.smoke)
		last.flame = int(last.flame) + int(emitted.flame)
	record.last_slot = last
	record.emitted_smoke = int(record.emitted_smoke) + int(last.smoke)
	record.emitted_flames = int(record.emitted_flames) + int(last.flame)

func _make_room(wanted: int) -> void:
	# Six-second smoke would otherwise consume all shared capacity and starve
	# current deck flame. Under pressure, discard oldest smoke rather than detach
	# or multiply flame batches. The truncation is explicit diagnostic evidence.
	while _items.size() + wanted > _capacity:
		var oldest: int = -1
		for index: int in range(_items.size()):
			if _items[index].kind == "smoke":
				oldest = index
				break
		if oldest < 0: return
		_items.remove_at(oldest)
		_capacity_smoke_evictions += 1
		_dropped += 1

func _remove_cold_flames() -> void:
	for index: int in range(_items.size() - 1, -1, -1):
		var item: Dictionary = _items[index]
		if item.kind != "flame" or not item.has("zone_ship"): continue
		var id: String = item.zone_ship
		var zone: String = item.zone
		if not _live.has(id) or not _live[id].zones.has(zone): _items.remove_at(index)

func _sample(item: Dictionary) -> Dictionary:
	if not item.has("zone_ship"): return super._sample(item)
	var sample: Dictionary = super._sample(item)
	if sample.is_empty(): return {}
	var id: String = item.zone_ship
	var zone: String = item.zone
	if item.kind == "flame":
		if not _live.has(id) or not _live[id].zones.has(zone): return {}
		var row: Dictionary = _live[id].zones[zone]
		if not bool(row.available) or float(row.anchor_time) != _time or float(row.heat) <= 0.0: return {}
		var phase: float = float(item.phase)
		var point: Vector3 = row.point + item.zone_offset
		point.x += sin(_time * 7.0 + phase) * 0.12
		point.y += sin(_time * 9.0 + phase) * 0.12
		sample.position = [point.x, point.y, point.z]
		sample.size = float(sample.size) * (0.9 + 0.1 * sin(_time * 11.0 + phase))
		sample.alpha = float(sample.alpha) * clampf(float(row.heat) / 28.0, 0.0, 1.0)
	sample.ship_id = id
	sample.zone = zone
	return sample

func diagnostics() -> Dictionary:
	var result: Dictionary = super.diagnostics()
	var anchors: Dictionary = {}
	var burning: int = 0
	for id: String in _live:
		for zone: String in _live[id].zones:
			var row: Dictionary = _live[id].zones[zone]
			var point: Vector3 = row.point
			anchors[id + "|" + zone] = {"shipId": id, "zone": zone, "time": float(row.anchor_time), "position": [point.x, point.y, point.z] if float(row.anchor_time) >= 0.0 else [], "available": bool(row.available), "heat": float(row.heat)}
			burning += 1
	result.living_fires = _live.size()
	result.burning_zones = burning
	result.zone_anchors = anchors
	result.ships = _records.duplicate(true)
	result.capacity_smoke_evictions = _capacity_smoke_evictions
	result.live_emission_policy = "one current observed 0.25-second slot per real ship: total 3 smoke + 4 flame; rotate zone extras; no gap backfill or unavailable-anchor redistribution"
	return result

func _clear_timeline() -> void:
	super._clear_timeline()
	_live.clear()
	_records.clear()
	_capacity_smoke_evictions = 0
