extends SceneTree
## Story world session contract and legacy-oracle parity.
## Parity drives a real legacy adventure_session on mirrored inputs and asserts
## identical accept/reject and quote numbers, so copied math cannot drift.

const WORLD_PATH := "res://game/domain/story_world/story_world_session.gd"
const RULES_PATH := "res://game/domain/story_world/story_rules.gd"
const SAVE_PATH := "res://game/domain/story_world/story_save.gd"
const LEGACY_PATH := "res://game/domain/legacy/adventure_session.gd"
const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const RULES_KINDS := ["grain", "wood", "iron", "silk", "porcelain", "spices"]
var assertions: int = 0
var failures: int = 0
var world_script: GDScript
var rules_script: GDScript
var save_script: GDScript
var legacy_script: GDScript

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	world_script = load(WORLD_PATH) as GDScript
	rules_script = load(RULES_PATH) as GDScript
	save_script = load(SAVE_PATH) as GDScript
	legacy_script = load(LEGACY_PATH) as GDScript
	if not check(world_script != null and rules_script != null and save_script != null and legacy_script != null, "story domain modules load"):
		_finish()
		return
	_test_configure_and_roundtrip()
	_test_forged_results_and_saves()
	_test_legacy_parity()
	_test_ledger_and_deliver()
	_test_manifests_and_handoff()
	_finish()

func _finish() -> void:
	print("STORY_WORLD_SESSION assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _opening() -> Dictionary:
	return {
		"silver": 650, "day": 1, "yearMarker": 1623, "homePort": "xiamen",
		"relations": {"zheng": 0, "voc": 0},
		"fleet": [{"id": "player", "kind": "fuchuan", "name": "定海号", "crew": 48, "cargo": {"grain": 30}}],
		"ports": [
			{"id": "xiamen", "x": -306.2570958447386, "z": 110.0, "tax": 0.05, "faction": "zheng", "services": ["trade", "repair", "recruit"],
				"prices": {"grain": 4, "wood": 8, "iron": 14, "silk": 32, "porcelain": 30, "spices": 26}, "stockCaps": {"grain": 200, "wood": 200, "iron": 200, "silk": 120, "porcelain": 120, "spices": 120},
				"stock": {"grain": 200, "wood": 200, "iron": 200, "silk": 120, "porcelain": 120, "spices": 120}},
			{"id": "kinmen", "x": 282.1499288930165, "z": 160.0, "tax": 0.08, "faction": "zheng", "services": ["trade"],
				"prices": {"grain": 8, "wood": 11, "iron": 19, "silk": 40, "porcelain": 38, "spices": 33}, "stockCaps": {"grain": 160, "wood": 160, "iron": 160, "silk": 100, "porcelain": 100, "spices": 100},
				"stock": {"grain": 40, "wood": 160, "iron": 160, "silk": 100, "porcelain": 100, "spices": 100}}
		],
		"log": "对照世界"
	}

func _world() -> RefCounted:
	var world: RefCounted = world_script.new()
	var configured: Dictionary = world.call("configure", _opening(), 1661, "story-run")
	check(configured.get("ok", false), "world configures from opening")
	return world

func _legacy() -> RefCounted:
	var session: RefCounted = legacy_script.new({"seed": 1661, "name": "对照船长"})
	check(session != null and session.last_error == "", "legacy oracle session starts")
	return session

func _native_pair(distance: float, rel_speed: float, hull: int, crew: int) -> Dictionary:
	return {"ships": [
		{"id": "player", "team": "player", "kind": "fuchuan", "name": "定海号", "hull": 100, "maxHull": 100, "crew": 48, "maxCrew": 100, "sail": 100, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0},
			"visual": {"position": {"x": 0.0, "z": 0.0}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}},
		{"id": "tgt", "team": "hostile", "kind": "merchant", "name": "对照目标", "hull": hull, "maxHull": 100, "crew": crew, "maxCrew": 70, "sail": 50, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0},
			"visual": {"position": {"x": distance, "z": 0.0}, "velocity": {"x": rel_speed, "z": 0.0}, "heading": 0.0}}
	]}

# --- tests ------------------------------------------------------------------

func _test_configure_and_roundtrip() -> void:
	var world := _world()
	var snapshot: Dictionary = world.call("snapshot")
	check(snapshot.fleet.size() == 1 and snapshot.fleet[0].cargo.grain == 30, "opening fleet and cargo minted")
	check(snapshot.meta.minted.grain == 270 and snapshot.meta.burned.grain == 0, "mint counters track opening cargo and port stock")
	check(world.call("inventory_count", "grain") == 30, "live inventory reads fleet cargo")
	var raw: String = world.call("serialize")
	var twin: RefCounted = world_script.new()
	check(twin.call("restore", raw).get("ok", false), "world restore accepts own save")
	var reserialized: String = JSON.stringify(twin.call("snapshot"))
	var original: String = JSON.stringify(snapshot)
	var diff_at := reserialized.length() if reserialized == original else _diff_index(original, reserialized)
	check(reserialized == original, "restore round-trips state exactly (first diff at %d: ...%s... vs ...%s...)" % [diff_at, original.substr(maxi(0, diff_at - 20), 40), reserialized.substr(maxi(0, diff_at - 20), 40)])

func _diff_index(a: String, b: String) -> int:
	var shared := mini(a.length(), b.length())
	for index in shared:
		if a[index] != b[index]:
			return index
	return shared

func _test_forged_results_and_saves() -> void:
	var world := _world()
	check(not world.call("command", {"type": "dock", "portId": "xiamen", "outcome": "success"}).get("ok", true), "caller-supplied outcome rejected as forged")
	check(not world.call("command", {"type": "buy", "good": "grain", "quantity": 1, "success": true}).get("ok", true), "caller-supplied success rejected as forged")
	var raw: String = world.call("serialize")
	var tampered: Dictionary = _parsed(raw)
	tampered.fleet[0].cargo.grain = 9999
	check(not world_script.call("validate_world", tampered).get("ok", true), "raised cargo without minting breaks conservation")
	var dup: Dictionary = _parsed(raw)
	dup.fleet.append(dup.fleet[0].duplicate(true))
	check(not world_script.call("validate_world", dup).get("ok", true), "duplicate ship identity rejected")
	var extra: Dictionary = _parsed(raw)
	extra.unknownField = 1
	check(not world_script.call("validate_world", extra).get("ok", true), "unknown save fields rejected")
	var two_transfers: Dictionary = _parsed(raw)
	two_transfers.transfers = [{"id": "t1"}, {"id": "t2"}]
	check(not world_script.call("validate_world", two_transfers).get("ok", true), "second handoff transfer rejected")

func _parsed(raw: String) -> Dictionary:
	var parser := JSON.new()
	parser.parse(raw)
	return (parser.data as Dictionary).duplicate(true)

func _test_legacy_parity() -> void:
	var legacy := _legacy()
	var world := _world()
	var home: Dictionary = legacy.port("xiamen")
	# dock gate parity: near and slow accepts; far or fast refuses on both copies.
	for case in [{"d": 25.0, "s": 0.0, "near": true}, {"d": 200.0, "s": 0.0, "near": false}, {"d": 25.0, "s": 2.0, "near": false}]:
		legacy.state.position = {"x": home.x + case.d, "z": home.z}
		legacy.state.speed = case.s
		legacy.state.currentPortId = null
		var legacy_dock: Dictionary = legacy.command({"type": "dock", "portId": "xiamen"})
		var ship: Dictionary = world.state.fleet[0]
		ship.position = {"x": float(_opening().ports[0].x) + case.d, "z": float(_opening().ports[0].z)}
		ship.speed = case.s
		world.state.currentPortId = ""
		var story_dock: Dictionary = world.call("command", {"type": "dock", "portId": "xiamen"})
		check(legacy_dock.ok == story_dock.ok and legacy_dock.ok == case.near, "dock gate parity at distance %s speed %s" % [case.d, case.s])
	# trade quote parity on cloned states. A docked fleet must be stationary,
	# matching the frozen oracle invariant (save_validation.gd:73). Market drift
	# factors are pinned to 1.0: the parity target is the copied quote math.
	legacy.state.currentPortId = "xiamen"
	legacy.state.speed = 0
	world.state.currentPortId = "xiamen"
	world.state.fleet[0].speed = 0.0
	for good: String in RULES_KINDS:
		world.state.ports.xiamen.priceFactor[good] = 1.0
		world.state.ports.kinmen.priceFactor[good] = 1.0
	var market: int = int(legacy.state.markets.xiamen.grain)
	var port_data: Dictionary = legacy.port("xiamen")
	for quantity in [1, 7, 40]:
		var legacy_buy: Dictionary = legacy.preview({"type": "buy", "good": "grain", "quantity": quantity})
		var twin: RefCounted = world_script.new()
		twin.call("restore", world.call("serialize"))
		var story_buy: Dictionary = twin.call("command", {"type": "buy", "good": "grain", "quantity": quantity})
		check(legacy_buy.ok == story_buy.ok, "buy parity accepts at quantity %d (legacy=%s/%s story=%s/%s)" % [quantity, legacy_buy.ok, legacy_buy.get("reason", ""), story_buy.ok, story_buy.get("reason", "")])
		if legacy_buy.ok:
			check(int(legacy_buy.cost) == int(story_buy.receipt.details.silver) * -1, "buy parity cost at quantity %d" % quantity)
	for quantity in [2, 10]:
		var legacy_sell: Dictionary = legacy.preview({"type": "sell", "good": "grain", "quantity": quantity})
		var twin: RefCounted = world_script.new()
		twin.call("restore", world.call("serialize"))
		var story_sell: Dictionary = twin.call("command", {"type": "sell", "good": "grain", "quantity": quantity})
		check(legacy_sell.ok == story_sell.ok, "sell parity accepts at quantity %d (legacy=%s/%s story=%s/%s)" % [quantity, legacy_sell.ok, legacy_sell.get("reason", ""), story_sell.ok, story_sell.get("reason", "")])
		if legacy_sell.ok:
			check(int(legacy_sell.reward) == int(story_sell.receipt.details.silver), "sell parity reward at quantity %d" % quantity)
	check(market > 0 and port_data.prices.grain > 0.0, "parity fixture uses live legacy market")
	# board gate and capture parity: refusals first, accepted capture last
	# (a real capture settles the target and arms the cooldown).
	for case in [{"distance": 50.0, "rel": 0.0, "hull": 60, "crew": 20, "accept": false}, {"distance": 20.0, "rel": 4.0, "hull": 60, "crew": 20, "accept": false}, {"distance": 20.0, "rel": 0.0, "hull": 90, "crew": 60, "accept": false}, {"distance": 20.0, "rel": 0.0, "hull": 60, "crew": 20, "accept": true}]:
		legacy.state.currentPortId = null
		legacy.latestNaval = _native_pair(case.distance, case.rel, case.hull, case.crew)
		var legacy_board: Dictionary = legacy.command({"type": "resolve-boarding", "targetId": "tgt", "success": true, "disposition": "capture", "injury": 0})
		world.state.currentPortId = ""
		world.call("attach_native", _native_pair(case.distance, case.rel, case.hull, case.crew))
		var story_board: Dictionary = world.call("command", {"type": "resolve-boarding", "targetId": "tgt", "captured": true, "disposition": "capture", "battleId": "parity-battle"})
		check(legacy_board.ok == story_board.ok and legacy_board.ok == case.accept, "board gate parity distance %s rel %s hull %s crew %s" % [case.distance, case.rel, case.hull, case.crew])
		if case.accept:
			check(int(legacy.flagship().crew) == int(world.state.fleet[0].crew), "capture volunteers parity")
			check(legacy.state.fleet.size() == world.state.fleet.size(), "prize insertion parity")
			check(int(legacy.state.fleet.back().crew) == int(world.state.fleet.back().crew), "prize crew parity")
	# reset both for the accepted-capture measurement already done above.

func _test_ledger_and_deliver() -> void:
	var world := _world()
	world.state.currentPortId = "xiamen"
	check(world.call("command", {"type": "open-contract", "contractId": "ch03", "kind": "trade-profit", "targetIds": []}).get("ok", false), "task ledger opens")
	var buy: Dictionary = world.call("command", {"type": "buy", "good": "grain", "quantity": 5})
	check(buy.get("ok", false), "buy settles against story market")
	var sell: Dictionary = world.call("command", {"type": "sell", "good": "grain", "quantity": 3})
	check(sell.get("ok", false), "sell settles against story market")
	var expected: int = int(sell.receipt.details.silver) + int(buy.receipt.details.silver)
	var ledger: Dictionary = world.call("voyage_ledger", "ch03")
	check(ledger.get("ok", false) and int(ledger.net) == expected, "per-task ledger nets this attempt only")
	check(world.call("command", {"type": "close-contract", "contractId": "ch03"}).get("ok", false), "task ledger closes")
	check(int(world.call("voyage_ledger", "ch03").net) == expected, "closed ledger retains its own window")
	check(not world.call("command", {"type": "open-contract", "contractId": "ch03b", "kind": "trade-profit"}).get("ok", true) or int(world.call("voyage_ledger", "ch03b").net) == 0, "fresh ledger never inherits old profit")
	world.state.currentPortId = "kinmen"
	var before: int = int(world.state.fleet[0].cargo.grain)
	var delivered: Dictionary = world.call("command", {"type": "deliver", "good": "grain", "quantity": 10})
	check(delivered.get("ok", false) and int(world.state.fleet[0].cargo.grain) == before - 10, "deliver consumes shipped goods")
	check(int(world.state.meta.burned.grain) == 10, "delivery burns goods out of the world ledger")
	check(not world.call("command", {"type": "deliver", "good": "grain", "quantity": 100000}).get("ok", true), "over-delivery refused")
	check(world_script.call("validate_world", world.call("snapshot")).get("ok", false), "conservation holds after trade and delivery")

func _test_manifests_and_handoff() -> void:
	var world := _world()
	var hull_before: int = int(world.state.fleet[0].hull)
	var silver_before: int = int(world.state.silver)
	check(world.call("command", {"type": "spawn-entity", "entity": {"id": "g1", "kind": "garrison", "team": "neutral", "name": "对照守军", "inventory": {"grain": 50}, "people": 5}}).get("ok", false), "garrison entity materializes with minted goods")
	check(int(world.state.meta.minted.grain) == 320, "spawned inventory joins minted totals")
	var loaded: Dictionary = world.call("command", {"type": "load-manifest", "manifestId": "m1", "fromId": "g1", "people": 2, "cargo": {"grain": 20}, "ontoShipIds": ["player"]})
	check(loaded.get("ok", false), "load-manifest moves people and goods onto ships")
	check(int(world.state.entities.g1.inventory.grain) == 30 and int(world.state.fleet[0].cargo.grain) == 50, "load-manifest conserves goods between source and ship")
	var handed: Dictionary = world.call("command", {"type": "handover-facilities", "handoverId": "h1", "facilityId": "g1", "portId": "kinmen"})
	check(handed.get("ok", false) and int(world.state.ports.kinmen.stock.grain) == 70, "handover transfers itemized inventory into the port")
	check(int(handed.receipt.details.itemized.grain) == 30, "handover receipt itemizes exact quantities")
	check(world_script.call("validate_world", world.call("snapshot")).get("ok", false), "conservation holds across load and handover")
	var manifest: Dictionary = world.call("present_manifest")
	check(manifest.ships == ["player"] and manifest.people == [], "present manifest lists only what is actually present")
	var transfer: Dictionary = world.call("command", {"type": "transfer-manifest", "to": "zheng-chenggong", "manifest": {"ships": ["player", "ghost"], "people": []}})
	check(transfer.get("ok", false) and transfer.receipt.details.leftBehind == ["ghost"], "handoff keeps absent ships in leftBehind")
	check(not world.call("command", {"type": "transfer-manifest", "to": "zheng-chenggong", "manifest": {"ships": ["player"], "people": []}}).get("ok", true), "duplicate handoff refused")
	check(int(world.state.fleet[0].hull) == hull_before and int(world.state.silver) == silver_before, "handoff heals nothing and clears no money")
	# story save: world + progress in one file, handoff markers must agree.
	var progress: RefCounted = load(PROGRESS_PATH).new()
	check(progress.call("configure", 1661, "story-run").get("ok", false), "progress fixture configures")
	var pristine: RefCounted = world_script.new()
	pristine.call("configure", _opening(), 1661, "story-run")
	var aligned: String = save_script.call("encode", pristine.call("snapshot"), progress.call("serialize"))
	check(save_script.call("validate", aligned).get("ok", false), "story save validates world and progress together")
	var contradiction: String = save_script.call("encode", world.call("snapshot"), progress.call("serialize"))
	check(not save_script.call("validate", contradiction).get("ok", true), "world transfer without progress handoff rejected")
	check(not save_script.call("validate", aligned + "x").get("ok", true), "corrupted save bytes rejected")
