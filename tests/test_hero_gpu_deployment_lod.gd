extends SceneTree
## Real R9b 3 LOD × 5 deployments. CPU node/mesh state only, never GPU proof.
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
		check(demo.configure({"model":"art_r9b","shadows":"authored","animated":false}).ok,"R9b experiment configures")
		root.add_child(demo)
		var original:Dictionary=demo.inspection_snapshot()
		var fixed:Dictionary=original.snapshot.duplicate(true)
		fixed.sailAngle=0.0;fixed.rudder=0.35
		for lod in 3:
			demo._ship.set_lod_distance([0.0,220.0,650.0][lod])
			check(gate.lod_evidence(demo,"art_r9b",lod).ok,"actual LOD%d is selected"%lod)
			var active:Node=demo._ship.get_model()
			var original_path:Variant=active.get_meta("source_path")
			active.set_meta("source_path","res://assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb")
			check(not gate.lod_evidence(demo,"art_r9b",lod).ok,"wrong active LOD source is rejected")
			active.set_meta("source_path",original_path)
			for deployment:float in [0.0,0.25,0.5,0.75,1.0]:
				var state:=fixed.duplicate(true);state.sailDeployment=deployment
				demo._ship.apply_snapshot(state,WIND,0)
				demo._rigid.compose({}, {"hero":demo._ship}, -demo._sun.global_basis.z,true,true)
				check(gate.caster_evidence(demo,"art_r9b","authored").ok,"LOD%d deployment %.2f retains all five authored proxies"%[lod,deployment])
				var pose:Dictionary=gate.deployment_evidence(demo,"art_r9b",state,WIND,-14.0/18.0*deployment)
				check(pose.ok,"LOD%d deployment %.2f binds canvas and battens to the same applied morph: %s"%[lod,deployment,str(pose.get("errors",[]))])
				if deployment==0.5:
					var wrong_wind:=WIND.duplicate(true);wrong_wind.speed=15.0
					check(not gate.deployment_evidence(demo,"art_r9b",state,wrong_wind,-14.0/18.0*deployment).ok,"different wind is rejected")
					var wrong_snapshot:=state.duplicate(true);wrong_snapshot.rudder=-0.35
					check(not gate.deployment_evidence(demo,"art_r9b",wrong_snapshot,WIND,-14.0/18.0*deployment).ok,"different accepted snapshot is rejected")
					var sail:=active.find_child("sail_0",true,false) as MeshInstance3D
					if check(sail!=null,"actual active sail exists"):
						var role:Dictionary={}
						for item:Dictionary in demo._ship.get("_pose_sails"):
							if item.node==sail:role=item;break
						var furl:=int(role.get("furl",-1))
						if check(furl>=0,"actual furl morph exists"):
							var saved:=sail.get_blend_shape_value(furl);sail.set_blend_shape_value(furl,saved+0.2)
							check(not gate.deployment_evidence(demo,"art_r9b",state,WIND,-14.0/18.0*deployment).ok,"incorrect real morph weight is rejected")
							sail.set_blend_shape_value(furl,saved)
						var inflate:=int(role.get("inflate",-1))
						if check(inflate>=0,"actual inflation morph exists"):
							var saved:=sail.get_blend_shape_value(inflate);sail.set_blend_shape_value(inflate,saved+0.2)
							check(not gate.deployment_evidence(demo,"art_r9b",state,WIND,-14.0/18.0*deployment).ok,"incorrect real inflation weight is rejected")
							sail.set_blend_shape_value(inflate,saved)
						var original_mesh:=sail.mesh
						var altered:=original_mesh.duplicate() as ArrayMesh
						if check(altered!=null,"actual sail mesh can be isolated for a failure fixture"):
							for surface in range(altered.get_surface_count()-1,-1,-1):
								var material:=altered.surface_get_material(surface)
								if material!=null and material.resource_name=="bamboo":altered.surface_remove(surface)
							sail.mesh=altered
							check(not gate.deployment_evidence(demo,"art_r9b",state,WIND,-14.0/18.0*deployment).ok,"missing batten surface is rejected")
							sail.mesh=original_mesh
		var reset:Dictionary=demo.reset_experiment({"animated":false,"paused":false})
		check(reset.ok and demo.inspection_snapshot()==original,"reset restores original experiment snapshot")
		check(gate.lod_evidence(demo,"art_r9b",0).ok,"reset restores LOD0 and its original source")
		check(gate.pose_evidence(demo,"art_r9b",original.snapshot).ok,"reset restores original sail and rudder poses")
		demo.dispose();demo.free()
	print("HERO_GPU_DEPLOYMENT_LOD assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
