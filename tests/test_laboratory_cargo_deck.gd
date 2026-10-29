extends SceneTree
## Real Encounter hit -> isolated CargoDamage commit -> actual cargo presentation.
const DEMO_PATH := "res://game/research/demos/cargo_deck_drift_experiment.gd"
const GOODS := ["grain", "water", "wood", "iron", "powder", "cloth", "silk", "porcelain", "tea", "sugar", "salt", "spices"]
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL LAB CARGO DECK: ", reason)
	return value

func finish() -> void:
	print("LABORATORY_CARGO_DECK assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func horizontal_distance(point: Vector3, box: AABB) -> float:
	return Vector2(point.x-clampf(point.x,box.position.x,box.end.x),point.z-clampf(point.z,box.position.z,box.end.z)).length()

func camera_outside_source(demo: Node3D, lot: Dictionary = {}) -> void:
	var source: Dictionary = demo.call("_ship_model", str(lot.get("shipId", "player")))
	var model: Node3D = source.get("model")
	if not check(is_instance_valid(model), "water camera retains the real source ship frame"): return
	var hull := model.find_child("hull", true, false) as MeshInstance3D
	if not check(hull != null and hull.mesh != null, "water camera clearance uses actual authored hull geometry"): return
	var sea: Node3D = demo.get("_sea")
	var eye: Vector3 = sea.camera.global_position
	var bounds := hull.mesh.get_aabb()
	check(horizontal_distance(hull.to_local(eye),bounds) >= .5, "water camera eye remains outside the actual tilted hull footprint")
	if lot.is_empty(): return
	var p: Array = lot.position
	var point := Vector3(p[0],p[1],p[2])
	var outward := point-model.global_position; outward.y=0.0; outward=outward.normalized()
	check((eye-point).dot(outward) >= 5.0, "water camera sits beyond the lot away from its source ship")
	if lot.get("phase") != "floating": return
	check(horizontal_distance(hull.to_local(point),bounds) > .6, "floating origin is outside visual hull geometry, not accepted only by a phase label")
	var cargo_world: Node3D = demo.get("_cargo")
	var models: Dictionary = cargo_world.get("_floating")
	var prop: Node3D = models.get(lot.dropId)
	if not check(is_instance_valid(prop), "floating receipt owns an actual original model node"): return
	var first := true
	var prop_bounds := AABB()
	for child: MeshInstance3D in prop.find_children("*", "MeshInstance3D", true, false):
		if child.mesh == null: continue
		var transformed: AABB = (hull.global_transform.affine_inverse()*child.global_transform)*child.mesh.get_aabb()
		prop_bounds = transformed if first else prop_bounds.merge(transformed); first=false
	check(not first, "floating package clearance samples its real mesh bounds")
	check(prop_bounds.end.x < bounds.position.x or prop_bounds.position.x > bounds.end.x or prop_bounds.end.z < bounds.position.z or prop_bounds.position.z > bounds.end.z, "entire rendered floating package clears the visual hull footprint")

func run() -> void:
	if not check(FileAccess.file_exists(DEMO_PATH), "independent cargo deck/drift demo exists"):
		finish(); return
	var script: Script = load(DEMO_PATH)
	if not check(script != null, "cargo demo script loads"):
		finish(); return
	var demo: Node3D = script.new()
	check(demo.configure({"paused": true}).get("ok", false) and demo.get_child_count() == 0, "pre-tree configuration owns no renderer or campaign save")
	var experiment_viewport := SubViewport.new()
	experiment_viewport.size = Vector2i(1, 1)
	experiment_viewport.own_world_3d = true
	root.add_child(experiment_viewport)
	experiment_viewport.add_child(demo)
	for _i in 2: await process_frame
	experiment_viewport.size = Vector2i(1100, 720)
	for _i in 2: await process_frame
	var initial: Dictionary = demo.inspection_snapshot()
	if not check(initial.ready, "actual production Sea and cargo world are ready"):
		printerr(initial.get("error", "")); demo.dispose(); demo.free(); experiment_viewport.free(); finish(); return
	var hud_strip: Control = demo.get("_strip")
	check(hud_strip.size.y <= 180.0 and hud_strip.size.x <= 1090.0, "HUD recovers compact geometry after 1 by 1 viewport becomes normal")
	check(initial.fixed_step == STEP and initial.tick == 0 and initial.parameters.stage == "showcase", "default is deterministic zero-tick cargo showcase")
	check(initial.native.oceanWaves.size() == 2 and initial.wave_surface.descriptors == initial.native.oceanWaves, "native encounter and cargo sampler share the two gentle real wave descriptors")
	var sea: Node3D = demo.get("_sea")
	check(sea.world.get_ocean().get("_descriptors") == initial.native.oceanWaves, "visible production sea uses the same wave descriptors")
	check(absf(float(demo.call("_water", 6.0, 2.0, 0.0)) - float(demo.call("_water", 6.0, 2.0, 1.0))) > .01, "water sampler has measurable accepted-time wave motion")
	check(initial.inventory.player.size() == 12 and initial.cargo.decks.player.goods.size() == 12, "all twelve real goods have an original visible model")
	for good: String in GOODS: check(initial.inventory.player[good] == 10, "default abstract stock is ten for " + good)
	check(initial.drops.is_empty() and initial.cargo.floating.is_empty() and initial.resources.storage == 0, "showcase invents no drop and uses no campaign storage")
	demo.advance(.25)
	demo.set_camera_mode("water")
	check(demo.inspection_snapshot().native == initial.native and demo.inspection_snapshot().inventory == initial.inventory, "paused water camera leaves authority and cargo unchanged")
	demo.set_camera_mode("deck")
	check(demo.set_parameter("stage", "combat").get("reset_required", false), "combat selection requests clean reset")
	check(demo.set_parameter("good", "porcelain").get("reset_required", false), "single-good selection requests clean reset")
	check(demo.reset_experiment({"stage": "showcase", "good": "porcelain", "paused": false}).get("ok", false), "single-good showcase rebuilds normally")
	for _i in 2: await process_frame
	hud_strip = demo.get("_strip")
	check(hud_strip.size.y <= 180.0, "reset does not retain an oversized wrapped HUD minimum height")
	var selected: Dictionary = demo.inspection_snapshot()
	check(selected.inventory.player == {"porcelain": 10} and selected.cargo.decks.player.goods.size() == 1, "selected good changes actual isolated inventory, not only a display label")
	check(selected.cargo.decks.player.goods[0].good == "porcelain" and selected.cargo.decks.player.goods[0].slot_index == 7, "single porcelain keeps authoritative fixed slot identity")
	demo.advance(.25)
	check(demo.inspection_snapshot().drops.is_empty(), "showcase never fires fake cannon or generates a demonstration loss")
	check(demo.reset_experiment({"stage": "combat", "good": "porcelain", "camera_mode":"water", "paused": false, "seed": 1661}).get("ok", false), "real solid-shot combat starts through clean lifecycle")
	camera_outside_source(demo)
	demo.advance(STEP * .5)
	check(demo.inspection_snapshot().tick == 0, "half step only accumulates")
	demo.advance(STEP * .5)
	for _i in 14: demo.advance(STEP)
	var replay_native: Dictionary = demo.inspection_snapshot().native
	check(demo.inspection_snapshot().tick == 15 and demo.inspection_snapshot().event_counts.fire > 0, "native cannon command creates real fire at fixed sixty hertz")
	check(demo.inspection_snapshot().wave_surface.phase_time == replay_native.time and demo.inspection_snapshot().wave_surface.probe_height != initial.wave_surface.probe_height, "combat advances the shared water phase with the accepted visual clock")
	check(demo.reset_experiment({"paused": false}).get("ok", false), "same combat fixture resets")
	for _i in 15: demo.advance(STEP)
	check(demo.inspection_snapshot().native == replay_native, "identical seed and ticks reproduce native authority exactly")
	var saw_floating := false
	for _i in 240:
		demo.advance(.25)
		var state: Dictionary = demo.inspection_snapshot()
		for lot: Dictionary in state.cargo.floating:
			if lot.get("phase", "") == "floating": saw_floating = true
		if saw_floating and state.splash_count > 0: break
	var combat: Dictionary = demo.inspection_snapshot()
	check(combat.event_counts.hit > 0 and not combat.drops.is_empty(), "real hostile hit causes a committed local cargo receipt")
	var lost := 0
	var unique: Dictionary = {}
	for drop: Dictionary in combat.drops:
		check(drop.goodId == "porcelain" and drop.quantity > 0, "selected actual good owns each lost quantity")
		check(not unique.has(drop.dropId), "drop IDs settle at most once")
		unique[drop.dropId] = true
		lost += int(drop.quantity)
		var caused := false
		for event: Dictionary in combat.events:
			if event.get("id") == drop.sourceEventId:
				caused = event.get("type") == "hit" and event.get("ammo") == "solid" and event.get("targetId") == drop.shipId and event.get("position") == drop.impactPosition
		check(caused and drop.hasImpact and drop.originKind == "event-position", "drop retains actual impact event, target and measured position")
	check(int(combat.inventory.player.get("porcelain", 0)) + lost == 10, "cargo loss and committed receipt quantity conserve original stock")
	check(saw_floating and combat.splash_count > 0, "actual original model passes flight, water entry and floating presentation")
	for lot: Dictionary in combat.cargo.floating:
		check(unique.has(lot.dropId), "every floating package has a committed source receipt")
		camera_outside_source(demo,lot)
	demo.set_paused(true)
	var stopped: Dictionary = demo.inspection_snapshot()
	demo.advance(.25)
	check(demo.inspection_snapshot() == stopped, "pause freezes accepted clock, cargo, water-entry events and floating positions")
	check(not demo.configure({"stage": "invalid"}).get("ok", true) and demo.inspection_snapshot() == stopped, "invalid options cannot destroy valid cargo state")
	check(demo.reset_experiment({"stage": "showcase", "good": "all", "paused": true}).get("ok", false), "reset restores fresh all-goods showcase")
	experiment_viewport.size = Vector2i(1, 1)
	for _i in 2: await process_frame
	experiment_viewport.size = Vector2i(1100, 720)
	for _i in 2: await process_frame
	hud_strip = demo.get("_strip")
	check(hud_strip.size.y <= 180.0, "post-reset narrow-to-normal resize cannot cover the rendered world")
	var restored: Dictionary = demo.inspection_snapshot()
	check(restored.inventory == initial.inventory and restored.drops.is_empty() and restored.cargo.floating.is_empty(), "reset clears seen receipts, lost cargo and old drifting models")
	demo.dispose()
	check(demo.get_child_count() == 0 and demo.inspection_snapshot().disposed, "dispose releases production sea and isolated cargo presentation")
	demo.free()
	experiment_viewport.free()
	await process_frame
	finish()
