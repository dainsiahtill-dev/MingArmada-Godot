extends "res://game/domain/encounters/common.gd"
var exact_elapsed=0.0
var time_compensation=0.0
func _init(world_seed=1,level="normal"):super(world_seed,level);reset()
func reset():
	exact_elapsed=0;time_compensation=0;random_state=seed
	var count=20 if difficulty=="hard" else 10 if difficulty=="easy" else 14;var interval=.6 if difficulty=="hard" else 1 if difficulty=="easy" else .8;var cues=[]
	for id in count:cues.append({"id":id,"direction":["up","down","left","right"][int(floor(random_value()*4))],"time":floor((1+id*interval)*1000+.5)/1000.0,"status":"pending"})
	state={"kind":"banquet","seed":seed,"phase":"active","result":null,"elapsed":0,"duration":cues[-1].time+1,"cues":cues,"combo":0,"maxCombo":0,"score":0,"hits":0,"mistakes":0,"hitWindow":.13 if difficulty=="hard" else .26 if difficulty=="easy" else .19,"socialReward":0,"lastEvent":"ready"}
func step(seconds):
	if state.phase!="active" or not finite_number(seconds) or seconds<=0:return
	var adjusted=seconds-time_compensation;var total=exact_elapsed+adjusted;time_compensation=(total-exact_elapsed)-adjusted;exact_elapsed=total;state.elapsed=min(state.duration,floor(exact_elapsed*1e9+.5)/1e9)
	for cue in state.cues:
		if cue.status=="pending" and state.elapsed>cue.time+state.hitWindow+1e-8:cue.status="missed";state.combo=0;state.mistakes+=1;state.lastEvent="missed"
	if state.elapsed>=state.duration:
		var success=state.hits>=ceil(state.cues.size()*.6);state.socialReward=floor(5+15.0*state.hits/state.cues.size()+.5) if success else 0;finish("won" if success else "lost",state.score,0)
func action(direction):
	if state.phase!="active" or direction_vector(direction)==null:return false
	var cue=null
	for c in state.cues:
		if c.status=="pending" and abs(c.time-state.elapsed)<=state.hitWindow+1e-8:cue=c;break
	if cue==null:
		for c in state.cues:
			if c.status!="pending" and abs(c.time-state.elapsed)<=state.hitWindow+1e-8:return false
		state.combo=0;state.mistakes+=1;state.lastEvent="off-beat";return false
	if cue.direction!=direction:cue.status="missed";state.combo=0;state.mistakes+=1;state.lastEvent="wrong-gesture";return false
	cue.status="hit";state.hits+=1;state.combo+=1;state.maxCombo=max(state.maxCombo,state.combo);var precise=abs(cue.time-state.elapsed)<=state.hitWindow/2;state.score+=(100 if precise else 60)+min(50,(state.combo-1)*5);state.lastEvent="perfect" if precise else "good";return true
