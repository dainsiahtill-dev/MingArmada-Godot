extends SceneTree
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Weather=preload("res://modules/environment_engine/weather_state.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var owner:=Node3D.new();root.add_child(owner)
	var camera:=Camera3D.new();owner.add_child(camera)
	camera.position=Vector3(-1600,250,700);camera.look_at(Vector3(-1600,70,0));camera.far=5000
	var renderer:=Atmosphere.new()
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	check(renderer.configure(owner,manifest).ok,"actual cloud assets configure")
	check(renderer.has_method("set_cloud_lifecycle_enabled"),"existing renderer accepts lifecycle experiment")
	if not renderer.has_method("set_cloud_lifecycle_enabled"):renderer.dispose();owner.free();finish();return
	renderer.set_cloud_lifecycle_enabled(true)
	var weather:=Weather.new()
	weather.configure({"epoch":3,"model_scale":10.0,"initial_state":{"lightTime":1200,"windHeading":1073741760,"windDisplacement":0,"windVelocity":0,"centers":[{"x":-15980,"y":0},{"x":3000,"y":4000},{"x":6000,"y":-4000}]}})
	var packet:Dictionary=weather.snapshot()
	renderer.apply_snapshot({"environment":packet},camera)
	var original:Vector3=renderer.diagnostics().worldCloudLifecycle.states[0].position
	packet=weather.advance(1.0/32.0)
	var frozen:=var_to_bytes(packet)
	renderer.apply_snapshot({"environment":packet},camera)
	var live:Dictionary=renderer.diagnostics().worldCloudLifecycle.states[0]
	check(packet.worldClouds[0].generation==1,"fixture crosses real native reset")
	check(live.retiring and live.position.distance_to(original)<4.0,"visible complete cloud keeps moving instead of teleporting")
	check(float(renderer._weather[0].lifecycleRadius)>100.0,"full original hierarchy bound includes model scale and shadows")
	var retained:Dictionary=renderer.diagnostics().worldCloudLifecycle.states
	camera.position+=Vector3(0,40,70);camera.look_at(original)
	renderer.apply_snapshot({"environment":packet},camera)
	check(renderer.diagnostics().worldCloudLifecycle.states==retained,"same accepted time camera refresh cannot replace a cloud")
	check(var_to_bytes(packet)==frozen,"presentation never mutates native packet")
	renderer.set_reduced_motion(true)
	var next:Dictionary=weather.advance(60.0)
	renderer.apply_snapshot({"environment":next},camera)
	check(renderer.diagnostics().worldCloudLifecycle.states==retained,"reduced motion holds cloud lifecycle as well as controllers")
	renderer.set_reduced_motion(false)
	renderer.apply_snapshot({"environment":next},camera)
	check(renderer.diagnostics().worldCloudLifecycle.states[0].position==live.position,"restoring motion does not integrate the frozen sixty seconds")
	next=weather.advance(60.0+1.0/60.0)
	renderer.apply_snapshot({"environment":next},camera)
	var resumed:Vector3=renderer.diagnostics().worldCloudLifecycle.states[0].position
	check(resumed.distance_to(live.position)>.01 and resumed.distance_to(live.position)<2.0,"first resumed frame moves smoothly instead of catching up kilometers")
	renderer.reset_timeline()
	check(renderer.diagnostics().worldCloudLifecycle.states.is_empty(),"explicit encounter reset discards display lifecycle")
	renderer.dispose();owner.free();finish()
func finish()->void:
	print("CLOUD_LIFECYCLE_PRESENTATION_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
