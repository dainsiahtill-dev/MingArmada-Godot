extends RefCounted
## Bounded, non-recoverable visual lots from already committed cargo receipts.
## Positions are world metres; rotations are XYZ radians. No cargo is settled here.
## Age uses campaign accepted seconds. Wave samples use a distinct visual clock.

const GOODS := ["grain","water","wood","iron","powder","cloth","silk","porcelain","tea","sugar","salt","spices"]
const MAX_SAFE := 9007199254740991
const GRAVITY := 9.81
const ENTRY_HZ := 60.0
const ENTRY_WINDOW := 2.0
const SPLASH_LIFETIME := 2.8
var _water := Callable()
var _configured := false
var _max_lots := 96
var _lifetime := 40.0
var _launch_spread := 0.0
var _time := -1.0
var _visual_time := -1.0
var _lots: Dictionary = {}
var _seen: Dictionary = {}
var _splashes: Array = []
var _rejections: Dictionary = {}
var _invalid_water_samples := 0
var _approximate_entries := 0
var _dropped_splashes := 0

func configure(water_sampler: Callable, options: Dictionary = {}) -> bool:
	var capacity: Variant = options.get("max_lots", 96)
	var duration: Variant = options.get("lifetime", 40.0)
	var spread: Variant = options.get("launch_spread", 0.0)
	if not water_sampler.is_valid() or not _count(capacity) or capacity < 1 or capacity > 1024 or not _finite(duration) or duration <= 0.0 or duration > 3600.0 or not _finite(spread) or spread < 0.0 or spread > 4.0:
		return false
	reset()
	_water = water_sampler
	_max_lots = int(capacity)
	_lifetime = float(duration)
	_launch_spread = float(spread)
	_configured = true
	return true

func add_drop(details: Dictionary, now: float) -> Dictionary:
	if not _configured:
		return _reject("not-configured")
	if not _time_valid(now):
		return _reject("invalid-clock")
	if details.get("hasImpact") != true or details.get("originKind") != "event-position":
		return _reject("missing-impact")
	if not _valid_details(details):
		return _reject("invalid-receipt")
	var born := float(details.campaignTime)
	# A rejected future receipt must not reserve its ID or move the timeline.
	if born > now:
		return _reject("future-drop")
	_observe_time(now)
	_prune(now)
	if now - born >= _lifetime:
		return _reject("expired-drop")
	var id: String = details.dropId
	if _seen.has(id):
		return _reject("duplicate-drop")
	if _lots.size() >= _max_lots:
		return _reject("capacity")
	var point := Vector3(float(details.impactPosition.x), float(details.impactPosition.y), float(details.impactPosition.z))
	var pose: Dictionary = details.originPose
	var heading := float(pose.heading)
	# The receipt stores heading/scalar speed: inherit a bow-axis approximation,
	# not the native body's unsaved sideways velocity.
	var forward := Vector3(cos(heading), 0.0, sin(heading))
	var outward := Vector3(point.x-float(pose.position.x), 0.0, point.z-float(pose.position.z))
	if outward.length_squared() > 0.000001:
		outward = outward.normalized()
	else:
		outward = forward
	var velocity := outward*2.5 + Vector3.UP*2.0 + forward*float(pose.speed)
	var spin_jitter := 0.0
	if _launch_spread > 0.0:
		# Receipt-derived tangent speed separates repeated compartment losses.
		# Keep the measured birth point, outward launch and economic quantity.
		var scatter := _receipt_scatter(id)
		velocity += Vector3(-outward.z,0.0,outward.x)*(_launch_spread*scatter)
		spin_jitter = minf(_launch_spread,1.5)*scatter*0.35
	if not velocity.is_finite() or not (point+velocity*_lifetime+Vector3.DOWN*(0.5*GRAVITY*_lifetime*_lifetime)).is_finite():
		return _reject("invalid-trajectory")
	_lots[id] = {
		"dropId":id,"goodId":details.goodId,"quantity":int(details.quantity),
		"shipId":details.shipId,"sourceShipId":details.sourceShipId,
		"sourceEventId":details.sourceEventId,"battleId":details.battleId,
		"born":born,"origin":point,"velocity":velocity,"heading":heading,"spin_jitter":spin_jitter,
		"phase_offset":NAN,"entry_age":-1.0,"entry_point":Vector3.ZERO,"entry_scan_tick":-1,
		"entry_approximate":false,"splash_emitted":false,
		"drift":Vector3.ZERO,"drift_stamp":-1.0,"drift_wind":Vector3.ZERO,
		"render":{},
	}
	_seen[id] = born
	return {"ok":true}

func advance(now: float, visual_time: float, wind: Dictionary) -> void:
	if not _configured or not _time_valid(now) or not _time_valid(visual_time):
		return
	var drift_velocity: Variant = _wind_velocity(wind)
	if drift_velocity == null:
		_reject("invalid-wind")
		return
	_observe_time(now)
	_visual_time = visual_time
	_prune(now)
	for lot: Dictionary in _lots.values():
		_render_lot(lot, now, visual_time, drift_velocity)

func snapshot() -> Array:
	var result: Array = []
	for lot: Dictionary in _lots.values():
		if not lot.render.is_empty():
			result.append(lot.render.duplicate(true))
	return result

func drain_splashes() -> Array:
	var result := _splashes.duplicate(true)
	_splashes.clear()
	return result

func diagnostics() -> Dictionary:
	return {"configured":_configured,"lots":_lots.size(),"seen":_seen.size(),"queued_splashes":_splashes.size(),"max_lots":_max_lots,"lifetime":_lifetime,"launch_spread":_launch_spread,"campaign_time":_time,"visual_time":_visual_time,"invalid_water_samples":_invalid_water_samples,"approximate_entries":_approximate_entries,"dropped_splashes":_dropped_splashes,"rejections":_rejections.duplicate(true),"scope":"non-recoverable presentation; first two flight seconds sampled at 60Hz; later crossing observed approximately; wind integrates accepted segments, late reconstruction assumes current wind before first observation; optional receipt-seeded tangent launch speed in metres/second"}

func reset() -> void:
	_lots.clear()
	_seen.clear()
	_splashes.clear()
	_rejections.clear()
	_invalid_water_samples = 0
	_approximate_entries = 0
	_dropped_splashes = 0
	_time = -1.0
	_visual_time = -1.0

func dispose() -> void:
	reset()
	_water = Callable()
	_configured = false

func _observe_time(now: float) -> void:
	if _time >= 0.0 and now < _time:
		reset()
	_time = now

func _prune(now: float) -> void:
	for id: String in _lots.keys():
		if now-float(_lots[id].born) >= _lifetime:
			_lots.erase(id)
	for id: String in _seen.keys():
		if now-float(_seen[id]) >= _lifetime:
			_seen.erase(id)
	for index in range(_splashes.size()-1, -1, -1):
		if now-float(_splashes[index].campaignTime) >= SPLASH_LIFETIME:
			_splashes.remove_at(index)

func _render_lot(lot: Dictionary, now: float, visual_time: float, wind_velocity: Vector3) -> void:
	var age := now-float(lot.born)
	if age < 0.0:
		return
	if is_nan(float(lot.phase_offset)):
		# There is no saved historical sea phase in the business receipt. Bind
		# the observed clock offset once; later visual-only refreshes change the
		# sampled water surface, never the lot's accepted age or flight history.
		lot.phase_offset = visual_time-now
	if float(lot.entry_age) < 0.0:
		var entry := _find_entry(lot, age, visual_time)
		if not entry.is_empty():
			lot.entry_age = entry.age
			lot.entry_point = entry.point
			lot.entry_approximate = entry.approximate
			if entry.approximate:
				_approximate_entries += 1
	var position: Vector3
	var rotation: Vector3
	var phase := "airborne"
	if float(lot.entry_age) < 0.0:
		position = _ballistic(lot, age)
		rotation = Vector3(age*0.7, float(lot.heading)+age*1.1, age*1.8)
		if float(lot.spin_jitter) != 0.0:
			rotation += Vector3(age*float(lot.spin_jitter)*0.4,age*float(lot.spin_jitter),age*float(lot.spin_jitter)*0.6)
	else:
		var afloat_age := maxf(0.0, age-float(lot.entry_age))
		var drift: Vector3 = lot.drift
		if float(lot.drift_stamp) < 0.0:
			# Late first observation can reconstruct constant wind exactly. A
			# varying pre-observation wind history is unavailable, not invented.
			drift = wind_velocity*afloat_age
		else:
			# Piecewise analytic displacement, using the previously accepted wind
			# until this new observation. No historical position jumps on change.
			drift += Vector3(lot.drift_wind)*maxf(0.0, now-float(lot.drift_stamp))
		position = Vector3(lot.entry_point)+drift
		position.x = snappedf(position.x, 0.000000001)
		position.z = snappedf(position.z, 0.000000001)
		if not position.is_finite():
			return
		# Accepted horizontal motion and wind observations do not depend on a
		# valid wave sample. A missing height freezes only the rendered pose.
		lot.drift = drift
		lot.drift_stamp = now
		lot.drift_wind = wind_velocity
		var surface: Variant = _water_at(position.x, position.z, visual_time)
		if surface == null:
			return # Keep the last finite render while retaining accepted wind.
		var depth := 0.16 if lot.goodId == "wood" else 0.24 if lot.goodId == "water" else 0.18
		phase = "floating"
		if lot.goodId == "iron":
			depth = 0.30 + maxf(0.0, afloat_age-3.0)*0.9
			if afloat_age > 3.0:
				phase = "sinking"
		elif lot.goodId == "porcelain":
			depth = 0.22 + maxf(0.0, afloat_age-8.0)*0.45
			if afloat_age > 8.0:
				phase = "sinking"
		position.y = float(surface)-depth
		var settle := exp(-3.0*afloat_age)
		rotation = Vector3(float(lot.entry_age)*0.7*settle+sin(afloat_age*1.7)*0.04, float(lot.heading)+float(lot.entry_age)*1.1+sin(afloat_age*0.6)*0.08, float(lot.entry_age)*1.8*settle+sin(afloat_age*2.1)*0.06)
		if float(lot.spin_jitter) != 0.0:
			var turn := float(lot.entry_age)*float(lot.spin_jitter)
			rotation += Vector3(turn*0.4*settle,turn,turn*0.6*settle)
		if not position.is_finite() or not rotation.is_finite():
			return
		_queue_entry(lot, now)
	if not position.is_finite() or not rotation.is_finite():
		return
	var fade_seconds := minf(3.0, _lifetime)
	lot.render = {
		"dropId":lot.dropId,"goodId":lot.goodId,"quantity":lot.quantity,
		"shipId":lot.shipId,"sourceShipId":lot.sourceShipId,
		"sourceEventId":lot.sourceEventId,"battleId":lot.battleId,
		"position":[position.x,position.y,position.z],"rotation":[rotation.x,rotation.y,rotation.z],
		"phase":phase,"alpha":clampf((_lifetime-age)/fade_seconds,0.0,1.0),"age":age,
		"entryAge":lot.entry_age,"entryApproximate":lot.entry_approximate,
	}

func _find_entry(lot: Dictionary, age: float, visual_time: float) -> Dictionary:
	var end_tick := int(floor(minf(age,ENTRY_WINDOW)*ENTRY_HZ+0.000000001))
	# The bound historical wave phase is immutable. Do not resample every old
	# flight step on every render; a late observer still replays at most 121.
	for index in range(int(lot.entry_scan_tick)+1,end_tick+1):
		var at := float(index)/ENTRY_HZ
		var point := _ballistic(lot,at)
		var surface: Variant = _water_at(point.x,point.z,float(lot.born)+float(lot.phase_offset)+at)
		if surface == null:
			return {} # Retry this unproven historical step after sampler recovery.
		lot.entry_scan_tick = index
		if point.y <= float(surface):
			point.y = float(surface)
			return {"age":at,"point":point,"approximate":false}
	if age > ENTRY_WINDOW:
		# Unusually high impacts are outside the replay window. Continue the
		# analytic fall, then accept only a genuinely observed submerged point;
		# do not manufacture an entry merely because the two seconds elapsed.
		var point := _ballistic(lot,age)
		var surface: Variant = _water_at(point.x,point.z,visual_time)
		if surface != null and point.y <= float(surface):
			point.y = float(surface)
			return {"age":age,"point":point,"approximate":true}
	return {}

func _queue_entry(lot: Dictionary, now: float) -> void:
	if lot.splash_emitted:
		return
	lot.splash_emitted = true
	var born := float(lot.born)+float(lot.entry_age)
	var visual_born := born+float(lot.phase_offset)
	if now-born >= SPLASH_LIFETIME or visual_born < 0.0:
		return
	if _splashes.size() >= _max_lots:
		_splashes.pop_front()
		_dropped_splashes += 1
	var point: Vector3 = lot.entry_point
	_splashes.append({"type":"splash","id":String(lot.dropId)+":water","dropId":lot.dropId,"time":visual_born,"campaignTime":born,"position":{"x":point.x,"y":point.y,"z":point.z},"scale":0.5})

func _water_at(x: float, z: float, visual_time: float) -> Variant:
	if not _water.is_valid() or not is_finite(x) or not is_finite(z) or not is_finite(visual_time):
		_invalid_water_samples += 1
		return null
	var height: Variant = _water.call(x,z,visual_time)
	if not _finite(height):
		_invalid_water_samples += 1
		return null
	return float(height)

func _reject(reason: String) -> Dictionary:
	_rejections[reason] = int(_rejections.get(reason,0))+1
	return {"ok":false,"reason":reason}

static func _ballistic(lot: Dictionary, age: float) -> Vector3:
	return Vector3(lot.origin)+Vector3(lot.velocity)*age+Vector3.DOWN*(0.5*GRAVITY*age*age)

static func _receipt_scatter(id: String) -> float:
	# Explicit uint32 integer mixing avoids global RNG and insertion-order state.
	# Products fit signed int64 before masking; the seed is not a security hash.
	var seed: int = 2166136261
	for byte: int in id.to_utf8_buffer():
		seed = ((seed ^ byte)*16777619) & 0xffffffff
	for _index in 2:
		seed = (((seed >> 16) ^ seed)*73244475) & 0xffffffff
	seed = (seed >> 16) ^ seed
	var magnitude := 0.35+float((seed >> 1) & 65535)/65535.0*0.65
	return magnitude if (seed & 1) != 0 else -magnitude

static func _wind_velocity(wind: Dictionary) -> Variant:
	if wind.is_empty():
		return Vector3.ZERO
	if not wind.get("direction") is Dictionary or not _finite(wind.get("speed")) or wind.speed < 0.0 or not _finite(wind.direction.get("x")) or not _finite(wind.direction.get("y")):
		return null
	var velocity := Vector3(-float(wind.direction.x),0.0,-float(wind.direction.y))*float(wind.speed)*0.02
	return velocity if velocity.is_finite() else null

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _count(value: Variant) -> bool:
	return _finite(value) and value >= 0 and value <= MAX_SAFE and value == floor(float(value))

static func _time_valid(value: Variant) -> bool:
	return _finite(value) and value >= 0.0 and value <= MAX_SAFE

static func _id(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value.length() > 4096:
		return false
	for index in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true

static func _valid_details(details: Dictionary) -> bool:
	if details.get("kind") != "cargo-drop" or not details.get("goodId") in GOODS or typeof(details.get("hasImpact")) != TYPE_BOOL or not _count(details.get("quantity")) or details.quantity <= 0:
		return false
	for key: String in ["dropId","sourceEventId","shipId","sourceShipId","battleId","policy"]:
		if not _id(details.get(key)):
			return false
	if not _count(details.get("nativeTick")):
		return false
	for key: String in ["campaignTime","eventTime","nativeTime"]:
		if not _time_valid(details.get(key)):
			return false
	if details.eventTime > details.nativeTime or not details.get("impactPosition") is Dictionary:
		return false
	for axis: String in ["x","y","z"]:
		if not _finite(details.impactPosition.get(axis)):
			return false
	var pose: Variant = details.get("originPose")
	return pose is Dictionary and pose.get("position") is Dictionary and _finite(pose.position.get("x")) and _finite(pose.position.get("z")) and _finite(pose.get("heading")) and _finite(pose.get("speed")) and pose.speed >= 0.0
