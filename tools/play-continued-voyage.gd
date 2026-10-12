extends SceneTree
## Real checkpoint -> convoy-002 -> supply delivery -> Xiamen safe checkpoint.
## Captain intents only. No teleport, HP/cargo/receipt edits, respawn or Storage.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const Catalog = preload("res://game/domain/mingqi/catalog.gd")
const Paths = preload("res://tools/qa-journey-paths.gd")
const CheckpointAudit = preload("res://tools/qa-journey-checkpoint.gd")
const STEP := 0.2
const MAXIMUM_SECONDS := 2400.0
const SOURCES = ["game/domain/mingqi/opening_story.gd","game/domain/mingqi/second_voyage_aftermath.gd","game/domain/mingqi/campaign.gd","game/domain/mingqi/catalog.gd","game/domain/persistence/save_codec.gd","game/runtime/mingqi_runtime.gd","game/runtime/near_field_bridge.gd","game/runtime/native_readiness.gd","modules/contracts/navigation_contract.gd","modules/naval_simulation/encounter.gd","modules/naval_simulation/navigation/approach_clearance.gd","modules/naval_simulation/navigation/wet_route_egress.gd","modules/naval_simulation/combat/cannon_system.gd","modules/naval_simulation/tactics/order_controller.gd","game/runtime/sailing_simulation.gd","modules/scene_engine/terrain/height_field.gd","game/scenes/common/reference_geography.gd","game/data/mingqi_geography.json","tools/qa-journey-paths.gd","tools/play-opening-story-journey.gd","tools/play-continued-voyage.gd"]
var runtime := Runtime.new()
var assertions := 0
var failures := 0
var serial := 0
var checks: Array = []
var commands: Array = []
var stages: Array = []
var result: Dictionary = {}
var output_path := ""
var arguments: Array = []
var wall_start := 0
var ready := false
func _initialize() -> void: run.call_deferred()
func check(value: bool, detail: String) -> bool:
	assertions += 1; checks.append({"ok":value,"detail":detail})
	if not value: failures += 1; printerr("FAIL: ",detail)
	return value
func command(kind: String, fields: Dictionary = {}, business: bool = true) -> Dictionary:
	var input: Dictionary = {"type":kind}
	if business:
		serial += 1
		input.merge({"commandId":"continued-voyage-"+str(serial),"expectedRevision":int(runtime.snapshot().campaign.revision)})
	input.merge(fields)
	var receipt: Dictionary = runtime.command(input)
	commands.append({"simulationSeconds":runtime.snapshot().campaign.simulationSeconds,"input":input,"result":receipt})
	check(receipt.get("ok",false),"real " + kind + " accepted: " + str(receipt.get("reason","")))
	return receipt
func stamp(label: String) -> void:
	var packet: Dictionary = runtime.snapshot()
	var ships: Array = []
	for ship: Dictionary in packet.naval.ships:
		ships.append({"id":ship.id,"position":ship.visual.position,"velocity":ship.visual.velocity,"heading":ship.visual.heading,"navigation":ship.get("navigation"),"nativeDiagnostics":ship,"navigationDiagnostics":navigation_diagnostics(ship.id),"campaignVessel":packet.campaign.vessels.get(ship.id)})
	stages.append({"label":label,"simulationSeconds":packet.campaign.simulationSeconds,"acceptedSimulationSeconds":packet.runtime.acceptedSeconds,"ships":ships,"voyages":packet.campaign.voyages,"contract":packet.campaign.contracts.get("convoy-002"),"evaluation":runtime.campaign.evaluate_convoy("convoy-002"),"runtime":packet.runtime})
	print("CONTINUED_VOYAGE ",label," time=",packet.campaign.simulationSeconds," delivered=",runtime.campaign.evaluate_convoy("convoy-002").delivered)
func navigation_diagnostics(id: String) -> Dictionary:
	for live: Dictionary in runtime.simulation.encounter.ships:
		if live.state.id==id:
			return {"route":live.get("route"),"approachRecovery":live.get("approachRecovery"),"wetRouteEgress":live.get("wetRouteEgress"),"egressClearance":live.get("egressClearance"),"lowSpeedTurn":live.get("lowSpeedTurn"),"sailRecovery":live.get("sailRecovery"),"motion":live.core.get_snapshot()}.duplicate(true)
	return {}
func rally_fleet(port_id: String) -> void:
	var packet: Dictionary = runtime.snapshot()
	for member: Dictionary in packet.naval.ships:
		if member.id in packet.runtime.controllableShipIds and member.hull > 0 and member.id != packet.campaign.flagshipId:
			var order: Dictionary = {"id":"continued-voyage-"+str(serial+1),"shipIds":[member.id],"intent":{"kind":"rally","point":Catalog.DATA.ports[port_id].position},"issuedAt":packet.campaign.simulationSeconds}
			command("assign-order",{"order":order})
func casualty_evidence(before: Dictionary, after: Dictionary) -> Dictionary:
	var ships: Array = []; var people: Array = []; var receipts: Array = []
	for id: String in after.vessels:
		var old: Dictionary = before.vessels.get(id,{})
		var now: Dictionary = after.vessels[id]
		ships.append({"id":id,"beforeHull":old.get("damage",{}).get("hull"),"afterHull":now.damage.hull,"beforeCrew":old.get("crew"),"afterCrew":now.crew,"newlySunk":not old.is_empty() and old.damage.hull>0 and now.damage.hull<=0})
	for id: String in after.people:
		people.append({"id":id,"before":before.people.get(id),"after":after.people[id],"newlyDead":before.people.has(id) and before.people[id].alive and not after.people[id].alive})
	var old_ids: Array = before.chronicle.map(func(entry): return entry.id)
	for entry: Dictionary in after.chronicle:
		if not entry.id in old_ids and entry.kind in ["near-casualties","crew-transition","near-sink","cargo-loss"]: receipts.append({"chronicle":entry,"settlement":after.settlements.get(entry.id)})
	return {"ships":ships,"people":people,"newCasualtyReceipts":receipts,"settlementReceipt":after.settlements.get(after.campaignId+":convoy-002:claim")}
func run() -> void:
	wall_start = Time.get_ticks_usec(); arguments = Array(OS.get_cmdline_user_args())
	var output: Dictionary = Paths.output(arguments)
	var journey: Dictionary = Paths.input_journey(arguments)
	if not output.ok or not journey.ok:
		printerr("CONTINUED_VOYAGE_PREFLIGHT_REJECTED ",output.get("reason",journey.get("reason",""))); quit(2); return
	output_path = output.path
	if "--preflight" in arguments:
		print("CONTINUED_VOYAGE_PREFLIGHT_PASS acceptedSeconds=0 input=",journey.path," output=",output_path); quit(0); return
	var source_bytes := FileAccess.get_file_as_string(journey.path)
	var parser := Codec.new()
	var parsed = parser._parse(source_bytes)
	result = {"mode":"headless native gameplay; no GPU, visual or performance claim","terrain":"same formal game terrain","journeyPath":journey.path,"journeySha256":source_bytes.sha256_text(),"arguments":arguments,"maximumAcceptedSeconds":MAXIMUM_SECONDS,"stepSeconds":STEP,"sourceHashes":{},"confirmedCheckpointJson":"","actualSafeReturn":false}
	for path: String in SOURCES: result.sourceHashes[path] = FileAccess.get_sha256("res://"+path)
	result.sourceHashes["tools/qa-journey-checkpoint.gd"] = FileAccess.get_sha256("res://tools/qa-journey-checkpoint.gd")
	if not check(parser.error.is_empty(),"input journey passes strict full-precision JSON parser: "+parser.error): finish(); return
	if not check(parsed is Dictionary,"input journey is JSON object"): finish(); return
	var record: Dictionary = parsed
	if not check(record.get("failures",-1)==0 and record.get("actualSafeReturn",false) and record.get("terrain")=="same formal game terrain","successful actual formal first safe return"): finish(); return
	if not check(record.get("sourceHashes",{}).has("modules/naval_simulation/navigation/approach_clearance.gd"),"fresh first voyage records approach clearance source"): finish(); return
	if not check(record.get("sourceHashes",{}).has("modules/naval_simulation/navigation/wet_route_egress.gd"),"fresh first voyage records wet route egress source"): finish(); return
	if not check(record.get("sourceHashes",{}).has("game/domain/mingqi/second_voyage_aftermath.gd"),"fresh first voyage records aftermath domain source"): finish(); return
	result.upstreamQaContext = []
	for path: String in record.sourceHashes:
		var current_hash := FileAccess.get_sha256("res://"+path)
		if path=="tools/play-continued-voyage.gd":
			result.upstreamQaContext.append({"path":path,"role":"unexecuted QA reference in first journey source inventory","recordedFirstHash":record.sourceHashes[path],"currentHash":current_hash,"drift":current_hash!=record.sourceHashes[path],"executedByFirstJourney":false})
			if not check(not current_hash.is_empty(),"executing continued driver self source recorded as upstream QA context"): finish(); return
			continue
		if not check(current_hash==record.sourceHashes[path],"frozen first journey source: "+path): finish(); return
	var checkpoint: String = record.get("confirmedCheckpointJson","")
	var decoded: Dictionary = Codec.decode(checkpoint)
	if not check(decoded.get("ok",false) and Codec._equal(decoded.get("state"),record.get("final",{}).get("campaign")),"normal full-precision confirmed checkpoint equals actual first final campaign"): finish(); return
	result.confirmedSourceCheckpointJson = checkpoint
	result.confirmedSourceCheckpointSha256 = checkpoint.sha256_text()
	var original: Dictionary = decoded.state
	if not check(original.currentPortId=="kinmen" and original.contracts["convoy-002"].status=="offered","checkpoint is exact Kinmen preaccept state"): finish(); return
	var heights := Height.new()
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not check(heights.configure_ports(geography,true,Layout.options()),"identical formal reference geography configures"): finish(); return
	runtime.enable_reference_enhancements()
	if not check(runtime.configure(heights.sample_height).get("ok",false),"real continuous native runtime configures"): finish(); return
	ready = true
	if not check(runtime.adopt_save(checkpoint,null).get("ok",false),"normal strict Codec-backed checkpoint adoption"): finish(); return
	result.preacceptCampaign = runtime.snapshot().campaign
	result.preacceptMaterialAudit = CheckpointAudit.assess(original,result.preacceptCampaign)
	result.rawCheckpointEqualsPostAdoptExactly = Codec._equal(original,result.preacceptCampaign)
	if not check(result.preacceptMaterialAudit.ok,"normal adoption preserves exact preaccept material; all lawful owner stamps recorded"): finish(); return
	stamp("adopted-preaccept")
	runtime.set_pause("loading",false)
	if not command("accept-convoy",{"contractId":"convoy-002"}).ok: finish(); return
	var accepted: Dictionary = runtime.snapshot().campaign
	var contract: Dictionary = accepted.contracts["convoy-002"]
	var load_receipt: Dictionary = accepted.settlements[accepted.campaignId+"-convoy-002-accept"]
	if not check(contract.status=="active" and load_receipt.details.loaded==20 and load_receipt.details.leasePaid==0 and accepted.ports.kinmen.stock.grain==original.ports.kinmen.stock.grain-20 and accepted.captain.silver==original.captain.silver,"actual existing convoy loads twenty real grain without second lease"): finish(); return
	if not check(contract.deadlineAt==accepted.simulationSeconds+1200,"unchanged actual 1200-second deadline"): finish(); return
	for id: String in contract.voyageIds:
		if not check(accepted.voyages[id].routeId=="kinmen-supply-deep","real catalog supply voyage route"): finish(); return
	stamp("accepted-twenty-grain")
	if not command("depart").ok: finish(); return
	var route: Array = Catalog.DATA.routes["kinmen-supply-deep"].points
	var return_route: Array = [route[2],route[1],Catalog.DATA.routes["xiamen-kinmen-outer"].points[1],Catalog.DATA.routes["xiamen-kinmen-outer"].points[0]]
	result.routes = {"outboundCatalogRoute":"kinmen-supply-deep","outboundPoints":route,"returnCatalogRoutes":["kinmen-supply-deep reversed","xiamen-kinmen-outer reversed"],"returnPoints":return_route}
	var waypoint := 1
	if not command("navigate",{"point":route[waypoint]},false).ok: finish(); return
	var fast_id: String = accepted.campaignId+"-fast"
	if fast_id in runtime.snapshot().runtime.controllableShipIds and accepted.vessels[fast_id].damage.hull>0 and accepted.vessels[fast_id].crew.able>=accepted.vessels[fast_id].crew.minimum:
		var protected: String = accepted.voyages[contract.voyageIds[0]].vesselId
		var order: Dictionary = {"id":"continued-voyage-"+str(serial+1),"shipIds":[fast_id],"intent":{"kind":"protect","targetId":protected},"issuedAt":accepted.simulationSeconds}
		if not command("assign-order",{"order":order}).ok: finish(); return
	stamp("actual-departure")
	var starting_seconds: float = runtime.snapshot().campaign.simulationSeconds
	var next_stamp := starting_seconds+15.0
	var claimed := false
	var safely_returned := false
	var return_started := false
	var return_waypoint := 0
	var last_moor_revision := -1
	var accepted_steps := 0
	var accepted_seconds := 0.0
	for iteration in int(MAXIMUM_SECONDS/STEP):
		var consumed: float = runtime.advance(STEP)
		if consumed<=0.0:
			check(false,"native runtime unexpectedly rejected bounded step"); break
		if absf(consumed-STEP)>1e-9:
			check(false,"native accepted time differs from requested 0.2-second step"); break
		accepted_steps+=1; accepted_seconds+=consumed
		var packet: Dictionary = runtime.snapshot()
		var flagship: Dictionary = runtime._ship(packet.naval,packet.campaign.flagshipId)
		if flagship.is_empty() or flagship.hull<=0: stamp("flagship-lost"); break
		var position := Vector2(float(flagship.visual.position.x),float(flagship.visual.position.z))
		if not return_started:
			var target := Vector2(float(route[waypoint].x),float(route[waypoint].z))
			if position.distance_to(target)<35.0 and waypoint<route.size()-1:
				waypoint += 1
				if not command("navigate",{"point":route[waypoint]},false).ok: break
		var evaluation: Dictionary = runtime.campaign.evaluate_convoy("convoy-002")
		if not claimed and evaluation.reason!="in-progress":
			if not command("claim-convoy",{"contractId":"convoy-002"}).ok: break
			claimed = true; stamp("real-terminal-settlement")
			return_started = true
			if not command("navigate",{"point":return_route[return_waypoint]},false).ok: break
			rally_fleet("xiamen")
			stamp("return-to-xiamen")
		if return_started:
			var return_target := Vector2(float(return_route[return_waypoint].x),float(return_route[return_waypoint].z))
			if position.distance_to(return_target)<35.0 and return_waypoint<return_route.size()-1:
				return_waypoint += 1
				if not command("navigate",{"point":return_route[return_waypoint]},false).ok: break
			var all_near := true
			for member: Dictionary in packet.naval.ships:
				if not member.id in packet.runtime.controllableShipIds or member.hull<=0: continue
				var delta := Vector2(float(member.visual.position.x)-float(Catalog.DATA.ports.xiamen.position.x),float(member.visual.position.z)-float(Catalog.DATA.ports.xiamen.position.z))
				all_near = all_near and delta.length()<=55.0 and Vector2(float(member.visual.velocity.x),float(member.visual.velocity.z)).length()<=0.75
				if not runtime.simulation.encounter.isAnchored(member.id): last_moor_revision = -1
			if packet.runtime.canDock.xiamen.ok and (not safely_returned or all_near and last_moor_revision<0):
				if not command("dock",{"portId":"xiamen"}).ok: break
				safely_returned = runtime.snapshot().campaign.currentPortId=="xiamen"
				last_moor_revision = runtime.snapshot().campaign.revision
				stamp("actual-xiamen-dock")
			if safely_returned and runtime.snapshot().runtime.canSave:
				var exported: Dictionary = runtime.export_save("2026-10-12T00:00:00.000Z")
				if check(exported.get("ok",false),"normal full-fleet Xiamen checkpoint export"):
					result.confirmedCheckpointJson = exported.json
					var saved: Dictionary = Codec.decode(exported.json)
					check(saved.get("ok",false) and Codec._equal(saved.get("state"),runtime.snapshot().campaign),"normal final decoded checkpoint equals exact live campaign")
					stamp("full-fleet-xiamen-checkpoint")
					break
		if packet.campaign.simulationSeconds>=next_stamp: stamp("voyage-progress"); next_stamp+=15.0
		if iteration%60==0: await process_frame
	var final: Dictionary = runtime.snapshot()
	var evaluation: Dictionary = runtime.campaign.evaluate_convoy("convoy-002")
	check(evaluation.reason!="in-progress","real voyage reaches terminal actual arrival/loss outcome")
	check(evaluation.delivered==20 and evaluation.lost==0,"actual twenty delivered and zero cargo lost")
	check(final.campaign.contracts["convoy-002"].status=="settled","actual contract claimed through authority")
	check(safely_returned and final.campaign.currentPortId=="xiamen","actual safe Xiamen docking through authority")
	check(not result.confirmedCheckpointJson.is_empty(),"normal confirmed full-fleet final checkpoint exists")
	if original.vessels[original.campaignId+"-enemy"].damage.hull<=0:
		check(final.campaign.vessels[original.campaignId+"-enemy"].damage.hull<=0,"checkpoint dead enemy remains dead without respawn")
	result.actualSafeReturn = safely_returned
	result.evaluation = evaluation
	result.casualties = casualty_evidence(original,final.campaign)
	result.acceptedSimulationSeconds = final.campaign.simulationSeconds-starting_seconds
	result.acceptedSteps = accepted_steps
	result.sumRuntimeAcceptedSeconds = accepted_seconds
	check(absf(accepted_seconds-result.acceptedSimulationSeconds)<1e-6,"aggregated accepted native time equals campaign elapsed simulation time")
	check(FileAccess.get_file_as_string(journey.path)==source_bytes,"immutable input journey remains byte exact")
	for path: String in result.sourceHashes:
		check(result.sourceHashes[path]==FileAccess.get_sha256("res://"+path),"frozen source throughout continued voyage: "+path)
	finish()
func finish() -> void:
	result.wallClockSeconds = (Time.get_ticks_usec()-wall_start)/1000000.0
	result.assertions = assertions; result.failures = failures; result.checks = checks; result.commands = commands; result.stages = stages
	result.final = runtime.snapshot() if ready else {}
	var guard: Dictionary = Paths.output(arguments)
	if not guard.ok: printerr("CONTINUED_VOYAGE_OUTPUT_REJECTED ",guard.reason); runtime.dispose(); quit(2); return
	var directory := ProjectSettings.globalize_path(output_path.get_base_dir())
	if DirAccess.make_dir_recursive_absolute(directory)!=OK: printerr("FAIL: evidence directory creation"); runtime.dispose(); quit(2); return
	var file := FileAccess.open(output_path,FileAccess.WRITE)
	if file==null: printerr("FAIL: evidence write"); runtime.dispose(); quit(2); return
	file.store_string(JSON.stringify(result,"\t",false,true)); file.flush()
	var written := file.get_error()==OK; file.close()
	runtime.dispose()
	print("CONTINUED_VOYAGE_COMPLETE assertions=",assertions," failures=",failures," writeOk=",written)
	quit(1 if failures or not written else 0)
