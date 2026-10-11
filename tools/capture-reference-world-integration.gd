extends SceneTree
## Actual menu entries using formal geography, vessels and shared sea adapters.
const Router=preload("res://game/runtime/game_router.gd")
const Storage=preload("res://game/persistence/save_coordinator.gd")
const Settings=preload("res://game/persistence/user_settings.gd")
const Legacy=preload("res://game/runtime/legacy_runtime.gd")
var main: Node
var scene: Node
var failures:=0
var assertions:=0
var captures:=0
var directory:="res://docs/migration/evidence/reference-world-integration"
func _initialize() -> void: run.call_deferred()
func check(value: bool, detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func frames(count: int=6) -> void:
	for frame in count: await process_frame
func click(control: Control) -> void:
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=control.get_global_rect().get_center()
	Input.parse_input_event(event); await process_frame
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await process_frame
func enter(mode: String) -> bool:
	var button: Button=main.menu._buttons[mode]
	main.menu._scroll.ensure_control_visible(button); await frames(3); await click(button)
	for frame in 240:
		if main.current_scene: break
		await process_frame
	check(main.current_scene!=null,"actual menu enters "+mode)
	if not main.current_scene: return false
	scene=main.current_scene; scene.set_process(false); scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),"formal entry starts "+mode)
	var ocean: MeshInstance3D=scene.sea.world.get_ocean()
	check(ocean.material_override.shader.resource_path=="res://modules/scene_engine/ocean/reference_game_water.gdshader","formal "+mode+" uses transplanted source optics")
	check(ocean.get_surface_optics_diagnostics().offscreen_targets==1,"formal "+mode+" owns a true planar mirror")
	check(scene.sea._environment.background_mode==Environment.BG_SKY,"formal "+mode+" binds reference sky")
	return true
func advance(count: int) -> void:
	for tick in count:
		# Isolated capture slots use explicit accepted ticks, not wall-time speed.
		scene.runtime.set_pause("blur",false)
		scene._physics_process(1.0/60.0)
		await process_frame
func capture(label: String) -> void:
	await frames(8); await RenderingServer.frame_post_draw
	var pixels:=root.get_texture().get_image(); var destination:=directory+"/"+label+".png"
	check(pixels.save_png(destination)==OK,"native GPU PNG "+label)
	var water: MeshInstance3D=scene.sea.world.get_ocean()
	var metadata:={"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"viewport":[pixels.get_width(),pixels.get_height()],"imageSha256":FileAccess.get_sha256(destination),"route":"actual MainScene menu Control and entry router","scene":scene.get_script().resource_path,"runtime":scene.runtime.snapshot(),"optics":water.get_surface_optics_diagnostics(),"waterShader":water.material_override.shader.resource_path,"wakes":scene.sea.wakes.diagnostics(),"effects":scene.sea.effects.diagnostics(),"camera":str(scene.sea.camera.global_transform),"terrainChunks":scene.sea.world.get_chunk_count(),"nearBounds":str(water.material_override.get_shader_parameter("reference_near_bounds")),"scope":"Formal gameplay composition and GPU appearance at accepted ticks. Excludes wall-time performance and complete historical journey."}
	metadata.referenceProfiles=scene.heights.reference_profiles()
	var file:=FileAccess.open(directory+"/"+label+".json",FileAccess.WRITE)
	check(file!=null,"native metadata "+label)
	if file: file.store_string(JSON.stringify(metadata,"\t")); file.close()
	captures+=1
func coast_camera(low: bool=false) -> void:
	var camera: Camera3D=scene.sea.camera
	camera.position=Vector3(-270,24,48) if low else Vector3(-350,125,95)
	camera.look_at(Vector3(-455,6,-55))
	scene.sea.world.apply_snapshot({"time":scene.runtime.snapshot().naval.time,"focus":Vector2(-450,-55)},0.0)
func leave() -> void:
	var mirror: WeakRef=weakref(scene.sea.world.get_ocean().get_reflection_viewport())
	scene.main_menu_requested.emit(); await frames(8)
	check(main.current_scene==null and main.menu.visible,"actual return to main menu")
	check(mirror.get_ref()==null,"return frees shared-world planar mirror")
	scene=null
func run() -> void:
	root.unresizable=true; root.size=Vector2i(1600,900); root.content_scale_size=root.size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var prefix:="user://tests/reference-world-capture-%s" % OS.get_process_id()
	var packed: PackedScene=load(ProjectSettings.get_setting("application/run/main_scene"))
	main=packed.instantiate(); main.router=Router.new({"dev":true,"mingqi_storage":Storage.new(prefix+"-v2.json"),"legacy_storage":Storage.new(prefix+"-v1.json",Legacy.validate_save),"settings_storage":Settings.new(prefix+"-settings.json")})
	root.add_child(main); await frames(10)
	for mode: String in ["sail","duel","fleet","mingqi","career"]:
		if not await enter(mode): continue
		if mode in ["sail","duel","fleet"]:
			scene.runtime.command({"type":"resume"}); scene._present(0)
			scene.runtime.set_held("KeyW",true); await advance(90); scene.runtime.set_held("KeyW",false)
			await capture(mode+"-captain")
			scene.sea.tactical=true; scene._present(0.25)
			await capture(mode+"-tactical")
		elif mode=="mingqi":
			scene.interface.close_panel(); scene._present(0)
			await capture("mingqi-harbor")
			coast_camera(); await capture("mingqi-island-shore")
			coast_camera(true); await capture("mingqi-shore-low")
			var ocean: MeshInstance3D=scene.sea.world.get_ocean()
			var frozen: Dictionary=scene.runtime.snapshot()
			ocean.set_reflection_enabled(false); await capture("mingqi-shore-reflection-off")
			ocean.set_reflection_enabled(true); await capture("mingqi-shore-reflection-on")
			check(scene.runtime.snapshot()==frozen,"paired mirror captures preserve canonical gameplay")
		else:
			scene.interface.visible=false; coast_camera(); await capture("career-island-shore")
			scene.runtime.set_pause("blur",false)
			check(scene._command({"type":"depart"}).get("ok",false),"career actual departure")
			scene.runtime.set_held("KeyW",true); await advance(150); scene.runtime.set_held("KeyW",false)
			scene.interface.visible=true; scene.sea._update_camera(scene.runtime.snapshot().naval,0.25)
			await capture("career-sailing")
		await leave()
	# Reentry proves new native menu composition after all mirror ownership exits.
	if await enter("sail"):
		await capture("sail-reentry"); await leave()
	main.queue_free(); await frames(4)
	print("REFERENCE_WORLD_GPU_CAPTURE_COMPLETE captures=",captures," assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
