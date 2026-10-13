extends SceneTree
const Weather=preload("res://modules/environment_engine/weather_state.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL source weather retention: "+message)
func _retained_bytes(weather:RefCounted)->int:
	return var_to_bytes(weather._journal).size()+var_to_bytes(weather._history).size()
func _initialize()->void:
	var weather:=Weather.new()
	check(weather.configure({"epoch":61,"history_retention_seconds":2.0}),"explicit positive target retention configures")
	var origin:Dictionary=weather.snapshot()
	var remembered:Dictionary={}
	var warm_bytes:=0;var middle_bytes:=0
	var warm_memory:=0.0
	for index in range(1,3073):
		var packet:Dictionary=weather.advance(index/120.0,{"position":Vector2(index*.03,index*.02),"heading":index*.001,"route":"battle" if index%2==0 else "sailing"},{"speed":index*.002})
		if index==1024:warm_bytes=_retained_bytes(weather);warm_memory=Performance.get_monitor(Performance.MEMORY_STATIC)
		if index==2048:middle_bytes=_retained_bytes(weather)
		if index==2960:remembered=packet
	var final_packet:=weather.snapshot()
	var final_bytes:=_retained_bytes(weather)
	var final_memory_delta:=Performance.get_monitor(Performance.MEMORY_STATIC)-warm_memory
	check(weather._journal.size()<=512 and weather._history.size()<=5,"rolling retention bounds live input/checkpoint counts after 12 windows")
	check(middle_bytes<=warm_bytes*1.25 and final_bytes<=warm_bytes*1.25,"warmed retained serialization plateaus instead of linear lifetime growth")
	check(final_memory_delta<4000000.0,"warmed live Godot allocation stays within four MB of retained working set")
	check(weather.has_method("diagnostics"),"target retention/admission diagnostic is exposed")
	if weather.has_method("diagnostics"):
		var diagnostic:Dictionary=weather.diagnostics()
		check(diagnostic.historyRetentionSeconds==2.0 and diagnostic.retainedFrom>23.0 and diagnostic.anchorTime<=diagnostic.retainedFrom,"window and nearest earlier anchor are explicitly reported")
	check(weather.advance(.1,{"route":"rejected_route"},{"speed":999})==final_packet,"outside-window intermediate time is atomically rejected")
	if weather.has_method("diagnostics"):
		check(not weather.diagnostics().admission.accepted and weather.diagnostics().admission.reason=="outside_retained_history","outside-window rejection has distinct admission diagnostic")
	check(weather.advance(2960/120.0,{"route":"ignored_replay_input"},{"speed":999})==remembered,"retained replay recovers exact RNG/routes/wind/sky/fog/actor clocks")
	check(weather.advance(3072/120.0,{},{})==final_packet,"retained future replay rejoins exact latest packet")
	for invalid:Variant in [0.0,-1.0,NAN,INF,"120",true]:
		check(not weather.configure({"history_retention_seconds":invalid}) and weather.snapshot()==final_packet,"invalid target retention is rejected without changing source state")
	var branch_packet:=weather.advance(24.5021,{"route":"retained_branch"},{"speed":5})
	if weather.has_method("diagnostics"):
		var branch_diagnostic:Dictionary=weather.diagnostics()
		check(branch_diagnostic.retainedFrom>=branch_diagnostic.anchorTime,"new branch admission cannot widen behind pruned anchor")
		check(weather.advance(float(branch_diagnostic.anchorTime)-.01,{},{})==branch_packet,"branch rewind before available anchor is atomically rejected")
	check(weather.advance(0.0,{},{})==origin,"time zero restores exact original epoch packet after pruning")
	check(weather._journal.is_empty() and weather._history.size()==1,"time zero discards inaccessible prior history for honest new branch")
	var fresh:=Weather.new();fresh.configure({"epoch":61,"history_retention_seconds":2.0})
	check(weather.advance(.25,{"route":"new_branch"},{"speed":4})==fresh.advance(.25,{"route":"new_branch"},{"speed":4}),"zero then forward is equivalent to a fresh branch, never fabricated old replay")
	var defaults:=Weather.new();defaults.configure()
	if defaults.has_method("diagnostics"):check(defaults.diagnostics().historyRetentionSeconds==120.0,"production default retains latest 120 source seconds")
	print("SOURCE_WEATHER_RETENTION_TESTS assertions=%d failures=%d"%[assertions,failures])
	print("retention measured bytes warm=",warm_bytes," middle=",middle_bytes," final=",final_bytes," static_memory_delta=",final_memory_delta)
	quit(1 if failures else 0)
