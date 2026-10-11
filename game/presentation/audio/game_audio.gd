extends Node
## Owns native players/filters. Explicit snapshots drive ambient; audio never ticks game state.
const Palette = preload("res://game/presentation/audio/sound_palette.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
const MAX_VOICES := 16
const MAX_EVENT_IDS := 512
const MUSIC_PATHS := {"sailing":"res://assets/music/大明逐浪.mp3","combat":"res://assets/music/破浪赤焰.mp3"}
var _built := false
var _disposed := false
var _paused := true
var _settings := Settings.defaults()
var _palette := Palette.new()
var _voices: Array = []
var _seen: Dictionary = {}
var _event_floor := -INF
var _deduplicated := 0
var _listener := Vector3.ZERO
var _clock := 0.0
var _wind_speed := 0.0
var _identity := ""
var _generation := ""
var _battle_id := ""
var _music_mode := "sailing"
var _music_position := 0.0
var _music_reason := ""
var _sea_gain := 0.0
var _wind_gain := 0.0
var _music_gain := 0.0
var _sea: AudioStreamPlayer
var _wind: AudioStreamPlayer
var _music: AudioStreamPlayer
var _voice_parent: Node
var _sea_filter: AudioEffectLowPassFilter
var _wind_filter: AudioEffectLowPassFilter
var _buses: PackedStringArray = []
var _effects_bus := ""

func _ready() -> void: _build()

func _build() -> void:
	if _built or _disposed: return
	_built = true
	_voice_parent = Node.new(); _voice_parent.name = "Voices"; add_child(_voice_parent)
	_sea = _player("Sea"); _wind = _player("Wind"); _music = _player("Music")
	_sea_filter = AudioEffectLowPassFilter.new(); _sea_filter.resonance = 0.5
	_wind_filter = AudioEffectLowPassFilter.new(); _wind_filter.resonance = 0.5
	var highpass := AudioEffectHighPassFilter.new(); highpass.cutoff_hz = 280; highpass.resonance = 0.4
	var compressor := AudioEffectCompressor.new(); compressor.threshold = -18; compressor.ratio = 6; compressor.attack_us = 3000; compressor.release_ms = 220
	# Godot processes buses right to left; sends must target an earlier bus.
	_effects_bus = _bus("Effects",[compressor])
	_sea.bus = _bus("Sea",[_sea_filter]); _wind.bus = _bus("Wind",[highpass,_wind_filter])
	AudioServer.set_bus_send(AudioServer.get_bus_index(_sea.bus),_effects_bus)
	AudioServer.set_bus_send(AudioServer.get_bus_index(_wind.bus),_effects_bus)
	_sea.stream = _palette.ambient_stream(); _wind.stream = _sea.stream
	_apply_mix()

func _bus(label: String,effects: Array) -> String:
	var bus_name := "MingArmada%s%d" % [label,get_instance_id()]
	AudioServer.add_bus(); var index := AudioServer.bus_count-1; AudioServer.set_bus_name(index,bus_name)
	for effect in effects: AudioServer.add_bus_effect(index,effect)
	_buses.append(bus_name); return bus_name

func _player(label: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new(); player.name = label; player.max_polyphony = 1; add_child(player); return player

func apply_settings(settings: Dictionary) -> void:
	if _disposed: return
	var candidate := _settings.duplicate(true); candidate.merge(settings,true); _settings = Settings.normalise_settings(candidate)
	_build()
	if not _settings.sound or _settings.soundVolume <= 0: _release_voices()
	_apply_mix()

func set_listener(position: Vector3) -> void:
	if _disposed or not position.is_finite(): return
	_listener = position
	for voice in _voices: _voice_volume(voice)

static func distance_gain(position: Vector3,listener: Vector3) -> float:
	if not position.is_finite() or not listener.is_finite(): return 1
	return 1/(1+Vector2(position.x-listener.x,position.z-listener.z).length()/100)

func set_paused(paused: bool) -> void:
	if _disposed: return
	_paused = paused; _build(); _apply_mix()
	for voice in _voices: voice.player.stream_paused = paused

func apply_snapshot(naval: Dictionary,accepted_delta: float) -> void:
	if _disposed: return
	_build()
	_generation = str(naval.get("generation",_generation))
	_battle_id = str(naval.get("battleId",_battle_id))
	var identity := _generation+":"+_battle_id
	if not _identity.is_empty() and identity != _identity:
		_release_voices(); _seen.clear(); _event_floor = -INF; _clock = 0.0
	_identity = identity
	_music_mode = "combat" if _combat(naval) else "sailing"
	if not _paused and is_finite(accepted_delta) and accepted_delta > 0:
		var time: Variant = naval.get("time",_clock+accepted_delta)
		if Settings._finite(time) and float(time) >= 0: _clock = float(time)
		var weather: Variant = naval.get("wind",{})
		var speed: Variant = weather.get("speed",0) if weather is Dictionary else 0
		_wind_speed = clampf(float(speed),0,40) if Settings._finite(speed) else 0
	_apply_mix()

func _combat(naval: Dictionary) -> bool:
	if naval.get("combat") is bool: return naval.combat
	if naval.has("musicMode"): return naval.musicMode == "combat"
	if not naval.get("projectiles",[]).is_empty(): return true
	var ships: Array = naval.get("ships",[])
	for hostile in ships:
		if hostile.get("team") != "hostile" or hostile.get("hull",0) <= 0: continue
		for player in ships:
			if player.get("team") == "player" and player.get("hull",0) > 0:
				var a := _ship_position(hostile); var b := _ship_position(player)
				if Vector2(a.x-b.x,a.z-b.z).length() <= 600: return true
	return false

func _ship_position(ship: Dictionary) -> Vector3:
	return _position(ship.get("visual",ship).get("position",{}))

func _position(raw: Variant) -> Vector3:
	if raw is Vector3: return raw if raw.is_finite() else Vector3.ZERO
	if raw is Dictionary:
		var x: Variant = raw.get("x",0); var y: Variant = raw.get("y",0); var z: Variant = raw.get("z",0)
		if Settings._finite(x) and Settings._finite(y) and Settings._finite(z): return Vector3(x,y,z)
	return Vector3.ZERO

func apply_events(events: Array) -> void:
	if _disposed: return
	_build()
	for event in events:
		if not event is Dictionary: continue
		var type := String(event.get("type",""))
		if type not in Palette.TYPES and type not in ["mission","surrender"]: continue
		var id := String(event.get("id",event.get("eventId","")))
		if id.is_empty(): id = "payload:%s" % JSON.stringify(event).sha256_text()
		var stamp: Variant = event.get("time",_clock)
		var time := float(stamp) if Settings._finite(stamp) else _clock
		if _seen.has(id) or time <= _event_floor: _deduplicated += 1; continue
		_seen[id] = time
		if _seen.size() > MAX_EVENT_IDS:
			var oldest: Variant = _seen.keys()[0]; _event_floor = maxf(_event_floor,_seen[oldest]); _seen.erase(oldest)
		# Consume IDs even during mute/pause: there is no delayed event queue.
		if _paused or not _settings.sound or _settings.soundVolume <= 0: continue
		if _voices.size() >= MAX_VOICES: _release_voice(_voices[0])
		var player := AudioStreamPlayer.new(); player.stream = _palette.event_stream(type); player.max_polyphony = 1
		player.bus = _effects_bus; _voice_parent.add_child(player)
		var voice := {"player":player,"type":type,"position":_position(event.get("position",{})),"positioned":event.has("position"),"alive":true,"eventId":id}
		player.set_meta("position",voice.position); player.set_meta("eventId",id)
		_voices.append(voice); _voice_volume(voice)
		player.finished.connect(func(): _release_voice(voice))
		player.play()

func _voice_volume(voice: Dictionary) -> void:
	if not voice.alive: return
	var base := 0.35 if voice.type == "fire" else 0.12 if voice.type in ["hit","splash"] else 0.23
	voice.player.volume_linear = base*float(_settings.soundVolume)*(distance_gain(voice.position,_listener) if voice.positioned else 1)

func _apply_mix() -> void:
	if not _built or _disposed: return
	var strength := _wind_speed/40
	var swell := 0.68+0.32*sin(fposmod(_clock,TAU/0.73)*0.73)
	var gust := 0.78+0.22*sin(fposmod(_clock,TAU/1.37)*1.37+0.8)
	_sea_filter.cutoff_hz = 260+strength*700+swell*140
	_wind_filter.cutoff_hz = 900+strength*2800+gust*420
	var sound_on: bool = _settings.sound and _settings.soundVolume > 0
	_sea_gain = (0.025+strength*0.105)*swell*float(_settings.soundVolume) if sound_on and not _paused else 0
	_wind_gain = strength*0.13*gust*float(_settings.soundVolume) if sound_on and not _paused else 0
	_sea.volume_linear = _sea_gain; _wind.volume_linear = _wind_gain
	for ambient in [_sea,_wind]:
		if sound_on:
			if not ambient.playing: ambient.play()
			ambient.stream_paused = _paused
		else: ambient.stop()
	for voice in _voices: _voice_volume(voice)
	_apply_music()

func _apply_music() -> void:
	var path: String = MUSIC_PATHS[_music_mode]
	if not _music.stream or _music.stream.resource_path != path:
		_music.stream_paused = false; _music.stop(); _music_position = 0
		_music.stream = ResourceLoader.load(path) if ResourceLoader.exists(path) else null
		_music_reason = "" if _music.stream is AudioStream else "music-resource-unavailable"
	_music_gain = float(_settings.musicVolume)*0.35 if _settings.music else 0
	_music.volume_linear = _music_gain
	if _music.stream is AudioStreamMP3: _music.stream.loop = true
	elif _music.stream is AudioStreamOggVorbis: _music.stream.loop = true
	if not _settings.music or _music_gain <= 0:
		if _music.playing: _music_position = _music.get_playback_position(); _music.stream_paused = false; _music.stop()
	elif _music.stream:
		if not _music.playing: _music.play(_music_position)
		_music.stream_paused = _paused

func _release_voice(voice: Dictionary) -> void:
	if not voice.alive: return
	voice.alive = false
	var player: AudioStreamPlayer = voice.player
	if is_instance_valid(player):
		player.stream_paused = false; player.stop(); player.stream = null
		if player.get_parent(): player.get_parent().remove_child(player)
		player.queue_free()
	_voices.erase(voice)

func _release_voices() -> void:
	for voice in _voices.duplicate(): _release_voice(voice)

func diagnostics() -> Dictionary:
	var voices: Array = []
	for voice in _voices: voices.append({"eventId":voice.eventId,"type":voice.type,"position":voice.position,"gain":voice.player.volume_linear,"paused":voice.player.stream_paused,"frames":voice.player.stream.data.size()/2})
	return {"state":"disposed" if _disposed else "paused" if _paused else "disabled" if not _settings.sound else "running","activeVoices":_voices.size(),"maxVoices":MAX_VOICES,"clock":_clock,"seaGain":_sea_gain,"windGain":_wind_gain,"seaCutoff":_sea_filter.cutoff_hz if _sea_filter else 0,"windCutoff":_wind_filter.cutoff_hz if _wind_filter else 0,"musicMode":_music_mode,"musicGain":_music_gain,"musicReason":_music_reason,"deduplicated":_deduplicated,"rememberedEvents":_seen.size(),"voices":voices,"audibleVerified":false}

func dispose() -> void:
	if _disposed: return
	_disposed = true; _release_voices()
	if _built:
		_sea.stream_paused = false; _wind.stream_paused = false; _music.stream_paused = false
		_sea.stop(); _wind.stop(); _music.stop()
		_sea.stream = null; _wind.stream = null; _music.stream = null
		for bus_name in _buses:
			var index := AudioServer.get_bus_index(bus_name)
			if index >= 0: AudioServer.remove_bus(index)
	_buses.clear(); _palette.clear(); _seen.clear(); _sea_gain = 0; _wind_gain = 0; _music_gain = 0

func _exit_tree() -> void: dispose()
