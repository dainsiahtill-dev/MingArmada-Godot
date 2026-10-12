extends SceneTree
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Profile=preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,reason: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",reason)
func _run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var layout: Dictionary={"xiamen":"coastal2","kinmen":"cat_island","forward-supply":"virgin_islands"}
	var options: Dictionary={"reference_islands":true,"reference_profiles":layout,"reference_art":{"sea_index":120.0,"height_gain":.28,"smoothing_radius":2,"border_rounding":.15,"border_fade_pixels":7.0}}
	var baseline:=Height.new(); var art:=Height.new()
	check(baseline.configure_ports(ports,false,{"reference_islands":true,"reference_profiles":layout}),"current raw profile baseline remains configurable")
	check(art.configure_ports(ports,false,options),"game art parameters are explicitly configured")
	var profiles: Array=art.reference_profiles()
	check(profiles[0].seaIndex==120.0,"new art threshold is used rather than silently ignored")
	check(profiles[0].get("heightGain")==.28 and profiles[0].get("smoothingRadius")==2,"game height and filtering parameters are recorded")
	var validator:=Profile.new()
	check(validator.has_method("valid_art_options"),"all art controls are validated before configuration")
	if failures: _finish(); return
	for index in ports.size():
		var port: Dictionary=ports[index]
		var base_stats:=_stats(baseline,port)
		var art_stats:=_stats(art,port)
		print("ISLAND_ART_LAND_PROBE ",JSON.stringify({"port":port.id,"base":base_stats,"art":art_stats}))
		check(art_stats.maximum<=float(port.peak)*.29,"the configured art gain removes the tall source spike")
		check(art_stats.land>base_stats.land,"lower game threshold creates connected backland and useful shallow coast")
		check(art_stats.slope_p95<base_stats.slope_p95*.60,"small source filter plus height gain lowers actual world gradients")
		if index==0: check(art_stats.forest>base_stats.forest*2.0,"sheltered town now has a substantially larger forest-compatible land area")
		var dock:=Vector2(float(port.x),float(port.z))
		var inward: Vector2=(Vector2(float(port.islandX),float(port.islandZ))-dock).normalized()
		var across:=Vector2(-inward.y,inward.x)
		for along: float in [-40.0,0.0,12.0,20.0]:
			for side: float in [-12.0,0.0,12.0]:
				var point:=dock+inward*along+across*side
				check(art.sample_height(point.x,point.y)<=-7.9,"art adapt preserves the actual navigable harbor")
		for along: float in [43.0,47.5,55.0]:
			var point:=dock+inward*along
			var h: float=art.sample_height(point.x,point.y)
			check(h>=1.5 and h<=3.1,"game gain does not reduce pier landing below land")
	var before: Array=art.reference_profiles()
	var accepted: float=art.sample_height(-480,-60)
	for invalid: Dictionary in [{"sea_index":NAN},{"height_gain":0.0},{"height_gain":"low"},{"smoothing_radius":2.5},{"smoothing_radius":-1},{"border_rounding":.6},{"border_fade_pixels":0.0},{"unknown":true}]:
		var bad:=options.duplicate(true); bad.reference_art=invalid
		check(not art.configure_ports(ports,false,bad),"invalid art settings are atomically rejected")
		check(art.reference_profiles()==before and art.sample_height(-480,-60)==accepted,"invalid art settings preserve the accepted data and shape")
	var bad_type:=options.duplicate(true); bad_type.reference_art=false
	check(not art.configure_ports(ports,false,bad_type),"art controls must be a dictionary")
	var data: Dictionary=Profile.load_source("coastal2")
	var raw_values: Array=data.values.duplicate()
	var direct:=Profile.new()
	check(direct.call("configure",ports[0],data,"coastal2",options.reference_art),"direct helper accepts the optional game art controls")
	check(data.values==raw_values,"derived filtering never changes caller-owned original indices")
	var custom_default:=Profile.new(); var explicit_default:=Profile.new()
	check(custom_default.configure(ports[0],data,"coastal2") and explicit_default.call("configure",ports[0],data,"coastal2",{"sea_index":128.0,"height_gain":1.0,"smoothing_radius":0,"border_rounding":0.0,"border_fade_pixels":5.0}),"explicit default art preserves existing source adapter settings")
	for row in 12:
		for column in 12:
			var x: float=-665+float(column)*32.0; var z: float=-245+float(row)*32.0
			check(custom_default.sample_height(x,z)==explicit_default.sample_height(x,z),"default source adapter remains exactly unchanged")
	var with_shelf:=Height.new()
	check(with_shelf.configure_ports(ports,true,options),"art terrain composes with the original supply shoal")
	var midpoint:=Vector2(float(ports[0].x)+float(ports[1].x),float(ports[0].z)+float(ports[1].z))*.5
	check(absf(with_shelf.sample_height(midpoint.x,midpoint.y)+2.4)<.000001,"original shallow supply route keeps its 2.4 metre depth")
	_finish()
func _stats(field: RefCounted,port: Dictionary) -> Dictionary:
	var maximum:=-24.0
	var land:=0
	var forest:=0
	var slopes: Array[float]=[]
	for row in 75:
		for column in 75:
			var x: float=port.islandX+(float(column)/74.0*2.0-1.0)*port.radius
			var z: float=port.islandZ+(float(row)/74.0*2.0-1.0)*port.radius
			var h: float=field.sample_height(x,z)
			maximum=maxf(maximum,h)
			if h<=0.0: continue
			land+=1
			var gx: float=field.sample_height(x+.5,z)-field.sample_height(x-.5,z)
			var gz: float=field.sample_height(x,z+.5)-field.sample_height(x,z-.5)
			var slope:=sqrt(gx*gx+gz*gz); slopes.append(slope)
			if h>1.2 and slope<.48: forest+=1
	slopes.sort()
	return {"maximum":maximum,"land":land,"forest":forest,"slope_p95":slopes[int((slopes.size()-1)*.95)]}
func _finish() -> void:
	print("REFERENCE_ISLAND_ART_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
