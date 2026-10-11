extends "res://tests/test_legacy_adventure.gd"
func _initialize():
	var f=parse_json(FileAccess.get_file_as_string("res://tests/fixtures/encounter-reference.json"))
	for scenario in f.scenarios:
		var script=load("res://game/domain/encounters/"+scenario.kind+".gd")
		check(script!=null,"native "+scenario.kind+" exists")
		if script==null:continue
		var e=script.new(scenario.args[0],scenario.args[1],scenario.args[2]) if scenario.args.size()==3 else script.new(scenario.args[0],scenario.args[1])
		check(equal(e.snapshot(),scenario.initial),scenario.kind+" full initial")
		for i in scenario.steps.size():
			var step=scenario.steps[i];var result=e.callv(step.method,step.args)
			if step.has("result"):check(equal(result,step.result),scenario.kind+" result "+str(i))
			check(equal(e.snapshot(),step.state),scenario.kind+" full state "+str(i))
	var duel=load("res://game/domain/encounters/duel.gd")
	for item in f.invalidBoarding:
		var invalid=duel.new(1,"normal",item.context)
		check(invalid.get("last_error")!=null and not str(invalid.get("last_error")).is_empty(),"invalid boarding context rejected")
	for kind in ["duel","banquet"]:
		var script=load("res://game/domain/encounters/"+kind+".gd");var coarse=script.new(9);var fine=script.new(9)
		coarse.step(8)
		for _i in 480:fine.step(1.0/60)
		check(equal(coarse.snapshot(),fine.snapshot()),kind+" frame chunk independence")
	print("encounter source golden: ","PASS" if failures==0 else "FAIL"," (",failures,")")
	quit(0 if failures==0 else 1)
