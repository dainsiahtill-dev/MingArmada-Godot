extends SceneTree

const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Cannon = preload("res://modules/naval_simulation/combat/cannon_system.gd")
const Hud = preload("res://game/ui/naval_practice.gd")
var failures := 0
var assertions := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func battle(kind: String = "heavy", crew: float = 160.0, blocker: bool = false) -> RefCounted:
	var fleet := [{"id":"player","kind":kind,"team":"player","position":{"x":0.0,"z":0.0},"crew":crew,"sailDeployment":0.0},{"id":"enemy","kind":"voc","team":"hostile","position":{"x":0.0,"z":110.0},"sailDeployment":0.0}]
	if blocker: fleet.append({"id":"friend","kind":"merchant","team":"player","position":{"x":0.0,"z":45.0},"sailDeployment":0.0})
	return Encounter.new({"referenceGunnery":true,"ships":fleet,"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],"sampleTerrainHeight":func(_x,_z): return -80.0})
func _initialize() -> void: run.call_deferred()
func policy_advice(cannon: RefCounted, native: Dictionary, policy: Dictionary) -> Dictionary:
	# During RED, the old three-argument implementation still executes, proving
	# incorrect readiness rather than stopping on a missing argument signature.
	var method: Dictionary = cannon.get_method_list().filter(func(m): return m.name=="broadside_status")[0]
	return cannon.call("broadside_status",native,"player","starboard",policy) if method.args.size()>=4 else cannon.call("broadside_status",native,"player","starboard")
func run() -> void:
	var e := battle()
	check(e.command({"type":"fire","side":"starboard"}).ok,"heavy broadside accepted")
	var shots: Array = e.drain_events().filter(func(v): return v.type == "fire" and v.shipId == "player")
	for tick in 120:
		e.step(1.0/60.0); shots.append_array(e.drain_events().filter(func(v): return v.type == "fire" and v.shipId == "player"))
	check(shots.size() == 8 and shots.back().time - shots.front().time >= 0.8 and shots.back().time - shots.front().time <= 1.5,"heavy salvo is eight finite guns over readable 0.8–1.5 seconds")
	check(e.snapshot().ships[0].ammo.solid == 39,"one salvo consumes one ammunition unit")
	check(not e.command({"type":"fire","side":"starboard"}).ok,"reload fences repeated same-side fire")
	check(e.command({"type":"fire","side":"port"}).ok,"opposite-side reload remains independent")
	var rapid := battle()
	rapid.update_ship_stats("player",{"stats":{"reloadMultiplier":0.01}})
	rapid.command({"type":"fire","side":"starboard"})
	for tick in 10: rapid.step(1.0/60.0)
	check(not rapid.command({"type":"fire","side":"starboard"}).ok,"reload upgrades cannot overlap an unfinished finite broadside")
	var weak := battle("heavy",40.0)
	weak.command({"type":"fire","side":"starboard"})
	check(weak.snapshot().ships[0].cooldownSeconds.starboard > 12.0,"understaffed heavy cannon battery reloads slower than healthy seven seconds")
	var unsafe := battle("heavy",160.0,true)
	var before: Dictionary = unsafe.snapshot()
	var receipt: Dictionary = unsafe.command({"type":"fire","side":"starboard"})
	check(not receipt.ok and receipt.get("reason") == "friendly-fire-blocked", "friendly hull crossing real ballistic launch corridor rejects fire")
	check(unsafe.snapshot() == before and unsafe.drain_events().is_empty(),"unsafe shot consumes no ammunition, reload, sequence or events")
	var late := battle("heavy",160.0,true)
	late.ships[2].core.set_state({"x":200.0,"z":45.0},0.0)
	check(late.command({"type":"fire","side":"starboard"}).ok,"clear corridor permits initial gun")
	late.drain_events(); late.ships[2].core.set_state({"x":0.0,"z":45.0},0.0)
	var late_shots: Array = []
	for tick in 90:
		late.step(1.0/60.0); late_shots.append_array(late.drain_events().filter(func(v): return v.type=="fire" and v.shipId=="player"))
	check(late_shots.is_empty() and late.volleys.is_empty(),"new friendly obstruction suppresses every remaining delayed gun without infinite pending fire")
	var locked_ammo := battle("fuchuan",100.0)
	locked_ammo.command({"type":"fire","side":"starboard"}); locked_ammo.drain_events()
	locked_ammo.command({"type":"select-ammo","ammo":"chain"})
	var queued_ammo: Array = []
	for tick in 30:
		locked_ammo.step(1.0/60.0); queued_ammo.append_array(locked_ammo.drain_events().filter(func(v): return v.type=="fire" and v.shipId=="player"))
	check(queued_ammo.size()==3 and queued_ammo.all(func(v): return v.ammo=="solid") and locked_ammo.snapshot().ships[0].ammo.chain==20,"ammunition switch does not rewrite pending salvo or consume another inventory")
	var frozen: Dictionary = locked_ammo.snapshot()
	locked_ammo.step(0.0); locked_ammo.step(-1.0); locked_ammo.step(NAN)
	check(locked_ammo.snapshot()==frozen and locked_ammo.drain_events().is_empty(),"invalid time cannot advance reload, ballistics or repeat events")
	var collision := battle("fuchuan",100.0)
	collision.command({"type":"fire","side":"starboard"})
	var resolved: Dictionary = {}
	var reported_hull_loss := 0.0
	var repeated := false
	for tick in 540:
		collision.step(1.0/60.0)
		for event: Dictionary in collision.drain_events():
			if event.type != "hit" or event.shipId != "player": continue
			if resolved.has(event.projectileId): repeated=true
			resolved[event.projectileId]=true
			if event.targetId=="enemy": reported_hull_loss+=event.damage.hull
	check(not resolved.is_empty() and not repeated,"actual sweep collisions resolve each launched projectile at most once")
	check(absf(100.0-collision.snapshot().ships[1].hull-reported_hull_loss)<1e-8,"actual hull loss equals authoritative hit events with no duplicate damage")
	check(not collision.volleys.any(func(v): return v.shipId=="player") and not collision.projectiles.any(func(v): return v.shipId=="player"),"player's finite broadside and flight TTL slots drain despite continuing enemy counterfire")
	var zero := battle("heavy",0.0)
	check(not zero.command({"type":"fire","side":"starboard"}).ok,"empty battery crew cannot fire")
	for ammo in ["solid","chain","grape"]:
		var firing := battle("fuchuan",100.0)
		firing.command({"type":"select-ammo","ammo":ammo})
		firing.command({"type":"fire","side":"starboard"})
		var shot: Dictionary = firing.snapshot().projectiles[0]
		var origin_y: float = shot.position.y
		var initial_vy: float = shot.velocity.y
		firing.step(1.0/60.0)
		var after: Dictionary = firing.snapshot().projectiles[0]
		check(absf(after.velocity.y - initial_vy + 9.81/60.0)<1e-9 and after.position.y != origin_y,"ammunition keeps actual gravity trajectory: " + ammo)
		check(firing.snapshot().ships[0].ammo[ammo] == {"solid":39,"chain":19,"grape":19}[ammo],"correct ammunition inventory charged: " + ammo)
	var advice := battle("fuchuan",100.0)
	var cannon: RefCounted = Cannon.new()
	for case: Dictionary in [
		{"name":"captured hostile","captured":["enemy"],"targets":["enemy"]},
		{"name":"temporarily non-hostile","captured":[],"targets":[]},
	]:
		var scoped_config: Dictionary = battle("fuchuan",100.0).config.duplicate(true)
		scoped_config.mode="continuous"; scoped_config.controllableShipIds=["player"]
		scoped_config.capturedShipIds=case.captured; scoped_config.hostileTargets={"player":case.targets}
		scoped_config.ships[1].position={"x":0.0,"z":45.0}
		var scoped := Encounter.new(scoped_config)
		var applied: Dictionary = scoped.reconcile_ships(scoped_config.ships,{"controllableShipIds":["player"],"capturedShipIds":case.captured,"hostileTargets":{"player":case.targets}})
		check(applied.ok,"continuous scoped policy applies through actual reconciliation: " + case.name)
		var classification := policy_advice(cannon,scoped.snapshot(),scoped.policy)
		check(classification.phase=="blocked" and classification.targetId=="", "HUD protects policy-scoped " + case.name + " in hostile-team hull")
		var refusal: Dictionary = scoped.command({"type":"fire","side":"starboard"})
		check(not refusal.ok and refusal.get("reason")=="friendly-fire-blocked","authority rejects same policy-scoped " + case.name)
		check(classification.phase=="blocked" and classification.label.contains("友船") and not refusal.ok,"policy HUD and authoritative fire agree: " + case.name)
	for team in ["neutral","player"]:
		var explicit_config: Dictionary = battle("fuchuan",100.0).config.duplicate(true)
		explicit_config.mode="continuous"; explicit_config.controllableShipIds=["player"]; explicit_config.hostileTargets={"player":["enemy"]}
		explicit_config.ships[1].team=team
		var explicit := Encounter.new(explicit_config)
		var explicit_advice := policy_advice(cannon,explicit.snapshot(),explicit.policy)
		check(explicit_advice.phase=="ready" and explicit_advice.targetId=="enemy" and explicit.command({"type":"fire","side":"starboard"}).ok,"explicit hostileTargets overrides "+team+" team in HUD exactly as authority")
	var fallback_config: Dictionary = battle("fuchuan",100.0).config.duplicate(true)
	fallback_config.mode="continuous"; fallback_config.controllableShipIds=["player"]; fallback_config.hostileTargets={"enemy":["player"]}
	var fallback := Encounter.new(fallback_config)
	check(policy_advice(cannon,fallback.snapshot(),fallback.policy).phase=="ready" and fallback.command({"type":"fire","side":"starboard"}).ok,"policy without this shooter's target list falls back to ordinary hostile-team classification")
	check(cannon.has_method("broadside_status"), "HUD can derive readable shot status from canonical snapshots")
	if cannon.has_method("broadside_status"):
		var status: Dictionary = cannon.call("broadside_status",advice.snapshot(),"player","starboard")
		check(status.phase == "ready" and status.targetId == "enemy", "HUD reports hostile inside selected side's safe arc")
		advice.command({"type":"select-ammo","ammo":"grape"})
		status = cannon.call("broadside_status",advice.snapshot(),"player","starboard")
		check(status.phase == "out-of-range" and status.rangeMeters == 80.0,"short grape range has distinct readable guidance")
		var edge := battle("fuchuan",100.0)
		edge.ships[1].core.set_state({"x":sin(deg_to_rad(26.0))*110.0,"z":cos(deg_to_rad(26.0))*110.0},0.0)
		check(cannon.call("broadside_status",edge.snapshot(),"player","starboard").phase == "out-of-arc","hostile outside 25-degree side arc receives helm guidance")
		edge.ships[1].core.set_state({"x":0.0,"z":249.0},0.0)
		check(cannon.call("broadside_status",edge.snapshot(),"player","starboard").phase == "ready","solid shot near 250m maximum remains eligible")
	var hud := Hud.new(); root.add_child(hud); await process_frame
	var packet := {"naval":advice.snapshot(),"runtime":{"mode":"duel","notice":"","surrenderQuote":{},"pauseReasons":[],"paused":false}}
	hud.apply_snapshot(packet)
	var feedback: Label = hud.find_child("GunneryStatus",true,false)
	check(feedback != null and feedback.text.contains("80") and feedback.text.contains("靠近"),"actual practice HUD explains short grape shot range")
	advice.command({"type":"select-ammo","ammo":"solid"}); advice.command({"type":"fire","side":"starboard"}); packet.naval=advice.snapshot(); hud.apply_snapshot(packet)
	check(hud.find_child("fire_starboard",true,false).disabled and hud.find_child("fire_starboard",true,false).tooltip_text.contains("装填"),"actual practice fire control reflects authoritative reload")
	packet.naval=unsafe.snapshot(); hud.apply_snapshot(packet)
	check(hud.find_child("fire_starboard",true,false).disabled and hud.find_child("GunneryStatus",true,false).text.contains("友船"),"actual practice HUD explains protected hull obstruction")
	hud.queue_free(); await process_frame
	print("REFERENCE_GUNNERY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
