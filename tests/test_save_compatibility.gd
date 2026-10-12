extends SceneTree
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const SaveCodec=preload("res://game/domain/persistence/save_codec.gd")
var failures=0
func check(value: bool,message: String):
	if not value:failures+=1;push_error(message)
func _initialize():
	var json=FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")
	var decoded=SaveCodec.decode(json)
	check(decoded.get("ok",false),"source v2 decode: "+str(decoded.get("code")))
	var c=Campaign.new()
	check(c.restore(json),"source web save restore")
	var expected=JSON.parse_string(json).state
	check(FileAccess.get_sha256("res://tests/fixtures/web-save-v2.json")=="ef7b64268d13c1ed92a1f6cabb3ad2418ad3ca1e34e6a18faa800dc26904c147","independent numeric oracle binds unchanged web fixture")
	# Raw -93.58935220948257 has independently verified Python binary64 bits.
	# Godot's native JSON parser rounds this fixture leaf one ULP toward zero.
	expected.vessels["fixture-1650-grain-a"].pose.position.z="646354f2b76557c0".hex_decode().decode_double(0)
	check(c.snapshot()==expected,"source save state exact")
	var encoded=c.serialize()
	check(not encoded.is_empty(),"native full state serialize")
	check(SaveCodec.decode(encoded).get("state")==expected,"native roundtrip")
	var before=c.snapshot()
	for invalid in ['{"version":1}','{"version":3}','{"version":2,"version":2}','{"version":2,"__proto__":{}}','{"version":2,"state":NaN}',json.substr(0,json.length()/2)]:
		check(not c.restore(invalid),"invalid save rejected")
		check(c.snapshot()==before,"invalid save atomic")
	var malformed=JSON.parse_string(json)
	malformed.state.vessels[malformed.state.flagshipId].cargo.grain=81
	check(not c.restore(JSON.stringify(malformed,"",false,true)),"over capacity rejected")
	malformed=JSON.parse_string(json);malformed.state.calendar.day=31
	check(not c.restore(JSON.stringify(malformed,"",false,true)),"calendar mismatch rejected")
	malformed=JSON.parse_string(json);malformed.state.ports.xiamen.position.x+=1
	check(not c.restore(JSON.stringify(malformed,"",false,true)),"canonical port geometry rejected")
	malformed=JSON.parse_string(json);malformed.campaignId="other"
	check(not c.restore(JSON.stringify(malformed,"",false,true)),"envelope identity mismatch rejected")
	malformed=JSON.parse_string(json);malformed.state.seed=4294967296
	check(not c.restore(JSON.stringify(malformed,"",false,true)),"uint32 seed rejected")
	var old=JSON.parse_string(json);old.state.erase("prizes");old.state.erase("casualtyOrdinals")
	var old_decoded=SaveCodec.decode(JSON.stringify(old,"",false,true))
	check(old_decoded.get("ok",false),"old v2 optional buckets normalized: "+str(old_decoded.get("code")))
	var fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	for item in fixture.saveCases:
		var result=SaveCodec.decode(item.json)
		check(result.get("ok",false)==item.ok,"source validator parity "+item.name+": "+str(result.get("code")))
		if not item.ok:
			check(not c.restore(item.json),"reject atomic "+item.name)
			check(c.snapshot()==before,"preserve prior state "+item.name)
	print("save compatibility v2: ","PASS" if failures==0 else "FAIL"," (",failures,")")
	quit(0 if failures==0 else 1)
