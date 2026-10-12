extends SceneTree
const Router=preload("res://game/runtime/game_router.gd")
var assertions:=0
var failures:=0
func check(ok:bool,description:String)->void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",description)
func _initialize()->void: _run.call_deferred()
func _run()->void:
	var router:=Router.new()
	var request:Dictionary=router.prepare_entry({"type":"fidelity-island","generation":router.generation,"nonce":1})
	var result:Dictionary=router.create_scene(request)
	check(result.ok,"normal menu router creates combined preview")
	if not result.ok: _finish(); return
	var scene:Control=result.scene; root.add_child(scene); await process_frame
	check(scene.startup_receipt.ok,"shared natural terrain and original sea initialize together")
	if scene.startup_receipt.ok:
		check(scene.world.get_chunk_count()==0 and scene.world.get_distant_chunks().is_empty(),"new native source grid replaces procedural near/far generation")
		check(scene.world.get_static_island_meshes().size()==4,"three accepted natural islands and one physical shoal have finite static mesh owners")
		check(scene.world.fidelity_diagnostics().geometryMode=="static_natural" and scene.world.fidelity_diagnostics().geometry.shoreSurf.size()==3,"sole public preview shares formal game terrain and source surf")
		check(scene.world.get_ocean().material_override.get_shader_parameter("coastal_breaker_strength")==0.36,"curved advancing fronts remain visible in the shared game world")
		check(scene.world.get_ocean().material_override.get_shader_parameter("shoreline_residue_strength")==0.38,"contact residue stays quieter than the approaching wave heads")
		check(scene.world.get_ocean().material_override.get_shader_parameter("wave_count")==5,"old five-wave sea survives combination")
		var nodes:Array=scene.world.get_static_island_meshes()
		var ids:Array=nodes.map(func(n):return n.get_instance_id())
		scene.focus=Vector3(1000,0,1000); scene.seconds=13.0; scene._render()
		var ship: Node3D=scene.sea.ships.player
		var attitude:=ship.rotation
		scene.seconds=18.0; scene._render()
		check(ship.rotation!=attitude,"shared preview ship rocks from the same sampled water clock")
		check(scene.world.get_static_island_meshes().map(func(n):return n.get_instance_id())==ids,"moving camera reuses source geometry")
		scene.paused=true; var phase:float=scene.seconds; scene._process(0.05)
		check(scene.seconds==phase,"paused preview preserves same accepted sea clock")
	scene.dispose(); scene.dispose(); check(scene.world==null and scene.sea==null,"combined teardown is idempotent")
	scene.free()
	_finish()
func _finish()->void:
	print("COMBINED_ISLAND_SCENE_TESTS assertions=%d failures=%d"%[assertions,failures]); quit(1 if failures else 0)
