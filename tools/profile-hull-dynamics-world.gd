extends SceneTree
## Actual public sail entry; fresh accepted-time CPU stage isolation, never FPS.
## Root runs this alone. No effects, actors, crew, terrain or ocean are removed.
const Main = preload("res://game/scenes/main/main_scene.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const Crew = preload("res://game/presentation/crew/crew_view.gd")
const Packet = preload("res://game/presentation/world/source_water_packet.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const STEP := 1.0 / 60.0
const WATCHED := ["res://game/scenes/naval_practice/naval_practice.gd","res://game/runtime/naval_practice_runtime.gd","res://game/presentation/world/naval_world_view.gd","res://modules/scene_engine/world/world_view.gd","res://game/presentation/crew/crew_view.gd","res://modules/scene_engine/water/hull_contact_froth.gd","res://game/presentation/world/target_rigid_shadow_caster.gd","res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd","res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd","res://modules/scene_engine/fidelity_fx/source_shadow_math.gd"]
var main: Node
var game: Node
var sample_count := 12
var warmup_frames := 12
var output := "res://docs/migration/evidence/hull-dynamics-2026-10-14/performance/world-cpu.json"
var failures: Array[String] = []
var proxies: Dictionary = {}
var slots: Array[RefCounted] = []

class MemorySlot extends RefCounted:
	var writes := 0
	func read_checkpoint() -> Dictionary: return {"ok":false,"reason":"save-not-found"}
	func write_checkpoint(_raw: String) -> Dictionary:
		writes += 1
		return {"ok":false,"reason":"inspection-write-forbidden"}

class ContactTimer extends RefCounted:
	var delegate: RefCounted
	var elapsed_us := 0
	var apply_calls := 0
	var redraw_calls := 0
	func _init(effect: RefCounted) -> void: delegate = effect
	func reset() -> void: elapsed_us = 0; apply_calls = 0; redraw_calls = 0
	func apply_snapshot(packet: Dictionary, seconds: float, water: Callable, sea: Callable) -> void:
		var start := Time.get_ticks_usec()
		delegate.apply_snapshot(packet,seconds,water,sea)
		elapsed_us += Time.get_ticks_usec()-start
		apply_calls += 1
	func redraw_camera(camera: Dictionary) -> void:
		var start := Time.get_ticks_usec()
		delegate.redraw_camera(camera)
		elapsed_us += Time.get_ticks_usec()-start
		redraw_calls += 1
	func diagnostics() -> Dictionary: return delegate.diagnostics()
	func dispose() -> void: delegate.dispose()
	func configure(parent: Node3D, family: int, seed: int, resource: String = "") -> Dictionary:
		return delegate.configure(parent,family,seed,resource)

func _initialize() -> void: run.call_deferred()

func check(ok: bool, message: String) -> bool:
	if not ok: failures.append(message); printerr("FAIL: ",message)
	return ok

func measure(costs: Dictionary, name: String, job: Callable) -> Variant:
	var start := Time.get_ticks_usec()
	var result: Variant = job.call()
	costs[name] = float(Time.get_ticks_usec()-start)/1000.0
	return result

func freeze_callbacks(node: Node) -> void:
	node.set_process(false)
	node.set_physics_process(false)
	node.set_process_input(false)
	node.set_process_unhandled_input(false)
	for child: Node in node.get_children(): freeze_callbacks(child)

func hashes() -> Dictionary:
	var values: Dictionary = {}
	for path: String in WATCHED: values[path] = FileAccess.get_sha256(path)
	return values

func install_contact_timers() -> void:
	var renderer: RefCounted = game.sea.wakes.get("_source_wakes")
	if not check(renderer != null,"actual source-wake renderer exists after warmup"): return
	var actors: Dictionary = renderer.get("_actors")
	for id: String in actors:
		var actor: Dictionary = actors[id]
		if actor.froth == null: continue
		var timer := ContactTimer.new(actor.froth)
		actor.froth = timer
		proxies[id] = timer
	check(proxies.size()==game.sea.ships.size(),"each actual contact owner retains its original delegate")

func profile_shadows(sea: Node3D, native: Dictionary, costs: Dictionary) -> Dictionary:
	# Exactly one execution of the production _apply_source_shadows sequence.
	# Compose is the real caster adapter, not a copied topology implementation.
	if sea.source_shadows==null: return {"active":false}
	var total_start := Time.get_ticks_usec()
	var world_light: Vector3 = -sea.get("_sun").global_basis.z
	var status: Dictionary = measure(costs,"sourceShadowStatus",func(): return sea.source_shadow_status())
	var settings: Dictionary = sea.get("_settings")
	var display: bool = bool(Sea.QUALITY.get(settings.quality,Sea.QUALITY.balanced).shadows)
	var adapter: RefCounted = sea.get("_rigid_casters")
	var renderer: RefCounted = sea.source_shadows
	var packet: Dictionary = measure(costs,"sourceShadowCompose",func(): return adapter.compose(native,sea.ships,world_light,bool(status.stencilActive),display))
	var merge_start := Time.get_ticks_usec()
	packet.actors.merge(sea.ships,false)
	costs.sourceShadowActorMerge = float(Time.get_ticks_usec()-merge_start)/1000.0
	measure(costs,"sourceShadowSubmit",func(): renderer.apply_snapshot(packet.native,packet.actors,native.get("environment",{})))
	costs.sourceShadows = float(Time.get_ticks_usec()-total_start)/1000.0
	# Collect only compact actual input metadata after the measured pipeline.
	var state: Dictionary = packet.native.get("sourceShadows",{})
	var casters: Array = state.get("casters",[])
	var dirty := 0
	var edges := 0
	var caps := 0
	var points := 0
	var caster_rows: Array = []
	for caster: Dictionary in casters:
		dirty += int(bool(caster.get("dirty",false)))
		edges += caster.get("edges",[]).size()
		caps += caster.get("capIndices",[]).size()
		points += caster.get("positions",[]).size()
		caster_rows.append({"id":caster.get("id"),"dirty":caster.get("dirty"),"geometryRevision":caster.get("geometryRevision"),"localLight":caster.get("localLight"),"worldRotation":caster.get("worldRotation"),"policy":caster.get("policy")})
	return {"active":true,"stencilActive":status.stencilActive,"displayShadows":state.get("displayShadows"),"worldLight":world_light,"casterCount":casters.size(),"dirtyCount":dirty,"edgeCount":edges,"capIndexCount":caps,"sourcePositionCount":points,"adapter":adapter.diagnostics(),"rendererRebuildCount":renderer.get("_rebuild_count"),"sourceCasters":caster_rows,"sourceShadowInputSHA256":JSON.stringify(caster_rows).sha256_text()}

func profile_sea(native: Dictionary, events: Array, consumed: float, costs: Dictionary) -> Array:
	var sea: Node3D = game.sea
	var sea_begin := Time.get_ticks_usec()
	check(float(native.time)>=float(sea.get("_snapshot").get("time",0.0)),"controlled native time is monotonic")
	var next_battle: String = str(native.get("battleId",""))
	check(next_battle==str(sea.get("_battle_id")),"diagnostic retains the warmup battle/route epoch")
	sea.set("_battle_id",next_battle)
	measure(costs,"seaSnapshotCopy",func(): sea.set("_snapshot",native.duplicate(true)))
	measure(costs,"camera",func(): sea._update_camera(native,consumed))
	measure(costs,"effectsBegin",func(): sea.effects.begin_snapshot(native,consumed))
	var requests: Array = []
	var start := Time.get_ticks_usec()
	for ship: Dictionary in native.ships:
		var p: Dictionary = ship.visual.position
		var distance: float = sea.camera.position.distance_to(Vector3(p.x,p.y,p.z))
		var requested: int = mini(24,int(ship.crew)) if distance<=220 else mini(8,int(ship.crew)) if distance<=650 else mini(2,int(ship.crew)) if distance<=1200 else 0
		requests.append({"id":ship.id,"distance":distance,"requested":requested})
	var allocations: Dictionary = Crew.allocate_sailors(requests)
	costs.crewBudget = float(Time.get_ticks_usec()-start)/1000.0
	var live: Dictionary = {}
	var per_ship: Array = []
	for ship: Dictionary in native.ships:
		var id: String = str(ship.id)
		live[id] = true
		var one: Dictionary = {}
		var view: Node3D = measure(one,"prepare",func(): return sea._prepare_ship(ship))
		if not check(view!=null,"existing real ship presenter remains available: "+id): continue
		var timed: Dictionary = measure(one,"snapshotCopy",func(): return ship.duplicate(true))
		timed.time = native.time
		var actor_seconds: float = maxf(0.0,consumed-float(sea.get("_local_presentation_seconds").get(id,0.0)))
		measure(one,"shipPose",func(): view.apply_snapshot(timed,native.get("wind",{}),actor_seconds))
		measure(one,"shipLOD",func(): view.set_lod_distance(sea.camera.position.distance_to(view.position)))
		var crew: Node3D = sea.sailors[id]
		measure(one,"crewModel",func(): crew.set_ship_model(view.get_model()))
		measure(one,"crewLOD",func(): crew.set_lod_distance(sea.camera.position.distance_to(view.position)))
		measure(one,"crewAllocation",func(): crew.set_allocation(int(allocations.get(id,0))))
		measure(one,"crewPose",func(): crew.apply_snapshot(timed,native.get("wind",{}),actor_seconds))
		for key: String in one: costs["actors_"+key] = float(costs.get("actors_"+key,0.0))+float(one[key])
		per_ship.append({"id":id,"kind":ship.kind,"stageMs":one,"allocation":allocations.get(id,0)})
	start = Time.get_ticks_usec()
	for id: String in sea.ships.keys():
		if not live.has(id): sea._release_ship(id)
	costs.actorRelease = float(Time.get_ticks_usec()-start)/1000.0
	measure(costs,"effectsFinish",func(): sea.effects.finish_snapshot())
	var presented: Array = measure(costs,"eventCompose",func(): return sea._source_fire_events(events))
	measure(costs,"actorEvents",func():
		for id: String in sea.ships:
			sea.ships[id].apply_events(presented)
			sea.sailors[id].apply_events(presented))
	measure(costs,"effectEvents",func(): sea.effects.apply_events(presented))
	measure(costs,"crewWaterEvents",func(): sea._flush_crew_water_entries())
	var water_packet: Dictionary = measure(costs,"waterPacket",func(): return Packet.compose(native,sea.ships,sea.camera))
	for timer: ContactTimer in proxies.values(): timer.reset()
	measure(costs,"wakesTotal",func(): sea.wakes.apply_snapshot(water_packet))
	var local_us := 0
	var local_calls := 0
	var redraw_calls := 0
	for timer: ContactTimer in proxies.values():
		local_us += timer.elapsed_us
		local_calls += timer.apply_calls
		redraw_calls += timer.redraw_calls
	costs.wakesLocalContact = float(local_us)/1000.0
	costs.wakesOldRemainder = maxf(0.0,float(costs.wakesTotal)-float(costs.wakesLocalContact))
	measure(costs,"world",func(): sea.world.apply_snapshot(sea._world_packet(native),consumed))
	var shadow_inputs: Dictionary = profile_shadows(sea,native,costs)
	sea.get("_local_presentation_seconds").clear()
	costs.seaInstrumentedWall = float(Time.get_ticks_usec()-sea_begin)/1000.0
	costs["_shipRecords"] = per_ship
	costs["_localApplyCalls"] = local_calls
	costs["_localRedrawCalls"] = redraw_calls
	costs["_shadowInputs"] = shadow_inputs
	return presented

func stats(values: Array) -> Dictionary:
	if values.is_empty(): return {"count":0}
	var sorted := values.duplicate(); sorted.sort()
	var total := 0.0
	for value: Variant in values: total += float(value)
	return {"count":values.size(),"mean":total/float(values.size()),"p50":sorted[ceili(.5*sorted.size())-1],"p95":sorted[ceili(.95*sorted.size())-1],"minimum":sorted[0],"maximum":sorted[-1]}

func metadata() -> Dictionary:
	var rows: Array = []
	for id: String in game.sea.ships:
		var view: Node3D = game.sea.ships[id]
		var crew: Node3D = game.sea.sailors[id]
		rows.append({"id":id,"distance":game.sea.camera.position.distance_to(view.position),"shipLOD":view.get_lod(),"crew":crew.diagnostics(),"contact":proxies[id].diagnostics() if proxies.has(id) else {}})
	return {"ships":rows,"world":game.sea.world.fidelity_diagnostics(),"effects":game.sea.effects.diagnostics(),"wakes":game.sea.wakes.diagnostics()}

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--samples="): sample_count = int(arg.trim_prefix("--samples="))
		if arg.begins_with("--warmup="): warmup_frames = int(arg.trim_prefix("--warmup="))
		if arg.begins_with("--output="): output = arg.trim_prefix("--output=")
	if not check(sample_count>=6 and sample_count<=32,"samples must be 6..32"): quit(1); return
	if not check(warmup_frames>=3 and warmup_frames<=60,"warmup must be 3..60 frames"): quit(1); return
	if not check(not FileAccess.file_exists(output),"fresh output required"): quit(1); return
	create_timer(90.0).timeout.connect(func():
		printerr("HULL_WORLD_CPU watchdog expired")
		quit(1))
	root.size = Vector2i(1200,900); root.content_scale_size = root.size
	var career := MemorySlot.new(); var legacy := MemorySlot.new()
	slots = [career,legacy]
	var settings := Settings.new("user://verification/hull-world-no-write-%d.json"%OS.get_process_id())
	main = Main.new()
	main.router = Router.new({"mingqi_storage":career,"legacy_storage":legacy,"settings_storage":settings})
	root.add_child(main)
	for frame: int in 5: await process_frame
	if not is_instance_valid(main.current_scene):
		var button: Button = main.menu.find_child("sail",true,false)
		if check(button!=null and not button.disabled,"actual public sail menu exists"): button.pressed.emit()
	for frame: int in 400:
		await process_frame
		if is_instance_valid(main.current_scene) and bool(main.current_scene.get("startup_receipt").get("ok",false)): break
	if not check(is_instance_valid(main.current_scene),"actual public route initialized"): main.free(); quit(1); return
	game = main.current_scene
	if not check(game.runtime.snapshot().runtime.get("mode","")=="sail","actual NavalPractice sail route"): main.free(); quit(1); return
	root.grab_focus()
	game.runtime.set_pause("menu",false); game.runtime.set_pause("player",false); game.runtime.set_pause("blur",false)
	for frame: int in warmup_frames: await process_frame
	freeze_callbacks(main)
	game.runtime.set_pause("blur",false)
	game._present(0.0)
	install_contact_timers()
	var source_before := hashes()
	var initial: Dictionary = game.runtime.snapshot()
	var initial_meta := metadata()
	var records: Array = []
	for index: int in sample_count:
		var costs: Dictionary = {}
		var before: Dictionary = game.runtime.snapshot()
		measure(costs,"projectileObservation",func(): game.sea.observe_projectiles(before.naval))
		var accepted: float = measure(costs,"runtimeAdvance",func(): return game.runtime.advance(STEP))
		var native: Dictionary = game.runtime.simulation.snapshot()
		if not check(accepted>0.0 and float(native.time)>float(before.naval.time),"fresh accepted native sample"): break
		game._sync_presentation_epoch(native)
		var terminal: RefCounted = game.get("_terminal_presentation")
		var tail: float = terminal.advance(native,game.runtime.presentation_pause_reasons(),STEP,accepted)
		var visual: Dictionary = terminal.snapshot(native)
		var consumed: float = accepted+tail
		game.set("_pending_presentation_seconds",0.0)
		measure(costs,"authoritativePoseHistory",func(): game.sea.remember_authoritative_poses(visual,consumed))
		var packet: Dictionary = measure(costs,"runtimeSnapshot",func(): return game.runtime.snapshot())
		var events: Array = measure(costs,"eventDrain",func(): return game.runtime.drain_events())
		var presented: Array = profile_sea(visual,events,consumed,costs)
		measure(costs,"services",func(): game.services.present(visual,presented,consumed,packet.runtime.paused))
		measure(costs,"interface",func(): game.interface.apply_snapshot(packet))
		measure(costs,"inputPresentation",func():
			if not game._mouse_sailing_ready(): game.get("_mouse_course").cancel_gesture()
			if not game._camera_input_ready(): game.sea.cancel_camera_drag())
		measure(costs,"minimap",func(): game.minimap.present(packet.naval,{},game.services.captures_keyboard() or game.interface.is_menu_open() or game.interface.chart.visible or not packet.runtime.surrenderQuote.is_empty() or packet.naval.status in ["victory","defeat","surrendered"]))
		var ship_rows: Array = costs.get("_shipRecords",[])
		var apply_calls: int = int(costs.get("_localApplyCalls",0))
		var redraw_calls: int = int(costs.get("_localRedrawCalls",0))
		var shadow_inputs: Dictionary = costs.get("_shadowInputs",{})
		costs.erase("_shipRecords"); costs.erase("_localApplyCalls"); costs.erase("_localRedrawCalls"); costs.erase("_shadowInputs")
		records.append({"index":index,"acceptedSeconds":accepted,"nativeTime":native.time,"nativeTick":native.tick,"stageMs":costs,"shipStages":ship_rows,"localApplyCalls":apply_calls,"localRedrawCalls":redraw_calls,"actualSourceShade":shadow_inputs})
		await process_frame
	var summaries: Dictionary = {}
	if not records.is_empty():
		for key: String in records[0].stageMs:
			var values: Array = []
			for record: Dictionary in records: values.append(record.stageMs.get(key,0.0))
			summaries[key] = stats(values)
	check(records.size()==sample_count,"all requested fresh samples completed")
	check(source_before==hashes(),"production source remains frozen")
	var accepted_local: Array = []
	var camera_local: Array = []
	for record: Dictionary in records:
		if int(record.localApplyCalls)>0: accepted_local.append(record.stageMs.wakesLocalContact)
		elif int(record.localRedrawCalls)>0: camera_local.append(record.stageMs.wakesLocalContact)
	for slot: RefCounted in slots: check(slot.writes==0,"no user save writes")
	var report := {"scope":"Real Main public sail entry/NavalPractice warmup, then disabled automatic process/physics/input callbacks and fixed real runtime.advance(1/60). All scene objects remain; fresh Sea production order reproduced in this diagnostic with separate stage timers. ContactTimer delegates to the existing production owner within actual scoped Wakes. CPU call wall-clock measurements; no FPS, GPU timing, appearance or exact normal-frame sum claim. effectsBegin/Finish preserve real async overlap; wakesLocalContact and wakesOldRemainder are children of wakesTotal, not additive extra stages. Old remainder includes tail, scope, packet merge and renderer work, not pure tail. world is the actual full world wrapper once at fresh time, not same-time cache replay. Shadow status/compose/actor merge/submit replace the single production wrapper once in its original order, with the original caster adapter, renderer, light and native fields. Shadow submit includes renderer CPU volume refresh, texture-plane reconciliation and compositor submit; it does not measure GPU render-thread draws or establish GPU readback time.","failures":failures,"samples":records.size(),"warmupFrames":warmup_frames,"fixedStepSeconds":STEP,"initialNative":initial.naval,"finalNative":game.runtime.snapshot().naval,"initialActors":initial_meta,"finalActors":metadata(),"stageMs":summaries,"records":records,"localAcceptedCallMs":stats(accepted_local),"localCameraOnlyMs":stats(camera_local),"localCadenceNote":"Native controlled advance is 60Hz; source call index is 32Hz. Mixed local p50 includes deduplicated camera-only samples and is not the fresh contact cost per ship.","sourceHashes":source_before,"actualSourceShade":{"casterAdapterSHA256":source_before["res://game/presentation/world/target_rigid_shadow_caster.gd"],"rendererSHA256":source_before["res://modules/scene_engine/fidelity_fx/source_shadow_renderer.gd"],"compositorSHA256":source_before["res://modules/scene_engine/fidelity_fx/source_shadow_compositor.gd"],"mathSHA256":source_before["res://modules/scene_engine/fidelity_fx/source_shadow_math.gd"]},"toolSHA256":FileAccess.get_sha256("res://tools/profile-hull-dynamics-world.gd"),"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"display":DisplayServer.get_name(),"headless":DisplayServer.get_name()=="headless","terrainRoute":"NavalPractice uses ReferenceGeography.options() natural islands; distinct from earlier Legacy source_options reference-island CPU controls"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output.get_base_dir()))
	var file := FileAccess.open(output,FileAccess.WRITE)
	if check(file!=null,"evidence output opens"): file.store_string(JSON.stringify(report,"\t")); file.close()
	print("HULL_WORLD_CPU samples=",records.size()," failures=",failures," stages=",summaries)
	main.free()
	quit(1 if not failures.is_empty() else 0)
