extends SceneTree
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Catalog=preload("res://game/domain/legacy/catalog.gd")
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: run.call_deferred()
func run() -> void:
	for path in ["res://game/scenes/legacy/legacy_scene.gd","res://game/scenes/naval_practice/naval_practice.gd"]:
		var scene=load(path).new(); root.add_child(scene); await process_frame; scene.set_physics_process(false)
		for point in [Vector2.ZERO,Vector2(140,100),Vector2(60,-120),Vector2(0,105),Vector2(0,-105)]:
			check(is_equal_approx(scene.heights.sample_height(point.x,point.y),-24.0),"actual "+path+" source spawn has deep water: "+str(point))
		scene.queue_free(); await process_frame; await process_frame; await create_timer(.08).timeout
	print("LEGACY_GEOGRAPHY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
