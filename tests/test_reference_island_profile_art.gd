extends SceneTree
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Profile=preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const Geography=preload("res://game/scenes/common/reference_geography.gd")
const Coordinates=preload("res://modules/scene_engine/fidelity_island/source_coordinates.gd")
var assertions:=0
var failures:=0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func art_for(options: Dictionary,id: String) -> Dictionary:
	var art: Dictionary=options.get("reference_art",{}).duplicate()
	art.merge(options.get("reference_art_by_profile",{}).get(id,{}),true)
	return art
func components(mask: PackedByteArray,width: int,height: int) -> Array[int]:
	var sizes: Array[int]=[]
	var seen:=PackedByteArray();seen.resize(mask.size())
	for start in mask.size():
		if mask[start]==0 or seen[start]: continue
		var queue: Array[int]=[start];seen[start]=1
		var cursor:=0
		while cursor<queue.size():
			var current: int=queue[cursor];cursor+=1
			for offset: Vector2i in [Vector2i(-1,0),Vector2i(1,0),Vector2i(0,-1),Vector2i(0,1)]:
				var point:=Vector2i(current%width,current/width)+offset
				if point.x<0 or point.x>=width or point.y<0 or point.y>=height: continue
				var next:=point.y*width+point.x
				if mask[next] and not seen[next]: seen[next]=1;queue.append(next)
		sizes.append(queue.size())
	sizes.sort();sizes.reverse()
	return sizes
func land_layout(profile: RefCounted) -> Dictionary:
	var mapping: Dictionary=profile.diagnostics()
	var mask:=PackedByteArray();mask.resize(int(mapping.width)*int(mapping.height))
	var count:=0
	for row in int(mapping.height):
		for column in int(mapping.width):
			var point:=Coordinates.source_pixel_to_world(Vector2(column,row),mapping)
			var h: float=profile.sample_height(point.x,point.y)
			if h>.01: mask[row*int(mapping.width)+column]=1;count+=1
	return {"count":count,"components":components(mask,int(mapping.width),int(mapping.height))}
func run() -> void:
	var ports: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	var options: Dictionary=Geography.source_options()
	var field:=Height.new()
	check(field.configure_ports(ports,true,options),"formal geography accepts profile art")
	var records: Array=field.reference_profiles()
	check(records[0].borderRounding==.3 and records[0].borderFadePixels==14.0,"mainland extract keeps its explicit closure")
	check(records[1].borderRounding==0.0 and records[1].borderFadePixels==5.0,"naturally enclosed Cat keeps its source coast")
	check(records[2].borderRounding==0.0 and records[2].borderFadePixels==5.0,"naturally enclosed Virgin keeps its source coast")
	# A distant dock isolates the source coastline from the intentional local
	# harbor. This catches loss of real source land, not a metadata-only change.
	for index: int in [1,2]:
		var port: Dictionary=ports[index].duplicate()
		port.x=100000.0;port.z=100000.0
		var id: String=options.reference_profiles[port.id]
		var profile:=Profile.new()
		check(profile.configure(port,Profile.load_source(id),id,art_for(options,id)),"natural island profile configures")
		var layout:=land_layout(profile)
		check(layout.count==[1070,894][index-1],"natural coast retains every filtered source land pixel: "+id)
	var accepted: Array=field.reference_profiles()
	var accepted_height: float=field.sample_height(-480,-60)
	for overrides: Variant in [false,{"unknown":{}},{"virgin_islands":false},{"virgin_islands":{"height_gain":NAN}},{"virgin_islands":{"harbor_land_half_width":0.0}},{"virgin_islands":{"harbor_land_half_width":30.0,"harbor_land_fade_width":10.0}},{"cat_island":{"sea_index":250.0}}]:
		var invalid:=options.duplicate(true);invalid.reference_art_by_profile=overrides
		check(not field.configure_ports(ports,true,invalid),"invalid per-profile art is rejected")
		check(field.reference_profiles()==accepted and field.sample_height(-480,-60)==accepted_height,"per-profile rejection preserves accepted terrain atomically")
	var merged:=Height.new()
	var merged_options:=options.duplicate(true)
	merged_options.reference_art={"harbor_land_half_width":6.0,"harbor_land_fade_width":4.0}
	merged_options.reference_art_by_profile={"virgin_islands":{"harbor_land_fade_width":25.0}}
	check(merged.configure_ports(ports,true,merged_options),"partial profile controls validate after merging with base art")
	if not merged.reference_profiles().is_empty():
		check(merged.reference_profiles()[2].harborLandHalfWidth==6.0 and merged.reference_profiles()[2].harborLandFadeWidth==25.0,"profile override inherits the base half width")
	var legacy:=Profile.new()
	var narrowed:=Profile.new()
	var supply: Dictionary=ports[2]
	var source: Dictionary=Profile.load_source("virgin_islands")
	var base_art: Dictionary=options.reference_art.duplicate()
	check(legacy.configure(supply,source,"virgin_islands",base_art),"legacy harbor baseline configures")
	check(narrowed.configure(supply,source,"virgin_islands",art_for(options,"virgin_islands")),"narrow positive harbor configures")
	var old_land:=land_layout(legacy)
	var new_land:=land_layout(narrowed)
	check(new_land.count<old_land.count-400,"supply apron no longer doubles the source archipelago land area")
	check(new_land.components.size()>=10 and new_land.components[0]<700,"outlying supply islands remain separate from the landing")
	var dock:=Vector2(float(supply.x),float(supply.z))
	var inward: Vector2=(Vector2(float(supply.islandX),float(supply.islandZ))-dock).normalized()
	var across:=Vector2(-inward.y,inward.x)
	for along: float in [-100.0,-40.0,0.0,12.0,20.0,25.0,30.0,35.0]:
		for lateral: float in [-34.0,-25.0,-18.0,-12.0,0.0,12.0,18.0,25.0,34.0]:
			var point:=dock+inward*along+across*lateral
			check(narrowed.sample_height(point.x,point.y)==legacy.sample_height(point.x,point.y),"negative-target harbor preserves original approach width/depth")
	for along: float in [43.0,47.5,54.0,55.0]:
		for lateral: float in [-5.0,0.0,5.0]:
			var point:=dock+inward*along+across*lateral
			var h: float=narrowed.sample_height(point.x,point.y)
			check(h>=2.0 and h<=2.41,"pier landing remains habitable across its ten metre footprint")
	# Densely sample the zero-target transition: narrowing must not introduce
	# the height jump produced by switching masks at target>0.
	var previous: float=narrowed.sample_height(dock.x+12.0,dock.y+35.0)
	for step in range(1,401):
		var h: float=narrowed.sample_height(dock.x+12.0,dock.y+35.0+step*.01)
		check(absf(h-previous)<.2,"positive apron width transitions continuously at sea level")
		previous=h
	var direct_default:=Profile.new()
	var explicit_default:=Profile.new()
	check(direct_default.configure(supply,source,"virgin_islands") and explicit_default.configure(supply,source,"virgin_islands",{"harbor_land_half_width":18.0,"harbor_land_fade_width":17.0}),"explicit legacy apron dimensions configure")
	for along: float in [0.0,20.0,35.0,40.0,54.0,75.0,90.0]:
		for lateral: float in [0.0,12.0,20.0,30.0,34.0]:
			var point:=dock+inward*along+across*lateral
			check(direct_default.sample_height(point.x,point.y)==explicit_default.sample_height(point.x,point.y),"omitted apron options preserve exact legacy behavior")
	print("PROFILE_ART_LAYOUT ",JSON.stringify({"before":old_land,"after":new_land}))
	print("REFERENCE_PROFILE_ART_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
