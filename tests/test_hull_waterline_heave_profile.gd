extends SceneTree
# Recorded original-hull fixtures; authored flagship has a separate water test.
const Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")
## Real six-model vertical hull rings; ray/triangle oracle is independent of
## the builder's height-plane edge intersections followed by Z sections.
const Ship=preload("res://game/presentation/ships/ship_view.gd")
const Profile=preload("res://game/presentation/ships/hull_waterline_profile.gd")
var assertions:=0
var failures:=0
func _initialize()->void:_run.call_deferred()
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _triangles(model:Node3D)->Array:
	var result:Array=[];var inverse:=model.global_transform.affine_inverse()
	for candidate:Node in model.find_children("*","MeshInstance3D",true,false):
		if str(candidate.get_meta("damage_surface",""))!="hull":continue
		var node:=candidate as MeshInstance3D
		if node.mesh==null:continue
		var transform:=inverse*node.global_transform
		for surface:int in node.mesh.get_surface_count():
			var arrays:Array=node.mesh.surface_get_arrays(surface)
			var points:PackedVector3Array=arrays[Mesh.ARRAY_VERTEX]
			var indices:PackedInt32Array=arrays[Mesh.ARRAY_INDEX]
			var count:=indices.size() if not indices.is_empty() else points.size()
			for start:int in range(0,count-2,3):
				var triangle:Array[Vector3]=[]
				for offset:int in 3:triangle.append(transform*points[indices[start+offset] if not indices.is_empty() else start+offset])
				result.append(triangle)
	return result
func _ray_extremes(triangles:Array,height:float,z:float)->Vector2:
	var left:=INF;var right:=-INF
	for triangle:Array in triangles:
		var a:Vector3=triangle[0];var ab:Vector3=triangle[1]-a;var ac:Vector3=triangle[2]-a
		var determinant:=float(ab.y)*ac.z-float(ab.z)*ac.y
		if absf(determinant)<0.00000001:continue
		var y:=height-a.y;var zz:=z-a.z
		var u:float=(y*ac.z-zz*ac.y)/determinant
		var v:float=(ab.y*zz-ab.z*y)/determinant
		if u<-.000001 or v<-.000001 or u+v>1.000001:continue
		var x:float=a.x+u*ab.x+v*ac.x
		left=minf(left,x);right=maxf(right,x)
	return Vector2(left,right)
func _ring(rows:Array,height:float)->Dictionary:
	for row:Dictionary in rows:
		if absf(float(row.height)-height)<.00000001:return row
	return {}
func _run()->void:
	# A derived interior height just below zero must not deduplicate away the
	# exact required zero ring or cause an unnecessary off-tree global read.
	var boundary_model:=Node3D.new();var boundary_mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new();box.size=Vector3(2.0,11.0,4.0)
	var boundary_array:=ArrayMesh.new();boundary_array.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,box.get_mesh_arrays())
	boundary_mesh.mesh=boundary_array;boundary_mesh.position.y=4.499995
	boundary_mesh.set_meta("damage_surface","hull");boundary_model.add_child(boundary_mesh)
	var boundary:Dictionary=Profile.build(boundary_model)
	var boundary_zero:=_ring(boundary.get("verticalSections",[]),0.0)
	check(not boundary_zero.is_empty(),"nearzero derived sampling never removes exact0 ring")
	if not boundary_zero.is_empty():check(is_same(boundary_zero.sections,boundary.sections),"nearzero sampling still reuses original Y0 sections")
	boundary_model.free()
	var timings:Array=[]
	for kind:String in Ship.KINDS:
		var actor:=Ship.new();root.add_child(actor)
		var start:=Time.get_ticks_usec();check(actor.configure(kind,null,Reference.new()),"actual model configures "+kind)
		var elapsed:=Time.get_ticks_usec()-start
		var profile:Dictionary=actor.source_water_attachment().surfaceProfile
		check(profile.has("verticalSections"),"actual cached profile exposes vertical rings "+kind)
		if not profile.has("verticalSections"):
			actor.dispose();actor.free();continue
		var rows:Array=profile.verticalSections
		check(rows.size()>=5 and rows.size()<=13,"bounded real height-ring count "+kind)
		var zero:=_ring(rows,0.0)
		check(not zero.is_empty(),"explicit height0 ring "+kind)
		if not zero.is_empty():check(is_same(zero.sections,profile.sections),"height0 reuses unchanged original sections array "+kind)
		var previous_height:=-INF
		for row:Dictionary in rows:
			check(is_finite(row.height) and row.height>previous_height,"sorted finite local ring heights")
			previous_height=row.height
			check(row.sections.size()>=2,"actual finite ring sections")
			var previous_z:=-INF
			for section:Dictionary in row.sections:
				check(is_finite(section.z) and is_finite(section.left) and is_finite(section.right),"finite actual vertical hull section")
				check(section.z>previous_z and section.right>=section.left,"ordered actual vertical hull section")
				previous_z=section.z
		var triangles:=_triangles(actor.get_model())
		for height:float in [-.5,0.0,.5]:
			var row:=_ring(rows,height)
			check(not row.is_empty(),"actual ring at heave reference height "+str(height)+" "+kind)
			if row.is_empty():continue
			var widest:=0.0
			for section:Dictionary in row.sections:widest=maxf(widest,section.right-section.left)
			check(widest>1.0,"heave ring crosses actual main hull "+kind)
			if kind=="fuchuan":check(widest<5.3,"vertical hull ring excludes rigging/sails, no broad bounds padding")
			for fraction:float in [.1,.25,.5,.75,.9]:
				var section:Dictionary=row.sections[roundi(float(row.sections.size()-1)*fraction)]
				var reference:=_ray_extremes(triangles,height,section.z)
				check(reference.is_finite(),"independent X ray intersects actual hull triangles")
				check(absf(section.left-reference.x)<.00015 and absf(section.right-reference.y)<.00015,"ring matches independent triangle ray, no approximate padding "+kind)
		var lower:=_ring(rows,-.5);var upper:=_ring(rows,.5)
		check(lower.sections!=upper.sections,"heave slices are real differing cross sections "+kind)
		var cached:Array=rows
		actor.apply_snapshot({"id":"audit","kind":kind,"time":100.0,"hull":100.0,"sailDeployment":1.0,"visual":{"position":{"x":20.0,"y":1.0,"z":10.0},"heading":.4,"pitch":.2,"heel":.15}}, {},0.0)
		check(is_same(cached,actor.source_water_attachment().surfaceProfile.verticalSections),"heave/pitch/heel/time use cached model-local geometry "+kind)
		timings.append({"kind":kind,"configureMicroseconds":elapsed,"heights":rows.map(func(r):return r.height),"ringCount":rows.size()})
		actor.dispose();actor.free()
	print("HULL_WATERLINE_HEAVE_PROFILE_EVIDENCE ",JSON.stringify(timings))
	print("HULL_WATERLINE_HEAVE_PROFILE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
