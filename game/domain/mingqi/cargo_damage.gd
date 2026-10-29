extends RefCounted
## Pure loss proposal. Campaign owns atomic commit and settlement deduplication.
## Cargo counts are abstract hold units, never numbers of rendered packages.

const MAX_SAFE := 9007199254740991
const GOODS := ["grain","water","wood","iron","powder","cloth","silk","porcelain","tea","sugar","salt","spices"]
const POLICY := "grain-first-5-v1"

## eventTime is the hit birth; nativeTime/nativeTick identify the accepted
## snapshot observing it. campaignTime belongs to the separate business clock.
## pose is the observed vessel pose, not a reconstructed historical impact pose.
static func plan(cargo: Dictionary, context: Dictionary) -> Dictionary:
	var result := {"ok":false,"loss":0,"goodId":"","beforeCargo":cargo.duplicate(true),"afterCargo":cargo.duplicate(true),"details":{}}
	if not _valid_cargo(cargo):
		result.reason = "invalid-cargo"
		return result
	for key: String in ["id","campaignId","battleId","vesselId","sourceShipId"]:
		if not _valid_id(context.get(key)):
			result.reason = "invalid-cargo-cause"
			return result
	if not context.get("ammo") in ["solid","chain","grape"]:
		result.reason = "invalid-cargo-ammo"
		return result
	if not _count(context.get("nativeTick")):
		result.reason = "invalid-cargo-clock"
		return result
	for key: String in ["eventTime","nativeTime","campaignTime"]:
		if not _time(context.get(key)):
			result.reason = "invalid-cargo-clock"
			return result
	if context.eventTime > context.nativeTime:
		result.reason = "future-cargo-event"
		return result
	if not _valid_pose(context.get("pose")):
		result.reason = "invalid-cargo-pose"
		return result
	var has_impact := context.has("position")
	if has_impact and not _position(context.position, ["x","y","z"]):
		result.reason = "invalid-cargo-impact"
		return result
	var drop_id: String = context.campaignId + ":" + context.battleId + ":" + context.id + ":cargo"
	if not _valid_id(drop_id):
		result.reason = "invalid-cargo-drop-id"
		return result
	result.ok = true
	if context.ammo != "solid":
		return result
	var good_id := ""
	for good: String in GOODS:
		if cargo.get(good, 0) > 0:
			good_id = good
			break
	if good_id.is_empty():
		return result
	var quantity := mini(5, int(cargo[good_id]))
	result.loss = quantity
	result.goodId = good_id
	result.afterCargo[good_id] = int(cargo[good_id]) - quantity
	var pose: Dictionary = context.pose
	var origin_pose := {"position":{"x":pose.position.x,"z":pose.position.z},"heading":pose.heading,"speed":pose.speed}
	# Missing positions belong to old near-sync fixtures. Y=0 is explicitly a
	# fallback datum; it is neither a measured impact height nor deck support.
	var impact := {"x":pose.position.x,"y":0.0,"z":pose.position.z}
	if has_impact:
		impact = {"x":context.position.x,"y":context.position.y,"z":context.position.z}
	result.details = {
		"kind":"cargo-drop","battleId":context.battleId,"sourceEventId":context.id,
		"shipId":context.vesselId,"sourceShipId":context.sourceShipId,
		"goodId":good_id,"quantity":quantity,"nativeTick":context.nativeTick,
		"eventTime":context.eventTime,"nativeTime":context.nativeTime,"campaignTime":context.campaignTime,
		"originPose":origin_pose,"impactPosition":impact,"hasImpact":has_impact,
		"originKind":"event-position" if has_impact else "vessel-pose",
		"dropId":drop_id,"policy":POLICY,
	}
	return result

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_finite(float(value))

static func _count(value: Variant) -> bool:
	return _finite(value) and value >= 0 and value <= MAX_SAFE and value == floor(float(value))

static func _time(value: Variant) -> bool:
	return _finite(value) and value >= 0 and value <= MAX_SAFE

static func _valid_cargo(cargo: Dictionary) -> bool:
	var total := 0
	for good: Variant in cargo:
		if not good in GOODS or not _count(cargo[good]):
			return false
		var quantity := int(cargo[good])
		if quantity > MAX_SAFE - total:
			return false
		total += quantity
	return true

static func _valid_id(value: Variant) -> bool:
	if not value is String or value.strip_edges().is_empty() or value in ["__proto__","prototype","constructor"]:
		return false
	var length := 0
	for index in value.length():
		var point: int = value.unicode_at(index)
		if point < 32 or point == 127:
			return false
		length += 2 if point > 65535 else 1
	return length <= 4096

static func _position(value: Variant, axes: Array) -> bool:
	if not value is Dictionary:
		return false
	for axis: String in axes:
		if not _finite(value.get(axis)):
			return false
	return true

static func _valid_pose(value: Variant) -> bool:
	return value is Dictionary and _position(value.get("position"), ["x","z"]) and _finite(value.get("heading")) and _finite(value.get("speed")) and value.speed >= 0
