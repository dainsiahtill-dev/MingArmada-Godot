extends RefCounted
## 4DFD30..4E0075 original 30x28-byte ring. Source Z-up scene units.
## Profiles cover recovered finite arithmetic, not the unresolved full strip ABI.
const TABLES = preload("res://assets/data/source_wake/source-tables.json")
const INI_CANDIDATE := {"WakeCreateTime":0.025,"WakeDestroyTime":0.04,"WakeTextureScaling":-750.0,"WakeCreateDistance":20.0,"WakeMaximumWidth":150.0}
const PE_DEFAULT := {"WakeCreateTime":0.05,"WakeDestroyTime":1.95,"WakeTextureScaling":1000.0,"WakeCreateDistance":1.0,"WakeMaximumWidth":300.0}
const CAPACITY := 30
var cfg:Dictionary
var scale:float
var marker:Variant
var points:Array=[]
var head:=0
var total:=0.0
var time:=0.0
var updates:=0
var vertex_count:=58
var last_result:="uninitialized"

static func f32(value:float)->float:return PackedFloat32Array([value])[0]
static func vector(p:Array)->Array:return [f32(p[0]),f32(p[1]),f32(p[2])]

func _init(options:Dictionary={},model_scale:float=0.1,marker_id:Variant=1,position:Array=[100.0,100.0,0.0])->void:
	cfg=INI_CANDIDATE.duplicate() if options.is_empty() else options.duplicate()
	for key:String in cfg:cfg[key]=f32(cfg[key])
	scale=f32(model_scale);marker=marker_id
	for i in CAPACITY:points.append({"p":vector(position),"born":f32(i*float(cfg.WakeCreateTime)),"length":0.0,"v":0.0,"active":false})

func update(position:Array,now:float,marker_id:Variant=null)->bool:
	if position.size()!=3 or not is_finite(now):last_result="invalid-input";return false
	for value:Variant in position:
		if not is_finite(float(value)):last_result="invalid-input";return false
	var p:=vector(position);now=f32(now)
	if now<time:last_result="time-rejected";return false
	if marker_id==null:marker_id=marker
	if marker_id!=marker:
		for point:Dictionary in points:point.active=false
	marker=marker_id;time=now
	var prior:Dictionary=points[head]
	var distance2:=0.0
	for i in 3:distance2+=pow(float(prior.p[i])-float(p[i]),2.0)
	if distance2>1000000.0:
		for point:Dictionary in points:point.active=false
	var distance:=sqrt(distance2)
	var count:=vertex_count/2
	if prior.active:
		if distance<=float(cfg.WakeCreateDistance)*scale:last_result="distance-rejected";return false
		head=(head+1)%CAPACITY
		var current:Dictionary=points[head]
		if current.active:total=f32(total-float(current.length))
		else:count+=1
		var length:=f32(distance)
		points[head]={"p":p,"born":now,"length":length,"v":f32(length/float(cfg.WakeTextureScaling)+float(prior.v)),"active":true}
		total=f32(length+total)
	else:
		points[head]={"p":p,"born":now,"length":0.0,"v":0.0,"active":true};total=0.0;count+=1
	updates+=1;vertex_count=mini(58,maxi(2,2*count));last_result="accepted"
	return true

func ring_bytes()->PackedByteArray:
	var raw:=PackedByteArray();raw.resize(848)
	for i in CAPACITY:
		var point:Dictionary=points[i];var offset:=28*i
		for axis in 3:raw.encode_float(offset+axis*4,float(point.p[axis]))
		raw.encode_float(offset+12,float(point.born));raw.encode_float(offset+16,float(point.length));raw.encode_float(offset+20,float(point.v));raw[offset+24]=1 if point.active else 0
	raw.encode_u32(840,head);raw.encode_float(844,total)
	return raw

static func curve(x:float,curve_scale:float=1.0,offset:float=0.0)->float:
	if not is_finite(x) or x<0.0 or x>1.0:return NAN
	var pixels:Array=TABLES.data.spread
	x=f32(x);var value:float=(pixels.size()-1)*x
	var stored:=f32(value);var left:=int(floor(value));var fraction:=f32(fmod(stored,1.0))
	var weighted_left:=f32(float(pixels[left])*(1.0-fraction))
	var right:=float(pixels[left+1]) if left+1<pixels.size() else 0.0
	return (right*fraction+weighted_left)*f32(1.0/255.0)*f32(curve_scale)+f32(offset)

static func half_width(model_scale:float,fraction:float,age:float,distance_after:float,maximum:float=150.0)->float:
	model_scale=f32(model_scale)
	var domain:=f32(1.0-f32(fraction)*f32(age))
	var curve_scale:=f32(distance_after*f32(0.0025)*250.0)
	var addition:=curve(domain,curve_scale,1.0)
	return f32((f32(maximum)+addition)*model_scale if model_scale>=f32(0.4) else f32(maximum)*model_scale)

static func row_alpha(update_count:int,row_vertex_index:int)->float:
	var startup:=minf(1.0,maxi(update_count-30,0)*f32(0.05))
	return 0.0 if row_vertex_index<=2 else f32(startup*(60-row_vertex_index)*f32(1.0/60.0))

static func profile_ratios(input:Dictionary)->Dictionary:
	var age:=clampf(f32((float(input.now)-float(input.born))/float(input.destroy_time)),0.0,1.0)
	var denominator:=float(input.total)+float(input.get("head_offset",0.0))
	var fraction:=clampf(f32(float(input.distance_before)/denominator),0.0,1.0) if denominator!=0.0 else 0.0
	return {"age":age,"fraction":fraction,"domain":f32(1.0-fraction*age),"distance_after":f32(float(input.distance_before)+float(input.point_length)),"native_equivalent":denominator!=0.0}

func profile()->Array:
	var distance:=0.0;var rows:Array=[]
	for row in CAPACITY:
		var point:Dictionary=points[posmod(head-row,CAPACITY)]
		if not point.active:rows.append({"row":row,"active":false,"alpha":0.0});continue
		var ratios:=profile_ratios({"now":time,"born":point.born,"destroy_time":cfg.WakeDestroyTime,"distance_before":distance,"total":total,"point_length":point.length})
		distance=ratios.distance_after
		var record:Dictionary={"row":row,"active":true,"position":point.p,"born":point.born,"length":point.length,"age_clamped":ratios.age,"spread_domain":ratios.domain,"half_width":half_width(scale,ratios.fraction,ratios.age,distance,cfg.WakeMaximumWidth),"alpha":row_alpha(updates,row*2),"uv":[[0.0,point.v],[1.0,point.v]]}
		if not ratios.native_equivalent:record.diagnostic_adaptation={"kind":"zero_length_ratio_fallback","native_equivalent":false,"native_fraction_domain":"NaN 0xFFC00000","original_nan_lut":"not_executed"}
		rows.append(record)
	return rows
