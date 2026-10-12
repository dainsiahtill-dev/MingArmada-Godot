extends SceneTree
## CPU-only paired sampler measurement; no gameplay FPS or GPU conclusion.
const Field = preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Surf = preload("res://modules/scene_engine/terrain/natural_shore_surf.gd")
const Source = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
var frames := 48
func _initialize() -> void: _run.call_deferred()
func _measure(sampler: RefCounted,packets: Array,round_index: int) -> float:
	var start: int = Time.get_ticks_usec()
	for frame in frames:
		var time: float = 12.0+float(frame)/60.0+float(round_index)*0.0001
		for packet: Dictionary in packets:
			sampler.sample(int(packet.sourceIndex),time*float(packet.clockSpeed)+float(packet.clockOffset))
	return float(Time.get_ticks_usec()-start)/1000.0/frames
func _run() -> void:
	var field := Field.new(); field.configure({"resolution":129})
	var surf := Surf.new(); root.add_child(surf)
	if not surf.configure(field): quit(1); return
	var source: Dictionary=Source.read_json("res://assets/data/fidelity_island/shore-scene.json")
	var baseline: RefCounted=load("res://Temp/compiled-shore-sampler-v1-baseline.gd").new()
	var current: RefCounted=load("res://modules/scene_engine/fidelity_island/compiled_shore_sampler.gd").new()
	if not baseline.configure(source) or not current.configure(source): quit(1); return
	var packets: Array=surf.diagnostics().packets
	_measure(baseline,packets,0); _measure(current,packets,0)
	var rounds: Array=[]
	for i in 5:
		var old_ms: float; var new_ms: float
		if i%2==0: old_ms=_measure(baseline,packets,i+1); new_ms=_measure(current,packets,i+1)
		else: new_ms=_measure(current,packets,i+1); old_ms=_measure(baseline,packets,i+1)
		rounds.append({"v1_ms_per_frame":old_ms,"v2_ms_per_frame":new_ms,"ratio":new_ms/old_ms})
	print("SHORE_SAMPLER_AB ",JSON.stringify({"packet_count":packets.size(),"frames_per_round":frames,"rounds":rounds,"scope":"Same real seeded packets and every accepted time; scalar sampler CPU only; excludes ShaderMaterial submission/world/GPU; no FPS claim"}))
	surf.dispose(); surf.free(); quit(0)
