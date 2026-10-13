extends SceneTree
## Actual production free-sail renderer, deterministic accepted inputs and clock.
## This is a QA driver, never a new player scene or menu entry.
const Practice = preload("res://game/scenes/naval_practice/naval_practice.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const AudioCleanup = preload("res://tests/fixtures/audio_cleanup.gd")
var scene: Node3D
var failures: Array[String] = []
var records: Array = []
var phase := "before"
var output := ""
var legacy_geometry: Script
var legacy_updates: Dictionary = {}
var isolate_final := false
var probe_feather := false
func _initialize() -> void: run.call_deferred()
func check(ok: bool, message: String) -> void:
	if not ok: failures.append(message); printerr("FAIL wake GPU: ", message)
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
	if legacy_geometry == null: return
	var renderer: RefCounted = scene.sea.wakes._source_wakes
	if renderer == null: return
	var native: Dictionary = scene.runtime.snapshot().naval
	var packet: Dictionary = preload("res://game/presentation/world/source_water_packet.gd").compose(native,scene.sea.ships,scene.sea.camera)
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
	check(pixels.save_png(output + "/" + label + ".png") == OK, label + " capture")
	var native: Dictionary = scene.runtime.snapshot().naval
	var ship: Dictionary = native.ships[0]
	var actors: Array = []
	var renderer: RefCounted = scene.sea.wakes._source_wakes
	if renderer != null:
		for id: String in renderer._actors:
			var actor: Dictionary = renderer._actors[id]
			var entry := {"id":id,"route":actor.route}
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
					if phase != "before" and key == "SceneStrip":
						check(row.shader == "res://modules/scene_engine/water/source_scene_wake.gdshader",label + " actual scene-trail material " + id)
						var expected: Dictionary = preload("res://modules/scene_engine/water/source_surface.gd").scene_strip_descriptor(actor.geometry)
						check(is_equal_approx(float(material.get_shader_parameter("tail_v")),float(expected.tail_v)),label + " current terminal UV " + id)
						check(is_equal_approx(float(material.get_shader_parameter("tail_span_v")),float(expected.tail_span_v)),label + " current terminal feather range " + id)
					surfaces.append(row)
			entry.surfaces = surfaces; actors.append(entry)
			if actor.froth != null:
				var transparent := 0; var authored := 0
				for key: String in actor.froth._surface.nodes:
					if not key.begins_with("bow_") and not key.begins_with("side_"): continue
					var node: MeshInstance3D = actor.froth._surface.nodes[key]
					if not node.visible or node.mesh == null: continue
					var arrays: Array = node.mesh.surface_get_arrays(0)
					for color: Color in arrays[Mesh.ARRAY_COLOR]:
						authored += 1
						if color.a == 0.0: transparent += 1
				entry.froth = {"authoredVertices":authored,"transparentVertices":transparent,"particles":actor.froth._particles.diagnostics()}
				if phase != "before" and authored > 0: check(transparent > 0,label + " source transparent froth edges " + id)
	var record := {"label":label,"phase":phase,"acceptedTime":native.time,"environmentTime":native.environment.acceptedTime,"position":ship.visual.position,"heading":ship.visual.heading,"velocity":ship.visual.velocity,"sailDeployment":ship.sailDeployment,"wake":scene.sea.wakes.diagnostics(),"actors":actors,"renderer":RenderingServer.get_current_rendering_method(),"gpu":RenderingServer.get_video_adapter_name(),"scope":"Actual production renderer with controlled runtime, not original DX9 parity or live FPS."}
	records.append(record)
	var file := FileAccess.open(output + "/" + label + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(record, "\t")); file.close()
	print("WAKE_GPU_CAPTURE ", phase, " ", label, " time=", native.time)
func run() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--phase="): phase = argument.trim_prefix("--phase=")
		if argument == "--isolate-final": isolate_final = true
		if argument == "--probe-feather": probe_feather = true
	output = "res://docs/migration/evidence/wake-regression-2026-10-14/" + phase + "/gpu"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
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
		var legacy_froth: Script = load("res://Temp/wake-regression-baseline/source_froth.gd")
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
			if actor.froth != null:
				actor.froth._container.visible = true
				for key: String in actor.froth._surface.nodes:
					actor.froth._surface.nodes[key].visible = key.begins_with("bow_") or key.begins_with("side_")
		await capture("09-resume-authored-only")
		for actor: Dictionary in renderer._actors.values():
			if actor.froth != null:
				for key: String in actor.froth._surface.nodes: actor.froth._surface.nodes[key].visible = key.begins_with("ParticleSystem_")
		await capture("10-resume-particles-only")
	var playbacks: Array[WeakRef] = AudioCleanup.stop_players(scene)
	scene.free(); scene=null; await frames(4)
	check(await AudioCleanup.wait_for_release(self,playbacks),"audio cleanup")
	var report := {"failures":failures,"captures":records,"scope":"Production wake visual regression, no original-runtime/FPS claim."}
	var file := FileAccess.open(output + "/VERIFICATION.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t")); file.close()
	print("WAKE_PRODUCTION_GPU failures=",failures.size()," captures=",records.size())
	quit(0 if failures.is_empty() else 1)
