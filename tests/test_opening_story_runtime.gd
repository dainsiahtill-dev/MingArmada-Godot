extends SceneTree
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
var assertions:=0
var failures:=0
func check(value: bool,detail: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",detail)
func intent(runtime: RefCounted,type: String,id: String,fields: Dictionary={}) -> Dictionary:
	var command: Dictionary={"type":type,"commandId":id,"expectedRevision":runtime.snapshot().campaign.revision}
	command.merge(fields)
	return runtime.command(command)
func equal_json(a: Variant,b: Variant) -> bool:
	if (a is int or a is float) and (b is int or b is float): return is_equal_approx(float(a),float(b))
	if a is Dictionary and b is Dictionary:
		if a.size()!=b.size(): return false
		for key in a:
			if not b.has(key) or not equal_json(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size()!=b.size(): return false
		for index in a.size():
			if not equal_json(a[index],b[index]): return false
		return true
	return a==b
func finish(runtime: RefCounted) -> void:
	runtime.dispose()
	print("OPENING_STORY_RUNTIME_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
func _initialize() -> void:
	var runtime:=Runtime.new()
	check(runtime.configure(func(_x: float,_z: float)->float: return -24.0).ok,"native runtime starts the existing opening")
	var packet: Dictionary=runtime.snapshot()
	check(packet.has("story") and packet.story is Dictionary,"runtime exposes authoritative opening story projection")
	if not packet.has("story"): finish(runtime); return
	check(packet.story.chapter.title=="旧账新帆","runtime publishes the opening chapter")
	check(packet.runtime.eligibility.story.get("old-ledger",{}).get("ok",false),"opening ledger action is ready at the real anchored flagship")
	var before: Dictionary=packet.campaign
	var paid:=intent(runtime,"story-choice","runtime-wages",{"sceneId":"old-ledger","choiceId":"settle-wages"})
	check(paid.ok,"real bridge commits first wages choice")
	packet=runtime.snapshot()
	check(packet.campaign.captain.silver==before.captain.silver-80 and packet.campaign.reputations.crewSupport==60,"choice has actual currency and crew consequences")
	check(packet.story.history.size()==1,"journal reads the actual committed choice")
	check(not packet.runtime.eligibility.story.get("old-ledger",{}).get("ok",false),"completed decision cannot be presented as available")
	var committed: Dictionary=packet.campaign
	check(runtime.command({"type":"story-choice","commandId":"runtime-wages","expectedRevision":before.revision,"sceneId":"old-ledger","choiceId":"settle-wages"}).ok,"old command retries through the normal idempotency boundary")
	check(runtime.snapshot().campaign==committed,"retry preserves currency, reputation and all receipt counts")
	check(intent(runtime,"accept-convoy","runtime-convoy").ok,"existing convoy acceptance still works after story")
	check(runtime.snapshot().runtime.eligibility.story.get("pilot-plan",{}).get("ok",false),"accepted and anchored convoy enables the preparation decision")
	runtime.set_pause("loading",true)
	before=runtime.snapshot().campaign
	check(not runtime.snapshot().runtime.eligibility.story.get("pilot-plan",{}).get("ok",false),"loading closes the projected story authority")
	check(not intent(runtime,"story-choice","runtime-loading",{"sceneId":"pilot-plan","choiceId":"hire-pilot"}).ok,"loading also rejects real choice intent")
	check(runtime.snapshot().campaign==before,"loading rejection is atomic")
	runtime.set_pause("loading",false)
	runtime.set_pause("player",true)
	before=runtime.snapshot().campaign
	check(intent(runtime,"story-choice","runtime-pilot",{"sceneId":"pilot-plan","choiceId":"hire-pilot"}).ok,"paused planning can hire a pilot through native authority")
	packet=runtime.snapshot()
	for voyage_id in packet.campaign.contracts["convoy-001"].voyageIds:
		check(packet.campaign.voyages[voyage_id].routeId=="xiamen-kinmen-shallow","pilot changes the actual grain voyage route")
		check(packet.campaign.voyages[voyage_id].escortIds==before.voyages[voyage_id].escortIds,"route choice preserves the existing escort lease")
	check(packet.campaign.flagshipId in packet.runtime.controllableShipIds,"pilot choice preserves flagship command authority")
	check(packet.naval.tick==runtime.render_snapshot().tick,"story commits do not bill simulation time")
	check(packet.runtime.eligibility.repayDebt.ok,"real anchored debtor can make a payment")
	before=packet.campaign
	check(intent(runtime,"repay-debt","runtime-pay-part",{"quantity":100}).ok,"actual partial payment commits")
	packet=runtime.snapshot()
	check(packet.campaign.debt.principal==300 and packet.campaign.captain.silver==before.captain.silver-100,"partial payment changes both silver and principal")
	check(packet.campaign.reputations.merchantCredit==before.reputations.merchantCredit,"partial payments cannot farm merchant credit")
	check(intent(runtime,"repay-debt","runtime-pay-full",{"quantity":300}).ok,"actual full payment commits once")
	packet=runtime.snapshot()
	check(packet.campaign.debt.principal==0 and not packet.runtime.eligibility.repayDebt.ok,"settled debt closes payment eligibility")
	check(packet.campaign.reputations.merchantCredit==before.reputations.merchantCredit+6,"full payoff grants the single bounded relationship consequence")
	var saved: Dictionary=runtime.export_save("2026-10-11T00:00:00.000Z")
	check(saved.ok,"real opening choices and debt export through safe-save gate")
	if saved.ok:
		var history: Array=packet.story.history.duplicate(true)
		check(runtime.adopt_save(saved.json).ok,"real runtime rebuild restores the story save")
		packet=runtime.snapshot()
		check(equal_json(packet.story.history,history) and packet.campaign.debt.principal==0,"restored projection is derived without duplicate rewards")
		check(not packet.runtime.eligibility.repayDebt.ok and not packet.runtime.eligibility.story["pilot-plan"].ok,"loading restore does not expose stale action buttons")
		runtime.set_pause("loading",false)
	runtime.set_pause("player",false)
	check(intent(runtime,"depart","runtime-depart").ok,"existing departure remains playable after story and debt choices")
	packet=runtime.snapshot()
	check(packet.campaign.currentPortId==null and not packet.runtime.eligibility.repayDebt.ok,"at-sea repayment is unavailable in the same runtime")
	before=packet.campaign
	check(not intent(runtime,"repay-debt","runtime-pay-at-sea",{"quantity":1}).ok and runtime.snapshot().campaign==before,"direct at-sea payment rejects atomically")
	packet.story.chapter.title="client mutation"
	check(runtime.snapshot().story.chapter.title=="旧账新帆","presentation reads detached data rather than owning story state")
	# This debtor still owes money. The ship stays inside the harbor at low
	# speed, but an actual live rudder intent means it is not anchored.
	var unsafe_runtime:=Runtime.new()
	check(unsafe_runtime.configure(func(_x: float,_z: float)->float: return -24.0).ok,"second native debtor starts without fixture state edits")
	check(intent(unsafe_runtime,"accept-convoy","unsafe-accept").ok,"second debtor borrows the actual convoy")
	check(unsafe_runtime.command({"type":"controls","rudder":0.3,"sailDeployment":0.0}).ok,"actual queued rudder intent reaches native handling")
	unsafe_runtime.advance(1.0/60.0)
	var unsafe_packet: Dictionary=unsafe_runtime.snapshot()
	check(unsafe_packet.campaign.currentPortId=="xiamen" and unsafe_packet.runtime.canDock.xiamen.ok,"low-speed vessel is still close enough to port")
	check(not unsafe_runtime.simulation.encounter.isAnchored(unsafe_packet.campaign.flagshipId),"live rudder makes the actual vessel unanchored")
	check(not unsafe_packet.runtime.eligibility.story["pilot-plan"].ok and not unsafe_packet.runtime.eligibility.repayDebt.ok,"story/pay hints require stronger docking than proximity")
	before=unsafe_packet.campaign
	check(not intent(unsafe_runtime,"repay-debt","unsafe-pay",{"quantity":100}).ok and unsafe_runtime.snapshot().campaign==before,"affordable real debt payment rejects while unanchored")
	check(not intent(unsafe_runtime,"story-choice","unsafe-plan",{"sceneId":"pilot-plan","choiceId":"hire-pilot"}).ok and unsafe_runtime.snapshot().campaign==before,"affordable route planning rejects while unanchored")
	unsafe_runtime.dispose()
	finish(runtime)
