extends SceneTree
## Original x86 fixtures constrain the placement table and nearest-even color
## stream. Integration fixtures also keep real tree anchors out of the sea and
## retained harbor buildings; rendering is checked separately by native capture.
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", message)
func _initialize() -> void: _run.call_deferred()
func load_json(path: String) -> Dictionary:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}
func flat_ground(_x: float, _z: float) -> float: return 8.0
func submerged(_x: float, _z: float) -> float: return -2.0
func _run() -> void:
	var mesh_path := "res://modules/scene_engine/fidelity_island/mesh_asset.gd"
	var path := "res://modules/scene_engine/fidelity_island/vegetation.gd"
	var mesh_script = load(mesh_path) if ResourceLoader.exists(mesh_path) else null
	var script = load(path) if ResourceLoader.exists(path) else null
	var valid_scripts: bool = mesh_script != null and script != null and mesh_script.can_instantiate() and script.can_instantiate()
	check(valid_scripts, "original native vegetation module exists and compiles")
	if not valid_scripts:
		print("FIDELITY_ISLAND_VEGETATION_COMPLETE assertions=%d failures=%d" % [assertions,failures])
		quit(1)
		return
	if mesh_script and script:
		var base := "res://assets/data/fidelity_island/"
		var source := load_json(base + "vegetation-original.json")
		var tables := load_json(base + "canopy-native-fixtures.json")
		var packing := load_json(base + "geometry-color-native-fixtures.json")
		var terrain := load_json(base + "terrain-scene.json")
		check(not source.is_empty() and not terrain.is_empty(), "immutable original assets and terrain metadata load")
		if not source.is_empty() and not terrain.is_empty():
			for fixture: Dictionary in tables.get("cases", []):
				var actual: Dictionary = script.canopy_table(source, terrain.get("metadata",terrain), int(fixture.column), int(fixture.row))
				var expected := PackedFloat32Array(fixture.data)
				check(actual.data.to_byte_array() == expected.to_byte_array(), "original 4E9950 CxD table is byte exact at %d,%d" % [fixture.column, fixture.row])
			var canopy: Dictionary = source.assets[1].meshes[0]
			var expected_argb: Array = packing.canopy.packed_argb
			for i in canopy.colors.size():
				check(mesh_script.pack_geometry_color_argb(canopy.colors[i]) == int(expected_argb[i]), "authored canopy color agrees with original full 5C5860 execution %d" % i)
			var boundaries: Dictionary = packing.get("boundaries", {})
			for index in boundaries.get("rgba", []).size():
				check(mesh_script.pack_geometry_color_argb(boundaries.rgba[index]) == int(boundaries.packed_argb[index]), "half-boundary nearest-even Geometry packing")
			var plants = script.new(); root.add_child(plants)
			var untouched := Node3D.new(); plants.add_child(untouched)
			check(plants.configure({}, Callable(), {"mode":"exact"}), "exact viewer accepts source-native coordinates without a fabricated ground sampler")
			var exact: Dictionary = plants.diagnostics()
			for child: Node in plants.get_children():
				if not child is MeshInstance3D: continue
				var native_mesh: ArrayMesh = child.mesh
				check(native_mesh.get_surface_count() == 1, "every owned original vegetation mesh has a real accepted native surface")
				if native_mesh.get_surface_count() == 1:
					var arrays := native_mesh.surface_get_arrays(0)
					var is_palm: bool = String(child.name).contains("palm")
					check(arrays[Mesh.ARRAY_VERTEX].size() == (1612 if is_palm else 3312), "native buffer contains every original vertex")
					check(arrays[Mesh.ARRAY_INDEX].size() == (3138 if is_palm else 10557), "native buffer contains every original triangle")
			check(exact.palm_vertices == 1612 and exact.palm_triangles == 1046, "original palm geometry retains all authored vertices and valid triangles")
			check(exact.canopy_vertices == 3312 and exact.canopy_triangles == 3519, "original CanopyFINAL_4x geometry remains intact")
			check(exact.canopy_patch_count == 3, "all three mask-positive native patches are displayed")
			check(exact.camera_pool_restored == false, "diagnostics do not claim original camera pool scheduling")
			plants.apply_snapshot({"time":0.0,"focus":Vector2.ZERO})
			check(plants.diagnostics().simulation_time == 0.0, "explicit simulation zero is accepted")
			var profile := {"id":"cat_island", "sourceCenter":Vector2(60,70), "sourceOutward":Vector2.DOWN, "islandCenter":Vector2.ZERO, "inward":Vector2.LEFT, "scale":5.0, "width":120,"height":140}
			check(plants.configure([profile], flat_ground, {"mode":"mapped"}), "formal profile mapping uses authoritative terrain")
			var mapped: Dictionary = plants.diagnostics()
			# Native table/color fixtures independently yield 9+5+19 canopy trees;
			# the merged original palm mesh has 24 connected authored trunks.
			check(mapped.accepted_tree_count == 57, "all 33 native mask-visible canopy trees and 24 real palm groups survive on dry terrain")
			for anchor: Dictionary in mapped.anchors:
				check(absf(anchor.position.y - 8.0) < 0.001, "whole original tree root is reanchored to sampled terrain")
			var site := {"position":Vector3.ZERO,"radius":2000.0}
			check(plants.configure([profile], flat_ground, {"mode":"mapped","existing_buildings":[site]}), "existing harbor geometry participates in planting exclusion")
			check(plants.diagnostics().accepted_tree_count == 0, "a building footprint excludes every overlapping actual tree")
			check(plants.configure([profile], submerged, {"mode":"mapped"}), "submerged terrain is valid geography")
			check(plants.diagnostics().accepted_tree_count == 0, "original layout never plants live trees into sea floor")
			var before: Dictionary = plants.diagnostics()
			check(not plants.configure([profile], Callable(), {"mode":"mapped"}), "mapping without authoritative ground is rejected")
			check(plants.diagnostics() == before, "invalid configure does not destroy an accepted scene")
			plants.dispose(); plants.dispose()
			check(is_instance_valid(untouched) and untouched.get_parent() == plants, "dispose preserves caller-owned nodes")
			check(plants.diagnostics().owned_nodes == 0, "dispose releases only owned vegetation nodes")
			plants.queue_free()
	print("FIDELITY_ISLAND_VEGETATION_COMPLETE assertions=%d failures=%d" % [assertions,failures])
	quit(0 if failures == 0 else 1)
