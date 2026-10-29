extends SceneTree
## Scripted ordinary game entry. Real authority and production presentation only.
const Main = preload("res://game/scenes/main/main_scene.tscn")
const STEP := 1.0/60.0
const TICKS_PER_FRAME := 4
const DUEL_SAMPLES := 180
var main: Node
var scene: Node
var output := ""
var own_output := false
var failures: Array = []
var captures: Array = []
var sequences: Array = []
var checks: Array = []
var commands: Array = []
var observed_shots: Dictionary = {}
var accepted_steps := 0
var default_sound_disabled := false
var camera_mode := "normal"
var cargo_focus_ship := ""

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> bool:
	if not value: failures.append(message); printerr("FAIL CARGO FX PRODUCTION: ",message)
	return value
func frames(count: int) -> void:
	for _i in count: await process_frame
func normal(path: String) -> String: return path.replace("\\","/").simplify_path().trim_suffix("/").to_lower()
func inside(path: String,parent: String) -> bool: return not parent.is_empty() and normal(path).begins_with(normal(parent)+"/")
func digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new(); context.start(HashingContext.HASH_SHA256); context.update(bytes); return context.finish().hex_encode()
func state_digest(value: Dictionary) -> String: return digest(JSON.stringify(value,"",false,true).to_utf8_buffer())
func same_data(a: Variant,b: Variant)->bool:
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:return a==b
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key:Variant in a:
			if not b.has(key) or not same_data(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same_data(a[i],b[i]):return false
		return true
	return a==b

func run() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--output=") and output.is_empty(): output=arg.trim_prefix("--output=")
		else: check(false,"unknown or duplicate argument")
	var expected := OS.get_environment("CARGO_FX_PRODUCTION_CAPTURE_OUTPUT")
	var profile := OS.get_environment("CARGO_FX_PRODUCTION_PROFILE_ROOT")
	var original := OS.get_environment("CARGO_FX_PRODUCTION_ORIGINAL_APPDATA")
	var app := OS.get_environment("APPDATA")
	var local := OS.get_environment("LOCALAPPDATA")
	check(not expected.is_empty() and output.begins_with("res://docs/research/evidence/cargo-fx-production/") and output.ends_with("/frames") and not output.contains("..") and not output.contains("\\") and normal(ProjectSettings.globalize_path(output))==normal(expected) and not DirAccess.dir_exists_absolute(expected) and not FileAccess.file_exists(expected),"fresh confined output")
	check(not original.is_empty() and inside(app,profile) and inside(local,profile) and normal(app)!=normal(local) and inside(ProjectSettings.globalize_path("user://"),app) and not inside(profile,original) and not inside(original,profile) and normal(profile)!=normal(original),"isolated actual userdata")
	check(DisplayServer.get_name()!="headless","non-headless graphics required")
	if DisplayServer.get_name()!="headless":
		var gpu:=RenderingServer.get_video_adapter_name().to_lower()
		check(not gpu.is_empty() and not "llvmpipe" in gpu and not "swiftshader" in gpu and not "software" in gpu,"hardware graphics required")
	if not failures.is_empty():
		print("CARGO_FX_PRODUCTION_GUARD_REJECTED failures=",failures.size()); quit(2); return
	if not check(DirAccess.make_dir_recursive_absolute(expected)==OK,"create fresh output"): quit(2); return
	own_output=true
	seed(1661)
	DisplayServer.window_set_size(Vector2i(1600,900)); root.content_scale_size=Vector2i(1600,900); root.size=Vector2i(1600,900)
	await frames(3)
	main=Main.instantiate(); root.add_child(main); await frames(4)
	var settings: Dictionary=main.router.settings_storage.snapshot()
	default_sound_disabled=not settings.sound and not settings.music
	if not check(default_sound_disabled,"fresh ordinary profile defaults to sound and music disabled"): await finish(); return
	await capture("menu-before.png","menu",{})
	if not await enter("mingqi"): await finish(); return
	if not await mingqi_case(): await finish(); return
	if not await leave("mingqi"): await finish(); return
	if not await enter("duel"): await finish(); return
	if not await duel_case(): await finish(); return
	if not await leave("duel"): await finish(); return
	await capture("menu-returned.png","menu",{})
	await finish()

func enter(mode: String) -> bool:
	var button: Button=main.menu.find_child(mode,true,false)
	if not check(is_instance_valid(button) and button.is_visible_in_tree() and not button.disabled,"ordinary menu button available: "+mode): return false
	button.pressed.emit()
	for _i in 300:
		await process_frame
		if is_instance_valid(main.current_scene): break
	scene=main.current_scene
	if not check(is_instance_valid(scene) and scene.startup_receipt.get("ok",false),"actual game startup: "+mode):return false
	# Disable autonomous callbacks, then call these same production callbacks at
	# exact accepted steps. Rendering pauses do not run another authority clock.
	scene.set_process(false); scene.set_physics_process(false)
	scene.runtime.set_pause("player",true)
	scene._present(0.0)
	checks.append({"name":"entry","mode":mode,"scene":scene.get_script().resource_path,"startup":scene.startup_receipt.duplicate(true),"ordinary_button":true})
	if not check(scene.sea.effects.has_method("atmosphere_diagnostics") and scene.sea.effects.atmosphere_diagnostics().get("enabled",false),"production scene enables new atmosphere: "+mode): return false
	return quiet_audio(mode)

func quiet_audio(label: String) -> bool:
	var settings: Dictionary=scene.services.settings_storage.snapshot()
	var audio: Dictionary=scene.services.audio.diagnostics()
	return check(not settings.sound and not settings.music and float(audio.seaGain)==0.0 and float(audio.windGain)==0.0 and float(audio.musicGain)==0.0 and int(audio.activeVoices)==0,"actual scene audio remains disabled: "+label)

func business(kind: String, extra: Dictionary={}) -> Dictionary:
	var packet: Dictionary=scene.runtime.snapshot()
	var command: Dictionary={"type":kind,"commandId":"production-"+kind+"-"+str(commands.size()),"expectedRevision":packet.campaign.revision}
	command.merge(extra,true)
	var receipt: Dictionary=scene.runtime.command(command)
	commands.append({"mode":"mingqi","command":command.duplicate(true),"receipt":receipt.duplicate(true)})
	return receipt

func mingqi_state() -> Dictionary:
	var packet: Dictionary=scene.runtime.snapshot()
	return {"packet":packet,"cargo":scene.sea.cargo_diagnostics(),"crew":crew_state(),"atmosphere":scene.sea.effects.atmosphere_diagnostics(),"audio":scene.services.audio.diagnostics(),"camera":camera_state()}

func state_differences(a:Variant,b:Variant,path:String="") -> Array:
	var result:Array=[]
	if a is Dictionary and b is Dictionary:
		for key:Variant in a:
			if not b.has(key):result.append({"path":path+"."+str(key),"reason":"missing"})
			else:result.append_array(state_differences(a[key],b[key],path+"."+str(key)))
		for key:Variant in b:
			if not a.has(key):result.append({"path":path+"."+str(key),"reason":"added"})
	elif a is Array and b is Array:
		if a.size()!=b.size():result.append({"path":path,"before_size":a.size(),"after_size":b.size()})
		else:
			for index in a.size():result.append_array(state_differences(a[index],b[index],path+"["+str(index)+"]"))
	elif a!=b:result.append({"path":path,"before":str(a),"after":str(b)})
	return result

func crew_state()->Dictionary:
	var result:Dictionary={}
	for id:String in scene.sea.sailors:
		var crew:Node3D=scene.sea.sailors[id]
		var support:RefCounted=crew.get("_deck")
		var frame:Transform3D=crew.get("_deck_frame")
		var stations:Array=[]
		if support!=null:
			for index in support.stations.size():
				var station:Dictionary=support.stations[index]
				var local:Vector3=station.position
				var world:Vector3=frame*local
				stations.append({"slot":index,"role":station.role,"side":station.side,"local_position":[local.x,local.y,local.z],"world_position":[world.x,world.y,world.z]})
		var drawn:Array=[]
		for instance:Dictionary in crew.get_instances():
			var owner:Node3D=instance.get("root")
			if not is_instance_valid(owner):continue
			var p:Vector3=owner.global_position
			drawn.append({"slot":instance.slot,"position":[p.x,p.y,p.z]})
		result[id]={"visible":crew.get_visible_count(),"stations":stations,"drawn":drawn,"diagnostics":crew.diagnostics()}
	return result

func cargo_matches(state: Dictionary, minimum_loaded: int) -> bool:
	var loaded:=0
	var cargo: Dictionary=state.cargo
	if not check(cargo.get("ready",false) and cargo.get("errors",[]).is_empty(),"actual cargo renderer ready without placement errors"): return false
	for id: String in cargo.decks:
		var deck: Dictionary=cargo.decks[id]
		var manifest: Dictionary=state.packet.campaign.vessels[id].cargo
		if not check(same_data(deck.manifest,manifest),"deck manifest equals committed campaign inventory: "+id):return false
		if float(manifest.get("grain",0))>0.0:
			loaded+=1
			if not check(not deck.goods.is_empty() and deck.overflow_goods.is_empty(),"actual loaded grain has safe visible original model: "+id): return false
	if not check(loaded>=minimum_loaded and cargo.floating.is_empty(),"load/trade creates deck models without false lost-cargo lots"):return false
	return true

func settle_business() -> void:
	scene.runtime.command({"type":"pause","value":false})
	scene._physics_process(STEP)
	scene.runtime.set_pause("player",true)
	scene._present(0.0)

func mingqi_case() -> bool:
	if not check(scene.sea.has_method("cargo_diagnostics") and scene.runtime.has_method("cargo_presentation"),"production committed cargo APIs exist"):return false
	await capture("mingqi-opening.png","mingqi",mingqi_state())
	scene.interface.close_panel()
	if not check(business("accept-convoy").get("ok",false),"real convoy accepted and grain loaded"):return false
	settle_business()
	var state:=mingqi_state()
	if not cargo_matches(state,2):return false
	for id: String in state.cargo.decks:
		if id.ends_with("-grain-a"): cargo_focus_ship=id
	if not check(not cargo_focus_ship.is_empty(),"actual first convoy ship is rendered"):return false
	camera_mode="cargo"; scene.sea.set_camera_controller(place_camera); scene._present(0.0)
	var convoy:=mingqi_state()
	if not check(convoy.camera.subjectKind=="merchant" and convoy.crew.has(cargo_focus_ship) and convoy.crew[cargo_focus_ship].visible>0,"merchant cargo closeup retains real crew and station evidence"):return false
	await capture("mingqi-convoy-loaded.png","mingqi",convoy)
	var flagship: String=state.packet.campaign.flagshipId
	if not check(business("buy",{"good":"grain","quantity":10}).get("ok",false),"real port purchase accepts ten grain"):return false
	settle_business(); cargo_focus_ship=flagship; scene._present(0.0); state=mingqi_state()
	if not cargo_matches(state,3) or not check(float(state.packet.campaign.vessels[flagship].cargo.grain)==10.0,"purchase changes true flagship stock"):return false
	await capture("mingqi-grain-bought.png","mingqi",state)
	var saved: Dictionary=scene.runtime.save_checkpoint(scene.storage,"2026-10-29T00:00:00.000Z")
	commands.append({"mode":"mingqi","command":{"type":"save-checkpoint"},"receipt":saved.duplicate(true)})
	if not check(saved.get("ok",false),"real safe-port checkpoint saved only in isolated profile"):return false
	var checkpoint: Dictionary=scene.storage.read_checkpoint()
	if not check(checkpoint.get("ok",false),"saved checkpoint reads back"):return false
	if not check(business("sell",{"good":"grain","quantity":3}).get("ok",false),"real port sale accepts three grain"):return false
	settle_business();state=mingqi_state()
	if not cargo_matches(state,3) or not check(float(state.packet.campaign.vessels[flagship].cargo.grain)==7.0,"sale changes true stock while keeping one representative package"):return false
	await capture("mingqi-grain-sold.png","mingqi",state)
	var prior_epoch: String=state.cargo.epoch
	var restored: Dictionary=scene.runtime.adopt_save(checkpoint.json,null,"2026-10-29T00:00:01.000Z")
	commands.append({"mode":"mingqi","command":{"type":"adopt-checkpoint"},"receipt":restored.duplicate(true)})
	if not check(restored.get("ok",false),"real validated checkpoint restored"):return false
	scene._terminal_presentation.reset(); scene._present(0.0)
	# Restore recreates the deck after Sea invokes the inspection camera. A
	# second zero-time submission resolves that new cargo anchor and its LODs
	# before taking the pause baseline; neither authority clock advances.
	scene._present(0.0);state=mingqi_state()
	if not cargo_matches(state,3) or not check(state.cargo.epoch!=prior_epoch and float(state.packet.campaign.vessels[flagship].cargo.grain)==10.0,"readback restores stock and changes cargo ownership generation"):return false
	await capture("mingqi-grain-restored.png","mingqi",state)
	var before:=state_digest(state)
	await frames(8);scene._present(0.0)
	var after:=mingqi_state()
	if state_digest(after)!=before:
		var differences:=state_differences(state,after)
		checks.append({"name":"mingqi-pause-differences","differences":differences})
		print("CARGO_FX_PRODUCTION_PAUSE_DIFFERENCES ",JSON.stringify(differences,"",false,true))
	if not check(state_digest(after)==before,"paused cargo checkpoint remains identical through rendered frames"):return false
	checks.append({"name":"mingqi-pause","unchanged":true,"frames":8})
	await capture("mingqi-paused.png","mingqi",after)
	return quiet_audio("mingqi-after-trade-and-load")

func duel_state() -> Dictionary:
	return {"packet":scene.runtime.snapshot(),"atmosphere":scene.sea.effects.atmosphere_diagnostics(),"tail":scene._terminal_presentation.diagnostics(),"audio":scene.services.audio.diagnostics(),"camera":camera_state()}

func duel_case() -> bool:
	camera_mode="duel-near";scene.sea.set_camera_controller(place_camera);scene._present(0.0)
	var initial:=duel_state()
	var initial_tick:int=int(initial.packet.naval.tick)
	var max_smoke:=0
	var max_flames:=0
	if not await capture("duel-000.png","duel",initial):return false
	sequences.append({"file":"duel-000.png","sample":0,"physics_steps":0,"tick":initial_tick,"time":initial.packet.naval.time,"visual_time":initial.atmosphere.time})
	for sample in range(1,DUEL_SAMPLES+1):
		if sample==91:camera_mode="duel-wide"
		scene.runtime.command({"type":"resume"})
		var native:Dictionary=scene.runtime.snapshot().naval
		var player:=find_ship(native,native.playerId)
		var side:String=scene.runtime.nearest_side()
		if not player.is_empty() and float(player.hull)>0.0 and float(player.cooldownSeconds[side])<=0.0 and int(player.ammo.solid)>0 and native.status not in ["victory","defeat","surrendered"]:
			var receipt:Dictionary=scene.runtime.command({"type":"fire","side":side})
			commands.append({"mode":"duel","command":{"type":"fire","side":side},"receipt":receipt.duplicate(true),"at_tick":native.tick})
		for _i in TICKS_PER_FRAME:
			scene._physics_process(STEP)
			accepted_steps+=1
			for shot:Dictionary in scene.runtime.simulation.snapshot().projectiles:
				if not observed_shots.has(shot.id):observed_shots[shot.id]=shot.duplicate(true)
		scene.runtime.set_pause("player",true);scene._present(0.0)
		var state:=duel_state()
		if not check(state.atmosphere.ready and state.atmosphere.enabled and state.atmosphere.particles.size()<=int(state.atmosphere.capacity),"actual integrated effect layer remains bounded"):return false
		max_smoke=maxi(max_smoke,int(state.atmosphere.active_smoke));max_flames=maxi(max_flames,int(state.atmosphere.active_flames))
		var file:="duel-%03d.png"%sample
		if not await capture(file,"duel",state):return false
		sequences.append({"file":file,"sample":sample,"physics_steps":sample*TICKS_PER_FRAME,"tick":state.packet.naval.tick,"time":state.packet.naval.time,"visual_time":state.atmosphere.time})
		if sample%60==0:print("CARGO_FX_PRODUCTION_PROGRESS sample=",sample," native=",state.packet.naval.time," smoke=",max_smoke)
	var final_state:=duel_state()
	var player_shots:=0;var hostile_shots:=0
	for shot:Dictionary in observed_shots.values():
		if shot.shipId==initial.packet.naval.playerId:player_shots+=1
		elif find_ship(initial.packet.naval,shot.shipId).get("team")=="hostile":hostile_shots+=1
	if not check(player_shots>0 and hostile_shots>0 and max_smoke>0,"real player commands and normal hostile AI produce projectiles and integrated smoke"):return false
	var before:=state_digest(final_state)
	await frames(8);scene._present(0.0)
	if not check(before==state_digest(duel_state()),"paused battle freezes native state and all integrated particles"):return false
	checks.append({"name":"duel-combat","player_projectiles":player_shots,"hostile_projectiles":hostile_shots,"max_smoke":max_smoke,"max_flames":max_flames,"initial_tick":initial_tick,"final_tick":final_state.packet.naval.tick,"pause_unchanged":true})
	await capture("duel-paused.png","duel",duel_state())
	return quiet_audio("duel-active-cannon-events")

func find_ship(native:Dictionary,id:String)->Dictionary:
	for ship:Dictionary in native.get("ships",[]):
		if ship.id==id:return ship
	return {}

func place_camera() -> void:
	if not is_instance_valid(scene) or not is_instance_valid(scene.sea):return
	var camera:Camera3D=scene.sea.camera
	var native:Dictionary=scene.runtime.snapshot().naval
	var player:=find_ship(native,native.playerId)
	if player.is_empty():return
	var position:Dictionary=player.visual.position
	var focus:=Vector3(float(position.x),float(position.y)+4.0,float(position.z))
	var distance:=66.0
	var direction:=Vector3(.75,.85,-.6).normalized()
	if camera_mode=="cargo":
		var cargo:Dictionary=scene.sea.cargo_diagnostics()
		var goods:Array=cargo.get("decks",{}).get(cargo_focus_ship,{}).get("goods",[])
		if not goods.is_empty():
			focus=goods[0].world_anchor+Vector3.UP*.3;distance=7.5
			var actor:Node3D=scene.sea.ships.get(cargo_focus_ship)
			if is_instance_valid(actor):
				var model:Node3D=actor.source_deck_model()
				if is_instance_valid(model):
					var outward:Vector3=focus-model.global_position;outward.y=0.0
					if outward.length_squared()<0.00001:outward=model.global_basis.x;outward.y=0.0
					direction=(outward.normalized()*.9+Vector3.UP*1.15).normalized()
	elif camera_mode=="duel-wide":
		var target:=find_ship(native,"enemy-1")
		if not target.is_empty():focus=(focus+Vector3(float(target.visual.position.x),float(target.visual.position.y)+4.0,float(target.visual.position.z)))*.5
		distance=170.0
	camera.fov=42.0;camera.projection=Camera3D.PROJECTION_PERSPECTIVE
	camera.position=focus+direction*distance
	camera.look_at(focus,Vector3.UP)

func camera_state()->Dictionary:
	var camera:Camera3D=scene.sea.camera
	var p:=camera.global_position
	var subject:Node3D=scene.sea.ships.get(cargo_focus_ship) if camera_mode=="cargo" else null
	return {"mode":camera_mode,"position":[p.x,p.y,p.z],"fov":camera.fov,"subjectShipId":cargo_focus_ship if camera_mode=="cargo" else "","subjectKind":str(subject.get("_kind")) if is_instance_valid(subject) else "","scope":"inspection camera override only; production world/actors/UI unchanged"}

func leave(mode:String)->bool:
	var owner:WeakRef=weakref(scene.sea)
	var current:WeakRef=weakref(scene)
	scene.main_menu_requested.emit();scene=null
	await frames(4)
	var freed:bool=owner.get_ref()==null and current.get_ref()==null
	checks.append({"name":"leave","mode":mode,"released":freed})
	return check(freed and main.current_scene==null and main.menu.visible,"actual return command releases sea and scene: "+mode)

func capture(file:String,kind:String,state:Dictionary)->bool:
	await frames(1);await RenderingServer.frame_post_draw
	var image:Image=root.get_texture().get_image()
	if not check(image!=null and not image.is_empty(),"hardware framebuffer exists: "+file):return false
	image.convert(Image.FORMAT_RGBA8)
	var path:=output+"/"+file
	if not check(not FileAccess.file_exists(path) and image.save_png(path)==OK,"fresh PNG: "+file):return false
	captures.append({"file":file,"kind":kind,"viewport":[image.get_width(),image.get_height()],"sha256":FileAccess.get_sha256(path),"framebuffer_sha256":digest(image.get_data()),"framebuffer_format":"RGBA8","snapshot":state.duplicate(true)})
	return true

func finish()->void:
	var report:Dictionary={"valid":failures.is_empty(),"failures":failures,"engine":Engine.get_version_info(),"gpu":RenderingServer.get_video_adapter_name(),"renderer":RenderingServer.get_current_rendering_method(),"displayServer":DisplayServer.get_name(),"fixedStep":STEP,"ticksPerFrame":TICKS_PER_FRAME,"nominalSamplesPerAcceptedSecond":15,"acceptedSteps":accepted_steps,"defaultSoundDisabled":default_sound_disabled,"masterMuteForced":false,"checks":checks,"commands":commands,"projectiles":observed_shots.values(),"sequences":sequences,"captures":captures,"scope":"Ordinary Main menu to actual Mingqi and duel. Production callbacks driven at fixed 60 Hz, GPU snapshot after four calls; inspection cameras explicitly recorded. Fresh isolated user profile; default audio verified through actual zero scene gains/voices, not forced master mute. No manual-input, real-time FPS, whole-game completion or art-quality claim."}
	if own_output:
		var path:=output+"/capture-result.json"
		if check(not FileAccess.file_exists(path),"fresh final report"):
			var file:=FileAccess.open(path,FileAccess.WRITE)
			if file:file.store_string(JSON.stringify(report,"",false,true));file.close()
			else:check(false,"report write failed")
	if is_instance_valid(main):main.free()
	await frames(2)
	print("CARGO_FX_PRODUCTION captures=",captures.size()," samples=",sequences.size()," accepted_steps=",accepted_steps," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)
