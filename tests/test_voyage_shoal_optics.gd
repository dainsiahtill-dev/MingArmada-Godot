extends SceneTree
const Demo = preload("res://game/research/demos/ocean_surface_experiment.gd")
var assertions := 0
var failures := 0
func _initialize() -> void: run.call_deferred()
func check(ok: bool,why: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",why)
func run() -> void:
	var viewport := SubViewport.new();viewport.size=Vector2i(1260,720);viewport.own_world_3d=true;root.add_child(viewport)
	var demo := Demo.new();viewport.add_child(demo)
	check(demo.configure({"fixture":"supply_shoal","paused":true,"bank_water_weight":0.0,"bank_palette_weight":0.0}).ok,"existing ocean demo builds actual navigation shoal")
	var before: Dictionary=demo.inspection_snapshot()
	check(absf(before.telemetry.shoal_center_height+2.4)<0.00001,"fixture retains actual -2.4m navigation plateau")
	check(demo.set_parameter("bank_water_weight",0.65).ok,"same-time bank factor accepted")
	var after: Dictionary=demo.inspection_snapshot()
	var declared := false
	for uniform: Dictionary in demo._ocean.material_override.shader.get_shader_uniform_list():
		if uniform.name=="detached_bank_water_weight":declared=true
	check(declared,"bank factor is an actual shader input, not an unused material property")
	check(after.telemetry.bank_water_weight!=null and is_equal_approx(float(after.telemetry.bank_water_weight),0.65),"bank factor reaches declared production shader uniform")
	check(before.time==after.time and before.telemetry.shoal_fingerprint==after.telemetry.shoal_fingerprint and before.telemetry.wave_samples==after.telemetry.wave_samples,"optical factor does not alter physics, terrain or accepted time")
	check(demo.set_parameter("bank_palette_weight",0.65).ok,"same-time bank palette control accepted")
	check(is_equal_approx(demo.inspection_snapshot().telemetry.bank_palette_weight,0.65),"palette factor reaches bound production material")
	for value: Variant in [-0.1,1.1,NAN,"green"]:
		check(not demo.set_parameter("bank_water_weight",value).ok,"invalid bank factor rejected "+str(value))
		check(not demo.set_parameter("bank_palette_weight",value).ok,"invalid palette factor rejected "+str(value))
	check(demo.set_parameter("fixture","optics").get("reset_required",false),"fixture changes require host-owned explicit reset")
	check(demo.reset_experiment({"bank_water_weight":0.65}).ok,"same bank resets through normal experiment owner")
	check(demo.inspection_snapshot().telemetry.shoal_fingerprint==before.telemetry.shoal_fingerprint,"reset preserves deterministic original navigation grid")
	var source := FileAccess.get_file_as_string("res://modules/scene_engine/ocean/reference_shore_foam.gdshaderinc")
	var regex := RegEx.new();regex.compile("(?s)float reference_detached_bank\\(float depth, float coast\\)\\s*\\{([^}]+)\\}")
	var found := regex.search(source)
	check(found!=null,"shared production bank classification exists")
	if found!=null:
		var script := GDScript.new()
		script.source_code="extends RefCounted\nfunc sample(depth: float,coast: float) -> float:\n\t"+found.get_string(1).strip_edges().replace(";","")+"\n"
		check(script.reload()==OK,"production classification executes")
		if script.can_instantiate():
			var model: RefCounted=script.new()
			for fixture: Array in [[2.4,1000.0,1.0],[2.4,0.0,0.0],[0.0,1000.0,0.0],[24.0,1000.0,0.0],[2.4,52.0,0.5]]:
				check(absf(model.sample(fixture[0],fixture[1])-fixture[2])<0.00001,"actual coast/depth isolates submerged bank "+str(fixture))
	demo.dispose();check(demo._shoal==null and demo._shoal_texture==null,"bank fixture releases owned grid and texture");viewport.free()
	print("VOYAGE_SHOAL_OPTICS_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
