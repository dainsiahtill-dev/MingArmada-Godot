extends SceneTree
## Procurement acceptance only. Root owns RED/GREEN and all Godot execution.
## Uses actual Runtime commands and native fences; no simulated purchase handler.

const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Fire = preload("res://modules/naval_simulation/combat/fire_control.gd")
const Launcher = preload("res://modules/naval_simulation/combat/fire_launcher.gd")
const UTC := "2026-10-29T00:00:00.000Z"
var checks := 0
var failures := 0
var authorized_state: Dictionary = {}

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		print("FAIL Mingqi fire supplies: ", label)
	return ok

func native_ship(packet: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in packet.get("naval",{}).get("ships",[]):
		if ship.id == id:
			return ship
	return {}

func buy(runtime: RefCounted, item: Variant, qty: Variant, id: String) -> Dictionary:
	return runtime.command({"type":"buy-fire-supplies","commandId":id,"expectedRevision":runtime.snapshot().campaign.revision,"item":item,"qty":qty})

func open_safe_runtime() -> RefCounted:
	var runtime = Runtime.new()
	if not check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).get("ok",false), "real opening Runtime builds"):
		runtime.dispose()
		return null
	var packet: Dictionary = runtime.snapshot()
	if not check(runtime.command({"type":"accept-convoy","commandId":"fire-supplies-lease","expectedRevision":packet.campaign.revision}).get("ok",false), "real convoy lease authorizes flagship"):
		runtime.dispose()
		return null
	packet = runtime.snapshot()
	if not check(runtime.command({"type":"dock","portId":"xiamen","commandId":"fire-supplies-dock","expectedRevision":packet.campaign.revision}).get("ok",false), "real safe dock anchors authorized flagship"):
		runtime.dispose()
		return null
	check(runtime.simulation.encounter.isAnchored(runtime.snapshot().campaign.flagshipId), "purchase fixture has actual native flagship anchor")
	return runtime

func from_state(state: Dictionary, label: String) -> RefCounted:
	var session = Campaign.new()
	session._state = state.duplicate(true)
	var runtime = Runtime.new()
	if not check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0,session).get("ok",false), "real Runtime rebuilds " + label):
		runtime.dispose()
		return null
	var packet: Dictionary = runtime.snapshot()
	if not check(runtime.command({"type":"dock","portId":"xiamen","commandId":"fire-supplies-redock-" + label,"expectedRevision":packet.campaign.revision}).get("ok",false), "rebuilt fixture actually docks " + label):
		runtime.dispose()
		return null
	return runtime

func run() -> void:
	var probe = Campaign.new()
	# Missing implementation produces the intended clean RED before invoking it.
	if not check(probe.has_method("quote_fire_supplies"), "Campaign exposes quote_fire_supplies procurement API"):
		finish()
		return
	_no_free_initial_stock(probe.snapshot())
	var runtime: RefCounted = open_safe_runtime()
	if runtime == null:
		finish()
		return
	authorized_state = runtime.snapshot().campaign.duplicate(true)
	_no_free_initial_stock(authorized_state)
	_quotes_are_read_only(runtime)
	if _paid_purchase_and_replay(runtime):
		_snapshot_is_detached(runtime)
		_invalid_inputs_are_atomic(runtime)
	runtime.dispose()
	_capacity_is_atomic()
	_insufficient_silver_is_atomic()
	finish()

func _no_free_initial_stock(state: Dictionary) -> void:
	for vessel: Dictionary in state.vessels.values():
		check(not vessel.has("fireControl") and not vessel.has("fireLauncher"), "opening or safe docking grants no fire stock: " + vessel.id)

func _quotes_are_read_only(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot()
	for fixture: Array in [["suppression",3,2,6],["fire-ball",2,12,24],["thorn-ball",1,24,24]]:
		var quote: Dictionary = runtime.campaign.call("quote_fire_supplies",fixture[0],fixture[1])
		check(quote.get("ok",false) and quote.get("item") == fixture[0] and quote.get("qty") == fixture[1] and quote.get("unitPrice") == fixture[2] and quote.get("cost") == fixture[3], "quote returns exact item, quantity and candidate price: " + fixture[0])
	var after: Dictionary = runtime.snapshot()
	check(after.campaign == before.campaign and after.naval == before.naval, "quotes neither deduct silver, create stock nor change either authority")

func _receipt(receipt: Dictionary, before: Dictionary, after: Dictionary, item: String, qty: int, unit_price: int, cost: int) -> void:
	var details: Dictionary = receipt.get("receipt",{}).get("details",{})
	var fields := ["kind","portId","shipId","item","qty","unitPrice","cost","silverBefore","silverAfter","stockBefore","stockAfter"]
	if not check(details.has_all(fields), "purchase receipt includes all required accounting fields: " + item):
		return
	check(details.kind == "fire-purchase" and details.portId == "xiamen" and details.shipId == before.flagshipId and details.item == item, "receipt binds item to actual flagship and port: " + item)
	check(details.qty == qty and details.unitPrice == unit_price and details.cost == cost and details.cost == details.unitPrice * details.qty, "receipt proves exact purchased quantity and price: " + item)
	check(details.silverBefore == before.captain.silver and details.silverAfter == after.captain.silver and details.silverBefore - details.silverAfter == cost, "receipt reconciles actual silver debit: " + item)
	check(details.stockBefore == 0 and details.stockAfter == qty and details.stockAfter - details.stockBefore == qty, "receipt proves only paid stock was added: " + item)

func _paid_purchase_and_replay(runtime: RefCounted) -> bool:
	var before: Dictionary = runtime.snapshot()
	var first_command := {"type":"buy-fire-supplies","commandId":"fire-supplies-paid-suppression","expectedRevision":before.campaign.revision,"item":"suppression","qty":3}
	var receipt: Dictionary = runtime.command(first_command)
	if not check(receipt.get("ok",false), "actual fenced purchase buys exactly three suppression portions"):
		return false
	var once: Dictionary = runtime.snapshot()
	var first_flag: Dictionary = once.campaign.vessels[once.campaign.flagshipId]
	if not check(first_flag.get("fireControl") is Dictionary, "first suppression purchase creates its explicit zero-based object"):
		return false
	check(first_flag.fireControl.supplies == 3 and not first_flag.has("fireLauncher"), "suppression purchase creates no free payloads or launcher")
	_receipt(receipt,before.campaign,once.campaign,"suppression",3,2,6)
	var replay: Dictionary = runtime.command(first_command)
	var replayed: Dictionary = runtime.snapshot()
	check(replay.get("ok",false) and replay.get("receipt") == receipt.get("receipt"), "identical commandId replays original accepted receipt despite old expectedRevision")
	check(replayed.campaign == once.campaign and replayed.naval == once.naval, "receipt replay neither charges twice nor adds duplicate stock or native projection")
	var fire_before: Dictionary = runtime.snapshot().campaign
	var control_before: Dictionary = fire_before.vessels[fire_before.flagshipId].fireControl.duplicate(true)
	var fire_receipt := buy(runtime,"fire-ball",2,"fire-supplies-paid-fire-ball")
	if not check(fire_receipt.get("ok",false), "actual fenced purchase buys two fire balls"):
		return false
	var fire_after: Dictionary = runtime.snapshot().campaign
	_receipt(fire_receipt,fire_before,fire_after,"fire-ball",2,12,24)
	var fire_flag: Dictionary = fire_after.vessels[fire_after.flagshipId]
	check(fire_flag.fireControl == control_before and fire_flag.get("fireLauncher",{}).get("ammo") == {"fire-ball":2,"thorn-ball":0}, "payload purchase preserves suppression state and grants no other payload")
	var thorn_before: Dictionary = runtime.snapshot().campaign
	var thorn_receipt := buy(runtime,"thorn-ball",1,"fire-supplies-paid-thorn-ball")
	if not check(thorn_receipt.get("ok",false), "actual fenced purchase buys one thorn ball"):
		return false
	var after: Dictionary = runtime.snapshot()
	_receipt(thorn_receipt,thorn_before,after.campaign,"thorn-ball",1,24,24)
	var vessel: Dictionary = after.campaign.vessels[after.campaign.flagshipId]
	if not check(vessel.get("fireControl") is Dictionary and vessel.get("fireLauncher") is Dictionary, "paid objects are both present after all purchases"):
		return false
	check(before.campaign.captain.silver - after.campaign.captain.silver == 54, "3*2 + 2*12 + 1*24 costs exactly 54 actual silver")
	check(vessel.fireControl.supplies == 3 and vessel.fireControl.workCarry == 0.0 and vessel.fireLauncher.ammo == {"fire-ball":2,"thorn-ball":1}, "final stock contains exactly purchased units and zero suppression work carry")
	var original: Dictionary = before.campaign.vessels[before.campaign.flagshipId]
	check(vessel.cargo == original.cargo and vessel.combat == original.combat and vessel.crew == original.crew, "purchases preserve cargo, ordinary ammo, both reload clocks and real crew buckets")
	check(after.campaign.ports == before.campaign.ports, "fire services do not consume grain, drinking water or another existing port commodity")
	var live := native_ship(after,after.campaign.flagshipId)
	check(live.get("fireControl") == vessel.fireControl and live.get("fireLauncher") == vessel.fireLauncher, "paid stock projects into the same actual native flagship")
	var original_live := native_ship(before,before.campaign.flagshipId)
	check(live.get("ammo") == original_live.get("ammo") and live.get("cooldownSeconds") == original_live.get("cooldownSeconds") and live.get("crew") == original_live.get("crew"), "native ordinary ammo, reload clocks and total population remain unchanged")
	for id: String in before.campaign.vessels:
		if id == before.campaign.flagshipId:
			continue
		var other: Dictionary = after.campaign.vessels[id]
		check(other.get("fireControl") == before.campaign.vessels[id].get("fireControl") and other.get("fireLauncher") == before.campaign.vessels[id].get("fireLauncher"), "flagship purchase cannot fill another vessel: " + id)
	var saved: String = runtime.campaign.serialize(UTC)
	check(not saved.is_empty() and Codec.decode(saved).get("state") == after.campaign, "real paid purchase receipts and inventories round trip through strict codec")
	return true

func _snapshot_is_detached(runtime: RefCounted) -> void:
	var before: Dictionary = runtime.snapshot()
	var detached: Dictionary = runtime.snapshot()
	var id: String = detached.campaign.flagshipId
	var vessel: Dictionary = detached.campaign.vessels[id]
	detached.campaign.captain.silver = 999999
	detached.campaign.ports.xiamen.stock.grain = 999999
	vessel.combat.ammo.solid = 999999
	vessel.combat.cooldownSeconds.port = 119.0
	vessel.crew.able = 0
	vessel.cargo.water = 999999
	vessel.fireControl.supplies = 600
	vessel.fireLauncher.ammo["fire-ball"] = 60
	var live := native_ship(detached,id)
	live.ammo.solid = 999999
	live.crew = 0
	live.cooldownSeconds.port = 119.0
	if live.get("fireControl") is Dictionary:
		live.fireControl.supplies = 600
	if live.get("fireLauncher") is Dictionary:
		live.fireLauncher.ammo["thorn-ball"] = 60
	var after: Dictionary = runtime.snapshot()
	check(after.campaign == before.campaign and after.naval == before.naval, "snapshot silver, port stores, cargo, ammo, reload, crew and fire inventories are detached read-only copies")

func _reject_command(runtime: RefCounted, command: Dictionary, label: String) -> void:
	var before: Dictionary = runtime.snapshot()
	check(not runtime.command(command).get("ok",false), "purchase rejected: " + label)
	var after: Dictionary = runtime.snapshot()
	check(after.campaign == before.campaign and after.naval == before.naval, "purchase rejection changes neither authority: " + label)

func _invalid_inputs_are_atomic(runtime: RefCounted) -> void:
	for fixture: Array in [["unknown",1],["suppression",0],["suppression",-1],["suppression",true],["suppression",false],["suppression",1.5],["suppression","3"],["suppression",null],["suppression",NAN],["suppression",INF],["suppression",-INF],["suppression",9007199254740991],["suppression",601],["fire-ball",61],["thorn-ball",61]]:
		var before: Dictionary = runtime.snapshot()
		var quote: Dictionary = runtime.campaign.call("quote_fire_supplies",fixture[0],fixture[1])
		check(not quote.get("ok",false), "read-only quote rejects invalid item or quantity: " + str(fixture))
		var after_quote: Dictionary = runtime.snapshot()
		check(after_quote.campaign == before.campaign and after_quote.naval == before.naval, "rejected quote changes neither authority")
		_reject_command(runtime,{"type":"buy-fire-supplies","commandId":"fire-supplies-invalid-" + str(checks),"expectedRevision":before.campaign.revision,"item":fixture[0],"qty":fixture[1]},str(fixture))
	var before: Dictionary = runtime.snapshot()
	_reject_command(runtime,{"type":"buy-fire-supplies","commandId":"fire-supplies-no-arbitrary-target","expectedRevision":before.campaign.revision,"shipId":before.campaign.campaignId + "-fast","item":"suppression","qty":1},"arbitrary shipId key")
	before = runtime.snapshot()
	var no_fence: Dictionary = runtime.campaign.command({"type":"buy-fire-supplies","commandId":"fire-supplies-no-native-fence","expectedRevision":before.campaign.revision,"item":"suppression","qty":1})
	check(not no_fence.get("ok",false), "money-changing purchase refuses missing native fence")
	check(runtime.snapshot().campaign == before.campaign and runtime.snapshot().naval == before.naval, "missing-fence refusal leaves money and stock untouched")

func _capacity_is_atomic() -> void:
	var state := authorized_state.duplicate(true)
	state.vessels[state.flagshipId].fireControl = Fire.initial(599)
	state.vessels[state.flagshipId].fireLauncher = Launcher.initial(59,59)
	var runtime: RefCounted = from_state(state,"capacity")
	if runtime == null:
		return
	for item: String in ["suppression","fire-ball","thorn-ball"]:
		var before: Dictionary = runtime.snapshot()
		_reject_command(runtime,{"type":"buy-fire-supplies","commandId":"fire-supplies-partial-cap-" + item,"expectedRevision":before.campaign.revision,"item":item,"qty":2},"capacity overflow cannot partially buy " + item)
	for item: String in ["suppression","fire-ball","thorn-ball"]:
		check(buy(runtime,item,1,"fire-supplies-exact-cap-" + item).get("ok",false), "one remaining slot accepts exactly one paid unit: " + item)
	var full: Dictionary = runtime.snapshot().campaign
	var vessel: Dictionary = full.vessels[full.flagshipId]
	check(vessel.fireControl.supplies == 600 and vessel.fireLauncher.ammo == {"fire-ball":60,"thorn-ball":60}, "independent exact capacities are 600 preparations and 60 of each payload")
	check(state.captain.silver - full.captain.silver == 38, "filling three final slots costs exactly 2+12+24 silver")
	for item: String in ["suppression","fire-ball","thorn-ball"]:
		var before: Dictionary = runtime.snapshot()
		_reject_command(runtime,{"type":"buy-fire-supplies","commandId":"fire-supplies-full-cap-" + item,"expectedRevision":before.campaign.revision,"item":item,"qty":1},"full capacity rejects another " + item)
	runtime.dispose()

func _insufficient_silver_is_atomic() -> void:
	var state := authorized_state.duplicate(true)
	state.captain.silver = 1
	var runtime: RefCounted = from_state(state,"insufficient-silver")
	if runtime == null:
		return
	for item: String in ["suppression","fire-ball","thorn-ball"]:
		var quote: Dictionary = runtime.campaign.call("quote_fire_supplies",item,1)
		check(not quote.get("ok",false) and quote.get("reason") == "insufficient-silver", "poor flagship receives explicit insufficient silver quote: " + item)
		var before: Dictionary = runtime.snapshot()
		_reject_command(runtime,{"type":"buy-fire-supplies","commandId":"fire-supplies-poor-" + item,"expectedRevision":before.campaign.revision,"item":item,"qty":1},"insufficient silver for " + item)
	var after: Dictionary = runtime.snapshot().campaign
	check(after.captain.silver == 1 and not after.vessels[after.flagshipId].has("fireControl") and not after.vessels[after.flagshipId].has("fireLauncher"), "failed purchases leave silver intact and create no free zero-based equipment")
	runtime.dispose()

func finish() -> void:
	print("Mingqi fire supplies: ","PASS" if failures == 0 else "FAIL"," (",checks," checks, ",failures," failures)")
	quit(0 if failures == 0 else 1)
