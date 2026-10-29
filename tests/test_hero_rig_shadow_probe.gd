extends SceneTree
const PATH="res://game/research/fixtures/hero_rig_shadow_probe.gd"
var assertions:=0
var failures:=0
func check(value:bool,why:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL rig probe: ",why)
func _initialize()->void:run.call_deferred()
func run()->void:
	check(ResourceLoader.exists(PATH),"reversible diagnostic controller exists")
	if ResourceLoader.exists(PATH):
		var actor:=Node3D.new();root.add_child(actor)
		var nodes:Array[MeshInstance3D]=[]
		for label:String in ["hull","rigging_0","sail_0","deck"]:
			var mesh:=MeshInstance3D.new();mesh.name=label;mesh.mesh=BoxMesh.new();mesh.position=Vector3(2,3,4)
			var material:=StandardMaterial3D.new();material.albedo_color=Color(.3,.4,.5);mesh.material_override=material
			actor.add_child(mesh);nodes.append(mesh)
		nodes[0].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		nodes[1].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		nodes[3].cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var hull_proxy:=BoxMesh.new();var deck_proxy:=BoxMesh.new()
		nodes[0].set_meta("target_shadow_geometry",hull_proxy);nodes[3].set_meta("target_shadow_geometry",deck_proxy)
		var sun:=DirectionalLight3D.new();root.add_child(sun);sun.shadow_enabled=true
		var effect:=CompositorEffect.new();effect.enabled=true
		var probe:RefCounted=load(PATH).new()
		check(probe.configure(actor,sun,effect).ok,"real scene configured")
		var resources:Array=[]
		for mesh:MeshInstance3D in nodes:resources.append([mesh.mesh,mesh.material_override,mesh.transform,mesh.visible])
		check(probe.apply("native_off").ok and not sun.shadow_enabled and effect.enabled,"native-off keeps compositor active")
		check(probe.apply("rig_cast_off").ok and sun.shadow_enabled and effect.enabled,"factor switch restores native light first")
		check(nodes[1].cast_shadow==0 and nodes[0].cast_shadow==0 and nodes[2].cast_shadow==1,"rig-only changes correct caster group")
		check(probe.apply("sail_cast_off").ok and nodes[1].cast_shadow==2 and nodes[2].cast_shadow==0,"sail-only restores exact rig enum")
		check(probe.apply("stencil_off").ok and not effect.enabled and sun.shadow_enabled,"stencil-only keeps native light active")
		check(nodes[0].cast_shadow==0 and nodes[1].cast_shadow==2 and nodes[2].cast_shadow==1,"stencil-only preserves all native caster enums")
		var before:Dictionary=probe.inspection()
		check(not probe.apply("invalid").ok and probe.inspection()==before,"invalid factor preserves current state")
		check(probe.apply("baseline").ok and effect.enabled and sun.shadow_enabled,"baseline restores both shadow routes")
		check(probe.apply("deck_visible").ok and nodes[3].get_meta("target_shadow_geometry")==nodes[3].mesh and nodes[0].get_meta("target_shadow_geometry")==hull_proxy,"deck input replacement preserves other proxy")
		check(probe.apply("hull_visible").ok and nodes[0].get_meta("target_shadow_geometry")==nodes[0].mesh and nodes[3].get_meta("target_shadow_geometry")==deck_proxy,"hull input replacement restores deck proxy")
		check(probe.apply("deck_down4mm").ok,"bounded deck proxy displacement available")
		var shifted:Mesh=nodes[3].get_meta("target_shadow_geometry")
		if shifted!=deck_proxy:
			var original:Array=deck_proxy.surface_get_arrays(0);var candidate:Array=shifted.surface_get_arrays(0)
			check(absf(candidate[Mesh.ARRAY_VERTEX][0].y-original[Mesh.ARRAY_VERTEX][0].y+.004)<.000001,"deck proxy vertices move exactly four millimetres")
			check(candidate[Mesh.ARRAY_NORMAL]==original[Mesh.ARRAY_NORMAL] and candidate[Mesh.ARRAY_INDEX]==original[Mesh.ARRAY_INDEX],"proxy translation preserves topology and normals")
		probe.apply("deck_down4mm")
		check(nodes[3].get_meta("target_shadow_geometry")==shifted,"repeated factor reuses derived resource")
		check(probe.apply("hull_down35mm").ok,"bounded hull proxy displacement available")
		check(probe.apply("baseline").ok and nodes[0].get_meta("target_shadow_geometry")==hull_proxy and nodes[3].get_meta("target_shadow_geometry")==deck_proxy,"baseline restores exact original proxy resources")
		for index in nodes.size():
			var mesh:MeshInstance3D=nodes[index]
			check([mesh.mesh,mesh.material_override,mesh.transform,mesh.visible]==resources[index],"factor preserves actual geometry/material/pose/visibility")
		probe.apply("native_off");probe.dispose()
		check(sun.shadow_enabled and effect.enabled and nodes[1].cast_shadow==2,"dispose restores owner state")
		check(probe.inspection().get("meshCount",-1)==0,"dispose releases held mesh references")
		check(probe.configure(actor,sun).ok,"native-only scene can be probed")
		probe.apply("native_off");before=probe.inspection()
		check(not probe.apply("stencil_off").ok and probe.inspection()==before,"absent compositor rejects without changing native factor")
		probe.dispose();actor.free();sun.free()
		var demo:Node3D=load("res://game/research/demos/hero_fuchuan_experiment.gd").new()
		check(demo.configure({"model":"art_r7c","animated":false,"paused":true,"rig_probe":"native_off"}).ok,"existing lab accepts explicit diagnostic preset")
		root.add_child(demo)
		check(not demo.get("_sun").shadow_enabled,"native diagnostic preset takes effect after scene build")
		var snapshot:Dictionary=demo.inspection_snapshot()
		demo.advance(2.0)
		check(demo.inspection_snapshot()==snapshot,"paused diagnostic does not advance accepted state")
		check(demo.set_parameter("rig_probe","baseline").ok and demo.get("_sun").shadow_enabled,"lab can restore original native projection")
		snapshot=demo.inspection_snapshot()
		check(not demo.set_parameter("rig_probe","stencil_off").ok and demo.inspection_snapshot()==snapshot,"lab rejects absent stencil without changing parameters")
		demo.set_parameter("rig_probe","rig_cast_off")
		snapshot=demo.inspection_snapshot();var owner_id:int=demo.get("_ship").get_instance_id()
		check(not demo.configure({"model":"art_r7c","shadows":"native","rig_probe":"deck_visible"}).ok,"incompatible native proxy preset rejected")
		check(demo.inspection_snapshot()==snapshot and demo.get("_ship").get_instance_id()==owner_id,"failed live preset preserves actor parameters and factor")
		check(demo.reset_experiment({"rig_probe":"baseline"}).ok and demo.get("_sun").shadow_enabled,"reset reconstructs baseline projection")
		demo.dispose();demo.free()
		var pending:Node3D=load("res://game/research/demos/hero_fuchuan_experiment.gd").new()
		pending.configure({"model":"art_r7c","shadows":"authored","paused":true})
		snapshot=pending.inspection_snapshot()
		check(not pending.configure({"model":"art_r7c","shadows":"visible","rig_probe":"hull_down35mm"}).ok and pending.inspection_snapshot()==snapshot,"visible mode proxy preset rejects before pending state mutation")
		check(not pending.configure({"model":"baseline","shadows":"authored","rig_probe":"deck_visible"}).ok and pending.inspection_snapshot()==snapshot,"unavailable model proxy rejects before pending state mutation")
		pending.dispose();pending.free()
	print("HERO_RIG_SHADOW_PROBE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
