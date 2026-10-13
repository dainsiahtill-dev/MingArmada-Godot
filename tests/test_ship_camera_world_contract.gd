extends SceneTree
## Real Sea/Camera ownership with injected terrain, imported ship and native
## Encounter. Camera-only updates intentionally do not replay world presentation.
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
var assertions := 0
var failures := 0
var _ground := -80.0
var _custom_calls := 0
const CUSTOM_EYE := Vector3(14.0,180.0,-22.0)

func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL camera world: ",detail)
	return ok

func _height(_x: float, _z: float) -> float: return _ground
func _water(_x: float, _z: float, _seconds: float) -> float: return 0.0

func _encounter(epoch: String, kind: String = "fisherman") -> RefCounted:
	var native := Encounter.new({"mode":"continuous","battleId":epoch,"playerId":"player",
		"controllableShipIds":["player"],"sampleTerrainHeight":_height,"oceanWaves":[],
		"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},
		"ships":[{"id":"player","kind":kind,"team":"player","crew":4,
			"position":{"x":100.0,"z":-30.0},"heading":0.0,"sailDeployment":0.0}]})
	check(native.last_error.is_empty(), "actual continuous Encounter configures one healthy native ship")
	native.step(0.1)
	return native

func _button(index: MouseButton, pressed: bool = true) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index; event.pressed = pressed; event.factor = 1.0
	return event

func _motion() -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(120.0,-30.0)
	event.button_mask = MOUSE_BUTTON_MASK_RIGHT
	return event

func _clocks(view: Node3D) -> Dictionary:
	var world: Node3D = view.get("world")
	var ocean: MeshInstance3D = world.call("get_ocean")
	var effects: Node3D = view.get("effects")
	var wakes: Node3D = view.get("wakes")
	var atmosphere: RefCounted = world.get("atmosphere")
	var weather: Dictionary = atmosphere.call("diagnostics") if atmosphere else {}
	return {"world":world.get("_simulation_time"),"ocean":ocean.get("_simulation_time"),
		"shader":(ocean.material_override as ShaderMaterial).get_shader_parameter("simulation_time"),
		"effects":effects.get("_time"),"wake":wakes.get("_time"),
		"weather":weather.get("time"),"weatherAnimation":weather.get("animationTime"),
		"worldTransform":world.global_transform,"oceanTransform":ocean.global_transform,
		"effectTransform":effects.global_transform,"terrainBuilds":world.call("get_chunk_build_count")}

func _render_input(view: Node3D, native: Dictionary) -> void:
	# Let the production input clock receive real frame intervals. No artificial
	# native delta, sleep, repeated world render or timestamp mutation is needed.
	for frame in 4:
		await process_frame
		view.call("_update_camera",native,0.0)

func _drive_custom(view: Node3D) -> void:
	_custom_calls += 1
	var camera: Camera3D = view.get("camera")
	camera.position = CUSTOM_EYE
	camera.look_at(Vector3(100.0,3.0,-30.0),Vector3.UP)

func _run() -> void:
	root.size = Vector2i(640,360)
	var encounter := _encounter("camera-world-a")
	var native: Dictionary = encounter.snapshot()
	var original := native.duplicate(true)
	var view := Sea.new()
	root.add_child(view)
	view.apply_settings({"quality":"low","cameraShake":0.0})
	if not check(view.configure(_height,[],_water,native,{"resolution":8,"ocean_resolution":8,"chunk_radius":0,"vegetation":false}),
		"real minimal Sea composes actual ocean, one imported vessel and deck crew"):
		view.free(); _finish(); return
	if not check(view.has_method("handle_camera_input") and view.has_method("camera_status"), "actual Sea exposes observer input and status"):
		view.free(); _finish(); return
	check(native.time > 0.0 and view.ships.size() == 1 and view.sailors.size() == 1,
		"fixture owns one live imported ship at nonzero accepted native time")
	var camera: Camera3D = view.camera
	var clocks := _clocks(view)
	check(clocks.world == native.time and clocks.ocean == native.time and clocks.effects == native.time,
		"world, ocean and combat clocks start at the same accepted native time")
	var initial := camera.global_transform
	var initial_radius: float = view.camera_status().radius
	for repeat in 3: view.call("_update_camera",native,0.0)
	check(camera.global_transform == initial and _clocks(view) == clocks,
		"zero-delta observation without input keeps the exact Camera transform and world clocks")

	check(view.handle_camera_input(_button(MOUSE_BUTTON_WHEEL_UP)), "actual paused Sea accepts wheel zoom")
	await _render_input(view,native)
	check(camera.global_transform != initial and float(view.camera_status().radius) < initial_radius,
		"paused wheel intent moves the actual Camera through its input clock")
	check(_clocks(view) == clocks and native == original and encounter.snapshot() == original and view.get("_snapshot") == original,
		"wheel observation changes no native authority, stored snapshot or world/effects time")
	var before_orbit := camera.global_transform
	check(view.handle_camera_input(_button(MOUSE_BUTTON_RIGHT)) and view.handle_camera_input(_motion()),
		"actual Sea accepts RMB drag and orbit motion")
	await _render_input(view,native)
	check(view.camera_status().manual and view.camera_status().dragging and camera.global_basis != before_orbit.basis,
		"paused orbit rotates the actual Camera and retains manual world orientation")
	check(_clocks(view) == clocks and native == original and encounter.snapshot() == original,
		"orbit input leaves native state and all presented world clocks frozen")

	var next_encounter := _encounter("camera-world-b")
	var next: Dictionary = next_encounter.snapshot()
	view.apply_snapshot(next,[],0.0)
	check(not view.camera_status().manual and not view.camera_status().dragging and view.zoom == 1.0,
		"new native epoch cancels dragging, manual orbit and wheel zoom ownership")
	var reset_frame := camera.global_transform
	await process_frame
	view.call("_update_camera",next,0.0)
	check(camera.global_transform == reset_frame, "new epoch without explicit input remains exactly frozen at zero delta")
	check(view.handle_camera_input(_button(MOUSE_BUTTON_RIGHT)) and view.handle_camera_input(_motion()),
		"kind replacement fixture first obtains manual camera ownership")
	var old_ship: WeakRef = weakref(view.ships.player)
	var changed_encounter := _encounter("camera-world-b","fuchuan")
	var changed: Dictionary = changed_encounter.snapshot()
	view.apply_snapshot(changed,[],0.0)
	check(old_ship.get_ref() == null and view.ships.player.get("_kind") == "fuchuan",
		"same-id kind replacement uses the new actual imported ship")
	check(not view.camera_status().manual and not view.camera_status().dragging and view.zoom == 1.0,
		"same-id new ship kind clears old manual camera and drag ownership")

	var before_land := camera.global_position
	var terrain_clocks := _clocks(view)
	_ground = 120.0
	view.call("_update_camera",changed,0.0)
	check(camera.global_position.y >= _height(camera.global_position.x,camera.global_position.z)+4.0 and camera.global_position.y > before_land.y,
		"actual Camera stays four metres above a newly raised terrain sample while paused")
	check(_clocks(view) == terrain_clocks and changed_encounter.snapshot() == changed,
		"terrain safety correction advances neither native authority nor world/effects clocks")
	var safe_transform := camera.global_transform
	view.call("_update_camera",changed,0.0)
	check(camera.global_transform == safe_transform, "unchanged terrain safety and zero-delta inputs preserve exact Camera transform")

	check(view.handle_camera_input(_button(MOUSE_BUTTON_RIGHT)), "custom-controller fixture starts with an active drag")
	view.set_camera_controller(_drive_custom.bind(view))
	check(not view.camera_status().dragging, "installing an external camera controller cancels Rig dragging")
	var external_status: Dictionary = view.camera_status()
	check(not view.handle_camera_input(_button(MOUSE_BUTTON_RIGHT)) and not view.handle_camera_input(_motion()) and not view.handle_camera_input(_button(MOUSE_BUTTON_WHEEL_UP)),
		"external controller exclusively owns camera input")
	view.recenter_camera()
	check(view.camera_status() == external_status, "Rig recenter cannot steal external camera ownership")
	view.apply_snapshot(changed,[],0.0)
	check(_custom_calls == 1 and camera.position == CUSTOM_EYE,
		"full Sea presentation invokes the custom controller without overwriting its Camera position")
	check(_clocks(view) == terrain_clocks and changed_encounter.snapshot() == changed,
		"custom observation preserves accepted native and world/effects clocks")

	var owned: Array[WeakRef] = [weakref(camera),weakref(view.world),weakref(view.world.get_ocean()),
		weakref(view.effects),weakref(view.wakes),weakref(view.ships.player),weakref(view.sailors.player)]
	view.dispose(); view.dispose()
	var released := true
	for node: WeakRef in owned: released = released and node.get_ref() == null
	check(released and view.ships.is_empty() and view.sailors.is_empty() and view.camera == null and view.world == null,
		"dispose releases actual Camera, ocean, world, effects, imported vessel and crew")
	check(not view.handle_camera_input(_button(MOUSE_BUTTON_RIGHT)), "disposed Sea cannot retain or accept camera input")
	view.free()
	_finish()

func _finish() -> void:
	print("SHIP_CAMERA_WORLD_CONTRACT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _initialize() -> void: _run.call_deferred()
