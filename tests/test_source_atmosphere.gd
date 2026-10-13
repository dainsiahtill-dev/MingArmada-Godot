extends SceneTree
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Weather=preload("res://modules/environment_engine/weather_state.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL source atmosphere: "+message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var camera:=Camera3D.new();owner.add_child(camera)
	var renderer:=Atmosphere.new()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	check(bool(renderer.configure(owner,manifest,{"fog_placements":[Transform3D.IDENTITY,Transform3D.IDENTITY]}).get("ok",false)),"existing dome ring/fog configuration preserved")
	var weather:=Weather.new();weather.configure({"epoch":12})
	var packet:=weather.advance(.25,{},{})
	renderer.apply_snapshot({"environment":packet},camera)
	var diagnostics:Dictionary=renderer.diagnostics()
	check(int(diagnostics.get("worldWeatherInstances",0))==3,"all 3 original world clouds reach renderer")
	check(int(diagnostics.get("worldWeatherMeshes",0))==45,"23 storm plus 2 times11 cloud meshes retained")
	check(int(diagnostics.get("bakedCloudShadowMeshes",0))==5,"storm sibling shadow and both cloud00 shadow pairs rendered")
	check(float(diagnostics.animationTime)==.25,"producer owns accepted cloud timeline")
	var before:Dictionary=renderer.diagnostics()
	renderer.apply_snapshot({"environment":packet},camera)
	check(renderer.diagnostics().cloudUpdates==before.cloudUpdates,"extra presentation cannot advance sky ring")
	check(bool(diagnostics.get("independentInstanceClocks",false)),"fog and weather actors own different clocks")
	var fog:Array=renderer._fog
	check(fog[0].compiled.roots[0].children[0].keyframes[0].clock!=fog[1].compiled.roots[0].children[0].keyframes[0].clock,"different fog phases do not share mutable controller clock")
	var next:=weather.advance(.33333333,{},{})
	renderer.apply_snapshot({"environment":next},camera)
	var before_rebuild:Array=renderer._weather[0].states.duplicate(true)
	renderer.configure(owner,manifest,{"fog_placements":[Transform3D.IDENTITY,Transform3D.IDENTITY]})
	renderer.apply_snapshot({"environment":next},camera)
	check(renderer._weather[0].states==before_rebuild,"quality recreation restores complete actor controller history")
	check(renderer._clouds[0][0].material.get_shader_parameter("source_environment_color")!=null,"accepted authored light reaches original cloud material")
	for instance:Dictionary in renderer._weather:
		for record:Dictionary in instance.meshes:
			if record.get("bakedShadow",false):check(absf(record.node.global_position.y-.12)<0.000001,"baked texture shadow belongs on explicit receiver surface")
	weather.configure({"epoch":13,"sky_crt_seed":77})
	renderer.apply_snapshot({"environment":weather.advance(.5,{},{})},camera)
	# Independent recovered JS createCloudRing(OriginalCrtRand(77)): 29/159.
	check(renderer.diagnostics().cloudClones==29 and renderer.diagnostics().cloudMeshes==159,"accepted seed77 selects original prototype topology rather than renderer seed1")
	renderer.dispose()
	check(owner.get_child_count()==1,"dispose releases all owned atmosphere nodes")
	owner.free()
	print("SOURCE_ATMOSPHERE_TESTS assertions=%d failures=%d"%[assertions,failures])
	quit(1 if failures else 0)
