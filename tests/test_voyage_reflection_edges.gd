extends SceneTree
const Shore = preload("res://game/research/demos/shore_surf_experiment.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,why: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",why)
func run() -> void:
	var source := FileAccess.get_file_as_string("res://modules/scene_engine/ocean/water_environment_optics.gdshaderinc")
	var regex := RegEx.new();regex.compile("(?s)float reference_reflection_border\\(float edge, float width\\)\\s*\\{([^}]+)\\}")
	var found := regex.search(source)
	check(found!=null,"finite mirror coverage has continuous edge confidence")
	if found!=null:
		var script := GDScript.new()
		script.source_code="extends RefCounted\nfunc sample(edge: float,width: float) -> float:\n\t"+found.get_string(1).strip_edges().replace(";","").replace("max(","maxf(")+"\n"
		check(script.reload()==OK,"production mirror coverage formula executes")
		if script.can_instantiate():
			var model: RefCounted=script.new()
			for fixture: Array in [[-0.02,0.08,0.0],[0.0,0.08,0.0],[0.04,0.08,0.5],[0.08,0.08,1.0],[0.5,0.08,1.0],[0.04,0.0,1.0]]:
				check(absf(model.sample(fixture[0],fixture[1])-fixture[2])<0.00001,"mirror/sky confidence "+str(fixture))
			check(absf(model.sample(0.00001,0.08)-model.sample(-0.00001,0.08))<0.000001,"crossing texture border cannot create a finite color jump")
	var viewport := SubViewport.new();viewport.size=Vector2i(1260,449);viewport.own_world_3d=true;root.add_child(viewport)
	var demo := Shore.new();viewport.add_child(demo);check(demo.configure({"paused":true}).ok,"existing shore fixture builds")
	var material: ShaderMaterial=demo._ocean.material_override
	var mirror: SubViewport=demo._ocean.get_reflection_viewport()
	var before: Dictionary=demo.inspection_snapshot()
	var declared := false
	for uniform: Dictionary in material.shader.get_shader_uniform_list():
		if uniform.name=="reflection_edge_feather":declared=true
	check(declared,"coverage factor is consumed by the actual production material interface")
	check(demo.set_parameter("reflection_edge_feather",0.08).ok,"same-time mirror border control accepted")
	check(is_equal_approx(float(material.get_shader_parameter("reflection_edge_feather")),0.08),"candidate is bound on production water")
	var after: Dictionary=demo.inspection_snapshot()
	check(before.time==after.time and before.telemetry.source==after.telemetry.source and before.telemetry.terrain_fingerprint==after.telemetry.terrain_fingerprint,"mirror control preserves source surf, terrain and accepted time")
	check(demo._ocean.get_reflection_viewport()==mirror and demo._ocean.get_surface_optics_diagnostics().reflection_enabled,"actual shared-world mirror remains active and owned")
	for value: Variant in [-0.1,0.16,NAN,"smooth"]:check(not demo.set_parameter("reflection_edge_feather",value).ok,"invalid mirror factor rejected "+str(value))
	demo.dispose();viewport.free()
	print("VOYAGE_REFLECTION_EDGES_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
