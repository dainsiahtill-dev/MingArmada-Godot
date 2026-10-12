extends SceneTree

const Terrain = preload("res://modules/scene_engine/fidelity_island/terrain.gdshader")
var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(condition: bool, reason: String) -> void:
	assertions+=1
	if not condition: failures+=1; printerr("FAIL: ",reason)

func _run() -> void:
	var Water: Script=load("res://modules/scene_engine/fidelity_island/source_water.gd")
	var probe: Node=Water.new()
	var available:=probe.has_method("terrain_composite"); probe.free()
	check(available, "source renderer exposes original UnderDark/additive composition")
	if not available:
		_finish(); return
	# Hand-evaluated source renderer draw equation. Background never receives
	# terrain light; half coverage must preserve half the prior NR water draw.
	var color: Vector3=Water.terrain_composite(Vector3(.2,.3,.4),.5,Vector3(.1,.2,.3),Vector3(.6,.8,1),Vector3(.458,.69,.85),.25,Vector3(.4,.6,.8))
	check(color.is_equal_approx(Vector3(.34725,.59625,.88125)), "exact source fogged UnderDark alpha then additive texture equation")
	color=Water.terrain_composite(Vector3.ZERO,0.0,Vector3.ZERO,Vector3(.1,.2,.3),Vector3(.458,.69,.85),.25,Vector3(.4,.6,.8))
	check(color.is_equal_approx(Vector3(.4,.6,.8)), "zero packed coverage preserves NR background independent of local lighting")
	color=Water.terrain_composite(Vector3(.2,.3,.4),1.0,Vector3(.1,.2,.3),Vector3(.6,.8,1),Vector3(.458,.69,.85),.25,Vector3(.9,.1,.2))
	check(color.is_equal_approx(Vector3(.2495,.4725,.7375)), "full packed coverage removes prior water only after UnderDark blend")
	var camera:=Camera3D.new(); root.add_child(camera)
	var water: Node3D=Water.new(); root.add_child(water)
	check(water.configure(camera,Vector3(269925.21875,202766.25,0)), "source renderer creates actual original pool")
	var terrain:=ShaderMaterial.new(); terrain.shader=Terrain
	check(terrain.get_shader_parameter("source_observer_composition") != true, "formal terrain receives no observer opt-in")
	check(water.bind_terrain(terrain,Rect2(Vector2(-3961.2422,-4627.015),Vector2(7922.4844,9254.03))), "source observer binds real terrain footprint and NR material")
	check(terrain.get_shader_parameter("source_observer_composition") == true, "only bound source observer enables recovered multi-pass equation")
	check(terrain.get_shader_parameter("source_water_texture") != null, "terrain backdrop samples same real authored NR DDS")
	check(water.apply_snapshot(12.35,{"ambient":[.48882356286,.5750980377,.7633333802],"fogColor":[.4588235617,.6941176653,.8509804606]}), "authoritative observer frame updates water and backdrop together")
	check(terrain.get_shader_parameter("source_time") == 12.35, "terrain background clock cannot lag ocean")
	check(terrain.get_shader_parameter("source_water_ambient") == Vector3(.48882356286,.5750980377,.7633333802), "terrain receives NR ambient independent of vertex surface lighting")
	check(water.diagnostics().terrainComposition, "actual depth footprint mask prevents water repainting partial terrain coverage")
	water.update_source_target(Vector2(45000,0))
	check(terrain.get_shader_parameter("source_water_uv_offset") == water.get_child(0).material_override.get_shader_parameter("source_water_uv_offset"), "tile resnap keeps terrain backdrop and original pool UV mapping synchronized")
	water.dispose()
	check(terrain.get_shader_parameter("source_observer_composition") == false, "observer teardown releases private opt-in rather than leaving stale source state")
	water.free(); camera.free()
	_finish()

func _finish() -> void:
	print("FIDELITY_SOURCE_COMPOSITION assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures>0 else 0)
