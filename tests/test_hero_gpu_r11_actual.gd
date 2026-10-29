extends SceneTree
## Real R11 3 LOD × 5 deployments. CPU node/mesh state only, never GPU proof.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
const Experiment=preload("res://game/research/demos/hero_fuchuan_experiment.gd")
const WIND={"direction":{"x":1.0,"y":0.0},"speed":14.0}
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->bool:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)
	return ok

func run()->void:
	var gate=Gate.new()
	var ready:=check(gate.has_method("lod_evidence"),"actual selected LOD source and visibility can be verified")
	ready=check(gate.has_method("deployment_evidence"),"canvas and battens can be verified for each deployment") and ready
	if ready:
		var demo=Experiment.new()
		check(demo.configure({"model":"art_r11","shadows":"authored","animated":false}).ok,"R11 experiment configures")
		root.add_child(demo)
		var original:Dictionary=demo.inspection_snapshot()
		var fixed:Dictionary=original.snapshot.duplicate(true)
		fixed.sailAngle=0.0;fixed.rudder=0.35
		for lod in 3:
			demo._ship.set_lod_distance([0.0,220.0,650.0][lod])
			check(gate.lod_evidence(demo,"art_r11",lod).ok,"actual LOD%d is selected"%lod)
			var active:Node=demo._ship.get_model()
			var original_path:Variant=active.get_meta("source_path")
			active.set_meta("source_path","res://assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb")
			check(not gate.lod_evidence(demo,"art_r11",lod).ok,"wrong active LOD source is rejected")
			active.set_meta("source_path",original_path)
			for deployment:float in [0.0,0.25,0.5,0.75,1.0]:
				var state:=fixed.duplicate(true);state.sailDeployment=deployment
				demo._ship.apply_snapshot(state,WIND,0)
				demo._rigid.compose({}, {"hero":demo._ship}, -demo._sun.global_basis.z,true,true)
				check(gate.caster_evidence(demo,"art_r11","authored").ok,"LOD%d deployment %.2f retains all five authored proxies"%[lod,deployment])
				var pose:Dictionary=gate.deployment_evidence(demo,"art_r11",state,WIND,-14.0/18.0*deployment)
				check(pose.ok,"LOD%d deployment %.2f binds canvas and battens to the same applied morph: %s"%[lod,deployment,str(pose.get("errors",[]))])
				if deployment==0.5:
					var wrong_wind:=WIND.duplicate(true);wrong_wind.speed=15.0
					check(not gate.deployment_evidence(demo,"art_r11",state,wrong_wind,-14.0/18.0*deployment).ok,"different wind is rejected")
					var wrong_snapshot:=state.duplicate(true);wrong_snapshot.rudder=-0.35
					check(not gate.deployment_evidence(demo,"art_r11",wrong_snapshot,WIND,-14.0/18.0*deployment).ok,"different accepted snapshot is rejected")
					var sail:=active.find_child("sail_0",true,false) as MeshInstance3D
					if check(sail!=null,"actual active sail exists"):
						var role:Dictionary={}
						for item:Dictionary in demo._ship.get("_pose_sails"):
							if item.node==sail:role=item;break
						var furl:=int(role.get("furl",-1))
						if check(furl>=0,"actual furl morph exists"):
							var saved:=sail.get_blend_shape_value(furl);sail.set_blend_shape_value(furl,saved+0.2)
							check(not gate.deployment_evidence(demo,"art_r11",state,WIND,-14.0/18.0*deployment).ok,"incorrect real morph weight is rejected")
							sail.set_blend_shape_value(furl,saved)
						var inflate:=int(role.get("inflate",-1))
						if check(inflate>=0,"actual inflation morph exists"):
							var saved:=sail.get_blend_shape_value(inflate);sail.set_blend_shape_value(inflate,saved+0.2)
							check(not gate.deployment_evidence(demo,"art_r11",state,WIND,-14.0/18.0*deployment).ok,"incorrect real inflation weight is rejected")
							sail.set_blend_shape_value(inflate,saved)
						var original_mesh:=sail.mesh
						var altered:=original_mesh.duplicate() as ArrayMesh
						if check(altered!=null,"actual sail mesh can be isolated for a failure fixture"):
							for surface in range(altered.get_surface_count()-1,-1,-1):
								var material:=altered.surface_get_material(surface)
								if material!=null and material.resource_name=="bamboo":altered.surface_remove(surface)
							sail.mesh=altered
							check(not gate.deployment_evidence(demo,"art_r11",state,WIND,-14.0/18.0*deployment).ok,"missing batten surface is rejected")
							sail.mesh=original_mesh
			for health:float in [100.0,80.0,60.0,30.0]:
				var damaged:=fixed.duplicate(true);damaged.sail=health;damaged.sailDeployment=1.0
				demo._ship.apply_snapshot(damaged,WIND,0)
				var color:Dictionary=gate.canvas_color_evidence(demo)
				check(color.ok and color.sails.size()==3,"LOD%d health %.0f preserves actual canvas vertex color and albedo: %s"%[lod,health,str(color.errors)])
			if lod==0:
				var active_shader:ShaderMaterial=null
				for entry:Dictionary in demo._ship.get("_damage").get("_materials"):
					if entry.sail and entry.node.is_visible_in_tree():active_shader=entry.material;break
				if check(active_shader!=null,"visible canvas damage shader found"):
					active_shader.set_shader_parameter("use_original_vertex_color",false)
					check(not gate.canvas_color_evidence(demo).ok,"disabled actual canvas vertex color is rejected")
					active_shader.set_shader_parameter("use_original_vertex_color",true)
		var reset:Dictionary=demo.reset_experiment({"animated":false,"paused":false})
		check(reset.ok and demo.inspection_snapshot()==original,"reset restores original experiment snapshot")
		check(gate.lod_evidence(demo,"art_r11",0).ok,"reset restores LOD0 and its original source")
		check(gate.pose_evidence(demo,"art_r11",original.snapshot).ok,"reset restores original sail and rudder poses")
		demo.dispose();demo.free()
	print("HERO_GPU_R11_ACTUAL assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
