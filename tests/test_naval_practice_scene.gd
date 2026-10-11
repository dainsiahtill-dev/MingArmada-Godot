extends SceneTree
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path:="res://game/scenes/naval_practice/naval_practice.gd"
	check(ResourceLoader.exists(path),"menu naval entries have a real playable scene")
	if ResourceLoader.exists(path):
		root.size=Vector2i(1600,900)
		var scene=load(path).new(); scene.startup_options={"mode":"duel"}
		root.add_child(scene); await process_frame; scene.set_physics_process(false)
		check(scene.startup_receipt.ok and scene.sea.ships.size()==2,"one player and one hostile original model actually mounted")
		var shot: Button=scene.interface.find_child("fire_starboard",true,false)
		var ammunition: int=scene.runtime.snapshot().naval.ships[0].ammo.solid
		check(shot!=null and not shot.disabled,"real cannon UI ready in active fight")
		if shot: shot.pressed.emit()
		scene._physics_process(1.0/60)
		check(scene.runtime.snapshot().naval.ships[0].ammo.solid<ammunition,"actual control consumes cannon ammunition")
		var slider: HSlider=scene.interface.find_child("sails",true,false); slider.grab_focus()
		var arrow:=InputEventKey.new(); arrow.physical_keycode=KEY_RIGHT; arrow.keycode=KEY_RIGHT; arrow.pressed=true
		Input.parse_input_event(arrow); await process_frame
		check(not scene.runtime.simulation._held.has("ArrowRight"),"focused sails slider keeps arrow keys out of ship helm")
		root.gui_release_focus()
		scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT); scene._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_IN)
		check(scene.runtime.is_paused(),"focus recovery waits for explicit Continue")
		scene.interface.find_child("pause",true,false).pressed.emit()
		check(not scene.runtime.is_paused(),"visible Continue explicitly resumes after focus loss")
		var key:=InputEventKey.new(); key.physical_keycode=KEY_ESCAPE; key.pressed=true
		Input.parse_input_event(key); await process_frame
		check(scene.interface.is_menu_open() and scene.runtime.is_paused(),"physical Escape opens actual paused practice menu")
		var before: Dictionary=scene.runtime.snapshot().naval
		scene._physics_process(60)
		check(scene.runtime.snapshot().naval==before,"menu freezes real combat")
		var resume: Button=scene.interface.find_child("resume",true,false)
		if resume: resume.pressed.emit()
		check(not scene.runtime.is_paused(),"actual resume button releases only menu pause")
		var surrender: Button=scene.interface.find_child("surrender",true,false)
		if surrender: surrender.pressed.emit()
		check(scene.interface.find_child("confirm_surrender",true,false).visible and scene.runtime.is_paused(),"actual surrender button shows authoritative confirmation")
		scene.interface.find_child("cancel_surrender",true,false).pressed.emit()
		check(not scene.runtime.is_paused(),"actual cancel preserves ongoing fight")
		var chart_key:=InputEventKey.new(); chart_key.physical_keycode=KEY_M; chart_key.pressed=true
		Input.parse_input_event(chart_key); await process_frame
		check(scene.interface.chart.visible and "chart" in scene.runtime.snapshot().runtime.pauseReasons,"M opens live ancient chart and suspends practice")
		scene.interface.find_child("close_chart",true,false).pressed.emit()
		check(not scene.interface.chart.visible and not scene.runtime.is_paused(),"chart close returns to combat")
		var count:=[0]; scene.main_menu_requested.connect(func(): count[0]+=1)
		scene.interface.find_child("main_menu",true,false).pressed.emit()
		check(count[0]==1,"actual button returns to owner menu")
		root.size=Vector2i(320,480); root.content_scale_size=Vector2i(320,480); await process_frame; await process_frame; await process_frame
		check(scene.interface._panel.get_rect().end.x<=320 and scene.interface._panel.get_rect().end.y<=480,"narrow practice HUD remains inside actual viewport and scrolls its content: "+str(scene.interface._panel.get_rect())+" visible="+str(root.get_visible_rect())+" minimum="+str(scene.interface._panel.get_combined_minimum_size()))
		scene.queue_free(); await process_frame; await process_frame; await create_timer(0.08).timeout
	print("NAVAL_PRACTICE_SCENE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
