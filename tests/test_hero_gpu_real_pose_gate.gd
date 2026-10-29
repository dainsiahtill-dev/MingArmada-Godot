extends SceneTree
## Actual R8b actors in headless mode. This tests binding and pose, not GPU.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: run.call_deferred()
func check(value:bool,detail:String)->void:
	assertions+=1
	if not value:failures+=1;printerr("FAIL: ",detail)

func run()->void:
	var gate=Gate.new()
	check(gate.has_method("caster_evidence"),"production evidence gate can inspect real caster binding")
	check(gate.has_method("pose_evidence"),"production evidence gate can inspect real active sail/rudder pose")
	if gate.has_method("caster_evidence") and gate.has_method("pose_evidence"):
		var demo=Experiment.new()
		check(demo.configure({"model":"art_r8b","shadows":"authored","animated":false}).ok,"R8b research model configures")
		root.add_child(demo)
		var actual:Node=demo._ship.get_model()
		check(is_instance_valid(actual) and actual.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r8b/fuchuan-lod0.glb","actual selected model is R8b LOD0")
		for lod in 3:
			var lod_node:Node=demo._ship.get_node_or_null("LOD%d"%lod)
			check(lod_node!=null and lod_node.get_meta("source_path","")=="res://assets/models/hero_fuchuan_v3_r8b/fuchuan-lod%d.glb"%lod,"actual actor binds distinct R8b LOD%d source"%lod)
		if is_instance_valid(actual):
			check(not gate.caster_evidence(demo,"art_r8b","authored").ok,"headless native fallback is not accepted as stencil handoff")
			# This is a controlled CPU handoff state, not a GPU rendering claim.
			demo._rigid.compose({}, {"hero":demo._ship}, -demo._sun.global_basis.z,true,true)
			var caster:Dictionary=gate.caster_evidence(demo,"art_r8b","authored")
			check(caster.ok and caster.casters.size()==5,"actual five proxy casters satisfy handoff contract")
			var hull:=actual.find_child("hull",true,false) as MeshInstance3D
			if hull:
				var original_mode:=hull.cast_shadow
				hull.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON
				check(not gate.caster_evidence(demo,"art_r8b","authored").ok,"native fallback on one caster is rejected")
				hull.cast_shadow=original_mode
				var original:Variant=hull.get_meta("target_shadow_geometry")
				hull.set_meta("target_shadow_geometry",hull.mesh)
				check(not gate.caster_evidence(demo,"art_r8b","authored").ok,"visible mesh substituted for authored proxy is rejected")
				hull.set_meta("target_shadow_geometry",original)
			else:check(false,"real hull caster exists")
			demo.set_parameter("animated",true);demo.advance(1.0/32.0)
			var snapshot:Dictionary=demo.inspection_snapshot().snapshot
			check(gate.pose_evidence(demo,"art_r8b",snapshot).ok,"actual sail and rudder match the new snapshot")
			var sails:Array=demo._ship.get("_pose_sails")
			var sail:MeshInstance3D
			var index:=-1
			for item:Dictionary in sails:
				if is_instance_valid(item.node) and item.node.is_visible_in_tree() and int(item.furl)>=0:
					sail=item.node;index=int(item.furl);break
			if sail:
				var prior:=sail.get_blend_shape_value(index)
				sail.set_blend_shape_value(index,prior+0.2)
				check(not gate.pose_evidence(demo,"art_r8b",snapshot).ok,"stale sail geometry is rejected")
				sail.set_blend_shape_value(index,prior)
			else:check(false,"actual active sail exists")
			var pivot:=actual.find_child("rudder_pivot",true,false) as Node3D
			if pivot:
				var prior:=pivot.rotation.y;pivot.rotation.y=prior+0.2
				check(not gate.pose_evidence(demo,"art_r8b",snapshot).ok,"stale rudder pose is rejected")
				pivot.rotation.y=prior
			else:check(false,"actual active rudder exists")
		demo.dispose();demo.free()
	print("HERO_GPU_REAL_POSE_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
