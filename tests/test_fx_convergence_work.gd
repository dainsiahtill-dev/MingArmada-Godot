extends SceneTree
## Paired native state/output and measurable work at the real Wakes seam.
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const Geometry = preload("res://modules/scene_engine/water/source_wake_geometry.gd")
const Frame = preload("res://modules/scene_engine/fidelity_fx/prepared_shadow_frame.gd")
const LegacyPrepared = preload("res://game/presentation/world/prepared_rigid_shadow.gd")
var assertions := 0
var failures := 0
var water_calls := 0
var sea_calls := 0
var wet := true
var measurements: Array = []

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX convergence: ",message)
func water(_x: float,_z: float,time: float) -> float:
	water_calls += 1
	return .35 + time*.01
func sea(_x: float,_z: float) -> bool:
	sea_calls += 1
	return wet
func packet(index: int,route: String,froth: bool = false) -> Dictionary:
	var time := float(index)*.1
	var wake := {"route":route,"sourceCallIndex":index,"sourceClock":time,"sourcePosition":[100.0+index*4.0,100.0,0.0],"markerId":"Dummy_Wake","modelScale":.1,"sourceToWorld":.01}
	if froth:
		wake.froth={"family":0,"seed":7,"controllerAppTime":time,"sourceBowPosition":[120.0+index*4.0,100.0,0.0],"enabled":true}
	if route == "battle_90":
		wake.battle={"type":0,"tick":index+7,"x":8000+index*4,"y":4000,"heading":index*1000,"map_origin_x":100,"map_origin_y":100,"sine_boundary":0,"hold_history":false}
	return {"time":time,"wake":{"route":route,"epoch":1,"sourceCallIndex":index},"ships":[{"id":"ship","hull":100.0,"sourceWake":wake}]}
func make_wakes() -> Node3D:
	var wakes := Wakes.new();root.add_child(wakes)
	wakes.configure(water);wakes.configure_surface_filter(sea)
	return wakes
func actor(wakes: Node3D) -> Dictionary:return wakes.get("_source_wakes").get("_actors").ship
func uploads(value: Dictionary) -> int:return int(value.surface.rebuilds)+int(value.surface.region_uploads)
func tail_arrays(value: Dictionary) -> Dictionary:
	var result := {}
	for key: String in value.surface.nodes:
		if key != "SceneStrip" and not key.begins_with("BattleDraw_"):continue
		var node: MeshInstance3D=value.surface.nodes[key]
		result[key]={"visible":node.visible,"arrays":node.mesh.surface_get_arrays(0) if node.mesh != null and node.mesh.get_surface_count()>0 else []}
	return result
func source_state(value: Dictionary) -> Dictionary:
	if value.history != null:
		return {"history":value.history.ring_bytes(),"geometry":value.history.get_meta(Geometry.STATE_KEY,{})}
	return {"history":value.battle_history,"arguments":value.geometry.get("draw_arguments",[])}
func paired_coverage(route: String) -> void:
	var baseline := make_wakes();var covered := make_wakes()
	for index in 45:
		baseline.apply_snapshot(packet(index,route));covered.apply_snapshot(packet(index,route))
	covered.set_interactive_coverage(["ship"])
	var actual := actor(covered);var before := uploads(actual)
	var hidden_water := 0;var hidden_sea := 0;var baseline_water := 0
	for index in range(45,65):
		var calls := water_calls
		baseline.apply_snapshot(packet(index,route));baseline_water += water_calls-calls
		calls = water_calls;var clips := sea_calls
		covered.apply_snapshot(packet(index,route))
		hidden_water += water_calls-calls;hidden_sea += sea_calls-clips
		check(source_state(actual)==source_state(actor(baseline)),route+": hidden updates preserve all native history and geometry state")
	check(hidden_water==0 and hidden_sea==0,route+": hidden tail performs no water fit or sea clipping")
	var hidden_uploads := uploads(actual)-before
	check(hidden_uploads==0,route+": hidden tail performs no mesh upload or rebuild")
	check(baseline_water>0,route+": visible control exercises actual tail sampling")
	covered.set_interactive_coverage([])
	check(tail_arrays(actual)==tail_arrays(actor(baseline)),route+": same-time coverage release restores current exact fallback geometry")
	var restored_uploads := uploads(actual);var restored_source := var_to_bytes(source_state(actual))
	covered.set_interactive_coverage([]);covered.apply_snapshot(packet(64,route))
	check(uploads(actual)==restored_uploads and var_to_bytes(source_state(actual))==restored_source,route+": repeated release and same call do not upload or advance again")
	covered.set_interactive_coverage(["ship"])
	wet=false;baseline.apply_snapshot(packet(65,route));covered.apply_snapshot(packet(65,route))
	covered.set_interactive_coverage([])
	check(tail_arrays(actual)==tail_arrays(actor(baseline)),route+": release rebuilds current dry eligibility without reviving old cached triangles")
	wet=true
	measurements.append({"route":route,"hiddenAcceptedCalls":20,"hiddenWaterQueries":hidden_water,"hiddenSeaQueries":hidden_sea,"hiddenUploads":hidden_uploads,"visibleControlWaterQueries":baseline_water})
	baseline.dispose();baseline.free();covered.dispose();covered.free()
func froth_state() -> void:
	var baseline:=make_wakes();var covered:=make_wakes()
	for index in 45:
		baseline.apply_snapshot(packet(index,"scene_30",true));covered.apply_snapshot(packet(index,"scene_30",true))
	covered.set_interactive_coverage(["ship"])
	var actual:=actor(covered);var identity:RefCounted=actual.froth
	for index in range(45,50):
		baseline.apply_snapshot(packet(index,"scene_30",true));covered.apply_snapshot(packet(index,"scene_30",true))
		check(actual.froth==identity,"coverage retains the original local froth owner")
		check(actual.froth.get("_particles").source_state()==actor(baseline).froth.get("_particles").source_state(),"coverage preserves froth controller/RNG/particle state")
	covered.set_interactive_coverage([])
	check(tail_arrays(actual)==tail_arrays(actor(baseline)),"froth and tail recover without replacing either native owner")
	baseline.dispose();baseline.free();covered.dispose();covered.free()
func rejected_source_updates() -> void:
	var baseline:=make_wakes();var covered:=make_wakes()
	for index in 45:
		baseline.apply_snapshot(packet(index,"scene_30"));covered.apply_snapshot(packet(index,"scene_30"))
	for reject_time in [false,true]:
		covered.set_interactive_coverage(["ship"])
		var index:=45 if not reject_time else 47
		var accepted:=packet(index,"scene_30")
		baseline.apply_snapshot(accepted);covered.apply_snapshot(accepted)
		var rejected:=packet(index+1,"scene_30")
		var source:Dictionary=rejected.ships[0].sourceWake
		if reject_time:source.sourceClock=float(accepted.time)-.2
		else:source.sourcePosition=accepted.ships[0].sourceWake.sourcePosition.duplicate()
		# A rejected producer call cannot remap the last accepted source carrier.
		source.sourceToWorld=.02;source.worldOrigin=[4.0,5.0,6.0]
		baseline.apply_snapshot(rejected);covered.apply_snapshot(rejected)
		check(source_state(actor(covered))==source_state(actor(baseline)),"rejected input preserves native source state under coverage")
		covered.set_interactive_coverage([])
		check(tail_arrays(actor(covered))==tail_arrays(actor(baseline)),"coverage release retains accepted projection across distance/time rejection")
	baseline.dispose();baseline.free();covered.dispose();covered.free()
func engine_shadow() -> void:
	var path:="res://modules/scene_engine/fidelity_fx/prepared_rigid_shadow.gd"
	check(FileAccess.file_exists(path),"prepared rigid shadow implementation belongs to scene engine")
	if not FileAccess.file_exists(path):return
	var implementation:Script=load(path)
	for prepared:RefCounted in [implementation.new(),LegacyPrepared.new()]:
		check(prepared.configure([[0,0,0],[1,0,0],[0,1,0]],[{"indices":[0,1,2],"normal":Vector3(0,0,1)}]).ok,"engine and compatibility owners prepare geometry")
		var volume:Dictionary=prepared.build_volume([0,0,-1])
		var frame:=Frame.new()
		check(frame.configure([{"geometry":volume,"preparedOwner":prepared}]),"typed receipt accepts engine and compatibility owners")
		check(is_same(frame.snapshot()[0].geometry,volume),"typed receipt keeps certified immutable geometry zero-copy")
func run() -> void:
	engine_shadow()
	paired_coverage("scene_30");paired_coverage("battle_90");froth_state();rejected_source_updates()
	print("FX_CONVERGENCE_WORK ",JSON.stringify(measurements))
	print("FX_CONVERGENCE_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
