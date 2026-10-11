extends RefCounted
## Native PCM equivalent of frozen SailingAudio.makeEventBuffer.
const SAMPLE_RATE := 22050
const TYPES := ["fire","hit","splash","dock","victory","defeat","quest","order","reload"]
var _cache: Dictionary = {}

func event_stream(type: String) -> AudioStreamWAV:
	if type == "mission": type = "quest"
	if type == "surrender": type = "defeat"
	if type not in TYPES: return null
	if _cache.has(type): return _cache[type]
	var samples: PackedFloat32Array
	if type in ["fire","hit","splash"]:
		var duration := 0.65 if type == "fire" else 0.25
		var count := ceili(SAMPLE_RATE*duration)
		samples.resize(count)
		var rng := RandomNumberGenerator.new(); rng.seed = {"fire":1661,"hit":1650,"splash":2026}[type]
		for i in count: samples[i] = rng.randf_range(-1,1)*exp(-float(i)/count*6)
		# WebAudio routes each noise voice through its own lowpass.
		samples = _lowpass(samples,{"fire":480.0,"hit":1100.0,"splash":1700.0}[type])
	else:
		var notes: Array = {"order":[440,554],"reload":[330,440,330],"dock":[392,523],"victory":[392,523,659,784],"defeat":[392,294,196,147],"quest":[523,659,784]}[type]
		var spacing := 0.18 if type == "dock" else 0.14
		var count := ceili(((notes.size()-1)*spacing+0.9)*SAMPLE_RATE); samples.resize(count)
		for i in count:
			var time := float(i)/SAMPLE_RATE; var sample := 0.0
			for note in notes.size():
				var age := time-note*spacing
				if age < 0: continue
				var angle := TAU*float(notes[note])*age
				sample += minf(1,age/0.006)*(0.56*sin(angle)*exp(-age*5)+0.23*sin(angle*2.76)*exp(-age*10)+0.11*sin(angle*4.07)*exp(-age*15))
			samples[i] = clampf(sample,-1,1)
		samples = _lowpass(samples,5200)
	var stream := _pcm(samples,false); _cache[type] = stream; return stream

func ambient_stream() -> AudioStreamWAV:
	if _cache.has("ambient"): return _cache.ambient
	var samples := PackedFloat32Array(); samples.resize(SAMPLE_RATE*2)
	var rng := RandomNumberGenerator.new(); rng.seed = 16501661
	for i in samples.size(): samples[i] = rng.randf_range(-1,1)
	var stream := _pcm(samples,true); _cache.ambient = stream; return stream

func _pcm(samples: PackedFloat32Array,looped: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray(); bytes.resize(samples.size()*2)
	for i in samples.size(): bytes.encode_s16(i*2,roundi(clampf(samples[i],-1,1)*32767))
	var stream := AudioStreamWAV.new(); stream.format = AudioStreamWAV.FORMAT_16_BITS; stream.mix_rate = SAMPLE_RATE; stream.stereo = false; stream.data = bytes
	if looped:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD; stream.loop_begin = 0; stream.loop_end = samples.size()
	return stream

func _lowpass(samples: PackedFloat32Array,frequency: float) -> PackedFloat32Array:
	# Offline RBJ biquad avoids an audio bus per event and keeps the 16 voice cap.
	var angle := TAU*frequency/SAMPLE_RATE; var cosine := cos(angle); var alpha := sin(angle)/2
	var denominator := 1+alpha
	var b0 := (1-cosine)*0.5/denominator; var b1 := (1-cosine)/denominator; var b2 := b0
	var a1 := -2*cosine/denominator; var a2 := (1-alpha)/denominator
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	var result := PackedFloat32Array(); result.resize(samples.size())
	for i in samples.size():
		var x0 := float(samples[i]); var y0 := b0*x0+b1*x1+b2*x2-a1*y1-a2*y2
		result[i] = y0; x2 = x1; x1 = x0; y2 = y1; y1 = y0
	return result

func clear() -> void: _cache.clear()
