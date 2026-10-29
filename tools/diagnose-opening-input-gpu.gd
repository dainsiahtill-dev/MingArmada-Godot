extends "res://tools/capture-opening-story.gd"
## Independent diagnostic. Reuses the original MainScene and mouse sequence.
## Nothing emits a UI signal or substitutes a business command for a click.
## Renderer and OS input remain distinct: these are injected viewport events.
const Paths = preload("res://tools/qa-journey-paths.gd")
const INPUTS = ["project.godot", "tools/diagnose-opening-input-gpu.gd", "tools/capture-opening-story.gd", "tools/qa-journey-paths.gd", "game/scenes/main/main_scene.gd", "game/runtime/game_router.gd", "game/scenes/mingqi/mingqi_scene.gd", "game/ui/mingqi/mingqi_interface.gd", "game/ui/shared/maritime_art_theme.gd", "game/ui/shared/painted_window_style.gd", "game/runtime/mingqi_runtime.gd", "game/domain/mingqi/campaign.gd", "game/domain/mingqi/opening_story.gd", "game/domain/mingqi/voyage_flow.gd", "game/domain/persistence/save_codec.gd", "game/runtime/near_field_bridge.gd", "modules/naval_simulation/encounter.gd"]
var output_owned := false
var trace: Array = []
var intents: Array = []
var stages: Array = []
var skipped: Array = []
var sources: Dictionary = {}
var watched: CanvasLayer

func _initialize() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): _guard_tests.call_deferred()
	else: _guarded_start.call_deferred()

func _norm(value: String) -> String:
	return value.replace("\\", "/").simplify_path().trim_suffix("/").to_lower()

func _profile_ok(appdata: String, localdata: String, original: String, userdata: String, allowed: String) -> bool:
	if appdata.is_empty() or localdata.is_empty() or original.is_empty() or userdata.is_empty() or allowed.is_empty(): return false
	var chosen := _norm(appdata)
	var allowed_root := _norm(allowed)
	var original_path := _norm(original)
	return chosen == _norm(localdata) and chosen != original_path and not chosen.begins_with(original_path + "/") and not original_path.begins_with(chosen + "/") and chosen.begins_with(allowed_root + "/") and _norm(userdata).begins_with(chosen + "/")

func _output_ok(value: String) -> bool:
	return Paths.output(["--output="+value+"/capture-result.json"]).ok and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(value)) and not FileAccess.file_exists(value)

func _guarded_start() -> void:
	var selected := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output=") and selected.is_empty(): selected=argument.trim_prefix("--output=")
		else: check(false,"unknown or duplicate argument")
	check(_output_ok(selected),"fresh confined evidence directory required")
	check(_profile_ok(OS.get_environment("APPDATA"),OS.get_environment("LOCALAPPDATA"),OS.get_environment("PARCHMENT_ORIGINAL_APPDATA"),ProjectSettings.globalize_path("user://"),ProjectSettings.globalize_path("res://Temp/ming-maritime-profiles")),"dedicated task profile distinct from original required")
	check(DisplayServer.get_name()!="headless","GPU display required")
	if DisplayServer.get_name()!="headless":
		var adapter := RenderingServer.get_video_adapter_name().to_lower()
		check(not adapter.is_empty() and not "llvmpipe" in adapter and not "swiftshader" in adapter,"non-software graphics adapter required")
	if failures:
		print("OPENING_INPUT_DIAGNOSTIC_GUARD_REJECTED failures=",failures)
		quit(2); return
	directory=selected
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))==OK,"create fresh evidence directory")
	if failures: quit(2); return
	output_owned=true
	for file: String in INPUTS:
		sources[file]=FileAccess.get_sha256("res://"+file)
		check(not sources[file].is_empty(),"source exists: "+file)
	if failures: await finish(); return
	await super.run()

func _rect(rect: Rect2) -> Array: return [rect.position.x,rect.position.y,rect.size.x,rect.size.y]

func _require(value: bool, detail: String) -> bool:
	check(value,detail)
	return value

func _stage_allowed(label: String, state: Dictionary) -> bool:
	if label not in ["07-next-objective-at-sea","08-at-sea-journal","09-sailing-1600"]: return true
	return state.has("port") and state.port == null

func _hover() -> String:
	var control := root.gui_get_hovered_control()
	return str(control.get_path()) if is_instance_valid(control) else ""

func _state() -> Dictionary:
	if not is_instance_valid(scene): return {}
	var packet: Dictionary=scene.runtime.snapshot()
	var state: Dictionary=packet.get("campaign",{})
	var runtime: Dictionary=packet.get("runtime",{})
	return {"port":state.get("currentPortId"),"revision":state.get("revision"),"time":state.get("simulationSeconds"),"canDepart":runtime.get("canDepart"),"notice":runtime.get("notice"),"noticeRevision":runtime.get("noticeRevision"),"chronicleLast":state.get("chronicle",[]).slice(-2)}

func _watch() -> void:
	if not is_instance_valid(scene) or watched==scene.interface: return
	watched=scene.interface
	watched.command_requested.connect(func(intent):
		intents.append({"intent":intent.duplicate(true),"stateAfterSceneHandler":_state()}))

func click(control: Control) -> void:
	var name_ := str(control.name)
	var ancestor: Node=control.get_parent()
	while ancestor:
		if ancestor is ScrollContainer: ancestor.ensure_control_visible(control)
		ancestor=ancestor.get_parent()
	await frames(3)
	if not is_instance_valid(control):
		trace.append({"name":name_,"freedBeforeInput":true}); check(false,"control freed before click: "+name_); return
	_watch()
	var bounds := control.get_global_rect()
	var intersection := bounds.intersection(Rect2(Vector2.ZERO,Vector2(root.size)))
	var clips: Array=[]
	ancestor=control.get_parent()
	while ancestor:
		if ancestor is Control and ancestor.clip_contents:
			var clip: Rect2=ancestor.get_global_rect()
			intersection=intersection.intersection(clip)
			clips.append({"path":str(ancestor.get_path()),"rect":_rect(clip),"intersection":_rect(intersection)})
		ancestor=ancestor.get_parent()
	var pressed := [0]
	if control is Button: control.pressed.connect(func(): pressed[0]+=1)
	var before := {"path":str(control.get_path()),"instance":control.get_instance_id(),"visible":control.is_visible_in_tree(),"disabled":control.disabled if control is Button else null,"bounds":_rect(bounds),"visibleIntersection":_rect(intersection),"clips":clips,"hover":_hover(),"state":_state()}
	# Match the historical input sequence exactly; do not add motion/global_position.
	var event:=InputEventMouseButton.new(); event.button_index=MOUSE_BUTTON_LEFT; event.pressed=true; event.position=bounds.get_center()
	Input.parse_input_event(event); await process_frame
	var hover_press := _hover()
	event=event.duplicate(); event.pressed=false; Input.parse_input_event(event); await frames(3)
	var current: Control = scene.interface.find_child(name_,true,false) if is_instance_valid(scene) else null
	trace.append({"name":name_,"before":before,"pressedCount":pressed[0],"hoverAfterPress":hover_press,"afterInstance":current.get_instance_id() if is_instance_valid(current) else 0,"afterState":_state()})

func capture(label: String) -> void:
	await frames(6); await RenderingServer.frame_post_draw
	var state := _state()
	if not _stage_allowed(label,state):
		skipped.append({"label":label,"reason":"not-confirmed-at-sea","state":state})
		check(false,"refuse mislabeled at-sea capture: "+label)
		return
	var path := directory+"/"+label+".png"
	if not _require(not FileAccess.file_exists(path),"fresh capture "+label): return
	var pixels := root.get_texture().get_image()
	if not _require(pixels!=null and not pixels.is_empty(),"nonempty GPU frame "+label): return
	if not _require(pixels.save_png(path)==OK,"GPU capture "+label): return
	var digest := FileAccess.get_sha256(path)
	if not _require(not digest.is_empty(),"captured image hash "+label): return
	stages.append({"label":label,"state":state,"imageSha256":digest,"viewport":[pixels.get_width(),pixels.get_height()]})
	captures+=1

func finish() -> void:
	if main: main.queue_free(); await frames(4); main=null
	for file: String in sources:
		check(FileAccess.get_sha256("res://"+file)==sources[file],"source unchanged: "+file)
	if output_owned:
		var result_path := directory+"/capture-result.json"
		if not _require(not FileAccess.file_exists(result_path),"fresh capture result"):
			print("OPENING_INPUT_DIAGNOSTIC_COMPLETE captures=",captures," assertions=",assertions," failures=",failures)
			quit(1); return
		var payload := {"assertions":assertions,"failures":failures,"captures":captures,"trace":trace,"intents":intents,"stages":stages,"skipped":skipped,"sourceHashes":sources,"userDataDir":ProjectSettings.globalize_path("user://"),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"display":DisplayServer.get_name(),"scope":"Real MainScene and frame-post-draw GPU screenshots with injected viewport mouse events. Original player slots are not read. World is frozen by inherited harness; not OS input, continuous voyage, full-source freeze or performance acceptance."}
		var encoded := JSON.stringify(payload,"\t",false,true)
		var file := FileAccess.open(result_path,FileAccess.WRITE)
		if file:
			file.store_string(encoded); file.flush(); var okay := file.get_error()==OK; file.close()
			check(okay and FileAccess.get_file_as_string(result_path)==encoded,"capture result flushed and read back exactly")
		else: check(false,"capture result write")
	print("OPENING_INPUT_DIAGNOSTIC_COMPLETE captures=",captures," assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)

func _guard_tests() -> void:
	var allowed := "C:/project/Temp/ming-maritime-profiles"
	var own := allowed+"/123"
	check(_profile_ok(own,own,"C:/Users/player/AppData/Roaming",own+"/Godot/app_userdata/MingArmada",allowed),"distinct child profile accepted")
	check(not _profile_ok(own,own,own,own+"/Godot/app_userdata/MingArmada",allowed),"original profile rejected")
	check(not _profile_ok(own,own,allowed,own+"/Godot/app_userdata/MingArmada",allowed),"child of original profile rejected")
	check(not _profile_ok(own,allowed+"/456","C:/old",own+"/Godot/app_userdata/MingArmada",allowed),"split profile rejected")
	check(not _profile_ok("C:/outside","C:/outside","C:/old","C:/outside/Godot",allowed),"outside workspace rejected")
	check(not _profile_ok(own,own,"C:/old","C:/elsewhere/Godot",allowed),"outside user data rejected")
	check(not _output_ok(""),"empty path rejected")
	check(not _output_ok("res://docs/migration/evidence/opening-story/native"),"existing evidence rejected")
	check(not _output_ok("res://docs/migration/evidence/opening-story/../bad"),"traversal rejected")
	check(not _output_ok("res://tools/outside"),"outside evidence rejected")
	check(not _output_ok("res://docs/migration/evidence/opening-story/CON"),"device alias rejected")
	check(_output_ok("res://docs/migration/evidence/opening-story/opening-input-guard-"+str(OS.get_process_id())),"unused output accepted")
	check(not _stage_allowed("07-next-objective-at-sea",{"port":"xiamen"}),"still in port rejects sailing screenshot")
	check(not _stage_allowed("08-at-sea-journal",{}),"missing port rejects sailing screenshot")
	check(_stage_allowed("09-sailing-1600",{"port":null}),"actual sailing state permits sailing screenshot")
	check(_stage_allowed("06-debt-payment-1280",{"port":"xiamen"}),"ordinary port screenshot remains allowed")
	print("OPENING_INPUT_DIAGNOSTIC_GUARDS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
