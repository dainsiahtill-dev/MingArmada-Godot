extends SceneTree
## R12 is research-only; loads actual three LOD GLBs and original damage path.
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const Provider=preload("res://game/research/fixtures/hero_palette_provider.gd")
const Formal=preload("res://modules/scene_engine/assets/hero_ship_provider.gd")
const Damage=preload("res://game/presentation/ships/ship_damage.gd")
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok
func run()->void:
	var demo=Experiment.new();root.add_child(demo)
	var result:Dictionary=demo.configure({"model":"art_r12","animated":false,"paused":true,"shadows":"authored"})
	check(result.get("ok",false),"R12 research scene configures")
	var choices:Array=demo.control_spec().filter(func(row):return row.id=="model")[0].choices
	check(choices.any(func(choice):return choice.value=="art_r12"),"laboratory exposes R12")
	check(demo.set_parameter("model","art_r12").get("ok",false),"laboratory accepts R12 choice")
	if result.get("ok",false):check(demo._ship.get_model().get_meta("source_path","").contains("hero_fuchuan_v3_r12/fuchuan-lod0.glb"),"demo loads R12 LOD0")
	var prior:=Provider.new("art_r6",true,"r7c")
	var candidate:=Provider.new("art_r6",true,"r12")
	for lod in range(3):
		var old:Node3D=prior.instantiate_ship("fuchuan",lod)
		var model:Node3D=candidate.instantiate_ship("fuchuan",lod)
		check(old!=null,"R7c remains loadable LOD%d"%lod)
		if not check(model!=null,"R12 provider loads LOD%d"%lod):
			if old:old.free()
			continue
		check(model.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r12/fuchuan-lod%d.glb"%lod,"R12 source identity LOD%d"%lod)
		check(model.get_meta("art_revision",0)==12,"R12 revision metadata")
		var damage=Damage.new();damage.configure([model])
		for index in range(3):
			var sail:=model.find_child("sail_%d"%index,true,false) as MeshInstance3D
			var old_sail:=old.find_child("sail_%d"%index,true,false) as MeshInstance3D if old else null
			if not check(sail!=null and old_sail!=null,"named sail%d LOD%d"%[index,lod]):continue
			check(sail.mesh.get_blend_shape_count()==2 and sail.mesh.get_blend_shape_name(0)=="furl" and sail.mesh.get_blend_shape_name(1)=="inflate","sail morph names retained")
			var found:=false
			for surface in sail.mesh.get_surface_count():
				var material=sail.mesh.surface_get_material(surface)
				if material is StandardMaterial3D and material.resource_name=="canvas":
					found=true
					var geometry:PackedVector3Array=sail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var old_geometry:PackedVector3Array=old_sail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX]
					var colors:PackedColorArray=sail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
					var old_colors:PackedColorArray=old_sail.mesh.surface_get_arrays(surface)[Mesh.ARRAY_COLOR]
					check(geometry.size()>0 and geometry.size()==old_geometry.size() and geometry!=old_geometry,"R12 actual canvas geometry changes")
					check(colors.size()>0 and colors==old_colors,"R12 canvas colors remain R7c")
					check(material.vertex_color_use_as_albedo,"canvas consumes vertex colors")
					var active=sail.get_active_material(surface)
					check(active is ShaderMaterial and active.get_shader_parameter("use_original_vertex_color")==true,"damage shader consumes canvas colors")
			check(found,"canvas material binding preserved")
		damage.dispose();model.free()
		if old:old.free()
	var formal:=Formal.new();var baseline:Node3D=formal.instantiate_ship("fuchuan",0)
	check(baseline!=null and baseline.get_meta("source_path","").contains("hero_fuchuan_v3_r7c"),"formal default remains R7c")
	if baseline:baseline.free()
	demo.dispose();demo.free()
	print("HERO_R12_EXPERIMENT_TEST assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
