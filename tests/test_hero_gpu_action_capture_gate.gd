extends SceneTree
## Real PNGs plus intentionally corrupted receipts; no GPU claim.
const Gate=preload("res://tools/research/hero_gpu_evidence_gate.gd")
const WIND={"direction":{"x":1.0,"y":0.0},"speed":14.0}
var assertions:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",detail)

func run()->void:
	var gate=Gate.new()
	check(gate.has_method("action_capture_evidence"),"new GPU action images have a complete receipt gate")
	if gate.has_method("action_capture_evidence"):
		var output:="user://hero-actions-%d"%Time.get_ticks_usec()
		check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))==OK,"isolated output exists")
		var pixel:=Image.create_empty(2,2,false,Image.FORMAT_RGBA8);pixel.fill(Color("345678"))
		var files:Array=[];var deployment_frames:Array=[];var lod_frames:Array=[];var shadows:Array=[]
		var paths:Array=gate.expected_source_paths("art_r9b")
		for deployment:float in [0.0,0.25,0.5,0.75,1.0]:
			var label:="deployment-%03d"%roundi(deployment*100)
			var saved:Dictionary=gate.save_png(pixel,output.path_join(label+".png"),label,8.0,Vector2i(2,2))
			check(saved.ok,"test PNG saved "+label);files.append(saved.entry)
			var state:={"time":8.0,"sailDeployment":deployment,"sailAngle":0.0,"rudder":0.35}
			deployment_frames.append({"phase":label,"deployment":deployment,"wind":WIND.duplicate(true),"snapshot":state,"lodEvidence":{"ok":true,"lod":0,"sourcePath":paths[0]},"components":{"ok":true,"supported":true},"file":saved.entry})
			shadows.append({"phase":label,"counterCheck":{"ok":true},"casterBinding":{"ok":true}})
		for lod in 3:
			var label:="lod-%d"%lod
			var saved:Dictionary=gate.save_png(pixel,output.path_join(label+".png"),label,8.0,Vector2i(2,2))
			check(saved.ok,"test PNG saved "+label);files.append(saved.entry)
			var state:={"time":8.0,"sailDeployment":1.0,"sailAngle":0.0,"rudder":0.35}
			lod_frames.append({"phase":label,"lod":lod,"wind":WIND.duplicate(true),"snapshot":state,"lodEvidence":{"ok":true,"lod":lod,"sourcePath":paths[lod]},"components":{"ok":true,"supported":true},"file":saved.entry})
			shadows.append({"phase":label,"counterCheck":{"ok":true},"casterBinding":{"ok":true}})
		check(gate.action_capture_evidence(deployment_frames,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"all five deployments and three correct LOD frames accepted")
		var damaged:=deployment_frames.duplicate(true);damaged.pop_back()
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"missing deployment rejected")
		damaged=deployment_frames.duplicate(true);damaged[1].deployment=0.0
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"duplicate deployment rejected")
		damaged=deployment_frames.duplicate(true);damaged[2].wind.speed=15.0
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"different wind rejected")
		damaged=deployment_frames.duplicate(true);damaged[2].snapshot.rudder=-0.35
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"different snapshot rejected")
		damaged=lod_frames.duplicate(true);damaged[1].lodEvidence.sourcePath=paths[0]
		check(not gate.action_capture_evidence(deployment_frames,damaged,files,shadows,"art_r9b","authored",WIND,output).ok,"wrong LOD source rejected")
		var absent:=shadows.duplicate(true);absent.pop_back()
		check(not gate.action_capture_evidence(deployment_frames,lod_frames,files,absent,"art_r9b","authored",WIND,output).ok,"missing active compositor receipt rejected")
		damaged=deployment_frames.duplicate(true);damaged[3].file.sha256="0".repeat(64)
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"wrong PNG hash rejected")
		damaged=deployment_frames.duplicate(true);damaged[3].components.ok=false
		check(not gate.action_capture_evidence(damaged,lod_frames,files,shadows,"art_r9b","authored",WIND,output).ok,"failed sail or batten evidence rejected")
		check(gate.has_method("reset_capture_evidence"),"reset image and restored initial state have a receipt gate")
		if gate.has_method("reset_capture_evidence"):
			var saved:Dictionary=gate.save_png(pixel,output.path_join("reset-initial.png"),"reset-initial",0.0,Vector2i(2,2));files.append(saved.entry)
			var initial:={"time":0.0,"sailDeployment":1.0,"sailAngle":0.0,"rudder":0.0}
			var reset:={"phase":"reset-initial","snapshot":initial.duplicate(true),"wind":WIND.duplicate(true),"lodEvidence":{"ok":true,"lod":0,"sourcePath":paths[0]},"poseEvidence":{"ok":true},"file":saved.entry}
			shadows.append({"phase":"reset-initial","counterCheck":{"ok":true},"casterBinding":{"ok":true}})
			check(gate.reset_capture_evidence(reset,initial,WIND,files,shadows,"art_r9b","authored",output).ok,"true initial state, LOD0 and rendered frame accepted")
			var bad:Dictionary=reset.duplicate(true);bad.snapshot.rudder=0.5
			check(not gate.reset_capture_evidence(bad,initial,WIND,files,shadows,"art_r9b","authored",output).ok,"incorrect reset state rejected")
			bad=reset.duplicate(true);bad.wind.speed=1.0
			check(not gate.reset_capture_evidence(bad,initial,WIND,files,shadows,"art_r9b","authored",output).ok,"incorrect reset wind rejected")
			bad=reset.duplicate(true);bad.lodEvidence.sourcePath=paths[1]
			check(not gate.reset_capture_evidence(bad,initial,WIND,files,shadows,"art_r9b","authored",output).ok,"incorrect reset LOD rejected")
			bad=reset.duplicate(true);bad.file.sha256="0".repeat(64)
			check(not gate.reset_capture_evidence(bad,initial,WIND,files,shadows,"art_r9b","authored",output).ok,"incorrect reset PNG hash rejected")
			var no_reset_shadow:=shadows.duplicate(true);no_reset_shadow.pop_back()
			check(not gate.reset_capture_evidence(reset,initial,WIND,files,no_reset_shadow,"art_r9b","authored",output).ok,"missing reset compositor receipt rejected")
	print("HERO_GPU_ACTION_CAPTURE_GATE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
