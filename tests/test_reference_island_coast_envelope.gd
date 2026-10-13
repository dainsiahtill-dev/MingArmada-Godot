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
func native_interior_art(art: Dictionary) -> Dictionary:
	var legacy:=art.duplicate()
	legacy.border_rounding=0.0
	legacy.border_fade_pixels=1.0
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
	check(before.configure(ports[0],source,"coastal2",native_interior_art(art)),"unrounded source comparison with a one-pixel border configures")
	check(after.configure(ports[0],source,"coastal2",art),"rounded mainland border closure configures")
	var old:=coast_stats(before);var new:=coast_stats(after)
	check(before.diagnostics().borderRounding==0.0 and after.diagnostics().borderRounding==.3,"coast comparison uses genuinely distinct rectangular and rounded closures")
	check(after._source_height(Vector2(10,10))==Profile.OUTSIDE_HEIGHT and before._source_height(Vector2(10,10))>Profile.OUTSIDE_HEIGHT,"rounded corners close the mainland extract without changing its interior")
	var info: Dictionary=after.diagnostics()
	var retained:=0
	for row in range(14,int(info.height)-14,3):
		for column in range(14,int(info.width)-14,3):
			var pixel:=Vector2(column,row)
			if edge_at(pixel,Vector2(info.width,info.height))<14.0: continue
			check(after._source_height(pixel)==before._source_height(pixel),"source interior remains exactly unchanged outside rounded closure band")
			retained+=1
	check(retained>4000,"interior comparison covers the source mainland")
	var scale: float=info.scale
	# The implemented boundary closes to -24m at edge zero, then meets the
	# retained source at14pixels. It does not define a six-metre sea-level inset.
	var epsilon:=.01
	var shore_pixel:=Vector2(0.0,80.25)
	var shore: float=after._source_height(shore_pixel)
	var left: float=(shore-after._source_height(shore_pixel-Vector2(epsilon/scale,0)))/epsilon
	var right: float=(after._source_height(shore_pixel+Vector2(epsilon/scale,0))-shore)/epsilon
	check(absf(shore-Profile.OUTSIDE_HEIGHT)<.000000001,"rounded border meets the retained minus24metre outside authority")
	check(absf(left-right)<.05 and absf(left)<.05 and absf(right)<.05,"outside-to-source closure joins with a continuous first derivative")
	var middle_pixel:=Vector2(7.0,80.25)
	# Rounded distance uses Float32 Vector2 arithmetic (edge7 differs by1.5e-6
	# pixels). This absolute10micrometre allowance covers that spatial precision.
	check(absf(after._source_height(middle_pixel)-lerpf(Profile.OUTSIDE_HEIGHT,before._source_height(middle_pixel),.5))<.00001,"14pixel closure uses the actual half-weight smoothstep at its midpoint")
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
			check(absf(after.sample_height(world.x,world.y)-before.sample_height(world.x,world.y))<.000000001,"approach minus-eight metre depth and pier apron remain exact within coordinate rounding")
	var landing:=dock+inward*54.0
	check(absf(after.sample_height(landing.x,landing.y)-2.375)<.00001,"54m pier still lands at2.375m")
	var accepted: float=after.sample_height(-480,-60)
	for invalid: Dictionary in [{"border_rounding":-.1},{"border_rounding":.46},{"border_fade_pixels":0.0},{"border_fade_pixels":NAN}]:
		var bad:=art.duplicate();bad.merge(invalid,true)
		check(not after.configure(ports[0],source,"coastal2",bad),"invalid or unfit coast controls reject before replacing accepted shape")
		check(after.sample_height(-480,-60)==accepted,"rejected coast update preserves source height authority")
	# Use the real immutable renderer with the same authority; coverage must
	# include the retained mainland and finite apron, not just source vertices.
	var height:=Height.new();check(height.configure_ports(ports,true,Geography.source_options()),"source comparison world enables the bounded coast")
	var builder:=Static.new()
	check(builder.configure(height.reference_profiles(),height.sample_height,[StandardMaterial3D.new(),StandardMaterial3D.new(),StandardMaterial3D.new()]),"immutable source mesh builds from the retained height authority")
	var holes:=0;var dry:=0;var max_error:=0.0
	for row in range(-80,241,2):
		for column in range(-200,201,2):
			var world:=Vector2(-480.0+column,-60.0+row)
			var h: float=height.sample_height(world.x,world.y)
			if h<=.01: continue
			dry+=1
			var rendered: float=builder.sample_mesh_height(world.x,world.y)
			if not is_finite(rendered): holes+=1
			else: max_error=maxf(max_error,absf(rendered-h))
	check(dry>5000 and holes==0,"every sampled positive mainland point has finite actual mesh coverage")
	check(max_error<.00005,"positive mainland physics heights match the actual triangles: max error="+str(max_error))
	var witness:=Vector2(-396,-130)
	check(absf(height.sample_height(witness.x,witness.y)-builder.sample_mesh_height(witness.x,witness.y))<.00005,"mixed sea-land cell retains the recorded0.236metre authority discrepancy regression")
	check(height.has_method("sample_original_reference_height"),"original raw-index reference authority remains explicitly available")
	if height.has_method("sample_original_reference_height"):
		check(absf(height.sample_original_reference_height(witness.x,witness.y)-.0683184737250926)<.000000001,"original raw-index/bilinear evidence preserves its known positive shoreline witness")
		check(absf(height.sample_height(witness.x,witness.y)+.167801345902262)<.000000001,"target authority keeps the actual retained triangle height at that same witness")
		var original:=Static.new()
		check(original.configure(height.reference_profiles(),height.sample_original_reference_height,[StandardMaterial3D.new(),StandardMaterial3D.new(),StandardMaterial3D.new()]),"original mathematical authority still builds the retained comparison geometry")
		for index in builder.get_meshes().size():
			var actual: Array=builder.get_meshes()[index].mesh.surface_get_arrays(0)
			var retained_mesh: Array=original.get_meshes()[index].mesh.surface_get_arrays(0)
			check(actual[Mesh.ARRAY_VERTEX]==retained_mesh[Mesh.ARRAY_VERTEX] and actual[Mesh.ARRAY_INDEX]==retained_mesh[Mesh.ARRAY_INDEX] and actual[Mesh.ARRAY_TEX_UV]==retained_mesh[Mesh.ARRAY_TEX_UV],"triangle physics adaptation preserves every retained render vertex/index/UV exactly")
		original.dispose()
	builder.dispose()
	print("COAST_ENVELOPE_PROBE ",JSON.stringify({"before":old,"after":new,"interiorSamples":retained,"shoreHeight":shore,"shoreDerivativeLeft":left,"shoreDerivativeRight":right,"positiveCoverageSamples":dry,"geometryHoles":holes,"maxTriangleAuthorityError":max_error}))
	print("REFERENCE_COAST_ENVELOPE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
