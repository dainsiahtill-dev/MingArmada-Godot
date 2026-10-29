extends SceneTree
## Actual authored fuchuan + original cargo GLBs; no fake deck or cargo boxes.
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const DeckSupport = preload("res://game/presentation/crew/deck_stations.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const VIEW_PATH := "res://game/presentation/cargo/cargo_deck_view.gd"
const MODELS_PATH := "res://game/presentation/cargo/cargo_models.gd"
const GOODS := ["grain", "water", "wood", "iron", "powder", "cloth", "silk", "porcelain", "tea", "sugar", "salt", "spices"]
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)
	return value

func finish() -> void:
	print("CARGO_DECK_VIEW assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func mesh_nodes(node: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	if node is MeshInstance3D: found.append(node)
	for child in node.find_children("*", "MeshInstance3D", true, false): found.append(child)
	return found

func rect_distance(point: Vector3, box: AABB) -> float:
	return Vector2(point.x - clampf(point.x, box.position.x, box.end.x), point.z - clampf(point.z, box.position.z, box.end.z)).length()

func material_state(node: Node3D) -> Array:
	var result: Array = []
	for mesh_node: MeshInstance3D in mesh_nodes(node):
		for surface in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.mesh.surface_get_material(surface) as BaseMaterial3D
			if mat: result.append([mat.transparency, mat.albedo_color, mat.roughness, mat.metallic])
	return result

func _run() -> void:
	var available := ResourceLoader.exists(VIEW_PATH) and ResourceLoader.exists(MODELS_PATH)
	check(available, "cargo deck projection and exact-model provider are implemented")
	if not available: finish(); return
	var view_script = load(VIEW_PATH)
	var models_script = load(MODELS_PATH)
	var provider = models_script.new()
	check(Array(provider.GOODS) == GOODS, "provider exposes exactly the authoritative twelve stable goods IDs")
	var material_before: Dictionary = {}
	for good: String in GOODS:
		var first: Node3D = provider.get_model(good)
		if not check(first != null, "original GLB loads for " + good): continue
		var second: Node3D = provider.get_model(good)
		check(second != null and second != first, "cached scene yields independent instances for " + good)
		check(first.get_meta("cargo_asset_path", "") == "res://assets/models/cargo_pack/r1/%s.glb" % good, "real cargo resource provenance for " + good)
		var meshes := mesh_nodes(first)
		check(not meshes.is_empty() and meshes[0].mesh is ArrayMesh, "cargo comes from imported geometry for " + good)
		var triangle_count := 0
		for mesh_node: MeshInstance3D in meshes:
			triangle_count += mesh_node.mesh.get_faces().size() / 3
		check(triangle_count > 3000, "cargo is authored package geometry, not a placeholder cube: " + good)
		material_before[good] = material_state(first)
		first.position = Vector3(99, 88, 77)
		check(second != null and second.position == Vector3.ZERO, "moving one cargo does not move cached/new cargo " + good)
		first.free()
		if second: second.free()
	check(provider.get_model("unknown") == null, "unsupported goods never produce a placeholder")
	var actor := ShipView.new()
	root.add_child(actor)
	if not check(actor.configure("fuchuan"), "actual HeroShipView fuchuan configures"):
		actor.free(); finish(); return
	var model: Node3D = actor.get_model()
	var deck := DeckSupport.new()
	check(model != null and model.is_inside_tree() and deck.configure("fuchuan", model), "actual fuchuan support and stations exist")
	var stations_before: Array = deck.stations.duplicate(true)
	var obstacles_before: Array = deck._obstacles.duplicate(true)
	var view = view_script.new()
	# Preparation is allowed before the independent presentation node enters tree.
	var configured: Dictionary = view.configure(model, "fuchuan")
	check(configured.get("ok", false), "detached cargo view prepares from an attached real model")
	root.add_child(view)
	view.refresh_transform()
	check(view.is_set_as_top_level(), "cargo has independent top-level transform ownership")
	var cargo: Dictionary = {}
	for index in GOODS.size(): cargo[GOODS[index]] = float(index + 1)
	var receipt: Dictionary = view.apply_manifest(cargo, 5.0)
	check(receipt.get("ok", false), "all twelve positive authoritative goods accepted")
	var state: Dictionary = view.snapshot()
	check(int(state.get("available_slots", 0)) == 12, "actual lower fuchuan deck supplies twelve fully safe slots")
	check(state.get("overflow_goods", []).is_empty(), "twelve goods have no hidden overflow")
	check(state.get("goods", []).size() == 12, "one visible package per positive good")
	check(state.get("accepted_time", -1.0) == 5.0, "presentation records supplied accepted clock")
	var anchors: Dictionary = {}
	var occupied: Array[AABB] = []
	for record: Dictionary in state.get("goods", []):
		var good: String = record.good
		var local: Vector3 = record.local_anchor
		var box: AABB = record.slot_bounds
		anchors[good] = local
		check(float(record.quantity) == float(cargo[good]), "abstract quantity retained for " + good)
		check(bool(record.visible), "visible package " + good)
		check(box.size.is_equal_approx(Vector3(.95, 1.1, .95)), "full reserved package volume " + good)
		check(box.end.x <= -.7 or box.position.x >= .7, "whole package clears centre walkway " + good)
		for obstacle: AABB in obstacles_before:
			check(not box.intersects(obstacle.grow(.1)), "whole package clears real obstacle " + good)
		for station: Dictionary in stations_before:
			check(rect_distance(station.position, box) >= .95 - 1e-5, "whole package clears crew station radius " + good)
			if station.has("patrol"):
				for step in 11:
					var p: Vector3 = (station.position as Vector3).lerp(station.patrol, step / 10.0)
					check(rect_distance(p, box) >= .95 - 1e-5, "whole package clears live walk segment " + good)
		var support_heights: Array[float] = []
		for offset: Vector2 in [Vector2.ZERO, Vector2(-.475, -.475), Vector2(-.475, .475), Vector2(.475, -.475), Vector2(.475, .475)]:
			var support: Dictionary = deck.sample(local.x + offset.x, local.z + offset.y)
			if not check(not support.is_empty(), "all five footprint points have actual support " + good): continue
			check(support.normal.y >= .94, "cargo avoids steep support " + good)
			check(support.point.y <= deck.bounds.position.y + .65 + 1e-5, "cargo stays on main deck rather than roof " + good)
			support_heights.append(support.point.y)
		if not support_heights.is_empty(): check(support_heights.max() - support_heights.min() <= .15 + 1e-5, "footprint height spread is safe " + good)
		for other: AABB in occupied: check(not box.intersects(other), "reserved cargo volumes do not intersect " + good)
		occupied.append(box)
		var anchor: Dictionary = view.anchor(good)
		check(not anchor.is_empty() and (anchor.position as Vector3).is_equal_approx(model.global_transform * local), "world anchor follows actual source frame " + good)
	# Caller cannot mutate the accepted cargo or detached diagnostic structures.
	cargo.grain = 99999.0
	state.goods[0].quantity = 88888.0
	state.slots.clear()
	check(float(view.snapshot().manifest.grain) == 1.0 and view.snapshot().slots.size() == 12, "snapshots and input dictionaries are detached copies")
	var changed: Dictionary = view.snapshot().manifest
	changed.grain = 0.0; changed.tea = 81.0
	check(view.apply_manifest(changed, 6.0).get("ok", false), "zero and quantity change accepted")
	check(view.snapshot().goods.size() == 11 and view.anchor("grain").is_empty(), "zero quantity removes old visible package")
	for record: Dictionary in view.snapshot().goods:
		check((record.local_anchor as Vector3).is_equal_approx(anchors[record.good]), "other goods never shift slots after quantity changes " + record.good)
	var before_invalid: Dictionary = view.snapshot()
	for invalid: Dictionary in [{"grain": -1.0}, {"unknown": 3.0}, {"grain": NAN}, {"grain": "3"}]:
		check(not view.apply_manifest(invalid, 7.0).get("ok", true), "invalid/unsupported manifest rejected")
		check(view.snapshot() == before_invalid, "rejected manifest is atomic")
	check(not view.apply_manifest({"grain": 2.0}, INF).get("ok", true), "invalid accepted time rejected")
	check(view.snapshot() == before_invalid, "invalid time preserves full accepted state")
	check(not view.configure(model, "unsupported_ship").get("ok", true), "unknown ship kind cannot reinterpret the accepted deck")
	check(view.snapshot() == before_invalid, "invalid reconfiguration leaves current cargo untouched")
	var unsupported := Node3D.new()
	check(not view.configure(unsupported, "fuchuan").get("ok", true), "detached model is rejected before reading a global transform")
	root.add_child(unsupported)
	check(not view.configure(unsupported, "fuchuan").get("ok", true), "model without real support cannot fabricate cargo slots")
	check(view.snapshot() == before_invalid, "unsupported source configuration is atomic")
	unsupported.free()
	model.visible = false
	actor.position = Vector3(17, -2.5, -9)
	actor.rotation = Vector3(.07, .8, -.05)
	view.refresh_transform()
	check(view.global_transform.is_equal_approx(model.global_transform), "cargo copies actual translated tilted sinking ship frame once")
	for child: Node3D in view.get_children(): check(child.is_visible_in_tree(), "LOD0 hidden flag does not hide independent cargo")
	for record: Dictionary in view.snapshot().goods:
		check((record.world_anchor as Vector3).is_equal_approx(model.global_transform * record.local_anchor), "world anchor includes real sinking/roll transform")
	var after_deck := DeckSupport.new(); after_deck.configure("fuchuan", model)
	check(after_deck.stations == stations_before and after_deck._obstacles == obstacles_before, "cargo never removes crew stations or rewrites authored obstacles")
	for good: String in GOODS:
		var fresh: Node3D = provider.get_model(good)
		check(material_state(fresh) == material_before[good], "cargo projection never alters original alpha/PBR materials " + good)
		fresh.free()
	check(view.apply_manifest({}, 2.0).get("ok", false), "empty replay manifest accepted on rewind")
	check(view.snapshot().goods.is_empty() and view.get_child_count() == 0, "empty manifest clears every old package immediately")
	check(view.apply_manifest({"grain": 4.0}, 2.0).get("ok", false), "same accepted time may project a replaced authoritative manifest")
	view.dispose()
	check(view.snapshot().disposed and view.get_child_count() == 0 and view.anchor("grain").is_empty(), "dispose releases nodes and anchors")
	check(not view.apply_manifest({"grain": 1.0}, 9.0).get("ok", true), "disposed projection cannot respawn cargo")
	view.free(); actor.dispose(); actor.free()
	# Reference merchant support includes the keel and cabin in one source mesh.
	# Its bounds minimum is not a deck datum, unlike the authored fuchuan deck.
	var merchant := ShipView.new()
	root.add_child(merchant)
	if check(merchant.configure("merchant"), "actual reference merchant configures"):
		var merchant_model: Node3D = merchant.get_model()
		var merchant_deck := DeckSupport.new()
		check(merchant_deck.configure("merchant", merchant_model), "merchant has actual source support and crew stations")
		var merchant_stations: Array = merchant_deck.stations.duplicate(true)
		var merchant_view = view_script.new(); root.add_child(merchant_view)
		check(merchant_view.configure(merchant_model, "merchant").get("ok", false), "merchant cargo adapter accepts real source geometry")
		check(merchant_view.apply_manifest({"grain": 10}, 0.0).get("ok", false), "merchant grain manifest accepted")
		var merchant_state: Dictionary = merchant_view.snapshot()
		check(merchant_state.goods.size() == 1 and merchant_state.overflow_goods.is_empty(), "real merchant main deck shows loaded grain despite submerged support bounds minimum")
		var all_goods: Dictionary = {}
		for good: String in GOODS: all_goods[good] = 10
		check(merchant_view.apply_manifest(all_goods, 1.0).get("complete", false), "measured merchant layout supports all twelve actual cargo types")
		merchant_state = merchant_view.snapshot()
		check(merchant_state.available_slots == 12 and merchant_state.goods.size() == 12 and merchant_state.overflow_goods.is_empty(), "merchant has twelve safe fixed slots without hidden overflow")
		var band: Dictionary = merchant_state.get("main_deck_band", {})
		check(band.get("method", "") == "dominant_exposed_surface_band" and float(band.get("low", -100.0)) > 1.8 and float(band.get("high", 100.0)) < 3.0, "merchant primary deck is measured from exposed support, not keel or upper roofs")
		var library := Library.new()
		var sailor: Node3D = library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
		var rest: AABB = merchant_deck._bounds(sailor, sailor)
		var occupied_merchant: Array[AABB] = []
		for record: Dictionary in merchant_state.goods:
			var bounds: AABB = record.slot_bounds
			var point: Vector3 = record.local_anchor
			check(bounds.size.is_equal_approx(Vector3(.95,1.1,.95)*(.5/.72)), "merchant uses measured half-metre package proportion " + record.good)
			check(bounds.end.x <= -.7 or bounds.position.x >= .7, "merchant retains the complete central walkway " + record.good)
			for obstacle: AABB in merchant_deck._obstacles: check(not bounds.intersects(obstacle.grow(.1)), "merchant package clears real cannon and mast obstacle " + record.good)
			for station: Dictionary in merchant_stations:
				check(rect_distance(station.position,bounds) >= .65-1e-5, "merchant retains measured worker clearance " + record.good)
				var basis := Basis(Quaternion(Vector3.UP,station.normal))*Basis(Vector3.UP,station.heading)
				var actor_box: AABB = Transform3D(basis,station.position)*rest.grow(.05)
				if station.has("patrol"):
					actor_box=actor_box.merge(AABB(actor_box.position+(station.patrol-station.position),actor_box.size))
					for step in 11:
						check(rect_distance((station.position as Vector3).lerp(station.patrol,step/10.0),bounds) >= .65-1e-5,"merchant package clears full worker walk segment")
				check(not bounds.intersects(actor_box), "merchant package clears original sailor rest mesh plus five centimetres " + record.good)
			var heights: Array[float]=[]
			for offset: Vector2 in [Vector2.ZERO,Vector2(-bounds.size.x*.5,-bounds.size.z*.5),Vector2(-bounds.size.x*.5,bounds.size.z*.5),Vector2(bounds.size.x*.5,-bounds.size.z*.5),Vector2(bounds.size.x*.5,bounds.size.z*.5)]:
				var support: Dictionary=merchant_deck.sample(point.x+offset.x,point.z+offset.y)
				if not check(not support.is_empty(),"merchant five-point footprint has real support"):continue
				check(support.normal.y >= .94 and support.point.y >= float(band.get("low",INF))-1e-5 and support.point.y <= float(band.get("high",-INF))+1e-5,"merchant footprint stays inside measured lower main deck band")
				heights.append(support.point.y)
			if not heights.is_empty():check(heights.max()-heights.min()<=.15+1e-5,"merchant footprint does not bridge a stair or unsupported slope")
			for old: AABB in occupied_merchant:check(not old.intersects(bounds),"merchant cargo packages do not intersect")
			occupied_merchant.append(bounds)
		for node: Node3D in merchant_view.get_children():check(node.scale.is_equal_approx(Vector3.ONE*.5),"merchant model keeps its original proportions at the probed package scale")
		sailor.free();library.dispose()
		check(merchant_deck.stations == merchant_stations, "merchant cargo does not remove crew to create space")
		merchant_view.dispose(); merchant_view.free()
	merchant.dispose(); merchant.free()
	await process_frame
	finish()
