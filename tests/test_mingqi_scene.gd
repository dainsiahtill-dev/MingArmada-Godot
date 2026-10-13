extends SceneTree
const Scene = preload("res://game/scenes/mingqi/mingqi_scene.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func key(code: Key,pressed: bool) -> void:
	var event := InputEventKey.new(); event.physical_keycode = code; event.keycode = code; event.pressed = pressed
	Input.parse_input_event(event)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	root.size = Vector2i(1600,900)
	var scene := Scene.new(); root.add_child(scene)
	await process_frame; scene.set_physics_process(false)
	check(scene.get("startup_receipt") is Dictionary and scene.get("startup_receipt").get("ok") == true,"default scene exposes completed startup receipt")
	check(scene.ships.size() == 5 and scene.sailors.size() == 5,"actual opening composes five imported models and crew adapters")
	check(scene.get("services") != null,"native Mingqi scene owns settings and actual audio presentation")
	var crew := 0
	for view in scene.sailors.values(): crew += view.get_visible_count()
	check(crew > 24 and crew <= 120,"visible animated sailors respect global budget across fleet")
	var before: Dictionary = scene.runtime.snapshot()
	var accept: Button = scene.interface.find_child("accept_convoy",true,false)
	if accept == null: accept = scene.interface.find_child("accept_convoy_convoy-001",true,false)
	# UI output naming is tested by its own real-control suite; root validates
	# integration with the canonical intent and a regular focused HUD button.
	check(scene.runtime.command({"type":"accept-convoy","commandId":"scene-test-accept","expectedRevision":before.campaign.revision}).ok,"native scene accepts real canonical convoy intent")
	# Public sailing requires departure since 44feae1; HUD focus must be
	# exercised in a legally sailing state rather than bypassing the dock gate.
	check(scene.runtime.command({"type":"depart","commandId":"scene-test-depart","expectedRevision":scene.runtime.snapshot().campaign.revision}).ok and scene.runtime.snapshot().campaign.currentPortId == null,"public departure enables actual sailing controls before HUD focus test")
	scene._present(0)
	var buttons: Array = scene.interface.find_children("*","Button",true,false)
	check(not buttons.is_empty(),"actual native interface has focusable controls")
	var focus_button: Button = buttons[0]; focus_button.grab_focus()
	check(not scene.interface.captures_keyboard(),"ordinary focused HUD button does not capture sail input")
	key(KEY_W,true); await process_frame
	for tick in 90: scene._physics_process(1.0/60)
	key(KEY_W,false); await process_frame
	var moving: Dictionary = scene.runtime.snapshot()
	var id: String = moving.naval.playerId
	check(scene.runtime._ship(moving.naval,id).sailDeployment > 0.9,"real native key event reaches gradual forward sails after HUD focus")
	scene.interface.close_panel(); scene._present(0.0); await process_frame
	check(scene.minimap.chart.visible and scene.minimap.chart._native==scene.runtime.snapshot().naval,"Mingqi sailing has a compact map reading the actual native fleet")
	var click := InputEventMouseButton.new(); click.button_index=MOUSE_BUTTON_LEFT; click.pressed=true; click.position=scene.minimap.chart.global_position+scene.minimap.chart.map_rect().get_center()
	Input.parse_input_event(click); await process_frame
	click=click.duplicate(); click.pressed=false; Input.parse_input_event(click); await process_frame
	check(scene.interface.is_panel_open() and scene.interface._panel=="convoy" and not scene.minimap.chart.visible,"actual Mingqi minimap click opens the source convoy chart without overlaying its panel")
	var expanded: Control=scene.interface.find_child("fleet_chart",true,false)
	check(expanded._configured and expanded._native==scene.runtime.snapshot().naval and not expanded._coast_segments.is_empty(),"Mingqi full chart uses the shared real terrain and live native ship positions")
	key(KEY_SPACE,true); await process_frame; key(KEY_SPACE,false); await process_frame
	before = scene.runtime.snapshot()
	scene._physics_process(30)
	check(before.naval == scene.runtime.snapshot().naval and before.campaign == scene.runtime.snapshot().campaign,"global pause freezes both authorities despite ordinary Button focus")
	check(absf(float(scene.world.get_ocean().get("_simulation_time"))-before.naval.time)<1e-10,"paused ocean reads accepted native time")
	if scene.get("services") != null:
		check(absf(float(scene.services.audio.diagnostics().clock)-before.naval.time)<1e-10,"audio reads the same accepted sea time when paused")
		scene.services.open_settings()
		var row: Control = scene.services.settings_panel.find_child("quality",true,false)
		var choice: OptionButton = row.get_node("Value") if row else null
		check(choice != null,"real settings modal contains a focusable quality selector")
		if choice: choice.grab_focus()
		var escape := InputEventKey.new(); escape.physical_keycode = KEY_ESCAPE; escape.pressed = true
		Input.parse_input_event(escape); await process_frame
		check(not scene.services.captures_keyboard(),"physical-only Escape closes settings before focused selector consumes it")
		check("player" in scene.runtime.snapshot().runtime.pauseReasons and not ("menu" in scene.runtime.snapshot().runtime.pauseReasons),"closing settings retains independent player pause")
	scene.queue_free(); await process_frame; await process_frame
	await create_timer(0.08).timeout
	print("MINGQI_SCENE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
