extends SceneTree

const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
var assertions := 0
var failures := 0

func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)

func _initialize() -> void:
	var encounter := Encounter.new({"referenceGunnery":true,"ships":[
		{"id":"player","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0}},
		{"id":"other","kind":"voc","team":"hostile","position":{"x":0.0,"z":45.0}},
	],"oceanWaves":[],"sampleTerrainHeight":func(_x,_z): return -80.0})
	var native: Dictionary = encounter.snapshot()
	native.ships[1].erase("team")
	var before := native.duplicate(true)
	var status: Variant = Cannon.broadside_status(native,"player","starboard")
	check(status is Dictionary and status.get("phase")=="blocked", "missing target team protects known hull in ballistic corridor")
	check(native==before,"unknown allegiance advice does not mutate native packet")
	status = Cannon.broadside_status(native,"player","starboard",{"hostileTargets":{"player":["other"]}})
	check(status is Dictionary and status.get("phase")=="ready" and status.get("targetId")=="other","explicit policy can establish hostility without optional team label")
	native.ships[0].erase("team"); native.ships[1].team="hostile"
	status = Cannon.broadside_status(native,"player","starboard")
	check(status is Dictionary and status.get("phase")=="blocked","missing shooter allegiance also protects other hulls")
	for omitted: String in ["kind","height"]:
		var partial: Dictionary = encounter.snapshot()
		if omitted=="kind": partial.ships[1].erase("kind")
		else: partial.ships[1].visual.position.erase("y")
		status=Cannon.broadside_status(partial,"player","starboard")
		check(status is Dictionary and status.get("phase")=="no-target" and status.get("targetId")=="", "partially projected target cannot claim verified readiness without "+omitted)
	# Exactly the display projection constructed in test_mingqi_ui: neither
	# physical kind nor vertical position nor allegiance is part of this packet.
	var state: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")).state
	var lean := {"ships":[],"playerId":state.flagshipId}
	for id: String in state.vessels:
		var v: Dictionary = state.vessels[id]
		lean.ships.append({"id":id,"name":v.name,"visual":{"position":v.pose.position.duplicate(),"velocity":{"x":2,"z":0},"heading":0},"hull":v.damage.hull,"crew":v.crew.able,"cannonsPerSide":4,"ammoType":"solid","ammo":{"solid":40},"cooldownSeconds":{"port":0,"starboard":0}})
	before=lean.duplicate(true)
	status=Cannon.broadside_status(lean,state.flagshipId,"port")
	check(status is Dictionary and status.get("phase")=="no-target" and status.get("label","").contains("待确认"),"lean display packet retains gun availability but never claims verified shot readiness")
	check(lean==before,"lean advice neither invents geometry nor mutates display packet")
	lean.ships[0].cooldownSeconds.port=2.5
	status=Cannon.broadside_status(lean,state.flagshipId,"port")
	check(status is Dictionary and status.get("phase")=="reloading" and status.get("reloadSeconds")==2.5,"lean packet still reports actual reload before geometry guidance")
	lean.ships[0].cooldownSeconds.port=0.0
	lean.ships[0].ammo.solid=0
	status=Cannon.broadside_status(lean,state.flagshipId,"port")
	check(status is Dictionary and status.get("phase")=="no-ammo","lean packet still fences actual ammunition exhaustion")
	print("REFERENCE_GUNNERY_LEAN_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
