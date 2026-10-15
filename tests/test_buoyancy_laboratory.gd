extends SceneTree
const Demo=preload("res://game/research/demos/hull_contact_experiment.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func _initialize()->void:run.call_deferred()
func run()->void:
	var viewport:=SubViewport.new();viewport.size=Vector2i(640,480);viewport.own_world_3d=true;root.add_child(viewport)
	var demo:=Demo.new();check(demo.configure({"kind":"fisherman","scenario":"slow","paused":true}).ok,"configure real existing lab")
	viewport.add_child(demo)
	var state:Dictionary=demo.inspection_snapshot()
	check(state.has("buoyancy"),"lab exposes actual solver waterline and draft diagnostics")
	if not state.has("buoyancy"):demo.dispose();viewport.free();finish();return
	check(state.buoyancy.relative_model,"lab default uses production water-relative solver")
	for i in 10:demo.advance(1.0/32.0)
	check(demo.inspection_snapshot().native_ship==state.native_ship,"paused lab holds same pose")
	check(demo.reset_experiment({"water_relative_buoyancy":false}).ok,"same lab can replay legacy baseline")
	check(not demo.inspection_snapshot().buoyancy.relative_model,"baseline is real legacy solver, not a label")
	check(not demo.configure({"water_relative_buoyancy":"false"}).ok,"invalid factor rejected atomically")
	check(not demo.inspection_snapshot().buoyancy.relative_model,"rejected factor preserves accepted solver")
	check(demo.reset_experiment({"water_relative_buoyancy":true,"paused":false}).ok,"restores production")
	for i in 64:demo.advance(1.0/32.0)
	state=demo.inspection_snapshot()
	check(state.buoyancy.relative_model and absf(float(state.buoyancy.relative_error_m))<=.250001,"real lab motion obeys fisherman immersion window")
	demo.dispose();viewport.free();finish()
func finish()->void:
	print("BUOYANCY_LABORATORY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
