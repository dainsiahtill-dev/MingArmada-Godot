extends SceneTree
## Model-local fire anchors: actual deck triangles, detached copies, no world ownership.
const ANCHORS_PATH: String = "res://game/research/demos/ship_fire_zone_anchors.gd"
const DeckSupport = preload("res://game/presentation/crew/deck_stations.gd")
const ShipView = preload("res://game/presentation/ships/ship_view.gd")
const ZONES: Array[String] = ["bow", "mid", "stern"]
var assertions: int = 0
var failures: int = 0
var _anchors_script: Script

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ", reason)
	return value

func _finish() -> void:
	print("SHIP_FIRE_ZONE_ANCHORS_TEST_COMPLETE assertions=%d failures=%d" % [assertions, failures])
	quit(0 if failures == 0 else 1)

func _surface(label: String, x0: float, x1: float, z0: float, z1: float, y: float) -> MeshInstance3D:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(x0, y, z0), Vector3(x1, y, z0), Vector3(x0, y, z1), Vector3(x1, y, z1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 2, 1, 1, 2, 3])
	var mesh: ArrayMesh = ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var surface: MeshInstance3D = MeshInstance3D.new()
	surface.name = label
	surface.mesh = mesh
	surface.set_meta("deck_support", true)
	return surface

func _fixture(center_gap: bool = false, missing_mid: bool = false) -> Node3D:
	var model: Node3D = Node3D.new()
	model.set_meta("source_family", "fire_anchor_authored_fixture")
	# Explicit source support avoids the legacy decorative deck-height adjustment.
	if not center_gap and not missing_mid:
		model.add_child(_surface("MainDeck", -4.0, 4.0, -9.0, 9.0, 2.0))
	else:
		model.add_child(_surface("BowDeck", -4.0, 4.0, 3.0, 9.0, 2.0))
		model.add_child(_surface("SternLowerDeck", -4.0, 4.0, -9.0, -3.0, 2.0))
	if center_gap:
		model.add_child(_surface("MidPortDeck", -4.0, -1.0, -3.0, 3.0, 3.0))
		model.add_child(_surface("MidStarboardDeck", 1.0, 4.0, -3.0, 3.0, 3.0))
	elif not missing_mid:
		model.add_child(_surface("RaisedMidDeck", -4.0, 4.0, -3.0, 3.0, 3.0))
	model.add_child(_surface("RaisedSternDeck", -4.0, 4.0, -9.0, -3.0, 5.0))
	return model

func _run() -> void:
	var available: bool = ResourceLoader.exists(ANCHORS_PATH)
	check(available, "FIRE_ZONE_ANCHORS_MISSING: real-deck zone helper must exist")
	if not available:
		_finish()
		return
	_anchors_script = load(ANCHORS_PATH)
	if not check(_anchors_script != null, "zone helper script loads"):
		_finish()
		return
	_test_real_triangle_heights_and_local_frame()
	_test_supported_deck_without_crew_stations()
	_test_hole_search_stays_inside_zone()
	_test_failure_clears_old_support()
	_test_detached_values_and_clear()
	_test_actual_fuchuan()
	_finish()

func _test_real_triangle_heights_and_local_frame() -> void:
	var model: Node3D = _fixture()
	model.transform = Transform3D(Basis.from_euler(Vector3(0.17, 0.68, -0.23)).scaled(Vector3(1.2, 0.8, 1.4)), Vector3(23.0, -11.0, 47.0))
	var helper: Variant = _anchors_script.new()
	check(helper.sample("bow").is_empty(), "unconfigured helper cannot invent support")
	var receipt: Dictionary = helper.configure("fuchuan", model)
	if check(receipt.get("ok", false) and receipt.get("reason", "missing") == "", "detached authored support configures without reading a world transform"):
		var expected: Dictionary = {"bow": Vector3(0.0, 2.0, 6.0), "mid": Vector3(0.0, 3.0, 0.0), "stern": Vector3(0.0, 5.0, -6.0)}
		for zone: String in ZONES:
			var anchor: Dictionary = helper.sample(zone)
			if not check(anchor.get("point") is Vector3 and anchor.get("normal") is Vector3, zone + " exposes typed local point and normal"):
				continue
			check(anchor.get("zone", "") == zone and anchor.point.distance_to(expected[zone]) < 0.0001, zone + " independently samples actual highest deck at its own longitudinal target")
			check(anchor.normal.distance_to(Vector3.UP) < 0.0001, zone + " normal faces above local deck")
		var diagnostic: Dictionary = helper.diagnostics()
		check(diagnostic.get("ready", false) and int(diagnostic.get("triangle_count", 0)) == 6, "diagnostics retain actual submitted deck triangle count")
		check(diagnostic.get("bounds") is Dictionary and diagnostic.get("anchors") is Dictionary, "bounds and anchors are serializable diagnostic values")
		var serialized: Variant = JSON.parse_string(JSON.stringify(diagnostic))
		check(serialized is Dictionary and serialized.get("anchors", {}).get("stern", {}).get("point") is Dictionary, "anchor diagnostics preserve numeric point components through JSON")
	check(helper.sample("unknown").is_empty(), "unknown zone cannot alias a supported region")
	model.free()

func _test_supported_deck_without_crew_stations() -> void:
	for narrow: bool in [false, true]:
		var model: Node3D = _fixture()
		for child: Node3D in model.get_children():
			child.position.z += 100.0
			if narrow: child.scale.x = 0.02
		var deck: RefCounted = DeckSupport.new()
		check(not deck.configure("fuchuan", model) and not deck.faces.is_empty(), "offset deck has triangles but no crew stations")
		var helper: Variant = _anchors_script.new()
		if check(helper.configure("fuchuan", model).get("ok", false), "fire support does not require crew stations; narrow=" + str(narrow)):
			for zone: String in ZONES:
				var anchor: Dictionary = helper.sample(zone)
				check(not anchor.is_empty() and anchor.point.z > 90.0 and anchor.point.z < 110.0, "offset " + zone + " anchor follows actual bounds")
		model.free()

func _test_hole_search_stays_inside_zone() -> void:
	var model: Node3D = _fixture(true)
	var helper: Variant = _anchors_script.new()
	var receipt: Dictionary = helper.configure("fuchuan", model)
	if check(receipt.get("ok", false), "zone with center hole searches actual nearby support"):
		var anchor: Dictionary = helper.sample("mid")
		if check(anchor.get("point") is Vector3, "center-hole search returns real mid deck point"):
			var point: Vector3 = anchor.point
			check(absf(point.x) >= 1.0 and absf(point.x) <= 4.0 and absf(point.z) < 3.0 and absf(point.y - 3.0) < 0.0001, "nearby search stays in mid partition and never borrows bow or stern height")
		var repeated: Variant = _anchors_script.new()
		check(repeated.configure("fuchuan", model).get("ok", false) and repeated.diagnostics() == helper.diagnostics(), "hole resolution deterministic for same submitted geometry")
	model.free()

func _test_failure_clears_old_support() -> void:
	var helper: Variant = _anchors_script.new()
	var accepted: Node3D = _fixture()
	check(helper.configure("fuchuan", accepted).get("ok", false), "failure fixture begins with supported anchors")
	var unsupported: Node3D = _fixture(false, true)
	var receipt: Dictionary = helper.configure("fuchuan", unsupported)
	check(not receipt.get("ok", true) and not str(receipt.get("reason", "")).is_empty(), "entire unsupported mid partition rejects configuration explicitly")
	check(not helper.diagnostics().get("ready", true) and helper.sample("bow").is_empty() and helper.sample("stern").is_empty(), "rejected replacement clears every old anchor")
	check(int(helper.diagnostics().get("triangle_count", -1)) == 0 and helper.diagnostics().get("anchors", {"old":true}).is_empty(), "failed replacement cannot expose stale geometry diagnostics")
	check(not helper.configure("unknown", accepted).get("ok", true), "unsupported kind rejected")
	check(not helper.configure("fuchuan", null).get("ok", true), "missing model rejected")
	var deckless: Node3D = Node3D.new()
	check(not helper.configure("fuchuan", deckless).get("ok", true), "deckless model cannot produce fabricated anchors")
	accepted.free()
	unsupported.free()
	deckless.free()

func _test_detached_values_and_clear() -> void:
	var helper: Variant = _anchors_script.new()
	var model: Node3D = _fixture()
	if check(helper.configure("fuchuan", model).get("ok", false), "detachment fixture configures"):
		var before: Dictionary = helper.sample("stern")
		var diagnostic: Dictionary = helper.diagnostics()
		var returned: Dictionary = helper.sample("stern")
		returned.point = Vector3(900.0, 900.0, 900.0)
		returned.zone = "corrupt"
		var external_diagnostic: Dictionary = helper.diagnostics()
		external_diagnostic.anchors.clear()
		check(helper.sample("stern") == before and helper.diagnostics() == diagnostic, "mutating returned values cannot poison retained support")
		for child: Node3D in model.get_children():
			child.position.y += 50.0
		model.transform = Transform3D(Basis.from_euler(Vector3(0.3, 1.1, -0.6)), Vector3(-80.0, 20.0, 12.0))
		model.free()
		check(helper.sample("stern") == before and helper.diagnostics() == diagnostic, "source mutation and lifetime do not affect copied model-local anchors")
	else:
		model.free()
	helper.clear()
	helper.clear()
	check(not helper.diagnostics().get("ready", true) and helper.diagnostics().get("anchors", {"old":true}).is_empty() and int(helper.diagnostics().get("triangle_count", -1)) == 0, "clear is repeatable and removes all retained support")
	for zone: String in ZONES:
		check(helper.sample(zone).is_empty(), "clear removes " + zone + " sampling")

func _test_actual_fuchuan() -> void:
	var actor: Node3D = ShipView.new()
	root.add_child(actor)
	if not check(actor.configure("fuchuan"), "actual ShipView fuchuan configures"):
		actor.free()
		return
	var model: Node3D = actor.source_deck_model()
	var deck: RefCounted = DeckSupport.new()
	if not check(model != null and deck.configure("fuchuan", model), "production model supplies actual deck support"):
		actor.dispose()
		actor.free()
		return
	var helper: Variant = _anchors_script.new()
	if check(helper.configure("fuchuan", model).get("ok", false), "actual fuchuan resolves all three fire regions"):
		var previous_z: float = INF
		var partition_length: float = deck.bounds.size.z / 3.0
		var centers: Dictionary = {"bow": deck.bounds.get_center().z + partition_length, "mid": deck.bounds.get_center().z, "stern": deck.bounds.get_center().z - partition_length}
		for zone: String in ZONES:
			var anchor: Dictionary = helper.sample(zone)
			if not check(anchor.get("point") is Vector3 and anchor.get("normal") is Vector3, "real " + zone + " anchor contains supported local vectors"):
				continue
			var point: Vector3 = anchor.point
			var normal: Vector3 = anchor.normal
			check(point.is_finite() and normal.is_finite() and point.y > 0.05 and normal.y >= 0.5, "real " + zone + " anchor finite and above native waterline")
			check(point.z < previous_z and absf(point.z - float(centers[zone])) < partition_length * 0.5, "real " + zone + " lies in its separate actual-bounds partition")
			previous_z = point.z
			var support: Dictionary = deck.sample(point.x, point.z)
			check(not support.is_empty() and point.distance_to(support.point) < 0.0001 and normal.distance_to(support.normal) < 0.0001, "real " + zone + " agrees with independent actual deck resample")
	actor.dispose()
	actor.free()
