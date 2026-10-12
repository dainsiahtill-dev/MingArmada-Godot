extends SceneTree
## Real shared renderer, actual DDS bindings and injected source clock.
const Effect = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL FX render: ", detail)
func _initialize() -> void: _run.call_deferred()
func _record(texture: String, depth: float, clamp_mode: int = 0) -> Dictionary:
	return {"name":"source-test","texture":texture,"vertices":[[-1.0,depth,-1.0],[1.0,depth,-1.0],[1.0,depth,1.0],[-1.0,depth,1.0]],"uvs":[[-.25,0.0],[1.25,0.0],[1.25,1.0],[-.25,1.0]],"triangles":[[0,1,2],[0,2,3]],"color":[.8,.45,.1],"alpha":.62,"alphaFlags":4845,"threshold":0,"clampMode":clamp_mode,"filterMode":2,"world":{"translation":[0.0,depth,0.0]}}
func _visible(effect: Node3D) -> Array:
	return effect.get_children().filter(func(node): return node is MeshInstance3D and node.visible)
func _geometry(effect: Node3D) -> Array:
	var out := []
	for node in _visible(effect): out.append([node.transform,node.mesh.surface_get_arrays(0)])
	return out
func _run() -> void:
	var camera := Camera3D.new(); root.add_child(camera); camera.position = Vector3(0,1,10)
	var native := Effect.new(); root.add_child(native)
	check(native.configure("fx_cannon_fire_01.nif",{"camera":camera,"seed":1}),"actual eleven-layer source configures")
	var smoke := _record("fx_cannon_smoke_03.dds",800.0)
	var mist := _record("fx_mist_01.dds",400.0,3)
	var near := _record("fx_cannon_smoke_03.dds",100.0)
	var material: ShaderMaterial = native._material(smoke)
	check(material.get_shader_parameter("source_repeat") == false,"native CC smoke uses the clamp sampler, including transformed UV outside the texture")
	var wrapped: ShaderMaterial = native._material(mist)
	check(wrapped.get_shader_parameter("source_repeat") == true,"native WW mist keeps its actual wrap sampler")
	var texture: Texture2D = material.get_shader_parameter("source_texture")
	check(texture != null and texture.get_image().has_mipmaps() and texture.get_image().get_mipmap_count() == 7,"actual smoke DDS retains all eight authored levels")
	check(material.get_shader_parameter("display_tint") == Color.WHITE,"native rendering leaves recovered packed RGBA unchanged")
	native._render([near,mist,smoke])
	var draws := _visible(native)
	check(draws.size() == 3,"far A, middle B, near A cannot collapse into a cross-layer material batch")
	if draws.size() == 3:
		check(draws[0].global_position.z < draws[1].global_position.z and draws[1].global_position.z < draws[2].global_position.z,"actual instances keep far-to-near centroids for camera and engine sorting")
		check(draws[0].material_override == draws[2].material_override,"source materials stay shared despite independent spatial order")
		for node in draws:
			var arrays: Array = node.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_COLOR][0].is_equal_approx(Color(.8,.45,.1,.62)),"source packed RGBA reaches the actual vertex array")
			check(arrays[Mesh.ARRAY_TEX_UV][0] == Vector2(-.25,0),"sampler correction does not rewrite native transformed UV")
	check(native.apply_snapshot(.06,10.06),"accepted source clock draws a real frame")
	check(not native.apply_snapshot(3.34,13.34),"past the explicit source controller clip is rejected")
	check(_visible(native).is_empty(),"out-of-clip update cannot freeze the preceding smoke frame")
	check(native.has_method("get_playback_duration"),"event owner can query actual source clip rather than hardcode it")
	if native.has_method("get_playback_duration"): check(absf(native.get_playback_duration()-3.3333332538604736)<.000001,"public duration comes from the original source clip")
	var game := Effect.new(); root.add_child(game)
	check(game.configure("fx_cannon_fire_01.nif",{"camera":camera,"seed":1,"render_profile":"game_cannon"}),"game cannon is an explicit display profile")
	check(game.apply_snapshot(.02,20.02),"early profile uses only injected accepted time")
	var early := _geometry(game)
	var flash := _visible(game).filter(func(node): return node.get_meta("display_role","") == "game_flash")
	check(not flash.is_empty(),"short textured yellow-orange muzzle flash accompanies original smoke")
	if not flash.is_empty():
		var warm: Color = flash[0].material_override.get_shader_parameter("display_tint")
		check(warm.r > warm.g and warm.g > warm.b,"actual flash material has a warm coloured profile, not a white sphere")
		check(flash[0].material_override.get_shader_parameter("source_texture") == Effect._texture("fx_streakin_001.dds"),"game flash reuses the original streak DDS")
	game.apply_snapshot(.02,20.02)
	check(_geometry(game) == early,"paused accepted source time leaves profile geometry unchanged")
	game.apply_snapshot(.20,20.20)
	check(_visible(game).all(func(node): return node.get_meta("display_role","") != "game_flash"),"game flash is finite while source smoke persists")
	check(game.diagnostics().get("particles",0) > 0,"flash expiry retains native smoke particles")
	game.apply_snapshot(.02,20.02)
	check(_geometry(game) == early,"same seed and source clock replay the same profile after rewind")
	var smoke_only := Effect.new(); root.add_child(smoke_only)
	check(smoke_only.configure("fx_cannon_fire_01.nif",{"camera":camera,"render_profile":"game_smoke"}),"destruction owner can request original smoke with no duplicate fire node")
	smoke_only.apply_snapshot(.02,.02)
	check(_visible(smoke_only).all(func(node): return node.get_meta("display_role","") != "game_flash"),"smoke-only profile has no invented muzzle flash")
	for effect in [native,game,smoke_only]: effect.dispose(); effect.dispose(); check(effect.get_child_count() == 0,"dispose releases every native/profile mesh"); effect.free()
	camera.free()
	print("FIDELITY_FX_RENDERING assertions=%d failures=%d" % [assertions,failures])
	quit(1 if failures else 0)
