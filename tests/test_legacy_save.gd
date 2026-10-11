extends "res://tests/test_legacy_adventure.gd"
func _initialize():
	var script=load("res://game/domain/legacy/adventure_session.gd")
	check(script!=null,"native legacy exists")
	if script!=null:
		var f=parse_json(FileAccess.get_file_as_string("res://tests/fixtures/legacy-reference.json"))
		var number_codec=load("res://game/domain/legacy/surrender.gd")
		var strings=load("res://game/domain/legacy/utf16_text.gd");var reader=load("res://game/domain/legacy/json_numbers.gd").new()
		for item in f.stringText:
			var parsed=reader.decode(item.json,true)
			check(parsed.ok==item.ok,"source JSON string acceptance")
			if parsed.ok:
				check(equal(strings.utf16_units(parsed.value),item.units),"exact source UTF16 code units")
				check(strings.source_length(parsed.value)==item.units.size(),"source UTF16 logical length")
				check(number_codec.js_json(parsed.value)==strings.display_text(item.expected),"exact source JSON string writer")
				check(reader.decode(number_codec.js_json(parsed.value)).value==parsed.value,"encoded string round trip")
		for item in f.stringDocuments:
			var parsed=reader.decode(item.json,true);check(parsed.ok,"source string-key document accepted")
			check(number_codec.js_json(parsed.value)==strings.display_text(item.expected),"source string keys without marker collisions")
			check(equal(reader.decode(number_codec.js_json(parsed.value)).value,parsed.value),"source string-key document round trip")
		var nul=strings.from_units([97,0,98]);var surrogate=strings.from_units([97,0xd800,98])
		check(strings.display_text(nul)=="a\\u0000b" and strings.display_text(surrogate)=="a\\ud800b","exceptional display is explicit and lossless state remains separate")
		check(nul!=strings.encode_native("a\uE0000000;b") and surrogate!=strings.encode_native("a\uE000d800;b"),"original private marker cannot collide with exceptional units")
		var marker_name="a\uE0000000;b";var marker_session=script.new({"name":marker_name})
		check(strings.utf16_units(marker_session.snapshot().player.name)==strings.native_units(marker_name),"native constructor escapes original private marker")
		for item in f.numberText:
			var value=PackedByteArray(item.bits).to_float64_array()[0]
			check(number_codec.js_json(value)==item.expected,"exact JS numeric text "+item.expected)
			check(number_codec.float_bits(number_codec.parse_number(item.expected))==number_codec.float_bits(value) or value==0,"exact binary64 decimal round trip "+item.expected)
		for case in f.saveCases:
			var s=script.new();var before=s.serialize();var ok=s.restore(case.json,null,true)
			check(ok==case.ok,"source v1 validation "+case.name)
			if not ok:check(s.serialize()==before,"restore atomic "+case.name)
			else:
				var source_envelope=parse_json(case.json,true)
				if source_envelope.state.has("pendingSurrenderReceipt"):
					check(s.snapshot().pendingSurrenderReceipt.quote.token.lossDigest==source_envelope.state.pendingSurrenderReceipt.quote.token.lossDigest,"byte exact imported surrender digest "+case.name)
				if case.name.begins_with("utf16"):
					check(equal(parse_json(s.serialize()).state,source_envelope.state),"source UTF16 full state serialization "+case.name)
					check(equal(parse_json(s.serialize()).meta,source_envelope.meta),"source UTF16 full metadata serialization "+case.name)
				check(equal(s.navalSetup(),case.naval),"restored naval setup "+case.name);check(equal(s.ambientNavalSetup(),case.ambient),"restored ambient "+case.name);check(equal(s.ambientWaypoints(),case.waypoints),"restored waypoints "+case.name)
				var saved=s.serialize();var c=script.new();check(c.restore(saved),"round trip "+case.name);check(equal(c.snapshot(),s.snapshot()),"round trip full state "+case.name)
	print("legacy save v1: ","PASS" if failures==0 else "FAIL"," (",failures,")")
	quit(0 if failures==0 else 1)
