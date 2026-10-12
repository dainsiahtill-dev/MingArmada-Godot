extends SceneTree
## Actual native menu/router, composed scenes and viewport PNGs. No save writes.
const Main = preload("res://game/scenes/main/main_scene.gd")
const Router = preload("res://game/runtime/game_router.gd")
const Settings = preload("res://game/persistence/user_settings.gd")
var main: Node
var output := "res://docs/migration/evidence/fidelity-island/native-v1"
var captures: Array=[]
var failures := 0
var settings: RefCounted
var output_owned := false
var capture_render_hook: Callable
class MemorySlot extends RefCounted:
	var raw := ""
	var writes := 0
	func read_checkpoint() -> Dictionary: return {"ok":true,"json":raw} if not raw.is_empty() else {"ok":false,"reason":"save-not-found"}
	func write_checkpoint(_raw: String) -> Dictionary: writes+=1; return {"ok":false,"reason":"inspection-write-forbidden"}
func check(ok: bool, detail: String) -> bool:
	if not ok: failures+=1; printerr("FAIL: ",detail)
	return ok
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="): output=arg.trim_prefix("--output=")
	if not check(DisplayServer.get_name()!="headless","native GPU required"): _finish(); return
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(output)):
		check(false,"fresh output required; never overwrite earlier screenshots"); _finish(); return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	output_owned=true
	root.size=Vector2i(1600,900)
	var slot:=MemorySlot.new(); var legacy:=MemorySlot.new()
	settings=Settings.new("user://verification/fidelity-island-no-write-%d.json" % OS.get_process_id())
	main=Main.new(); main.router=Router.new({"mingqi_storage":slot,"legacy_storage":legacy,"settings_storage":settings}); root.add_child(main)
	await process_frame
	var button: Button=main.menu.find_child("fidelity-source",true,false)
	if not check(button!=null and not button.disabled,"normal public menu island entry is available"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("fidelity-island"): _finish(); return
	var scene: Control=main.current_scene; scene.paused=true; scene.seconds=12.0
	await _capture("island-noon-wide",scene)
	var anchors: Array=scene.trees.diagnostics().anchors
	var point:=Vector3(1700,40,3000)
	for anchor: Dictionary in anchors:
		if anchor.kind=="canopy": point=anchor.position; break
	scene.camera.position=point+Vector3(750,1050,1000); scene.camera.look_at(point+Vector3.UP*35,Vector3.UP)
	await _capture("island-forest-close",scene)
	scene.camera.position=Vector3(500,2600,6500); scene.camera.look_at(Vector3(900,0,2400),Vector3.UP)
	await _capture("island-shore-time-12",scene)
	scene.seconds=23.0; await _capture("island-shore-time-23",scene)
	scene._update_camera(); scene.set_daylight(18.0); await _capture("island-evening-wide",scene)
	scene.set_daylight(0.0); await _capture("island-night-wide",scene)
	main._return_from_scene(scene); await process_frame
	var first_path:="res://docs/migration/evidence/opening-story/fleet-stop-native-record-and-aftermath/journey-first.json"
	var first: Variant=JSON.parse_string(FileAccess.get_file_as_string(first_path))
	if not check(first is Dictionary and first.get("failures",1)==0 and not String(first.get("confirmedCheckpointJson","")).is_empty(),"genuine Kinmen voyage checkpoint available for normal Continue"): _finish(); return
	slot.raw=first.confirmedCheckpointJson
	main._refresh_menu()
	button=main.menu.find_child("mingqi-continue",true,false)
	if not check(button!=null and not button.disabled,"ordinary native Continue uses the exact existing checkpoint"): _finish(); return
	button.pressed.emit()
	if not await _await_scene("mingqi"): _finish(); return
	var game: Node=main.current_scene
	game.runtime.set_pause("player",true)
	game.process_mode=Node.PROCESS_MODE_DISABLED
	game.interface.close_menu()
	game.interface.close_panel()
	game.sea.apply_settings({"cameraFollow":false})
	game.sea.camera.position=Vector3(510,125,0); game.sea.camera.look_at(Vector3(455,10,180),Vector3.UP)
	await _capture("formal-kinmen-harbor",game)
	game.sea.camera.position=Vector3(600,250,-160); game.sea.camera.look_at(Vector3(420,12,160),Vector3.UP)
	await _capture("formal-kinmen-island",game)
	check(slot.writes==0 and legacy.writes==0,"all native entry and Continue inspection preserved user save slots")
	_finish()
func _await_scene(mode: String) -> bool:
	for frame in 300:
		await process_frame
		if is_instance_valid(main.current_scene):
			return check(main.current_scene.startup_receipt.get("ok",false),"actual "+mode+" scene initialized")
	return check(false,"normal native scene entry timed out: "+mode)
func _capture(label: String, scene: Node) -> void:
	for frame in 5: await process_frame
	if scene.has_method("_render"): scene._render()
	else: scene.sea.world.get_ocean().update_projection()
	if capture_render_hook.is_valid(): capture_render_hook.call()
	await RenderingServer.frame_post_draw
	var image: Image=root.get_texture().get_image()
	var path:=output+"/"+label+".png"
	if not check(image!=null and not image.is_empty() and image.save_png(path)==OK,"actual viewport PNG "+label): return
	var snapshot: Dictionary=scene.inspection_snapshot() if scene.has_method("inspection_snapshot") else scene.runtime.snapshot()
	var world_audit: Dictionary={} if scene.has_method("inspection_snapshot") else scene.sea.world.fidelity_diagnostics()
	var metadata:={"label":label,"imageSha256":FileAccess.get_sha256(path),"gpu":RenderingServer.get_video_adapter_name(),"renderingMethod":RenderingServer.get_current_rendering_method(),"viewport":[image.get_width(),image.get_height()],"snapshot":snapshot,"world":world_audit,"sourceManifestSha256":FileAccess.get_sha256("res://assets/data/fidelity_island/manifest.json"),"scope":"Actual current Godot menu/router scene PNG; read-only source checkpoint Continue; no original-game-frame or performance claim."}
	var camera: Camera3D=scene.camera if scene.has_method("inspection_snapshot") else scene.sea.camera
	metadata.cameraFov=camera.fov
	metadata.productionShaderHashes={}
	var ship_manifest:="res://assets/data/fidelity_naval/ships-manifest.json"
	if FileAccess.file_exists(ship_manifest):
		metadata.shipModelManifestSha256=FileAccess.get_sha256(ship_manifest)
		metadata.shipPresentationHashes={}
		for source_path: String in ["res://modules/scene_engine/assets/ship_model_provider.gd","res://game/presentation/ships/ship_view.gd","res://game/presentation/ships/ship_damage.gd","res://game/presentation/ships/ship_damage.gdshader","res://game/presentation/ships/ship_damage_alpha.gdshader","res://game/presentation/ships/ship_damage_surface.gdshaderinc","res://game/presentation/combat/combat_effects.gd"]:
			metadata.shipPresentationHashes[source_path]=FileAccess.get_sha256(source_path)
	for shader_path: String in ["res://modules/scene_engine/ocean/reference_game_water.gdshader","res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc","res://modules/scene_engine/terrain/natural_shore_surf.gdshader"]:
		metadata.productionShaderHashes[shader_path]=FileAccess.get_sha256(shader_path)
	var macro_optics_path:="res://modules/scene_engine/ocean/macro_wave_optics.gdshaderinc"
	if FileAccess.file_exists(macro_optics_path): metadata.productionShaderHashes[macro_optics_path]=FileAccess.get_sha256(macro_optics_path)
	var file:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE)
	if not check(file!=null,"PNG metadata file opens"): return
	file.store_string(JSON.stringify(metadata,"\t")); file.close(); captures.append(metadata)
func _finish() -> void:
	if output_owned:
		var file:=FileAccess.open(output+"/capture-result.json",FileAccess.WRITE)
		if file!=null: file.store_string(JSON.stringify({"captures":captures,"failures":failures,"gpu":RenderingServer.get_video_adapter_name()},"\t")); file.close()
	if is_instance_valid(main): main.free()
	print("FIDELITY_ISLAND_NATIVE_CAPTURE captures=%d failures=%d" % [captures.size(),failures])
	quit(1 if failures else 0)
