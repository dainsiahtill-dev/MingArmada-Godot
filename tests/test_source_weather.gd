extends SceneTree
const Native=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
var assertions:=0
var failures:=0
func check(ok:bool,message:String)->void:
	assertions+=1
	if not ok: failures+=1;printerr("FAIL source weather: "+message)
func _initialize()->void:
	var fixture:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_weather.json"))
	var order:Dictionary=fixture.composition
	var expected:Array=[]
	for value:Variant in order.native.translation:expected.append(Native.f32(float(value)))
	check(Native.compose_transform(order.parent,order.local).translation==expected,"rotate/f32 before parent scale matches original byte output")
	var compiler:=Compiler.new()
	check(compiler._compose_transform(order.parent,order.local).translation==expected,"compiled TRS matches independently executed original bytes")
	var clock_data:Dictionary={"flags":4,"frequency":1.0,"phase":0.0,"start_time":0.0,"stop_time":24.0}
	var controller:Dictionary=compiler._controller({"fields":clock_data},{})
	controller.clock.started=true;controller.clock.last=10.0;controller.clock.accumulated=6.0
	check(compiler._clock_time(controller,10.25,true)==6.25,"captured clock history continues instead of reset seek")
	check(FileAccess.file_exists("res://modules/environment_engine/weather_state.gd"),"accepted environment producer exists")
	if FileAccess.file_exists("res://modules/environment_engine/weather_state.gd"):
		var producer=load("res://modules/environment_engine/weather_state.gd").new()
		var rng:=Native.OriginalCrtRand.new(int(fixture.initialRandState))
		for row:Dictionary in fixture.rows:
			var actual:Dictionary=producer.step_original_weather(row.before,row.input,rng.next)
			var equal:=true
			for key:String in ["lightTime","windHeading","windDisplacement","windVelocity"]:equal=equal and int(actual.state[key])==int(row.native[key])
			for index in 3:
				equal=equal and int(actual.state.centers[index].x)==int(row.native.centers[index].x) and int(actual.state.centers[index].y)==int(row.native.centers[index].y)
			check(equal,"int32/time/wind/center source call %d"%int(row.input.frame))
			check(rng.state==int(row.randStateAfter),"exact source RNG consumption %d"%int(row.input.frame))
			var events:Array=row.externalOperations.duplicate(true)
			for event:Dictionary in events:
				if event.has("lightTime"):event.lightTime=int(event.lightTime)
				if event.has("soundEvent"):event.soundEvent=int(event.soundEvent)
			check(actual.externalOperations==events,"source light/audio external submission inputs %d"%int(row.input.frame))
		check(producer.original_scene_day_mode(1499).mode==0 and producer.original_scene_day_mode(1500).mode==1 and producer.original_scene_day_mode(2030).mode==2,"original day thresholds")
		check(producer.original_local_wind_strength(0,0,[{"x":0,"y":0},{"x":0,"y":0},{"x":0,"y":0}])==32,"source integer wind strength at center")
		check(producer.original_local_wind_strength(1000,0,[{"x":0,"y":0},{"x":0,"y":0},{"x":0,"y":0}])==31,"source weighted wind distance divides toward zero")
		check(not producer.configure({"initial_state":{"lightTime":1200,"windHeading":0,"windDisplacement":0,"windVelocity":0,"centers":[{"x":1.5,"y":0},{"x":0,"y":0},{"x":0,"y":0}]}}),"reject fractional source integers")
		check(not producer.configure({"source_environment":{"sineBoundary":2147483648}}),"reject source int32 overflow")
		check(producer.configure({"source_calls_per_second":32.0,"source_position_units_per_metre":10.0}),"configured target adapter")
		var first:Dictionary=producer.advance(.25,{"position":Vector2(10,20)},{})
		check(int(first.sourceCallIndex)==8 and first.worldClouds.size()==3,"accepted simulation cadence and 3 world actors")
		var detached:=first.duplicate(true)
		first.source.weather.centers[0].x=123
		check(producer.snapshot().source.weather.centers[0].x!=123,"caller cannot mutate owned source history")
		check(producer.advance(.25,{}, {})==detached,"repeated presentation cannot consume RNG twice")
		check(producer.advance(1.0,{}, {},true)==detached,"pause preserves accepted simulation time")
		producer.advance(.5,{}, {})
		check(producer.advance(.25,{}, {})==detached,"rewind restores accepted state and RNG")
		check(int(producer.advance(.1,{"epoch":99},{}).epoch)==99,"new scene epoch creates separate state")
		var voyage=load("res://modules/environment_engine/weather_state.gd").new()
		voyage.configure({"epoch":101})
		var remembered:Dictionary={}
		for index in range(1,513):
			var packet:Dictionary=voyage.advance(index/32.0,{"position":Vector2(index,index*2),"heading":index*.002},{"speed":index*.001})
			if index==137:remembered=packet
		check(voyage._history.size()<=6,"512 accepted steps retain sparse complete checkpoints")
		check(voyage.get("_journal") is Array and voyage.get("_journal").size()==512,"all accepted inputs remain available for exact rewind")
		if voyage.get("_journal") is Array:
			check(not voyage.get("_journal")[0].has("packet") and not voyage.get("_journal")[0].has("ring"),"lightweight journal does not retain full cloud/controller packets")
		check(voyage.advance(137/32.0,{}, {})==remembered,"sparse checkpoint replay recovers exact observer/wind/RNG/cloud/fog packet")
		var axis=load("res://modules/environment_engine/weather_state.gd").new()
		axis.configure({"source_environment":{"forceCenterZero":true,"movementSpeed":0}})
		check(axis.advance(1.0/32.0,{"position":Vector2(1000,500)},{}).worldClouds[0].worldPosition==[1800.0,30.0,500.0],"observer Vector2 worldXZ maps into original XY with correct handedness")
	print("SOURCE_WEATHER_TESTS assertions=%d failures=%d"%[assertions,failures])
	quit(1 if failures else 0)
