extends SceneTree
## Actual production free-sail renderer, deterministic accepted inputs and clock.
## This is a QA driver, never a new player scene or menu entry.
const Practice = preload("res://game/scenes/naval_practice/naval_practice.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
const ContactFroth = preload("res://modules/scene_engine/water/hull_contact_froth.gd")
const SourceFroth = preload("res://modules/scene_engine/water/source_froth.gd")
var scene: Node3D
var failures: Array[String] = []
var records: Array = []
var phase := "before"
var output := ""
var legacy_geometry: Script
var legacy_froth: Script
var legacy_updates: Dictionary = {}
var isolated_visibility: Dictionary = {}
var isolate_final := false
var probe_feather := false
var baseline_source := false
var expect_flow := false
func _initialize() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): compatibility_self_test.call_deferred()
	else: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("FAIL wake GPU: ", message)

func compatibility_self_test() -> void:
	check(has_method("baseline_packet"),"source baseline packet adapter exists")
	check(has_method("flow_diagnostic_valid"),"candidate diagnostic contract is checked")
	if failures.is_empty():
		var original := {"time":1.0,"wake":{"sourceCallIndex":32},"ships":[{"id":"one","sourceWake":{"targetTrail":{"enabled":true,"position":Vector3.ZERO},"sourceClock":1.0}},{"id":"raw","sourceWake":{"sourceClock":1.0}}]}
		var before := var_to_bytes(original)
		var baseline: Dictionary = call("baseline_packet", original)
		check(not baseline.ships[0].sourceWake.targetTrail.enabled,"baseline explicitly disables target adapter")
		check(var_to_bytes(original)==before and baseline.ships[1]==original.ships[1],"baseline never edits caller or raw source fixture")
		var report := {"samples":2,"time":1.0,"length_m":3.0,"emitting":true,"visible":true,"vertices":6,"updates":2,"lifetime_seconds":14.0}
		check(call("flow_diagnostic_valid",report,1.0),"complete accepted candidate public state accepted")
		check(not call("flow_diagnostic_valid",{},1.0),"missing candidate public state refused")
		check(not call("flow_diagnostic_valid",report,2.0),"stale candidate time refused")
		report.vertices=0
		check(not call("flow_diagnostic_valid",report,1.0),"visible candidate requires actual mesh vertices")
	print("WAKE_GPU_TOOL_SELF_TEST_PASS failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

static func expected_capture_labels(feather: bool, isolated: bool) -> Array:
	var labels := ["01-start","02-straight-4s","03-straight-12s","04-turn-5s","05-turn-12s","06-stopped-10s","07-resume-5s"]
	if feather: labels.append("08-resume-edge-feather-probe")
	if isolated: labels.append_array(["08-resume-strip-only","09-resume-local-froth-only","10-resume-spray-only"])
	return labels

static func capture_inventory_valid(captures: Array, feather: bool, isolated: bool) -> bool:
	var expected := expected_capture_labels(feather,isolated)
	if captures.size() != expected.size(): return false
	for index in expected.size():
		if not captures[index] is Dictionary or captures[index].get("label") != expected[index]: return false
	return true

static func baseline_packet(packet: Dictionary) -> Dictionary:
	var result := packet.duplicate(true)
	for ship: Dictionary in result.get("ships", []):
		var trail: Variant = ship.get("sourceWake", {}).get("targetTrail")
		if trail is Dictionary: trail.enabled = false
	return result

static func flow_diagnostic_valid(report: Dictionary, accepted_time: float) -> bool:
	if not report.has_all(["samples","time","length_m","emitting","visible","vertices","updates","lifetime_seconds"]): return false
	for key in ["samples","time","length_m","vertices","updates","lifetime_seconds"]:
		if not (report[key] is float or report[key] is int) or not is_finite(float(report[key])) or float(report[key]) < 0: return false
	if not report.emitting is bool or not report.visible is bool or not is_equal_approx(float(report.time),accepted_time): return false
	return not report.visible or (int(report.samples) >= 2 and int(report.vertices) >= 3 and float(report.length_m) > 0.0)

static func froth_diagnostic(effect: RefCounted, legacy: Script = null) -> Dictionary:
	if effect is ContactFroth:
		return {"ok":true,"kind":"target-hull-contact","diagnostics":effect.diagnostics()}
	if not (effect is SourceFroth or (legacy != null and effect.get_script() == legacy)):
		return {"ok":false,"kind":"unknown","reason":"unrecognized-froth-implementation"}
	var transparent := 0; var authored := 0
	if effect._surface != null:
		for key: String in effect._surface.nodes:
			if not key.begins_with("bow_") and not key.begins_with("side_"): continue
			var node: MeshInstance3D = effect._surface.nodes[key]
			if not node.visible or node.mesh == null or node.mesh.get_surface_count() == 0: continue
			var arrays: Array = node.mesh.surface_get_arrays(0)
			for color: Color in arrays[Mesh.ARRAY_COLOR]:
				authored += 1
				if color.a == 0.0: transparent += 1
	return {"ok":true,"kind":"authored-source-froth","diagnostics":effect.diagnostics(),"authoredVertices":authored,"transparentVertices":transparent,"particles":effect._particles.diagnostics() if effect._particles != null else {}}

func isolate_froth(effect: RefCounted, spray_only: bool) -> void:
	var nodes: Dictionary = {}
	if effect is ContactFroth:
		# Explicit observed target scene nodes; public diagnostics above remain
		# the evidence contract. Never look for source-only Surface/Particles.
		for node: Node in effect._container.get_children():
			if node is MeshInstance3D: nodes[str(node.name)] = node
	elif effect is SourceFroth or (legacy_froth != null and effect.get_script() == legacy_froth): nodes = effect._surface.nodes
	else: check(false,"unsupported froth isolation"); return
	for key: String in nodes:
		var node: MeshInstance3D = nodes[key]
		var token := node.get_instance_id()
		if not isolated_visibility.has(token): isolated_visibility[token] = node.visible
		var spray := key == "ContactSpray" if effect is ContactFroth else key.begins_with("ParticleSystem_")
		var local := key in ["FlowPort","FlowStarboard"] if effect is ContactFroth else key.begins_with("bow_") or key.begins_with("side_")
		node.visible = bool(isolated_visibility[token]) and (spray if spray_only else local)
func frames(count: int) -> void:
	for _i in count: await process_frame
func ticks(count: int) -> void:
	for i in count:
		scene.runtime.set_pause("blur", false)
		scene._physics_process(1.0 / 60.0)
		# This is the real presentation path. At 30Hz it consumes the same
		# accepted source-call indices as ordinary player presentation.
		if i % 2 == 0:
			scene._present(0.0)
			apply_baseline_geometry()
			await process_frame
	scene._present(0.0)
	apply_baseline_geometry()
func apply_baseline_geometry() -> void:
	if legacy_geometry == null and not baseline_source and phase != "before": return
	var renderer: RefCounted = scene.sea.wakes._source_wakes
	if renderer == null: return
	var native: Dictionary = scene.runtime.snapshot().naval
	var packet: Dictionary = preload("res://game/presentation/world/source_water_packet.gd").compose(native,scene.sea.ships,scene.sea.camera)
	# The renderer's explicit selection gate releases target flow and restores
	# the source strip without changing native history/RNG or authoritative time.
	renderer.apply_snapshot(baseline_packet(packet),scene.sea.wakes._water,scene.sea.wakes._surface_filter)
	if legacy_geometry == null: return
	for ship: Dictionary in packet.ships:
		if not renderer._actors.has(ship.id): continue
		var actor: Dictionary = renderer._actors[ship.id]
		if actor.history == null: continue
		if legacy_updates.get(ship.id,-1) != actor.history.updates:
			actor.geometry = legacy_geometry.build(actor.history,ship.sourceWake,native.time,scene.sea.wakes._water,scene.sea.wakes._surface_filter)
			legacy_updates[ship.id] = actor.history.updates
		elif not actor.geometry.is_empty():
			renderer._fit_water(actor.geometry,native.time,scene.sea.wakes._water)
		if not actor.geometry.is_empty():
			actor.surface.submit("SceneStrip",actor.geometry.vertices,actor.geometry.uvs,actor.geometry.colors,actor.geometry.indices,{"texture":"wake3unique.dds","alphaFlags":4333,"clampMode":3})
func capture(label: String) -> void:
	await frames(3); await RenderingServer.frame_post_draw
	var pixels := root.get_texture().get_image()
	if pixels == null or pixels.is_empty(): check(false,label+" empty image"); return
	var image_error := pixels.save_png(output + "/" + label + ".png")
	check(image_error == OK,label+" capture")
	if image_error != OK: return
	var native: Dictionary = scene.runtime.snapshot().naval
	var ship: Dictionary = native.ships[0]
	var actors: Array = []
	var renderer: RefCounted = scene.sea.wakes._source_wakes
	if renderer != null:
		for id: String in renderer._actors:
			var actor: Dictionary = renderer._actors[id]
			var entry := {"id":id,"route":actor.route}
			var has_flow: bool = actor.get("flow") != null
			entry.tailMode = "candidate" if has_flow else "source"
			if has_flow:
				entry.flow = actor.flow.diagnostics()
				check(flow_diagnostic_valid(entry.flow,float(native.time)),label+" valid accepted candidate diagnostics "+id)
			if baseline_source or phase == "before": check(not has_flow,label+" source baseline excludes candidate "+id)
			if expect_flow and actor.route == "scene_30": check(has_flow,label+" production candidate exists "+id)
			if actor.history != null:
				entry.updates = actor.history.updates
				entry.scale = actor.history.scale
				entry.totalNativeLength = actor.history.total
				entry.historyResult = actor.history.last_result
			var surfaces: Array = []
			for key: String in actor.surface.nodes:
				var node: MeshInstance3D = actor.surface.nodes[key]
				var row := {"key":key,"visible":node.visible}
				if node.mesh != null:
					var arrays: Array = node.mesh.surface_get_arrays(0)
					var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
					var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
					var finite := true
					for vertex in vertices: finite = finite and vertex.is_finite()
					check(finite, label + " finite " + id + "/" + key)
					row.vertices = vertices.size(); row.alphaMax = 0.0
					for color in colors: row.alphaMax = maxf(row.alphaMax, color.a)
					var material: ShaderMaterial = node.material_override
					row.shader = material.shader.resource_path
					if has_flow and key == "SceneStrip": check(not node.visible,label+" candidate hides original strip "+id)
					if not has_flow and phase != "before" and key == "SceneStrip":
						check(row.shader == "res://modules/scene_engine/water/source_scene_wake.gdshader",label + " actual scene-trail material " + id)
						var expected: Dictionary = preload("res://modules/scene_engine/water/source_surface.gd").scene_strip_descriptor(actor.geometry)
						check(is_equal_approx(float(material.get_shader_parameter("tail_v")),float(expected.tail_v)),label + " current terminal UV " + id)
						check(is_equal_approx(float(material.get_shader_parameter("tail_span_v")),float(expected.tail_span_v)),label + " current terminal feather range " + id)
					surfaces.append(row)
			entry.surfaces = surfaces; actors.append(entry)
			if actor.froth != null:
				entry.froth = froth_diagnostic(actor.froth,legacy_froth)
				check(entry.froth.ok,label+" recognized froth implementation "+id)
				if phase != "before" and entry.froth.get("authoredVertices",0) > 0: check(entry.froth.transparentVertices > 0,label + " source transparent froth edges " + id)
	var record := {"label":label,"phase":phase,"acceptedTime":native.time,"environmentTime":native.environment.acceptedTime,"position":ship.visual.position,"heading":ship.visual.heading,"velocity":ship.visual.velocity,"sailDeployment":ship.sailDeployment,"wake":scene.sea.wakes.diagnostics(),"actors":actors,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual production renderer with controlled runtime, not original DX9 parity or live FPS."}
	var file := FileAccess.open(output + "/" + label + ".json", FileAccess.WRITE)
	if file == null: check(false,label+" record file open"); return
	file.store_string(JSON.stringify(record, "\t")); file.flush()
	var record_error := file.get_error(); file.close()
	check(record_error == OK,label+" record flushed")
	if record_error != OK: return
	records.append(record)
	print("WAKE_GPU_CAPTURE ", phase, " ", label, " time=", native.time)
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		if argument.begins_with("--output="): output = argument.trim_prefix("--output=")
		if argument == "--isolate-final": isolate_final = true
		if argument == "--probe-feather": probe_feather = true
		if argument == "--baseline-source": baseline_source = true
		if argument == "--candidate": expect_flow = true
	check(not expect_flow or (not baseline_source and phase != "before"),"candidate capture needs non-before phase and cannot request baseline-source")
	if output.is_empty(): output = "res://docs/migration/evidence/wake-regression-2026-10-14/" + phase + "/gpu"
	var absolute := ProjectSettings.globalize_path(output)
	check(not DirAccess.dir_exists_absolute(absolute) and not FileAccess.file_exists(output),"fresh output directory required; previous runs preserved")
	if not failures.is_empty(): quit(1); return
	check(DirAccess.make_dir_recursive_absolute(absolute) == OK,"new output directory created")
	if not failures.is_empty(): quit(1); return
	root.size = Vector2i(1600,900); root.content_scale_size = Vector2i(1600,900)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	scene = Practice.new(); scene.startup_options = {"mode":"sail","staged":true}
	scene.settings_storage = Settings.new("user://tests/wake-gpu-%s-settings.json" % OS.get_process_id())
	root.add_child(scene); await frames(2)
	scene.set_process(false); scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false), "production startup")
	if not scene.startup_receipt.get("ok",false): quit(1); return
	scene.activate_entry(); scene.sea.apply_settings({"quality":"balanced"})
	scene.runtime.set_pause("blur",false); await frames(8)
	if phase == "before":
		# Frozen pre-fix consumers are confined to this QA process. New source
		# metadata is inert to the old consumer; production files stay untouched.
		legacy_geometry = load("res://Temp/wake-regression-baseline/source_wake_geometry.gd")
		legacy_froth = load("res://Temp/wake-regression-baseline/source_froth.gd")
		var renderer: RefCounted = scene.sea.wakes._source_wakes
		var native: Dictionary = scene.runtime.snapshot().naval
		var packet: Dictionary = preload("res://game/presentation/world/source_water_packet.gd").compose(native,scene.sea.ships,scene.sea.camera)
		for ship: Dictionary in packet.ships:
			if not renderer._actors.has(ship.id): continue
			var actor: Dictionary = renderer._actors[ship.id]
			if actor.froth != null: actor.froth.dispose()
			actor.froth = legacy_froth.new()
			actor.froth.configure(actor.node,int(ship.sourceWake.froth.family),int(ship.sourceWake.froth.seed),str(ship.sourceWake.froth.sourceResourceName))
			var attached: Dictionary = ship.sourceWake.duplicate(true); attached.merge(ship.sourceWake.froth,true)
			actor.froth.apply_snapshot(attached,native.time,scene.sea.wakes._water,scene.sea.wakes._surface_filter)
		apply_baseline_geometry()
	if baseline_source: apply_baseline_geometry()
	await capture("01-start")
	var initial: Dictionary = scene.runtime.snapshot().naval.ships[0].visual.position
	check(scene.runtime.command({"type":"mouse-course","point":{"x":initial.x+700.0,"z":initial.z}}).ok,"straight mouse course")
	await ticks(240); await capture("02-straight-4s")
	await ticks(480); await capture("03-straight-12s")
	var straight: Dictionary = scene.runtime.snapshot().naval.ships[0].visual.position
	check(Vector2(straight.x-initial.x,straight.z-initial.z).length()>10.0,"actual open-water displacement")
	check(scene.runtime.command({"type":"mouse-course","point":{"x":straight.x+120.0,"z":straight.z+650.0}}).ok,"turn mouse course")
	await ticks(300); await capture("04-turn-5s")
	await ticks(420); await capture("05-turn-12s")
	check(scene.runtime.command({"type":"stop-sailing"}).ok,"stop command")
	await ticks(600); await capture("06-stopped-10s")
	var stopped: Dictionary = scene.runtime.snapshot().naval.ships[0].visual.position
	check(scene.runtime.command({"type":"mouse-course","point":{"x":stopped.x+450.0,"z":stopped.z+120.0}}).ok,"resume mouse course")
	await ticks(300); await capture("07-resume-5s")
	if probe_feather:
		var renderer: RefCounted = scene.sea.wakes._source_wakes
		for actor: Dictionary in renderer._actors.values():
			if actor.get("flow") != null:
				check(false,"source feather probe requires --baseline-source; candidate uses its own material")
				continue
			if actor.history == null or not actor.surface.nodes.has("SceneStrip"): continue
			var node: MeshInstance3D = actor.surface.nodes.SceneStrip
			if node.mesh == null: continue
			var material: ShaderMaterial = node.material_override.duplicate()
			material.shader = load("res://Temp/wake-regression-baseline/scene_wake_feather.gdshader")
			var count := mini(58,int(actor.history.vertex_count))
			var uv: PackedVector2Array = actor.geometry.uvs
			material.set_shader_parameter("tail_v",uv[count-1].y)
			material.set_shader_parameter("tail_span_v",uv[maxi(0,count-7)].y-uv[count-1].y)
			node.material_override = material
		await capture("08-resume-edge-feather-probe")
	if isolate_final:
		var renderer: RefCounted = scene.sea.wakes._source_wakes
		for actor: Dictionary in renderer._actors.values():
			if actor.froth != null: actor.froth._container.visible = false
		await capture("08-resume-strip-only")
		for actor: Dictionary in renderer._actors.values():
			for node: MeshInstance3D in actor.surface.nodes.values(): node.visible = false
			var flow_node: Node3D = actor.node.get_node_or_null("TargetWakeFlow")
			if is_instance_valid(flow_node): flow_node.visible = false
			if actor.froth != null:
				actor.froth._container.visible = true
				isolate_froth(actor.froth,false)
		await capture("09-resume-local-froth-only")
		for actor: Dictionary in renderer._actors.values():
			if actor.froth != null:
				isolate_froth(actor.froth,true)
		await capture("10-resume-spray-only")
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free(); scene=null; await frames(4)
	check(await AudioCleanup.wait_for_release(self,playbacks),"audio cleanup")
	check(capture_inventory_valid(records,probe_feather,isolate_final),"all expected nonzero captures completed exactly once")
	if expect_flow:
		var visible_flow := false
		for record: Dictionary in records:
			for actor: Dictionary in record.actors: visible_flow = visible_flow or actor.get("flow", {}).get("visible", false)
		check(visible_flow,"candidate capture set includes a visible actual tail")
	var report := {"failures":failures,"captures":records,"baselineSource":baseline_source or phase=="before","candidateRequired":expect_flow,"expectedCaptureLabels":expected_capture_labels(probe_feather,isolate_final),"scope":"Production wake visual regression, no original-runtime/FPS claim."}
	var file := FileAccess.open(output + "/VERIFICATION.json",FileAccess.WRITE)
	if file == null: check(false,"verification file open")
	else:
		file.store_string(JSON.stringify(report,"\t")); file.flush()
		check(file.get_error() == OK,"verification file flush"); file.close()
	print("WAKE_PRODUCTION_GPU captures=",records.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
