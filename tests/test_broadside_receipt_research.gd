extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside receipt: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path := "res://game/research/demos/broadside_receipt_projection.gd"
	check(ResourceLoader.exists(path),"independent read-only event projection exists")
	if failures: finish(); return
	var projection = load(path).new()
	var policy := {"hostileTargets":{"flag":["enemy"]},"capturedShipIds":[]}
	var names := {"flag":{"name":"旗舰","team":"player"},"friend":{"name":"粮船甲","team":"player"},"enemy":{"name":"倭船","team":"hostile"}}
	projection.reset("battle-1","flag",policy,names)
	var fire := {"id":"e1","type":"fire","shipId":"flag","side":"starboard","projectileId":"p1"}
	var hit := {"id":"e2","type":"hit","shipId":"flag","targetId":"enemy","projectileId":"p1"}
	var fire2 := {"id":"e3","type":"fire","shipId":"flag","side":"starboard","projectileId":"p2"}
	var splash := {"id":"e4","type":"splash","shipId":"flag","projectileId":"p2"}
	var input := [fire,hit,fire2,splash].duplicate(true)
	for e in input: projection.consume(e,1.0)
	var state: Dictionary = projection.snapshot(1.0)
	check(state.text == "右舷命中 · 敌船倭船","later splash does not overwrite true hit")
	check(input == [fire,hit,fire2,splash],"projection does not modify input events")
	projection.consume(hit,2.0)
	check(projection.snapshot(4.01).text == "","replayed event cannot extend receipt duration")
	projection.reset("battle-2","flag",policy,names)
	projection.consume({"id":"u1","type":"hit","shipId":"flag","targetId":"enemy","projectileId":"unknown"},0.0)
	check(projection.snapshot(0).text == "","hit without matching fire is not attributed")
	projection.consume({"id":"u2","type":"fire","shipId":"friend","side":"port","projectileId":"p9"},0.0)
	projection.consume({"id":"u3","type":"hit","shipId":"friend","targetId":"enemy","projectileId":"p9"},0.0)
	check(projection.snapshot(0).text == "","allied gunfire is not flagship fire")
	projection.consume({"id":"f1","type":"fire","shipId":"flag","side":"port","projectileId":"pf"},0.0)
	projection.consume({"id":"f2","type":"hit","shipId":"flag","targetId":"friend","projectileId":"pf"},0.0)
	check(projection.snapshot(0).text == "左舷命中 · 友船粮船甲","protected ship is not labeled enemy")
	projection.reset("battle-3","flag",{},names)
	projection.consume(fire,0.0); projection.consume(hit,0.0)
	check(projection.snapshot(0).text == "右舷命中 · 船只倭船","unknown policy does not claim target is hostile")
	projection.reset("battle-4","flag",policy,names)
	projection.consume(fire,0.0); projection.consume(splash,0.0)
	check(projection.snapshot(0).text == "","splash must reference matching projectile")
	projection.consume({"id":"s1","type":"splash","shipId":"flag","projectileId":"p1"},0.0)
	check(projection.snapshot(0).text == "右舷炮弹未命中","matched splash means this projectile did not hit, not necessarily water")
	projection.reset("battle-5","flag",policy,names)
	projection.consume(hit,0.0)
	check(projection.snapshot(0).text == "","epoch reset clears projectile association")
	projection.reset("battle-6","flag",{"hostileTargets":{"flag":["enemy"]},"capturedShipIds":["enemy"]},names)
	projection.consume(fire,0.0); projection.consume(hit,0.0)
	check(projection.snapshot(0).text == "右舷命中 · 船只倭船","captured target is not reported as enemy")
	projection.reset("battle-7","flag",policy,names)
	projection.consume({"id":"grape-fire","type":"fire","shipId":"flag","side":"starboard","projectileId":"pellet-1","ammo":"grape"},0.0)
	projection.consume({"id":"grape-hit","type":"hit","shipId":"flag","targetId":"enemy","projectileId":"pellet-2","ammo":"grape"},0.0)
	check(projection.snapshot(0).text == "","grape sibling projectile without fire association is not invented")
	finish()
func finish() -> void:
	print("BROADSIDE_RECEIPT_RESEARCH assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
