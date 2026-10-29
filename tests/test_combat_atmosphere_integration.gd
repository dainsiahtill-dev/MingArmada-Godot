extends SceneTree
## Real Sea/Encounter integration; no invented fire, hit, sink or destruction.
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Tail = preload("res://game/scenes/common/terminal_presentation_clock.gd")
const Deck = preload("res://game/presentation/crew/deck_stations.gd")
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0
var destruction_events: Array = []

func check(ok: bool, label: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL COMBAT ATMOSPHERE INTEGRATION: ", label)
	return ok
func _initialize() -> void: run.call_deferred()
func ground(_x: float, _z: float) -> float: return -80.0
func water(_x: float, _z: float, _time: float) -> float: return 0.0
func ship(native: Dictionary, id: String) -> Dictionary:
	for value: Dictionary in native.ships:
		if value.id == id: return value
	return {}
func point(value: Dictionary) -> Vector3: return Vector3(float(value.x), float(value.y), float(value.z))
func particle_point(value: Dictionary) -> Vector3: return Vector3(float(value.position[0]), float(value.position[1]), float(value.position[2]))
func fixture(id: String) -> RefCounted:
	return Encounter.new({"mode": "terminal", "referenceGunnery": true, "seed": 1661, "battleId": id, "playerId": "player", "wind": {"direction": {"x": 1.0, "y": 0.0}, "speed": 0.0}, "oceanWaves": [], "sampleTerrainHeight": ground, "ships": [
		{"id": "player", "kind": "fuchuan", "team": "player", "position": {"x": 0.0, "z": 0.0}, "heading": 0.0, "sailDeployment": 0.0, "hull": 42.0},
		{"id": "enemy", "kind": "fuchuan", "team": "hostile", "position": {"x": 0.0, "z": 55.0}, "heading": 0.0, "sailDeployment": 0.0, "hull": 100.0}
	]})
func make_sea(native: Dictionary, enabled: bool) -> Node3D:
	var sea := Sea.new()
	root.add_child(sea)
	sea.apply_settings({"quality": "low", "cameraFollow": false})
	var options := {"chunk_radius": 0, "resolution": 8, "ocean_resolution": 24, "ocean_distance": 1200.0, "vegetation": false, "island_details": false, "fidelity_islands": false, "interactive_wake": false}
	# Omission, rather than enabled:true, proves the formal default.
	if not enabled: options.combat_atmosphere = false
	check(sea.configure(ground, [], water, native, options), "actual production Sea configures")
	return sea
func seen_destruction(event: Dictionary) -> void:
	if event.get("type") == "destruction-explosion": destruction_events.append(event.duplicate(true))

func run() -> void:
	var effects := Effects.new()
	var model := Ship.new()
	var contracts := effects.has_method("configure_atmosphere") and effects.has_method("atmosphere_diagnostics") and model.has_method("source_destruction_anchor") and model.has_method("source_deck_model")
	check(contracts, "production effect owner and readonly drawn-deck APIs exist")
	effects.free(); model.free()
	if not contracts: finish(); return
	await production_case()
	finish()

func production_case() -> void:
	var encounter := fixture("atmosphere-production")
	if not check(encounter.last_error.is_empty(), "real terminal encounter validates"): return
	var native: Dictionary = encounter.snapshot()
	var sea := make_sea(native, true)
	var initial: Dictionary = sea.effects.atmosphere_diagnostics()
	if not check(initial.get("ready", false) and initial.get("enabled", false) and initial.get("particles", []).is_empty(), "formal Sea default enables an initially empty atmosphere"):
		sea.dispose(); sea.free(); return
	var player_view: Node3D = sea.ships.player
	player_view.presentation_event.connect(seen_destruction)
	var deck_model: Node3D = player_view.source_deck_model()
	check(deck_model == player_view.get("_models")[0], "public deck model always returns canonical LOD0")
	player_view.set_lod_distance(1000.0)
	check(player_view.source_deck_model() == deck_model and player_view.get_model() != deck_model, "deck coordinate API remains stable when displayed LOD changes")
	player_view.set_lod_distance(0.0)
	var deck := Deck.new()
	check(deck.configure("fuchuan", deck_model), "independent actual deck support configures")
	var support: Dictionary = deck.sample(0.0, 0.0)
	if not check(not support.is_empty(), "canonical hull supplies real central deck triangle"):
		sea.dispose(); sea.free(); return
	var local_anchor: Vector3 = support.point + Vector3.UP * 0.35
	var anchor: Dictionary = player_view.source_destruction_anchor()
	check(anchor.get("position") is Vector3 and anchor.shipId == "player" and anchor.time == native.time and anchor.position.is_equal_approx(deck_model.global_transform * local_anchor), "readonly deck anchor includes actual current model transform exactly once")
	var before_authority := native.duplicate(true)
	check(encounter.command({"type": "fire", "shipId": "player", "side": "starboard"}).get("ok", false), "real player fire is authorized")
	sea.observe_projectiles(native)
	encounter.step_fixed()
	native = encounter.snapshot()
	var events: Array = encounter.drain_events()
	var original_events := events.duplicate(true)
	var original_native := native.duplicate(true)
	sea.remember_authoritative_poses(native, STEP)
	var presented: Array = sea.apply_local_fire(native, events, STEP)
	check(events == original_events and native == original_native and before_authority.tick == 0, "local-fire presentation leaves all native and caller event data untouched")
	var atmosphere: Dictionary = sea.effects.atmosphere_diagnostics()
	check(atmosphere.active_smoke > 0 and sea.effects.get("_source_fire").size() > 0, "local-fire immediately feeds both candidate smoke and retained source effects")
	var player_fire: Array = presented.filter(func(e: Dictionary) -> bool: return e.get("type") == "fire" and e.get("shipId") == "player")
	check(not player_fire.is_empty(), "local-fire returns actual player's source-muzzle event")
	for shot: Dictionary in player_fire:
		check(shot.has("source_muzzle_position"), "drawn muzzle is captured before atmosphere consumes fire")
		if not shot.has("source_muzzle_position"): continue
		var matching: Array = atmosphere.particles.filter(func(p: Dictionary) -> bool: return String(p.id).begins_with(String(shot.id) + ":smoke:"))
		check(not matching.is_empty(), "candidate plume is traceable to same real event ID")
		for particle: Dictionary in matching: check(particle_point(particle).distance_to(point(shot.source_muzzle_position)) < 0.3, "new smoke is at actual source mouth with only its accepted age motion")
	var local_anchor_now: Dictionary = player_view.source_destruction_anchor()
	check(local_anchor_now.time == native.time and local_anchor_now.position.is_equal_approx(deck_model.global_transform * local_anchor), "local-fire submits fresh drawn-deck anchor for the firing owner")
	var once: Array = atmosphere.particles.duplicate(true)
	sea.apply_snapshot(native, events, 0.0)
	check(sea.effects.atmosphere_diagnostics().particles == once, "same-time full presentation and repeated event cannot duplicate or advance local-fire particles")
	sea.apply_settings({"quality": "balanced"})
	check(sea.effects.atmosphere_diagnostics().particles == once, "paused quality rebuild preserves existing atmosphere lifetime and position")
	var actual_sinks := 0
	var pending: Array = []
	var consumed := 0.0
	for index in 1800:
		if native.status in ["victory", "defeat"]: break
		sea.observe_projectiles(native)
		var player := ship(native, "player")
		if player.hull > 0.0 and player.crew > 0.0 and player.cooldownSeconds.starboard <= 0.0 and player.ammo.solid > 0:
			encounter.command({"type": "fire", "shipId": "player", "side": "starboard"})
		encounter.step_fixed()
		native = encounter.snapshot()
		var accepted: Array = encounter.drain_events()
		for event: Dictionary in accepted:
			if event.type == "sink": actual_sinks += 1
		pending.append_array(accepted)
		consumed += STEP
		sea.remember_authoritative_poses(native, STEP)
		if (index + 1) % 15 == 0 or native.status in ["victory", "defeat"]:
			sea.apply_snapshot(native, pending, consumed)
			pending.clear(); consumed = 0.0
	if not check(native.status in ["victory", "defeat"] and actual_sinks > 0, "normal opposing cannon AI and real ballistics reach an actual sink"):
		sea.dispose(); sea.free(); return
	var terminal := native.duplicate(true)
	var tail := Tail.new()
	tail.advance(native, ["result"], STEP, STEP)
	var saw_flame := false
	var saw_underwater := false
	for _index in 41:
		var seconds: float = tail.advance(native, ["result"], 0.25, 0.0)
		var visual: Dictionary = tail.snapshot(native)
		sea.remember_authoritative_poses(visual, seconds)
		sea.apply_snapshot(visual, [], seconds)
		check(encounter.snapshot() == terminal and native == terminal, "production flame tail cannot mutate frozen encounter")
		var data: Dictionary = sea.effects.atmosphere_diagnostics()
		if data.active_flames > 0 and not destruction_events.is_empty():
			saw_flame = true
			var drawn: Dictionary = player_view.source_destruction_anchor()
			check(not drawn.is_empty() and drawn.time == visual.time and drawn.position.is_equal_approx(deck_model.global_transform * local_anchor), "wreck fire follows actual sinking deck without applying sinking twice")
			var paused: Array = data.particles.duplicate(true)
			sea.apply_snapshot(visual, [], 0.0)
			check(sea.effects.atmosphere_diagnostics().particles == paused, "same-time terminal redraw cannot move attached flames or world smoke")
		if data.underwater_stopped > 0: saw_underwater = true
	check(destruction_events.size() == 1 and saw_flame, "one actual ShipDamage destruction event activates production attached wreck fire")
	check(saw_underwater, "real sinking deck crosses water and permanently stops attached fire")
	check(sea.effects.atmosphere_diagnostics().particles.is_empty() and player_view.source_destruction_anchor().is_empty(), "terminal tail expires smoke and completed sink has no live deck attachment")
	var old_effects: WeakRef = weakref(sea.effects)
	var replacement := fixture("atmosphere-next-epoch")
	var fresh: Dictionary = replacement.snapshot()
	sea.apply_snapshot(fresh, [], 0.0)
	var renewed: Dictionary = sea.effects.atmosphere_diagnostics()
	check(old_effects.get_ref() == null and renewed.ready and renewed.enabled and renewed.particles.is_empty() and renewed.seen_events == 0, "new epoch recreates configured effect owner with no stale event identities")
	check(not sea.ships.player.source_destruction_anchor().is_empty(), "new epoch reconnects a valid fresh ship anchor provider")
	sea.dispose()
	check(sea.effects == null and sea.ships.is_empty(), "Sea dispose releases effect owner and fleet")
	sea.free()
	var baseline := make_sea(fresh, false)
	check(replacement.command({"type": "fire", "shipId": "player", "side": "starboard"}).get("ok", false), "explicit baseline uses same real fire command")
	replacement.step_fixed()
	var baseline_native: Dictionary = replacement.snapshot()
	var baseline_events: Array = replacement.drain_events()
	baseline.remember_authoritative_poses(baseline_native, STEP)
	baseline.apply_local_fire(baseline_native, baseline_events, STEP)
	var disabled: Dictionary = baseline.effects.atmosphere_diagnostics()
	check(not disabled.enabled and disabled.particles.is_empty() and disabled.draw_calls == 0 and baseline.effects.get("_source_fire").size() > 0, "explicit world combat_atmosphere:false disables only candidate and retains source cannon effects")
	var baseline_next := fixture("baseline-next-epoch")
	baseline.apply_snapshot(baseline_next.snapshot(), [], 0.0)
	check(not baseline.effects.atmosphere_diagnostics().enabled, "explicit candidate-off survives new-epoch effect reconstruction")
	baseline.dispose(); baseline.free()
	await process_frame

func finish() -> void:
	print("COMBAT_ATMOSPHERE_INTEGRATION_TESTS assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
