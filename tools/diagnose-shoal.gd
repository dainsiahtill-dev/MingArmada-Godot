extends SceneTree

const Heights = preload("res://modules/scene_engine/terrain/height_field.gd")
const Waves = preload("res://modules/physics_engine/ocean/wave_field.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/water-probe-terrain.json"))
	var field := Heights.new()
	field.configure_ports(fixture.ports)
	var waves := Waves.new()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600, 900)
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.fov = 55.0
	camera.position = Vector3(-173.6819, 26.3417, -114.7917)
	camera.look_at(Vector3(-206.6819, 2.3417, -75.7917))
	for screen: Vector2 in [Vector2(100, 450), Vector2(180, 500), Vector2(100, 650)]:
		var ray := camera.project_ray_normal(screen)
		var distance := (-2.4 - camera.position.y) / ray.y
		var point := camera.position + ray * distance
		var height := field.sample_height(point.x, point.z)
		print("SHOAL_DIAGNOSTIC screen=", screen, " world=", point, " terrain=", height, " water=", waves.sample(point.x, point.z, 10.0).height)
	viewport.free()
	quit()
