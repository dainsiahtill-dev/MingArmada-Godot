extends SceneTree
const Ocean=preload("res://modules/scene_engine/ocean/projected_ocean.gd")
var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,reason: String) -> void:
	assertions+=1
	if not ok: failures+=1; printerr("FAIL: ",reason)
func _run() -> void:
	var helper: String="res://modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc"
	check(FileAccess.file_exists(helper),"separate original alpha micro-sparkle layer exists")
	if failures: _finish(); return
	var shader:=Shader.new()
	shader.code='shader_type spatial;\n#include "'+helper+'"\nvoid fragment(){ALBEDO=reference_original_micro_sparkle(vec2(4,8),vec3(0,1,0),12.25,vec2(1,0),14.0,.1,25.0,.95);}'
	var uniforms: Array=shader.get_shader_uniform_list()
	var found:=false
	for entry: Dictionary in uniforms:
		if entry.name=="reference_original_sparkle_texture": found=true
	check(found,"standalone helper parses and exposes its real source texture")
	var provenance: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/pirates_reference/user-water-textures.provenance.json"))
	check(provenance is Dictionary and provenance.textures.size()==4,"four source textures have separately recorded pixel/channel evidence")
	if provenance is Dictionary:
		for record: Dictionary in provenance.textures:
			check(FileAccess.get_sha256("res://assets/textures/pirates_reference/"+str(record.name))==record.pngSha256,"project texture retains exact original preview bytes")
	var bindings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/textures/pirates_reference/water-binding-provenance.json"))
	check(bindings.nifFilesScanned==1253 and bindings.errors.is_empty(),"whole Pak library binding scan parsed the relevant water assets without errors")
	var original: Array=bindings.hintBindings["water_spaarkle.dds"]
	check(original.size()==1 and original[0].propertyBlock==7 and original[0].textureBlock==8 and original[0].role=="base","original micro-sparkle has a proved NIF Base material pointer")
	check(bindings.hintBindings["02_sparkle_b.dds"].is_empty(),"unproved original sparkle file binding is retained as unknown")
	var texture: Texture2D=load("res://assets/textures/pirates_reference/water_spaarkle.dds.png")
	check(texture.get_width()==256 and texture.get_height()==256,"micro-sparkle uses the full original 256 texture")
	var pixels: Image=texture.get_image()
	var zero:=0
	var bright:=0
	var total:=0.0
	for y in pixels.get_height():
		for x in pixels.get_width():
			var alpha: float=pixels.get_pixel(x,y).a
			if alpha<.01: zero+=1
			if alpha>.7: bright+=1
			total+=alpha
	check(zero>10000 and bright>100 and bright<10000,"actual alpha is sparse bright points with broad transparent water")
	check(total/(pixels.get_width()*pixels.get_height())<.12,"original mask cannot be treated as an opaque white surface")
	var viewport:=SubViewport.new(); viewport.size=Vector2i(640,360); root.add_child(viewport)
	var camera:=Camera3D.new(); viewport.add_child(camera); camera.position=Vector3(15,20,25); camera.look_at(Vector3.ZERO)
	var ocean:=Ocean.new(); viewport.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),16)
	var material: ShaderMaterial=ocean.material_override
	check(material.get_shader_parameter("reference_original_sparkle_texture")==texture,"formal ocean binds the original sparkle alongside existing glints")
	var waves: Variant=material.get_shader_parameter("wave_components")
	ocean.set_simulation_time(12.25); ocean.set_simulation_time(12.25)
	check(material.get_shader_parameter("u_time")==12.25 and material.get_shader_parameter("wave_components")==waves,"new sparkle binding does not change accepted time or physical waves")
	ocean.free(); camera.free(); viewport.free()
	_finish()
func _finish() -> void:
	print("REFERENCE_SPARKLE_FUSION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
