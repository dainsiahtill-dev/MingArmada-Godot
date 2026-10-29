extends SceneTree
const Contract = preload("res://tools/research/broadside_capture_contract.gd")
const Demo = preload("res://game/research/demos/broadside_receipt_experiment.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL broadside capture guard: ",message)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var gpu_script = load("res://tools/research/capture_broadside_lab_gpu.gd")
	check(gpu_script != null and gpu_script.can_instantiate(),"GPU driver parses without starting a graphics run")
	check(Contract.profile_ok("C:/work/profile/roaming","C:/work/profile/local","C:/work/profile","C:/Users/real/AppData/Roaming","C:/work/profile/roaming/Godot/app_userdata/MingArmada"),"isolated roaming and local profile accepted")
	check(not Contract.profile_ok("C:/Users/real/AppData/Roaming","C:/work/profile/local","C:/work/profile","C:/Users/real/AppData/Roaming","C:/Users/real/AppData/Roaming/Godot/app_userdata/MingArmada"),"real appdata rejected")
	check(not Contract.profile_ok("C:/work/profile/roaming","C:/work/profile/roaming","C:/work/profile","C:/Users/real/AppData/Roaming","C:/work/profile/roaming/Godot/app_userdata/MingArmada"),"local and roaming must be distinct")
	check(not Contract.profile_ok("C:/work/profile/roaming","C:/work/profile/roaming/local","C:/work/profile","C:/Users/real/AppData/Roaming","C:/work/profile/roaming/Godot/app_userdata/MingArmada"),"local and roaming must not overlap")
	check(not Contract.profile_ok("C:/work/profile/roaming","C:/work/profile/local","C:/work/profile","C:/Users/real/AppData/Roaming","C:/work/other"),"actual Godot userdata must be under isolated roaming")
	var base := "res://docs/research/evidence/broadside-receipt-readability/never-created-guard-test/frames"
	check(Contract.output_ok(base,ProjectSettings.globalize_path(base)),"fresh confined output accepted")
	check(not Contract.output_ok("res://docs/research/evidence/../../outside/frames",ProjectSettings.globalize_path(base)),"traversal rejected")
	check(not Contract.output_ok(base,ProjectSettings.globalize_path(base+"-other")),"mismatched expected output rejected")
	check(not Contract.output_ok("res://docs/research/evidence/broadside-receipt-readability/baseline-01",ProjectSettings.globalize_path("res://docs/research/evidence/broadside-receipt-readability/baseline-01")),"existing evidence rejected")
	var viewport := SubViewport.new(); viewport.own_world_3d = true; viewport.size = Vector2i(960,640); root.add_child(viewport)
	var snapshots := []
	for enabled in [false,true]:
		var demo = Demo.new(); check(demo.configure({"candidate_enabled":enabled}).ok,"configured fixed fixture")
		viewport.add_child(demo)
		var timeline := []
		for tick in Contract.LAST_TICK+1:
			if tick > 0: demo.advance(Contract.STEP)
			var snap: Dictionary = demo.inspection_snapshot()
			check(snap.tick == tick and absf(snap.time-tick*Contract.STEP)<1.0e-12,"exact fixed-step tick")
			timeline.append(snap)
		snapshots.append(timeline); demo.dispose(); demo.free()
	for tick in Contract.LAST_TICK+1: check(Contract.pair_ok(snapshots[0][tick],snapshots[1][tick]),"paired snapshots match except displayed receipt")
	check(Contract.fixture_events(16)[0].id == "e5" and Contract.fixture_events(20)[0].id == "e6","event IDs bound to their actual fixed ticks")
	var fixture_hash := HashingContext.new(); fixture_hash.start(HashingContext.HASH_SHA256); fixture_hash.update(JSON.stringify(Contract.input_fixture()).to_utf8_buffer())
	print("BROADSIDE_FIXTURE_SHA256 ",fixture_hash.finish().hex_encode())
	check(snapshots[1][16].visible_receipt == "右舷命中 · 敌船倭船" and snapshots[1][20].visible_receipt == snapshots[1][16].visible_receipt,"candidate keeps hit through mixed splash")
	check(snapshots[1][112].visible_receipt == "","three-second result expires at tick 112")
	var tampered: Dictionary = snapshots[1][20].duplicate(true); tampered.receipt.text = "invented"
	check(not Contract.pair_ok(snapshots[0][20],tampered),"paired comparison rejects mismatched receipt")
	viewport.free(); finish()
func finish() -> void:
	print("BROADSIDE_CAPTURE_GUARDS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
