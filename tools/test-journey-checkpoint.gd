extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _initialize() -> void:
	var script = load("res://tools/qa-journey-checkpoint.gd")
	check(script!=null,"material audit helper exists")
	if script!=null:
		var before: Dictionary = {"revision":3,"nextId":4,"simulationSeconds":12.0,"nearTicks":{"old":20},"vessels":{"ship":{"revision":1,"controlsProjection":{"sequence":2},"controlsObserved":{"sequence":2},"pose":{"position":{"x":1.0,"z":2.0},"heading":3.0,"speed":0.1},"cargo":{"grain":10},"damage":{"hull":80}}}}
		var after: Dictionary = before.duplicate(true)
		after.revision=5; after.nextId=5; after.nearTicks.fresh=0; after.vessels.ship.revision=2; after.vessels.ship.controlsProjection.sequence=3; after.vessels.ship.controlsObserved.sequence=3
		check(script.assess(before,after).ok,"normal owner stamps permitted and reported")
		check(not script.assess(before,after).differences.is_empty(),"actual stamp differences recorded")
		var changed: Dictionary = after.duplicate(true); changed.vessels.ship.cargo.grain=11
		check(not script.assess(before,changed).ok,"cargo mutation rejected")
		changed=after.duplicate(true); changed.vessels.ship.damage.hull=81
		check(not script.assess(before,changed).ok,"HP mutation rejected")
		changed=after.duplicate(true); changed.nearTicks.old=21
		check(not script.assess(before,changed).ok,"old native epoch mutation rejected")
		changed=after.duplicate(true); changed.vessels.ship.pose.position.x+=1e-10
		check(not script.assess(before,changed).ok,"position change rejected exactly")
		changed=after.duplicate(true); changed.vessels.ship.pose.speed+=1e-10
		check(script.assess(before,changed).ok,"native pose speed numerical roundoff permitted")
		changed=after.duplicate(true); changed.vessels.ship.pose.speed+=1e-7
		check(not script.assess(before,changed).ok,"material pose speed change rejected")
		changed=after.duplicate(true); changed.simulationSeconds+=0.2
		check(not script.assess(before,changed).ok,"simulation advancement rejected")
	print("JOURNEY_CHECKPOINT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
