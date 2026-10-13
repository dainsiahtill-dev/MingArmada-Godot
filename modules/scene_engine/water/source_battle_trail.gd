extends RefCounted
## Original 4756B0 selected 90-word history and exact 21 draw argument arrays.
const TABLES=preload("res://assets/data/source_wake/source-tables.json")
static func signed(value:int)->int:return ((value+2147483648)&0xffffffff)-2147483648
static func add(a:int,b:int)->int:return signed(a+b)
static func mul(a:int,b:int)->int:return signed(a*b)
static func divi(a:int,b:int)->int:return signed(int(float(a)/b))
static func fixed_trig(amount:int,angle:int,boundary:int)->int:
	amount=signed(amount);angle=signed(angle)
	if angle<0:amount=signed(-amount);angle&=0x7fffffff
	if angle&0x40000000:angle=add(0x7fffffff,-angle)
	var factor:=1
	while abs(amount)>32000:amount=divi(amount,2);factor=add(factor,factor)
	var index:=angle>>22;var fraction:=angle&0x3fffff
	var low:=int(TABLES.data.sine256[index]);var high:=boundary if index==255 else int(TABLES.data.sine256[index+1])
	var interpolated:=add(low,mul(fraction,add(high,-low))>>22)
	return mul(factor,mul(amount,interpolated)>>16)
static func outer_width(size:int,index:int)->int:return divi(divi(divi(mul(add(size,index),1000),12),15),4)
static func core_width(size:int,index:int)->int:return divi(divi(divi(mul(add(add(divi(index,2),size),8),1000),20),15),4)
static func argb(maximum:int,index:int)->int:return ((divi(mul(maximum,90-index),90)<<24)|0xffffff)&0xffffffff
static func flank(point:Dictionary,amount:int,quarter:int,boundary:int)->Array:
	var angle:=add(int(point.heading),quarter)
	return [add(int(point.x),fixed_trig(amount,angle,boundary)),add(int(point.y),fixed_trig(amount,add(angle,0x40000000),boundary))]
static func arguments_for(current:Dictionary,previous:Dictionary,a:int,b:int,row:int,last_uv:int,maximum:int,old_index:int,new_index:int,boundary:int)->Array:
	var left:=flank(current,b,-0x40000000,boundary);var old_left:=flank(previous,a,-0x40000000,boundary)
	var old_right:=flank(previous,a,0x40000000,boundary);var right:=flank(current,b,0x40000000,boundary);var z:=row+2
	var out:Array=[left[0],left[1],z,old_left[0],old_left[1],z,old_right[0],old_right[1],z,right[0],right[1],z,0,last_uv,0,1000,1000,1000,1000,last_uv,argb(maximum,new_index),argb(maximum,old_index),argb(maximum,old_index),argb(maximum,new_index)]
	for i in out.size():out[i]=int(out[i])&0xffffffff
	return out
static func draw(input:Dictionary)->Dictionary:
	var history:Dictionary=input.history.duplicate(true)
	var size:=int(TABLES.data.class_size[int(input.type)]);var boundary:=int(input.sine_boundary)
	if not input.hold_history:
		for key:String in ["x","y","heading"]:
			for i in range(89,0,-1):history[key][i]=history[key][i-1]
		var forward:=divi(divi(mul(size,1000),25),4)
		history.x[0]=add(add(int(input.map_origin_x),fixed_trig(forward,int(input.heading),boundary)),divi(divi(int(input.x),100),4))
		history.y[0]=add(add(int(input.map_origin_y),fixed_trig(forward,add(int(input.heading),0x40000000),boundary)),divi(divi(int(input.y),100),4))
		history.heading[0]=int(input.heading)
	var phase:=int(input.tick)%15;var calls:Array=[]
	var previous:Dictionary={"x":history.x[0],"y":history.y[0],"heading":history.heading[0]}
	for row in 7:
		var selected:=89 if row==6 else phase+15*row;var old_index:=0 if row==0 else phase+15*row-15
		var current:Dictionary={"x":history.x[selected],"y":history.y[selected],"heading":history.heading[selected]}
		var width:=outer_width(size,selected);var old_width:=divi(width,2) if row==0 else outer_width(size,old_index)
		var last_uv:=divi(mul(phase,1000),15) if row==6 else 0
		calls.append(arguments_for(current,previous,old_width,width,row,last_uv,160,old_index,selected,boundary))
		calls.append(arguments_for(current,previous,old_width,width,row,last_uv,255,old_index,selected,boundary))
		var core:=core_width(size,selected);var old_core:=core if row==0 else core_width(size,old_index)
		calls.append(arguments_for(current,previous,old_core,core,row,last_uv,255,old_index,selected,boundary));previous=current
	return {"history":history,"draw_arguments":calls}
