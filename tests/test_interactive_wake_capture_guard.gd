extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool,detail: String) -> void:
	assertions += 1
	if not ok: failures+=1;printerr("FAIL interactive field capture: ",detail)
func _initialize() -> void:
	var path := "res://tools/verify-interactive-wake-lab-gpu.gd"
	check(ResourceLoader.exists(path),"interactive field GPU driver exists")
	if failures: finish();return
	var script: Script=load(path)
	var names: Array=[]
	for method: Dictionary in script.get_script_method_list(): names.append(str(method.name))
	check("capture_inventory_valid" in names,"driver checks full timeline inventory")
	if failures: finish();return
	check(not script.call("capture_inventory_valid",[],5,2,"field"),"zero captures never pass")
	var window_api := false
	for method: Dictionary in script.get_script_method_list():
		if method.name=="capture_ticks":window_api=method.args.size()>=3
	check(window_api,"capture schedule accepts explicit short-stage windows")
	if window_api:
		check(script.call("capture_ticks",8,4,[[2,3],[6,7]])==[0,2,3,4,6,7,8],"short stage windows add consecutive captures around sparse keyframes")
		check(script.call("capture_ticks",8,4,[[7,2]]).is_empty(),"reversed stage window rejected")
	var records: Array=[]
	for tick in [0,2,4,5]:
		records.append({"tick":tick,"time":tick/32.0,"image_sha256":"a".repeat(64),"ship_sha256":"b".repeat(64),"controls_sha256":"c".repeat(64),"camera_transform":Array(range(16)),"camera_projection":Array(range(16)),"field_status":"ready","field_bound":true})
	check(script.call("capture_inventory_valid",records,5,2,"field"),"complete fixed timeline including final remainder accepted")
	var broken: Array=records.duplicate(true);broken.remove_at(1)
	check(not script.call("capture_inventory_valid",broken,5,2,"field"),"missing middle frame rejected")
	broken=records.duplicate(true);broken[2].time=0.0
	check(not script.call("capture_inventory_valid",broken,5,2,"field"),"backward accepted time rejected")
	broken=records.duplicate(true);broken[1].field_status="pending";broken[1].field_bound=false
	check(not script.call("capture_inventory_valid",broken,5,2,"field"),"candidate pending fallback cannot pass as ready")
	broken=records.duplicate(true);broken[1].image_sha256=""
	check(not script.call("capture_inventory_valid",broken,5,2,"field"),"missing artifact digest rejected")
	broken=records.duplicate(true);broken[1].camera_projection=[]
	check(not script.call("capture_inventory_valid",broken,5,2,"field"),"missing camera replay metadata rejected")
	for record: Dictionary in records: record.field_status="disabled";record.field_bound=false
	check(script.call("capture_inventory_valid",records,5,2,"source"),"same strict timeline supports unchanged source baseline")
	check("summarize_readback" in names,"readback validation guards raw GPU data before indexing")
	if "summarize_readback" in names:
		var receipt := {"error":"","resolution":1,"format":"rgba32f","data":PackedFloat32Array([.125,.1,.2,.5]).to_byte_array()}
		var valid: Dictionary=script.call("summarize_readback",receipt)
		check(valid.get("ok",false) and valid.get("max_abs_height_m")==.125 and valid.get("max_foam")==.5,"real float channels summarize in declared units")
		receipt.data=PackedByteArray([1,2,3])
		check(not script.call("summarize_readback",receipt).get("ok",true),"truncated readback cannot crash or pass")
		receipt.data=PackedFloat32Array([NAN,0,0,.5]).to_byte_array()
		check(not script.call("summarize_readback",receipt).get("ok",true),"nonfinite height cannot pass GPU evidence")
	finish()
func finish() -> void:
	print("INTERACTIVE_WAKE_CAPTURE_GUARD_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
