extends SceneTree

var assertions:=0
var failures:=0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, reason: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",reason)

func _run() -> void:
	var original: Texture2D=load("res://assets/textures/waternormals.jpg")
	var image:=original.get_image()
	check(image.has_mipmaps(),"bound original normal has a real mip chain; sampler hints cannot filter one level")
	if image.has_mipmaps():
		check(image.get_mipmap_count()==10,"1024 original normal retains all mip levels down to one pixel")
		var top:=image.get_pixel(0,0)
		check(top.b>.6,"original tangent-space normal channels remain intact")
	var shader: Shader=load("res://modules/scene_engine/ocean/reference_game_water.gdshader")
	var found:=false
	for entry: Dictionary in shader.get_shader_uniform_list():
		if entry.name=="surface_ripple_light_strength": found=true
	check(found,"formal water shader compiles the detail helper and exposes bounded ripple light")
	print("OCEAN_DETAIL_MIPS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
