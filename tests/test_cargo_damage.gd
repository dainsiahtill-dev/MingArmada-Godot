extends SceneTree

const RULES_PATH := "res://game/domain/mingqi/cargo_damage.gd"
var checks := 0
var failures := 0
var rules: Script

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func context() -> Dictionary:
	return {"id":"hit-7","campaignId":"voyage","battleId":"near-3","nativeTick":120,"eventTime":1.5,"nativeTime":2.0,"campaignTime":42.0,"vesselId":"merchant","sourceShipId":"pirate","ammo":"solid","position":{"x":10.0,"y":4.0,"z":-8.0},"pose":{"position":{"x":11.0,"z":-9.0},"heading":0.5,"speed":2.0}}

func rejected(cargo: Dictionary, input: Dictionary, label: String) -> void:
	var result: Dictionary = rules.plan(cargo, input)
	check(not result.get("ok", true), label)
	check(result.get("loss", -1) == 0 and result.get("details", {"unexpected":true}).is_empty(), label + " produces no drop")

func _run() -> void:
	if not check(ResourceLoader.exists(RULES_PATH), "cargo damage planning module exists"):
		_finish()
		return
	rules = load(RULES_PATH)
	if not check(rules != null and rules.has_method("plan"), "cargo damage exposes pure plan"):
		_finish()
		return
	var cargo := {"silk":20,"grain":12,"water":7}
	var input := context()
	var before := cargo.duplicate(true)
	var before_input := input.duplicate(true)
	var result: Dictionary = rules.plan(cargo, input)
	if not check(result.get("ok", false), "valid cargo loss planned"):
		_finish()
		return
	check(result.loss == 5 and result.goodId == "grain", "grain retains five-unit loss priority despite input order")
	check(result.beforeCargo == {"silk":20,"grain":12,"water":7} and result.afterCargo == {"silk":20,"grain":7,"water":7}, "plan conserves unaffected goods and exact grain balance")
	check(cargo == before and input == before_input, "planning never mutates caller inputs")
	var expected_details := {"kind":"cargo-drop","battleId":"near-3","sourceEventId":"hit-7","shipId":"merchant","sourceShipId":"pirate","goodId":"grain","quantity":5,"nativeTick":120,"eventTime":1.5,"nativeTime":2.0,"campaignTime":42.0,"originPose":{"position":{"x":11.0,"z":-9.0},"heading":0.5,"speed":2.0},"impactPosition":{"x":10.0,"y":4.0,"z":-8.0},"hasImpact":true,"originKind":"event-position","dropId":"voyage:near-3:hit-7:cargo","policy":"grain-first-5-v1"}
	check(result.details == expected_details, "receipt binds loss to the real cause, clocks and sampled pose")
	check(rules.plan(cargo, input) == result, "same input replays identically without pretending planner owns deduplication")
	result.afterCargo.grain = 900
	result.beforeCargo.silk = 901
	result.details.originPose.position.x = 999.0
	result.details.impactPosition.y = 999.0
	check(cargo == before and input == before_input, "returned nested dictionaries are detached from caller")
	check(rules.plan(cargo, input).details == expected_details, "mutating prior result cannot poison replay")
	var short: Dictionary = rules.plan({"grain":2,"silk":20}, context())
	check(short.loss == 2 and short.afterCargo == {"grain":0,"silk":20}, "partial grain stack loses only its actual two units")
	for good: String in ["water","wood","iron","powder","cloth","silk","porcelain","tea","sugar","salt","spices"]:
		var one := {good:3}
		var item: Dictionary = rules.plan(one, context())
		check(item.ok and item.loss == 3 and item.goodId == good and item.afterCargo == {good:0}, "non-grain cargo has real bounded loss: " + good)
	var ordered: Dictionary = rules.plan({"spices":8,"iron":11,"wood":9,"water":0,"grain":0}, context())
	check(ordered.goodId == "wood" and ordered.loss == 5 and ordered.afterCargo == {"spices":8,"iron":11,"wood":4,"water":0,"grain":0}, "fallback uses formal goods order rather than dictionary order")
	for empty: Dictionary in [{},{"grain":0,"silk":0}]:
		var no_cargo: Dictionary = rules.plan(empty, context())
		check(no_cargo.ok and no_cargo.loss == 0 and no_cargo.goodId == "" and no_cargo.afterCargo == empty and no_cargo.details.is_empty(), "empty cargo creates no drop")
	for ammo: String in ["chain","grape"]:
		var harmless := context()
		harmless.ammo = ammo
		var no_loss: Dictionary = rules.plan(cargo, harmless)
		check(no_loss.ok and no_loss.loss == 0 and no_loss.goodId == "" and no_loss.beforeCargo == cargo and no_loss.afterCargo == cargo and no_loss.details.is_empty(), ammo + " keeps cargo unchanged")
	var fallback := context()
	fallback.erase("position")
	var fallback_result: Dictionary = rules.plan({"grain":8}, fallback)
	check(fallback_result.ok and not fallback_result.details.hasImpact and fallback_result.details.originKind == "vessel-pose" and fallback_result.details.impactPosition == {"x":11.0,"y":0.0,"z":-9.0}, "legacy hit without position uses explicit vessel-pose fallback")
	var no_damage := context()
	no_damage.damage = {"hull":0,"sail":0,"crew":0}
	check(rules.plan({"grain":8}, no_damage).loss == 5, "loss policy never adds an implicit damage threshold")
	for bad_quantity in [-1, 0.5, NAN, INF, true, false, "3", null, 9007199254740992]:
		rejected({"grain":bad_quantity}, context(), "invalid cargo quantity rejected: " + str(bad_quantity))
	rejected({"unknown":1}, context(), "unknown good rejected")
	rejected({"grain":9007199254740991,"water":1}, context(), "aggregate cargo outside safe integer range rejected")
	for field: String in ["id","campaignId","battleId","vesselId","sourceShipId"]:
		for invalid_id in ["", "  ", true, 7, null, "bad\nidentity"]:
			var malformed := context()
			malformed[field] = invalid_id
			rejected({"grain":8}, malformed, "invalid identity rejected: " + field)
	for field: String in ["eventTime","nativeTime","campaignTime"]:
		for invalid_time in [-0.1, NAN, INF, true, "2", null]:
			var malformed := context()
			malformed[field] = invalid_time
			rejected({"grain":8}, malformed, "invalid clock rejected: " + field)
	for invalid_tick in [-1, 0.5, NAN, INF, true, "120", null, 9007199254740992]:
		var malformed := context()
		malformed.nativeTick = invalid_tick
		rejected({"grain":8}, malformed, "invalid native tick rejected")
	var future := context()
	future.eventTime = 2.000001
	rejected({"grain":8}, future, "future event cannot create cargo loss")
	var simultaneous := context()
	simultaneous.eventTime = simultaneous.nativeTime
	check(rules.plan({"grain":8}, simultaneous).ok, "event at current accepted time is allowed")
	for invalid_position in [null, {}, {"x":10,"z":8}, {"x":NAN,"y":0,"z":0}, {"x":0,"y":true,"z":0}]:
		var malformed := context()
		malformed.position = invalid_position
		rejected({"grain":8}, malformed, "supplied invalid position never silently falls back")
	for invalid_pose in [null, {}, {"position":{"x":NAN,"z":0},"heading":0,"speed":0}, {"position":{"x":0,"z":0},"heading":INF,"speed":0}, {"position":{"x":0,"z":0},"heading":0,"speed":-1}, {"position":{"x":0,"z":false},"heading":0,"speed":0}]:
		var malformed := context()
		malformed.pose = invalid_pose
		rejected({"grain":8}, malformed, "invalid source pose rejected")
	var unknown_ammo := context()
	unknown_ammo.ammo = "firepot"
	rejected({"grain":8}, unknown_ammo, "unsupported ammunition rejected")
	var missing_clock := context()
	missing_clock.erase("eventTime")
	rejected({"grain":8}, missing_clock, "event birth clock is required explicitly")
	var bad_harmless := context()
	bad_harmless.ammo = "chain"
	rejected({"grain":true}, bad_harmless, "non-damaging ammo still validates cargo")
	_finish()

func _finish() -> void:
	print("CARGO_DAMAGE_TEST_COMPLETE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
