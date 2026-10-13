extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL ",label)
func _initialize()->void:
	call_deferred("run")
func run()->void:
	check(FileAccess.file_exists("res://modules/scene_engine/fidelity_fx/source_shadow_assets/ship_shadow.dds.bin"),"original DDS bytes use export-included bin suffix")
	if not ResourceLoader.exists("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd"):
		check(false,"renderer lifecycle is absent");quit(1);return
	var renderer=load("res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd").new()
	var parent:=Node3D.new();root.add_child(parent)
	var camera:=Camera3D.new();parent.add_child(camera)
	var capability:Dictionary=renderer.configure(parent,camera)
	check(capability.has("nativePixelEquivalent") and not capability.nativePixelEquivalent,"honest GPU scope")
	var actor:=Node3D.new();parent.add_child(actor)
	var caster:Dictionary={"id":"c","actorId":"a","positions":[[0,0,0],[1,0,0],[0,1,0]],"edges":[[0,1],[1,2],[2,0]],"capIndices":[0,1,2],"localLight":[0,0,-1],"worldRotation":[1,0,0,0,1,0,0,0,1]}
	var packet:Dictionary={"sourceShadows":{"casters":[caster]}}
	renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().volumeCount==1,"registered caster")
	var first:int=renderer.diagnostics().rebuildCount
	renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().rebuildCount==first,"repeat no rebuild")
	actor.position=Vector3(5,2,7);renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().rebuildCount==first,"translation updates without rebuild")
	caster.localLight=[1,0,0];renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().rebuildCount==first+1,"direction rebuild")
	caster.worldRotation=[0.9999619126319885,-0.008726535364985466,0,0.008726535364985466,0.9999619126319885,0,0,0,1]
	renderer.apply_snapshot(packet,{"a":actor})
	caster.worldRotation=[0.9998477101325989,-0.017452405765652657,0,0.017452405765652657,0.9998477101325989,0,0,0,1]
	renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().rebuildCount==first+2,"rotation compares last volume rotation not last frame")
	caster.actor144=true;renderer.apply_snapshot(packet,{"a":actor})
	check(renderer.diagnostics().volumeCount==0,"gate removes live volume")
	caster.actor144=false;renderer.apply_snapshot(packet,{})
	check(renderer.diagnostics().volumeCount==0,"missing actor removes live volume")
	var plane:Node3D=renderer.attach_ship_texture_plane(actor,"fluyt")
	check(plane!=null and plane.get_child_count()==1,"original parent hierarchy")
	var shadow_mesh:MeshInstance3D=plane.get_node("Scene Root/dummy_fluyt/dummy_fluyt NonAccum/ship_shadow_plane")
	var mesh_arrays:Array=shadow_mesh.mesh.surface_get_arrays(0)
	check(mesh_arrays[Mesh.ARRAY_NORMAL]!=null and mesh_arrays[Mesh.ARRAY_NORMAL].size()==4,"source normals retained")
	check(mesh_arrays[Mesh.ARRAY_TEX_UV][0].is_equal_approx(Vector2(0.9995005130767822,0.0004995465278625488)),"authored UV retained")
	check(shadow_mesh.position.is_equal_approx(Vector3(-2.7202301025390625,35.808349609375,-40.82020568847656)),"authored plane TRS retained")
	check(renderer.attach_ship_texture_plane(actor,"sloop")==null,"no invented other ship shadow")
	check(renderer.attach_ship_texture_plane(actor,"fluyt")==plane,"attachment idempotent")
	renderer.dispose();renderer.dispose()
	check(renderer.diagnostics().volumeCount==0,"dispose releases volume")
	check(is_instance_valid(actor),"unowned actor survives dispose")
	parent.free()
	print("SOURCE_SHADOW_RENDERER failures=",failures)
	quit(1 if failures else 0)
