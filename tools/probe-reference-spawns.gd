extends SceneTree
## Audit only: actual opening simulation against the new canonical geography.
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
const Types=preload("res://modules/contracts/physics_types.gd")
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var field:=Height.new()
	if not field.configure_ports(ports,true,preload("res://game/scenes/common/reference_geography.gd").options()): printerr("FAIL: reference geography"); quit(1); return
	var runtime:=Runtime.new(); var ready: Dictionary=runtime.configure(field.sample_height)
	if not ready.ok: printerr("FAIL: actual Mingqi startup ",ready); quit(1); return
	var native: Dictionary=runtime.snapshot().naval; var records: Array=[]; var failures:=0
	for ship: Dictionary in native.ships:
		var position: Dictionary=ship.visual.position; var spec: Dictionary=Types.ship_spec(ship.kind)
		var h:=field.sample_height(position.x,position.z)
		var minimum_depth:=INF; var land_points:=0; var hull_points: Array=[]
		for longitudinal: float in [-.5,0.0,.5]:
			for lateral: float in [-.5,0.0,.5]:
				var x: float=position.x+cos(ship.visual.heading)*spec.length*longitudinal-sin(ship.visual.heading)*spec.width*lateral
				var z: float=position.z+sin(ship.visual.heading)*spec.length*longitudinal+cos(ship.visual.heading)*spec.width*lateral
				var height:=field.sample_height(x,z); minimum_depth=minf(minimum_depth,-height)
				if height>=0.0: land_points+=1
				hull_points.append({"x":x,"z":z,"height":height})
		var draft: float=ship.get("stats",{}).get("draftMeters",spec.draft)
		if h>=0.0 or minimum_depth<draft+.3: failures+=1
		records.append({"id":ship.id,"kind":ship.kind,"team":ship.get("team",""),"position":position,"heading":ship.visual.heading,"centerGroundHeight":h,"minimumHullDepth":minimum_depth,"draftMeters":draft,"landHullPoints":land_points,"hullPoints":hull_points})
	print("REFERENCE_OPENING_SPAWN_REPORT ",JSON.stringify({"fleet":records,"profiles":field.reference_profiles(),"failures":failures}))
	runtime.dispose()
	print("REFERENCE_OPENING_SPAWN_CHECK ships=",records.size()," failures=",failures)
	quit(1 if failures else 0)
