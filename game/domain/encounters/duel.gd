extends "res://game/domain/encounters/common.gd"
var ticks=0
var remainder=0.0
var next_attack=48
var strike_at=0
var ready_at=0
var defense_until=0
var counter_until=0
var counter_count=0
var context=null
func _init(world_seed=1,level="normal",boarding_context=null):
	super(world_seed,level)
	if boarding_context!=null:
		if not boarding_context is Dictionary or not bounded_number(boarding_context.get("crew"),10000) or not bounded_number(boarding_context.get("enemyCrew"),10000) or not bounded_number(boarding_context.get("morale"),100):last_error="Invalid boarding crew or morale context";return
		context={"crew":boarding_context.crew,"enemyCrew":boarding_context.enemyCrew,"morale":boarding_context.morale}
	reset()
func reset():
	if not last_error.is_empty():return
	random_state=seed;ticks=0;remainder=0.0;next_attack=48;strike_at=0;ready_at=0;defense_until=0;counter_until=0;counter_count=0
	var balance=(context.crew-context.enemyCrew)/max(1.0,context.crew+context.enemyCrew) if context!=null else 0.0
	var attack=floor((1+balance*.25+(context.morale-50)*.003)*1000+.5)/1000.0 if context!=null else 1
	state={"kind":"duel","seed":seed,"phase":"active","result":null,"elapsed":0,"playerHealth":100,"enemyHealth":100,"stamina":50+context.morale/2.0 if context!=null else 100,"enemyGuard":"high" if random_value()<.5 else "low","telegraph":null,"actionWindow":0,"cooldown":0,"playerAction":null,"combo":0,"lastEvent":"ready","boardingContext":context.duplicate(true) if context!=null else null,"attackMultiplier":attack,"staminaRecovery":6.6+context.morale*.066 if context!=null else 13.2}
func action(value):
	if state.is_empty() or value not in ["high","low","thrust","guard-high","guard-low","parry","dodge"] or state.phase!="active" or ticks<ready_at:return false
	var cost=18 if value=="parry" else 22 if value=="dodge" else 8 if value.begins_with("guard") else 14
	if state.stamina<cost:return false
	state.stamina-=cost;state.playerAction=value
	if value in ["high","low","thrust"]:
		var counter=ticks<=counter_until and counter_until>0;var blocked=value==state.enemyGuard
		var damage=max(1,floor(((4 if blocked else 13 if value=="thrust" else 18)+(15 if counter else 0))*state.attackMultiplier+.5))
		state.enemyHealth=max(0,state.enemyHealth-damage);state.lastEvent="counterattack" if counter else "enemy-blocked" if blocked else "hit";state.combo+=1;ready_at=ticks+27;counter_until=0
		if state.enemyHealth==0:finish("won",100+counter_count*25+state.playerHealth,100-state.playerHealth)
	else:
		ready_at=ticks+(8 if value.begins_with("guard") else 15);defense_until=ticks+(72 if value.begins_with("guard") else 14 if value=="parry" else 22);state.lastEvent=value
	refresh_timers();return true
func step(seconds):
	if state.is_empty() or state.phase!="active" or not finite_number(seconds) or seconds<=0:return
	var total=remainder+seconds;var count=int(floor(total*60+1e-8));remainder=max(0,total-count/60.0)
	for _i in count:
		if state.phase!="active":break
		ticks+=1;state.stamina=min(100,floor((state.stamina+state.staminaRecovery/60.0)*100+.5)/100.0)
		if defense_until<ticks and state.playerAction!=null and state.playerAction.begins_with("guard"):state.playerAction=null
		if state.telegraph==null and ticks>=next_attack:
			state.telegraph=["high","low","thrust"][int(floor(random_value()*3))];state.enemyGuard="high" if random_value()<.5 else "low";strike_at=ticks+(30 if difficulty=="hard" else 60 if difficulty=="easy" else 45);state.lastEvent="enemy-windup"
		if state.telegraph!=null and ticks>=strike_at:resolve_strike()
		refresh_timers()
func resolve_strike():
	var defense=state.playerAction if ticks<=defense_until else null;var strike=state.telegraph
	if defense=="parry":counter_until=ticks+54;counter_count+=1;state.stamina=min(100,state.stamina+12);state.lastEvent="parried"
	elif defense=="dodge":state.lastEvent="dodged"
	elif (strike=="high" and defense=="guard-high") or (strike=="low" and defense=="guard-low"):state.stamina=max(0,state.stamina-8);state.lastEvent="blocked"
	else:state.playerHealth=max(0,state.playerHealth-(26 if difficulty=="hard" else 14 if difficulty=="easy" else 20));state.combo=0;state.lastEvent="injured"
	state.telegraph=null;state.playerAction=null;defense_until=0;next_attack=ticks+45+int(floor(random_value()*25))
	if state.playerHealth==0:finish("lost",counter_count*25,100)
func refresh_timers():state.elapsed=ticks/60.0;state.actionWindow=0 if state.telegraph==null else max(0,strike_at-ticks)/60.0;state.cooldown=max(0,ready_at-ticks)/60.0
func retreat():
	if state.is_empty() or state.phase!="active":return false
	finish("retreated",0,100-state.playerHealth);return true
