extends SceneTree
## Headless behavior checks. GPU appearance is accepted separately by the owner.
const PATH: String = "res://game/research/demos/ship_fire_zone_view.gd"
const Spread = preload("res://modules/naval_simulation/combat/fire_spread.gd")
const ZONES: Array[String] = ["bow", "mid", "stern"]
var checks: int = 0
var failures: int = 0
var _script: Script
var _anchors: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL zone fire: ", label)
	return value

func _finish() -> void:
	print("SHIP_FIRE_ZONE_VIEW checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func _run() -> void:
	if not check(ResourceLoader.exists(PATH), "SHIP_FIRE_ZONE_VIEW_MISSING: research candidate exists"):
		_finish()
		return
	_script = load(PATH)
	if not check(_script != null, "candidate script loads"):
		_finish()
		return
	_test_per_ship_budget_and_rotation()
	_test_time_gate_and_no_backfill()
	_test_world_smoke_and_current_heat_flames()
	_test_anchor_validation()
	_test_cold_rewind_and_disposal()
	_test_real_ship_capacity_and_snapshot_validation()
	_test_detached_diagnostics()
	_finish()

func _ship(id: String = "real-ship", heats: Array = [20.0, 20.0, 20.0]) -> Dictionary:
	var spread: Dictionary = Spread.initial(24)
	spread.heatByZone = heats.duplicate()
	spread.fuelSeconds = 24.0
	return {"id": id, "hull": 100.0, "fireSpread": spread, "fireControl": Spread.summary(spread)}

func _packet(time: float, ships: Array, epoch: String = "zones") -> Dictionary:
	return {"time": time, "battleId": epoch, "wind": {"direction": {"x": 1.0, "y": 0.0}, "speed": 8.0}, "ships": ships}

func _put_anchors(id: String, time: float, x: float = 0.0) -> void:
	for index: int in range(3):
		var zone: String = ZONES[index]
		_anchors[id + "|" + zone] = {"shipId": id, "zone": zone, "time": time, "position": Vector3(x, 4.0, float(index - 1) * 8.0)}

func _provider(key: String) -> Dictionary:
	return _anchors.get(key, {})

func _new_view() -> Variant:
	_anchors.clear()
	var view: Variant = _script.new()
	root.add_child(view)
	var receipt: Dictionary = view.configure({}, null, func(_x: float, _z: float, _time: float) -> float: return 0.0, _provider)
	check(receipt.get("ok", false), "original textures configure bounded inherited batches")
	return view

func _burn(view: Variant, time: float, ships: Array, epoch: String = "zones") -> Dictionary:
	view.apply_snapshot(_packet(time, ships, epoch))
	view.refresh_anchors()
	return view.diagnostics()

func _birth_counts(diagnostic: Dictionary, time: float) -> Dictionary:
	var counts: Dictionary = {"smoke": 0, "flame": 0, "zones": {"bow": {"smoke": 0, "flame": 0}, "mid": {"smoke": 0, "flame": 0}, "stern": {"smoke": 0, "flame": 0}}}
	for particle: Dictionary in diagnostic.get("particles", []):
		if float(particle.born) != time: continue
		var kind: String = str(particle.kind)
		var zone: String = str(particle.get("zone", ""))
		if kind not in ["smoke", "flame"]: continue
		counts[kind] += 1
		if zone in ZONES: counts.zones[zone][kind] += 1
	return counts

func _test_per_ship_budget_and_rotation() -> void:
	# Catches multiplying the old whole-ship emitter by the number of zones.
	for heats: Array in [[60.0, 0.0, 0.0], [30.0, 30.0, 0.0], [20.0, 20.0, 20.0]]:
		var view: Variant = _new_view()
		var ship: Dictionary = _ship("real-ship", heats)
		_put_anchors("real-ship", 0.0)
		var diagnostic: Dictionary = _burn(view, 0.0, [ship])
		var counts: Dictionary = _birth_counts(diagnostic, 0.0)
		check(counts.smoke == 3 and counts.flame == 4, "one real ship emits exactly three smoke and four flame for one to three zones")
		var active: int = 0
		for index: int in range(3):
			if float(heats[index]) <= 0.0: continue
			active += 1
			check(counts.zones[ZONES[index]].smoke >= 1 and counts.zones[ZONES[index]].flame >= 1, "every active zone receives both particle kinds")
		check(diagnostic.get("living_fires", -1) == 1 and diagnostic.get("burning_zones", -1) == active, "ownership counts real ships and hot zones independently")
		if active == 3:
			check(counts.zones.bow.flame == 2 and counts.zones.mid.flame == 1 and counts.zones.stern.flame == 1, "first three-zone extra flame starts at bow")
		_put_anchors("real-ship", 0.25)
		var next: Dictionary = _birth_counts(_burn(view, 0.25, [ship]), 0.25)
		if active == 3: check(next.zones.mid.flame == 2 and next.zones.bow.flame == 1, "next slot rotates extra flame to mid")
		if active == 2: check(counts.zones.bow.smoke == 2 and next.zones.mid.smoke == 2, "two-zone extra smoke rotates between active zones")
		var per_ship: Dictionary = view.diagnostics().get("ships", {}).get("real-ship", {})
		check(per_ship.get("emitted_smoke", -1) == 6 and per_ship.get("emitted_flames", -1) == 8, "cumulative budget records actual per-ship emissions")
		view.free()

func _test_time_gate_and_no_backfill() -> void:
	# Catches frame-based spawning, camera-dependent spawning, and gap replay.
	var view: Variant = _new_view()
	var ship: Dictionary = _ship()
	_put_anchors("real-ship", 0.0)
	var first: Dictionary = _burn(view, 0.0, [ship])
	view.apply_snapshot(_packet(0.0, [ship]))
	view.refresh_anchors()
	view.refresh_anchors()
	check(view.diagnostics() == first, "paused duplicate snapshots and refreshes do not alter emission diagnostics")
	var camera: Camera3D = Camera3D.new()
	root.add_child(camera)
	view.set_camera(camera)
	view.refresh_anchors()
	check(view.diagnostics().ships["real-ship"].emitted_flames == 4, "camera refresh cannot respawn fire")
	_put_anchors("real-ship", 0.24)
	_burn(view, 0.24, [ship])
	check(view.diagnostics().ships["real-ship"].emitted_smoke == 3, "advancing inside one quarter-second slot does not emit")
	_put_anchors("real-ship", 2.0)
	var jumped: Dictionary = _burn(view, 2.0, [ship])
	var born: Dictionary = _birth_counts(jumped, 2.0)
	check(born.smoke == 3 and born.flame == 4 and jumped.ships["real-ship"].emitted_smoke == 6, "time gap emits only current observed slot without replaying seven skipped slots")
	check(jumped.ships["real-ship"].last_slot.get("slot", -1) == 8 and jumped.ships["real-ship"].last_slot.get("smoke", -1) == 3 and jumped.ships["real-ship"].last_slot.get("flame", -1) == 4, "last-slot evidence reports one whole-ship budget")
	camera.free()
	view.free()

func _test_world_smoke_and_current_heat_flames() -> void:
	# Catches old flames detached from the moving zone and alpha frozen at birth.
	var view: Variant = _new_view()
	var ship: Dictionary = _ship("real-ship", [60.0, 0.0, 0.0])
	_put_anchors("real-ship", 0.0)
	_burn(view, 0.0, [ship])
	_put_anchors("real-ship", 0.1, 50.0)
	var moved: Dictionary = _burn(view, 0.1, [ship])
	var smoke_stays: bool = false
	var high_alpha: float = 0.0
	for particle: Dictionary in moved.particles:
		check(particle.get("ship_id", "") == "real-ship" and particle.get("zone", "") == "bow", "visible evidence tags the actual ship and zone")
		if particle.kind == "smoke": smoke_stays = smoke_stays or absf(float(particle.position[0])) < 3.0
		if particle.kind == "flame":
			check(absf(float(particle.position[0]) - 50.0) < 2.0 and absf(float(particle.position[2]) + 8.0) < 2.0, "each existing flame follows its actual current bow anchor")
			high_alpha = maxf(high_alpha, float(particle.alpha))
	check(smoke_stays, "already-born smoke remains in world space after a fifty-metre ship move")
	ship = _ship("real-ship", [3.0, 0.0, 0.0])
	var cooled: Dictionary = _burn(view, 0.1, [ship])
	var low_alpha: float = 0.0
	for particle: Dictionary in cooled.particles:
		if particle.kind == "flame": low_alpha = maxf(low_alpha, float(particle.alpha))
	check(low_alpha > 0.0 and low_alpha < high_alpha * 0.2, "flame opacity responds to current zone heat within the same emission slot")
	view.free()

func _test_anchor_validation() -> void:
	# Catches fabricated center anchors and acceptance of stale, submerged, or wrong-zone poses.
	var invalid: Array = [
		{},
		{"shipId": "other", "zone": "bow", "time": 0.0, "position": Vector3(0, 4, 0)},
		{"shipId": "real-ship", "zone": "mid", "time": 0.0, "position": Vector3(0, 4, 0)},
		{"shipId": "real-ship", "zone": "bow", "time": -0.1, "position": Vector3(0, 4, 0)},
		{"shipId": "real-ship", "zone": "bow", "time": 0.0, "position": Vector3(0, -1, 0)},
		{"shipId": "real-ship", "zone": "bow", "time": 0.0, "position": Vector3(INF, 4, 0)},
		{"shipId": "real-ship", "zone": "bow", "time": 0.0, "position": {"x": 0.0, "y": 4.0, "z": 0.0}}
	]
	for source: Dictionary in invalid:
		var view: Variant = _new_view()
		_anchors["real-ship|bow"] = source
		var result: Dictionary = _burn(view, 0.0, [_ship("real-ship", [60.0, 0.0, 0.0])])
		check(result.active_flames == 0 and result.active_smoke == 0 and result.reserved_particles == 0, "invalid zone pose cannot emit or reserve hidden particles")
		view.free()
	var view: Variant = _new_view()
	_put_anchors("real-ship", 0.0)
	_burn(view, 0.0, [_ship()])
	view.apply_snapshot(_packet(0.1, [_ship()]))
	view.refresh_anchors()
	check(view.diagnostics().active_flames == 0, "prior accepted-time anchors cannot keep flame visible")
	view.free()

func _test_cold_rewind_and_disposal() -> void:
	# Catches cold-zone particle resurrection and state surviving rewind/epoch/dispose.
	var view: Variant = _new_view()
	_put_anchors("real-ship", 0.0)
	_burn(view, 0.0, [_ship()])
	var cold: Dictionary = _burn(view, 0.0, [_ship("real-ship", [0.0, 20.0, 20.0])])
	for particle: Dictionary in cold.particles:
		check(particle.kind != "flame" or particle.zone != "bow", "cold bow immediately loses every attached flame")
	_burn(view, 0.0, [_ship()])
	check(view.diagnostics().ships["real-ship"].emitted_flames == 4, "cold then hot in one paused slot cannot emit twice")
	for particle: Dictionary in view.diagnostics().particles:
		check(particle.kind != "flame" or particle.zone != "bow", "old bow flames cannot resurrect after same-slot reheat")
	var extinguished: Dictionary = _burn(view, 0.0, [_ship("real-ship", [0.0, 0.0, 0.0])])
	check(extinguished.living_fires == 0 and extinguished.burning_zones == 0 and extinguished.active_flames == 0, "all-cold ship has no living emitter or visible flame")
	_put_anchors("real-ship", 0.25)
	_burn(view, 0.25, [_ship()])
	_put_anchors("real-ship", 0.0)
	var rewind: Dictionary = _burn(view, 0.0, [_ship()])
	check(rewind.reserved_particles == 7 and rewind.ships["real-ship"].emitted_flames == 4, "rewind discards previous particle ownership and counters")
	var reset: Dictionary = _burn(view, 0.0, [], "other-epoch")
	check(reset.reserved_particles == 0 and reset.particles.is_empty() and reset.living_fires == 0, "epoch reset clears every prior particle")
	view.dispose()
	view.refresh_anchors()
	check(not view.diagnostics().ready and view.get_child_count() == 0 and view.diagnostics().particles.is_empty(), "disposal releases batches and prohibits stale anchor rendering")
	view.free()

func _test_real_ship_capacity_and_snapshot_validation() -> void:
	# Catches pseudo-ships per zone, accepting bad summaries, and overbooking base capacity.
	var view: Variant = _new_view()
	var ships: Array = []
	for index: int in range(17):
		var id: String = "real-%02d" % index
		ships.append(_ship(id))
		_put_anchors(id, 0.0, float(index) * 20.0)
	var diagnostic: Dictionary = _burn(view, 0.0, ships)
	check(diagnostic.living_fires == 16 and diagnostic.burning_zones == 48 and diagnostic.reserved_particles == 112, "seventeen real ships reserve at most sixteen emitters and forty-eight zones")
	for slot: int in range(1, 10):
		for ship: Dictionary in ships: _put_anchors(str(ship.id), float(slot) * 0.25)
		diagnostic = _burn(view, float(slot) * 0.25, ships)
	check(diagnostic.capacity == 384 and diagnostic.reserved_particles <= 384 and diagnostic.draw_calls <= 3 and view.get_child_count() == 3, "global particle budget remains shared by three inherited batches under sustained load")
	view.free()
	var rejected: Array = []
	var dead: Dictionary = _ship("dead"); dead.hull = 0.0; rejected.append(dead)
	var bad_spread: Dictionary = _ship("bad-spread"); bad_spread.fireSpread.version = "fake"; rejected.append(bad_spread)
	var mismatched: Dictionary = _ship("mismatch"); mismatched.fireControl.heat = 5.0; rejected.append(mismatched)
	var missing: Dictionary = _ship("missing"); missing.erase("fireSpread"); rejected.append(missing)
	view = _new_view()
	for ship: Dictionary in rejected: _put_anchors(str(ship.id), 0.0)
	var result: Dictionary = _burn(view, 0.0, rejected)
	check(result.living_fires == 0 and result.reserved_particles == 0, "invalid r2, incoherent r1 summary, missing r2, and zero real hull cannot create fire")
	view.free()

func _test_detached_diagnostics() -> void:
	var view: Variant = _new_view()
	var ship: Dictionary = _ship()
	var before: Dictionary = ship.duplicate(true)
	_put_anchors("real-ship", 0.0)
	var diagnostic: Dictionary = _burn(view, 0.0, [ship])
	var saved: Dictionary = diagnostic.duplicate(true)
	check(JSON.parse_string(JSON.stringify(diagnostic)) is Dictionary and diagnostic.get("zone_anchors", {}).size() == 3, "diagnostics contain three serializable actual zone anchors")
	diagnostic.ships["real-ship"].emitted_smoke = -99
	diagnostic.zone_anchors["real-ship|bow"].position[0] = -999.0
	if not diagnostic.particles.is_empty(): diagnostic.particles[0].position[0] = -999.0
	check(view.diagnostics() == saved, "editing returned nested diagnostic values cannot mutate live particles, anchors, or accounting")
	check(ship == before, "presentation never modifies authoritative spread or fire summary")
	view.free()
