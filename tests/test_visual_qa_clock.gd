extends SceneTree
## Real idle clock regression; original scene, Encounter and JSON export, isolated storage.
class IsolatedQA extends "res://game/scenes/visual_qa/visual_qa.gd":
	var diagnostic_path: String
	func export_diagnostics(path: String="") -> Dictionary:
		return super.export_diagnostics(diagnostic_path if path.is_empty() else path)
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var directory:="user://migration-verification/visual-qa-clock-%d" % OS.get_process_id()
	var settings_path:=directory+"-settings.json"
	var diagnostic_path:=directory+"-diagnostics.json"
	var scene:=IsolatedQA.new()
	scene.startup_options={"qa":true,"staged":true,"scenario":"benchmark"}
	scene.settings_storage=load("res://game/persistence/user_settings.gd").new(settings_path)
	scene.diagnostic_path=diagnostic_path
	root.add_child(scene); await process_frame; scene.set_process(false); scene.set_physics_process(false)
	check(scene.startup_receipt.ok,"native benchmark clock fixture prepared")
	scene.activate_entry()
	for intent: Dictionary in [{"type":"fire","side":"starboard"},{"type":"select-ammo","ammo":"chain"},{"type":"sails","value":0.5},{"type":"handling","value":"assisted"},{"type":"playback","value":0.25},{"type":"export"}]:
		# Deterministic earlier wall-clock anchor, then ordinary UI command + actual idle callback.
		# No synthetic physics callback or substitute clock implementation used.
		var anchor:=Time.get_ticks_usec()/1000.0-250.0
		scene._last_frame_ms=anchor
		var before: float=scene.runtime.snapshot().runtime.benchmarkSeconds
		var samples: int=scene.runtime.diagnostics.summary().sampleCount
		scene._command(intent)
		check(scene._last_frame_ms==anchor,"ordinary "+intent.type+" retains previous idle callback anchor")
		scene._process(0.0)
		var intervals: Array=scene.runtime.diagnostics.snapshot().samples
		check(intervals.size()==samples+1 and intervals.back().elapsedMs>=250.0,"actual _process retains entire interactive wall interval "+intent.type)
		check(scene.runtime.snapshot().runtime.benchmarkSeconds-before>=0.25,"interactive benchmark wall time includes ordinary "+intent.type)
	check(FileAccess.file_exists(diagnostic_path),"export-clock regression uses real JSON in isolated destination")
	scene._last_frame_ms=Time.get_ticks_usec()/1000.0-5000.0
	var pause_start:=Time.get_ticks_usec()/1000.0
	scene._command({"type":"pause"})
	check(scene.runtime.is_paused() and scene._last_frame_ms>=pause_start,"pause resets callback anchor at inactive transition")
	var paused_time: float=scene.runtime.snapshot().runtime.benchmarkSeconds
	var paused_samples: int=scene.runtime.diagnostics.summary().sampleCount
	scene._last_frame_ms=Time.get_ticks_usec()/1000.0-5000.0
	scene._process(0.0)
	check(scene.runtime.snapshot().runtime.benchmarkSeconds==paused_time and scene.runtime.diagnostics.summary().sampleCount==paused_samples,"actual paused idle callback excludes inactive wall period")
	scene._last_frame_ms=Time.get_ticks_usec()/1000.0-5000.0
	var resume_start:=Time.get_ticks_usec()/1000.0
	scene._command({"type":"resume"})
	check(not scene.runtime.is_paused() and scene._last_frame_ms>=resume_start,"resume resets anchor before first active callback")
	var resume_anchor: float=scene._last_frame_ms
	scene._process(0.0)
	# Active presentation CPU is part of the source wall interval. Compare with
	# the reset callback anchor instead of assuming the host completes it in .2s.
	check(absf(scene.runtime.snapshot().runtime.benchmarkSeconds-paused_time-(scene._last_frame_ms-resume_anchor)/1000.0)<0.000001,"resumed actual idle callback counts only wall time since active anchor")
	scene._command({"type":"open-settings"})
	check(scene.runtime.is_paused() and scene.services.captures_keyboard(),"actual settings dialog pauses benchmark")
	scene._last_frame_ms=Time.get_ticks_usec()/1000.0-5000.0
	var close_start:=Time.get_ticks_usec()/1000.0
	var settings_time: float=scene.runtime.snapshot().runtime.benchmarkSeconds
	scene.services.settings_panel.close_requested.emit()
	check(not scene.runtime.is_paused() and scene._last_frame_ms>=close_start,"actual settings close resets paused callback anchor")
	var close_anchor: float=scene._last_frame_ms
	scene._process(0.0)
	check(absf(scene.runtime.snapshot().runtime.benchmarkSeconds-settings_time-(scene._last_frame_ms-close_anchor)/1000.0)<0.000001,"actual settings-close callback excludes hidden wall period while counting active CPU")
	scene._last_frame_ms=Time.get_ticks_usec()/1000.0-5000.0
	var restart_start:=Time.get_ticks_usec()/1000.0
	scene._command({"type":"restart"})
	check(scene.runtime.snapshot().naval.tick==0 and scene._last_frame_ms>=restart_start,"restart resets clock after rebuilding real benchmark")
	var restart_anchor: float=scene._last_frame_ms
	scene._process(0.0)
	check(absf(scene.runtime.snapshot().runtime.benchmarkSeconds-(scene._last_frame_ms-restart_anchor)/1000.0)<0.000001,"restarted actual idle callback counts only its new run wall interval")
	scene.queue_free(); await process_frame; await process_frame; await create_timer(0.08).timeout
	for path: String in [settings_path,diagnostic_path]:
		for suffix in ["",".backup",".rollback",".staged"]:
			if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	print("VISUAL_QA_CLOCK_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
