extends SceneTree
## A delayed fire event must stay at the drawn gun where it was born, after
## later ship movement/rotation. Renderer snapshots must not rewrite ballistics.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
var assertions := 0
var failures := 0

func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL fire birth pose: ", detail)

func _initialize() -> void: _run.call_deferred()

func _encounter() -> RefCounted:
	return Encounter.new({"referenceHandling":true,"referenceGunnery":true,
		"ships":[{"id":"player","kind":"fuchuan","team":"player","heading":0.0,"position":{"x":12.5,"z":-34.0},"sailDeployment":0.0},
			{"id":"enemy","kind":"voc","team":"hostile","position":{"x":12.5,"z":76.0},"sailDeployment":0.0}],
		"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],
		"sampleTerrainHeight":func(_x: float,_z: float)->float:return -80.0})

func _point(value: Dictionary) -> Vector3: return Vector3(value.x,value.y,value.z)
func _wire(value: Vector3) -> Dictionary: return {"x":value.x,"y":value.y,"z":value.z}

func _original_mouth(view: Node3D, event: Dictionary, library: RefCounted) -> Vector3:
	# Expected geometry comes from the untouched GLB, not the history helper.
	var model: Node3D = view.get_model()
	var original: Node3D = library.instantiate_model(str(model.get_meta("source_path")))
	root.add_child(original)
	var closest: Node3D = null
	var distance := INF
	for socket: Node3D in model.find_children("socket_smoke_"+str(event.side)+"_*","Node3D",true,false):
		var next := socket.global_position.distance_squared_to(_point(event.position))
		if next < distance: closest=socket; distance=next
	var source: Node3D = original.find_child(str(closest.name),true,false)
	var expected: Vector3 = model.global_transform * (original.global_transform.affine_inverse() * source.global_position)
	original.free()
	return expected

func _moved(ship: Dictionary, time: float) -> Dictionary:
	var next := ship.duplicate(true)
	next.time = time
	next.visual.position = {"x":112.5,"y":8.0,"z":46.0}
	next.visual.heading = PI/2.0
	next.visual.pitch = 0.12
	next.visual.heel = -0.08
	return next

func _run() -> void:
	var native := _encounter()
	var before: Dictionary = native.snapshot()
	check(native.command({"type":"fire","side":"starboard"}).ok,"real authoritative encounter produces a fire event")
	var shots: Array = native.drain_events().filter(func(event: Dictionary)->bool:return event.type=="fire" and event.shipId=="player")
	check(shots.size()==1,"one actual player fire is available")
	if shots.is_empty(): _finish(); return
	var event: Dictionary = shots[0]
	var library := Library.new()
	var view := Ship.new(); root.add_child(view)
	check(view.configure("fuchuan",library),"actual original ship configures")
	var ship: Dictionary = before.ships[0].duplicate(true); ship.time=before.time
	view.apply_snapshot(ship,before.wind,0.0)
	var expected := _original_mouth(view,event,library)
	var original_event := event.duplicate(true)
	check(view.source_fire_position(event).distance_to(expected)<0.01,"on-time fire uses untouched drawn original mouth")
	var moved := _moved(ship,2.0)
	view.apply_snapshot(moved,before.wind,0.0)
	var delayed: Variant = view.source_fire_position(event)
	check(delayed is Vector3 and delayed.distance_to(expected)<0.01,"delayed fire retains born mouth after ship translates and rotates")
	view.set_lod_distance(700.0)
	for i in 3: view.apply_snapshot(moved,before.wind,0.0)
	delayed = view.source_fire_position(event)
	check(delayed is Vector3 and delayed.distance_to(expected)<0.01,"paused and LOD snapshots keep the same historical fire mouth")
	check(event==original_event,"historical lookup never rewrites native position or velocity")
	var same_time := moved.duplicate(true); same_time.visual.position.x=152.5
	view.apply_snapshot(same_time,before.wind,0.0)
	var current := event.duplicate(true); current.time=2.0
	current.position=_wire(view.get_model().find_children("socket_smoke_starboard_*","Node3D",true,false)[0].global_position)
	var replaced_expected := _original_mouth(view,current,library)
	check(view.source_fire_position(current).distance_to(replaced_expected)<0.01,"same accepted time replaces the displayed pose rather than keeping an old pose")
	var rewind := ship.duplicate(true); rewind.time=0.25; rewind.visual.position.x=-47.5
	view.apply_snapshot(rewind,before.wind,0.0)
	check(view.source_fire_position(current)==null,"rewind discards future fire poses")
	check(view.source_fire_position(event)==null,"rewind cannot reuse a prior encounter's earlier pose")
	var expiring := event.duplicate(true); expiring.time=0.25
	expiring.position=_wire(view.get_model().find_children("socket_smoke_starboard_*","Node3D",true,false)[0].global_position)
	check(view.source_fire_position(expiring) is Vector3,"new timeline accepts its own current fire mouth")
	for i in 270:
		var sample := rewind.duplicate(true); sample.time=0.25+float(i)/60.0
		view.apply_snapshot(sample,before.wind,0.0)
	check(view.source_fire_position(expiring)==null,"expired pose history uses canonical muzzle fallback instead of moving old smoke")
	_test_interpolated_birth(view,ship,event,before.wind,library)
	view.dispose(); view.free(); library.dispose()
	if OS.get_environment("MING_ARMADA_FIRE_POSE_SHIP_ONLY") != "1":
		await _test_sea_bridge(before,event)
	_finish()

func _test_interpolated_birth(view: Node3D, ship: Dictionary, event: Dictionary, wind: Dictionary, library: RefCounted) -> void:
	view.configure("fuchuan",library)
	var start := ship.duplicate(true); start.time=0.0
	start.visual.position={"x":0.0,"y":0.0,"z":0.0}; start.visual.heading=0.0
	start.visual.pitch=0.0; start.visual.heel=0.0
	view.apply_snapshot(start,wind,0.0)
	var socket: Node3D = view.get_model().find_children("socket_smoke_starboard_*","Node3D",true,false)[0]
	var shot := event.duplicate(true); shot.position=_wire(socket.global_position)
	var mouth := _original_mouth(view,shot,library)
	# Worked inverse of heading0's Y+90 basis: (worldX,Y,Z)->(-Z,Y,X).
	var logical_local := Vector3(-socket.global_position.z,socket.global_position.y,socket.global_position.x)
	var mouth_local := Vector3(-mouth.z,mouth.y,mouth.x)
	var end := start.duplicate(true); end.time=2.0
	end.visual.position={"x":100.0,"y":0.0,"z":80.0}; end.visual.heading=PI/2.0
	view.apply_snapshot(end,wind,0.0)
	var mid := Basis(Vector3.UP,PI/4.0)
	shot.time=1.0; shot.position=_wire(Vector3(50,0,40)+mid*logical_local)
	var expected := Vector3(50,0,40)+mid*mouth_local
	var mapped: Variant = view.source_fire_position(shot)
	check(mapped is Vector3 and mapped.distance_to(expected)<0.01,"fire between accepted poses uses half translation and 45 degree source rotation")
	view.configure("fuchuan",library); view.apply_snapshot(end,wind,0.0)
	check(view.source_fire_position(shot)==null,"reconfiguration discards old pose history")

func _test_sea_bridge(before: Dictionary, event: Dictionary) -> void:
	var sea := Sea.new(); root.add_child(sea)
	check(sea.configure(func(_x,_z):return -80.0,[],func(_x,_z,_t):return 0.0,before,{"resolution":8,"chunk_radius":0,"vegetation":false,"island_details":false}),"real naval presentation bridge configures")
	var original := event.duplicate(true)
	var on_time: Array = sea.apply_snapshot(before,[event],0.0)
	var source: Dictionary = on_time[0].source_muzzle_position
	var moved := before.duplicate(true); moved.time=2.0
	moved.ships[0]=_moved(before.ships[0],2.0)
	var snapshot_copy := moved.duplicate(true)
	var late: Array = sea.apply_snapshot(moved,[event],0.0)
	check(late[0].has("source_muzzle_position") and _point(late[0].source_muzzle_position).distance_to(_point(source))<0.01,"actual bridge places late smoke at original born mouth")
	var supplied := event.duplicate(true); supplied.source_muzzle_position={"x":212.0,"y":5.0,"z":-10.0}
	var supplied_copy := supplied.duplicate(true)
	var retained: Array = sea.apply_snapshot(moved,[supplied],0.0)
	check(retained[0].source_muzzle_position==supplied.source_muzzle_position,"bridge preserves an already captured source muzzle instead of recomputing it")
	check(event==original and supplied==supplied_copy and moved==snapshot_copy,"bridge leaves input native events and authoritative ship state immutable")
	var reset := moved.duplicate(true); reset.battleId="fresh-fire-pose-epoch"
	var fresh: Array = sea.apply_snapshot(reset,[event],0.0)
	check(not fresh[0].has("source_muzzle_position"),"new encounter has no old born pose and falls back to native event mouth")
	sea.dispose(); sea.free()
	await process_frame; await process_frame

func _finish() -> void:
	print("REFERENCE_FIRE_BIRTH_POSE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
