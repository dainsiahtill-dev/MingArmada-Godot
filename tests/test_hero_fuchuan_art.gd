extends "res://tests/test_hero_fuchuan.gd"
const Art=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
func make_provider()->RefCounted:return Art.new("art_r6")
func finish()->void:
	var provider:=make_provider()
	var model:Node3D=provider.instantiate_ship("fuchuan",0)
	check(model!=null,"art model available for gunport clearance")
	if model:
		root.add_child(model)
		check(model.get_meta("texture_style","")=="art_v3_imagegen","art revision remains observable")
		var hull:MeshInstance3D=model.find_child("hull",true,false)
		for side:String in ["port","starboard"]:
			for index in 4:
				var socket:Node3D=model.find_child("socket_smoke_%s_%02d"%[side,index],true,false)
				var origin:=Vector3(0,2.2,socket.global_position.z)
				check(not _blocked(hull,origin,socket.global_position+Vector3(1 if side=="port" else -1,0,0)),"each authoritative cannon axis crosses a real opening, not a solid hull panel")
		model.free()
	for lod in 3:
		var refined:Node3D=provider.instantiate_ship("fuchuan",lod);root.add_child(refined)
		var transom:=refined.find_child("stern_transom",true,false) as MeshInstance3D
		check(transom!=null,"refined aft wall has a distinct structural surface LOD"+str(lod))
		if transom:
			check(transom.mesh.get_aabb().size.z>.28,"aft shoulders turn forward rather than remain a flat wall")
			check(transom.get_meta("deck_obstacle",false),"structural aft wall remains a crew obstacle")
		var cabin:=refined.find_child("sterncastle",true,false) as MeshInstance3D
		var fittings:=refined.find_child("deck_fittings",true,false) as MeshInstance3D
		var deck:=refined.find_child("deck",true,false) as MeshInstance3D
		var unique:Dictionary={}
		for surface in deck.mesh.get_surface_count():
			for point:Vector3 in deck.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if absf(point.z)<.10 and point.y<3.0 and absf(point.x)<.6:unique[point.x]=true
		var xs:Array=unique.keys();xs.sort();var smallest:=INF
		for i in range(1,xs.size()):
			var delta:float=float(xs[i])-float(xs[i-1])
			if delta>.0001:smallest=minf(smallest,delta)
		check(smallest<=.005,"authored narrow caulk joints avoid the old 16mm dark-gap pattern LOD"+str(lod))
		for side in [-1,1]:
			for center in [-14.4,-12.9,-11.4,-9.9]:
				var a:=Vector3(side*6,3.74,center+.06);var b:=Vector3(side,3.74,center+.06)
				check(not _blocked(cabin,a,b),"side window is a real opening in the cabin wall")
				var pane:Variant=_nearest_hit(fittings,a,b)
				var frame:Variant=_nearest_hit(fittings,a+Vector3(0,0,.30),b+Vector3(0,0,.30))
				check(pane is Vector3 and frame is Vector3 and side*(frame.x-pane.x)>.06 and side*(frame.x-pane.x)<.22,"window backing is physically inset behind its frame")
		var blade:=refined.find_child("rudder_blade",true,false) as MeshInstance3D
		var leading:=0.0;var trailing:=0.0
		for surface in blade.mesh.get_surface_count():
			for point:Vector3 in blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
				if point.z>-.25:leading=maxf(leading,absf(point.x))
				if point.z<-1.55:trailing=maxf(trailing,absf(point.x))
		check(leading>.08 and trailing/leading<.55,"rudder working section thins toward trailing edge LOD"+str(lod))
		var box:AABB=blade.mesh.get_aabb()
		check(box.position.y>=-3.251 and box.end.y<=.801 and box.position.z>=-1.801 and box.end.z<=.101,"rounded rudder remains in its original control envelope")
		if lod==2 and transom:
			var neck:=Vector3.ZERO;var found:=false
			for surface in blade.mesh.get_surface_count():
				for point:Vector3 in blade.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]:
					if point.y>.5 and (not found or point.z>neck.z):neck=point;found=true
			var pivot:Node3D=refined.find_child("rudder_pivot",true,false)
			var hull:MeshInstance3D=refined.find_child("hull",true,false)
			for angle in [-.48,0.0,.48]:
				pivot.rotation.y=angle
				var sample:=pivot.to_global(neck);var aft:=sample+Vector3(0,0,-2)
				check(found and not _blocked(hull,sample,aft) and not _blocked(transom,sample,aft),"upper blade clears the raked stern across steering angles "+str(angle))
		refined.free()
	print("HERO_FUCHUAN_ART_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _blocked(mesh:MeshInstance3D,start:Vector3,end:Vector3)->bool:
	var a:=mesh.to_local(start);var b:=mesh.to_local(end)
	for surface in mesh.mesh.get_surface_count():
		var arrays:Array=mesh.mesh.surface_get_arrays(surface)
		var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
		var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			if Geometry3D.segment_intersects_triangle(a,b,points[indices[i]],points[indices[i+1]],points[indices[i+2]])!=null:return true
	return false
func _nearest_hit(mesh:MeshInstance3D,start:Vector3,end:Vector3)->Variant:
	var a:=mesh.to_local(start);var b:=mesh.to_local(end);var result:Variant=null;var distance:=INF
	for surface in mesh.mesh.get_surface_count():
		var arrays:Array=mesh.mesh.surface_get_arrays(surface);var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX];var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
		for i in range(0,indices.size(),3):
			var hit:Variant=Geometry3D.segment_intersects_triangle(a,b,points[indices[i]],points[indices[i+1]],points[indices[i+2]])
			if hit is Vector3 and a.distance_squared_to(hit)<distance:result=mesh.to_global(hit);distance=a.distance_squared_to(hit)
	return result
