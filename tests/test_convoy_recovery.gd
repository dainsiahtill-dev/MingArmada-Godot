extends SceneTree
const Campaign=preload("res://game/domain/mingqi/campaign.gd")
const Codec=preload("res://game/domain/persistence/save_codec.gd")
const Story=preload("res://game/domain/mingqi/opening_story.gd")
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
var assertions:=0
var failures:=0
var fixture: Dictionary
func check(ok: bool,message: String) -> void:
	assertions+=1
	if not ok:failures+=1;printerr("FAIL: ",message)
func envelope(s: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":s.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-12T00:00:00.000Z","simulationSeconds":s.simulationSeconds,"state":s},"",false,true)
func send(r: RefCounted,type: String,extra: Dictionary={},id: String="") -> Dictionary:
	var s: Dictionary=r.campaign.snapshot();var c:={"type":type,"commandId":id if not id.is_empty() else "recovery-"+str(s.revision),"expectedRevision":s.revision};c.merge(extra)
	return r.command(c)
func returned(sunk_a: bool=false,sunk_b: bool=false,crew_b: int=20) -> RefCounted:
	var c:=Campaign.new();check(c.restore(envelope(fixture.convoySteps[1].state)),"old departing convoy fixture valid")
	var observation: Dictionary=fixture.convoySteps[2].native.duplicate(true)
	for ship in observation.ships:
		if ship.id=="convoy-grain-a" and sunk_a or ship.id=="convoy-grain-b" and sunk_b:ship.hull=0;ship.crew=0
		elif ship.id=="convoy-grain-b":ship.crew=crew_b
	check(c.sync_near(observation,[]).ok,"real domain creates arrival/loss/casualty receipts from native boundary observation")
	check(c.command({"type":"claim-convoy","contractId":"convoy-001","commandId":"claim-recovery","expectedRevision":c.snapshot().revision}).ok,"actual first terminal convoy is claimed")
	var r:=Runtime.new();check(r.configure(func(_x: float,_z: float)->float:return -24.0,c).ok,"real native bridge constructs returned fleet")
	check(send(r,"dock",{"portId":"kinmen"},"dock-recovery").ok,"actual native fleet safely anchors at kinmen")
	return r
func reject(r: RefCounted,extra: Dictionary,label: String) -> void:
	var before: Dictionary=r.campaign.snapshot();check(not send(r,"accept-convoy",extra).ok,label+" rejected");check(before==r.campaign.snapshot(),label+" atomic")
func _initialize() -> void:
	fixture=JSON.parse_string(FileAccess.get_file_as_string("res://tests/fixtures/mingqi-reference.json"))
	var r:=returned(true);var before: Dictionary=r.campaign.snapshot();var result:=send(r,"accept-convoy",{"contractId":"convoy-002"},"single-load")
	check(result.ok,"genuine sunk original plus healthy original accepts real single-ship second convoy")
	if result.ok:
		var s: Dictionary=r.campaign.snapshot();var ct: Dictionary=s.contracts["convoy-002"]
		check(ct.voyageIds.size()==1 and s.voyages[ct.voyageIds[0]].vesselId=="convoy-grain-b" and s.vessels["convoy-grain-b"].cargo.grain==20,"single real surviving vessel loads20 in one voyage")
		check(s.ports.kinmen.stock.grain==before.ports.kinmen.stock.grain-20 and s.captain.silver==before.captain.silver,"single carrier conserves real20 port stock without new lease fee")
		check(s.vessels["convoy-grain-a"].damage==before.vessels["convoy-grain-a"].damage and s.vessels["convoy-grain-a"].crew==before.vessels["convoy-grain-a"].crew and s.people==before.people and s.casualtyOrdinals==before.casualtyOrdinals,"sunk hull and original deaths are never restored")
		check(ct.criticalPersonIds==["steward-b"] and s.contracts["convoy-001"].criticalPersonIds==["steward-a","steward-b"] and not s.people["steward-a"].alive,"new single-carrier personnel reflects surviving actual embarkation without rewriting first death")
		check(Codec.decode(r.campaign.serialize()).get("ok",false),"single-voyage load saves and restores")
		var snapshot: Dictionary=r.campaign.snapshot();var replay: Dictionary=r.command({"type":"accept-convoy","contractId":"convoy-002","commandId":"single-load","expectedRevision":0})
		check(replay.ok and replay.receipt==result.receipt and r.campaign.snapshot()==snapshot,"single load retry cannot duplicate cargo or stock")
		check(not r.command({"type":"accept-convoy","contractId":"convoy-002","commandId":"stale-load","expectedRevision":snapshot.revision-1}).ok and r.campaign.snapshot()==snapshot,"stale acceptance leaves single load unchanged")
		for kind in ["carrier","load","omitted-living","voyage-count","critical-person","wrong-vessel"]:
			var forged: Dictionary=s.duplicate(true);var d: Dictionary=forged.settlements[result.receipt.id].details
			match kind:
				"carrier":d.ships[0].shipId="convoy-fast"
				"load":d.loaded=19
				"omitted-living":forged.vessels["convoy-grain-a"].damage.hull=100
				"voyage-count":forged.contracts["convoy-002"].voyageIds.append("convoy-grain-a-voyage")
				"critical-person":forged.contracts["convoy-002"].criticalPersonIds=[]
				"wrong-vessel":forged.voyages[ct.voyageIds[0]].vesselId="convoy-fast"
			check(not Codec.decode(envelope(forged)).get("ok",false),"forged single-vessel save "+kind+" rejected")
		check(send(r,"depart",{},"single-depart").ok,"second real single carrier departs without first-return conversation")
		# Native observation fixture verifies domain arrivals, not an acceptance journey teleport.
		var arrival: Dictionary=r.simulation.snapshot().duplicate(true);arrival.tick+=1;arrival.time+=1.0/60.0
		for ship in arrival.ships:
			if ship.id=="convoy-grain-b":ship.visual.position.x=-60;ship.visual.position.z=320;ship.visual.velocity={"x":0,"z":0};ship.sailDeployment=0;ship.rudder=0
		check(r.campaign.sync_near(arrival,[]).ok,"real domain creates second arrival receipt from supplied native boundary observation")
		var settled: Dictionary=r.campaign.command({"type":"claim-convoy","commandId":"single-claim","expectedRevision":r.campaign.snapshot().revision,"contractId":"convoy-002"})
		check(settled.ok and settled.receipt.details.delivered==20 and settled.receipt.details.bonus==50 and settled.receipt.details.people==[{"personId":"steward-b","alive":true}],"living actual single-carrier steward can earn new50 bonus without resurrecting old dead steward")
		check(r.campaign.snapshot().settlements["convoy:convoy-001:claim"].details.bonus==0 and Codec.decode(r.campaign.serialize()).get("ok",false),"first casualty penalty remains and new single settlement roundtrips")
	r.dispose()
	r=returned(false,false,7);before=r.campaign.snapshot();var id="convoy-grain-b";var packet: Dictionary=r.snapshot()
	check(packet.runtime.eligibility["treat-wounded:"+id].ok,"genuine leased below-min wounded transport exposes actual safe treatment")
	check(id in packet.runtime.policy.disabledMotionShipIds and id in packet.runtime.policy.lockedShipIds,"below-min service authority remains motion-disabled and locked")
	check(not r.simulation.encounter.navigate(id,{"x":0,"z":0}).ok,"treatment permission cannot become sailing permission")
	reject(r,{"contractId":"convoy-002"},"living low-crew original cannot be silently omitted")
	result=send(r,"treat-wounded",{"shipId":id,"quantity":1},"heal-minimum")
	check(result.ok,"actual leased ship pays for wounded treatment despite below-min able crew")
	if result.ok:
		var s: Dictionary=r.campaign.snapshot()
		check(s.captain.silver==before.captain.silver-4 and s.vessels[id].crew.able==7 and s.vessels[id].crew.wounded==before.vessels[id].crew.wounded,"payment does not instantly heal or restore dead crew")
		check(Codec.decode(r.campaign.serialize()).get("ok",false),"active leased treatment saves")
		var fake_service: Dictionary=s.duplicate(true);var work_id: String=result.receipt.details.workId
		fake_service.works[work_id].shipId="convoy-background-grain-01";fake_service.settlements[result.receipt.id].details.shipId="convoy-background-grain-01";fake_service.vessels["convoy-background-grain-01"].crew.wounded=1
		check(not Codec.decode(envelope(fake_service)).get("ok",false),"forged house-lin treatment cannot switch work/payment to an unleased background carrier")
		check(not send(r,"depart",{},"work-depart").ok,"cannot leave port during actual treatment")
		for i in 1801:r.advance(1.0/60.0)
		s=r.campaign.snapshot();check(s.vessels[id].crew.able==8 and s.vessels[id].crew.wounded==before.vessels[id].crew.wounded-1 and s.people==before.people,"actual30-second work restores minimum from real wounded only")
		check(not id in r.snapshot().runtime.policy.disabledMotionShipIds and Codec.decode(r.campaign.serialize()).get("ok",false),"finished real treatment restores motion and save continuity")
		check(send(r,"accept-convoy",{"contractId":"convoy-002"},"two-after-care").ok,"both live originals can accept existing two-carrier load after actual recovery")
	r.dispose()
	r=returned();before=r.campaign.snapshot();result=send(r,"accept-convoy",{"contractId":"convoy-002"},"healthy-load")
	check(result.ok and r.campaign.snapshot().contracts["convoy-002"].voyageIds.size()==2,"healthy two-original default convoy retains two voyages")
	check(r.campaign.snapshot().vessels["convoy-grain-a"].cargo.grain==10 and r.campaign.snapshot().vessels["convoy-grain-b"].cargo.grain==10,"healthy two-original load remains10 each")
	r.dispose()
	r=returned();r.campaign._state.vessels["convoy-grain-b"].pose.position.x+=500
	var rebuilt: Dictionary=r.campaign.snapshot();r.dispose()
	# Rebuild through an actual session instead of editing a live native pose.
	var session:=Campaign.new();session._state=rebuilt;r=Runtime.new();check(r.configure(func(_x: float,_z: float)->float:return -24.0,session).ok,"away living ship fixture creates real native position")
	reject(r,{"contractId":"convoy-002"},"alive-away original cannot be silently omitted");r.dispose()
	r=returned(true,true);reject(r,{"contractId":"convoy-002"},"two actual sunk transports cannot be magically replaced");r.dispose()
	r=returned(true);var loss: Dictionary=r.simulation.snapshot().duplicate(true);loss.tick+=1;loss.time+=1.0/60.0
	for ship in loss.ships:
		if ship.id=="convoy-grain-b":ship.hull=0;ship.crew=0
	check(r.campaign.sync_near(loss,[]).ok,"second original truly sinks after positive first claim via native observation")
	var all_lost: Dictionary=r.campaign.snapshot();r.dispose();session=Campaign.new();check(session.restore(envelope(all_lost)),"both wrecks after claim remain a valid saved history");r=Runtime.new();r.configure(func(_x: float,_z: float)->float:return -24.0,session)
	before=r.campaign.snapshot();result=send(r,"accept-convoy",{"contractId":"convoy-002"},"both-lost")
	check(not result.ok and result.reason=="convoy-transports-sunk" and before==r.campaign.snapshot(),"offered commission explains actual all-wreck transport obstruction without replacement")
	check(send(r,"story-choice",{"sceneId":"first-return","choiceId":"keep-capital"},"both-clerk").ok,"optional clerk can acknowledge existing losses without restoring ships")
	check(Story.project(r.campaign.snapshot()).objective.detail.contains("没有替换"),"all-wreck continuation clearly discloses unsupported replacement")
	r.dispose()
	r=returned(false,false,7);r.campaign._state.captain.silver=3;before=r.campaign.snapshot()
	check(not r.snapshot().runtime.eligibility["treat-wounded:convoy-grain-b"].ok,"generic leased treatment readiness requires at least one real affordable wounded person")
	check(not send(r,"treat-wounded",{"shipId":"convoy-grain-b","quantity":1},"poor-care").ok and before==r.campaign.snapshot(),"insufficient treatment silver rolls all resources back");r.dispose()
	r=returned(false,false,7);before=r.campaign.snapshot()
	check(not send(r,"treat-wounded",{"shipId":"convoy-grain-b","quantity":8},"excess-care").ok and before==r.campaign.snapshot(),"cannot treat more than actual available wounded")
	var unanchored: Dictionary=r.bridge.command_context();unanchored.native.isAnchored=func(_id):return false
	check(not r.campaign.command({"type":"treat-wounded","shipId":"convoy-grain-b","quantity":1,"commandId":"unanchored-care","expectedRevision":before.revision},unanchored).ok and before==r.campaign.snapshot(),"genuine lease cannot bypass native anchored berth")
	r.campaign._state.vessels["convoy-grain-b"].crew.wounded=24;before=r.campaign.snapshot()
	check(not r.snapshot().runtime.eligibility["treat-wounded:convoy-grain-b"].ok and not send(r,"treat-wounded",{"shipId":"convoy-grain-b","quantity":1},"capacity-care").ok and before==r.campaign.snapshot(),"invalid total crew capacity cannot reserve treatment or payment")
	r.dispose()
	var claimed: Dictionary=fixture.convoySteps[3].state
	check(Story.project(claimed).objective.id=="return-to-kinmen" and Story.project(claimed).objective.panel=="port","claimed at sea guides actual kinmen return instead of pretending conversation")
	check(Story.project(fixture.convoySteps[4].state).objective.id=="first-return-meeting" and Story.project(fixture.convoySteps[4].state).objective.panel=="story","kinmen before optional choice prioritizes clerk meeting")
	check(Story.project(fixture.convoySteps[5].state).objective.id=="depart-convoy-002","direct second acceptance skips meeting objective without blocking mission")
	for unauthorized in ["unsigned","background-house","foreign"]:
		r=returned(false,false,7)
		if unauthorized=="unsigned":r.campaign._state.settlements.erase("convoy-convoy-001-accept")
		elif unauthorized=="background-house":id="convoy-background-grain-01"
		else:r.campaign._state.vessels["convoy-grain-b"].ownerId="foreign-owner"
		var packet_now: Dictionary=r.snapshot()
		check(not packet_now.runtime.eligibility["treat-wounded:"+id].ok,"unrelated or unsigned leased service hint rejects "+unauthorized)
		var before_service: Dictionary=r.campaign.snapshot();check(not send(r,"treat-wounded",{"shipId":id,"quantity":1},"invalid-care").ok and before_service==r.campaign.snapshot(),"unrelated or unsigned leased treatment cannot commit "+unauthorized)
		id="convoy-grain-b";r.dispose()
	r=returned();var hurt_flag: Dictionary=r.simulation.snapshot().duplicate(true);hurt_flag.tick+=1;hurt_flag.time+=1.0/60.0
	for ship in hurt_flag.ships:
		if ship.id=="convoy-flagship":ship.crew=19
	check(r.campaign.sync_near(hurt_flag,[]).ok,"real domain casualty boundary creates below-min flagship")
	var flag_state: Dictionary=r.campaign.snapshot();r.dispose();session=Campaign.new();check(session.restore(envelope(flag_state)),"below-min flagship casualty history saves");r=Runtime.new();check(r.configure(func(_x: float,_z: float)->float:return -24.0,session).ok,"below-min flagship builds real service-only native fleet")
	check(not r.snapshot().runtime.canDepart,"actual runtime hint cannot depart with service-only below-min flagship")
	before=r.campaign.snapshot();check(not send(r,"depart",{},"flag-below-depart").ok and before==r.campaign.snapshot(),"domain refuses below-min flagship despite service permission")
	check(send(r,"treat-wounded",{"shipId":"convoy-flagship","quantity":1},"flag-care").ok,"below-min original leased flagship can receive actual treatment")
	check(not r.snapshot().runtime.canDepart and "convoy-flagship" in r.snapshot().runtime.policy.lockedShipIds and not send(r,"depart",{},"flag-working-depart").ok,"actual locked active-work flagship cannot depart in hint or domain")
	r.dispose()
	print("CONVOY_RECOVERY_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
