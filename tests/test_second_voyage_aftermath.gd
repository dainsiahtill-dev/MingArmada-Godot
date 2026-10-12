extends SceneTree
const Fixture=preload("res://tests/second_voyage_aftermath_fixture.gd")
var Subject
var assertions:=0
var failures:=0
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func at_port(kind: String="full",port: String="forward-supply") -> Dictionary:
	var s: Dictionary=Fixture.make_claim(kind)
	check(not s.is_empty(),"constructed "+kind+" fixture creates actual second claim through domain boundary")
	if not s.is_empty():s.currentPortId=port
	return s
func _initialize() -> void:
	check(ResourceLoader.exists("res://game/domain/mingqi/second_voyage_aftermath.gd"),"second aftermath domain implementation exists")
	if failures:finish();return
	Subject=load("res://game/domain/mingqi/second_voyage_aftermath.gd")
	test_reward_shares();test_participants_and_cut_points();test_scene_copy_and_projection();test_apply_and_receipts();test_history_slices_and_load_identity()
	finish()
func finish() -> void:
	print("SECOND_VOYAGE_AFTERMATH_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func test_reward_shares() -> void:
	for row in [["full",250,50,4],["late",200,40,4],["partial",150,30,3],["zero",0,0,0]]:
		var s:=at_port(row[0]);var q: Dictionary=Subject.quote(s,"share-proceeds")
		check(q.revenue==row[1] and q.silverCost==row[2] and q.supportAward==row[3],"actual "+row[0]+" claim derives literal revenue/share/support")
		check(q.ok==(row[1]>0),"zero actual revenue refuses only dividend")
		if row[1]>0:
			s.captain.silver=row[2];check(Subject.quote(s,"share-proceeds").ok,"exact dividend silver affordable")
			s.captain.silver=row[2]-1;check(Subject.quote(s,"share-proceeds").reason=="insufficient-silver","one less than dividend refuses")
	var s:=at_port()
	for row in [[98,100,2],[100,100,0]]:
		s.reputations.crewSupport=row[0];var bill: Dictionary=Subject.project(s).bill
		check(bill.supportAfter==row[1] and bill.supportDelta==row[2],"constructed high-support preview displays bounded actual delta")
		check(Subject.quote(s,"share-proceeds").reason=="unexplained-crew-support","old unexplained high support cannot newly claim share")
		check(Subject.quote(s,"keep-capital").ok and Subject.quote(s,"return-xiamen").ok,"old unexplained support leaves zero-effect choices usable")
func test_participants_and_cut_points() -> void:
	var s:=at_port();var q: Dictionary=Subject.quote(s,"share-proceeds")
	check(q.beneficiaries==[{"shipId":"convoy-grain-a","able":20,"wounded":0},{"shipId":"convoy-grain-b","able":20,"wounded":0}] and q.beneficiaryCount==40,"only two proven carriers receive; flagship fast background excluded")
	check(Fixture.casualty(s,"convoy-grain-a",0),"real casualty boundary creates wounded-only living carrier")
	q=Subject.quote(s,"share-proceeds")
	check(q.ok and q.beneficiaries[0].able==0 and q.beneficiaries[0].wounded==10 and q.beneficiaryCount==30,"surviving wounded receive; ten actual deaths do not")
	var before: Dictionary=s.duplicate(true);var result: Dictionary=Subject.apply(s,"share-proceeds",Fixture.safe_witness(s));var receipt:=Fixture.record_choice(s,result)
	check(result.ok and Subject.receipt_error(s,receipt).is_empty(),"wounded payment receipt validates at its payment event")
	check(Fixture.casualty(s,"convoy-grain-a",0,0),"later actual sinking creates genuine later casualty event")
	check(Subject.receipt_error(s,receipt).is_empty(),"later death never invalidates earlier surviving wounded payment")
	var old_bucket: Dictionary=Subject.crew_at_event(s,"convoy-grain-a",receipt.id)
	check(old_bucket.ok and old_bucket.able==0 and old_bucket.wounded==10,"historical crew cut reverses later loss read-only")
	var forged: Dictionary=s.duplicate(true);forged.settlements[receipt.id].details.aftermath.beneficiaries[0].wounded=0
	check(not Subject.receipt_error(forged,forged.settlements[receipt.id]).is_empty(),"current buckets cannot replace historical paid buckets")
	s=before.duplicate(true);s.vessels["convoy-grain-b"].crew.able=19
	check(Subject.quote(s,"share-proceeds").beneficiaryCount==10,"undocumented carrier bucket chain conservatively excludes that group")
	s=at_port();check(Fixture.casualty(s,"convoy-grain-a",0,0),"actual carrier loss fixture")
	check(Subject.quote(s,"share-proceeds").beneficiaryCount==20,"one sunk carrier leaves only actual survivor paid")
	s=at_port();s.vessels["convoy-grain-a"].crew={"able":0,"wounded":0,"prisoners":20,"minimum":8}
	check(Subject.quote(s,"share-proceeds").beneficiaryCount==20,"unproved prisoner-only group never enters beneficiary count")
func test_scene_copy_and_projection() -> void:
	var fixture: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	check(Subject.project(fixture.convoySteps[6].state).is_empty(),"no second claim means no extra scene")
	var s: Dictionary=Fixture.make_claim();var p: Dictionary=Subject.project(s)
	check(p.objective.detail.contains("厦门、金门或近岸补给点") and p.scene.status=="locked","at-sea genuine claim points to three real safe ports")
	for port in ["xiamen","kinmen","forward-supply"]:
		s.currentPortId=port;p=Subject.project(s)
		check(p.scene.id=="second-return" and p.scene.choices.size()==3 and p.scene.text.size()==2,"legal port projects one concise three-choice ledger")
		check(p.scene.choices[0].label==("在厦门偿债" if port=="xiamen" else "回厦门偿债"),"real port determines debt goal label")
		check(p.bill.revenue==250 and p.bill.dividend==50 and p.bill.principal==400 and p.bill.beneficiaryCount==40,"bill exposes actual claim cash debt and proven carriers")
		check(p.bill.scopeNote.contains("仅含承运船") and p.bill.scopeNote.contains("护卫伤亡未列入"),"unknown escort history expressly outside bill")
	check(not p.scene.text[0].contains("新增伤") and not p.scene.text[0].contains("全队无人"),"old wounds and unknown escorts never become false journey claims")
	s=at_port("zero");check(Subject.quote(s,"keep-capital").ok and Subject.quote(s,"return-xiamen").ok,"zero revenue still allows debt goal or retained capital")
	s.debt.principal=0;check(Subject.quote(s,"return-xiamen").reason=="debt-paid","paid debt cannot create false new repayment goal")
func test_apply_and_receipts() -> void:
	for choice in ["return-xiamen","keep-capital","share-proceeds"]:
		var s:=at_port();var before: Dictionary=s.duplicate(true);var result: Dictionary=Subject.apply(s,choice,Fixture.safe_witness(s))
		check(result.ok,"real quote and independently supplied safe witness applies "+choice)
		check(s.captain.silver==before.captain.silver-(50 if choice=="share-proceeds" else 0) and s.reputations.crewSupport==before.reputations.crewSupport+(4 if choice=="share-proceeds" else 0),"choice applies only specified silver/support effects")
		check(s.debt==before.debt and s.vessels==before.vessels and s.contracts==before.contracts and s.settlements==before.settlements and s.chronicle==before.chronicle,"apply cannot repay heal mutate contracts or persist own receipt")
		var receipt:=Fixture.record_choice(s,result);check(Subject.receipt_error(s,receipt).is_empty(),"full new receipt validates "+choice)
		var decoded: Dictionary=JSON.parse_string(JSON.stringify(s,"",false,true))
		check(Subject.receipt_error(decoded,decoded.settlements[receipt.id]).is_empty(),"JSON number and field order roundtrip preserves real "+choice+" receipt")
		check(Subject.quote(s,choice).reason=="story-completed","fixed receipt refuses further arrangement")
		for field in ["revenue","silverAfter","supportAfter","beneficiaryCount"]:
			var forged: Dictionary=s.duplicate(true);forged.settlements[receipt.id].details.aftermath[field]+=1
			check(not Subject.receipt_error(forged,forged.settlements[receipt.id]).is_empty(),"receipt rejects forged "+choice+" "+field)
		var bad: Dictionary=s.duplicate(true);bad.settlements[receipt.id].details.portId="kinmen"
		check(not Subject.receipt_error(bad,bad.settlements[receipt.id]).is_empty(),"historical witness refuses swapping another allowed port")
	var s:=at_port();var before: Dictionary=s.duplicate(true);var witness:=Fixture.safe_witness(s);witness.anchored=false
	check(not Subject.apply(s,"share-proceeds",witness).ok and s==before,"unsafe witness rejects before any resource mutation")
func transition_slice(s: Dictionary,reason: String,changes: Array) -> void:
	# Explicit aggregate-history unit fixture, not a gameplay action or a Codec-valid save.
	var cause="constructed-history-"+str(s.revision);var id=cause+":crew"
	for change in changes:
		for key in ["able","wounded","prisoners"]:s.vessels[change.shipId].crew[key]=change.after[key]
	s.revision+=1
	s.settlements[id]={"id":id,"commandId":id,"revision":s.revision,"kind":"crew-transition","message":"constructed history slice","details":{"kind":"crew-transition","reason":reason,"causeId":cause,"changes":changes.duplicate(true)}}
	var causes=[cause]
	for change in changes:causes.append(change.shipId)
	s.chronicle.append({"id":id,"kind":"crew-transition","causeIds":causes,"simTime":s.simulationSeconds,"date":s.calendar.duplicate(true),"message":"constructed history slice"})
func test_history_slices_and_load_identity() -> void:
	var s:=at_port();var forged: Dictionary=s.duplicate(true)
	forged.settlements["convoy-convoy-002-accept"].details.ships[1].shipId="convoy-grain-a"
	check(Subject.quote(forged,"share-proceeds").reason=="second-convoy-unclaimed","duplicate loading carrier cannot prove another group's participation")
	check(not Subject.crew_at_event(s,"convoy-grain-a","missing-cut-event").ok,"missing historical event cannot reconstruct a payment cut")
	check(Fixture.casualty(s,"convoy-grain-a",0),"slice baseline uses genuine casualty boundary")
	transition_slice(s,"treatment",[{"shipId":"convoy-grain-a","before":{"able":0,"wounded":10,"prisoners":0},"after":{"able":1,"wounded":9,"prisoners":0}}])
	check(Subject.quote(s,"share-proceeds").beneficiaryCount==30,"prior treatment moves living bucket without losing proven participation")
	var result: Dictionary=Subject.apply(s,"share-proceeds",Fixture.safe_witness(s));var receipt:=Fixture.record_choice(s,result)
	transition_slice(s,"prize-rescue",[{"shipId":"convoy-grain-a","before":{"able":1,"wounded":9,"prisoners":0},"after":{"able":1,"wounded":8,"prisoners":0}},{"shipId":"convoy-flagship","before":{"able":60,"wounded":0,"prisoners":0},"after":{"able":60,"wounded":1,"prisoners":0}}])
	check(Subject.receipt_error(s,receipt).is_empty(),"later aggregate transfer cannot change already paid historical group")
	s=at_port();transition_slice(s,"allocation",[{"shipId":"convoy-grain-a","before":{"able":20,"wounded":0,"prisoners":0},"after":{"able":19,"wounded":0,"prisoners":0}},{"shipId":"convoy-flagship","before":{"able":60,"wounded":0,"prisoners":0},"after":{"able":61,"wounded":0,"prisoners":0}}])
	var q: Dictionary=Subject.quote(s,"share-proceeds")
	check(q.ok and q.beneficiaryCount==20 and q.exclusions[0].contains("曾跨船调动"),"prior transfer excludes whole mixed group; other proven carrier remains")
	check(Fixture.casualty(s,"convoy-grain-b",0,0),"genuine sinking removes last unmixed group")
	check(Subject.quote(s,"share-proceeds").reason=="no-verified-beneficiaries","no surviving unmixed carrier refuses payment")
