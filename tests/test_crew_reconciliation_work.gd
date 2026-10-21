extends SceneTree
## Work contract plus exact real-model oracle from the frozen pre-guard CrewView.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const FROZEN := "res://docs/research/evidence/architecture-convergence-2026-10-21/baseline/source/game/presentation/crew/crew_view.gd.txt"
const FROZEN_SHA256 := "24f80809086bd805fa18adc4bd6fe42abfb3d27c77a7d8ff362f1faae4e86a6a"

class ObservedCrew:
	extends "res://game/presentation/crew/crew_view.gd"
	var samples := 0
	var reconciles := 0
	var recoveries := 0
	var releases := 0
	func _sample_instance(instance: Dictionary, station: Dictionary) -> void:
		samples += 1
		super._sample_instance(instance,station)
	func _reconcile() -> void:
		reconciles += 1
		super._reconcile()
	func _finish_impact(slot: int, instance: Dictionary, recover: bool) -> void:
		if recover: recoveries += 1
		else: releases += 1
		super._finish_impact(slot,instance,recover)
	func reset_work() -> void: samples = 0; reconciles = 0

var assertions := 0
var failures := 0
var work: Array = []
func _initialize() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL crew reconciliation: ",detail)
func water(_x: float,_z: float,_phase: float) -> float: return -1000.0
func snapshot(kind: String) -> Dictionary:
	return {"id":kind,"kind":kind,"time":20.0,"crew":100.0,"hull":100.0,"maxHull":100.0,"sail":100.0,"maxSail":100.0,"sailDeployment":1.0,"sailAngle":0.0,"rudder":.3,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"heading":.2,"pitch":.03,"heel":-.02,"velocity":{"x":2.0,"z":0.0}},"cooldownSeconds":{"port":0.0,"starboard":0.0}}
func skin(instance: Dictionary) -> Dictionary:
	var bones := []
	var skeleton: Skeleton3D = instance.skeleton
	for index in skeleton.get_bone_count(): bones.append({"name":skeleton.get_bone_name(index),"local":skeleton.get_bone_pose(index),"global":skeleton.get_bone_global_pose(index)})
	return {"slot":instance.slot,"clip":instance.clip,"lod":instance.lod,"root":instance.root.transform,"visible":instance.root.visible,"bones":bones}
func state_of(crew: Node3D) -> Dictionary:
	var standing := []; var retired := []; var bodies := []
	var slots: Array = crew.get("_instances").keys(); slots.sort()
	for slot: int in slots: standing.append(skin(crew.get("_instances")[slot]))
	slots = crew.get("_retired").keys(); slots.sort()
	for slot: int in slots: retired.append(skin(crew.get("_retired")[slot]))
	var pool: Node3D = crew.get_impact_pool()
	for entry: Dictionary in pool.get("_bodies").values(): bodies.append({"slot":entry.source.slot,"age":entry.age,"wet":entry.wet,"casualty":entry.casualty,"lifetime":entry.lifetime,"bones":entry.bones.size(),"joints":entry.joints.size()})
	return {"ship":crew.get("_ship").duplicate(true),"time":crew.get("_time"),"distance":crew.get("_distance"),"lod":crew.get("_lod"),"allocation":crew.get("_allocation"),"reduced":crew.get("_reduced"),"roles":crew.diagnostics().roles,"standing":standing,"retired":retired,"bodies":bodies,"poolPhase":pool.get("_phase"),"lossBudget":crew.get("_loss_budget"),"sheetUntil":crew.get("_sheet_until"),"fireUntil":crew.get("_fire_until").duplicate(true),"seen":crew.get("_seen").duplicate(true)}
func same(crew: Node3D, oracle: Node3D, label: String) -> void:
	check(var_to_bytes(state_of(crew)) == var_to_bytes(state_of(oracle)),"actual final source bone/root/role/lifecycle state equals frozen old implementation: "+label)
func hit(kind: String, id: String) -> Array:
	return [{"type":"hit","id":id,"targetId":kind,"position":{"x":0.0,"y":2.0,"z":0.0},"velocity":{"x":10.0,"y":0.0,"z":0.0},"damage":{"crew":1.0}}]
func event_metadata(events: Array) -> Array:
	var result := []
	for original: Dictionary in events:
		var event := original.duplicate(true)
		if event.has("body_id"): event.body_id = "impact_"+str(event.body_id).get_slice("_",2)
		result.append(event)
	return result

func _run() -> void:
	check(FileAccess.get_sha256(FROZEN) == FROZEN_SHA256,"oracle remains the original frozen production source")
	var old := GDScript.new(); old.source_code = FileAccess.get_file_as_string(FROZEN)
	check(old.reload() == OK and old.can_instantiate(),"frozen source compiles independently")
	if not old.can_instantiate(): _finish(); return
	var library := Library.new()
	for kind: String in Ship.KINDS:
		var ship := Ship.new(); root.add_child(ship)
		check(ship.configure(kind,library),"actual source ship configures: "+kind)
		var crew := ObservedCrew.new(); root.add_child(crew)
		var oracle: Node3D = old.new(); root.add_child(oracle)
		check(crew.configure(kind,ship.get_model(),library) and oracle.configure(kind,ship.get_model(),library),"real source crew/deck owners configure: "+kind)
		crew.set_environment(water); oracle.set_environment(water)
		var events: Array = []; var old_events: Array = []
		crew.get_impact_pool().visual_event.connect(func(event: Dictionary): events.append(event.duplicate(true)))
		oracle.get_impact_pool().visual_event.connect(func(event: Dictionary): old_events.append(event.duplicate(true)))
		var packet := snapshot(kind)
		for owner: Node3D in [crew,oracle]: owner.apply_snapshot(packet,{},0.0)
		same(crew,oracle,kind+" initial")
		var first: Dictionary = crew.get_instances()[0]
		check(first.skeleton != oracle.get_instances()[0].skeleton,"frozen oracle and production own different mutable skeletons")
		var identity := [first.root.get_instance_id(),first.skeleton.get_instance_id()]
		crew.reset_work()
		crew.set_lod_distance(80.0); oracle.set_lod_distance(80.0)
		check(crew.get("_distance") == 80.0 and crew.reconciles == 0 and crew.samples == 0,"same LOD/cutoff updates distance without resampling old phase: "+kind)
		same(crew,oracle,kind+" unchanged LOD")
		crew.reset_work()
		crew.set_allocation(99); oracle.set_allocation(99)
		check(crew.get("_allocation") == 24 and crew.reconciles == 0 and crew.samples == 0,"allocation canonical equality skips repeated reconciliation: "+kind)
		same(crew,oracle,kind+" canonical allocation")
		work.append({"kind":kind,"stableSetterReconciles":crew.reconciles,"stableSetterSamples":crew.samples})
		check(identity == [crew.get_instances()[0].root.get_instance_id(),crew.get_instances()[0].skeleton.get_instance_id()],"unchanged setters retain the exact model/skeleton owner identity")
		for distance: float in [350.0,1900.0,1800.1,1800.0,50.0]:
			var previous_lod: int = crew.get("_lod")
			crew.set_lod_distance(distance); oracle.set_lod_distance(distance)
			same(crew,oracle,kind+" immediate cutoff "+str(distance))
			if distance == 1900.0: check(previous_lod == 2 and crew.get("_lod") == 2 and crew.get_visible_count() == 0,"same-LOD2 1800 crossing immediately releases standing skins")
			if distance == 1800.0: check(crew.get_visible_count() > 0,"exact 1800 boundary immediately restores standing skins")
		crew.set_allocation(-10); oracle.set_allocation(-10)
		check(crew.get_visible_count() == 0,"changed allocation immediately releases original skins")
		crew.reset_work(); crew.set_allocation(-1); oracle.set_allocation(-1)
		check(crew.reconciles == 0,"different negative inputs have the same canonical zero allocation")
		crew.set_allocation(24); oracle.set_allocation(24)
		for lod in 3:
			ship.set_lod_distance([0.0,300.0,700.0][lod])
			for owner: Node3D in [crew,oracle]:
				owner.set_ship_model(ship.get_model()); owner.set_lod_distance([50.0,200.0,700.0][lod])
				owner.apply_snapshot(packet,{},0.0); owner.apply_events([])
			same(crew,oracle,kind+" real LOD "+str(lod))
		ship.set_lod_distance(0.0)
		for owner: Node3D in [crew,oracle]: owner.set_ship_model(ship.get_model()); owner.set_lod_distance(50.0)
		for phase: float in [21.0,21.0,0.0,20.0]:
			packet.time = phase; crew.reset_work()
			for owner: Node3D in [crew,oracle]: owner.apply_snapshot(packet,{},0.0)
			check(crew.samples > 0,"final snapshot keeps current-phase source animation sampling")
			same(crew,oracle,kind+" final pose/rewind "+str(phase))
		for reduced: bool in [true,false]:
			for owner: Node3D in [crew,oracle]: owner.set_reduced_motion(reduced); owner.apply_snapshot(packet,{},0.0)
			same(crew,oracle,kind+" reduced "+str(reduced))
		# The native expiry/recovery callback owns its own reconciliation. It
		# must still restore the real skin after unchanged setters, without a new
		# apply_snapshot or accepted animation phase being supplied by the caller.
		packet.crew = 2.0
		for owner: Node3D in [crew,oracle]: owner.apply_snapshot(packet,{},0.0); owner.apply_events([])
		# Seed the two-skin fixture first, then admit the unchanged native packet:
		# a nonlethal hit must not inherit the prior fixture's 100->2 loss budget.
		for owner: Node3D in [crew,oracle]: owner.apply_snapshot(packet,{},0.0)
		for owner: Node3D in [crew,oracle]: owner.apply_events(hit(kind,kind+"-late-recovery"))
		check(crew.get_impact_pool().get_body_count() == 1,"late recovery fixture transfers one real eighteen-bone skin")
		same(crew,oracle,kind+" real nonlethal transfer")
		for owner: Node3D in [crew,oracle]: owner.set_lod_distance(50.0); owner.set_allocation(24)
		var recoveries := crew.recoveries
		for owner: Node3D in [crew,oracle]: owner.get_impact_pool().advance(1.3,21.3)
		check(crew.recoveries == recoveries+1 and crew.get_impact_pool().get_body_count() == 0 and crew.get_visible_count() == 2,"late native recovery callback restores skin without relying on unchanged setters")
		same(crew,oracle,kind+" late recovery")
		packet.time = 21.3; packet.crew = 1.0
		for owner: Node3D in [crew,oracle]: owner.apply_snapshot(packet,{},0.0); owner.apply_events(hit(kind,kind+"-late-release"))
		check(crew.get_impact_pool().get_body_count() == 1,"authoritative crew loss retains casualty skin transfer")
		var releases := crew.releases
		for owner: Node3D in [crew,oracle]: owner.set_allocation(24); owner.set_lod_distance(50.0); owner.get_impact_pool().remove_ship(kind)
		check(crew.releases == releases+1 and crew.get_impact_pool().get_body_count() == 0,"late native release callback remains immediate")
		same(crew,oracle,kind+" late release")
		check(event_metadata(events) == event_metadata(old_events),"native callback/event order equals frozen old owner after ObjectID normalization")
		crew.dispose(); oracle.dispose(); crew.free(); oracle.free(); ship.dispose(); ship.free()
	library.dispose()
	_finish()
func _finish() -> void:
	print("CREW_RECONCILIATION_WORK ",JSON.stringify(work))
	print("CREW_RECONCILIATION_WORK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
