extends SceneTree
## Consumer checks for the game-only flare after GPU confirmed low coverage.
const Effect = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX flare: ",detail)
func _initialize() -> void: _run.call_deferred()
func _flash(effect: Node3D) -> Array:
	return effect.get_children().filter(func(node): return node is MeshInstance3D and node.visible and node.get_meta("display_role","") == "game_flash")
func _run() -> void:
	var camera := Camera3D.new(); root.add_child(camera); camera.position = Vector3(-35,23,48); camera.look_at(Vector3(0,6,3))
	var effect := Effect.new(); root.add_child(effect)
	var origin := Vector3(-9.55,2.04,1.38)
	var direction := Vector3(.06,0,1).normalized()
	check(effect.configure("fx_cannon_fire_01.nif",{"origin":origin,"direction":direction,"seed":1,"camera":camera,"render_profile":"game_cannon"}),"actual game-only flare configures at the untouched observed muzzle")
	var phase: Array[Color] = []
	var replay_geometry: Array = []
	var measured_phases: Array = []
	for age in [.033,.067,.10,.133]:
		check(effect.apply_snapshot(age,20.0+age),"accepted profile phase draws")
		var quads := _flash(effect)
		check(quads.size() == 2,"the two finite axial source-texture planes persist through the short flash")
		if quads.is_empty(): continue
		var material: ShaderMaterial = quads[0].material_override
		var tint: Color = material.get_shader_parameter("display_tint")
		phase.append(tint)
		check(float(material.get_shader_parameter("emission_gain")) >= 1.2,"game flare has enough configured emission after the visibility probe")
		var arrays: Array = quads[0].mesh.surface_get_arrays(0)
		var a: Vector3 = quads[0].to_global(arrays[Mesh.ARRAY_VERTEX][0])
		var b: Vector3 = quads[0].to_global(arrays[Mesh.ARRAY_VERTEX][3])
		measured_phases.append({"age":age,"start_width_m":a.distance_to(b),"opacity":tint.a,"emission_gain":material.get_shader_parameter("emission_gain"),"tint_rgb":[tint.r,tint.g,tint.b]})
		check(a.distance_to(b) >= .8,"actual start width maintains a visible axial footprint rather than the old tiny streak")
		check(((a+b)*.5).distance_to(origin+direction*.04)<.0001,"coverage improvement never lifts or moves the original muzzle")
		if is_equal_approx(age,.067): replay_geometry = [quads[0].transform,arrays,tint]
	if phase.size() == 4:
		check(phase[1].a >= .45,"middle early frame retains light instead of quadratic opacity collapse")
		check(phase[0].g > phase[1].g and phase[1].g > phase[2].g,"hot yellow transitions toward orange using the accepted clock")
		check(phase[0].a > phase[1].a and phase[1].a > phase[2].a and phase[2].a > phase[3].a and phase[3].a > 0,"flare opacity decays continuously to its finite endpoint")
	effect.apply_snapshot(.14,20.14)
	check(_flash(effect).is_empty(),"game flare fully expires at 0.14 seconds")
	check(effect.diagnostics().get("particles",0)>0,"native smoke remains after only the game flare expires")
	effect.apply_snapshot(.067,20.067)
	var rewind := _flash(effect)
	if not rewind.is_empty(): check([rewind[0].transform,rewind[0].mesh.surface_get_arrays(0),rewind[0].material_override.get_shader_parameter("display_tint")] == replay_geometry,"profile replay preserves both geometry and material phase")
	effect.dispose(); effect.free(); camera.free()
	print("FIDELITY_FX_FLASH_PHASES ",JSON.stringify(measured_phases))
	print("FIDELITY_FX_FLASH_PROFILE assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures else 0)
