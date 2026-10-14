extends SceneTree
## Execute the production scalar shader body, not a copied reference algorithm.
const SOURCE := "res://modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc"
const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL shore edge coverage: ", message)

func production_function(name: String) -> RefCounted:
	var expression := RegEx.new()
	expression.compile("(?s)float\\s+" + name + "\\s*\\(([^)]*)\\)\\s*\\{([^}]+)\\}")
	var found := expression.search(FileAccess.get_file_as_string(SOURCE))
	check(found != null, "production scalar exists: " + name)
	if found == null:
		return null
	var parameters: Array[String] = []
	for parameter: String in found.get_string(1).split(","):
		parameters.append(parameter.strip_edges().trim_prefix("float ") + ": float")
	var body := ""
	for line: String in found.get_string(2).split("\n"):
		line = line.strip_edges()
		if line.is_empty() or line.begins_with("//"):
			continue
		line = line.trim_suffix(";").replace("max(", "maxf(").replace("min(", "minf(").replace("mix(", "lerpf(").replace("clamp(", "clampf(")
		if line.begins_with("if(") or line.begins_with("if ("):
			var end := line.find(")")
			body += "\tif " + line.substr(line.find("(") + 1, end - line.find("(") - 1) + ":\n\t\t" + line.substr(end + 1).strip_edges() + "\n"
		else:
			if line.begins_with("float "):
				line = "var " + line.trim_prefix("float ")
			body += "\t" + line + "\n"
	var program := GDScript.new()
	program.source_code = "extends RefCounted\nfunc evaluate(" + ", ".join(parameters) + ") -> float:\n" + body
	check(program.reload() == OK, "actual production scalar body executes as GDScript")
	return program.new() if program.can_instantiate() else null

func run() -> void:
	check(FileAccess.file_exists(SOURCE), "shore coverage is an independent production scalar")
	if failures:
		finish()
		return
	var model := production_function("reference_shore_edge_coverage")
	if model == null:
		finish()
		return
	# Literal expected values come from cubic smoothstep at 0,1/4,1/2,3/4,1.
	var fixtures: Array = [
		[0.0, 0.0, 0.0, 0.0, 1.0], [-2.0, -3.0, -4.0, 0.0, 1.0],
		[0.0, 0.0, 0.0, -0.1, 1.0], [0.0, 1.0, 1.0, 0.35, 0.0],
		[-0.01, 1.0, 1.0, 0.35, 0.0], [1.0, 0.0, 1.0, 0.35, 0.0],
		[1.0, -0.01, 1.0, 0.35, 0.0], [0.0875, 1.0, 1.0, 0.35, 0.15625],
		[0.175, 1.0, 1.0, 0.35, 0.5], [0.2625, 1.0, 1.0, 0.35, 0.84375],
		[0.35, 1.0, 1.0, 0.35, 1.0], [1.0, 0.175, 1.0, 0.35, 0.5],
		[0.175, 1.0, 0.0875, 0.35, 0.15625], [0.35, 1.0, 0.175, 0.35, 0.5],
		[0.4375, 1.0, 0.0, 0.35, 0.15625], [0.525, 1.0, 0.0, 0.35, 0.5],
		[0.6125, 1.0, 0.0, 0.35, 0.84375], [0.7, 1.0, 0.0, 0.35, 1.0],
		[20.0, 20.0, 0.0, 0.35, 1.0], [20.0, 20.0, 0.1, 0.35, 1.0]
	]
	for fixture: Array in fixtures:
		var value: float = model.evaluate(fixture[0], fixture[1], fixture[2], fixture[3])
		check(is_finite(value) and absf(value - fixture[4]) <= 0.000001, "coverage hand-derived fixture " + str(fixture))
	for boundary: float in [0.0, 0.35, 0.7]:
		var left: float = model.evaluate(boundary - 0.00001, 20.0, 0.0, 0.35)
		var right: float = model.evaluate(boundary + 0.00001, 20.0, 0.0, 0.35)
		check(absf(left - right) <= 0.001, "screen-depth correction continuous at " + str(boundary))
	var previous := -1.0
	for index in 65:
		var value: float = model.evaluate(float(index) / 64.0, 20.0, 20.0, 0.35)
		check(value >= previous and value >= 0.0 and value <= 1.0, "terrain crossing stays monotone and bounded")
		previous = value
	var weight_model := production_function("reference_shore_edge_water_weight")
	if weight_model == null:
		finish()
		return
	# Literal weights are independently derived from b*c+(1-b)*c².
	for fixture: Array in [[0.0, 0.0, 0.0], [0.0, 0.55, 0.0], [0.0, 1.0, 0.0], [1.0, 0.0, 1.0], [1.0, 0.55, 1.0], [1.0, 1.0, 1.0], [0.5, 0.0, 0.25], [0.5, 0.55, 0.3875], [0.5, 1.0, 0.5], [0.25, 0.55, 0.165625], [0.75, 0.55, 0.665625], [0.5, -1.0, 0.25], [0.5, 2.0, 0.5]]:
		var value: float = weight_model.evaluate(fixture[0], fixture[1])
		check(is_finite(value) and absf(value - fixture[2]) <= 0.000001, "local water weight hand-derived fixture " + str(fixture))
	for weight: float in [0.0, 0.55, 1.0]:
		previous = -1.0
		for index in 33:
			var coverage := float(index) / 32.0
			var value: float = weight_model.evaluate(coverage, weight)
			check(value >= previous and value >= 0.0 and value <= coverage, "water weight monotone and only increases local transparency")
			if weight == 1.0:
				check(value == coverage, "weight one restores previous same-width response")
			previous = value
		check(weight_model.evaluate(0.00001, weight) < 0.001 and 1.0 - weight_model.evaluate(0.99999, weight) < 0.001, "water weight approaches both neighbor endpoints continuously")
	check(weight_model.evaluate(model.evaluate(20.0, 20.0, 0.0, 0.6), 0.55) == 1.0, "real deep-water coverage stays one with local water weight")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(800, 450)
	viewport.own_world_3d = true
	root.add_child(viewport)
	var camera := Camera3D.new()
	viewport.add_child(camera)
	camera.position = Vector3(20.0, 8.0, 26.0)
	camera.look_at(Vector3.ZERO)
	var ocean := Ocean.new()
	viewport.add_child(ocean)
	ocean.configure(camera, load("res://assets/textures/waternormals.jpg"), 16)
	ocean.configure_reflection(camera)
	ocean.enable_surface_optics(true)
	var material: ShaderMaterial = ocean.material_override
	# Headless ShaderMaterial returns null for an unset shader default. Execute
	# the actual uniform initializer and its coastline behavior instead.
	var default_pattern := RegEx.new()
	default_pattern.compile("uniform\\s+float\\s+shore_edge_feather_m(?:\\s*:[^=;]+)?\\s*=\\s*([^;]+);")
	var default_source := default_pattern.search(material.shader.code)
	check(default_source != null, "actual production material declares controlled coverage input")
	if default_source != null:
		var initializer := Expression.new()
		check(initializer.parse(default_source.get_string(1)) == OK, "actual coverage default initializer is executable")
		var default_width: Variant = initializer.execute()
		check(not initializer.has_execute_failed() and default_width is float and absf(default_width-0.6)<1e-6 and model.evaluate(0.0,0.0,0.0,default_width) == 0.0 and model.evaluate(20.0,20.0,0.0,default_width) == 1.0, "accepted default feathers contact while preserving deep-water coverage")
	default_pattern.compile("uniform\\s+float\\s+shore_edge_water_weight(?:\\s*:[^=;]+)?\\s*=\\s*([^;]+);")
	default_source = default_pattern.search(material.shader.code)
	check(default_source != null, "actual production material declares independent local water weight")
	if default_source != null:
		var initializer := Expression.new()
		check(initializer.parse(default_source.get_string(1)) == OK, "actual water weight default initializer is executable")
		var default_weight: Variant = initializer.execute()
		check(not initializer.has_execute_failed() and default_weight is float and absf(weight_model.evaluate(0.5, default_weight) - 0.3875) < 1e-6, "water weight default supplies accepted local midpoint response")
	var wave_components: Variant = material.get_shader_parameter("wave_components")
	var geometry := ocean.mesh
	var mirror: SubViewport = ocean.get_reflection_viewport()
	ocean.set_simulation_time(2.0)
	material.set_shader_parameter("shore_edge_feather_m", 0.35)
	material.set_shader_parameter("shore_edge_water_weight", 0.55)
	ocean.update_projection()
	check(material.get_shader_parameter("shore_edge_feather_m") == 0.35, "actual material retains controlled candidate width")
	check(material.get_shader_parameter("shore_edge_water_weight") == 0.55, "actual material retains independent local water weight")
	check(material.get_shader_parameter("wave_components") == wave_components and material.get_shader_parameter("wave_count") == 5, "coverage cannot change authoritative five-wave descriptor")
	check(material.get_shader_parameter("simulation_time") == 2.0 and material.get_shader_parameter("u_time") == 2.0, "coverage keeps both accepted shader clocks")
	check(ocean.mesh == geometry and ocean.get_reflection_viewport() == mirror, "same-time candidate keeps grid and mirror owners")
	material.set_shader_parameter("shore_edge_feather_m", 0.0)
	check(material.get_shader_parameter("shore_edge_feather_m") == 0.0, "same-time baseline restored without rebuilding production owners")
	ocean.set_visual_style(0)
	viewport.free()
	finish()

func finish() -> void:
	print("SHORE_EDGE_COVERAGE_TESTS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
