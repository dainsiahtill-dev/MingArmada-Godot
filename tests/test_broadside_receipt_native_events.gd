extends SceneTree
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const ReceiptProjection = preload("res://game/research/demos/broadside_receipt_projection.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside native events: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var encounter = Encounter.new({"referenceGunnery":true,"ships":[{"id":"player","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0},"crew":100,"sailDeployment":0.0},{"id":"enemy","name":"倭船","kind":"voc","team":"hostile","position":{"x":0.0,"z":110.0},"sailDeployment":0.0}],"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],"sampleTerrainHeight":func(_x,_z): return -80.0})
	var projection = ReceiptProjection.new()
	projection.reset("native-fixture","player",{"hostileTargets":{"player":["enemy"]},"capturedShipIds":[]},{"player":{"name":"旗舰","team":"player"},"enemy":{"name":"倭船","team":"hostile"}})
	check(encounter.command({"type":"fire","side":"starboard"}).ok,"native broadside command accepted")
	var events: Array = encounter.drain_events()
	for tick in 540:
		encounter.step(1.0/60.0)
		events.append_array(encounter.drain_events())
	var fires := 0; var hits := 0; var correct_hits := 0
	for event: Dictionary in events:
		if event.get("shipId") != "player": continue
		if event.type == "fire": fires += 1
		projection.consume(event,float(event.time))
		if event.type == "hit" and event.targetId == "enemy":
			hits += 1
			var receipt: Dictionary = projection.snapshot(float(event.time)).receipt
			if receipt.get("projectileId") == event.projectileId and receipt.get("text") == "右舷命中 · 敌船倭船": correct_hits += 1
	check(fires == 4,"native fuchuan issues four fire events")
	check(hits > 0,"actual projectile collision produces at least one enemy hit")
	check(correct_hits == hits,"every observed native solid hit maps to its real fire projectile")
	print("NATIVE_BROADSIDE_SAMPLE fires=",fires," enemy_hits=",hits," attributed=",correct_hits)
	finish()
func finish() -> void:
	print("BROADSIDE_RECEIPT_NATIVE_EVENTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
