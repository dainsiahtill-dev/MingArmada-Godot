extends SceneTree
## Real CombatEffects owner and real presentation Nodes. Event packets below are
## adapter fixtures, not a claim that a gameplay launch or hit was simulated.
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const LivingFire = preload("res://game/presentation/combat/ship_fire_view.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
var assertions: int = 0
var failures: int = 0
var _effects: Node3D
var _deck: Node3D
var _anchor_time: float = 0.0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	_effects = Effects.new()
	root.add_child(_effects)
	_deck = Node3D.new()
	_deck.name = "ObservedDeck"
	_deck.position = Vector3(3.0, 4.0, 5.0)
	root.add_child(_deck)
	for method: String in ["configure_atmosphere", "atmosphere_diagnostics", "refresh_attached_effects", "apply_snapshot", "apply_events", "set_water_sampler"]:
		check(_effects.has_method(method), "effect owner API " + method)
	if failures > 0:
		_finish()
		return
	_effects.set_water_sampler(_water)
	var configured: Dictionary = _effects.configure_atmosphere({"quality":"low"}, _anchor)
	if not check(configured.get("ok", false), "actual effect owner configures living-fire texture backend"):
		_finish()
		return
	var atmosphere: Node3D = _effects.get("_atmosphere")
	var native_factory: bool = atmosphere != null and atmosphere.get_script() == LivingFire
	if not check(native_factory and _effects.atmosphere_diagnostics().has("living_fires"), "FIRE_SKIRMISH_EFFECTS_MISSING: CombatEffects factory owns the living-fire subclass"):
		_finish()
		return
	_test_living_fire_owner()
	_test_payload_material()
	_test_payload_event_adapters()
	_test_same_time_epoch()
	_finish()

func _test_same_time_epoch() -> void:
	var packet: Dictionary = _packet(0.0, "epoch-a")
	packet.projectiles=[{"id":"reused-shot","shipId":"ship","ammo":"solid","position":{"x":1.0,"y":3.0,"z":4.0},"velocity":{"x":0.0,"y":0.0,"z":1.0}}]
	_present(packet)
	_effects.apply_events([{"id":"reused-event","type":"splash","time":0.0,"position":{"x":4.0,"y":0.0,"z":8.0}}])
	check(_effects.diagnostics().splashes>0,"same-time epoch fixture owns a real old water splash")
	packet.battleId="epoch-b";packet.projectiles[0].erase("ammo");packet.projectiles[0].kind="fire-payload";packet.projectiles[0].payload="fire-ball"
	_present(packet)
	check(_effects.get("_balls")["reused-shot"].material_override==_effects.get("_fire_ball_material"),"same-time epoch recreates reused projectile IDs with their correct material")
	check(_effects.diagnostics().events==0 and _effects.diagnostics().splashes==0,"same-time epoch clears old event dedupe and water ownership")

func _water(_x: float, _z: float, _seconds: float) -> float:
	return 0.0

func _anchor(ship_id: String) -> Dictionary:
	return {"position":_deck.global_position, "shipId":ship_id, "time":_anchor_time}

func _packet(seconds: float, epoch: String, burning: bool = false) -> Dictionary:
	var state: Dictionary = Fire.initial(24)
	if burning: state = Fire.ignite(state, "fire-ball", 0.0).state
	return {"time":seconds, "tick":int(round(seconds*60.0)), "battleId":epoch, "status":"active", "playerId":"ship",
		"wind":{"direction":{"x":1.0, "y":0.0}, "speed":8.0}, "ships":[{"id":"ship", "hull":100.0, "fireControl":state}], "projectiles":[]}

func _present(packet: Dictionary) -> void:
	_anchor_time = packet.time
	_effects.apply_snapshot(packet, 0.0)
	_effects.refresh_attached_effects()

func _test_living_fire_owner() -> void:
	var cold: Dictionary = _packet(0.0, "owner-live-fire")
	_present(cold)
	var initial: Dictionary = _effects.atmosphere_diagnostics()
	check(initial.living_fires == 0 and initial.active_flames == 0 and initial.active_smoke == 0, "zero authority heat produces no living fire through real owner")
	var hot: Dictionary = _packet(0.25, "owner-live-fire", true)
	var authority: Dictionary = hot.duplicate(true)
	_present(hot)
	var burning: Dictionary = _effects.atmosphere_diagnostics()
	check(burning.living_fires == 1 and burning.active_flames > 0 and burning.active_smoke > 0, "positive authority heat reaches living flames and smoke through CombatEffects")
	_present(hot)
	check(_effects.atmosphere_diagnostics() == burning, "same accepted snapshot never duplicates living emission")
	check(hot == authority, "real effect owner leaves authoritative fire state untouched")
	_deck.position.x = 13.0
	hot.time = 0.5
	hot.tick = 30
	_present(hot)
	var moved: Dictionary = _effects.atmosphere_diagnostics()
	var world_smoke: bool = false
	for particle: Dictionary in moved.particles:
		if particle.kind == "flame": check(absf(float(particle.position[0])-13.0) < 2.0, "real Node3D deck transform moves attached flame once")
		if particle.kind == "smoke" and is_equal_approx(float(particle.born), 0.25): world_smoke = absf(float(particle.position[0])-3.0) < 3.0
	check(world_smoke, "earlier smoke stays at its world birth after actual deck moves")
	_present(_packet(0.75, "owner-live-fire"))
	var quenched: Dictionary = _effects.atmosphere_diagnostics()
	check(quenched.living_fires == 0 and quenched.active_flames == 0 and quenched.active_smoke > 0, "quenching removes living flames immediately and retains finite residual smoke")
	_present(_packet(8.0, "owner-live-fire"))
	check(_effects.atmosphere_diagnostics().particles.is_empty(), "residual smoke expires on accepted owner time")
	_present(_packet(8.25, "owner-live-fire", true))
	check(_effects.atmosphere_diagnostics().living_fires == 1, "new positive fire can be observed after a prior quench")
	_present(_packet(8.25, "owner-next-epoch"))
	var renewed: Dictionary = _effects.atmosphere_diagnostics()
	check(renewed.living_fires == 0 and renewed.particles.is_empty(), "new battle ID clears living ownership and smoke even without clock rewind")

func _test_payload_material() -> void:
	var native: Dictionary = _packet(0.0, "owner-projectiles")
	native.projectiles = [
		{"id":"plain-shot", "shipId":"ship", "ammo":"solid", "position":{"x":1.0, "y":3.0, "z":4.0}, "velocity":{"x":1.0, "y":1.0, "z":1.0}, "age":0.0, "ttl":8.0},
		{"id":"fire-shot", "shipId":"ship", "kind":"fire-payload", "payload":"fire-ball", "position":{"x":2.0, "y":3.0, "z":4.0}, "velocity":{"x":1.0, "y":1.0, "z":1.0}, "age":0.0, "ttl":4.0},
	]
	var before: Dictionary = native.duplicate(true)
	_present(native)
	var carriers: Dictionary = _effects.get("_balls")
	if not check(carriers.has("plain-shot") and carriers.has("fire-shot"), "real effect owner creates both ordinary and auxiliary projectile carriers"):
		return
	var ordinary: MeshInstance3D = carriers["plain-shot"]
	var payload: MeshInstance3D = carriers["fire-shot"]
	var plain_material: Material = ordinary.material_override
	var fire_material: Material = payload.material_override
	var distinct: bool = plain_material != null and fire_material != null and plain_material != fire_material
	if plain_material is BaseMaterial3D and fire_material is BaseMaterial3D:
		distinct = distinct and (plain_material.albedo_color != fire_material.albedo_color or plain_material.emission_enabled != fire_material.emission_enabled or plain_material.emission != fire_material.emission)
	check(distinct, "auxiliary projectile has an actually different material appearance from solid shot")
	check(ordinary.position == Vector3(1.0, 3.0, 4.0) and payload.position == Vector3(2.0, 3.0, 4.0), "different carriers still follow exact authoritative projectile positions")
	check(native == before, "projectile styling neither relabels ammunition nor mutates native data")

func _ordinary_fragments() -> int:
	var found: int = 0
	var puffs: Array = _effects.get("_puffs")
	for puff: Dictionary in puffs:
		var node: MeshInstance3D = puff.node
		var material: Material = puff.material
		if not material is BaseMaterial3D: continue
		var color: Color = material.albedo_color
		if node.mesh is BoxMesh and is_equal_approx(color.r, 0.55) and is_equal_approx(color.g, 0.35) and is_equal_approx(color.b, 0.15): found += 1
	return found

func _test_payload_event_adapters() -> void:
	_present(_packet(0.0, "owner-payload-events"))
	var events: Array = [
		{"id":"aux-launch", "type":"fire-payload-launched", "time":0.0, "shipId":"ship", "targetId":"enemy", "payload":"fire-ball", "projectileId":"aux-shot", "position":{"x":3.0, "y":4.0, "z":5.0}, "velocity":{"x":0.0, "y":8.0, "z":25.0}},
		{"id":"aux-hit", "type":"fire-payload-hit", "time":0.0, "shipId":"ship", "targetId":"enemy", "payload":"fire-ball", "projectileId":"aux-shot", "position":{"x":3.0, "y":4.0, "z":50.0}},
		{"id":"aux-splash", "type":"fire-payload-splash", "time":0.0, "shipId":"ship", "payload":"thorn-ball", "projectileId":"missed-shot", "position":{"x":8.0, "y":0.0, "z":35.0}},
	]
	var originals: Array = events.duplicate(true)
	var fragments: int = _ordinary_fragments()
	var water_before: int = int(_effects.diagnostics().splashes)
	var decorated: Array = _effects.presentation_events(events)
	_effects.apply_events(decorated)
	var shown: Dictionary = _effects.diagnostics()
	check(shown.source_fire == 0 and _effects.find_children("CannonSource_*", "Node3D", true, false).is_empty(), "auxiliary launch never creates an ordinary CannonSource node")
	check(_ordinary_fragments() == fragments, "auxiliary hit does not become ordinary brown cannon-hit fragments")
	check(_effects.atmosphere_diagnostics().living_fires == 0 and _effects.atmosphere_diagnostics().active_flames == 0, "payload event alone cannot forge positive heat or persistent fire")
	check(int(shown.splashes) == water_before+1, "auxiliary miss is routed to one real water splash")
	var event_types: Array = decorated.map(func(event: Dictionary) -> String: return event.type)
	var original_types: Array = originals.map(func(event: Dictionary) -> String: return event.type)
	check(events == originals and event_types == original_types and decorated.all(func(event: Dictionary) -> bool: return not event.has("ammo") and not event.has("damage")), "splash adapter preserves independent original event types and caller data")
	_effects.apply_events(decorated)
	check(int(_effects.diagnostics().splashes) == water_before+1 and _ordinary_fragments() == fragments and _effects.diagnostics().source_fire == 0, "redelivered payload events deduplicate without extra water, cannon smoke or hit fragments")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL FIRE SKIRMISH EFFECTS: ", label)
	return value

func _finish() -> void:
	if is_instance_valid(_effects):
		_effects.dispose()
		_effects.free()
	if is_instance_valid(_deck): _deck.free()
	print("FIRE_SKIRMISH_EFFECTS assertions=", assertions, " failures=", failures)
	quit(0 if failures == 0 else 1)
