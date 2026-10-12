extends "res://tools/capture-fidelity-island.gd"
const PresentationProfile=preload("res://tools/profile-career-presentation.gd")
## Private CPU diagnostic: actual menu/router and production methods.
## Synchronous method costs are not native FPS or GPU timings.
var report: Dictionary={"scope":"Actual game entry and CPU method costs; no FPS/GPU performance claim.","scenes":[],"failures":0}
var physics_budget_ms:=0.0
func _run() -> void:
	output="res://Temp/career-cost-baseline-v1.json"
	var order: Array=["mingqi","duel"]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
		if arg.begins_with("--order="): order=arg.trim_prefix("--order=").split(",")
		if arg.begins_with("--budget-ms="): physics_budget_ms=arg.trim_prefix("--budget-ms=").to_float()
	if FileAccess.file_exists(output): check(false,"fresh diagnostic output required"); quit(1); return
	root.size=Vector2i(1600,900)
	var slot:=MemorySlot.new(); var legacy:=MemorySlot.new()
	settings=Settings.new("user://verification/career-cost-no-write-%d.json"%OS.get_process_id())
	main=Main.new(); main.router=Router.new({"mingqi_storage":slot,"legacy_storage":legacy,"settings_storage":settings}); root.add_child(main)
	for frame in 5: await process_frame
	for mode: String in order:
		var button: Button=main.menu.find_child(mode,true,false)
		if not check(button!=null and not button.disabled,"actual menu route "+mode): continue
		var entry_start:=Time.get_ticks_usec()
		button.pressed.emit()
		if not await _await_scene(mode): continue
		var entry_ms:=float(Time.get_ticks_usec()-entry_start)/1000.0
		var game: Node=main.current_scene
		game.set_physics_process(false)
		game.set_process(false)
		if game.has_method("_render"):
			game.process_mode=Node.PROCESS_MODE_DISABLED; game.paused=true
			var preview_samples: Array=[]
			for index in 6:
				var preview_start:=Time.get_ticks_usec(); game._render()
				preview_samples.append(float(Time.get_ticks_usec()-preview_start)/1000.0)
				await process_frame
			report.scenes.append({"mode":mode,"entryWallMs":entry_ms,"shipCount":0,"nodeCount":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"previewOwnerMs":preview_samples})
			print("CAREER_COST preview ",mode," ",preview_samples)
			main._return_from_scene(game)
			for frame in 5: await process_frame
			continue
		var packet: Dictionary=game.runtime.snapshot()
		var scene_report: Dictionary={"mode":mode,"entryWallMs":entry_ms,"shipCount":packet.naval.ships.size(),"nodeCount":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"initialPause":packet.runtime.get("pauseReasons",[]),"phases":[]}
		print("CAREER_COST entry ",mode," ms=",entry_ms," ships=",packet.naval.ships.size())
		for state in ["paused","running"]:
			game.runtime.set_pause("blur",false)
			if mode=="mingqi": game.interface.close_panel(); game.interface.close_menu()
			else: game.runtime.set_pause("menu",false)
			game.runtime.set_pause("player",state=="paused")
			var samples: Array=[]
			for sample_index in 6:
				var t:=Time.get_ticks_usec()
				game._physics_process(1.0/60.0)
				var whole_ms:=float(Time.get_ticks_usec()-t)/1000.0
				var render_ms:=0.0
				if mode=="mingqi" and game.has_method("_process"):
					t=Time.get_ticks_usec(); game._process(0.0)
					render_ms=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec()
				var native_observed: Dictionary=game.runtime.simulation.snapshot() if mode=="mingqi" else game.runtime.snapshot().naval
				game.sea.observe_projectiles(native_observed)
				var observe_ms:=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec()
				var consumed: float=game.runtime.advance(1.0/60.0)
				var advance_ms:=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec(); packet=game.runtime.snapshot()
				var snapshot_ms:=float(Time.get_ticks_usec()-t)/1000.0
				if mode=="mingqi":
					packet.runtime.hasCheckpoint=false; packet.runtime.saveStatus=""
					game.sea.tactical=game.tactical; game.sea.zoom=game._zoom
				t=Time.get_ticks_usec()
				var events: Array=game.sea.apply_snapshot(packet.naval,game.runtime.drain_events(),consumed)
				var sea_ms:=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec(); game.services.present(packet.naval,events,consumed,packet.runtime.paused)
				var services_ms:=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec(); game.interface.apply_snapshot(packet)
				var ui_ms:=float(Time.get_ticks_usec()-t)/1000.0
				t=Time.get_ticks_usec(); game.minimap.present(packet.naval,{},false)
				var minimap_ms:=float(Time.get_ticks_usec()-t)/1000.0
				samples.append({"wholePhysicsMethodMs":whole_ms,"renderPresentationMethodMs":render_ms,"wholeOwnerMs":whole_ms+render_ms,"observeMs":observe_ms,"advanceMs":advance_ms,"snapshotMs":snapshot_ms,"seaMs":sea_ms,"servicesMs":services_ms,"interfaceMs":ui_ms,"minimapMs":minimap_ms,"acceptedTime":packet.naval.time,"paused":packet.runtime.paused})
				if OS.get_cmdline_user_args().has("--stages"):
					var detail: Dictionary=PresentationProfile.sample(game.sea,packet.naval)
					check(detail.get("ok",false),"same-time production presentation profiling is valid")
					samples[-1].presentation=detail
				print("CAREER_COST ",mode," ",state," sample=",sample_index," physicsMs=",whole_ms," renderMs=",render_ms," seaMs=",sea_ms)
				await process_frame
			scene_report.phases.append({"state":state,"samples":samples})
			if mode=="mingqi" and physics_budget_ms>0.0:
				var costs: Array=samples.map(func(value: Dictionary):return value.wholePhysicsMethodMs)
				costs.sort()
				var median: float=(float(costs[2])+float(costs[3]))*0.5
				check(median<=physics_budget_ms,"actual mingqi "+state+" CPU method budget %.2fms; median %.3fms"%[physics_budget_ms,median])
		report.scenes.append(scene_report)
		main._return_from_scene(game)
		for frame in 5: await process_frame
	check(slot.writes==0 and legacy.writes==0,"diagnostic preserves actual user saves")
	report.failures=failures; report.headless=DisplayServer.get_name()=="headless"; report.godot=Engine.get_version_info().string; report.gpu=RenderingServer.get_video_adapter_name()
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if check(file!=null,"diagnostic receipt opens"): file.store_string(JSON.stringify(report,"\t")); file.close()
	main.free()
	print("CAREER_COST_COMPLETE failures=",failures)
	quit(1 if failures else 0)
