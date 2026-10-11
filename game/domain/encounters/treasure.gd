extends "res://game/domain/encounters/common.gd"
var targetSiteId=""
func _init(world_seed=1,level="normal",target_site_id=null):
	super(world_seed,level);targetSiteId=target_site_id if target_site_id!=null else "treasure-"+str(seed);reset()
func reset():
	random_state=seed;var terrain=terrain_grid();var treasure={"x":6+int(floor(random_value()*2)),"y":4+int(floor(random_value()*2))};var guard={"x":5,"y":1}
	for y in range(1,6):
		for x in range(2,8):
			if y!=5 and x!=treasure.x and random_value()<.27:terrain[y][x]="wall"
	terrain[guard.y][guard.x]="ground";terrain[treasure.y][treasure.x]="ground"
	var revealed=[]
	for _y in 7:revealed.append([false,false,false,false,false,false,false,false,false])
	state={"kind":"treasure","seed":seed,"phase":"active","result":null,"width":9,"height":7,"terrain":terrain,"position":{"x":1,"y":1},"treasure":treasure,"guard":guard,"revealed":revealed,"targetSiteId":targetSiteId,"clue":"行至东岸第%d列、南侧第%d行，古石旁掘土。"%[treasure.x+1,treasure.y+1],"moves":0,"digsLeft":3,"playerHealth":100,"collected":false,"lastEvent":"ready"};reveal()
func move(direction):
	var delta=direction_vector(direction)
	if state.phase!="active" or delta==null:return false
	var next={"x":state.position.x+delta.x,"y":state.position.y+delta.y}
	if not inside(next.x,next.y) or state.terrain[next.y][next.x]=="wall":return false
	if same_point(next,state.guard):
		state.playerHealth=max(0,state.playerHealth-(40 if difficulty=="hard" else 30));state.lastEvent="guard-repelled"
		if state.playerHealth==0:finish("lost",0,100)
		return false
	state.position=next;state.moves+=1;state.lastEvent="moved";reveal();return true
func dig():
	if state.phase!="active" or state.collected:return false
	if same_point(state.position,state.treasure):state.collected=true;state.lastEvent="treasure-found";finish("won",max(50,150-state.moves)+state.digsLeft*20,100-state.playerHealth);return true
	state.digsLeft-=1;state.lastEvent="empty-dig"
	if state.digsLeft==0:finish("lost",0,100-state.playerHealth)
	return false
func reveal():
	for dy in range(-1,2):
		for dx in range(-1,2):
			var x=state.position.x+dx;var y=state.position.y+dy
			if inside(x,y):state.revealed[y][x]=true
func retreat():
	if state.phase!="active":return false
	finish("retreated",0,100-state.playerHealth);return true
