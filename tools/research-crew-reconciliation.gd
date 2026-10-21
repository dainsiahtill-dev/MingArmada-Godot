extends SceneTree
## Research only. The second owner selects frozen baseline or two setter guards.
## Real GLBs, Skeleton3D, AnimationPlayer and isolated Jolt World3Ds are retained.
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Library = preload("res://modules/scene_engine/assets/asset_library.gd")
const FROZEN = "res://docs/research/evidence/architecture-convergence-2026-10-21/crew/frozen_crew_view.gd"
const STEP := 1.0/60.0

class ObservedPool:
	extends "res://modules/physics_engine/impacts/impact_pool.gd"
	var registrations: Array = []
	var advances: Array = []
	func register_deck(target_id: String, faces: PackedVector3Array, frame: Transform3D) -> void:
		registrations.append({"id":target_id,"frame":frame,"faces":faces.size()})
		super.register_deck(target_id,faces,frame)
	func advance(accepted_seconds: float, phase: float) -> void:
		advances.append({"accepted":accepted_seconds,"phase":phase})
		super.advance(accepted_seconds,phase)

class ObservedCrew:
	extends "res://docs/research/evidence/architecture-convergence-2026-10-21/crew/frozen_crew_view.gd"
	var probe := {"reconciles":0,"samples":0,"releases":[],"callbacks":[],"events":[]}
	func configure(ship_kind: String, ship_model: Node3D, asset_library = null) -> bool:
		if not super.configure(ship_kind,ship_model,asset_library): return false
		# Observe the same native owner before any body/deck exists. Keep owned
		# pool semantics; neither Jolt stepping nor any native method is replaced.
		_pool.dispose(); _pool.free(); _pool = ObservedPool.new(); add_child(_pool)
		_pool.set_environment(_water,_sample_impact_deck)
		return true
	func _reconcile() -> void:
		probe.reconciles += 1
		super._reconcile()
	func _sample_instance(instance: Dictionary, station: Dictionary) -> void:
		probe.samples += 1
		super._sample_instance(instance,station)
	func _release_instance(instance: Dictionary) -> void:
		probe.releases.append(int(instance.slot))
		super._release_instance(instance)
	func _finish_impact(slot: int, instance: Dictionary, recover: bool) -> void:
		probe.callbacks.append({"slot":slot,"recover":recover})
		super._finish_impact(slot,instance,recover)
	func observe_pool() -> void:
		get_impact_pool().visual_event.connect(func(event: Dictionary): probe.events.append(event.duplicate(true)))

class SetterCrew:
	extends ObservedCrew
	func set_allocation(count: int) -> void:
		var next := clampi(count,0,24)
		if next == _allocation: return
		_allocation = next
		_reconcile()
	func set_lod_distance(distance: float) -> void:
		if not is_finite(distance): return
		var previous_lod := _lod
		var previous_far := _distance > 1800.0
		_distance = maxf(0.0,distance)
		if _lod == 0 and distance > 110.0: _lod = 1
		if _lod == 1 and distance < 90.0: _lod = 0
		if _lod == 1 and distance >= 330.0: _lod = 2
		if _lod == 2 and distance < 270.0: _lod = 0 if distance < 90.0 else 1
		if previous_lod == _lod and previous_far == (_distance > 1800.0): return
		_reconcile()

var assertions := 0
var failures: Array[String] = []
var rows: Array = []
var candidate := "setters"
var require_work_reduction := false
var output := ""
var pair: Array = []
var state := {}
var distance := 50.0
var allocation := 24

func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> bool:
	assertions += 1
	if not ok: failures.append(message); printerr("FAIL crew reconciliation research: ",message)
	return ok
func digest(value: Variant) -> String: return var_to_bytes(value).hex_encode().sha256_text()
func dry(_x: float,_z: float,_time: float) -> float: return -1000.0
func wet(_x: float,_z: float,_time: float) -> float: return 1000.0
func initial(kind: String, phase: float = 20.0) -> Dictionary:
	return {"id":kind,"kind":kind,"time":phase,"hull":100.0,"maxHull":100.0,"crew":100.0,"sail":100.0,"maxSail":100.0,"sailDeployment":1.0,"sailAngle":0.0,"rudder":.3,"visual":{"position":{"x":0.0,"y":0.0,"z":0.0},"heading":0.0,"pitch":0.0,"heel":0.0,"velocity":{"x":2.0,"z":0.0}},"cooldownSeconds":{"port":0.0,"starboard":0.0}}

func make_pair(kind: String) -> bool:
	pair.clear(); state = initial(kind); distance = 50.0; allocation = 24
	for side in 2:
		var viewport := SubViewport.new(); viewport.name = "CrewResearchWorld"+str(side)
		viewport.size = Vector2i(64,64); viewport.own_world_3d = true; viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		root.add_child(viewport)
		var host := Node3D.new(); viewport.add_child(host)
		var library := Library.new()
		var ship := Ship.new(); host.add_child(ship)
		if not check(ship.configure(kind,library),"actual source ship configures: "+kind+"/"+str(side)):
			viewport.free(); library.dispose(); return false
		var crew: ObservedCrew = SetterCrew.new() if side == 1 and candidate == "setters" else ObservedCrew.new()
		host.add_child(crew)
		if not check(crew.configure(kind,ship.get_model(),library),"frozen real deck/crew configures: "+kind+"/"+str(side)):
			viewport.free(); library.dispose(); return false
		crew.set_environment(dry); crew.observe_pool()
		pair.append({"viewport":viewport,"ship":ship,"crew":crew,"library":library})
	return true

func skeleton_state(instance: Dictionary) -> Dictionary:
	var bones := []; var skeleton: Skeleton3D = instance.skeleton
	for bone in skeleton.get_bone_count(): bones.append({"name":skeleton.get_bone_name(bone),"parent":skeleton.get_bone_parent(bone),"local":skeleton.get_bone_pose(bone),"global":skeleton.get_bone_global_pose(bone)})
	var meshes := []
	for mesh: MeshInstance3D in instance.root.find_children("*","MeshInstance3D",true,false): meshes.append({"visible":mesh.visible,"transparency":mesh.transparency})
	return {"slot":instance.slot,"lod":instance.lod,"clip":instance.clip,"root":instance.root.transform,"visible":instance.root.visible,"bones":bones,"meshes":meshes}

func body_label(id: String) -> String:
	# Pool IDs contain owner ObjectIDs; only the owner-local spawn ordinal has
	# semantic correspondence. Raw IDs remain in each work/event observation.
	return "impact_"+id.get_slice("_",2)

func capture(crew: ObservedCrew) -> Dictionary:
	var standing := []; var retired := []; var bodies := []; var impact_transforms := []; var impact_skins := []
	var events := []; var physical_events := []
	var slots: Array = crew.get("_instances").keys(); slots.sort()
	for slot: int in slots: standing.append(skeleton_state(crew.get("_instances")[slot]))
	slots = crew.get("_retired").keys(); slots.sort()
	for slot: int in slots: retired.append(skeleton_state(crew.get("_retired")[slot]))
	var pool: Node3D = crew.get_impact_pool()
	if pool != null:
		var ids: Array = pool.get("_bodies").keys(); ids.sort()
		for id: String in ids:
			var entry: Dictionary = pool.get("_bodies")[id]
			bodies.append({"id":body_label(id),"age":entry.age,"wet":entry.wet,"state":entry.state,"waterEntered":entry.water_entered,"lifetime":entry.lifetime,"casualty":entry.casualty,"slot":entry.source.slot,"bones":entry.bones.size(),"joints":entry.joints.size()})
			impact_transforms.append({"id":body_label(id),"transforms":pool.get_transforms(id)})
			if crew.get("_impacts").has(id): impact_skins.append(skeleton_state(crew.get("_impacts")[id]))
	for original: Dictionary in crew.probe.events:
		var event := original.duplicate(true)
		if event.has("body_id"): event.body_id = body_label(str(event.body_id))
		if event.has("position"):
			physical_events.append({"index":events.size(),"position":event.position}); event.erase("position")
		events.append(event)
	return {"phase":crew.get("_time"),"distance":crew.get("_distance"),"allocation":crew.get("_allocation"),"lod":crew.get("_lod"),"roles":crew.diagnostics().roles,"standing":standing,"retired":retired,"poolPhase":pool.get("_phase") if pool else null,"poolAdvanceCount":pool.get("advances").size() if pool else 0,"poolAdvanceHash":digest(pool.get("advances")) if pool else "","deckRegisterCount":pool.get("registrations").size() if pool else 0,"deckRegisterHash":digest(pool.get("registrations")) if pool else "","bodies":bodies,"physics":{"transforms":impact_transforms,"skins":impact_skins,"eventPositions":physical_events},"lossBudget":crew.get("_loss_budget"),"seen":crew.get("_seen").duplicate(true),"callbacks":crew.probe.callbacks.duplicate(true),"releases":crew.probe.releases.duplicate(),"events":events}

func same_physics(a: Variant, b: Variant) -> bool:
	if typeof(a) != typeof(b): return false
	if a is Transform3D or a is Vector3 or a is Basis: return a.is_equal_approx(b)
	if a is float: return is_equal_approx(a,b)
	if a is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_physics(a[index],b[index]): return false
		return true
	if a is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_physics(a[key],b[key]): return false
		return true
	return a == b

func compare(label: String) -> void:
	var before := capture(pair[0].crew); var after := capture(pair[1].crew)
	# Standing/retired source animation and bookkeeping must be byte-identical.
	# Live Jolt transforms are compared with Godot's standard approximate matrix
	# predicate, never relabelled as byte-identical physics across distinct worlds.
	var a: Dictionary = before.physics; var b: Dictionary = after.physics
	before.erase("physics"); after.erase("physics")
	check(var_to_bytes(before) == var_to_bytes(after),label+": exact source bones/root/roles/ownership-event state")
	check(same_physics(a,b),label+": live Jolt transforms, impact skins and water-entry positions")
	rows.append({"case":label,"baseline":digest(before),"candidate":digest(after),"baselineWork":pair[0].crew.probe.duplicate(true),"candidateWork":pair[1].crew.probe.duplicate(true),"liveJoltBodies":a.transforms.size()})

func present(label: String, consumed: float = 0.0, events: Array = []) -> void:
	for owner: Dictionary in pair:
		owner.ship.apply_snapshot(state,{},consumed)
		owner.crew.set_ship_model(owner.ship.get_model())
		owner.crew.set_lod_distance(distance); owner.crew.set_allocation(allocation)
		owner.crew.apply_snapshot(state,{},consumed)
	# Preserve production's snapshot-before-events handoff, including retired skins.
	for owner: Dictionary in pair: owner.crew.apply_events(events)
	compare(label)

func identities(crew: ObservedCrew) -> Array:
	var result := []
	for instance: Dictionary in crew.get_instances(): result.append([instance.root.get_instance_id(),instance.skeleton.get_instance_id()])
	return result

func physics_steps(count: int, label: String) -> void:
	for index in count:
		state.time += STEP
		for owner: Dictionary in pair:
			var pose: Transform3D = owner.ship.remember_authoritative_pose(state,state.time)
			owner.crew.advance_impacts(state.time,STEP,pose)
		await physics_frame
		await process_frame
		present(label+"/"+str(index),STEP)

func hit(id: String, damage: float) -> Array:
	return [{"type":"hit","id":id,"targetId":state.id,"position":{"x":0.0,"y":2.0,"z":0.0},"velocity":{"x":10.0,"y":0.0,"z":0.0},"damage":{"crew":damage}}]

func release_pair() -> void:
	for owner: Dictionary in pair:
		owner.crew.dispose(); owner.ship.dispose(); owner.library.dispose()
		check(owner.crew.get("_instances").is_empty() and owner.crew.get("_retired").is_empty() and owner.crew.get_impact_pool() == null,"dispose clears all source crew/pool ownership")
	if pair.size() == 2: check(pair[0].crew.probe.callbacks == pair[1].crew.probe.callbacks,"dispose preserves release callback sequence")
	for owner: Dictionary in pair: owner.viewport.free()
	pair.clear()

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
		elif arg.begins_with("--candidate="): candidate = arg.trim_prefix("--candidate=")
		elif arg == "--require-work-reduction": require_work_reduction = true
	if output.is_empty() or FileAccess.file_exists(output) or candidate not in ["baseline","setters"]:
		printerr("fresh --output= and --candidate=baseline|setters required"); quit(1); return
	check(Engine.physics_ticks_per_second == 60,"real Jolt driver retains production 60Hz")
	var source_hashes := {}
	for path: String in [FROZEN,"res://tools/research-crew-reconciliation.gd","res://game/presentation/ships/ship_view.gd","res://game/presentation/crew/deck_stations.gd","res://modules/physics_engine/impacts/impact_pool.gd","res://modules/physics_engine/impacts/impact_bone.gd","res://modules/scene_engine/assets/asset_library.gd","res://assets/models/sailors/sailor-lod0.glb","res://assets/models/sailors/sailor-lod1.glb","res://assets/models/sailors/sailor-lod2.glb"]: source_hashes[path] = FileAccess.get_sha256(path)
	for kind: String in Ship.KINDS:
		if not make_pair(kind): release_pair(); break
		present(kind+"/initial")
		for lod in 3:
			for owner: Dictionary in pair: owner.ship.set_lod_distance([0.0,300.0,700.0][lod])
			distance = [50.0,200.0,700.0][lod]; present(kind+"/real-model-lod"+str(lod))
			check(pair[1].crew.get_visible_count() > 0 and pair[1].crew.get_visible_count() <= [24,8,2][lod],"all three LODs retain actual standing crew within original caps")
			for instance: Dictionary in pair[1].crew.get_instances(): check(instance.skeleton.get_bone_count() == 18,"actual eighteen-bone authored sailor")
		for owner: Dictionary in pair: owner.ship.set_lod_distance(0.0)
		distance = 50.0; present(kind+"/stable-seed")
		var previous := [identities(pair[0].crew),identities(pair[1].crew)]
		var old_samples: int = pair[0].crew.probe.samples; var new_samples: int = pair[1].crew.probe.samples
		for frame in 8: present(kind+"/same-time-stable"+str(frame))
		check(previous == [identities(pair[0].crew),identities(pair[1].crew)],"stable batches retain own model/skeleton identities")
		check(pair[0].crew.get_instances()[0].skeleton != pair[1].crew.get_instances()[0].skeleton,"owners never share mutable skeleton")
		var old_work: int = pair[0].crew.probe.samples-old_samples; var new_work: int = pair[1].crew.probe.samples-new_samples
		check(new_work < old_work if candidate == "setters" or require_work_reduction else new_work == old_work,"actual stable seek work changes only with selected candidate")
		for next: float in [89.0,110.1,109.0,90.1,89.9,329.9,330.0,270.1,269.9,700.0,1800.0,1800.1,1900.0,1800.0,50.0]:
			distance = next
			for owner: Dictionary in pair: owner.crew.set_lod_distance(distance)
			compare(kind+"/immediate-distance"+str(next)); present(kind+"/distance"+str(next))
		for next: int in [24,24,99,24,8,8,2,0,0,1,24]:
			allocation = next
			for owner: Dictionary in pair: owner.crew.set_allocation(allocation)
			compare(kind+"/immediate-allocation"+str(next)); present(kind+"/allocation"+str(next))
		for reduced: bool in [true,false]:
			for owner: Dictionary in pair: owner.crew.set_reduced_motion(reduced)
			for phase: float in [21.0,21.0,20.0,0.0,20.5]: state.time = phase; present(kind+"/rewind-reduced"+str([reduced,phase]))
		state.crew = 2.0; present(kind+"/two-skins")
		present(kind+"/nonlethal-birth",0.0,hit(kind+"-recover",.5))
		check(pair[0].crew.get_impact_pool().get_body_count() == 1,"real nonlethal Jolt body is born")
		await physics_steps(80,kind+"/recovery")
		check(pair[0].crew.get_impact_pool().get_body_count() == 0,"accepted expiry returns nonlethal skin")
		check(pair[0].crew.probe.callbacks.any(func(event: Dictionary): return event.recover),"actual nonlethal recovery callback executes")
		for owner: Dictionary in pair: owner.crew.set_environment(wet)
		present(kind+"/wet-birth",0.0,hit(kind+"-wet",.5))
		await physics_steps(80,kind+"/wet-transition")
		check(pair[0].crew.get_impact_pool().get_body_count() == 0,"wet lifetime releases live articulated body")
		check(pair[0].crew.probe.events.any(func(event: Dictionary): return event.type == "crew-water-entry"),"actual Jolt water transition publishes a visual event")
		for owner: Dictionary in pair: owner.crew.set_environment(dry)
		state.time += STEP; state.crew = 0.0; state.hull = 0.0
		present(kind+"/terminal-casualty",STEP,hit(kind+"-terminal",2.0))
		check(pair[0].crew.get_impact_pool().get_body_count() == 2,"terminal loss transfers both retired skins before release")
		await physics_steps(2,kind+"/terminal-live-jolt")
		state = initial(kind,0.0); present(kind+"/impact-rewind")
		check(pair[0].crew.get_impact_pool().get_body_count() == 0,"rewind releases old impacts")
		var held := []
		for owner: Dictionary in pair:
			held.append(weakref(owner.crew.get_instances()[0].root)); owner.crew.dispose()
			check(owner.crew.configure(kind,owner.ship.get_model(),owner.library),"same-owner reconfigure binds real source deck")
			owner.crew.set_environment(dry); owner.crew.observe_pool()
		present(kind+"/reconfigure")
		for reference: WeakRef in held: check(reference.get_ref() == null,"reconfigure releases prior sailor nodes")
		release_pair()
	var report := {"schema":"crew-reconciliation-research-v1","candidate":candidate,"requireWorkReduction":require_work_reduction,"assertions":assertions,"failures":failures,"rows":rows,"sourceHashes":source_hashes,"engine":Engine.get_version_info(),"scope":"Research-only frozen CrewView subclasses. Two setters only; empty apply_events unchanged. Exact authored standing/retired bones, roots, roles and lifecycle event metadata after owner-ID normalization; standard approximate live Jolt transforms/skins/water positions in isolated World3Ds. Counts are seek/reconcile work, not FPS, GPU or flush timing."}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file == null: check(false,"fresh output opens")
	else: file.store_string(JSON.stringify(report,"\t")); file.close()
	print("CREW_RECONCILIATION_RESEARCH assertions=",assertions," failures=",failures.size()," candidate=",candidate," output=",output)
	quit(1 if not failures.is_empty() else 0)
