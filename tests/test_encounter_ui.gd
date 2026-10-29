extends SceneTree
var failures=0
var assertions=0
var emitted: Array=[]
const Duel=preload("res://game/domain/encounters/duel.gd")
const Land=preload("res://game/domain/encounters/land_battle.gd")
const Treasure=preload("res://game/domain/encounters/treasure.gd")
const Banquet=preload("res://game/domain/encounters/banquet.gd")
func check(value,message):
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",message)
func _initialize():call_deferred("run")
func press(ui,id):
	var b=ui.find_child(id,true,false)
	check(b is Button and not b.disabled,"enabled encounter Control "+id)
	if b is Button and not b.disabled:b.pressed.emit()
func run():
	var path="res://game/ui/encounters/encounter_interface.gd"
	check(ResourceLoader.exists(path),"four-game native encounter interface exists")
	if not ResourceLoader.exists(path):finish();return
	var script=load(path);check(script!=null and script.can_instantiate(),"encounter UI compiles")
	if not script or not script.can_instantiate():finish();return
	var ui=script.new();root.add_child(ui);await process_frame
	ui.command_requested.connect(func(intent):emitted.append(intent))
	var models={"duel":Duel.new(1661),"landBattle":Land.new(1661),"treasure":Treasure.new(1661),"banquet":Banquet.new(1661)}
	for kind in models:
		var model=models[kind]
		var packet={"id":kind,"generation":1,"kind":kind,"state":model.snapshot(),"practice":false,"settled":false}
		ui.apply_snapshot(packet,9);check(ui.visible,"actual encounter panel visible")
		var panel: PanelContainer = ui.find_child("encounter_panel",true,false)
		check(panel != null and panel.get_theme_stylebox("panel").has_method("get_edge_style"),kind+" encounter has generated outer frame")
		if kind=="duel":
			for action in ["high","low","thrust","guard-high","guard-low","parry","dodge"]:
				press(ui,"duel_"+action);check(emitted.back().action==action,"original duel action "+action)
				check(not emitted.back().has("result") and not emitted.back().has("injury"),"UI cannot forge result")
			check(ui.find_child("duel_stats",true,false).text.contains("体力"),"live health stamina timers")
			model.step(.8);packet.state=model.snapshot();ui.apply_snapshot(packet,10)
			check(ui.find_child("duel_telegraph",true,false).text.contains("秒"),"actual source action window")
		elif kind=="landBattle":
			check(ui.find_child("grid",true,false).get_child_count()==63,"9x7 native terrain")
			press(ui,"cell_1_4");check(emitted.back().action=={"type":"select","id":"player-musketeer"},"select friendly actual unit")
			press(ui,"cell_2_2");check(emitted.back().action=={"type":"move","x":2,"y":2},"source cell move")
			press(ui,"cell_7_2");check(emitted.back().action=={"type":"attack","id":"enemy-melee"},"source enemy target")
			press(ui,"end_turn");check(emitted.back().action.type=="end-turn","actual turn action")
			check(model.snapshot()==packet.state,"UI never advances battle")
		elif kind=="treasure":
			check(ui.find_child("cell_7_5",true,false).text=="？","fog hides unrevealed terrain and treasure")
			for direction in ["up","down","left","right"]:press(ui,"move_"+direction);check(emitted.back().action=={"type":"move","direction":direction},"source movement "+direction)
			press(ui,"dig");check(emitted.back().action.type=="dig","dig emits no found result")
		else:
			for direction in ["up","down","left","right"]:press(ui,"gesture_"+direction);check(emitted.back().action==direction,"source rhythm direction")
			model.step(model.state.cues[0].time);model.action(model.state.cues[0].direction);packet.state=model.snapshot();ui.apply_snapshot(packet,11)
			check(ui.find_child("banquet_stats",true,false).text.contains("100"),"actual perfect score displayed")
		press(ui,"retreat");check(emitted.back().type=="encounter-retreat" and emitted.back().id==kind,"identity fenced retreat")
		model.retreat();packet.state=model.snapshot();ui.apply_snapshot(packet,12)
		press(ui,"settle");check(emitted.back().type=="encounter-settle" and not emitted.back().has("result"),"actual settlement identity only")
		check(ui.find_child("retry",true,false).disabled,"career retry forbidden")
		packet.practice=true;packet.settled=true;ui.apply_snapshot(packet,13);press(ui,"retry");check(emitted.back().type=="encounter-retry","practice retry distinguished")
	var stale=ui.find_child("retry",true,false);var count=emitted.size();ui.apply_snapshot({"id":"next","generation":2,"kind":"duel","state":Duel.new().snapshot()},14);stale.pressed.emit();check(emitted.size()==count,"superseded result cannot retry")
	verify_original_controls(ui)
	verify_career_banquet(ui)
	await verify_layout(ui)
	ui.free();await process_frame;finish()
func verify_original_controls(ui):
	var decoded=load("res://game/domain/legacy/json_numbers.gd").new().decode(FileAccess.get_file_as_string("res://tests/fixtures/encounter-reference.json"));check(decoded.ok,"source encounter oracle exact decoder");var reference=decoded.value;var generation=10;var actions=0;var refusals=0
	for scenario in reference.scenarios:
		generation+=1;var model
		match scenario.kind:
			"duel":model=Duel.new.callv(scenario.args)
			"land_battle":model=Land.new.callv(scenario.args)
			"treasure":model=Treasure.new.callv(scenario.args)
			"banquet":model=Banquet.new.callv(scenario.args)
		var revision=0
		for step in scenario.steps:
			revision+=1;ui.apply_snapshot({"id":"oracle-"+str(generation),"generation":generation,"kind":model.state.kind,"state":model.snapshot(),"difficulty":model.difficulty,"practice":true},revision)
			var button=null;var action=null
			if step.method=="action" and step.args[0] in ["high","low","thrust","guard-high","guard-low","parry","dodge"]:button=ui.find_child("duel_"+step.args[0],true,false);action=step.args[0]
			elif step.method=="action" and step.args[0] in ["up","down","left","right"]:button=ui.find_child("gesture_"+step.args[0],true,false);action=step.args[0]
			elif step.method=="move" and model.state.kind=="treasure" and step.args[0] in ["up","down","left","right"]:button=ui.find_child("move_"+step.args[0],true,false);action={"type":"move","direction":step.args[0]}
			elif step.method=="dig":button=ui.find_child("dig",true,false);action={"type":"dig"}
			elif step.method=="endTurn":button=ui.find_child("end_turn",true,false);action={"type":"end-turn"}
			elif step.method=="move" and model.state.kind=="landBattle" and step.args[0]>=0 and step.args[0]<9 and step.args[1]>=0 and step.args[1]<7:
				var occupied=false
				for unit in model.state.units:
					if unit.x==step.args[0] and unit.y==step.args[1]:occupied=true
				if not occupied:button=ui.find_child("cell_%s_%s"%[step.args[0],step.args[1]],true,false);action={"type":"move","x":step.args[0],"y":step.args[1]}
			elif step.method in ["select","attack"] and model.state.kind=="landBattle":
				for unit in model.state.units:
					if unit.id==step.args[0] and ((step.method=="select" and unit.side=="player") or (step.method=="attack" and unit.side=="enemy")):button=ui.find_child("cell_%s_%s"%[unit.x,unit.y],true,false);action={"type":step.method,"id":unit.id}
			if button is Button:
				var before=emitted.size();button.pressed.emit()
				if not button.disabled:
					check(emitted.size()==before+1 and emitted.back().action==action,"original source Control action "+scenario.kind+":"+step.method);check(emitted.back().generation==generation and emitted.back().expectedRevision==revision,"original source callback fence");actions+=1
				else:check(step.get("result",false)==false or model.state.phase!="active","source rejection corresponds to disabled action");refusals+=1
			model.callv(step.method,step.args)
			check(equal(model.snapshot(),step.state),"original source model oracle "+scenario.kind+":"+step.method)
			if model.state.kind=="duel" and model.state.phase=="won":
				ui.apply_snapshot({"id":"oracle-"+str(generation),"generation":generation,"kind":"duel","state":model.snapshot(),"practice":false,"settled":false},revision)
				check(ui.find_child("settle",true,false).disabled,"career boarding requires explicit disposition")
				for disposition in ["capture","plunder","release"]:
					press(ui,"settle_"+disposition);check(emitted.back().disposition==disposition and not emitted.back().has("success") and not emitted.back().has("injury"),"actual source boarding disposition "+disposition)
	check(actions>100 and refusals>5,"four-game source actions and rejection oracles exercised")
	print("ENCOUNTER_UI_SOURCE actions=",actions," disabled=",refusals)
func equal(a,b):
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:return abs(float(a)-float(b))<=1e-8
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for key in a:
			if not b.has(key) or not equal(a[key],b[key]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equal(a[i],b[i]):return false
		return true
	return a==b
func verify_career_banquet(ui):
	var runtime=load("res://game/runtime/legacy_runtime.gd").new();check(runtime.configure(func(_x,_z):return -30.0).ok,"real banquet runtime configures")
	check(runtime.command({"type":"start-encounter","kind":"banquet","targetId":"xiamen"}).ok,"actual career banquet starts")
	runtime.advance(30);var encounter=runtime.snapshot().runtime.encounter
	check(runtime.command({"type":"encounter-settle","id":encounter.id}).ok,"actual career banquet settles")
	var packet=runtime.snapshot();ui.apply_snapshot(packet.runtime.encounter,packet.runtime.revision)
	var label=ui.find_child("settlement_notice",true,false)
	check(label.text.contains("30") and label.text.contains("士气") and label.text.contains("生涯"),"actual normalized career score and paid gains visible")
	runtime.dispose()
func verify_layout(ui):
	for width in [1600,600,400]:
		root.size=Vector2i(width,900);root.content_scale_size=Vector2i.ZERO
		ui.apply_snapshot({"id":"layout","generation":1,"kind":"landBattle","state":Land.new().snapshot()})
		for frame in 8:await process_frame
		for id in ["end_turn","retreat","encounter_pause"]:
			var button=ui.find_child(id,true,false);check(button.size.x>=76 and button.size.y<60,"encounter actual action text fits "+id+":"+str(width))
		var cell=ui.find_child("cell_1_2",true,false);var style=cell.get_theme_stylebox("normal");var available=cell.size.x-style.get_content_margin(SIDE_LEFT)-style.get_content_margin(SIDE_RIGHT)
		check(available>=cell.get_theme_default_font().get_string_size("我刀",HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,"actual Chinese unit glyphs fit 9-column grid "+str(width))
func finish():print("ENCOUNTER_UI_TESTS assertions=",assertions," failures=",failures);quit(1 if failures else 0)
