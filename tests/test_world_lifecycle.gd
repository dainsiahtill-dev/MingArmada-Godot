extends SceneTree

var failures: Array[String] = []
var assertions := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var terrain_script = load("res://modules/scene_engine/terrain/height_field.gd") if FileAccess.file_exists("res://modules/scene_engine/terrain/height_field.gd") else null
	var world_script = load("res://modules/scene_engine/world/world_view.gd") if FileAccess.file_exists("res://modules/scene_engine/world/world_view.gd") else null
	var ship_script = load("res://game/presentation/ships/ship_view.gd") if FileAccess.file_exists("res://game/presentation/ships/ship_view.gd") else null
	check(terrain_script != null, "native injected HeightField is required")
	check(world_script != null, "native owned WorldView is required")
	check(ship_script != null, "original GLB ShipView is required")
	if terrain_script and world_script and ship_script:
		var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/reference/mingqi-geography.json"))
		var field = terrain_script.new()
		field.configure_ports(fixture.ports)
		for sample: Dictionary in fixture.samples:
			check(absf(field.sample_height(sample.x, sample.z) - sample.height) < 1.0e-10, "original JS terrain golden at %s,%s" % [sample.x, sample.z])
		check(is_nan(field.sample_height(NAN, 0.0)), "invalid coordinates rejected without fabricated height")
		var viewport := SubViewport.new()
		viewport.size = Vector2i(640, 480)
		root.add_child(viewport)
		var camera := Camera3D.new()
		viewport.add_child(camera)
		camera.position = Vector3(0, 50, 150)
		camera.look_at(Vector3.ZERO)
		var world = world_script.new()
		viewport.add_child(world)
		var unrelated := Node3D.new()
		world.add_child(unrelated)
		var options := {"camera": camera, "ports": fixture.ports, "chunk_radius": 1, "resolution": 12, "vegetation": false}
		world.configure(field.sample_height, [], options)
		var maximum_wave := 0.0
		for component: Array in preload("res://modules/contracts/wave_descriptor.gd").ORIGINAL_COMPONENTS: maximum_wave += absf(component[0])
		for pier: MeshInstance3D in world.find_children("PierDeck", "MeshInstance3D", true, false):
			check(pier.position.y - pier.mesh.size.y * 0.5 > maximum_wave, "native pier stays above the original offshore wave envelope")
		check(world.get_chunk_count() == 9, "bounded window has nine chunks")
		var terrain = world.get_chunks()[0]
		var beach_start: Color = terrain.get_biome_color(2.0)
		var beach_end: Color = terrain.get_biome_color(10.0)
		var beach_middle: Color = terrain.get_biome_color(6.0)
		check(beach_middle.is_equal_approx(beach_start.lerp(beach_end, 0.5)), "original smoothstep height colors must interpolate, not create bands")
		var builds: int = world.get_chunk_build_count()
		world.apply_snapshot({"time": 4.25, "focus": {"x": 0, "z": 0}}, 1.0 / 60.0)
		world.apply_snapshot({"time": 4.25, "focus": {"x": 0, "z": 0}}, 0.0)
		check(world.get_chunk_build_count() == builds, "same window must not rebuild expensive terrain")
		check(world.get_ocean().material_override.get_shader_parameter("simulation_time") == 4.25, "paused consumed time does not advance water")
		for chunk in world.get_chunks():
			var arrays: Array = chunk.mesh.surface_get_arrays(0)
			for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
				var point: Vector3 = vertex + chunk.position
				check(absf(point.y - field.sample_height(point.x, point.z)) < 2.0e-5, "rendered vertices use authoritative height sampler")
			check(chunk.get_collision_body() != null, "same rendered mesh supplies owned collision")
		world.apply_snapshot({"time": 4.25, "focus": {"x": 1000, "z": 0}}, 0.0)
		check(world.get_chunk_count() == 9, "moving window cannot grow unbounded")
		world.dispose()
		world.dispose()
		check(is_instance_valid(unrelated) and unrelated.get_parent() == world, "dispose preserves nodes owned by caller")
		check(world.get_chunk_count() == 0, "dispose clears owned terrain")
		world.configure(field.sample_height, [], options)
		check(world.get_chunk_count() == 9, "disposed world can be configured again without remnants")
		world.dispose()
		var ship = ship_script.new()
		viewport.add_child(ship)
		check(ship.configure("fuchuan"), "ship loads original GLB")
		for heading: float in [0.0, PI / 2.0, PI, -PI / 2.0]:
			ship.apply_snapshot({"visual": {"position": {"x": 3, "y": 2, "z": 5}, "heading": heading, "pitch": 0.1, "heel": 0.2, "velocity": {"x": 0, "z": 0}}, "sailDeployment": 0.25, "sailAngle": 0.3, "sail": 100, "maxSail": 100, "rudder": 0.5}, {"speed": 9, "direction": {"x": 1, "y": 0}}, 0.0)
			check(ship.position == Vector3(3, 2, 5), "visual position stays meter exact")
			check(absf(ship.rotation.x + 0.1) < 1.0e-6 and absf(ship.rotation.y - (PI / 2.0 - heading)) < 1.0e-6 and absf(ship.rotation.z - 0.2) < 1.0e-6, "native pose preserves original heading/pitch/heel")
		var model = ship.get_model()
		var rudder = model.find_child("rudder_pivot", true, false)
		check(rudder != null and absf(rudder.rotation.y - 0.21) < 1.0e-6, "original rudder receives normalized steering")
		for mesh_node in model.find_children("*", "MeshInstance3D", true, false):
			if String(mesh_node.name).begins_with("sail_"):
				check(absf(mesh_node.get_blend_shape_value(0) - 0.75) < 1.0e-6, "real sail furl morph follows deployment")
		var first_barrel = model.find_child("barrel_port_01", true, false)
		var second_barrel = model.find_child("barrel_port_02", true, false)
		var socket = model.find_child("socket_smoke_port_01", true, false)
		check(first_barrel != null and second_barrel != null and socket != null, "original cannon recoil and smoke sockets are retained")
		if first_barrel and second_barrel and socket:
			var first_rest: float = first_barrel.position.z
			var second_rest: float = second_barrel.position.z
			var snapshot := {"id": "test-vessel", "visual": {"position": {"x": 3, "y": 2, "z": 5}, "heading": 0, "pitch": 0, "heel": 0}}
			ship.apply_snapshot(snapshot, {}, 0.0)
			var fire_point: Vector3 = socket.global_position
			ship.apply_events([{"type": "fire", "id": "fire-01", "shipId": "test-vessel", "side": "port", "position": {"x": fire_point.x, "y": fire_point.y, "z": fire_point.z}}])
			check(absf(first_barrel.position.z - (first_rest - 0.6)) < 1.0e-6, "real fire chooses nearest authored cannon and recoils by original 0.6m")
			check(absf(second_barrel.position.z - second_rest) < 1.0e-6, "one actual fire event must not recoil every gun")
			ship.apply_snapshot(snapshot, {}, 0.1)
			var after_decay: float = first_barrel.position.z
			check(absf(after_decay - (first_rest - 0.6 * exp(-0.9))) < 1.0e-6, "recoil decays using original consumed-delta exponential")
			ship.apply_snapshot(snapshot, {}, 0.0)
			check(first_barrel.position.z == after_decay, "pause cannot advance cannon recoil")
			ship.apply_events([{"type": "fire", "id": "fire-01", "shipId": "test-vessel", "side": "port"}])
			check(first_barrel.position.z == after_decay, "replayed event cannot recoil the gun twice")
		ship.set_lod_distance(300.0)
		check(ship.get_lod() == 1, "original middle LOD activates at 220m")
		ship.set_lod_distance(800.0)
		check(ship.get_lod() == 2, "original distant LOD activates at 650m")
		ship.dispose()
		ship.dispose()
		check(ship.get_model() == null, "ship dispose releases owned models")
		viewport.free()
	for message in failures:
		printerr("FAIL: ", message)
	print("WORLD_LIFECYCLE_TESTS assertions=", assertions, " failures=", failures.size())
	quit(0 if failures.is_empty() else 1)
