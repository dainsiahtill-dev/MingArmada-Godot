extends SceneTree
const Profile=preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
const Coordinates=preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
const Static=preload("res://modules/scene_engine/fidelity_island/static_islands.gd")
var assertions:=0
var failures:=0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func edge_at(point: Vector2,size: Vector2) -> float:
	var radius:=minf(size.x-1.0,size.y-1.0)*.3
	var half: Vector2=(size-Vector2.ONE)*.5
	var q: Vector2=(point-half).abs()-(half-Vector2.ONE*radius)
	return radius-q.max(Vector2.ZERO).length()-minf(maxf(q.x,q.y),0.0)
func coast_art() -> Dictionary:
	var options: Dictionary=Geography.source_options()
	var art: Dictionary=options.reference_art.duplicate()
	art.merge(options.reference_art_by_profile.coastal2,true)
	return art
func legacy_art(art: Dictionary) -> Dictionary:
	var legacy:=art.duplicate()
	legacy.erase("border_coast_inset");legacy.erase("border_coast_slope")
	return legacy
func coast_stats(profile: RefCounted) -> Dictionary:
	var info: Dictionary=profile.diagnostics()
	var slopes: Array[float]=[]
	var land:=0
	for row in int(info.height):
		for column in int(info.width):
			var pixel:=Vector2(column,row)
			var h: float=profile._source_height(pixel)
			if h<=0: continue
			land+=1
			if edge_at(pixel,Vector2(info.width,info.height))>=14.0: continue
			var dx: float=(profile._source_height(pixel+Vector2(.5,0))-profile._source_height(pixel-Vector2(.5,0)))/float(info.scale)
			var dy: float=(profile._source_height(pixel+Vector2(0,.5))-profile._source_height(pixel-Vector2(0,.5)))/float(info.scale)
			slopes.append(sqrt(dx*dx+dy*dy))
	slopes.sort()
	return {"land":land,"samples":slopes.size(),"p50":slopes[int(slopes.size()*.5)],"p95":slopes[int(slopes.size()*.95)]}
func run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var source: Dictionary=Profile.load_source("coastal2")
	var art:=coast_art()
	var before:=Profile.new();var after:=Profile.new()
	check(before.configure(ports[0],source,"coastal2",legacy_art(art)),"original mainland closure configures")
	check(after.configure(ports[0],source,"coastal2",art),"bounded mainland coast envelope configures")
	var old:=coast_stats(before);var new:=coast_stats(after)
	check(new.p95<1.2 and new.p95<old.p95*.6,"artificial dry coast p95 slope falls without flattening the whole island")
	check(new.land>old.land+2000,"gentle boundary does not consume more source lowland")
	var info: Dictionary=after.diagnostics()
	var retained:=0
	for row in range(14,int(info.height)-14,3):
		for column in range(14,int(info.width)-14,3):
			var pixel:=Vector2(column,row)
			if edge_at(pixel,Vector2(info.width,info.height))<14.0: continue
			var world:=Coordinates.source_pixel_to_world(pixel,info)
			check(after.sample_height(world.x,world.y)==before.sample_height(world.x,world.y),"source interior and harbor authority remain exactly unchanged outside closure band")
			retained+=1
	check(retained>4000,"interior comparison covers the source mainland")
	var scale: float=info.scale
	# The straight left boundary at row80.25 contains verified positive source
	# land. Check the new shoreline value and one-sided world-metre derivatives.
	var epsilon:=.01
	var shore_pixel:=Vector2(6.0/scale,80.25)
	var shore: float=after._source_height(shore_pixel)
	var left: float=(shore-after._source_height(shore_pixel-Vector2(epsilon/scale,0)))/epsilon
	var right: float=(after._source_height(shore_pixel+Vector2(epsilon/scale,0))-shore)/epsilon
	check(absf(shore)<.000001,"artificial shoreline meets sea level at its explicit six metre inset")
	check(absf(left-right)<.05 and absf(left)<.05 and absf(right)<.05,"sea-to-land envelope joins with a continuous first derivative")
	# At the inner band exit, compare the correction to the original source;
	# this avoids confusing an existing native pixel crease with a new seam.
	for pixel: Vector2 in [Vector2(14.0,80.25),Vector2(314.0,100.25)]:
		var middle: float=after._source_height(pixel)-before._source_height(pixel)
		var before_exit: float=after._source_height(pixel-Vector2(epsilon/scale,0))-before._source_height(pixel-Vector2(epsilon/scale,0))
		var after_exit: float=after._source_height(pixel+Vector2(epsilon/scale,0))-before._source_height(pixel+Vector2(epsilon/scale,0))
		check(middle==0.0 and absf(before_exit)<.001 and absf(after_exit)<.001,"coast correction is continuous at source-interior exit")
		check(absf((after_exit-middle)/epsilon-(middle-before_exit)/epsilon)<.05,"coast correction has no derivative jump at source-interior exit")
	var dock:=Vector2(float(ports[0].x),float(ports[0].z))
	var inward: Vector2=(Vector2(float(ports[0].islandX),float(ports[0].islandZ))-dock).normalized()
	var across:=Vector2(-inward.y,inward.x)
	for along: float in [-40.0,0.0,12.0,20.0,43.0,54.0,55.0]:
		for lateral: float in [-12.0,0.0,12.0]:
			var world:=dock+inward*along+across*lateral
			check(after.sample_height(world.x,world.y)==before.sample_height(world.x,world.y),"approach minus-eight metre depth and pier apron remain exact")
	var landing:=dock+inward*54.0
	check(absf(after.sample_height(landing.x,landing.y)-2.375)<.00001,"54m pier still lands at2.375m")
	var accepted: float=after.sample_height(-480,-60)
	for invalid: Dictionary in [{"border_coast_inset":-1.0},{"border_coast_slope":0.0},{"border_coast_inset":NAN},{"border_coast_inset":20.0,"border_fade_pixels":14.0}]:
		var bad:=art.duplicate();bad.merge(invalid,true)
		check(not after.configure(ports[0],source,"coastal2",bad),"invalid or unfit coast controls reject before replacing accepted shape")
		check(after.sample_height(-480,-60)==accepted,"rejected coast update preserves source height authority")
	# Use the real immutable renderer with the same authority; coverage must
	# include added beach and existing finite apron, not just source vertices.
	var height:=Height.new();check(height.configure_ports(ports,true,Geography.source_options()),"source comparison world enables the bounded coast")
	var builder:=Static.new()
	check(builder.configure(height.reference_profiles(),height.sample_height,[StandardMaterial3D.new(),StandardMaterial3D.new(),StandardMaterial3D.new()]),"immutable source mesh builds from the retained height authority")
	var holes:=0;var dry:=0
	for row in range(-80,241,2):
		for column in range(-200,201,2):
			var world:=Vector2(-480.0+column,-60.0+row)
			var h: float=height.sample_height(world.x,world.y)
			if h<=.01: continue
			dry+=1
			var rendered: float=builder.sample_mesh_height(world.x,world.y)
			if not is_finite(rendered) or rendered<-.1: holes+=1
	check(dry>5000 and holes==0,"every sampled positive mainland point has actual mesh coverage")
	builder.dispose()
	print("COAST_ENVELOPE_PROBE ",JSON.stringify({"before":old,"after":new,"interiorSamples":retained,"shoreHeight":shore,"shoreDerivativeLeft":left,"shoreDerivativeRight":right,"positiveCoverageSamples":dry,"geometryHoles":holes}))
	print("REFERENCE_COAST_ENVELOPE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
