extends SceneTree
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var path:="res://game/runtime/visual_qa_runtime.gd"
	check(ResourceLoader.exists(path),"fifteen source visual scenarios have a real native runtime")
	if ResourceLoader.exists(path):
		var script=load(path)
		var expected:=["fleet","damage","sink","impact","impact-weak","benchmark","shore-escape","wave-fisherman","wave-patrol","crew-fuchuan","crew-fisherman","crew-merchant","crew-voc","crew-patrol","crew-heavy"]
		check(script.SCENARIOS==expected,"original fifteen scenario IDs and order retained")
		var height=load("res://modules/scene_engine/terrain/height_field.gd").new()
		height.configure_ports(load("res://game/domain/legacy/catalog.gd").DATA.PORTS,false)
		for id: String in expected:
			var runtime=script.new(); var receipt: Dictionary=runtime.configure(height.sample_height,{"scenario":id})
			check(receipt.ok,"real Encounter accepts source config "+id)
			if not receipt.ok: runtime.dispose(); continue
			var native: Dictionary=runtime.snapshot().naval
			check(native.battleId=="visual-"+id and native.tick==0,"source identity and zero initial tick "+id)
			check(runtime.snapshot().runtime.handlingMode=="realistic","QA defaults to original realistic physics "+id)
			runtime.advance(1.0/60.0)
			check(runtime.snapshot().naval.tick==1,"source uses real 60Hz physics "+id)
			if id=="shore-escape":
				check(native.ships[0].navigation=={"x":-178,"z":475},"shore escape installs source native navigation once")
				check(native.ships[0].hull==81.6 and native.ships[0].crew==37 and native.ships[0].stats.cargoMass==3000,"shore escape restored damage and load exact")
			if id.begins_with("wave-"):
				for frame in 310: runtime.advance(1.0/60.0)
				check(is_equal_approx(runtime.snapshot().naval.time,4.6) and runtime.is_paused(),"wave reaches actual 4.6s crest and freezes "+id)
				var held: Dictionary=runtime.snapshot().naval
				runtime.command({"type":"resume"}); runtime.advance(0.1)
				check(runtime.snapshot().naval==held,"source wave inspection hold survives Continue "+id)
			if id in ["impact","impact-weak","sink","damage"]:
				var before: Dictionary=runtime.snapshot().naval
				runtime.command({"type":"fire","side":"starboard"})
				var events: Array=[]
				for frame in 180:
					runtime.advance(1.0/60.0); events.append_array(runtime.drain_events())
				var after: Dictionary=runtime.snapshot().naval
				check(after.ships[0].ammo.solid<before.ships[0].ammo.solid,"source cannon consumes real ammo "+id)
				check(events.any(func(e): return e.type=="hit"),"source cannon produces real ballistic hit "+id)
				check(after.ships[1].hull<before.ships[1].hull,"source hit changes authoritative hull "+id)
				if id=="sink": check(after.ships[1].hull==0 and events.any(func(e): return e.type=="sink"),"low hull target sinks through actual hits")
				if id=="impact-weak": check(before.ships[1].crew-after.ships[1].crew>0 and before.ships[1].crew-after.ships[1].crew<1,"2 percent solid impact retains fractional native damage for later nonlethal recovery")
			runtime.set_held("KeyW",true); runtime.set_pause("blur",true)
			var paused: Dictionary=runtime.snapshot().naval
			runtime.advance(0.1)
			check(runtime.snapshot().naval==paused and not runtime.simulation.has_pending_input(),"focus loss freezes authority and clears input "+id)
			runtime.command({"type":"restart"})
			check(runtime.snapshot().naval.tick==0 and runtime.snapshot().runtime.playback==1.0,"restart recreates original scenario and playback "+id)
			runtime.dispose(); runtime.dispose()
			check(runtime.snapshot().is_empty(),"dispose releases native simulation "+id)
		var runtime=script.new(); runtime.configure(height.sample_height,{"scenario":"benchmark"})
		check(not runtime.command({"type":"playback","value":0.25}).ok,"benchmark forbids slowed sampling")
		for frame in 801: runtime.advance(0.1)
		check(runtime.is_paused() and runtime.snapshot().runtime.phase=="complete" and runtime.snapshot().runtime.benchmarkSeconds>=80,"benchmark wall-time warmup20/sample60 auto pauses")
		check(runtime.original_metrics().frames==601,"benchmark matches source 20 inclusive /80 exclusive on accumulated 0.1s wall intervals")
		runtime.dispose()
		var diagnostics=script.FrameDiagnostics.new()
		diagnostics.complete_frame({"cpuStartedAtMs":10.0,"cpuCompletedAtMs":20.0,"cpu":{"simulationMs":3.0},"world":{"before":{"chunks":1},"after":{"chunks":2}}})
		diagnostics.record_interval({"elapsedMs":16.0,"callbackTimestampMs":25.0,"benchmarkSeconds":22.0,"phase":"sampling","includedInMetrics":true})
		diagnostics.record_interval({"elapsedMs":200.0,"callbackTimestampMs":300.0,"benchmarkSeconds":81.0,"phase":"complete","includedInMetrics":false})
		var data: Dictionary=diagnostics.snapshot()
		check(data.samples[0].previousCompletedFrame!=null and data.samples[1].previousCompletedFrame==null,"frame CPU attached only when previous span overlaps interval")
		data.samples[0].previousCompletedFrame.cpu.simulationMs=999
		check(diagnostics.snapshot().samples[0].previousCompletedFrame.cpu.simulationMs==3.0,"diagnostic export detached from stored CPU and chunks")
		check(diagnostics.summary().maxMs==200.0 and diagnostics.summary().includedInMetrics==1 and diagnostics.summary().overMs[100]==1,"raw long frame retained outside benchmark metric window")
	print("VISUAL_QA_RUNTIME_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
