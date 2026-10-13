extends SceneTree
## Exercise real Sea/CombatEffects event handoff without terrain generation.
## Pool's public signal represents a water contact between two drawn frames;
## this fixture does not claim to create a physical contact or a GPU frame.
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Wakes = preload("res://game/presentation/water/wake_trails.gd")
const Pool = preload("res://modules/physics_engine/impacts/impact_pool.gd")
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var sea := Sea.new(); root.add_child(sea)
	sea._water = func(_x,_z,_time): return 0.0
	sea._height = func(_x,_z): return -20.0
	sea.world = World.new(); sea._own(sea.world)
	sea.camera = Camera3D.new(); sea._own(sea.camera)
	sea.effects = Effects.new(); sea._own(sea.effects)
	sea.effects.set_water_sampler(sea._water)
	sea.wakes = Wakes.new(); sea._own(sea.wakes); sea.wakes.configure(sea._water)
	sea._disposed = false
	var native := {"battleId":"water-a","time":10.0,"ships":[],"projectiles":[],"wind":{}}
	sea.apply_snapshot(native,[],0.0)
	var pool := Pool.new(); sea.add_child(pool)
	pool.visual_event.connect(sea._on_crew_water_entry)
	var event := {"type":"crew-water-entry","event_id":"hit-a","body_id":"body-a","position":Vector3(12,0,-7),"time":10.1}
	var id := "crew-entry:hit-a:body-a"
	pool.visual_event.emit(event)
	check(not sea.effects._seen.has(id),"future crew water entry remains pending instead of being acknowledged and discarded")
	check(sea.effects.diagnostics().splashes == 0,"crew water entry does not render before the effect clock reaches its original birth time")
	pool.visual_event.emit(event)
	native.time = 10.15; sea.apply_snapshot(native,[],0.15)
	check(sea.effects.diagnostics().splashes == 1,"next actual Sea snapshot flushes exactly one pending splash")
	if sea.effects._water_splashes._splashes.size() == 1:
		var splash: Dictionary = sea.effects._water_splashes._splashes[0]
		check(absf(splash.time-10.1)<1e-8 and splash.birth_origin==Vector3(12,0,-7),"deferred splash retains original contact position and birth time")
	else: check(false,"actual splash geometry exists for birth data inspection")
	sea.apply_snapshot(native,[],0.0); pool.visual_event.emit(event)
	sea.apply_snapshot(native,[],0.0)
	check(sea.effects.diagnostics().splashes == 1,"same-time render and duplicate contact do not replay a splash")
	pool.visual_event.emit({"type":"crew-water-entry","event_id":"old","body_id":"old","position":Vector3.ZERO,"time":11.0})
	native.battleId="water-b"; native.time=0.0; sea.apply_snapshot(native,[],0.0)
	native.time=11.0; sea.apply_snapshot(native,[],0.0)
	check(not sea.effects._seen.has("crew-entry:old:old") and sea.effects.diagnostics().splashes==0,"battle epoch reset discards contacts from the old actor fleet")
	pool.visual_event.emit({"type":"crew-water-entry","event_id":"rewound","body_id":"r","position":Vector3.ZERO,"time":11.1})
	native.time=0.0; sea.apply_snapshot(native,[],0.0)
	native.time=11.1; sea.apply_snapshot(native,[],0.0)
	check(not sea.effects._seen.has("crew-entry:rewound:r") and sea.effects.diagnostics().splashes==0,"rewind clears future crew contacts instead of resurrecting old water entry")
	sea.dispose(); sea.free()
	print("DEFERRED_CREW_WATER_ENTRY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
