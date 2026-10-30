extends RefCounted
## Story world session: sole authority for money, ships, cargo, people, permits,
## agreements, ledgers, blockades and transfers. The progress layer never owns
## any of these. Commands are real settlements with unique receipts; gates copy
## the verified legacy math through story_rules.gd. No caller may pass an
## outcome/score/success — results derive from world and native facts only.

const Rules = preload("res://game/domain/story_world/story_rules.gd")

const CAMPAIGN_ID := "zheng-family-v1"
const SCHEMA_VERSION := 1
const MAX_RECEIPTS := 512
const MAX_FLEET := 8
const MAX_SILVER := 100000000
const MAX_GOODS_UNIT := 1000000
const GOODS := ["grain", "wood", "iron", "silk", "porcelain", "spices"]
const STATE_KEYS := ["schemaVersion", "campaignId", "seed", "runId", "day", "elapsedSeconds", "yearMarker", "silver", "relations", "flagshipId", "currentPortId", "battleActive", "fleet", "ports", "entities", "people", "permits", "agreements", "contracts", "captures", "landPositions", "blockades", "dispatches", "transfers", "rescued", "receipts", "intel", "orders", "weather", "meta", "log"]
const FORMATIONS := ["line", "abreast", "convoy"]

var state: Dictionary = {}
var latest_native: Dictionary = {}
var last_error := ""

func configure(opening: Dictionary, seed: int = 1661, run_id: String = "story") -> Dictionary:
	if typeof(opening) != TYPE_DICTIONARY or not _token(run_id, 96) or not _int(seed, -2147483648, 2147483647):
		return _fail("invalid world seed, run id or opening")
	var reason := _opening_reason(opening)
	if not reason.is_empty():
		return _fail(reason)
	var ports := {}
	for entry: Dictionary in opening.ports:
		var stock := {}
		var prices := {}
		var warehouse := {}
		var price_factor := {}
		for good: String in GOODS:
			stock[good] = int(entry.stock.get(good, 0))
			prices[good] = float(entry.prices.get(good, 1))
			warehouse[good] = 0
			price_factor[good] = Rules.price_factor(int(opening.get("day", 1)), str(entry.id), good)
		ports[entry.id] = {"id": entry.id, "x": float(entry.x), "z": float(entry.z), "tax": float(entry.tax), "faction": str(entry.faction), "services": entry.services.duplicate(true), "prices": prices, "stockCaps": entry.stockCaps.duplicate(true), "stock": stock, "warehouse": warehouse, "priceFactor": price_factor}
	var minted := {}
	var burned := {}
	for good: String in GOODS:
		minted[good] = 0
		burned[good] = 0
	var fleet := []
	for spec: Dictionary in opening.fleet:
		var ship := _new_ship(str(spec.id), str(spec.kind), str(spec.name), int(spec.get("crew", 0)))
		for good: String in GOODS:
			var quantity: int = int(spec.cargo.get(good, 0))
			ship.cargo[good] = quantity
			minted[good] += quantity
		fleet.append(ship)
	for port_id: Variant in ports:
		for good: String in GOODS:
			minted[good] += int(ports[port_id].stock[good])
	state = {"schemaVersion": SCHEMA_VERSION, "campaignId": CAMPAIGN_ID, "seed": int(seed), "runId": run_id, "day": int(opening.get("day", 1)), "elapsedSeconds": 0.0, "yearMarker": int(opening.get("yearMarker", 1623)), "silver": int(opening.get("silver", 650)), "relations": (opening.get("relations", {}) as Dictionary).duplicate(true), "flagshipId": str(opening.fleet[0].id), "currentPortId": str(opening.get("homePort", "")), "battleActive": false, "fleet": fleet, "ports": ports, "entities": {}, "people": [], "permits": [], "agreements": [], "contracts": {}, "captures": [], "landPositions": {}, "blockades": {}, "dispatches": [], "transfers": [], "rescued": [], "receipts": [], "intel": {}, "orders": {"formation": "line", "escorts": {}}, "weather": {"sea": "breeze", "wind": {"x": 0.86, "y": 0.5, "speed": 7.0}}, "meta": {"shipSequence": 1, "receiptSequence": 0, "minted": minted, "burned": burned, "difficultyTier": 1}, "log": []}
	_add_log("世界开账：%s。" % str(opening.get("log", "航程开始")))
	var canonical := validate_world(state)
	if not canonical.ok:
		return _fail(str(canonical.reason))
	state = canonical.state
	return _ok()

func attach_native(snapshot: Dictionary) -> void:
	if typeof(snapshot) != TYPE_DICTIONARY or not snapshot.has("ships"):
		return
	latest_native = snapshot
	var hostile_near := false
	for entry: Dictionary in snapshot.ships:
		var ship := _ship(str(entry.get("id", "")))
		if ship.is_empty():
			continue
		var visual: Dictionary = entry.get("visual", {})
		ship.position = {"x": float(visual.get("position", {}).get("x", 0.0)), "z": float(visual.get("position", {}).get("z", 0.0))}
		ship.speed = _length(visual.get("velocity", {"x": 0.0, "z": 0.0}))
		ship.heading = float(visual.get("heading", 0.0))
		ship.hull = int(entry.get("hull", ship.hull))
		ship.sail = int(entry.get("sail", ship.sail))
		ship.crew = int(entry.get("crew", ship.crew))
		if str(entry.get("team", "")) == "hostile" and int(entry.get("hull", 0)) > 0 and _distance(ship.position, _own_position()) <= 300.0:
			hostile_near = true
	state.battleActive = hostile_near

func command(c: Variant) -> Dictionary:
	if not state is Dictionary or state.is_empty():
		return _fail("world is not configured")
	if not c is Dictionary or not c.get("type") is String:
		return _fail("无效操作")
	if typeof(c.get("outcome")) != TYPE_NIL or typeof(c.get("success")) != TYPE_NIL or typeof(c.get("score")) != TYPE_NIL:
		return _fail("forged-world-result")
	match str(c.type):
		"dock": return _dock(c)
		"depart": return _depart(c)
		"buy": return _trade(c, true)
		"sell": return _trade(c, false)
		"deliver": return _deliver(c)
		"repair": return _repair(c)
		"recruit": return _recruit(c)
		"buy-ship": return _buy_ship(c)
		"transfer-cargo": return _transfer_cargo(c)
		"transfer-crew": return _transfer_crew(c)
		"sign-on": return _sign_on(c)
		"identify-target": return _identify(c)
		"resolve-boarding": return _boarding(c)
		"resolve-land": return _land(c)
		"sign-charter": return _sign_charter(c)
		"sign-terms": return _sign_terms(c)
		"load-manifest": return _load_manifest(c)
		"handover-facilities": return _handover(c)
		"transfer-manifest": return _transfer_manifest(c)
		"dispatch-convoy": return _dispatch(c)
		"return-dispatch": return _return_dispatch(c)
		"withdraw": return _withdraw(c)
		"store-goods": return _store_goods(c)
		"withdraw-goods": return _withdraw_goods(c)
		"upgrade": return _upgrade(c)
		"treat-wounded": return _treat_wounded(c)
		"attend-banquet": return _attend_banquet(c)
		"gather-intel": return _gather_intel(c)
		"set-formation": return _set_formation(c)
		"assign-escort": return _assign_escort(c)
		"release-escort": return _release_escort(c)
		"set-weather": return _set_weather(c)
		"rescue": return _rescue(c)
		"open-blockade": return _open_blockade(c)
		"breach-blockade": return _breach_blockade(c)
		"verify-blockade": return _verify_blockade(c)
		"close-blockade": return _close_blockade(c)
		"open-contract": return _open_contract(c)
		"close-contract": return _close_contract(c)
		"advance-day": return _advance_day(c)
		"transition": return _transition(c)
		"relations-delta": return _relations_delta(c)
		"set-difficulty": return _set_difficulty(c)
		"spawn-entity": return _spawn_entity(c)
		"mint-grant": return _mint_grant(c)
	return _fail("未知世界操作")

# --- sea gates -------------------------------------------------------------

func _dock(c: Dictionary) -> Dictionary:
	var entry := _port(str(c.get("portId", "")))
	if entry.is_empty():
		return _fail("港口不存在")
	if state.battleActive:
		return _fail("交战中无法靠港，请先脱离敌舰")
	var here := _own_position()
	if not Rules.dock_gate(_distance(here, {"x": entry.x, "z": entry.z}), float(_own_speed())):
		return _fail("距锚地超过55米或船速高于1.5米/秒")
	if int(state.relations.get(entry.faction, 0)) <= -50:
		return _fail("此势力拒绝你的舰队入港")
	state.currentPortId = entry.id
	for ship: Dictionary in state.fleet:
		ship.speed = 0.0
	return _receipt("dock", {"portId": entry.id})

func _depart(_c: Dictionary) -> Dictionary:
	if not str(state.currentPortId) is String or str(state.currentPortId).is_empty():
		return _fail("当前未靠港")
	for ship: Dictionary in state.fleet:
		if int(ship.hull) <= 0 or int(ship.crew) < int(ship.minCrew):
			return _fail("请修复船只并为每艘船配足最低船员 (%s hull=%d crew=%d min=%d)" % [str(ship.id), int(ship.hull), int(ship.crew), int(ship.minCrew)])
	var entry := _port(str(state.currentPortId))
	state.currentPortId = ""
	for ship: Dictionary in state.fleet:
		ship.speed = 0.0
	return _receipt("depart", {"portId": entry.id})

# --- economy ---------------------------------------------------------------

func _trade(c: Dictionary, buy: bool) -> Dictionary:
	if str(state.currentPortId).is_empty() or state.battleActive:
		return _fail("此操作须安全靠港后进行")
	var entry := _port(str(state.currentPortId))
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT:
		return _fail("货物或数量无效")
	var ship := _ship(str(state.flagshipId))
	var stock: int = int(entry.stock[good])
	var price: float = float(entry.prices[good]) * float(entry.priceFactor.get(good, 1.0))
	var quoted: Dictionary = Rules.quote(buy, quantity, price, stock, int(entry.stockCaps[good]), float(entry.tax), float(state.relations.get(entry.faction, 0)))
	if not quoted.ok:
		return _fail(str(quoted.reason))
	if buy:
		var cost: int = int(quoted.cost)
		if int(state.silver) < cost:
			return _fail("银两不足")
		if _cargo_size(ship) + int(quantity) > int(ship.capacity):
			return _fail("旗舰货舱不足")
		state.silver -= cost
		ship.cargo[good] = int(ship.cargo[good]) + int(quantity)
		entry.stock[good] = stock - int(quantity)
		_ledger_delta(-cost, {good: int(quantity)})
		return _receipt("buy", {"good": good, "quantity": quantity, "silver": -cost, "portId": entry.id})
	if int(ship.cargo[good]) < int(quantity):
		return _fail("货物不足")
	var reward: int = int(quoted.reward)
	ship.cargo[good] = int(ship.cargo[good]) - int(quantity)
	entry.stock[good] = stock + int(quantity)
	state.silver = mini(state.silver + reward, MAX_SILVER)
	state.meta.burned[good] = int(state.meta.burned[good])  # sell moves ship -> port stock: conserved
	_ledger_delta(reward, {good: -int(quantity)})
	return _receipt("sell", {"good": good, "quantity": quantity, "silver": reward, "portId": entry.id})

func _deliver(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在交付港靠泊后交货")
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT or int(quantity) < 1:
		return _fail("交付货物无效")
	var ship := _ship(str(state.flagshipId))
	if int(ship.cargo[good]) < int(quantity):
		return _fail("交付货物不足")
	ship.cargo[good] = int(ship.cargo[good]) - int(quantity)
	state.meta.burned[good] = int(state.meta.burned[good]) + int(quantity)
	_ledger_delta(0, {good: -int(quantity)})
	return _receipt("deliver", {"good": good, "quantity": quantity, "portId": str(state.currentPortId)})

func _repair(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内修船")
	var entry := _port(str(state.currentPortId))
	if not "repair" in entry.services:
		return _fail("此港没有修船服务")
	var ship := _ship(str(c.get("shipId", state.flagshipId)))
	if ship.is_empty():
		return _fail("船只不存在")
	var roles := _roles()
	var cost := int(round((40 + int(100 - int(ship.hull))) * Rules.repair_cost_multiplier(roles)))
	if int(state.silver) < cost:
		return _fail("修船银两不足")
	state.silver -= cost
	ship.hull = int(ship.maxHull)
	ship.sail = int(ship.maxSail)
	var crew_bonus := Rules.repair_crew_bonus(roles)
	if crew_bonus > 0:
		ship.crew = mini(int(ship.crew) + crew_bonus, int(ship.maxCrew))
	return _receipt("repair", {"shipId": ship.id, "silver": -cost, "crewBonus": crew_bonus})

func _recruit(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内募员")
	var entry := _port(str(state.currentPortId))
	if not "recruit" in entry.services:
		return _fail("此港没有募员服务")
	var count: Variant = c.get("count")
	if typeof(count) != TYPE_INT or int(count) < 1 or int(count) > 200:
		return _fail("募员数量无效")
	var cost := int(count) * 6
	if int(state.silver) < cost:
		return _fail("募员银两不足")
	var ship := _ship(str(state.flagshipId))
	if int(ship.crew) + int(count) > int(ship.maxCrew):
		return _fail("旗舰床位不足")
	state.silver -= cost
	ship.crew = int(ship.crew) + int(count)
	return _receipt("recruit", {"count": count, "silver": -cost})

func _sign_on(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内招揽同伴")
	var person_id := str(c.get("personId", ""))
	var role := str(c.get("role", ""))
	if person_id.is_empty() or role.is_empty():
		return _fail("同伴身份无效")
	for person: Dictionary in state.people:
		if person.id == person_id:
			return _fail("此人已在队中")
	var wage := int(c.get("wage", 0))
	var cost := int(c.get("cost", 0))
	if cost < 0 or wage < 0 or int(state.silver) < cost:
		return _fail("聘金不足")
	state.silver -= cost
	state.people.append({"id": person_id, "name": str(c.get("name", person_id)), "role": role, "aboardShipId": str(state.flagshipId), "wage": wage, "contractDay": int(state.day)})
	return _receipt("recruit", {"personId": person_id, "role": role, "silver": -cost})

# --- encounters ------------------------------------------------------------

func _identify(c: Dictionary) -> Dictionary:
	var entity := _entity(str(c.get("shipId", "")))
	if entity.is_empty():
		return _fail("目标不在视野内")
	var distance := _distance(_own_position(), entity.get("position", {"x": 0.0, "z": 0.0}))
	if distance > 120.0:
		return _fail("距离过远，无法核认目标")
	entity.identified = true
	return _receipt("identify", {"shipId": entity.id, "identity": entity.identity.duplicate(true)})

func _boarding(c: Dictionary) -> Dictionary:
	if not str(state.currentPortId).is_empty():
		return _fail("接舷目标无效或不在海上")
	var target := _native_ship(str(c.get("targetId", "")))
	if target.is_empty() or str(target.get("team", "")) != "hostile" or int(target.get("hull", 0)) <= 0:
		return _fail("接舷目标无效或不在海上")
	var own := _native_ship(str(state.flagshipId))
	if own.is_empty():
		return _fail("接舷目标无效或不在海上")
	var position: Dictionary = target.get("visual", {}).get("position", {})
	var own_position: Dictionary = own.get("visual", {}).get("position", {})
	var velocity: Dictionary = target.get("visual", {}).get("velocity", {})
	var own_velocity: Dictionary = own.get("visual", {}).get("velocity", {})
	var hull_ratio := float(target.get("hull", 1)) / maxf(1.0, float(target.get("maxHull", 1)))
	var crew_ratio := float(target.get("crew", 1)) / maxf(1.0, float(target.get("maxCrew", 1)))
	if not Rules.board_gate(_distance(position, own_position), _distance(velocity, own_velocity), hull_ratio, crew_ratio):
		return _fail("接舷需要36米内且相对速度不超过3米/秒，并先削弱敌船船体或船员")
	var captured: bool = bool(c.get("captured", false))
	var disposition := str(c.get("disposition", "capture"))
	if not disposition in ["capture", "plunder", "release"]:
		return _fail("无效俘获处置")
	for record: Dictionary in state.captures:
		if record.targetId == str(c.get("targetId", "")):
			return _fail("此船战利品已结算")
	var battle_id := str(c.get("battleId", "battle-%d" % int(state.day)))
	var ship := _ship(str(state.flagshipId))
	if not captured:
		# A failed boarding costs hands to the sick berth, not to the sea.
		var hurt := mini(Rules.BOARDING_FAILURE_WOUNDED, int(ship.crew) - 1)
		ship.crew = int(ship.crew) - hurt
		ship.wounded = int(ship.wounded) + hurt
		return _receipt("boarding", {"targetId": str(c.get("targetId", "")), "captured": false, "battleId": battle_id, "wounded": hurt})
	var volunteers := int(ceil(Rules.capture_volunteers(Rules.profile_min_crew(str(target.get("kind", "merchant"))), int(target.get("crew", 0))) * Rules.boarding_volunteer_multiplier(_roles())))
	if int(ship.crew) - volunteers < int(ship.minCrew):
		return _fail("没有足够船员操纵缴获船只 (crew=%d volunteers=%d min=%d target=%s/%s)" % [int(ship.crew), volunteers, int(ship.minCrew), str(target.get("kind", "?")), str(target.get("crew", -1))])
	if state.fleet.size() >= MAX_FLEET:
		return _fail("舰队已满，请先处理船位")
	ship.crew = int(ship.crew) - volunteers
	state.meta.shipSequence = int(state.meta.shipSequence) + 1
	var prize := _new_ship("prize-%d" % int(state.meta.shipSequence), str(target.get("kind", "merchant")), "缴获·%s" % str(target.get("name", target.get("id", "船"))), Rules.profile_min_crew(str(target.get("kind", "merchant"))))
	prize.hull = clampi(int(target.get("hull", 15)), 15, int(prize.maxHull))
	prize.position = position.duplicate(true)
	prize.heading = float(target.get("visual", {}).get("heading", 0.0))
	state.fleet.append(prize)
	state.captures.append({"shipId": prize.id, "targetId": str(c.get("targetId", "")), "battleId": battle_id, "receiptId": _peek_receipt_id()})
	return _receipt("capture", {"targetId": str(c.get("targetId", "")), "shipId": prize.id, "battleId": battle_id, "disposition": disposition, "volunteers": volunteers})

func _land(c: Dictionary) -> Dictionary:
	var site_id := str(c.get("siteId", ""))
	if site_id.is_empty():
		return _fail("陆战目标无效")
	var victory: bool = bool(c.get("victory", false))
	if not victory:
		var hurt := mini(Rules.LAND_FAILURE_WOUNDED, int(_ship(str(state.flagshipId)).crew) - 1)
		if hurt > 0:
			_ship(str(state.flagshipId)).crew = int(_ship(str(state.flagshipId)).crew) - hurt
			_ship(str(state.flagshipId)).wounded = int(_ship(str(state.flagshipId)).wounded) + hurt
	state.landPositions[site_id] = {"controller": "player", "receiptId": _peek_receipt_id(), "day": int(state.day)}
	return _receipt("land", {"siteId": site_id, "victory": victory})

# --- conditional transactions ---------------------------------------------

func _sign_charter(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty() and not bool(c.get("remote", false)):
		return _fail("须在港内申领文书")
	var permit_id := str(c.get("permitId", ""))
	if permit_id.is_empty():
		return _fail("文书标识无效")
	for permit: Dictionary in state.permits:
		if permit.id == permit_id:
			return _fail("此文书已申领")
	var cost := int(c.get("cost", 0))
	cost = int(round(float(cost) * Rules.charter_cost_multiplier(_roles())))
	if cost < 0 or int(state.silver) < cost:
		return _fail("申领费用不足")
	state.silver -= cost
	state.permits.append({"id": permit_id, "scope": str(c.get("scope", "")), "issuer": str(c.get("issuer", "")), "conditions": (c.get("conditions", []) as Array).duplicate(true), "cost": cost})
	return _receipt("charter", {"permitId": permit_id, "silver": -cost})

func _sign_terms(c: Dictionary) -> Dictionary:
	var agreement_id := str(c.get("agreementId", ""))
	if agreement_id.is_empty():
		return _fail("协议标识无效")
	for agreement: Dictionary in state.agreements:
		if agreement.id == agreement_id:
			return _fail("此协议已签订")
	var terms: Dictionary = c.get("terms", {})
	if not terms is Dictionary or terms.is_empty():
		return _fail("协议条款无效")
	var created := _receipt("terms", {"agreementId": agreement_id})
	if not created.get("ok", false):
		return created
	state.agreements.append({"id": agreement_id, "terms": terms.duplicate(true), "termsDigest": Rules.terms_digest(terms), "parties": (c.get("parties", []) as Array).duplicate(true), "receiptId": created.receipt.id})
	return created

func _buy_ship(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty() or state.battleActive:
		return _fail("此操作须安全靠港后进行")
	var entry := _port(str(state.currentPortId))
	if not "shipyard" in entry.services:
		return _fail("此港没有船坞")
	var kind := str(c.get("kind", ""))
	if not Rules.SHIP_PROFILES.has(kind):
		return _fail("未知船型")
	if state.fleet.size() >= MAX_FLEET:
		return _fail("舰队已满")
	var cost := int(Rules.ship_profile(kind).price)
	if int(state.silver) < cost:
		return _fail("购船银两不足")
	state.silver -= cost
	state.meta.shipSequence = int(state.meta.shipSequence) + 1
	var ship := _new_ship("fleet-%d" % int(state.meta.shipSequence), kind, "%s%d号" % [str(c.get("name", kind)), int(state.meta.shipSequence)], 0)
	ship.position = {"x": float(entry.x) + 25.0 + 20.0 * float(state.fleet.size()), "z": float(entry.z)}
	state.fleet.append(ship)
	return _receipt("buy-ship", {"shipId": ship.id, "kind": kind, "silver": -cost})

func _transfer_cargo(c: Dictionary) -> Dictionary:
	var from := _ship(str(c.get("fromShipId", "")))
	var to := _ship(str(c.get("toShipId", "")))
	if from.is_empty() or to.is_empty() or str(from.id) == str(to.id):
		return _fail("请选择两艘不同的舰队船只")
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT or int(quantity) < 1:
		return _fail("货物或数量无效")
	if int(from.cargo[good]) < int(quantity):
		return _fail("转出货物不足")
	if _cargo_size(to) + int(quantity) > int(to.capacity):
		return _fail("转入货舱不足")
	from.cargo[good] = int(from.cargo[good]) - int(quantity)
	to.cargo[good] = int(to.cargo[good]) + int(quantity)
	return _ok({"transferred": quantity})

func _transfer_crew(c: Dictionary) -> Dictionary:
	var from := _ship(str(c.get("fromShipId", "")))
	var to := _ship(str(c.get("toShipId", "")))
	if from.is_empty() or to.is_empty() or str(from.id) == str(to.id):
		return _fail("请选择两艘不同的舰队船只")
	var count: Variant = c.get("count")
	if typeof(count) != TYPE_INT or int(count) < 1 or int(from.crew) < int(count):
		return _fail("转出船员不足")
	if int(to.crew) + int(count) > int(to.maxCrew):
		return _fail("转入床位不足")
	from.crew = int(from.crew) - int(count)
	to.crew = int(to.crew) + int(count)
	return _ok({"transferred": count})

func _load_manifest(c: Dictionary) -> Dictionary:
	var manifest_id := str(c.get("manifestId", ""))
	var source := _entity(str(c.get("fromId", "")))
	if manifest_id.is_empty() or source.is_empty():
		return _fail("装载来源无效")
	var people: int = int(c.get("people", 0))
	var cargo: Dictionary = c.get("cargo", {})
	if people < 0 or not cargo is Dictionary:
		return _fail("清单内容无效")
	if int(source.get("people", 0)) < people:
		return _fail("来源人员不足")
	for good: Variant in cargo:
		if not good in GOODS or not _int(cargo[good], 0, MAX_GOODS_UNIT) or int(source.inventory.get(good, 0)) < int(cargo[good]):
			return _fail("来源货物不足")
	var ships: Array = c.get("ontoShipIds", [])
	var capacity := 0
	var people_room := 0
	for ship_id: Variant in ships:
		var ship := _ship(str(ship_id))
		if ship.is_empty():
			return _fail("装载船只不存在")
		capacity += int(ship.capacity) - _cargo_size(ship)
		people_room += int(ship.maxCrew) - int(ship.crew) - int(ship.passengers)
	var units := 0
	for good: Variant in cargo:
		units += int(cargo[good])
	var sold := {}
	if (units > capacity or people > people_room) and str(c.get("overflow", "")) == "sell" and not str(state.currentPortId).is_empty():
		# Manifest overflow: sell cargo at this port's real market until the
		# load fits — a genuine market action, recorded on the receipt.
		var market := _port(str(state.currentPortId))
		for ship_id: Variant in ships:
			var seller := _ship(str(ship_id))
			while capacity < units:
				var spilled := ""
				var spilled_count := 0
				for good: String in GOODS:
					if int(seller.cargo[good]) > spilled_count:
						spilled = good
						spilled_count = int(seller.cargo[good])
				if spilled.is_empty():
					break
				var quote := Rules.quote(false, spilled_count, float(market.prices[spilled]) * float(market.priceFactor[spilled]), int(market.stock[spilled]), int(market.stockCaps[spilled]), float(market.tax), float(state.relations.get(market.faction, 0)))
				if not quote.ok:
					break
				seller.cargo[spilled] = 0
				market.stock[spilled] = int(market.stock[spilled]) + spilled_count
				state.silver += int(quote.reward)
				sold[spilled] = int(sold.get(spilled, 0)) + spilled_count
				capacity += spilled_count
	if units > capacity or people > people_room:
		return _fail("舱容或铺位不足")
	source.people = int(source.get("people", 0)) - people
	var remaining_people := people
	for ship_id: Variant in ships:
		var ship := _ship(str(ship_id))
		var berths: int = int(ship.maxCrew) - int(ship.crew) - int(ship.passengers)
		var take: int = mini(berths, remaining_people)
		ship.passengers = int(ship.passengers) + take
		remaining_people -= take
		if remaining_people <= 0:
			break
	var moved := {}
	for good: String in GOODS:
		var quantity: int = int(cargo.get(good, 0))
		if quantity > 0:
			source.inventory[good] = int(source.inventory.get(good, 0)) - quantity
			moved[good] = quantity
	for good: Variant in moved:
		for ship_id: Variant in ships:
			var ship := _ship(str(ship_id))
			var room: int = int(ship.capacity) - _cargo_size(ship)
			var take: int = mini(room, int(moved[good]))
			ship.cargo[good] = int(ship.cargo[good]) + take
			moved[good] = int(moved[good]) - take
			if int(moved[good]) <= 0:
				break
	return _receipt("load-manifest", {"manifestId": manifest_id, "fromId": source.id, "people": people, "cargo": cargo.duplicate(true), "sold": sold})

func _handover(c: Dictionary) -> Dictionary:
	var handover_id := str(c.get("handoverId", ""))
	var source := _entity(str(c.get("facilityId", "")))
	var entry := _port(str(c.get("portId", "")))
	if handover_id.is_empty() or source.is_empty() or entry.is_empty():
		return _fail("接收对象无效")
	var itemized := {}
	for good: String in GOODS:
		var quantity: int = int(source.inventory.get(good, 0))
		if quantity > 0:
			entry.stock[good] = int(entry.stock[good]) + quantity
			source.inventory[good] = 0
			itemized[good] = quantity
	return _receipt("handover", {"handoverId": handover_id, "facilityId": source.id, "portId": entry.id, "itemized": itemized, "people": int(source.get("people", 0))})

func _transfer_manifest(c: Dictionary) -> Dictionary:
	if not state.transfers.is_empty():
		return _fail("交接已完成，不可重复")
	var manifest: Dictionary = c.get("manifest", {})
	if not manifest is Dictionary:
		return _fail("交接清单无效")
	var present := present_manifest()
	var left_behind := []
	for ship_id: Variant in manifest.get("ships", []):
		if not str(ship_id) in (present.ships as Array):
			left_behind.append(str(ship_id))
	for person_id: Variant in manifest.get("people", []):
		if not str(person_id) in (present.people as Array):
			left_behind.append(str(person_id))
	state.transfers.append({"id": "transfer-%d" % (int(state.transfers.size()) + 1), "to": str(c.get("to", "")), "manifest": manifest.duplicate(true), "leftBehind": left_behind, "receiptId": _peek_receipt_id()})
	return _receipt("handoff", {"to": str(c.get("to", "")), "manifest": manifest.duplicate(true), "leftBehind": left_behind})

func _dispatch(c: Dictionary) -> Dictionary:
	var dispatch_id := str(c.get("dispatchId", ""))
	if dispatch_id.is_empty():
		return _fail("分队标识无效")
	for record: Dictionary in state.dispatches:
		if record.id == dispatch_id:
			return _fail("此分队已派出")
	var ship_ids: Array = c.get("shipIds", [])
	if ship_ids.is_empty():
		return _fail("分队船只无效")
	for ship_id: Variant in ship_ids:
		if _ship(str(ship_id)).is_empty():
			return _fail("分队船只不存在")
	var partner_id := str(c.get("partnerId", ""))
	var capital := 0
	var destination := ""
	if not partner_id.is_empty():
		var signed := false
		for person: Dictionary in state.people:
			if str(person.id) == partner_id:
				signed = true
		if not signed:
			return _fail("合伙人未在编")
		destination = str(c.get("destinationPortId", ""))
		if _port(destination).is_empty():
			return _fail("合伙航向无效")
		capital = int(c.get("capital", 0))
		if capital < 1 or int(state.silver) < capital:
			return _fail("合伙本钱不足")
		state.silver -= capital
	state.dispatches.append({"id": dispatch_id, "route": str(c.get("route", "")), "shipIds": ship_ids.duplicate(true), "status": "outbound", "returnReceiptId": "", "day": int(state.day), "partnerId": partner_id, "capital": capital, "destinationPortId": destination})
	return _receipt("dispatch", {"dispatchId": dispatch_id, "shipIds": ship_ids.duplicate(true), "partnerId": partner_id, "capital": -capital})

func _return_dispatch(c: Dictionary) -> Dictionary:
	var dispatch_id := str(c.get("dispatchId", ""))
	for record: Dictionary in state.dispatches:
		if record.id != dispatch_id:
			continue
		if record.status == "returned":
			return _fail("此分队已归建")
		record.status = "returned"
		record.returnReceiptId = _peek_receipt_id()
		var settlement := {}
		if str(record.get("partnerId", "")) != "":
			var home: Dictionary = _port(str(state.currentPortId))
			var away: Dictionary = _port(str(record.get("destinationPortId", "")))
			var spread := Rules.partner_spread((home.get("priceFactor", {}) as Dictionary), (away.get("priceFactor", {}) as Dictionary))
			var returned := Rules.partner_player_return(int(record.get("capital", 0)), spread)
			state.silver += returned
			settlement = {"spread": spread, "returned": returned}
		return _receipt("dispatch-returned", {"dispatchId": dispatch_id, "resultManifest": (c.get("resultManifest", {}) as Dictionary).duplicate(true), "settlement": settlement})
	return _fail("分队记录不存在")

func _withdraw(c: Dictionary) -> Dictionary:
	var people: int = int(c.get("people", 0))
	if people < 0:
		return _fail("撤离人数无效")
	return _receipt("withdraw", {"groupId": str(c.get("groupId", "")), "rendezvousPortId": str(c.get("rendezvousPortId", "")), "people": people, "ships": (c.get("ships", []) as Array).duplicate(true)})

func _rescue(c: Dictionary) -> Dictionary:
	var target_id := str(c.get("targetId", ""))
	if target_id.is_empty():
		return _fail("救援目标无效")
	for record: Dictionary in state.rescued:
		if record.id == target_id:
			return _fail("此目标已救援")
	state.rescued.append({"id": target_id, "kind": str(c.get("kind", "crew")), "name": str(c.get("name", target_id)), "receiptId": _peek_receipt_id()})
	# A rescuer aboard recovers hands from the sea (bounded by berths).
	var bonus := Rules.rescue_crew_bonus(_roles())
	var flagship := _ship(str(state.flagshipId))
	if bonus > 0 and not flagship.is_empty():
		flagship.crew = mini(int(flagship.crew) + bonus, int(flagship.maxCrew))
	return _receipt("rescue", {"targetId": target_id, "crewBonus": bonus})

# --- blockades -------------------------------------------------------------

func _open_blockade(c: Dictionary) -> Dictionary:
	var watch_id := str(c.get("watchId", ""))
	if watch_id.is_empty() or state.blockades.has(watch_id):
		return _fail("封锁标识无效或已存在")
	var station: Array = c.get("stationShipIds", [])
	for ship_id: Variant in station:
		if _ship(str(ship_id)).is_empty():
			return _fail("封锁船只不存在")
	state.blockades[watch_id] = {"activeSinceDay": int(state.day), "lastVerifiedDay": int(state.day), "stationShipIds": station.duplicate(true), "breaches": 0, "linePoints": (c.get("linePoints", []) as Array).duplicate(true)}
	return _receipt("blockade-open", {"watchId": watch_id})

func _breach_blockade(c: Dictionary) -> Dictionary:
	var watch = state.blockades.get(str(c.get("watchId", "")))
	if not watch is Dictionary:
		return _fail("封锁不存在")
	watch.breaches = int(watch.breaches) + 1
	return _receipt("blockade-breach", {"watchId": str(c.get("watchId", ""))})

func _verify_blockade(c: Dictionary) -> Dictionary:
	var watch_id := str(c.get("watchId", ""))
	var watch = state.blockades.get(watch_id)
	if not watch is Dictionary:
		return _fail("封锁不存在")
	for ship_id: Variant in watch.stationShipIds:
		var ship := _ship(str(ship_id))
		if ship.is_empty() or int(ship.hull) <= 0:
			return _fail("封锁线已有船只离线")
	watch.lastVerifiedDay = int(state.day)
	return _receipt("blockade-verify", {"watchId": watch_id})

func _close_blockade(c: Dictionary) -> Dictionary:
	var watch_id := str(c.get("watchId", ""))
	if not state.blockades.has(watch_id):
		return _fail("封锁不存在")
	state.blockades.erase(watch_id)
	return _receipt("blockade-close", {"watchId": watch_id})

# --- contracts / ledgers ---------------------------------------------------

func _open_contract(c: Dictionary) -> Dictionary:
	var contract_id := str(c.get("contractId", ""))
	if contract_id.is_empty() or state.contracts.has(contract_id):
		return _fail("任务账本无效或已存在")
	state.contracts[contract_id] = {"kind": str(c.get("kind", "")), "targetIds": (c.get("targetIds", []) as Array).duplicate(true), "ledger": [], "status": "open", "day": int(state.day)}
	return _ok({"contractId": contract_id})

func _close_contract(c: Dictionary) -> Dictionary:
	var contract_id := str(c.get("contractId", ""))
	var contract: Dictionary = state.contracts.get(contract_id, {})
	if contract.is_empty():
		return _fail("任务账本不存在")
	contract.status = "closed"
	return _ok({"contractId": contract_id, "net": _ledger_net(contract)})

func _ledger_delta(silver: int, goods: Dictionary) -> void:
	for key: Variant in state.contracts:
		var contract: Dictionary = state.contracts[key]
		if contract.status != "open":
			continue
		contract.ledger.append({"receiptId": _peek_receipt_id(), "day": int(state.day), "delta": silver, "goods": goods.duplicate(true)})

func voyage_ledger(contract_id: String) -> Dictionary:
	var contract: Dictionary = state.contracts.get(contract_id, {})
	if contract.is_empty():
		return {"ok": false, "reason": "任务账本不存在"}
	return {"ok": true, "net": _ledger_net(contract), "ledger": contract.ledger.duplicate(true)}

func _ledger_net(contract: Dictionary) -> int:
	var net := 0
	for entry: Dictionary in contract.ledger:
		net += int(entry.delta)
	return net

# --- helpers ---------------------------------------------------------------

func inventory_count(good: String) -> int:
	var total := 0
	for ship: Dictionary in state.fleet:
		total += int(ship.cargo.get(good, 0))
	return total

func present_manifest() -> Dictionary:
	var ships := []
	var people := []
	var cargo := []
	for ship: Dictionary in state.fleet:
		ships.append(str(ship.id))
		for good: String in GOODS:
			if int(ship.cargo.get(good, 0)) > 0:
				cargo.append({"shipId": str(ship.id), "good": good, "qty": int(ship.cargo[good])})
	for person: Dictionary in state.people:
		people.append(str(person.id))
	var open_contracts := []
	for key: Variant in state.contracts:
		if state.contracts[key].status == "open":
			open_contracts.append(str(key))
	return {"ships": ships, "people": people, "cargo": cargo, "openContracts": open_contracts}

func fleet_safe() -> bool:
	if state.battleActive:
		return false
	var ship := _ship(str(state.flagshipId))
	return not ship.is_empty() and int(ship.hull) > 0

func snapshot() -> Dictionary:
	return state.duplicate(true)

func serialize() -> String:
	if state.is_empty():
		return ""
	return JSON.stringify(state)

func restore(raw: String) -> Dictionary:
	if raw.is_empty() or raw.to_utf8_buffer().size() > 16777216:
		return _fail("save is empty or exceeds limit")
	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return _fail("invalid save JSON")
	var validated := validate_world(parser.data)
	if not validated.ok:
		return _fail(str(validated.reason))
	state = validated.state
	latest_native = {}
	return _ok()

static func validate_world(value: Variant) -> Dictionary:
	if not _keys(value, STATE_KEYS):
		return {"ok": false, "reason": "world fields do not match story schema"}
	var s: Dictionary = value
	if not _int(s.schemaVersion, 1, 1) or s.campaignId != CAMPAIGN_ID or not _int(s.seed, -2147483648, 2147483647) or not _token(s.runId, 96):
		return {"ok": false, "reason": "world identity invalid"}
	if not _int(s.day, 1, 1000000) or not _int(s.yearMarker, 1600, 1700) or not _int(s.silver, 0, MAX_SILVER) or not s.battleActive is bool:
		return {"ok": false, "reason": "world counters invalid"}
	if not s.fleet is Array or s.fleet.is_empty() or s.fleet.size() > MAX_FLEET or not s.ports is Dictionary or not s.receipts is Array or s.receipts.size() > MAX_RECEIPTS:
		return {"ok": false, "reason": "world fleet, ports or receipts invalid"}
	var seen_ships := {}
	for ship: Variant in s.fleet:
		if not _keys(ship, ["id", "name", "kind", "hull", "sail", "crew", "minCrew", "maxHull", "maxSail", "maxCrew", "capacity", "cargo", "passengers", "wounded", "upgrades", "position", "heading", "speed"]) or not _token(ship.id, 96) or seen_ships.has(ship.id):
			return {"ok": false, "reason": "world ship fields or identity invalid"}
		seen_ships[ship.id] = true
		if not _upgrades_valid(ship.upgrades) or not _int(ship.hull, 0, 200) or not _int(ship.maxHull, 100, 200) or not _int(ship.sail, 0, 100) or not _int(ship.crew, 0, 1000) or not _int(ship.wounded, 0, 1000) or not _int(ship.passengers, 0, 2000) or not _cargo_valid(ship.cargo):
			return {"ok": false, "reason": "world ship bounds invalid"}
	if not seen_ships.has(str(s.flagshipId)):
		return {"ok": false, "reason": "world flagship missing"}
	var meta: Dictionary = s.meta
	if not _keys(meta, ["shipSequence", "receiptSequence", "minted", "burned", "difficultyTier"]) or not _cargo_valid(meta.minted) or not _cargo_valid(meta.burned) or not _int(meta.difficultyTier, 1, 6):
		return {"ok": false, "reason": "world conservation counters invalid"}
	var stock := {}
	for good: String in GOODS:
		stock[good] = 0
	for ship: Dictionary in s.fleet:
		for good: String in GOODS:
			stock[good] += int(ship.cargo[good])
	for key: Variant in s.ports:
		var entry: Variant = s.ports[key]
		if not _keys(entry, ["id", "x", "z", "tax", "faction", "services", "prices", "stockCaps", "stock", "warehouse", "priceFactor"]) or entry.id != key or not _cargo_valid(entry.stock) or not _cargo_valid(entry.warehouse) or not _price_map_valid(entry.priceFactor):
			return {"ok": false, "reason": "world port fields invalid"}
		for good: String in GOODS:
			stock[good] += int(entry.stock[good]) + int(entry.warehouse[good])
	for key: Variant in s.entities:
		var entity: Variant = s.entities[key]
		if not entity is Dictionary or str(entity.get("id", "")) != str(key) or not _cargo_valid(entity.get("inventory", {})):
			return {"ok": false, "reason": "world entity fields invalid"}
		for good: String in GOODS:
			stock[good] += int(entity.inventory.get(good, 0))
	if not s.intel is Dictionary or s.intel.size() > 32:
		return {"ok": false, "reason": "world intel invalid"}
	for key: Variant in s.intel:
		var report: Variant = s.intel[key]
		if not report is Dictionary or report.size() != 2 or not s.ports.has(str(key)) or not _int(report.get("day", -1), 1, 1000000) or not _price_map_valid(report.get("priceFactor", {})):
			return {"ok": false, "reason": "world intel entries invalid"}
	if not s.orders is Dictionary or s.orders.size() != 2 or not s.orders.get("formation") in FORMATIONS or not s.orders.get("escorts") is Dictionary or (s.orders.escorts as Dictionary).size() > MAX_FLEET:
		return {"ok": false, "reason": "world orders invalid"}
	for key: Variant in s.orders.escorts:
		if not seen_ships.has(str(key)) or not s.orders.escorts[key] is String:
			return {"ok": false, "reason": "world escort orders invalid"}
	var weather: Variant = s.weather
	if not weather is Dictionary or weather.size() != 2 or not weather.get("sea") in Rules.WEATHERS or not weather.get("wind") is Dictionary:
		return {"ok": false, "reason": "world weather invalid"}
	var wind: Dictionary = weather.wind
	if wind.size() != 3:
		return {"ok": false, "reason": "world weather wind invalid"}
	for field: String in ["x", "y", "speed"]:
		var wind_value = wind.get(field, null)
		if not typeof(wind_value) in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(wind_value)) or absf(float(wind_value)) > 100.0:
			return {"ok": false, "reason": "world weather wind invalid"}
	if not str(s.currentPortId).is_empty():
		if not s.ports.has(str(s.currentPortId)):
			return {"ok": false, "reason": "world docked at unknown port"}
		for ship: Dictionary in s.fleet:
			if float(ship.speed) != 0.0:
				return {"ok": false, "reason": "world docked fleet must be stationary"}
	for good: String in GOODS:
		if int(meta.minted[good]) - int(meta.burned[good]) != int(stock[good]) or int(meta.minted[good]) < 0 or int(meta.burned[good]) < 0:
			return {"ok": false, "reason": "world goods conservation broken"}
	if not s.transfers is Array or s.transfers.size() > 1:
		return {"ok": false, "reason": "world transfers invalid"}
	# Canonicalize numeric types so JSON round-trips are byte-stable: JSON parse
	# turns every number into float, which would drift ints and integral floats.
	return {"ok": true, "state": _normalize(s.duplicate(true))}

const FLOAT_KEYS := ["x", "y", "z", "tax", "heading", "speed", "elapsedSeconds"]
const FLOAT_MAPS := ["prices", "priceFactor"]

static func _price_map_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != GOODS.size():
		return false
	for good: String in GOODS:
		if not value.has(good):
			return false
		var factor := float(value[good])
		if not is_finite(factor) or factor < 0.7 or factor > 1.3:
			return false
	return true

static func _upgrades_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != Rules.UPGRADE_SYSTEMS.size():
		return false
	for system: String in Rules.UPGRADE_SYSTEMS:
		if not value.has(system) or not _int(value[system], 0, Rules.UPGRADE_MAX_LEVEL):
			return false
	return true

static func _normalize(value: Variant, key: String = "") -> Variant:
	if value is Dictionary:
		var forced: bool = key in FLOAT_MAPS
		var out := {}
		for child: Variant in value:
			out[child] = _normalize(value[child], "__forced_float__" if forced else str(child))
		return out
	if value is Array:
		var items: Array = []
		for item: Variant in value:
			items.append(_normalize(item, key))
		return items
	if typeof(value) in [TYPE_INT, TYPE_FLOAT]:
		if key == "__forced_float__" or key in FLOAT_KEYS:
			return float(value)
		var as_float := float(value)
		if is_finite(as_float) and as_float == floor(as_float):
			return int(as_float)
		return as_float
	return value

func _new_ship(id: String, kind: String, display_name: String, crew: int) -> Dictionary:
	var p := Rules.ship_profile(kind)
	var cargo := {}
	for good: String in GOODS:
		cargo[good] = 0
	return {"id": id, "name": display_name, "kind": kind, "hull": 100, "sail": 100, "crew": clampi(crew, 0, int(p.crew)), "minCrew": int(p.minCrew), "maxHull": 100, "maxSail": 100, "maxCrew": int(p.crew), "capacity": int(p.capacity), "cargo": cargo, "passengers": 0, "wounded": 0, "upgrades": {"hull": 0, "cannons": 0, "sails": 0, "equipment": 0}, "position": {"x": 0.0, "z": 0.0}, "heading": 0.0, "speed": 0.0}

func _upgrade(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty() or state.battleActive:
		return _fail("此操作须安全靠港后进行")
	var entry := _port(str(state.currentPortId))
	if not "shipyard" in entry.services:
		return _fail("此港没有船坞")
	var system := str(c.get("system", ""))
	if not system in Rules.UPGRADE_SYSTEMS:
		return _fail("未知升级系统")
	var ship := _ship(str(c.get("shipId", state.flagshipId)))
	if ship.is_empty():
		return _fail("船只不存在")
	var level: int = int(ship.upgrades[system])
	if level >= Rules.UPGRADE_MAX_LEVEL:
		return _fail("此系统已达三级上限")
	var cost := Rules.upgrade_cost(system, level)
	if int(state.silver) < cost:
		return _fail("升级银两不足")
	state.silver -= cost
	ship.upgrades[system] = level + 1
	if system == "hull":
		var old_cap := int(ship.maxHull)
		ship.maxHull = Rules.upgraded_max_hull(level + 1)
		ship.hull = mini(int(ship.hull) + int(ship.maxHull) - old_cap, int(ship.maxHull))
	return _receipt("upgrade", {"shipId": ship.id, "system": system, "level": level + 1, "silver": -cost})

func _ship(id: String) -> Dictionary:
	for ship: Dictionary in state.fleet:
		if ship.id == id:
			return ship
	return {}

func _port(id: String) -> Dictionary:
	return state.ports.get(id, {})

func _entity(id: String) -> Dictionary:
	return state.entities.get(id, {})

func _native_ship(id: String) -> Dictionary:
	for entry: Dictionary in latest_native.get("ships", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}

func _spawn_entity(c: Dictionary) -> Dictionary:
	var entity: Dictionary = c.get("entity", {})
	if not entity is Dictionary or not _token(entity.get("id", ""), 96):
		return _fail("场景实体无效或重复")
	var inventory := {}
	for good: String in GOODS:
		inventory[good] = int(entity.get("inventory", {}).get(good, 0))
	if state.entities.has(str(entity.id)):
		# Rebinding resets the entity for a fresh attempt: old stock leaves the
		# world ledger, declared stock is minted again.
		var previous: Dictionary = state.entities[str(entity.id)]
		for good: String in GOODS:
			state.meta.burned[good] = int(state.meta.burned[good]) + int(previous.inventory.get(good, 0))
	for good: String in GOODS:
		state.meta.minted[good] = int(state.meta.minted[good]) + int(inventory[good])
	state.entities[str(entity.id)] = {"id": str(entity.id), "kind": str(entity.get("kind", "")), "team": str(entity.get("team", "neutral")), "name": str(entity.get("name", entity.id)), "identity": (entity.get("identity", {}) as Dictionary).duplicate(true), "inventory": inventory, "people": int(entity.get("people", 0)), "position": (entity.get("position", {"x": 0.0, "z": 0.0}) as Dictionary).duplicate(true), "identified": false}
	return _ok({"entityId": str(entity.id)})

func _mint_grant(c: Dictionary) -> Dictionary:
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT or int(quantity) < 0:
		return _fail("补给内容无效")
	var ship := _ship(str(c.get("shipId", state.flagshipId)))
	if ship.is_empty():
		return _fail("补给船只不存在")
	if _cargo_size(ship) + int(quantity) > int(ship.capacity):
		return _fail("补给超出货舱容量")
	state.meta.minted[good] = int(state.meta.minted[good]) + int(quantity)
	ship.cargo[good] = int(ship.cargo[good]) + int(quantity)
	return _receipt("mint-grant", {"good": good, "quantity": quantity, "shipId": ship.id})

func _advance_day(_c: Dictionary) -> Dictionary:
	state.day = int(state.day) + 1
	for port_id: Variant in state.ports:
		var entry: Dictionary = state.ports[port_id]
		for good: String in GOODS:
			entry.priceFactor[good] = Rules.price_factor(int(state.day), str(port_id), good)
	var tier := int(state.meta.get("difficultyTier", 1))
	var roles: Array = []
	for person: Dictionary in state.people:
		roles.append(str(person.get("role", "")))
	var upkeep := int(round((2 + int(state.people.size())) * (1.0 + 0.1 * float(tier - 1)) * Rules.upkeep_multiplier(roles)))
	if int(state.silver) >= upkeep:
		state.silver -= upkeep
	# A doctor aboard returns one wounded hand to duty each day at sea.
	if Rules.repair_crew_bonus(roles) > 0:
		for ship: Dictionary in state.fleet:
			if int(ship.wounded) > 0 and int(ship.crew) < int(ship.maxCrew):
				ship.wounded = int(ship.wounded) - 1
				ship.crew = int(ship.crew) + 1
				break
	return _receipt("advance-day", {"day": int(state.day), "upkeep": upkeep})

func _set_difficulty(c: Dictionary) -> Dictionary:
	var tier: Variant = c.get("tier")
	if typeof(tier) != TYPE_INT or int(tier) < 1 or int(tier) > 6:
		return _fail("难度档无效")
	state.meta.difficultyTier = int(tier)
	return _ok({"tier": int(tier)})

func _attend_banquet(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内赴宴")
	var entry := _port(str(state.currentPortId))
	if not "banquet" in entry.services:
		return _fail("此港没有宴饮场合")
	if int(state.silver) < 30:
		return _fail("赴宴需三十两")
	state.silver -= 30
	var relation := clampi(int(state.relations.get(entry.faction, 0)) + 3, -100, 100)
	state.relations[entry.faction] = relation
	return _receipt("attend-banquet", {"portId": entry.id, "faction": entry.faction, "relation": relation, "silver": -30})

func _treat_wounded(c: Dictionary) -> Dictionary:
	var ship := _ship(str(c.get("shipId", state.flagshipId)))
	if ship.is_empty():
		return _fail("船只不存在")
	var roles := _roles()
	var ashore := not str(state.currentPortId).is_empty()
	var entry := _port(str(state.currentPortId))
	var doctor := Rules.repair_crew_bonus(roles) > 0
	if not ashore or (not "repair" in entry.services and not doctor):
		return _fail("须在有医馆或修船处的港口疗伤")
	var count: Variant = c.get("count")
	if typeof(count) != TYPE_INT or int(count) < 1 or int(count) > int(ship.wounded):
		return _fail("疗伤人数无效")
	var cost := int(count) * Rules.TREAT_COST_PER_HEAD
	if int(state.silver) < cost:
		return _fail("疗伤银两不足")
	state.silver -= cost
	ship.wounded = int(ship.wounded) - int(count)
	ship.crew = mini(int(ship.crew) + int(count), int(ship.maxCrew))
	return _receipt("treat-wounded", {"shipId": ship.id, "count": count, "silver": -cost})

func _gather_intel(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内探听")
	var entry := _port(str(state.currentPortId))
	if not "intel" in entry.services:
		return _fail("此港没有消息行")
	if int(state.silver) < 20:
		return _fail("探听需二十两")
	var target_id := str(c.get("portId", ""))
	var target := _port(target_id)
	if target.is_empty() or target_id == str(state.currentPortId):
		return _fail("探听目标无效")
	state.silver -= 20
	state.intel[target_id] = {"day": int(state.day), "priceFactor": (target.priceFactor as Dictionary).duplicate(true)}
	return _receipt("gather-intel", {"portId": target_id, "from": entry.id, "silver": -20})

func _set_formation(c: Dictionary) -> Dictionary:
	var mode := str(c.get("mode", ""))
	if not mode in FORMATIONS:
		return _fail("编队队形无效")
	state.orders.formation = mode
	return _receipt("set-formation", {"mode": mode})

func _assign_escort(c: Dictionary) -> Dictionary:
	var ship := _ship(str(c.get("shipId", "")))
	if ship.is_empty() or str(ship.id) == str(state.flagshipId):
		return _fail("护航船只无效")
	var target_id := str(c.get("targetId", ""))
	if target_id.is_empty():
		return _fail("护航目标无效")
	state.orders.escorts[str(ship.id)] = target_id
	return _receipt("assign-escort", {"shipId": ship.id, "targetId": target_id})

func _release_escort(c: Dictionary) -> Dictionary:
	var ship_id := str(c.get("shipId", ""))
	if not state.orders.escorts.has(ship_id):
		return _fail("此船无护航任务")
	state.orders.escorts.erase(ship_id)
	return _receipt("release-escort", {"shipId": ship_id})

func _set_weather(c: Dictionary) -> Dictionary:
	var sea := str(c.get("sea", ""))
	if not sea in Rules.WEATHERS:
		return _fail("海况无效")
	state.weather = {"sea": sea, "wind": Rules.weather_wind(sea)}
	return _receipt("set-weather", {"sea": sea})

func _store_goods(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内存仓")
	var entry := _port(str(state.currentPortId))
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT or int(quantity) < 1:
		return _fail("货物或数量无效")
	var ship := _ship(str(state.flagshipId))
	if int(ship.cargo[good]) < int(quantity):
		return _fail("船上货物不足")
	ship.cargo[good] = int(ship.cargo[good]) - int(quantity)
	entry.warehouse[good] = int(entry.warehouse[good]) + int(quantity)
	return _receipt("store-goods", {"good": good, "quantity": quantity, "portId": entry.id})

func _withdraw_goods(c: Dictionary) -> Dictionary:
	if str(state.currentPortId).is_empty():
		return _fail("须在港内取仓")
	var entry := _port(str(state.currentPortId))
	var good := str(c.get("good", ""))
	var quantity: Variant = c.get("quantity")
	if not good in GOODS or typeof(quantity) != TYPE_INT or int(quantity) < 1:
		return _fail("货物或数量无效")
	if int(entry.warehouse[good]) < int(quantity):
		return _fail("仓内货物不足")
	var ship := _ship(str(state.flagshipId))
	if _cargo_size(ship) + int(quantity) > int(ship.capacity):
		return _fail("货舱不足")
	entry.warehouse[good] = int(entry.warehouse[good]) - int(quantity)
	ship.cargo[good] = int(ship.cargo[good]) + int(quantity)
	return _receipt("withdraw-goods", {"good": good, "quantity": quantity, "portId": entry.id})

func _transition(c: Dictionary) -> Dictionary:
	var year: Variant = c.get("yearMarker")
	if typeof(year) != TYPE_INT or int(year) < int(state.yearMarker) or int(year) > 1700:
		return _fail("转场年份无效")
	state.yearMarker = int(year)
	var to := str(c.get("to", ""))
	if not to.is_empty():
		var entry := _port(to)
		if entry.is_empty():
			return _fail("转场港口不存在")
		state.currentPortId = to
		for ship: Dictionary in state.fleet:
			ship.speed = 0.0
			ship.position = {"x": float(entry.x) + 25.0, "z": float(entry.z)}
	return _receipt("transition", {"yearMarker": int(year), "to": to, "note": str(c.get("note", ""))})

func _relations_delta(c: Dictionary) -> Dictionary:
	var faction := str(c.get("faction", ""))
	var delta: Variant = c.get("delta")
	if faction.is_empty() or typeof(delta) != TYPE_INT or int(delta) < -100 or int(delta) > 100:
		return _fail("关系变动无效")
	var current := int(state.relations.get(faction, 0))
	state.relations[faction] = clampi(current + int(delta), -100, 100)
	return _receipt("relations", {"faction": faction, "delta": int(delta)})

func _peek_receipt_id() -> String:
	return "wsr-%05d" % (int(state.meta.receiptSequence) + 1)

func _receipt(kind: String, details: Dictionary) -> Dictionary:
	if state.receipts.size() >= MAX_RECEIPTS:
		return _fail("world receipt history full")
	state.meta.receiptSequence = int(state.meta.receiptSequence) + 1
	var receipt := {"id": "wsr-%05d" % int(state.meta.receiptSequence), "kind": kind, "day": int(state.day), "details": details.duplicate(true)}
	state.receipts.append(receipt)
	return {"ok": true, "reason": "", "receipt": receipt.duplicate(true), "state": snapshot()}

func _add_log(message: String) -> void:
	state.log.append("第%d日：%s" % [int(state.day), message])
	if state.log.size() > 256:
		state.log.pop_front()

func _cargo_size(ship: Dictionary) -> int:
	var total := 0
	for good: String in GOODS:
		total += int(ship.cargo.get(good, 0))
	return total

func _roles() -> Array:
	var roles: Array = []
	for person: Dictionary in state.people:
		roles.append(str(person.get("role", "")))
	return roles

func _own_position() -> Dictionary:
	var ship := _ship(str(state.flagshipId))
	return ship.position if not ship.is_empty() else {"x": 0.0, "z": 0.0}

func _own_speed() -> float:
	var ship := _ship(str(state.flagshipId))
	return float(ship.speed) if not ship.is_empty() else 0.0

func _distance(a: Dictionary, b: Dictionary) -> float:
	var dx := float(a.get("x", 0.0)) - float(b.get("x", 0.0))
	var dz := float(a.get("z", 0.0)) - float(b.get("z", 0.0))
	return sqrt(dx * dx + dz * dz)

func _length(v: Dictionary) -> float:
	return sqrt(float(v.get("x", 0.0)) * float(v.get("x", 0.0)) + float(v.get("z", 0.0)) * float(v.get("z", 0.0)))

func _ok(extra: Dictionary = {}) -> Dictionary:
	var result := {"ok": true, "reason": ""}
	for key: Variant in extra:
		result[key] = extra[key]
	return result

func _fail(reason: String) -> Dictionary:
	last_error = reason
	return {"ok": false, "reason": reason}

static func _int(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false

static func _cargo_valid(value: Variant) -> bool:
	if not value is Dictionary or value.size() != GOODS.size():
		return false
	for good: String in GOODS:
		if not value.has(good) or not _int(value[good], 0, MAX_GOODS_UNIT):
			return false
	return true

static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true

static func _token(value: Variant, maximum: int) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum or value.strip_edges() != value:
		return false
	return true

static func _opening_reason(opening: Variant) -> String:
	if not _keys(opening, ["silver", "day", "yearMarker", "homePort", "relations", "fleet", "ports", "log"]):
		return "invalid-opening-fields"
	if not _int(opening.silver, 0, MAX_SILVER) or not _int(opening.day, 1, 1000000) or not _int(opening.yearMarker, 1600, 1700):
		return "invalid-opening-counters"
	if not opening.fleet is Array or opening.fleet.is_empty() or opening.fleet.size() > MAX_FLEET or not opening.ports is Array or opening.ports.is_empty():
		return "invalid-opening-fleet-or-ports"
	return ""
