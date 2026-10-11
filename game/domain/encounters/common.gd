extends RefCounted
var state={}
var seed=1
var difficulty="normal"
var random_state=1
var last_error=""
func _init(world_seed=1,level="normal"):
	seed=(int(world_seed)&0xffffffff) if typeof(world_seed) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(world_seed)) else 1
	difficulty=level if level in ["easy","hard"] else "normal"
	random_state=seed
func random_value():
	random_state=(random_state*1664525+1013904223)&0xffffffff
	return float(random_state)/4294967296.0
func snapshot():return state.duplicate(true)
func finite_number(value):return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
func bounded_number(value,maximum):return finite_number(value) and value>=0 and value<=maximum
func finish(phase,score,injury):
	if state.phase!="active":return
	state.phase=phase;state.result={"success":phase=="won","score":max(0,floor(float(score)+0.5)),"injury":clamp(floor(float(injury)+0.5),0,100)}
func retreat():
	if state.phase!="active":return false
	finish("retreated",0,0);return true
func terrain_grid():
	var terrain=[]
	for y in 7:
		var row=[]
		for x in 9:row.append("wall" if x==0 or y==0 or x==8 or y==6 else "ground")
		terrain.append(row)
	return terrain
func inside(x,y):return typeof(x) in [TYPE_INT,TYPE_FLOAT] and typeof(y) in [TYPE_INT,TYPE_FLOAT] and x==floor(x) and y==floor(y) and x>=0 and x<9 and y>=0 and y<7
func distance(a,b):return abs(a.x-b.x)+abs(a.y-b.y)
func same_point(a,b):return a.x==b.x and a.y==b.y
func direction_vector(direction):return {"up":{"x":0,"y":-1},"down":{"x":0,"y":1},"left":{"x":-1,"y":0},"right":{"x":1,"y":0}}.get(direction)
