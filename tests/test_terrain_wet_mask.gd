extends SceneTree
const World=preload("res://modules/scene_engine/world/world_view.gd")
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions:=0
var failures:=0
var queries:=0
var bad_query:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL terrain wet mask: ",message)
func height(_x:float,_z:float)->float:
	queries+=1
	return NAN if bad_query>0 and queries==bad_query else -1.0
func _initialize()->void:run.call_deferred()
func run()->void:
	var path:="res://modules/scene_engine/water/terrain_wet_mask.gd"
	var world:=World.new();root.add_child(world)
	check(world.has_method("get_interactive_water_mask") and world.has_method("get_interactive_water_mask_revision"),"world publishes cached mask and lightweight revision")
	check(ResourceLoader.exists(path),"CPU-only R8 builder exists")
	if failures:world.free();finish();return
	var builder:Script=load(path)
	var heights:=PackedFloat32Array([-1,-1,-1,-1,-1,0,-1,-1,-1])
	var bounds:=Rect2(-2,-6,4,12)
	var built:Dictionary=builder.build(heights,3,bounds)
	check(built.valid and built.resolution==2 and built.data==PackedByteArray([255,0,255,0]),"each output cell uses all4 corners; exact sea-level corner is dry")
	check(built.bounds==Vector4(-2,-6,2,6) and built.cell_m==Vector2(2,6),"endpoint lattice produces cell mask with correct rectangular world spacing")
	var same:Dictionary=builder.build(heights,3,bounds)
	check(same.digest==built.digest,"identical mask content yields deterministic digest")
	check(builder.build(heights,3,Rect2(-1,-6,4,12)).digest!=built.digest,"world-domain shift participates in digest")
	var zero:=heights.duplicate();zero[0]=NAN
	check(not builder.build(zero,3,bounds).valid,"nonfinite source height rejects whole mask")
	check(not builder.build(PackedFloat32Array([-1]),3,bounds).valid,"height count cannot silently fabricate allwet")
	check(not builder.build(heights,3,Rect2()).valid,"zero-size world domain rejected")
	check(not builder.build(heights,1,bounds).valid,"no-cell lattice rejected")
	var larger:=PackedFloat32Array();larger.resize(16);larger.fill(-1)
	var odd:Dictionary=builder.build(larger,4,bounds)
	check(odd.valid and odd.resolution==3 and odd.data.size()==9,"mask resolution side-1 need not be multipleof8")
	var field=load("res://modules/scene_engine/water/interactive_wake_field.gd").new()
	check(field._valid_mask(odd),"existing T1 accepts odd-resolution R8 mask contract")
	field.dispose()
	check(not world.get_interactive_water_mask().valid,"unconfigured world is unknown, never allwet")
	var ocean:=Ocean.new();root.add_child(ocean)
	world._ocean=ocean;world._height_sampler=height;world._static_shore_resolution=3
	queries=0
	world._configure_static_shore_field(bounds)
	var first:Dictionary=world.get_interactive_water_mask();var revision:int=world.get_interactive_water_mask_revision()
	check(queries==9 and first.valid and first.resolution==2,"static bridge reuses existing9 height reads; no new sampling")
	check(first.revision==revision and first.data==PackedByteArray([255,255,255,255]),"complete static R8 publication has matching revision")
	var pristine:Dictionary=first.duplicate(true)
	first.data[0]=0;first.bounds=Vector4.ZERO
	var isolated:Dictionary=world.get_interactive_water_mask()
	check(isolated.data==pristine.data and isolated.bounds==pristine.bounds,"caller cannot mutate cached packed data or bounds")
	for i in 5:world.get_interactive_water_mask_revision()
	check(queries==9 and world.get_interactive_water_mask_revision()==revision,"cheap revision reads never resample terrain or republish")
	queries=0;bad_query=3
	world._configure_static_shore_field(bounds)
	var invalid:Dictionary=world.get_interactive_water_mask()
	check(not invalid.valid and not invalid.error.is_empty() and not invalid.has("data"),"partial bad height lattice publishes explicit invalid status, never partial/allwet")
	check(world.get_interactive_water_mask_revision()>revision,"failed rebuild changes revision so consumer notices invalidation")
	check(world._interactive_water_mask.data==pristine.data,"failed build does not overwrite last complete cached bytes")
	queries=0;bad_query=0;world._static_shore_resolution=4
	world._configure_static_shore_field(bounds)
	var rebuilt:Dictionary=world.get_interactive_water_mask()
	check(rebuilt.valid and rebuilt.resolution==3 and rebuilt.revision>invalid.revision and rebuilt.digest!=pristine.digest,"changed quality lattice recomputes content and monotonically advances revision")
	check(queries==16,"quality recomputation makes only existing16 height queries")
	world._radius=0;world._resolution=4;world._chunk_size=25.0;queries=0
	world._update_near_shore_field(Vector2i.ZERO)
	var dynamic:Dictionary=world.get_interactive_water_mask()
	check(dynamic.valid and dynamic.resolution==4 and dynamic.bounds==Vector4(-12.5,-12.5,12.5,12.5) and queries==25,"dynamic bridge reuses existing5x5 lattice with exact world cell domain")
	world._update_near_shore_field(Vector2i.ZERO)
	check(queries==25 and world.get_interactive_water_mask_revision()==dynamic.revision,"same chunk window retains cached mask")
	world._update_near_shore_field(Vector2i(1,0))
	var moved:Dictionary=world.get_interactive_water_mask()
	check(queries==50 and moved.bounds==Vector4(12.5,-12.5,37.5,12.5) and moved.digest!=dynamic.digest,"new chunk window updates matching mask bytes and bounds")
	var before_dispose:int=world.get_interactive_water_mask_revision();world.dispose()
	check(not world.get_interactive_water_mask().valid and world._interactive_water_mask.is_empty(),"dispose clears cache and exposes explicit unavailable state")
	check(world.get_interactive_water_mask_revision()>before_dispose,"dispose revision invalidates held consumer binding")
	var disposed_revision:int=world.get_interactive_water_mask_revision()
	check(world.configure(height,[],{"ports":[],"vegetation":false,"collision":false,"chunk_radius":0,"resolution":4,"ocean_resolution":8,"island_details":false}),"actual openwater world configures")
	check(world.get_interactive_water_mask().is_empty(),"explicit no-shore route returns allwet empty contract")
	check(world.get_interactive_water_mask_revision()>disposed_revision,"configure after dispose is a new observed mask lifecycle")
	world.dispose();world.free();ocean.free();finish()
func finish()->void:
	print("TERRAIN_WET_MASK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
