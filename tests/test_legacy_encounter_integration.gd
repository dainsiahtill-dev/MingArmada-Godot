extends SceneTree
var assertions := 0
var failures := 0
func check(value: bool, detail: String) -> void:
	assertions+=1
	if not value: failures+=1; print("FAIL ",detail)
func sea(_x: float,_z: float) -> float: return -20.0
func career_checkpoint(Runtime,index: int):
	var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
	var r = Runtime.new(); r.configure(sea,{"initialDock":true})
	check(r.adopt_save(fixture.careerCheckpoints[str(index)]).ok,"source valid career checkpoint")
	return r
func move_treasure(r,request: Dictionary) -> void:
	var state: Dictionary = request.state; var from: Dictionary = state.position; var goal: Dictionary = state.treasure
	var queue: Array = [{"point":from,"moves":[]}]; var seen := {}; seen[str(from.x)+":"+str(from.y)] = true
	var route: Array = []
	while not queue.is_empty():
		var item: Dictionary = queue.pop_front(); var p: Dictionary = item.point
		if p.x==goal.x and p.y==goal.y: route = item.moves; break
		for direction in ["up","down","left","right"]:
			var delta: Vector2i = {"up":Vector2i(0,-1),"down":Vector2i(0,1),"left":Vector2i(-1,0),"right":Vector2i(1,0)}[direction]
			var x: int = p.x+delta.x; var y: int = p.y+delta.y; var key := str(x)+":"+str(y)
			if x<0 or x>=state.width or y<0 or y>=state.height or state.terrain[y][x]=="wall" or x==state.guard.x and y==state.guard.y or seen.has(key): continue
			seen[key] = true; var moves: Array = item.moves.duplicate(); moves.append(direction); queue.append({"point":{"x":x,"y":y},"moves":moves})
	check(not route.is_empty(),"real treasure grid has navigable route")
	for direction in route: check(r.command({"type":"encounter-action","id":request.id,"action":{"type":"move","direction":direction}}).ok,"native treasure movement")
	check(r.command({"type":"encounter-action","id":request.id,"action":{"type":"dig"}}).ok,"native treasure dig")
func win_land(r,request: Dictionary) -> void:
	var model = r.encounter_coordinator._model
	for _turn in 30:
		if model.state.phase!="active": break
		var players: Array = model.state.units.filter(func(u): return u.side=="player").duplicate(true)
		for player: Dictionary in players:
			if model.state.phase!="active": break
			r.command({"type":"encounter-action","id":request.id,"action":{"type":"select","id":player.id}})
			var current = model.selected()
			if current==null: continue
			var enemies: Array = model.state.units.filter(func(u): return u.side=="enemy")
			var chosen: Dictionary = {}; var best := INF
			for y in range(1,6):
				for x in range(1,8):
					var path = model.path_to(current,{"x":x,"y":y})
					if path==null or path.size()>current.movesLeft: continue
					var proxy: Dictionary = current.duplicate(); proxy.x=x; proxy.y=y
					var quality := INF
					for enemy: Dictionary in enemies: quality = minf(quality,-20+model.distance(proxy,enemy) if model.can_attack(proxy,enemy) else model.approach_distance(proxy,enemy))
					quality += path.size()*.01
					if quality<best: best=quality; chosen={"x":x,"y":y}
			if not chosen.is_empty(): r.command({"type":"encounter-action","id":request.id,"action":{"type":"move","x":chosen.x,"y":chosen.y}})
			for enemy: Dictionary in enemies:
				if model.can_attack(model.selected(),enemy): r.command({"type":"encounter-action","id":request.id,"action":{"type":"attack","id":enemy.id}}); break
		if model.state.phase=="active": r.command({"type":"encounter-action","id":request.id,"action":{"type":"end-turn"}})
	check(model.state.phase=="won","native land tactics produce victory")
func test_career_games(Runtime) -> void:
	for disposition in ["capture","plunder","release"]:
		var r = career_checkpoint(Runtime,14); var initial: Dictionary = r.snapshot().adventure
		check(r.command({"type":"start-encounter","kind":"duel","targetId":"pirate-dongshan"}).ok,"career boarding starts")
		var request: Dictionary = r.snapshot().runtime.encounter
		check(request.context.boardingContext.crew==initial.fleet[0].crew,"actual owned boarding crew context")
		for _i in 16:
			if r.snapshot().runtime.encounter.state.phase!="active": break
			r.command({"type":"encounter-action","id":request.id,"action":"thrust"}); r.advance(.45)
		check(r.snapshot().runtime.encounter.result.success,"real duel attacks produce victory")
		check(r.command({"type":"encounter-settle","id":request.id,"disposition":disposition}).ok,"actual boarding "+disposition+" settles")
		var after: Dictionary = r.snapshot()
		check(after.adventure.fleet.size()==initial.fleet.size()+(1 if disposition=="capture" else 0),"source disposition ownership")
		check(after.adventure.player.silver==initial.player.silver+(0 if disposition=="release" else 120),"source disposition loot")
		check(not after.naval.ships.any(func(s): return s.id=="pirate-dongshan"),"captured hostile excluded from native")
		check(not r.command({"type":"encounter-settle","id":request.id,"disposition":disposition}).ok,"duplicate boarding result refused")
		check(r.snapshot()==after,"duplicate boarding has no consequence")
		r.command({"type":"encounter-close","id":request.id}); r.dispose()
	var r = career_checkpoint(Runtime,14); var crew: int = r.snapshot().adventure.fleet[0].crew
	r.command({"type":"start-encounter","kind":"duel","targetId":"pirate-dongshan"}); var request: Dictionary = r.snapshot().runtime.encounter
	r.advance(2); r.command({"type":"encounter-retreat","id":request.id})
	check(r.command({"type":"encounter-settle","id":request.id}).ok,"career duel retreat settles actual injuries")
	check(r.snapshot().adventure.fleet[0].crew==crew-4,"source boarding retreat crew loss")
	r.dispose()
	r = career_checkpoint(Runtime,37); var silver: int = r.snapshot().adventure.player.silver
	check(r.command({"type":"start-encounter","kind":"treasure","targetId":"treasure-cove"}).ok,"three actual clues permit treasure")
	request = r.snapshot().runtime.encounter; move_treasure(r,request)
	check(r.snapshot().runtime.encounter.result.success,"actual treasure found")
	check(r.command({"type":"encounter-settle","id":request.id}).ok,"native treasure reward settles")
	var treasure: Dictionary = r.snapshot()
	check(treasure.adventure.player.silver>silver and treasure.adventure.career.treasureFound==1,"source treasure rewards")
	check(not r.command({"type":"encounter-settle","id":request.id}).ok and r.snapshot()==treasure,"treasure duplicate atomic")
	r.dispose()
	r = career_checkpoint(Runtime,62); var land_before: Dictionary = r.snapshot().adventure
	check(r.command({"type":"start-encounter","kind":"landBattle","targetId":"taiwan-fort"}).ok,"source settled sea guard permits land battle")
	request = r.snapshot().runtime.encounter; win_land(r,request)
	check(r.command({"type":"encounter-settle","id":request.id}).ok,"real land result settles")
	var land_after: Dictionary = r.snapshot()
	check(land_after.adventure.player.silver>land_before.player.silver and "taiwan-fort" in r.voyage.meta.landWon,"source fort reward")
	check(not r.command({"type":"encounter-settle","id":request.id}).ok and r.snapshot()==land_after,"land duplicate atomic")
	r.dispose()
func test_panel_career_encounters(Runtime) -> void:
	for kind in ["banquet","duel"]:
		var r = Runtime.new()
		check(r.configure(sea,{"initialDock":true}).ok,"panel encounter uses real configure "+kind)
		if kind=="duel":
			var fixture = JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/legacy-runtime-reference.json"))
			check(r.adopt_save(fixture.careerCheckpoints["14"]).ok,"panel duel adopts actual career battle")
		r.set_pause("panel",true); var before: Dictionary = r.snapshot()
		check(r.command({"type":"start-encounter","kind":kind,"targetId":"xiamen" if kind=="banquet" else "pirate-dongshan"}).ok,"panel career encounter starts "+kind)
		var packet: Dictionary = r.snapshot().runtime.encounter
		var action: String = packet.state.cues[0].direction if kind=="banquet" else "thrust"
		var delay: float = packet.state.cues[0].time if kind=="banquet" else .45
		check(r.advance(delay)==0 and r.snapshot().runtime.encounter.acceptedSeconds>0,"panel career model clock independent of sea "+kind)
		check(r.command({"type":"encounter-action","id":packet.id,"action":action}).ok,"panel career model action accepted "+kind)
		check(r.snapshot().naval.tick==before.naval.tick and r.snapshot().adventure.elapsedSeconds==before.adventure.elapsedSeconds and r.snapshot().runtime.pauseReasons.has("panel"),"panel retains sea suspension during career model "+kind)
		for reason in ["player","menu","blur","hidden"]:
			r.set_pause(reason,true); var suspended: Dictionary = r.snapshot(); r.advance(1)
			check(not r.command({"type":"encounter-action","id":packet.id,"action":action}).ok and r.snapshot()==suspended,"real pause fences career clock and action "+kind+" "+reason)
			r.set_pause(reason,false)
		r.dispose()
func _initialize() -> void:
	var Runtime = load("res://game/runtime/legacy_runtime.gd")
	check(Runtime != null,"runtime owns encounter authority")
	if Runtime == null: finish(); return
	test_career_games(Runtime)
	test_panel_career_encounters(Runtime)
	var r = Runtime.new(); r.configure(sea,{"initialDock":true})
	var before: Dictionary = r.snapshot()
	var started: Dictionary = r.command({"type":"start-encounter","kind":"banquet","targetId":"xiamen"})
	check(started.ok,"banquet starts from actual port context")
	var packet: Dictionary = r.snapshot().runtime.encounter
	check(packet.kind=="banquet" and packet.state.phase=="active","actual native rhythm model")
	check(r.advance(.5)==0,"sea clock pauses independently during encounter")
	check(r.snapshot().runtime.encounter.acceptedSeconds>.4,"encounter clock accepts own time")
	check(r.snapshot().adventure.elapsedSeconds==before.adventure.elapsedSeconds,"no sea time leaks into docked encounter")
	check(not r.command({"type":"encounter-settle","id":packet.id,"result":{"success":true,"score":999}}).ok,"unfinished model cannot settle forged result")
	r.set_pause("hidden",true); var clock: float = r.snapshot().runtime.encounter.acceptedSeconds; r.advance(1)
	check(r.snapshot().runtime.encounter.acceptedSeconds==clock,"hidden pauses minigame")
	var hidden: Dictionary = r.snapshot()
	check(not r.command({"type":"encounter-action","id":packet.id,"action":"up"}).ok,"hidden rejects minigame callback")
	check(r.snapshot()==hidden,"hidden callback no rhythm mutation")
	r.set_pause("hidden",false)
	for cue: Dictionary in packet.state.cues:
		var state: Dictionary = r.snapshot().runtime.encounter.state
		r.advance(maxf(0,cue.time-state.elapsed))
		check(r.command({"type":"encounter-action","id":packet.id,"action":cue.direction}).ok,"actual rhythm cue accepted")
	r.advance(2)
	var result: Dictionary = r.snapshot().runtime.encounter.result
	check(result.success and result.score>0,"native model produces real banquet victory")
	check(r.command({"type":"encounter-settle","id":packet.id}).ok,"banquet result settles")
	var settled: Dictionary = r.snapshot()
	check(settled.adventure.player.silver==before.adventure.player.silver-30,"source banquet fee exactly once")
	check(settled.adventure.player.fame==before.adventure.player.fame+4,"source normalized perfect score reward")
	check(settled.runtime.encounter.has("settlement"),"banquet canonical presentation settlement exists")
	if settled.runtime.encounter.has("settlement"):
		var social: Dictionary = settled.runtime.encounter.settlement
		check(social.mode=="career" and social.score==100 and social.paid==30,"canonical banquet normalized score and paid fee")
		check(social.before.silver==before.adventure.player.silver and social.after.silver==settled.adventure.player.silver and social.after.fame==settled.adventure.player.fame and social.after.relation==settled.adventure.relations.zheng,"banquet presentation reports actual career before/after")
	check(not r.command({"type":"encounter-settle","id":packet.id}).ok,"duplicate result refused")
	check(r.snapshot()==settled,"duplicate result cannot change reward")
	check(r.command({"type":"encounter-close","id":packet.id}).ok,"settled encounter closes")
	check(not r.command({"type":"start-encounter","kind":"banquet","targetId":"xiamen"}).ok,"career banquet cooldown enforced")
	for kind in ["duel","landBattle","treasure","banquet"]:
		var career: Dictionary = r.snapshot().adventure
		check(r.command({"type":"start-encounter","kind":kind,"targetId":"practice","practice":true}).ok,"practice real "+kind+" starts")
		var request: Dictionary = r.snapshot().runtime.encounter
		check(request.state.kind==kind,"practice owns native "+kind+" model")
		check(not r.command({"type":"encounter-action","id":"stale","action":"thrust"}).ok,"stale callback refused")
		check(r.command({"type":"encounter-retreat","id":request.id}).ok,"native "+kind+" retreat")
		check(r.command({"type":"encounter-settle","id":request.id}).ok,"practice "+kind+" settlement")
		check(r.snapshot().adventure==career,"practice "+kind+" grants no career mutation")
		check(r.command({"type":"encounter-close","id":request.id}).ok,"practice close")
		check(not r.command({"type":"encounter-settle","id":request.id}).ok,"superseded callback refused")
	check(r.command({"type":"start-encounter","kind":"duel","targetId":"practice","practice":true}).ok,"practice retry begins actual model")
	var prior: Dictionary = r.snapshot().runtime.encounter
	r.command({"type":"encounter-retreat","id":prior.id})
	check(r.command({"type":"encounter-retry","id":prior.id}).ok,"practice retry creates new identity")
	check(r.snapshot().runtime.encounter.id!=prior.id and not r.command({"type":"encounter-action","id":prior.id,"action":"thrust"}).ok,"retry supersedes old callback")
	var retired_coordinator = r.encounter_coordinator
	r.dispose()
	check(not retired_coordinator.command({"type":"encounter-settle","id":prior.id}).ok,"dispose fences retained coordinator callback")
	finish()
func finish() -> void:
	print("LEGACY_ENCOUNTER_INTEGRATION_TESTS assertions=",assertions," failures=",failures)
	quit(0 if failures==0 else 1)
