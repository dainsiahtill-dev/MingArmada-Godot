extends SceneTree
## Each script starts one actual entrance, bounding its work independently.
const Practice=preload("res://game/scenes/naval_practice/naval_practice.gd")
const Trial=preload("res://game/scenes/sailing_trial/sailing_trial.gd")
const AudioCleanup=preload("res://tests/fixtures/audio_cleanup.gd")
var assertions:=0
var failures:=0
func check(ok: bool,detail: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",detail)
func _wet(height: RefCounted,pose: Dictionary,dimensions: Dictionary,label: String) -> void:
	for forward in [-0.5,0.0,0.5]:
		for side in [-0.5,0.0,0.5]:
			var x: float=pose.position.x+cos(pose.heading)*dimensions.length*forward-sin(pose.heading)*dimensions.width*side
			var z: float=pose.position.z+sin(pose.heading)*dimensions.length*forward+cos(pose.heading)*dimensions.width*side
			check(height.sample_height(x,z)<-dimensions.draft-0.3,label+" retains wet authored full-hull spawn")
func run_practice(mode: String) -> void:
	root.size=Vector2i(1600,900)
	var scene:=Practice.new(); scene.startup_options={"mode":mode,"staged":true}
	root.add_child(scene); await process_frame; scene.set_physics_process(false)
	check(scene.startup_receipt.get("ok",false),mode+" actual ordinary scene bootstraps")
	if scene.startup_receipt.get("ok",false):
		check(scene.heights.natural_islands().size()==6 and scene.heights.reference_profiles().is_empty(),mode+" preserves six-port practice geography with shared natural provider")
		var world: Node3D=scene.sea.world
		var diagnostics: Dictionary=world.fidelity_diagnostics()
		check(diagnostics.geometryMode=="static_natural" and world.get_chunk_count()==0,mode+" owns finite same-grid natural rendering")
		check(diagnostics.geometry.get("shoreSurf",[]).size()==6,mode+" binds source advancing surf to every real natural shore")
		check(int(world.get_ocean().material_override.get_shader_parameter("wave_count"))==5,mode+" retains original accepted ocean waves")
		var native: Dictionary=scene.runtime.snapshot().naval
		check(native.ships.size()==(2 if mode=="duel" else 3),mode+" preserves authored boat setup")
		for ship: Dictionary in native.ships: _wet(scene.heights,ship.visual,ship.dimensions,mode+" "+ship.id)
	var playbacks: Array[WeakRef]=AudioCleanup.stop_players(scene)
	scene.free(); await process_frame; await process_frame
	check(await AudioCleanup.wait_for_release(self,playbacks),mode+" scene releases actual stopped audio playbacks before exit")
func run_trial() -> void:
	root.size=Vector2i(1600,900)
	var trial:=Trial.new(); root.add_child(trial); await process_frame; trial.set_physics_process(false)
	check(trial.runtime._configured and trial.world!=null,"actual ordinary sailing trial bootstraps")
	if trial.world!=null:
		check(trial.heights.natural_islands().size()==3 and trial.heights.reference_profiles().is_empty(),"sailing trial shares formal three-port accepted natural authority")
		check(trial.world.fidelity_diagnostics().geometryMode=="static_natural" and trial.world.get_static_island_meshes().size()==4,"sailing trial shares three natural islands plus rendered supply shoal")
		check(trial.world.fidelity_diagnostics().geometry.get("shoreSurf",[]).size()==3,"sailing trial shares all three advancing natural shoreline loops")
		var packet: Dictionary=trial.runtime.snapshot().ship
		_wet(trial.heights,packet,packet.dimensions,"sailing trial")
	trial.free(); await process_frame; await process_frame
