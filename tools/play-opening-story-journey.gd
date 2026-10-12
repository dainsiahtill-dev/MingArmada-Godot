extends SceneTree
## A captain driver uses only real runtime intents. No teleport, damage edits,
## cargo edits, victory injection, or instant contract completion.
const Runtime=preload("res://game/runtime/mingqi_runtime.gd")
const Height=preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout=preload("res://game/scenes/common/reference_geography.gd")
const Catalog=preload("res://game/domain/mingqi/catalog.gd")
const Gunnery=preload("res://modules/naval_simulation/combat/cannon_system.gd")
const Paths=preload("res://tools/qa-journey-paths.gd")
var runtime:=Runtime.new()
var heights:=Height.new()
var serial:=0
var assertions:=0
var failures:=0
var stages: Array=[]
var source_hashes: Dictionary={}
var commands: Array=[]
var checks: Array=[]
var held_keys: Dictionary={}
func _initialize() -> void: run.call_deferred()
func check(value: bool,detail: String) -> void:
	assertions+=1
	checks.append({"ok":value,"detail":detail})
	if not value: failures+=1; printerr("FAIL: ",detail)
static func write_verified(path: String, bytes: String) -> Dictionary:
	if FileAccess.file_exists(path) or DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
		return {"ok":false,"reason":"evidence-already-exists","writeError":ERR_ALREADY_EXISTS,"readbackExact":false}
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	if directory_error!=OK: return {"ok":false,"reason":"directory-write-failed","writeError":directory_error,"readbackExact":false}
	var file := FileAccess.open(path,FileAccess.WRITE)
	if file==null: return {"ok":false,"reason":"evidence-open-failed","writeError":FileAccess.get_open_error(),"readbackExact":false}
	file.store_string(bytes); file.flush()
	var write_error := file.get_error()
	file.close()
	var exact := FileAccess.get_file_as_string(path)==bytes
	return {"ok":write_error==OK and exact,"writeError":write_error,"readbackExact":exact}
func command(type: String,fields: Dictionary={}) -> Dictionary:
	serial+=1
	var input: Dictionary={"type":type,"commandId":"journey-"+str(serial),"expectedRevision":runtime.snapshot().campaign.revision}
	input.merge(fields)
	var result: Dictionary=runtime.command(input)
	commands.append({"simulationSeconds":runtime.snapshot().campaign.simulationSeconds,"input":input,"result":result})
	return result
func native(type: String,fields: Dictionary={}) -> Dictionary:
	var input: Dictionary={"type":type}; input.merge(fields)
	var result: Dictionary=runtime.command(input)
	commands.append({"simulationSeconds":runtime.snapshot().campaign.simulationSeconds,"input":input,"result":result})
	return result
func stamp(packet: Dictionary,label: String) -> void:
	var ships: Array=[]
	for ship: Dictionary in packet.naval.ships:
		ships.append({"id":ship.id,"position":ship.visual.position,"velocity":ship.visual.velocity,"heading":ship.visual.heading,"hull":ship.hull,"sail":ship.sail,"crew":ship.crew,"ammo":ship.ammo,"navigation":ship.get("navigation"),"nativeDiagnostics":ship,"navigationDiagnostics":navigation_diagnostics(ship.id)})
	stages.append({"label":label,"time":packet.campaign.simulationSeconds,"ships":ships,"voyages":packet.campaign.voyages,"contract":packet.campaign.contracts["convoy-001"],"storyObjective":packet.story.objective,"evaluation":runtime.campaign.evaluate_convoy("convoy-001")})
	print("STORY_JOURNEY ",label," time=",snappedf(packet.campaign.simulationSeconds,.1)," delivered=",runtime.campaign.evaluate_convoy("convoy-001").delivered)
func navigation_diagnostics(id: String) -> Dictionary:
	for live: Dictionary in runtime.simulation.encounter.ships:
		if live.state.id==id:
			return {"route":live.get("route"),"approachRecovery":live.get("approachRecovery"),"wetRouteEgress":live.get("wetRouteEgress"),"egressClearance":live.get("egressClearance"),"lowSpeedTurn":live.get("lowSpeedTurn"),"sailRecovery":live.get("sailRecovery"),"motion":live.core.get_snapshot()}.duplicate(true)
	return {}
func hold(key: String, pressed: bool) -> void:
	if held_keys.get(key,false)!=pressed:
		held_keys[key]=pressed
		commands.append({"simulationSeconds":runtime.snapshot().campaign.simulationSeconds,"input":{"type":"held-key","key":key,"pressed":pressed}})
	runtime.set_held(key,pressed)
func release_helm() -> void:
	for key: String in ["KeyW","KeyS","KeyA","KeyD"]: hold(key,false)
func captain_gun_course(flagship: Dictionary,enemy: Dictionary,distance: float) -> void:
	var bearing:=atan2(float(enemy.visual.position.z)-float(flagship.visual.position.z),float(enemy.visual.position.x)-float(flagship.visual.position.x))
	var heading: float=flagship.visual.heading
	var desired:=bearing
	if distance<=230.0:
		var wind: Dictionary=runtime.snapshot().naval.wind
		var wind_from:=atan2(float(wind.direction.y),float(wind.direction.x))
		var candidates: Array=[bearing+PI/2.0,bearing-PI/2.0]
		candidates.sort_custom(func(a,b):
			var a_wet_wind: bool=wind.speed<=0 or absf(wrapf(a-wind_from,-PI,PI))>=PI/3.0
			var b_wet_wind: bool=wind.speed<=0 or absf(wrapf(b-wind_from,-PI,PI))>=PI/3.0
			return a_wet_wind if a_wet_wind!=b_wet_wind else absf(wrapf(a-heading,-PI,PI))<absf(wrapf(b-heading,-PI,PI)))
		desired=candidates[0]
	var error:=wrapf(desired-heading,-PI,PI)
	# Real assisted helm keys only. Approach beyond range; brake and turn a
	# downwind gun side into the target. The native hull/shore/shot rules apply.
	hold("KeyW",distance>230.0)
	hold("KeyS",distance<=230.0)
	hold("KeyA",error<-.04)
	hold("KeyD",error>.04)
func run() -> void:
	var wall_start:=Time.get_ticks_usec()
	var args: Array=Array(OS.get_cmdline_user_args())
	var guarded: Dictionary=Paths.output(args)
	if not guarded.ok:
		printerr("JOURNEY_OUTPUT_REJECTED ",guarded.reason); quit(2); return
	if "--preflight" in args:
		print("OPENING_JOURNEY_PREFLIGHT_PASS acceptedSeconds=0 output=",guarded.path); quit(0); return
	for path: String in ["game/domain/mingqi/opening_story.gd","game/domain/mingqi/second_voyage_aftermath.gd","game/domain/mingqi/campaign.gd","game/domain/mingqi/catalog.gd","game/domain/persistence/save_codec.gd","game/runtime/mingqi_runtime.gd","game/runtime/near_field_bridge.gd","game/runtime/native_readiness.gd","modules/contracts/navigation_contract.gd","modules/naval_simulation/encounter.gd","modules/naval_simulation/navigation/approach_clearance.gd","modules/naval_simulation/navigation/wet_route_egress.gd","modules/naval_simulation/combat/cannon_system.gd","modules/naval_simulation/tactics/order_controller.gd","game/runtime/sailing_simulation.gd","modules/scene_engine/terrain/height_field.gd","game/scenes/common/reference_geography.gd","game/data/mingqi_geography.json","tools/qa-journey-paths.gd","tools/play-opening-story-journey.gd","tools/play-continued-voyage.gd"]:
		source_hashes[path]=FileAccess.get_sha256("res://"+path)
	source_hashes["tools/qa-journey-checkpoint.gd"]=FileAccess.get_sha256("res://tools/qa-journey-checkpoint.gd")
	var geography: Array=JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	check(heights.configure_ports(geography,true,Layout.options()),"same formal geography configures the captain journey")
	var flat:= "--flat" in OS.get_cmdline_user_args()
	var outer:= "--outer" in OS.get_cmdline_user_args()
	var tactical:= "--tactical" in OS.get_cmdline_user_args()
	var tactical_range:=200.0 if "--range200" in OS.get_cmdline_user_args() else 100.0
	var return_to_port:="--return" in OS.get_cmdline_user_args()
	var manual_fire:="--manual-fire" in OS.get_cmdline_user_args()
	var maximum_seconds:=2400.0 if "--deadline" in OS.get_cmdline_user_args() else 900.0
	var sampler: Callable=func(_x: float,_z: float)->float: return -24.0
	if not flat: sampler=heights.sample_height
	runtime.enable_reference_enhancements()
	check(runtime.configure(sampler).ok,"real native continuous opening starts")
	check(command("story-choice",{"sceneId":"old-ledger","choiceId":"settle-wages"}).ok,"captain pays actual old wages")
	check(command("accept-convoy").ok,"captain accepts the existing real grain voyage")
	check(command("story-choice",{"sceneId":"pilot-plan","choiceId":"hire-pilot"}).ok,"captain hires pilot for real shallow grain routes")
	check(command("depart").ok,"captain actually departs")
	var route: Array=Catalog.DATA.routes["xiamen-kinmen-outer" if outer else "xiamen-kinmen-deep"].points
	var waypoint:=1
	check(native("navigate",{"point":route[waypoint]}).ok,"captain follows existing deep flagship route")
	var escort: Dictionary={"id":"journey-"+str(serial+1),"shipIds":[runtime.snapshot().campaign.campaignId+"-fast"],"intent":{"kind":"protect","targetId":runtime.snapshot().campaign.campaignId+"-grain-a"},"issuedAt":runtime.snapshot().campaign.simulationSeconds}
	check(command("assign-order",{"order":escort}).ok,"captain assigns the real fast vessel to protect a grain transport")
	stamp(runtime.snapshot(),"departure")
	var next_stamp:=30.0
	var last_fire:=-100.0
	var combat_target:=""
	var claimed:=false
	var safely_returned:=false
	var fleet_regroup_started:=false
	var confirmed_checkpoint:=""
	for iteration in int(maximum_seconds/.2): # Bounded accepted time, never wall-clock or frame fast-forward.
		var consumed: float=runtime.advance(.2)
		if consumed<=0.0: check(false,"journey unexpectedly stopped consuming accepted time"); break
		var packet: Dictionary=runtime.snapshot()
		var flagship: Dictionary=runtime._ship(packet.naval,packet.campaign.flagshipId)
		if flagship.is_empty() or flagship.hull<=0: stamp(packet,"flagship-lost"); break
		var position:=Vector2(float(flagship.visual.position.x),float(flagship.visual.position.z))
		var target:=Vector2(float(route[waypoint].x),float(route[waypoint].z))
		if combat_target.is_empty() and position.distance_to(target)<35.0 and waypoint<route.size()-1:
			waypoint+=1; check(native("navigate",{"point":route[waypoint]}).ok,"captain advances deep route waypoint")
		# Fire real broadsides only when an actual hostile ship is close. Existing
		# gunnery still determines arc, ammo, reload, projectile collision and loss.
		var hostile:=false
		var nearest: Dictionary={}
		var nearest_distance:=INF
		for enemy: Dictionary in packet.naval.ships:
			if enemy.hull>0 and enemy.id in packet.runtime.policy.hostileTargets.get(flagship.id,[]):
				var distance:=position.distance_to(Vector2(float(enemy.visual.position.x),float(enemy.visual.position.z)))
				hostile=hostile or distance<250.0
				if distance<nearest_distance: nearest_distance=distance; nearest=enemy
		if manual_fire and hostile and combat_target.is_empty():
			combat_target=nearest.id
			check(native("navigate",{"point":null}).ok,"captain takes real helm for downwind broadside positioning")
		if manual_fire and not combat_target.is_empty() and not nearest.is_empty() and nearest_distance<500:
			captain_gun_course(flagship,nearest,nearest_distance)
		elif tactical and hostile and combat_target.is_empty():
			var fight_order: Dictionary={"id":"journey-"+str(serial+1),"shipIds":[flagship.id],"intent":{"kind":"keep-distance","targetId":nearest.id,"range":tactical_range},"issuedAt":packet.campaign.simulationSeconds}
			var ordered:=command("assign-order",{"order":fight_order})
			check(ordered.ok,"captain chooses the existing keep-distance tactic through live authority")
			if ordered.ok: combat_target=nearest.id
		if not combat_target.is_empty() and (nearest.is_empty() or nearest_distance>500.0):
			release_helm();combat_target=""; check(native("navigate",{"point":route[waypoint]}).ok,"captain returns to real voyage after clearing the threat")
		if hostile and packet.campaign.simulationSeconds-last_fire>=10.0:
			var fired:=false
			for side: String in ["port","starboard"]:
				var advice: Dictionary=Gunnery.broadside_status(packet.naval,flagship.id,side,packet.runtime.policy)
				if advice.phase=="ready" and not advice.targetId.is_empty():
					var fire_result:=native("fire",{"side":side})
					check(fire_result.ok,"live firing intent enters the real native command queue")
					fired=fire_result.ok or fired
			if fired: last_fire=packet.campaign.simulationSeconds
		if packet.campaign.simulationSeconds>=next_stamp:
			stamp(packet,"voyage-progress"); next_stamp+=30.0
		var evaluated: Dictionary=runtime.campaign.evaluate_convoy("convoy-001")
		if not claimed and evaluated.reason!="in-progress":
			check(command("claim-convoy",{"contractId":"convoy-001"}).ok,"captain claims only actual completed shipment")
			claimed=true
			stamp(runtime.snapshot(),"settlement")
			if not return_to_port: break
		if return_to_port and claimed and not safely_returned and packet.runtime.canDock.kinmen.ok:
			var docked:=command("dock",{"portId":"kinmen"})
			check(docked.ok,"captain docks only after real speed position and hostile safety checks")
			var met_clerk:=command("story-choice",{"sceneId":"first-return","choiceId":"buy-intelligence"})
			check(met_clerk.ok,"captain meets clerk at actual safe Kinmen and buys real stock intelligence")
			safely_returned=docked.ok and met_clerk.ok and runtime.snapshot().campaign.currentPortId=="kinmen"
			stamp(runtime.snapshot(),"safe-first-return")
		if safely_returned:
			if not fleet_regroup_started:
				fleet_regroup_started=true
				for member: Dictionary in runtime.snapshot().naval.ships:
					if member.id in runtime.snapshot().runtime.controllableShipIds and member.hull>0 and not runtime.simulation.encounter.isAnchored(member.id):
						var rally: Dictionary={"id":"journey-"+str(serial+1),"shipIds":[member.id],"intent":{"kind":"rally","point":Catalog.DATA.ports.kinmen.position},"issuedAt":runtime.snapshot().campaign.simulationSeconds}
						check(command("assign-order",{"order":rally}).ok,"captain rallies the actual undocked vessel to the harbor for next departure")
			var regrouped: Dictionary=runtime.snapshot()
			if regrouped.runtime.canSave:
				var exported: Dictionary=runtime.export_save("2026-10-12T00:00:00.000Z")
				check(exported.ok,"normal runtime exports a genuinely safe full fleet checkpoint")
				if exported.ok: confirmed_checkpoint=exported.json
				stamp(runtime.snapshot(),"fleet-moored-checkpoint")
				break
			var all_near:=true
			for member: Dictionary in regrouped.naval.ships:
				if not member.id in regrouped.runtime.controllableShipIds or member.hull<=0:continue
				var relative:=Vector2(member.visual.position.x-Catalog.DATA.ports.kinmen.position.x,member.visual.position.z-Catalog.DATA.ports.kinmen.position.z)
				all_near=all_near and relative.length()<=55 and Vector2(member.visual.velocity.x,member.visual.velocity.z).length()<=.75
			if all_near and regrouped.runtime.canDock.kinmen.ok:
				check(command("dock",{"portId":"kinmen"}).ok,"captain actually anchors the regrouped low speed fleet")
		if iteration%60==0: await process_frame
	var final: Dictionary=runtime.snapshot()
	release_helm()
	var evaluation: Dictionary=runtime.campaign.evaluate_convoy("convoy-001")
	check(evaluation.reason!="in-progress","real voyage reaches a delivered/lost terminal outcome")
	check(evaluation.delivered>0,"story plan preserves some actual grain to establish the next commission")
	check(final.campaign.contracts["convoy-001"].status=="settled","real shipment is claimed through the campaign")
	check(final.campaign.contracts.has("convoy-002"),"real positive delivery opens the next voyage")
	if return_to_port: check(safely_returned,"terminal convoy is followed by actual safe port conversation")
	if return_to_port:check(not confirmed_checkpoint.is_empty(),"actual return includes safe fleet mooring and a valid normal checkpoint")
	var player_fires:=0;var player_hits:=0
	for receipt: Dictionary in final.campaign.chronicle:
		if receipt.kind=="near-fire" and receipt.causeIds[0]==final.campaign.flagshipId: player_fires+=1
		if receipt.kind in ["near-hit","cargo-loss"] and receipt.causeIds.size()>=3 and receipt.causeIds[0]==final.campaign.flagshipId and receipt.causeIds[1]==final.campaign.campaignId+"-enemy": player_hits+=1
	if manual_fire:
		check(player_fires>0,"real assisted helm obtains a native fired volley, beyond queued=true")
		check(player_hits>0,"real projectile flight hits the hostile through native collision receipts")
	for path: String in source_hashes:
		check(source_hashes[path]==FileAccess.get_sha256("res://"+path),"frozen source throughout first voyage: "+path)
	var still_unused: Dictionary=Paths.output(args)
	if not still_unused.ok:
		printerr("JOURNEY_OUTPUT_REJECTED ",still_unused.reason); runtime.dispose(); quit(2); return
	var bytes := JSON.stringify({"mode":"headless native gameplay; no visual/performance claim","terrain":"flat control" if flat else "same formal game terrain","flagshipRoute":"xiamen-kinmen-outer" if outer else "xiamen-kinmen-deep","tactics":"real W/S/A/D assisted helm and same UI firing advice" if manual_fire else "existing keep-distance order and same UI firing advice" if tactical else "voyage navigation and same UI firing advice","maximumAcceptedSeconds":maximum_seconds,"wallClockSeconds":(Time.get_ticks_usec()-wall_start)/1000000.0,"acceptedSimulationSeconds":final.runtime.acceptedSeconds,"keepDistanceMeters":tactical_range if tactical and not manual_fire else null,"actualSafeReturn":safely_returned,"confirmedCheckpointJson":confirmed_checkpoint,"combatProof":{"nativeFlagshipFireReceipts":player_fires,"nativeFlagshipHitHostileReceipts":player_hits},"sourceHashes":source_hashes,"arguments":args,"commands":commands,"checks":checks,"assertions":assertions,"failures":failures,"stages":stages,"final":final},"\t",false,true)
	var written := write_verified(guarded.path,bytes)
	check(written.ok,"captain evidence flushed without error and exact bytes read back: "+str(written))
	runtime.dispose()
	print("OPENING_STORY_JOURNEY_COMPLETE assertions=",assertions," failures=",failures," writeOk=",written.ok)
	quit(1 if failures else 0)
