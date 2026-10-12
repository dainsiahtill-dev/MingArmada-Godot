extends SceneTree
const Router = preload("res://game/runtime/game_router.gd")
const WaveDescriptor = preload("res://modules/contracts/wave_descriptor.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var router := Router.new()
	var prepared: Dictionary=router.prepare_entry({"type":"fidelity-island","generation":router.generation,"nonce":1,"name":"船长"})
	check(prepared.get("ok",false) and prepared.get("persist_name",true)==false,"normal public island entry does not write a captain setting")
	var created: Dictionary=router.create_scene(prepared)
	check(created.get("ok",false),"normal router creates the actual new island scene")
	if not created.get("ok",false): _finish(); return
	var scene: Control=created.scene; root.add_child(scene)
	await process_frame
	check(scene.startup_receipt.get("ok",false),"complete native island initializes, rather than displaying an empty demo")
	if not scene.startup_receipt.get("ok",false): scene.free(); _finish(); return
	check(scene.startup_receipt.terrainVertices==17182 and scene.startup_receipt.terrainTriangles==11462,"all six source cells and their real geometry are present")
	var before: Dictionary=scene.inspection_snapshot()
	check(before.trees.get("mode")=="exact","native source viewer keeps original tree transforms")
	check(before.shore.get("meshes",before.shore.get("meshCount",0))==8,"original eight separate surf meshes are instantiated")
	check(scene.get("reference_ocean") != null,"source preview actually uses the completed demo water material")
	check(absf(scene.camera.fov-360.0/7.0)<0.0001,"default preview uses the demo's viewing lens")
	check(before.shore.get("followSurface",true)==false,"native source shoreline stays fixed with the matching flat source sea")
	var water_material: ShaderMaterial=scene.ocean.material_override
	check(water_material.get_shader_parameter("normal_texture")!=null,"source viewer retains the actual game's existing moving normal texture")
	check(water_material.get_shader_parameter("wave_count")==WaveDescriptor.original_descriptors().size(),"island integration preserves the game's original five waves")
	check(scene.set_daylight(0.0) and scene.set_daylight(18.0) and scene.set_daylight(12.0),"original night/evening/noon inputs work on the actual composed scene")
	check(not scene.set_daylight(NAN) and not scene.set_daylight(25.0),"invalid authoring time cannot poison native light")
	scene.paused=true; var seconds: float=scene.seconds
	scene._process(0.05)
	check(scene.seconds==seconds,"paused island does not bill a separate wave clock")
	scene.dispose(); scene.dispose()
	check(not preload("res://modules/scene_engine/fidelity_island/terrain_material.gd").load_source().is_empty(),"disposing a viewer never clears another owner's immutable source cache")
	check(scene.world==null and scene.camera==null,"native scene cleanup is idempotent and releases its world")
	scene.free(); _finish()
func _finish() -> void:
	print("FIDELITY_ISLAND_SCENE_VERIFY assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures else 0)
