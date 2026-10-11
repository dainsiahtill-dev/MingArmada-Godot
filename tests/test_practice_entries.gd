extends SceneTree
var failures := 0
var assertions := 0
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: _run.call_deferred()
func physical(code: int, repeat: bool=false) -> void:
	var event:=InputEventKey.new(); event.physical_keycode=code; event.pressed=true; event.echo=repeat
	Input.parse_input_event(event); await process_frame
func begin_scene(scene) -> void:
	var control=scene.find_child("Begin",true,false)
	check(control!=null and control.visible,"source timed game has actual visible Begin control")
	if control: control.pressed.emit()
func _run() -> void:
	if not ResourceLoader.exists("res://game/runtime/practice_runtime.gd"):
		check(false,"standalone practice authority exists without career storage"); _finish(); return
	var Runtime = load("res://game/runtime/practice_runtime.gd")
	var runtime = Runtime.new()
	for kind in ["duel","landBattle","treasure","banquet"]:
		check(runtime.start(kind).ok,"source standalone mode starts: "+kind)
		var packet: Dictionary = runtime.snapshot()
		check(packet.practice and packet.seed==1661 and packet.difficulty=="normal" and packet.state.kind==kind,"source seed/difficulty/native model: "+kind)
		if kind in ["duel","banquet"]:
			check(not packet.get("started",true),"timed model waits for explicit source Begin")
			var waiting:Dictionary=runtime.snapshot(); runtime.advance(.1)
			check(runtime.snapshot()==waiting and not runtime.command({"type":"encounter-action","id":packet.id,"action":"thrust" if kind=="duel" else "up"}).ok,"waiting model rejects time and actions")
			check(runtime.command({"type":"encounter-begin","id":packet.id}).ok,"explicit Begin opens timed model gate")
		var before: Dictionary = runtime.snapshot()
		check(not runtime.command({"type":"encounter-settle","id":packet.id,"result":{"success":true}}).ok and runtime.snapshot()==before,"result injection refused: "+kind)
		check(not runtime.command({"type":"encounter-action","id":"stale","action":"thrust"}).ok,"stale native callback refused")
		if kind=="duel":
			check(packet.state.boardingContext=={"crew":48,"enemyCrew":38,"morale":100},"source standalone boarding crew context")
			check(runtime.command({"type":"encounter-action","id":packet.id,"action":"thrust"}).ok and runtime.snapshot().state.enemyHealth<100,"real native duel action changes opponent health")
		elif kind=="landBattle":
			check(runtime.command({"type":"encounter-action","id":packet.id,"action":{"type":"move","x":2,"y":2}}).ok and runtime.snapshot().state.units[0].x==2,"real native land path changes unit")
		elif kind=="treasure":
			var health = packet.state.playerHealth
			check(runtime.command({"type":"encounter-action","id":packet.id,"action":{"type":"dig"}}).ok and runtime.snapshot().state.digsLeft<packet.state.digsLeft,"real native treasure dig consumes attempt")
			check(runtime.snapshot().state.playerHealth<=health,"treasure injury remains native model fact")
		else:
			var cue: Dictionary = packet.state.cues[0]
			runtime.advance(cue.time)
			check(runtime.command({"type":"encounter-action","id":packet.id,"action":cue.direction}).ok and runtime.snapshot().state.score>0,"real rhythm timing generates score")
		check(runtime.command({"type":"encounter-pause","id":packet.id,"value":true}).ok,"practice pauses")
		var paused: Dictionary = runtime.snapshot(); runtime.advance(1)
		check(runtime.snapshot()==paused and not runtime.command({"type":"encounter-retreat","id":packet.id}).ok,"pause fences model clock/actions")
		runtime.command({"type":"encounter-pause","id":packet.id,"value":false})
		check(runtime.command({"type":"encounter-retreat","id":packet.id}).ok,"actual model retreat")
		check(runtime.command({"type":"encounter-settle","id":packet.id}).ok,"practice settles native result")
		check(runtime.snapshot().settlement=={"mode":"practice","rawScore":runtime.snapshot().result.score,"paid":0},"practice settlement has no career reward")
		check(not runtime.command({"type":"encounter-settle","id":packet.id}).ok,"double settlement fenced")
		check(runtime.command({"type":"encounter-retry","id":packet.id}).ok and runtime.snapshot().id!=packet.id,"retry creates fresh identity")
		if kind in ["duel","banquet"]: check(not runtime.snapshot().get("started",true) and runtime.advance(1)==0,"retry resets explicit Begin gate")
		check(not runtime.command({"type":"encounter-action","id":packet.id,"action":"thrust"}).ok,"retry fences retained callback")
	var scene = load("res://game/scenes/practice/practice.tscn").instantiate()
	scene.startup_options={"kind":"banquet"}; root.add_child(scene); await process_frame
	check(scene.startup_receipt.ok and scene.runtime.snapshot().kind=="banquet","router options launch actual standalone scene")
	for frame in 3: await process_frame
	check(scene.runtime.snapshot().state.elapsed==0,"scene presentation frames do not start banquet countdown")
	var header = scene.find_child("PracticeHeader",true,false)
	check(scene.encounter_ui._panel.position.y>=header.position.y+header.size.y,"practice header and actual minigame panel never overlap")
	var picker = scene.find_child("PracticeKind",true,false)
	picker.select(0); picker.item_selected.emit(0)
	begin_scene(scene)
	var focus:Control=root.gui_get_focus_owner()
	if focus: focus.release_focus()
	var physical_key:=InputEventKey.new(); physical_key.physical_keycode=KEY_L; physical_key.pressed=true
	var physical_health:float=scene.runtime.snapshot().state.enemyHealth
	Input.parse_input_event(physical_key); await process_frame
	check(scene.runtime.snapshot().state.enemyHealth<physical_health,"actual physical-key-only L event reaches native duel action")
	picker.select(0); picker.item_selected.emit(0); begin_scene(scene); picker.grab_focus()
	var focused_health:float=scene.runtime.snapshot().state.enemyHealth
	var focused_key:=InputEventKey.new(); focused_key.physical_keycode=KEY_J; focused_key.pressed=true
	Input.parse_input_event(focused_key); await process_frame
	check(scene.runtime.snapshot().state.enemyHealth==focused_health,"focused native selector owns physical keys without attacking")
	picker.release_focus()
	var first: Dictionary = scene.runtime.snapshot()
	scene.find_child("duel_thrust",true,false).pressed.emit()
	check(scene.runtime.snapshot().state.enemyHealth<first.state.enemyHealth,"native practice button operates real domain action")
	scene.find_child("retreat",true,false).pressed.emit()
	check(scene.runtime.snapshot().settled and scene.find_child("retry",true,false).disabled==false,"actual UI retreat confirms practice result and enables retry")
	scene.find_child("retry",true,false).pressed.emit()
	check(scene.runtime.snapshot().id!=first.id and scene.runtime.snapshot().state.phase=="active","native retry button starts fresh model")
	check(scene.find_child("Begin",true,false)!=null and not scene.runtime.snapshot().get("started",true),"native retry returns to visible Begin gate")
	var stale: Dictionary = scene.runtime.snapshot()
	picker.select(3); picker.item_selected.emit(3)
	check(not scene.runtime.command({"type":"encounter-retreat","id":stale.id}).ok,"kind switch fences previous model callback")
	scene.runtime.set_suspended(true)
	var suspended: Dictionary = scene.runtime.snapshot(); scene.runtime.advance(1)
	check(scene.runtime.snapshot()==suspended and not scene.runtime.command({"type":"encounter-action","id":suspended.id,"action":"up"}).ok,"focus suspension stops native model and UI actions")
	scene.runtime.set_suspended(false)
	# Source shortcuts use real physical key events and actual domain changes.
	picker.select(2); picker.item_selected.emit(2); root.gui_release_focus()
	var treasure_before:Dictionary=scene.runtime.snapshot().state
	await physical(KEY_S)
	check(scene.runtime.snapshot().state.position.y==treasure_before.position.y+1,"physical S moves explorer onto actual open path")
	await physical(KEY_D)
	check(scene.runtime.snapshot().state.position.x==treasure_before.position.x+1,"physical D moves real treasure explorer")
	await physical(KEY_A); await physical(KEY_W)
	check(scene.runtime.snapshot().state.position==treasure_before.position,"physical A/W return through actual native terrain")
	var digs:int=scene.runtime.snapshot().state.digsLeft
	await physical(KEY_E)
	check(scene.runtime.snapshot().state.digsLeft==digs-1,"physical E digs using actual treasure model")
	picker.select(1); picker.item_selected.emit(1); root.gui_release_focus()
	await physical(KEY_2)
	check(scene.runtime.snapshot().state.selectedUnitId=="player-musketeer","physical2 selects actual land musketeer")
	await physical(KEY_1)
	check(scene.runtime.snapshot().state.selectedUnitId=="player-melee","physical1 selects actual land melee")
	var turn:int=scene.runtime.snapshot().state.turn
	await physical(KEY_E)
	check(scene.runtime.snapshot().state.turn==turn+1,"physical E advances native land enemy turn")
	picker.select(3); picker.item_selected.emit(3); begin_scene(scene); root.gui_release_focus(); scene.set_process(false)
	var cue:Dictionary=scene.runtime.snapshot().state.cues[0]; scene.runtime.advance(cue.time); scene._refresh()
	await physical({"up":KEY_W,"down":KEY_S,"left":KEY_A,"right":KEY_D}[cue.direction])
	check(scene.runtime.snapshot().state.hits==1,"physical WASD hits actual banquet cue")
	scene.set_process(true)
	picker.select(0); picker.item_selected.emit(0); begin_scene(scene)
	scene.find_child("retreat",true,false).pressed.emit()
	var real_result: Dictionary=scene.runtime.snapshot().result
	scene.find_child("encounter_close",true,false).pressed.emit()
	check(scene.runtime.snapshot().is_empty() and scene._status.text.contains("实际得分 %s"%real_result.score) and scene._status.text.contains("伤损 %s%%"%real_result.injury),"closed standalone practice retains source actual result summary")
	var leaves: Array = []; scene.main_menu_requested.connect(func(): leaves.append(true))
	scene.find_child("MainMenu",true,false).pressed.emit()
	check(leaves.size()==1,"practice menu signal returns to application owner")
	scene.queue_free(); await process_frame
	runtime.dispose(); check(runtime.snapshot().is_empty() and not runtime.start("duel").ok,"disposed authority rejects resurrection")
	_finish()
func _finish() -> void:
	print("PRACTICE_ENTRIES_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
