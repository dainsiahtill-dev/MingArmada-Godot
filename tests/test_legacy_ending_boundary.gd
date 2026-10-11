extends "res://tests/test_legacy_adventure.gd"
var assertions=0
func boundary_check(ok,message):
	assertions+=1
	check(ok,message)
func _initialize():
	var script=load("res://game/domain/legacy/adventure_session.gd")
	var strings=load("res://game/domain/legacy/utf16_text.gd")
	var fixture=parse_json(FileAccess.get_file_as_string("res://tests/fixtures/legacy-reference.json"))
	var count=0
	for item in fixture.saveCases:
		if not item.name.begins_with("utf16-ending-"):continue
		count+=1
		var session=script.new({"name":"原生恢复前船长"})
		var before=session.serialize();var before_state=session.snapshot()
		var accepted=session.restore(item.json,null,true)
		boundary_check(accepted==item.ok,"source ending boundary acceptance "+item.name)
		if not accepted:
			boundary_check(session.serialize()==before,"rejected ending keeps state and metadata bytes "+item.name)
			boundary_check(equal(session.snapshot(),before_state),"rejected ending keeps live snapshot "+item.name)
		else:
			var original=parse_json(item.json,true)
			boundary_check(equal(strings.utf16_units(session.snapshot().career.ending),item.endingUnits),"accepted ending retains exact source units "+item.name)
			var serialized=session.serialize();var saved=parse_json(serialized)
			boundary_check(equal(saved.state,original.state) and equal(saved.meta,original.meta),"accepted ending serializes complete source envelope "+item.name)
			var restored=script.new()
			boundary_check(restored.restore(serialized),"serialized exceptional ending restores via raw JSON API "+item.name)
			boundary_check(equal(strings.utf16_units(restored.snapshot().career.ending),item.endingUnits),"raw JSON ending round trip preserves source units "+item.name)
	boundary_check(count==10,"all ten frozen source ending boundaries exercised")
	print("LEGACY_ENDING_BOUNDARY_", "PASS" if failures==0 else "FAIL", " assertions=", assertions," cases=",count," failures=",failures)
	quit(0 if failures==0 else 1)
