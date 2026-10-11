extends SceneTree
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/presentation/audio/game_audio.gd"):
		check(false,"native audio must synthesize palette and own bounded voices"); _finish(); return
	var Audio = load("res://game/presentation/audio/game_audio.gd")
	await _verify_native_signal_path(Audio)
	var initial_buses := AudioServer.bus_count
	var audio = Audio.new(); root.add_child(audio)
	audio.apply_settings({"sound":true,"music":true,"soundVolume":0.5,"musicVolume":0.7})
	audio.set_paused(false)
	audio.set_listener(Vector3.ZERO)
	audio.apply_snapshot({"time":12.0,"wind":{"speed":20.0},"battleId":"fixture","ships":[],"projectiles":[]},0.1)
	await create_timer(0.04).timeout
	var diag: Dictionary = audio.diagnostics()
	check(diag.clock == 12 and diag.seaGain > 0 and diag.windGain > 0,"ambient follows explicit snapshot wind and accepted clock")
	check(diag.musicMode == "sailing" and absf(diag.musicGain-0.245)<0.00001,"source sailing music uses individual volume times .35")
	check(audio.get_node("Music").stream is AudioStreamMP3,"copied sailing music loads actual native compressed AudioStream")
	var events := [{"id":"fire-1","type":"fire","time":12.0,"position":{"x":100,"y":0,"z":0}},{"id":"hit-1","type":"hit","time":12.0,"position":{"x":0,"z":0}},{"id":"dock-1","type":"dock","time":12.0}]
	audio.apply_events(events); audio.apply_events(events)
	await create_timer(0.04).timeout
	diag = audio.diagnostics()
	check(diag.activeVoices == 3 and diag.deduplicated == 3,"duplicate accepted event IDs cannot replay voices")
	var fire = audio.get_node("Voices").get_child(0)
	var hit = audio.get_node("Voices").get_child(1)
	var dock = audio.get_node("Voices").get_child(2)
	check(fire.stream is AudioStreamWAV and fire.stream.mix_rate == 22050 and fire.stream.data.size() == 28666,"cannon generates real 0.65 second native PCM waveform")
	check(hit.stream.data.size() == 11026 and dock.stream.data.size() == 47628,"impact and two-note bronze dock preserve source durations")
	check(fire.stream.data != hit.stream.data and dock.stream.data != hit.stream.data,"events have distinct waveforms instead of generic clicks")
	check(absf(fire.volume_linear-0.0875)<0.00001 and absf(hit.volume_linear-0.06)<0.00001,"100m event source attenuation halves cannon gain while local impact remains full")
	check(fire.get_meta("position") == Vector3(100,0,0),"native voice retains emitted world position")
	audio.set_listener(Vector3(100,0,0))
	check(absf(fire.volume_linear-0.175)<0.00001,"listener movement updates source distance gain")
	var burst: Array = []
	for i in 30: burst.append({"id":"burst-%d"%i,"type":"splash","time":12.1})
	audio.apply_events(burst)
	await create_timer(0.04).timeout
	check(audio.diagnostics().activeVoices == 16 and audio.get_node("Voices").get_child_count() == 16,"oldest voice release bounds native player count to source cap 16")
	audio.set_paused(true)
	await create_timer(0.04).timeout
	var clock: float = audio.diagnostics().clock
	audio.apply_snapshot({"time":99.0,"wind":{"speed":40.0}},20)
	audio.apply_events([{"id":"during-pause","type":"fire","time":99.0}])
	check(audio.diagnostics().clock == clock and audio.diagnostics().seaGain == 0 and audio.diagnostics().activeVoices == 16,"pause neither accepts clock nor queues new sounds")
	check(audio.get_node("Voices").get_child(0).stream_paused and audio.get_node("Music").stream_paused,"pause suspends native effects and music")
	audio.set_paused(false)
	await create_timer(0.04).timeout
	audio.apply_events([{"id":"during-pause","type":"fire","time":99.0}])
	check(audio.diagnostics().activeVoices == 16 and audio.diagnostics().deduplicated == 4,"muted/paused events cannot replay after resume")
	audio.apply_snapshot({"time":12.5,"wind":{"speed":20.0},"combat":true,"battleId":"fixture"},0.5)
	await create_timer(0.04).timeout
	check(audio.diagnostics().musicMode == "combat" and audio.get_node("Music").stream.resource_path.ends_with("破浪赤焰.mp3"),"combat snapshot selects copied combat track")
	audio.apply_settings({"sound":false,"music":false})
	await create_timer(0.04).timeout
	check(audio.diagnostics().activeVoices == 0 and audio.diagnostics().seaGain == 0 and not audio.get_node("Music").playing,"toggles release native effects and stop music")
	audio.apply_settings({"sound":true,"music":true,"soundVolume":1.0})
	audio.apply_events([{"id":"mission-1","type":"mission","time":13.0}])
	await create_timer(0.04).timeout
	check(audio.diagnostics().activeVoices == 1,"mission feedback resumes only from new accepted event")
	audio.apply_snapshot({"time":0.0,"wind":{"speed":10.0},"battleId":"replacement"},0.1)
	check(audio.diagnostics().activeVoices == 0 and audio.diagnostics().clock == 0,"battle handoff releases old voices and resets accepted clock")
	audio.apply_events([{"id":"life","type":"order","time":0.0}])
	await create_timer(0.04).timeout
	var life = audio.get_node("Voices").get_child(0)
	var late_finish: Callable = life.finished.get_connections()[0].callable
	life.finished.emit()
	check(audio.diagnostics().activeVoices == 0,"native finished signal releases voice without shared game timer")
	audio.apply_events([{"id":"natural-finish","type":"splash","time":0.0}])
	await create_timer(0.35).timeout
	check(audio.diagnostics().activeVoices == 0 and audio.diagnostics().clock == 0,"actual native playback finishes and releases without advancing accepted game clock")
	audio.dispose(); audio.dispose()
	audio.apply_settings({"sound":true}); audio.set_paused(false); audio.apply_events([{"id":"late","type":"fire"}]); late_finish.call()
	check(audio.diagnostics().state == "disposed" and audio.diagnostics().activeVoices == 0 and not audio.get_node("Music").playing,"dispose and late callbacks cannot revive audio")
	check(AudioServer.bus_count == initial_buses,"dispose releases owned native filter buses")
	audio.queue_free(); await process_frame
	# AudioServer retires stopped playback objects on its own mixing thread.
	await create_timer(0.15).timeout
	_finish()
func _rms(samples: PackedVector2Array) -> float:
	var total := 0.0
	for sample in samples: total += sample.length_squared()
	return sqrt(total/maxi(1,samples.size()))

func _verify_native_signal_path(Audio: GDScript) -> void:
	# Mutation caught: constructing Effects after Sea/Wind bypasses compressor.
	# Read native mixed PCM, not player gains or configured send names.
	var initial_count := AudioServer.bus_count
	var unrelated_name := "AudioTestUnrelated%d" % OS.get_process_id()
	AudioServer.add_bus(); AudioServer.set_bus_name(initial_count,unrelated_name)
	AudioServer.set_bus_volume_db(initial_count,-9)
	var audio = Audio.new(); root.add_child(audio)
	audio.apply_settings({"sound":true,"music":false,"soundVolume":1.0})
	audio.set_paused(false)
	audio.apply_snapshot({"time":12.0,"wind":{"speed":20.0}},0.1)
	var sea: AudioStreamPlayer = audio.get_node("Sea")
	var effects_index := AudioServer.get_bus_index(AudioServer.get_bus_send(AudioServer.get_bus_index(sea.bus)))
	var master_capture := AudioEffectCapture.new(); master_capture.buffer_length = 0.5
	var effects_capture := AudioEffectCapture.new(); effects_capture.buffer_length = 0.5
	var master_effect_index := AudioServer.get_bus_effect_count(0)
	AudioServer.add_bus_effect(0,master_capture)
	AudioServer.add_bus_effect(effects_index,effects_capture)
	await create_timer(0.25).timeout
	var effects_samples := effects_capture.get_buffer(effects_capture.get_frames_available())
	var master_samples := master_capture.get_buffer(master_capture.get_frames_available())
	var effects_rms := _rms(effects_samples); var master_rms := _rms(master_samples)
	print("AUDIO_NATIVE_SIGNAL effects_rms=",effects_rms," master_rms=",master_rms)
	check(master_rms > 0.001 and master_samples.size() > 1000,"native ambient produces a measurable actual master signal")
	check(effects_rms > 0.001 and effects_samples.size() > 1000,"actual ambient PCM traverses shared effects/compressor bus")
	# With music disabled and no events, every master sample comes via Effects.
	check(absf(effects_rms-master_rms) < 0.00001,"native master ambience equals shared effects output with no bypass")
	audio.dispose(); audio.queue_free()
	check(AudioServer.bus_count == initial_count+1 and AudioServer.get_bus_index(unrelated_name) == initial_count and AudioServer.get_bus_volume_db(initial_count) == -9,"owned graph teardown preserves existing unrelated native bus")
	AudioServer.remove_bus_effect(0,master_effect_index)
	AudioServer.remove_bus(AudioServer.get_bus_index(unrelated_name))
	await process_frame; await create_timer(0.15).timeout
func _finish() -> void:
	print("GAME_AUDIO_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
