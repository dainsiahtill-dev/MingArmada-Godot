extends "res://game/domain/encounters/common.gd"
func _init(world_seed=1,level="normal"):super(world_seed,level);reset()
func reset():
	var terrain=terrain_grid()
	for y in [1,2,4,5]:terrain[y][4]="wall"
	terrain[3][3]="cover";terrain[3][5]="cover";terrain[4][6]="cover"
	var hp=20 if difficulty=="hard" else -15 if difficulty=="easy" else 0
	state={"kind":"landBattle","seed":seed,"phase":"active","result":null,"width":9,"height":7,"terrain":terrain,"selectedUnitId":"player-melee","turn":1,"lastEvent":"ready","units":[{"id":"player-melee","side":"player","role":"melee","x":1,"y":2,"health":90,"movesLeft":3,"attacksLeft":1},{"id":"player-musketeer","side":"player","role":"musketeer","x":1,"y":4,"health":70,"movesLeft":2,"attacksLeft":1},{"id":"enemy-melee","side":"enemy","role":"melee","x":7,"y":2,"health":80+hp,"movesLeft":3,"attacksLeft":1},{"id":"enemy-musketeer","side":"enemy","role":"musketeer","x":7,"y":4,"health":65+hp,"movesLeft":2,"attacksLeft":1}]}
func select(id):
	if state.phase!="active":return false
	for u in state.units:
		if u.id==id and u.side=="player":state.selectedUnitId=id;return true
	return false
func selected():
	for u in state.units:
		if u.id==state.selectedUnitId and u.side=="player":return u
	return null
func move(x,y):
	var unit=selected()
	if state.phase!="active" or unit==null or not inside(x,y) or same_point(unit,{"x":x,"y":y}):return false
	var route=path_to(unit,{"x":x,"y":y})
	if route==null or route.size()>unit.movesLeft:return false
	unit.x=x;unit.y=y;unit.movesLeft-=route.size();state.lastEvent="moved";return true
func attack(id):
	var unit=selected();var target=null
	for u in state.units:
		if u.id==id:target=u;break
	if state.phase!="active" or unit==null or target==null or target.side!="enemy" or not can_attack(unit,target):return false
	strike(unit,target);return true
func occupied(p,unit,to,ignore_target):
	for u in state.units:
		if same_point(u,p) and not same_point(u,unit) and not (ignore_target and same_point(u,to)):return true
	return false
func path_to(unit,to,ignore_target=false):
	if not inside(to.x,to.y) or state.terrain[to.y][to.x]=="wall" or occupied(to,unit,to,ignore_target):return null
	var queue=[{"point":unit,"path":[]}];var seen={str(unit.x)+","+str(unit.y):true}
	while not queue.is_empty():
		var item=queue.pop_front()
		if same_point(item.point,to):return item.path
		for delta in [[1,0],[0,1],[-1,0],[0,-1]]:
			var p={"x":item.point.x+delta[0],"y":item.point.y+delta[1]};var key=str(p.x)+","+str(p.y)
			if not inside(p.x,p.y) or seen.has(key) or state.terrain[p.y][p.x]=="wall" or occupied(p,unit,to,ignore_target):continue
			seen[key]=true;queue.append({"point":p,"path":item.path+[p]})
	return null
func can_attack(unit,target):
	if unit.attacksLeft<=0 or unit.side==target.side or distance(unit,target)>(1 if unit.role=="melee" else 4):return false
	if unit.role=="melee":return true
	var x=unit.x;var y=unit.y;var dx=target.x-x;var dy=target.y-y;var nx=abs(dx);var ny=abs(dy);var sx=sign(dx);var sy=sign(dy);var ix=0;var iy=0
	while ix<nx or iy<ny:
		var decision=(1+2*ix)*ny-(1+2*iy)*nx
		if decision==0:
			if state.terrain[y][x+sx]=="wall" or state.terrain[y+sy][x]=="wall":return false
			x+=sx;y+=sy;ix+=1;iy+=1
		elif decision<0:x+=sx;ix+=1
		else:y+=sy;iy+=1
		if state.terrain[y][x]=="wall":return false
	return true
func approach_distance(unit,target):
	var p=path_to(unit,target,true);return p.size() if p!=null else 100
func endTurn():
	if state.phase!="active":return false
	for enemy in state.units.filter(func(u):return u.side=="enemy"):
		if state.phase!="active":break
		enemy.movesLeft=3 if enemy.role=="melee" else 2;enemy.attacksLeft=1
		var targets=state.units.filter(func(u):return u.side=="player")
		targets.sort_custom(func(a,b):return distance(enemy,a)<distance(enemy,b) if distance(enemy,a)!=distance(enemy,b) else a.health<b.health)
		var target=null
		for t in targets:
			if can_attack(enemy,t):target=t;break
		if target==null:
			var options=[]
			for y in range(1,6):
				for x in range(1,8):
					var route=path_to(enemy,{"x":x,"y":y})
					if route==null or route.size()>enemy.movesLeft:continue
					var proxy=enemy.duplicate();proxy.x=x;proxy.y=y;var quality=INF
					for t in targets:quality=min(quality,-10+distance(proxy,t) if can_attack(proxy,t) else approach_distance(proxy,t))
					options.append({"point":{"x":x,"y":y},"path":route,"quality":quality,"ordinal":options.size()})
			options.sort_custom(func(a,b):
				if a.quality!=b.quality:return a.quality<b.quality
				if a.path.size()!=b.path.size():return a.path.size()<b.path.size()
				var ay=(int(a.point.y)+seed+int(state.turn))%7;var by=(int(b.point.y)+seed+int(state.turn))%7
				return ay<by if ay!=by else a.ordinal<b.ordinal)
			if not options.is_empty():enemy.x=options[0].point.x;enemy.y=options[0].point.y;enemy.movesLeft-=options[0].path.size()
			targets=state.units.filter(func(u):return u.side=="player")
			for t in targets:
				if can_attack(enemy,t):target=t;break
		if target!=null:strike(enemy,target)
	if state.phase=="active":
		state.turn+=1
		for u in state.units.filter(func(u):return u.side=="player"):u.movesLeft=3 if u.role=="melee" else 2;u.attacksLeft=1
		if selected()==null:
			state.selectedUnitId=null
			for u in state.units:
				if u.side=="player":state.selectedUnitId=u.id;break
	return true
func end_turn():return endTurn()
func strike(unit,target):
	var damage=30 if unit.role=="melee" else 13 if state.terrain[target.y][target.x]=="cover" else 26
	target.health=max(0,target.health-damage);unit.attacksLeft-=1;state.lastEvent=unit.id+"-attacked-"+target.id;state.units=state.units.filter(func(u):return u.health>0)
	if state.units.filter(func(u):return u.side=="enemy").is_empty():
		var health=0
		for u in state.units:health+=u.health
		finish("won",100+health,injury())
	if state.units.filter(func(u):return u.side=="player").is_empty():finish("lost",0,100)
func injury():
	var health=0.0
	for u in state.units:
		if u.side=="player":health+=u.health
	return floor(100-health/160*100+.5)
func retreat():
	if state.phase!="active":return false
	finish("retreated",0,injury());return true
