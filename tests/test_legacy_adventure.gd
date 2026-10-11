extends SceneTree
var failures=0
func check(ok,message):
	if not ok:failures+=1;push_error(message)
func parse_json(text,encoded_input=false):
	var parsed=load("res://game/domain/legacy/json_numbers.gd").new().decode(text,encoded_input)
	check(parsed.ok,"golden JSON parses with exact binary64 numbers")
	return parsed.value
func equal(a,b):
	if typeof(a) in [TYPE_FLOAT,TYPE_INT] or typeof(b) in [TYPE_FLOAT,TYPE_INT]:
		if typeof(a) not in [TYPE_FLOAT,TYPE_INT] or typeof(b) not in [TYPE_FLOAT,TYPE_INT]:return false
		if not is_finite(float(a)) or not is_finite(float(b)):return false
		if typeof(a)==TYPE_INT and typeof(b)==TYPE_INT:return a==b
		if typeof(a)==TYPE_INT or typeof(b)==TYPE_INT:
			var integral=a if typeof(a)==TYPE_INT else b;var floating=b if typeof(a)==TYPE_INT else a
			return floating==floor(floating) and floating>=-9223372036854775808.0 and floating<9223372036854775808.0 and integral==int(floating)
		if float(a)==floor(float(a)) or float(b)==floor(float(b)):return a==b
		return abs(float(a)-float(b))<=1e-12*max(abs(float(a)),abs(float(b)))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size():return false
		for k in a:
			if not b.has(k) or not equal(a[k],b[k]):return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not equal(a[i],b[i]):return false
		return true
	return a==b
func _initialize():
	check(not equal(4294967295,4294967294),"numeric oracle rejects adjacent uint32 IDs")
	check(not equal(4294967295.0,4294967294.0),"numeric oracle rejects adjacent parsed uint32 IDs")
	check(not equal(9007199254740993,9007199254740992.0),"numeric oracle retains native integer precision")
	check(not equal(INF,INF) and not equal(NAN,NAN),"numeric oracle rejects nonfinite values")
	var script=load("res://game/domain/legacy/adventure_session.gd")
	check(script!=null,"native legacy implementation exists")
	if script!=null:
		var f=parse_json(FileAccess.get_file_as_string("res://tests/fixtures/legacy-reference.json"))
		for item in f.constructors:
			var candidate=script.new(item.options,true)
			check(candidate.last_error.is_empty()==item.ok,"source constructor acceptance")
			if item.ok:check(equal(candidate.snapshot(),item.state),"source constructor state")
		for scenario in f.scenarios:
			var s=script.new(scenario.options,true)
			if scenario.get("fromSave",false):check(s.restore(scenario.initialSave,null,true),scenario.name+" initial saved voyage")
			check(equal(s.snapshot(),scenario.initial),scenario.name+" initial full state")
			check(equal(s.navalSetup(),scenario.initialNaval),scenario.name+" initial naval setup")
			check(equal(s.ambientNavalSetup(),scenario.initialAmbient),scenario.name+" initial ambient setup")
			check(equal(s.ambientWaypoints(),scenario.initialWaypoints),scenario.name+" initial waypoints")
			for i in scenario.steps.size():
				var step=scenario.steps[i]
				if step.kind=="command":
					var untouched=s.serialize();check(equal(s.preview(step.args),step.preview),scenario.name+" preview "+str(i));check(s.serialize()==untouched,scenario.name+" preview atomic "+str(i))
					check(equal(s.command(step.args),step.result),scenario.name+" result "+str(i)+" "+step.args.type)
				elif step.kind=="sync":s.syncNaval(step.args.snapshot,step.args.events)
				elif step.kind=="sync-docked":s.syncDockedFleet(step.args)
				elif step.kind=="paused":s.setPaused(step.args)
				elif step.kind=="advance":s.advance(step.args)
				check(equal(s.snapshot(),step.state),scenario.name+" full state "+str(i))
				check(equal(parse_json(s.serialize()),step.save),scenario.name+" full meta "+str(i))
				check(equal(s.navalSetup(),step.naval),scenario.name+" naval setup "+str(i))
				check(equal(s.ambientNavalSetup(),step.ambient),scenario.name+" ambient setup "+str(i))
				check(equal(s.ambientWaypoints(),step.waypoints),scenario.name+" ambient waypoints "+str(i))
				check(equal(s.quoteSurrender(),step.quote),scenario.name+" surrender quote "+str(i))
			var before=s.snapshot();var detached=s.snapshot();detached.player.silver=999999
			check(equal(s.snapshot(),before),"snapshot detached")
			var candidate=script.new();check(candidate.commitFrom(s),scenario.name+" valid prepared transaction commits");check(equal(parse_json(candidate.serialize()),parse_json(s.serialize())),scenario.name+" prepared full state and meta commits")
			var untouched=candidate.serialize();var invalid=script.new();invalid.meta.shipSequence=-1
			check(not candidate.commitFrom(invalid) and candidate.serialize()==untouched,"invalid prepared transaction atomic")
		var boarding=script.new();var native=f.scenarios[2].steps[0].args.snapshot.duplicate(true)
		for ship in native.ships:ship.hull=int(ship.maxHull*.8);ship.crew=int(ship.maxCrew*.8);ship.maxHull=int(ship.maxHull);ship.maxCrew=int(ship.maxCrew);ship.visual.position={"x":0,"z":0}
		boarding.syncNaval(native,[])
		check(not boarding.command({"type":"resolve-boarding","targetId":"voc-enemy","success":true,"disposition":"release"}).ok,"integer naval quantities preserve boarding ratios")
	print("legacy source golden: ","PASS" if failures==0 else "FAIL"," (",failures,")")
	quit(0 if failures==0 else 1)
