extends SceneTree
const Library=preload("res://modules/scene_engine/assets/asset_library.gd")
const Deck=preload("res://game/presentation/crew/deck_stations.gd")
const Waterline=preload("res://game/presentation/ships/hull_waterline_profile.gd")
const PATH="res://modules/scene_engine/assets/hero_ship_provider.gd"
var assertions:=0
var failures:=0
func check(value:bool,reason:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",reason)
func _initialize()->void:run.call_deferred()
func make_provider()->RefCounted:return load(PATH).new()
func finish()->void:
	print("HERO_FUCHUAN_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func run()->void:
	check(ResourceLoader.exists(PATH),"dedicated authored ship provider exists")
	if not ResourceLoader.exists(PATH):finish();return
	var provider:RefCounted=make_provider()
	var library:=Library.new()
	for lod in 3:
		var model:Node3D=provider.instantiate_ship("fuchuan",lod,library)
		check(model!=null,"GLB loads for LOD "+str(lod))
		if model==null:continue
		root.add_child(model)
		check(model.get_meta("model_origin","")=="blender_authored","original authorship is observable")
		var hull:=model.find_child("hull",true,false) as MeshInstance3D
		check(hull!=null and hull.mesh!=null,"actual ship hull exists")
		if hull:
			var bounds:=hull.mesh.get_aabb()
			check(bounds.size.z>=31.9 and bounds.size.z<=32.3,"32m hull retained independently of mast/cannon extents")
			check(bounds.size.x>=8.8 and bounds.size.x<=9.3,"9m hull beam")
			check(bounds.position.y < -1.8 and bounds.end.y>1.85,"hull crosses real waterline")
		var water:=Waterline.build(model)
		check(not water.is_empty() and water.get("sections",[]).size()>4,"new authored hull provides sampled water contact contour")
		var deck:=Deck.new()
		check(deck.configure("fuchuan",model),"actual deck supports crew stations")
		check(not deck.sample(0,0).is_empty(),"centre deck physically supports crew")
		var helms:Array=deck.stations.filter(func(s:Dictionary)->bool:return s.role=="helm")
		check(helms.size()==1 and helms[0].position.y>4.2,"helmsman stands on the authored upper steering deck")
		for index in 3:
			check(model.find_child("mast_%d"%index,true,false)!=null,"separate mast pivot")
			var cloth:=model.find_child("sail_%d"%index,true,false) as MeshInstance3D
			check(cloth!=null and cloth.mesh.get_blend_shape_count()==2,"sail and battens carry furl/inflate morphs")
			if cloth:
				check(cloth.mesh.get_blend_shape_name(0)=="furl" and cloth.mesh.get_blend_shape_name(1)=="inflate","runtime morph identities retained")
				for surface in cloth.mesh.get_surface_count():
					if cloth.mesh.surface_get_material(surface).resource_name!="canvas":continue
					var uvs:PackedVector2Array=cloth.mesh.surface_get_arrays(surface)[Mesh.ARRAY_TEX_UV]
					var normalized:=not uvs.is_empty();var spread:=Rect2(uvs[0],Vector2.ZERO)
					for uv in uvs:
						normalized=normalized and uv.x>=-.001 and uv.y>=-.001 and uv.x<=1.001 and uv.y<=1.001
						spread=spread.expand(uv)
					check(normalized and spread.size.x>.99 and spread.size.y>.99,"sail damage UV spans the complete 0-1 cloth instead of clamping an edge")
		check(model.find_child("rudder_pivot",true,false)!=null and model.find_child("tiller_beam",true,false)!=null,"separate rudder and tiller components")
		for side:String in ["port","starboard"]:
			for index in 4:
				var socket:=model.find_child("socket_smoke_%s_%02d"%[side,index],true,false) as Node3D
				var barrel:=model.find_child("barrel_%s_%02d"%[side,index],true,false) as Node3D
				check(socket!=null and barrel!=null,"eight functional battery sockets and recoil pivots")
				if socket:
					var z:=32.0*(-.138+index*.092)
					var x:=9.0*.435*pow(1.0-pow(z/16.0,2),.64)+.87
					check(socket.global_position.distance_to(Vector3(x if side=="port" else -x,2.2,z))<.001,"authored muzzle agrees with authoritative broadside")
		var other:Node3D=provider.instantiate_ship("fuchuan",lod,library)
		check(other!=null and other!=model,"cached resource creates independent ship instances")
		if other:
			var a:=model.find_child("sail_0",true,false) as MeshInstance3D
			var b:=other.find_child("sail_0",true,false) as MeshInstance3D
			a.set_blend_shape_value(0,.75)
			check(b.get_blend_shape_value(0)==0,"reefing one ship never changes another ship")
			other.free()
		model.free()
	check(provider.instantiate_ship("fuchuan",9,library)==null,"invalid LOD rejected")
	library.dispose()
	check(provider.instantiate_ship("fuchuan",0,library)==null,"disposed library cannot manufacture a new ship")
	await process_frame
	finish()
