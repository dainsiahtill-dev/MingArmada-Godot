extends SceneTree
## Staged future acceptance contract. Not part of the currently enabled suite.
## Move into tests only when implementing Campaign fire persistence and procurement.
## Pending production integration: root owns all Godot execution and the GPU gate.

const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Bridge = preload("res://game/runtime/near_field_bridge.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
var checks := 0
var failures := 0
var authorized_state: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL Mingqi fire authority: ", label)
	return ok

func near(actual: float, wanted: float, label: String) -> void:
	check(absf(actual - wanted) < 0.00000001, label)

func raw_save(state: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":state.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-29T00:00:00.000Z","simulationSeconds":state.simulationSeconds,"state":state}, "", false, true)

func native_ship(runtime: RefCounted, id: String) -> Dictionary:
	for ship: Dictionary in runtime.snapshot().naval.ships:
		if ship.id == id:
			return ship
	return {}

func from_state(state: Dictionary) -> RefCounted:
	var session = Campaign.new()
	session._state = state.duplicate(true)
	var runtime = Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0, session).ok, "real runtime builds explicit fire fixture")
	return runtime

func buy(runtime: RefCounted, item: Variant, qty: Variant, id: String) -> Dictionary:
	return runtime.command({"type":"buy-fire-supplies","commandId":id,"expectedRevision":runtime.snapshot().campaign.revision,"item":item,"qty":qty})

func run() -> void:
	var probe = Campaign.new()
	if not check(probe.has_method("quote_fire_supplies"), "Campaign exposes fire-supply quote and transaction seam"):
		finish()
		return
	_legacy_and_schema()
	var runtime = Runtime.new()
	if not check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).ok, "real opening runtime builds"):
		finish()
		return
	var packet: Dictionary = runtime.snapshot()
	if not check(runtime.command({"type":"accept-convoy","commandId":"fire-authority-lease","expectedRevision":packet.campaign.revision}).ok, "real lease authorizes flagship before buying"):
		runtime.dispose()
		finish()
		return
	packet = runtime.snapshot()
	if not check(runtime.command({"type":"dock","portId":"xiamen","commandId":"fire-authority-dock","expectedRevision":packet.campaign.revision}).ok, "real safe dock anchors authorized flagship"):
		runtime.dispose()
		finish()
		return
	authorized_state = runtime.snapshot().campaign.duplicate(true)
	_purchase(runtime)
	runtime.dispose()
	_purchase_failures()
	_busy_safety_and_arrival()
	_native_reprojection_and_queue()
	_far_pin()
	finish()

func _legacy_and_schema() -> void:
	var legacy := FileAccess.get_file_as_string("res://tests/fixtures/web-save-v2.json")
	var session = Campaign.new()
	if not check(session.restore(legacy), "unchanged old web save remains readable"):
		return
	var old: Dictionary = session.snapshot()
	for vessel: Dictionary in old.vessels.values():
		check(not vessel.has("fireControl") and not vessel.has("fireLauncher"), "old save receives neither free stock nor silent extension")
	var flag: Dictionary = old.vessels[old.flagshipId]
	var setup: Dictionary = session.near_field_setup(flag, "player")
	check(not setup.has("fireControl") and not setup.has("fireLauncher"), "old near-field setup retains absence")
	var state := old.duplicate(true)
	var fire: Dictionary = Fire.initial(4)
	fire.heat = 20.0
	fire.fuelSeconds = 17.25
	fire.crewDamageCarry = 0.875
	fire.workCarry = 1.75
	fire.assignedFirefighters = 3
	fire.pendingFirefighters = 2
	fire.transferTicks = 17
	var launcher: Dictionary = Launcher.initial(2, 1)
	launcher.cooldownSeconds = 7.5
	launcher.operationSeconds = 1.5
	state.vessels[state.flagshipId].fireControl = fire
	state.vessels[state.flagshipId].fireLauncher = launcher
	state.vessels[state.flagshipId].damage.fire = 20.0
	if not check(session.restore(raw_save(state)), "strict optional fire objects restore without flattening their state"):
		return
	var restored: Dictionary = session.snapshot().vessels[state.flagshipId]
	check(restored.fireControl == fire and restored.fireLauncher == launcher and restored.damage.fire == 20.0, "all carries, travel ticks, stock and remaining launcher seconds survive restore")
	var encoded: String = session.serialize("2026-10-29T00:00:00.000Z")
	check(not encoded.is_empty() and Codec.decode(encoded).get("state",{}) == session.snapshot(), "fire objects round-trip through actual full-precision codec")
	setup = session.near_field_setup(restored, "player")
	check(setup.fireControl == fire and setup.fireLauncher == launcher and setup.crew == restored.crew.able and not setup.has("availableCrew"), "setup forwards exact extension and actual total crew")
	setup.fireControl.workCarry = 0.0
	setup.fireLauncher.ammo["fire-ball"] = 60
	check(session.snapshot().vessels[state.flagshipId].fireControl == fire and session.snapshot().vessels[state.flagshipId].fireLauncher == launcher, "setup deep copy cannot alter campaign stock or carry")
	var before: Dictionary = session.snapshot()
	for mutation: String in ["heat-mismatch", "extra-fire-key", "bool-supply", "fractional-crew", "too-many-workers", "bad-launcher", "persisted-derived-crew"]:
		var bad := state.duplicate(true)
		var vessel: Dictionary = bad.vessels[bad.flagshipId]
		match mutation:
			"heat-mismatch": vessel.damage.fire = 19.0
			"extra-fire-key": vessel.fireControl.unowned = 1
			"bool-supply": vessel.fireControl.supplies = true
			"fractional-crew": vessel.fireControl.pendingFirefighters = 1.5
			"too-many-workers": vessel.fireControl.pendingFirefighters = 128
			"bad-launcher": vessel.fireLauncher.operationSeconds = 2.01
			"persisted-derived-crew": vessel.availableCrew = 7
		check(not session.restore(raw_save(bad)) and session.snapshot() == before, "malformed or inconsistent saved fire state rejected atomically: " + mutation)
	var unresolved := old.duplicate(true)
	unresolved.vessels[unresolved.flagshipId].damage.fire = 9.0
	check(session.restore(raw_save(unresolved)), "legacy positive fire is preserved for explicit migration")
	check(session.snapshot().vessels[unresolved.flagshipId].damage.fire == 9.0 and not session.snapshot().vessels[unresolved.flagshipId].has("fireControl"), "legacy migration neither erases fire nor invents fuel or supplies")

func _purchase(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot().campaign
	for fixture: Array in [["suppression",3,2,6],["fire-ball",2,12,24],["thorn-ball",1,24,24]]:
		var quote: Dictionary = runtime.campaign.call("quote_fire_supplies", fixture[0], fixture[1])
		check(quote.get("ok",false) and quote.item == fixture[0] and quote.qty == fixture[1] and quote.unitPrice == fixture[2] and quote.cost == fixture[3], "read-only quote uses locked candidate price: " + fixture[0])
	check(runtime.snapshot().campaign == before, "quotes do not reserve money or create equipment")
	var command := {"type":"buy-fire-supplies","commandId":"fire-authority-suppression","expectedRevision":before.revision,"item":"suppression","qty":3}
	var receipt: Dictionary = runtime.command(command)
	if not check(receipt.get("ok",false), "real fenced purchase buys exactly three preparation portions"):
		return
	var once: Dictionary = runtime.snapshot().campaign
	check(runtime.command(command).get("ok",false) and runtime.snapshot().campaign == once, "same accepted command replays without double charge or duplicated portions")
	check(buy(runtime,"fire-ball",2,"fire-authority-ordinary").get("ok",false) and buy(runtime,"thorn-ball",1,"fire-authority-thorn").get("ok",false), "both paid payload kinds purchase through real business transactions")
	var after: Dictionary = runtime.snapshot().campaign
	var vessel: Dictionary = after.vessels[after.flagshipId]
	check(before.captain.silver - after.captain.silver == 54, "three purchases consume exactly 54 actual silver")
	check(vessel.fireControl.supplies == 3 and vessel.fireControl.workCarry == 0.0 and vessel.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":1}, "lazy setup grants only purchased stock with no free remainder")
	check(vessel.cargo == before.vessels[before.flagshipId].cargo and vessel.combat == before.vessels[before.flagshipId].combat and vessel.crew == before.vessels[before.flagshipId].crew, "purchase preserves real cargo, ordinary ammunition, reload and total crew")
	var details: Dictionary = receipt.receipt.get("details",{})
	check(details.get("kind") == "fire-purchase" and details.item == "suppression" and details.qty == 3 and details.unitPrice == 2 and details.cost == 6 and details.silverBefore - details.silverAfter == 6 and details.stockAfter - details.stockBefore == 3, "receipt proves item, exact stock delta and exact silver debit")
	var native: Dictionary = native_ship(runtime,after.flagshipId)
	check(native.fireControl == vessel.fireControl and native.fireLauncher == vessel.fireLauncher, "successful purchase projects paid stock to same live native flagship")
	check(after.vessels[after.campaignId+"-fast"].get("fireLauncher") == before.vessels[before.campaignId+"-fast"].get("fireLauncher") and after.vessels[after.campaignId+"-fast"].get("fireControl") == before.vessels[before.campaignId+"-fast"].get("fireControl"), "flagship purchase cannot fill another ship")
	check(not runtime.campaign.serialize("2026-10-29T00:00:00.000Z").is_empty(), "real purchase receipt remains strictly serializable")

func _purchase_failures() -> void:
	var runtime: RefCounted = from_state(authorized_state)
	for pair: Array in [["unknown",1],["suppression",0],["suppression",-1],["suppression",true],["suppression",1.5],["suppression",601],["fire-ball",61],["thorn-ball",61]]:
		var before: Dictionary = runtime.snapshot().campaign
		check(not buy(runtime,pair[0],pair[1],"fire-invalid-"+str(checks)).get("ok",false) and runtime.snapshot().campaign == before, "invalid purchase is atomic: " + str(pair))
	var no_fence: Dictionary = runtime.campaign.command({"type":"buy-fire-supplies","commandId":"fire-no-fence","expectedRevision":runtime.snapshot().campaign.revision,"item":"suppression","qty":1})
	check(not no_fence.get("ok",false), "money-changing purchase requires actual native fence")
	runtime.dispose()
	var poor := authorized_state.duplicate(true)
	poor.captain.silver = 1
	runtime = from_state(poor)
	var before: Dictionary = runtime.snapshot().campaign
	check(not buy(runtime,"suppression",1,"fire-poor").get("ok",false) and runtime.snapshot().campaign == before, "insufficient silver gives no free preparation and changes no state")
	runtime.dispose()
	var full := authorized_state.duplicate(true)
	full.vessels[full.flagshipId].fireControl = Fire.initial(600)
	full.vessels[full.flagshipId].fireLauncher = Launcher.initial(60,60)
	runtime = from_state(full)
	for item: String in ["suppression","fire-ball","thorn-ball"]:
		before = runtime.snapshot().campaign
		check(not buy(runtime,item,1,"fire-cap-"+item).get("ok",false) and runtime.snapshot().campaign == before, "capacity rejection neither charges nor partially fills: " + item)
	runtime.dispose()

func _busy_safety_and_arrival() -> void:
	var safety = Runtime.new()
	var cold = Campaign.new()
	cold._state = authorized_state.duplicate(true)
	if not check(safety.check_safety(cold).get("ok",false), "matched cold source fleet is safe before adding a busy factor"):
		return
	for factor: String in ["legacy-fire","heat","assigned","pending","transfer","operation"]:
		var state := authorized_state.duplicate(true)
		var vessel: Dictionary = state.vessels[state.flagshipId]
		vessel.fireControl = Fire.initial()
		vessel.fireLauncher = Launcher.initial()
		vessel.damage.hull = 80.0
		match factor:
			"legacy-fire": vessel.erase("fireControl"); vessel.damage.fire = 9.0
			"heat": vessel.fireControl.heat = 9.0; vessel.fireControl.fuelSeconds = 18.0; vessel.damage.fire = 9.0
			"assigned": vessel.fireControl.assignedFirefighters = 2
			"pending": vessel.fireControl.pendingFirefighters = 2
			"transfer": vessel.fireControl.transferTicks = 1
			"operation": vessel.fireLauncher.operationSeconds = 1.0; vessel.fireLauncher.cooldownSeconds = 11.0
		var session = Campaign.new()
		session._state = state
		var denied: Dictionary = safety.check_safety(session)
		check(not denied.get("ok",false) and denied.get("reason") == "save-fire-busy:" + state.flagshipId, "busy factor specifically blocks safe save: " + factor)
		var purchase_quote: Dictionary = session.call("quote_fire_supplies","suppression",1)
		check(not purchase_quote.get("ok",false) and purchase_quote.get("reason") == "ship-fire-busy", "busy factor specifically blocks procurement quote: " + factor)
		var repair_quote: Dictionary = session.quote_port_service({"type":"repair","shipId":state.flagshipId})
		check(not repair_quote.get("ok",false) and repair_quote.get("reason") == "ship-fire-busy", "busy factor specifically blocks otherwise-needed repair: " + factor)
	var cooled := authorized_state.duplicate(true)
	cooled.vessels[cooled.flagshipId].fireLauncher = Launcher.initial(1,0)
	cooled.vessels[cooled.flagshipId].fireLauncher.cooldownSeconds = 7.5
	cold._state = cooled
	check(safety.check_safety(cold).get("ok",false), "cold idle fleet may safely save remaining launcher cooldown")
	check(Codec.decode(cold.serialize("2026-10-29T00:00:00.000Z")).get("state",{}).get("vessels",{}).get(cooled.flagshipId,{}).get("fireLauncher",{}).get("cooldownSeconds") == 7.5, "allowed cooldown save retains original remaining seconds")
	var arrival := authorized_state.duplicate(true)
	var id: String = arrival.campaignId + "-grain-a"
	var grain: Dictionary = arrival.vessels[id]
	var voyage: Dictionary = arrival.voyages[grain.voyageId]
	voyage.status = "underway"
	grain.pose.position = arrival.ports[voyage.destinationId].position.duplicate(true)
	grain.pose.speed = 0.0
	grain.fireControl = Fire.initial()
	grain.fireControl.heat = 9.0
	grain.fireControl.fuelSeconds = 18.0
	grain.damage.fire = 9.0
	var cargo_before: Dictionary = grain.cargo.duplicate(true)
	cold._inspect(arrival,grain)
	check(voyage.status == "underway" and grain.cargo == cargo_before, "automatic arrival cannot unload cargo while burning")
	var heritage := authorized_state.duplicate(true)
	var inherited: Dictionary = heritage.vessels[heritage.campaignId+"-heritage"]
	inherited.fireLauncher = Launcher.initial()
	inherited.fireLauncher.cooldownSeconds = 1.0
	check(not Bridge.ordinary_heritage_berth(heritage), "heritage cooldown cannot enter skipped ordinary berth and freeze")

func _native_reprojection_and_queue() -> void:
	var state := authorized_state.duplicate(true)
	var vessel: Dictionary = state.vessels[state.flagshipId]
	vessel.fireControl = Fire.initial(4)
	vessel.fireControl.heat = 20.0
	vessel.fireControl.fuelSeconds = 18.0
	vessel.fireControl.crewDamageCarry = 0.875
	vessel.fireControl.workCarry = 1.9
	vessel.fireControl.assignedFirefighters = 2
	vessel.fireControl.pendingFirefighters = 2
	vessel.damage.fire = 20.0
	vessel.fireLauncher = Launcher.initial(2,1)
	vessel.fireLauncher.cooldownSeconds = 7.5
	var runtime: RefCounted = from_state(state)
	var total_crew: int = int(vessel.crew.able)
	for tick in range(4):
		check(runtime.advance(1.0/60.0) > 0.0, "real fixed tick advances fire fixture")
		var packet: Dictionary = runtime.snapshot()
		var source: Dictionary = packet.campaign.vessels[state.flagshipId]
		var live: Dictionary = native_ship(runtime,state.flagshipId)
		check(source.fireControl == live.fireControl and source.fireLauncher == live.fireLauncher and source.damage.fire == live.fireControl.heat, "per-tick Bridge round trip preserves exact live extension")
		check(source.crew.able == live.crew and source.crew.able == total_crew and live.availableCrew == total_crew-2, "derived reservation does not replace actual crew population")
	var final: Dictionary = runtime.snapshot().campaign.vessels[state.flagshipId]
	check(final.fireControl.supplies == 3 and final.fireControl.crewDamageCarry > 0.875, "fractional work crosses one real preparation while fractional casualty carry accumulates")
	near(final.fireControl.workCarry, 1.0/30.0, "work remainder survives four real Bridge projections")
	near(final.fireLauncher.cooldownSeconds, 7.5-4.0/60.0, "reconcile does not restart existing launcher deadline")
	runtime.dispose()
	runtime = from_state(authorized_state)
	runtime.set_pause("player",true)
	var before: Dictionary = runtime.snapshot()
	check(not runtime.command({"type":"fire-control","crew":2}).get("ok",false) and not runtime.command({"type":"launch-fire","targetId":state.campaignId+"-enemy","payload":"fire-ball"}).get("ok",false), "paused runtime rejects both new native action types")
	check(runtime.snapshot().campaign == before.campaign and runtime.snapshot().naval == before.naval, "paused actions do not mutate either authority")
	runtime.set_pause("player",false)
	var queued: Dictionary = runtime.command({"type":"fire-control","crew":2})
	check(queued.get("ok",false) and queued.get("queued",false), "fire assignment enters original action queue with default selected ship")
	runtime.advance(1.0/60.0)
	var assigned: Dictionary = runtime.snapshot().campaign.vessels[authorized_state.flagshipId]
	check(assigned.get("fireControl",{}).get("pendingFirefighters") == 2 and assigned.fireControl.transferTicks == 119 and assigned.crew == authorized_state.vessels[authorized_state.flagshipId].crew, "queued assignment reaches one real tick and preserves crew buckets")
	runtime.dispose()

func _far_pin() -> void:
	for factor: String in ["heat","cooldown"]:
		var state := authorized_state.duplicate(true)
		var id: String = state.campaignId + "-enemy"
		var enemy: Dictionary = state.vessels[id]
		enemy.representation = "route"
		enemy.pose.position = {"x":5000.0,"z":5000.0}
		if factor == "heat":
			enemy.fireControl = Fire.initial()
			enemy.fireControl.heat = 20.0
			enemy.fireControl.fuelSeconds = 18.0
			enemy.damage.fire = 20.0
		else:
			enemy.fireLauncher = Launcher.initial()
			enemy.fireLauncher.cooldownSeconds = 3.0
		var runtime: RefCounted = from_state(state)
		if not check(not native_ship(runtime,id).is_empty(), "far in-port enemy is included before skip branch: " + factor):
			runtime.dispose()
			continue
		for i in range(3):
			runtime.advance(1.0/60.0)
		var live: Dictionary = native_ship(runtime,id)
		check(not live.is_empty() and id in runtime.bridge.near_ids(), "busy far enemy remains pinned during reconcile: " + factor)
		if factor == "heat":
			check(live.fireControl.fuelSeconds < 18.0 and live.fireControl.heat > 20.0, "far fire accepts real ticks instead of freezing")
		else:
			near(live.fireLauncher.cooldownSeconds, 2.95, "far cooldown accepts three real ticks instead of freezing")
		runtime.dispose()

func finish() -> void:
	print("MINGQI_FIRE_AUTHORITY_TEST_COMPLETE checks=", checks, " failures=", failures)
	quit(0 if failures == 0 else 1)
