extends SceneTree
const HEIGHT_PATH := "res://modules/scene_engine/terrain/height_field.gd"
const PROFILE_PATH := "res://modules/scene_engine/terrain/reference_island_profile.gd"
var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, reason: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",reason)
func _run() -> void:
	check(FileAccess.file_exists(PROFILE_PATH),"reference island profile consumes original height data")
	if failures:
		print("REFERENCE_ISLAND_PROFILES_TESTS assertions=",assertions," failures=",failures)
		quit(1); return
	var Profile: GDScript=load(PROFILE_PATH)
	var Height: GDScript=load(HEIGHT_PATH)
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var old: RefCounted=Height.new()
	check(old.configure_ports(ports),"historical oracle remains default")
	var field: RefCounted=Height.new()
	check(field.configure_ports(ports,true,{"reference_islands":true}),"formal geography opts into real original profiles")
	var diagnostics: Array=field.reference_profiles()
	check(diagnostics.size()==3,"all formal islands consume a separate source profile")
	var names: Array=[]
	for record: Dictionary in diagnostics: names.append(record.id)
	check(names==["cat_island","coastal2","virgin_islands"],"source silhouettes are distinct in the original three-port world")
	for id: String in ["cat_island","coastal2","virgin_islands"]:
		var data: Dictionary=Profile.load_source(id)
		check(not data.is_empty(),"full source asset is valid and SHA verified: "+id)
		check(data.get("world_units")==null and data.get("world_height_scale")==null,"unknown original world units are preserved instead of invented")
		var profile: RefCounted=Profile.new()
		check(profile.configure(ports[names.find(id)],data,id),"profile accepts intact original indices")
		var profile_port: Dictionary=ports[names.find(id)]
		var before: float=profile.sample_height(float(profile_port.islandX),float(profile_port.islandZ))
		var before_diagnostics: Dictionary=profile.diagnostics()
		var broken:=data.duplicate(true); broken.values[0]=NAN
		check(not profile.configure(ports[0],broken,id),"nonfinite source index update is rejected atomically")
		check(profile.sample_height(float(profile_port.islandX),float(profile_port.islandZ))==before and profile.diagnostics()==before_diagnostics,"rejected source update retains prior profile and transform")
		_verify_source_samples(profile,data,profile_port)
	for port: Dictionary in ports:
		var dock:=Vector2(float(port.x),float(port.z))
		var inward: Vector2=(Vector2(float(port.islandX),float(port.islandZ))-dock).normalized()
		var across:=Vector2(-inward.y,inward.x)
		for along: float in [-40.0,0.0,12.0,20.0]:
			for lateral: float in [-12.0,0.0,12.0]:
				var point:=dock+inward*along+across*lateral
				check(field.sample_height(point.x,point.y)<=-7.9,"actual docking approach stays deep enough for the starter ship: "+str(port.id))
		for along: float in [43.0,47.5,55.0]:
			var point:=dock+inward*along
			var h: float=field.sample_height(point.x,point.y)
			check(h>=1.5 and h<=3.1,"55 metre pier lands on a local habitable apron: "+str(port.id))
		var changed:=0
		var water:=0
		var land:=0
		for row in 31:
			for column in 31:
				var x: float=port.islandX+(float(column)/30.0*2.0-1.0)*port.radius
				var z: float=port.islandZ+(float(row)/30.0*2.0-1.0)*port.radius
				var h: float=field.sample_height(x,z)
				check(is_finite(h),"source island sampling is finite throughout the world footprint")
				if absf(h-old.sample_height(x,z))>.5: changed+=1
				if h>0: land+=1
				else: water+=1
		check(changed>300 and land>25 and water>100,"actual source ridge/coast layout replaces the circular terrain")
	var accepted: float=field.sample_height(-480,-60)
	var invalid:=ports.duplicate(true); invalid[0].radius=0.0
	check(not field.configure_ports(invalid,true,{"reference_islands":true}),"invalid port update is rejected")
	check(field.sample_height(-480,-60)==accepted,"invalid port update preserves accepted reference geography")
	check(not field.configure_ports(ports,true,{"reference_islands":"yes"}),"invalid opt-in type is rejected")
	check(field.sample_height(-480,-60)==accepted,"invalid options preserve accepted reference geography")
	var unknown:=ports.duplicate(true); unknown[1].referenceProfile="invented-island"
	check(not field.configure_ports(unknown,true,{"reference_islands":true}),"unknown source profile is rejected rather than silently replacing it")
	check(field.sample_height(-480,-60)==accepted,"unknown source profile preserves all accepted islands")
	var invalid_type:=ports.duplicate(true); invalid_type[0].peak={"bad":1}
	check(not field.configure_ports(invalid_type,true,{"reference_islands":true}),"reference port rejects a nonnumeric height before casting or mutating")
	check(field.sample_height(-480,-60)==accepted,"nonnumeric port rejection preserves the whole accepted height field")
	var without_shelf: RefCounted=Height.new()
	check(without_shelf.configure_ports(ports,false,{"reference_islands":true}),"reference profile can be composed without the supply shelf")
	var shelf_point:=Vector2(float(ports[0].x)+float(ports[1].x),float(ports[0].z)+float(ports[1].z))*.5
	check(absf(field.sample_height(shelf_point.x,shelf_point.y)+2.4)<.000001,"the original open-water supply shoal keeps its 2.4 metre depth")
	check(without_shelf.sample_height(shelf_point.x,shelf_point.y)<-8.0,"disabling supply shelf does not flatten unrelated source terrain")
	var default_again: RefCounted=Height.new()
	check(default_again.configure_ports(ports,true,{}),"empty options preserve old default formula")
	for row in 20:
		for column in 20:
			var x: float=-750.0+float(column)*75.0
			var z: float=-300.0+float(row)*50.0
			check(default_again.sample_height(x,z)==old.sample_height(x,z),"default opt-out retains the exact pre-existing terrain oracle")
	check(is_nan(field.sample_height(NAN,0)),"invalid world coordinate preserves height contract")
	print("REFERENCE_ISLAND_PROFILES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _verify_source_samples(profile: RefCounted,data: Dictionary,port: Dictionary) -> void:
	# Independent inverse of the reported transform. Every sampled source index
	# away from the small dock/border adaptations must retain its original shape.
	var info: Dictionary=profile.diagnostics()
	var raw_outward: Vector2=info.sourceOutward
	var raw_across:=Vector2(-raw_outward.y,raw_outward.x)
	var inward: Vector2=info.inward
	var across:=Vector2(-inward.y,inward.x)
	var minimum:=255.0
	var maximum:=0.0
	for value: Variant in data.values: minimum=minf(minimum,float(value)); maximum=maxf(maximum,float(value))
	var retained:=0
	for y in range(6,int(data.height)-6,7):
		for x in range(6,int(data.width)-6,7):
			var raw_offset:=Vector2(x,y)-Vector2(info.sourceCenter)
			var point: Vector2=Vector2(info.islandCenter)+(-inward*raw_offset.dot(raw_outward)+across*raw_offset.dot(raw_across))*float(info.scale)
			var dock_offset:=point-Vector2(info.dock)
			if absf(dock_offset.dot(across))<35.0 and dock_offset.dot(inward)>-120.0 and dock_offset.dot(inward)<95.0: continue
			var raw:=float(data.values[y*int(data.width)+x])
			var expected: float=(raw-128.0)*(float(port.peak)/(maximum-128.0) if raw>=128.0 else 24.0/(128.0-minimum))
			check(absf(profile.sample_height(point.x,point.y)-expected)<.002,"original interior indexed height is retained after world scaling and rotation")
			retained+=1
	check(retained>20,"source integrity test covers many points outside the local harbor adaptation")
