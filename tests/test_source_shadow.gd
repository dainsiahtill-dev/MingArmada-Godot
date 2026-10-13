extends SceneTree
var failures:=0
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok: failures+=1; printerr("FAIL ",label)
func same(a:Variant,b:Variant)->bool:
	if a is Array and b is Array:
		if a.size()!=b.size():return false
		for i in a.size():
			if not same(a[i],b[i]):return false
		return true
	if (a is float or a is int) and (b is float or b is int):return PackedFloat32Array([float(a)])[0]==PackedFloat32Array([float(b)])[0]
	return a==b
func _initialize()->void:
	if not ResourceLoader.exists("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd"):
		check(false,"source shadow finite port is absent")
		quit(1);return
	var math=load("res://modules/scene_engine/fidelity_fx/source_shadow_math.gd")
	var cases:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/source_shadow_original.json"))
	for fixture in cases.edge:
		var edges:Array=[]
		for row in fixture.rows:
			math.toggle_edge(edges,int(row.edge[0]),int(row.edge[1]))
			check(same(edges,row.originalEdges),"edge swap cancellation")
	for fixture in cases.volume:
		var input:Dictionary=fixture.input
		var got:Dictionary=math.build_volume_component(input.positions,input.light,input.edges,input.cap)
		for key in fixture.original:
			check(same(got.get(key),fixture.original[key]),"volume %s %s" % [input.label,key])
	for fixture in cases.predicate:
		check(math.should_rebuild(fixture.skinned,fixture.hasVolume,fixture.current,fixture.previous)==fixture.original,"rotation %s" % fixture.label)
	for fixture in cases.registrationGate:
		check(math.registration_allowed(fixture.displayShadowByte,fixture.featureBits,fixture.hasActorCasterList,fixture.actor144)==fixture.originalEnteredRegistrationLoop,"gate")
	check(math.build_volume_component([[0,0,0]],[0,0,0],[[32768,0]],[]).has("error"),"signed edge bound")
	check(math.build_volume_component([[0,0,0]],[NAN,0,0],[],[]).has("error"),"nonfinite light rejected")
	print("SOURCE_SHADOW checks=",checks," failures=",failures)
	quit(1 if failures else 0)
