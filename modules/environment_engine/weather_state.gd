extends RefCounted
## Recovered 4604A0 integer slices. Scheduling, world units and light intensity
## are explicit target adapters; no original live RNG/cadence claim.
const Cloud=preload("res://modules/scene_engine/fidelity_fx/cloud_native.gd")
const Daylight=preload("res://modules/scene_engine/fidelity_island/daylight.gd")
const Compiler=preload("res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd")
const SourceMath=preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const SINE_PATH="res://modules/environment_engine/source_sine_table.json"
var _sine:Array=[]
var _options:Dictionary={}
var _state:Dictionary={}
var _rng:RefCounted
var _ring:Dictionary={}
var _packet:Dictionary={}
var _history:Array=[]
var _journal:Array=[]
const CHECKPOINT_INTERVAL:=128
var _accepted:=0.0
var _calls:=0
var _epoch:=0
var _revision:=0
var _rate:=32.0
var _units:=10.0
var _compiler:=Compiler.new()
var _weather_graphs:Array=[]
var _fog_clocks:Array=[]
var _last_light_time:=-1
var _last_light:Dictionary={}
var _published_nodes:Array=[]
var _published_updates:=-1

static func _json(path:String)->Dictionary:return JSON.parse_string(FileAccess.get_file_as_string(path))

static func i32(value:int)->int:
	var word:=value&0xffffffff
	return word-0x100000000 if word&0x80000000 else word
static func _div(a:int,b:int)->int:
	assert(b!=0 and not (a==-2147483648 and b==-1),"Original IDIV fault")
	return i32(int(a/float(b)))
static func _abs(a:int)->int:return i32(-a) if a<0 else a
static func _is_i32(value:Variant)->bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)==floor(float(value)) and float(value)>=-2147483648.0 and float(value)<=2147483647.0
static func _valid_options(options:Dictionary)->bool:
	for key:String in ["crt_seed","sky_crt_seed"]:
		var seed:Variant=options.get(key,1)
		if not (seed is int or seed is float) or not is_finite(float(seed)) or float(seed)!=floor(float(seed)) or float(seed)<0.0 or float(seed)>4294967295.0:return false
	for key:String in ["source_calls_per_second","source_position_units_per_metre","model_scale"]:
		var value:Variant=options.get(key,1.0)
		if not (value is int or value is float) or not is_finite(float(value)) or float(value)<=0.0:return false
	if options.has("initial_state"):
		var state:Variant=options.initial_state
		if not state is Dictionary or not state.has_all(["lightTime","windHeading","windDisplacement","windVelocity","centers"]):return false
		for key:String in ["lightTime","windHeading","windDisplacement","windVelocity"]:
			if not _is_i32(state[key]):return false
		if not state.centers is Array or state.centers.size()!=3:return false
		for center:Variant in state.centers:
			if not center is Dictionary or not center.has_all(["x","y"]) or not _is_i32(center.x) or not _is_i32(center.y):return false
	var source:Variant=options.get("source_environment",{})
	if not source is Dictionary:return false
	for key:String in ["frame","difficulty","movementSpeed","pace","playerMapX","playerMapY","shipHeading","sineBoundary"]:
		if source.has(key) and not _is_i32(source[key]):return false
	for key:String in ["pause","holdLight","forceCenterZero"]:
		if source.has(key) and not source[key] is bool:return false
	return true

func _load_sine()->void:
	if _sine.is_empty():_sine=JSON.parse_string(FileAccess.get_file_as_string(SINE_PATH)).sine256
func fixed_trig(magnitude:int,heading:int,boundary:int=65536)->int:
	_load_sine()
	var amount:=magnitude
	var angle:=heading
	if angle<0:amount=i32(-amount);angle&=0x7fffffff
	if angle&0x40000000:angle=i32(0x7fffffff-angle)
	var scale:=1
	while _abs(amount)>32000:amount=_div(amount,2);scale=i32(scale+scale)
	var index:=angle>>22
	var fraction:=angle&0x3fffff
	var low:=int(_sine[index])
	var high:=boundary if index==255 else int(_sine[index+1])
	var interpolated:=i32(low+(i32(fraction*i32(high-low))>>22))
	return i32(scale*(i32(amount*interpolated)>>16))

func step_original_weather(input:Dictionary,environment:Dictionary,rand:Callable)->Dictionary:
	var state:=input.duplicate(true)
	for key:String in ["lightTime","windHeading","windDisplacement","windVelocity"]:state[key]=int(state[key])
	for center:Dictionary in state.centers:center.x=int(center.x);center.y=int(center.y)
	var events:Array=[]
	if not environment.holdLight and int(state.lightTime)!=1200:
		state.lightTime=i32(i32(int(state.lightTime)+(int(state.lightTime)&3))+4)%2400
		events.append({"entry":"0x4AC640","lightTime":state.lightTime,"scope":"External light/scene update stub"})
	var target:=i32(3*i32(i32(int(environment.difficulty)*int(state.windDisplacement))+357913920))
	state.windHeading=i32(int(state.windHeading)+_div(i32(target-int(state.windHeading)),32))
	if not (int(environment.frame)&15) and not environment.pause:
		state.windDisplacement=i32(int(state.windDisplacement)+i32(186413*int(state.windVelocity)))
		state.windVelocity=i32(i32(i32(int(state.windVelocity)-_div(_div(int(state.windDisplacement),11930464),4))+_div(int(state.windVelocity),-16))+(int(rand.call())%11-5))
	for index in 3:
		var center:Dictionary=state.centers[index]
		if index==0 and environment.forceCenterZero:
			center.x=i32(1000*i32(int(environment.playerMapX)+8));center.y=i32(1000*int(environment.playerMapY))
		if not environment.pause:
			var amount:=_div(int(environment.movementSpeed),16)
			center.x=i32(int(center.x)-fixed_trig(amount,int(state.windHeading),int(environment.sineBoundary)))
			center.y=i32(int(center.y)-fixed_trig(amount,i32(int(state.windHeading)+0x40000000),int(environment.sineBoundary)))
		var dx:=_abs(i32(int(center.x)-i32(1000*int(environment.playerMapX))))
		var dy:=_abs(i32(int(center.y)-i32(1000*int(environment.playerMapY))))
		var distance:=_div(i32(dx+i32(2*dy)) if dx<=dy else i32(dy+i32(2*dx)),2)
		if int(center.x)<i32(1000*int(environment.playerMapX)) and distance>16000:
			center.x=i32(1000*i32(i32(_div(i32(12*int(environment.pace)),3)-int(rand.call())%3)+int(environment.playerMapX)))
			center.y=i32(1000*i32(i32(i32(fixed_trig(12,i32(int(environment.shipHeading)+0x40000000),int(environment.sineBoundary))+int(rand.call())%21)+int(environment.playerMapY))-10))
			if index==0:events.append({"entry":"0x487410","soundEvent":105,"scope":"External audio stub"})
	return {"state":state,"externalOperations":events}

static func original_scene_day_mode(source_time:int)->Dictionary:
	var mode:=0 if source_time>=1000 and source_time<1500 else (1 if source_time>=1500 and source_time<2030 else 2)
	return {"mode":mode,"skyResource":["skydome006.nif","skydome_lateday.nif","skydome_night.nif"][mode],"lightTime":[1200,1930,2300][mode]}
static func original_local_wind_strength(ship_x:int,ship_y:int,centers:Array)->int:
	var x:=_div(ship_x,1000);var y:=_div(ship_y,1000);var nearest:=65535
	for index in 3:
		var dx:=_abs(i32(x-int(centers[index].x)));var dy:=_abs(i32(y-int(centers[index].y)))
		var distance:=_div(i32(dx+i32(2*dy)) if dx<=dy else i32(dy+i32(2*dx)),2)
		if index:distance=i32(distance+2000)
		nearest=mini(nearest,distance)
	return _div(128000,i32(nearest+4000))

func configure(options:Dictionary={})->bool:
	if not _valid_options(options):return false
	var rate:=float(options.get("source_calls_per_second",32.0))
	var units:=float(options.get("source_position_units_per_metre",10.0))
	if not is_finite(rate) or rate<=0.0 or not is_finite(units) or units<=0.0:return false
	if not is_finite(float(options.get("model_scale",1.0))) or float(options.get("model_scale",1.0))<=0.0:return false
	_options=options.duplicate(true);_rate=rate;_units=units
	reset(_options)
	return true
func reset(options:Dictionary={})->void:
	if not _valid_options(options):return
	if not options.is_empty():_options=options.duplicate(true)
	_rate=float(_options.get("source_calls_per_second",32.0));_units=float(_options.get("source_position_units_per_metre",10.0))
	_epoch=int(_options.get("epoch",_epoch+1));_accepted=0.0;_calls=0;_revision=0
	_last_light_time=-1;_last_light.clear();_published_nodes=[];_published_updates=-1
	_rng=Cloud.OriginalCrtRand.new(int(_options.get("crt_seed",1)))
	_ring=Cloud.create_cloud_ring(int(_options.get("sky_crt_seed",1)))
	_state=_options.get("initial_state",{"lightTime":1200,"windHeading":1073741760,"windDisplacement":0,"windVelocity":0,"centers":[{"x":8000,"y":0},{"x":3000,"y":4000},{"x":6000,"y":-4000}]}).duplicate(true)
	for key:String in ["lightTime","windHeading","windDisplacement","windVelocity"]:_state[key]=int(_state[key])
	for center:Dictionary in _state.centers:center.x=int(center.x);center.y=int(center.y)
	_weather_graphs.clear();_fog_clocks.clear()
	var storm:=_compiler.bind_sequence(_json("res://assets/data/reference_atmosphere/definitions/assets/Pak2/stormcloud_sound.nif.json"),_json("res://assets/data/reference_atmosphere/definitions/assets/Pak6/stormcloud_sound_stormcloud_parent_stormcloud.kf.json"))
	_weather_graphs.append(_compiler.compile_asset(storm))
	for index in 2:_weather_graphs.append(_compiler.compile_asset(_json("res://assets/data/reference_atmosphere/definitions/assets/Pak7/cloud00.nif.json")))
	# All 50 source fog controllers have this same timing record, but mutable
	# phase state stays independent. elapsed+phase is a declared target schedule.
	for index in 20:
		var phase:=Cloud.f32(index*33.333335876464844*Cloud.FOG_PHASE_SCALE)
		var clock:=SourceMath.ControllerClock.new({"flags":44,"frequency":1.0,"phase":0.0,"start_time":0.0,"stop_time":33.333335876464844})
		clock.advance(phase);_fog_clocks.append({"phase":phase,"clock":clock})
	_history.clear();_journal.clear();_packet=_make_packet(0.0,[],{})
	_record()
func _record()->void:
	# Packet is private and frozen after construction. Only snapshot() duplicates
	# it for callers; retained accepted history can share immutable source arrays.
	_history.append({"time":_accepted,"journalIndex":_journal.size(),"packet":_packet})
func _restore(row:Dictionary)->void:
	_packet=row.packet.duplicate(true)
	_accepted=float(row.time);_state=_packet.source.weather.duplicate(true);_rng.state=int(_packet.source.rngState);_rng.draws=int(_packet.source.rngDraws)
	_ring=_packet.sky.ring.duplicate(true);_calls=int(_packet.sourceCallIndex);_revision=int(_packet.revision)
	_published_updates=-1
	for index in _weather_graphs.size():_compiler.restore_controllers(_weather_graphs[index],_packet.worldClouds[index].controllerState)
	for index in _fog_clocks.size():
		var saved:Dictionary=_packet.source.fogClocks[index]
		var clock:RefCounted=_fog_clocks[index].clock
		clock.last=float(saved.last);clock.accumulated=float(saved.accumulated);clock.started=bool(saved.started)
func advance(accepted_time:float,observer:Dictionary={},wind:Dictionary={},paused:bool=false)->Dictionary:
	if _packet.is_empty():configure()
	if observer.has("epoch") and int(observer.epoch)!=_epoch:
		var next:=_options.duplicate(true);next.epoch=int(observer.epoch);reset(next)
	if paused or not is_finite(accepted_time) or accepted_time<0.0:return snapshot()
	if accepted_time==_accepted:return snapshot()
	# Normal forward update never scans retained history. Replay only enters the
	# existing accepted domain; each checkpoint limits controller/sky replay to
	# 127 inputs, while the compact journal preserves every supplied delta.
	var recorded_end:=float(_journal[-1].time) if not _journal.is_empty() else 0.0
	if accepted_time<=recorded_end or accepted_time<_accepted:
		var low:=0;var high:=_history.size()-1
		while low<high:
			var middle:=int((low+high+1)/2)
			if float(_history[middle].time)<=accepted_time:low=middle
			else:high=middle-1
		var checkpoint:Dictionary=_history[low]
		_restore(checkpoint)
		var cursor:=int(checkpoint.journalIndex)
		while cursor<_journal.size() and float(_journal[cursor].time)<=accepted_time:
			var input:Dictionary=_journal[cursor]
			_advance_forward(float(input.time),input.observer,input.wind,false)
			cursor+=1
		if accepted_time==_accepted:return snapshot()
		# A new accepted point inside recorded history creates a new branch.
		_journal.resize(cursor)
		while float(_history[-1].time)>_accepted:_history.pop_back()
	elif _accepted<recorded_end:
		# Rejoin retained future inputs before a new point beyond recorded end.
		advance(recorded_end)
	_advance_forward(accepted_time,observer,wind,true)
	return snapshot()

func _advance_forward(accepted_time:float,observer:Dictionary,wind:Dictionary,record:bool)->void:
	var position:Variant=observer.get("position",Vector2.ZERO)
	var px:=0.0;var py:=0.0
	if position is Vector2:px=position.x;py=-position.y
	elif position is Vector3:px=position.x;py=-position.z
	elif position is Array and position.size()>=2:px=float(position[0]);py=-float(position[1])
	var environment:Dictionary={"frame":_calls,"pause":false,"holdLight":bool(_options.get("hold_light",true)),"forceCenterZero":false,"difficulty":2,"movementSpeed":500,"pace":3,"playerMapX":int(px*_units/1000.0),"playerMapY":int(py*_units/1000.0),"shipHeading":i32(int(float(observer.get("heading",0.0))*2147483648.0/PI)),"sineBoundary":65536}
	environment.merge(_options.get("source_environment",{}),true)
	var events:Array=[]
	var target_calls:=int(floor(accepted_time*_rate+0.000000001))
	while _calls<target_calls:
		environment.frame=_calls
		var result:=step_original_weather(_state,environment,_rng.next)
		_state=result.state;events.append_array(result.externalOperations);_calls+=1
	var delta:=accepted_time-_accepted
	Cloud.advance_clouds(_ring,delta)
	_accepted=accepted_time;_revision+=1
	for graph:Dictionary in _weather_graphs:_compiler.advance_controllers(graph,_accepted)
	for instance:Dictionary in _fog_clocks:instance.clock.advance(_accepted+float(instance.phase))
	_packet=_make_packet(delta,events,observer)
	_packet.source.localWindStrength=original_local_wind_strength(i32(int(px*_units)),i32(int(py*_units)),_state.centers)
	_packet.source.targetWindInput=wind.duplicate(true)
	if record:
		_journal.append({"time":accepted_time,"observer":observer.duplicate(true),"wind":wind.duplicate(true)})
		if _journal.size()%CHECKPOINT_INTERVAL==0:_record()
func _make_packet(delta:float,events:Array,observer:Dictionary)->Dictionary:
	var clouds:Array=[]
	for index in 3:
		var center:Dictionary=_state.centers[index]
		var height:=300 if index==0 else 500
		clouds.append({"index":index,"resource":"stormcloud_sound.nif" if index==0 else "cloud00.nif","sourcePosition":[int(center.x),int(center.y),height],"worldPosition":[float(center.x)/_units,height/_units,-float(center.y)/_units],"modelScale":float(_options.get("model_scale",1.0)),"appTime":_accepted,"controllerState":_compiler.controller_snapshot(_weather_graphs[index])})
	var day:=original_scene_day_mode(int(_state.lightTime))
	var source_time:=Cloud.f32(int(_state.lightTime)*0.009999999776482582)
	if _last_light_time!=int(_state.lightTime):
		_last_light=Daylight.sample(source_time);_last_light_time=int(_state.lightTime)
	var light:=_last_light
	var direction:Array=light.get("lightDirection",[0.3,-0.4,-0.85])
	var rgb:Array=light.get("lightColor",[1.0,1.0,1.0])
	var ambient:Array=light.get("ambient",[.2,.2,.2])
	var brightness:=clampf((float(rgb[0])+float(rgb[1])+float(rgb[2]))/3.0,.08,1.0)
	var target:Dictionary={"direction":[float(direction[0]),float(direction[2]),-float(direction[1])],"color":rgb.duplicate(),"energy":clampf(brightness*1.15,.12,1.15),"ambientColor":ambient.duplicate(),"waterColor":[.018*brightness,.12*brightness,.25*brightness]}
	var fog_clocks:Array=[]
	for instance:Dictionary in _fog_clocks:
		var clock:RefCounted=instance.clock
		fog_clocks.append({"phase":instance.phase,"last":clock.last,"accumulated":clock.accumulated,"started":clock.started})
	if _published_updates!=int(_ring.updates):_published_nodes=_ring.nodes.duplicate(true);_published_updates=int(_ring.updates)
	var published_ring:Dictionary={"nodes":_published_nodes,"accumulator":_ring.accumulator,"updates":_ring.updates,"draws":_ring.draws}
	return {"revision":_revision,"epoch":_epoch,"acceptedTime":_accepted,"sourceCallIndex":_calls,"route":str(observer.get("route",_options.get("route","sailing"))),"source":{"weather":_state.duplicate(true),"rngState":_rng.state,"rngDraws":_rng.draws,"frame":_calls,"cloudDelta":Cloud.f32(delta),"controllerAppTime":_accepted,"fogClocks":fog_clocks,"fogSchedule":"target elapsed+phase; original town-sneak eligibility/appTime unrecovered","stormSubmissionMilliseconds":int(_accepted*1000.0),"externalOperations":events.duplicate(true),"scheduling":{"sourceCallsPerSecond":_rate,"authority":"explicit target cadence; original loop minimum wait 31ms, no fixed rate proof"},"units":{"sourcePositionUnitsPerMetre":_units,"modelMetresPerUnit":0.01,"authority":"explicit target world placement"}},"worldClouds":clouds,"sky":{"ring":published_ring,"appTime":_accepted},"lighting":{"sourceTime":_state.lightTime,"dayMode":day.mode,"skyResource":day.skyResource,"controllerAppTime":source_time,"sourceLightFields":light,"target":target,"adaptation":"original authored TimeOfDay direction/colors; target sun energy and blue water tint retained"}}
func snapshot()->Dictionary:return _packet.duplicate(true)
