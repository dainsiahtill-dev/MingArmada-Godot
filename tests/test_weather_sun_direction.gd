extends SceneTree
const Weather=preload("res://modules/environment_engine/weather_state.gd")
const World=preload("res://modules/scene_engine/world/world_view.gd")
var assertions:=0
var failures:=0
func check(ok:bool,detail:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL weather sun direction: ",detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	var weather:=Weather.new();check(weather.configure(),"original default weather configures")
	var packet:Dictionary=weather.snapshot()
	var source:Array=packet.lighting.sourceLightFields.lightDirection
	var ray:=Vector3(source[0],source[2],-source[1]).normalized()
	var target:Array=packet.lighting.target.direction
	var toward_sun:=Vector3(target[0],target[1],target[2]).normalized()
	check(toward_sun.dot(ray)<-.999999,"target direction points toward sun, opposite untouched source ray")
	var world:=World.new();root.add_child(world)
	var sun:=DirectionalLight3D.new();root.add_child(sun)
	world._source_lighting=packet.lighting.target.duplicate(true)
	world.bind_environment(Environment.new(),sun)
	check((-sun.global_basis.z).dot(ray)>.999999,"native -Z emits in actual converted source ray direction")
	check((-sun.global_basis.z).y<0 and toward_sun.y>0,"default noon illuminates downward from above")
	check(weather.snapshot().lighting.sourceLightFields.lightDirection==source,"consumer does not alter source authority")
	world.dispose();world.free();sun.free()
	print("WEATHER_SUN_DIRECTION_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
