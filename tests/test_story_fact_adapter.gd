extends SceneTree
## Fact adapter witnesses over REAL world settlements, with settle-time
## re-verification negatives and one full progress-contract integration.

const FACT_PATH := "res://game/domain/story_campaign/fact_adapter.gd"
const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const SCENARIOS_PATH := "res://game/domain/story_campaign/scenarios.gd"
const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
const WORLD_PATH := "res://game/domain/story_world/story_world_session.gd"
var assertions: int = 0
var failures: int = 0
var fact_script: GDScript
var progress_script: GDScript
var scenarios_script: GDScript
var catalog_script: GDScript
var world_script: GDScript
var stages: Array = []

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	fact_script = load(FACT_PATH) as GDScript
	progress_script = load(PROGRESS_PATH) as GDScript
	scenarios_script = load(SCENARIOS_PATH) as GDScript
	catalog_script = load(CATALOG_PATH) as GDScript
	world_script = load(WORLD_PATH) as GDScript
	if not check(fact_script != null and world_script != null, "fact adapter and world session load"):
		_finish()
		return
	stages = catalog_script.call("stages")
	_test_sailing_and_trade_witnesses()
	_test_encounter_witnesses()
	_test_escort_and_people_witnesses()
	_test_port_transaction_witnesses()
	_test_taiwan_witnesses()
	_test_settle_time_reverification()
	_test_progress_contract_integration()
	_finish()

func _finish() -> void:
	print("STORY_FACT_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

# --- fixtures ---------------------------------------------------------------

func _fresh() -> Array:
	var world: RefCounted = world_script.new()
	world.call("configure", scenarios_script.call("opening"), 1661, "story-run")
	world.state.currentPortId = ""
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	return [world, {"ships": []}]

func _stage(stage_id: String) -> Dictionary:
	for entry: Dictionary in stages:
		if entry.id == stage_id:
			return entry
	return {}

func _scenario(stage_id: String) -> Dictionary:
	return scenarios_script.call("scenario", stage_id)

func _ship_entry(id: String, team: String, kind: String, hull: int, crew: int, x: float, z: float) -> Dictionary:
	return {"id": id, "team": team, "kind": kind, "name": id, "hull": hull, "maxHull": 100, "crew": crew, "maxCrew": 70, "sail": 50, "maxSail": 100, "ammo": {"solid": 0, "chain": 0, "grape": 0},
		"visual": {"position": {"x": x, "z": z}, "velocity": {"x": 0.0, "z": 0.0}, "heading": 0.0}}

func _outcome(stage_id: String, world: RefCounted, native: Dictionary, retreat: bool = false) -> String:
	var result: Dictionary = fact_script.call("settle", _stage(stage_id), _scenario(stage_id), world.call("snapshot"), native, retreat)
	return str(result.outcome)

func _facts(stage_id: String, world: RefCounted, native: Dictionary) -> Array:
	return fact_script.call("facts", _stage(stage_id), _scenario(stage_id), world.call("snapshot"), native, "story-run", 1)

# --- tests ------------------------------------------------------------------

func _test_sailing_and_trade_witnesses() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	world.state.currentPortId = "kinmen"
	world.call("command", {"type": "deliver", "good": "grain", "quantity": 30})
	check(_outcome("CH-01-S1", world, native) == "success", "CH-01 deliver witness settles from real delivery")
	world.call("command", {"type": "open-contract", "contractId": "ch03-public-cargo", "kind": "trade-profit"})
	world.state.currentPortId = "xiamen"
	world.state.silver = 2000
	world.call("command", {"type": "buy", "good": "grain", "quantity": 60})
	world.state.currentPortId = "kinmen"
	world.call("command", {"type": "sell", "good": "grain", "quantity": 60})
	check(_outcome("CH-03-S1", world, native) == "success", "CH-03 trade-profit witness counts only its own ledger window")
	pair = _fresh()
	world = pair[0]
	native = pair[1]
	world.state.silver = 4000
	world.state.currentPortId = "xiamen"
	world.call("command", {"type": "buy-ship", "kind": "merchant"})
	var merchant_id: String = str(world.state.fleet[1].id)
	world.call("command", {"type": "sign-charter", "permitId": "regional-supply-renewal", "scope": "expedition-supply", "issuer": "ming-coast", "cost": 120, "conditions": ["续订粮水与修材"]})
	world.call("command", {"type": "mint-grant", "shipId": merchant_id, "good": "grain", "quantity": 120})
	world.call("command", {"type": "mint-grant", "shipId": merchant_id, "good": "wood", "quantity": 40})
	world.call("command", {"type": "mint-grant", "shipId": "player", "good": "grain", "quantity": 30})
	var ch20: Dictionary = fact_script.call("settle", _stage("CH-20-S1"), _scenario("CH-20-S1"), world.call("snapshot"), native)
	check(ch20.outcome == "success", "CH-20 stockpile witness reads live inventory: " + str(ch20.witnesses))
	world.call("command", {"type": "sell", "good": "grain", "quantity": 60})
	check(_outcome("CH-20-S1", world, native) != "success", "CH-20 stockpile invalid once goods are consumed")

func _test_encounter_witnesses() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch02-confirmed-prize", "hostile", "merchant", 65, 28, 20.0, 0.0)]}
	world.call("attach_native", native)
	world.call("command", {"type": "resolve-boarding", "targetId": "ch02-confirmed-prize", "captured": true, "disposition": "capture", "battleId": "b1"})
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0)]}
	world.call("attach_native", native)
	check(_outcome("CH-02-S1", world, native) == "success", "CH-02 capture witness accepts the confirmed prize")
	pair = _fresh()
	world = pair[0]
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch02-decoy-merchant", "hostile", "merchant", 65, 28, 20.0, 0.0)]}
	world.call("attach_native", native)
	world.call("command", {"type": "resolve-boarding", "targetId": "ch02-decoy-merchant", "captured": true, "disposition": "capture", "battleId": "b2"})
	check(_outcome("CH-02-S1", world, native) == "failure", "CH-02 decoy capture earns no objective credit")
	pair = _fresh()
	world = pair[0]
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch07-enemy-screen", "hostile", "patrol", 0, 12, 200.0, 200.0), _ship_entry("ch07-friendly-transport", "neutral", "merchant", 100, 18, -200.0, -200.0)]}
	check(_outcome("CH-07-S1", world, native) == "success", "CH-07 neutralize and protect witnesses hold together")
	native.ships[2].hull = 0
	check(_outcome("CH-07-S1", world, native) != "success", "CH-07 protect fails once the transport sinks")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "spawn-entity", "entity": {"id": "ch08-trade-route", "kind": "route", "team": "neutral", "name": "金门商路"}})
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch08-confirmed-raider", "hostile", "fuchuan", 60, 30, 20.0, 0.0)]}
	world.call("attach_native", native)
	world.call("command", {"type": "resolve-boarding", "targetId": "ch08-confirmed-raider", "captured": true, "disposition": "capture", "battleId": "b3"})
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0)]}
	world.call("attach_native", native)
	check(_outcome("CH-08-S1", world, native) == "success", "CH-08 capture plus route protect settles")
	world.state.entities["ch08-trade-route"].compromised = true
	check(_outcome("CH-08-S1", world, native) != "success", "CH-08 protect fails once the route is compromised")

func _test_escort_and_people_witnesses() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	native = {"ships": [_ship_entry("ch04-client-convoy", "neutral", "merchant", 100, 20, -150.0, 155.0)]}
	check(_outcome("CH-04-S1", world, native) == "success", "CH-04 escort arrival witness checks live position and hull")
	native.ships[0].hull = 0
	check(_outcome("CH-04-S1", world, native) == "failure", "CH-04 escort witness fails after the client sinks")
	pair = _fresh()
	world = pair[0]
	world.state.currentPortId = "xiamen"
	world.call("command", {"type": "sign-on", "personId": "ch05-willing-navigator", "name": "陈引水", "role": "navigator", "cost": 60, "wage": 6})
	check(_outcome("CH-05-S1", world, native) == "success", "CH-05 recruit witness reads signed contracts")
	pair = _fresh()
	world = pair[0]
	world.state.entities["ryukyu-envoy-vessel"] = {"id": "ryukyu-envoy-vessel", "kind": "fisherman", "team": "neutral", "name": "使船", "identity": {}, "inventory": {}, "people": 0, "position": {"x": 0.0, "z": 0.0}, "identified": false}
	world.call("command", {"type": "rescue", "targetId": "ryukyu-envoy-vessel"})
	native = {"ships": [_ship_entry("ryukyu-envoy-vessel", "neutral", "fisherman", 45, 12, 1275.0, -465.0)]}
	world.state.fleet[0].position = {"x": 0.0, "z": 0.0}
	world.call("command", {"type": "sign-charter", "permitId": "ryukyu-limited-trade-permit", "scope": "limited-trade", "issuer": "ryukyu-court", "cost": 80, "conditions": ["按货单申领"], "remote": true})
	check(_outcome("CH-09-S1", world, native) == "success", "CH-09 rescue, escort and permit witnesses combine")
	native.ships[0].visual.position = {"x": 0.0, "z": 0.0}
	check(_outcome("CH-09-S1", world, native) != "success", "CH-09 escort fails when the envoy is not at Naha now")
	pair = _fresh()
	world = pair[0]
	world.state.entities["ch11-quay-families"] = {"id": "ch11-quay-families", "kind": "group", "team": "neutral", "name": "家属", "identity": {}, "inventory": {}, "people": 40, "position": {"x": 0.0, "z": 0.0}, "identified": false}
	world.call("command", {"type": "rescue", "targetId": "ch11-quay-families"})
	world.call("command", {"type": "withdraw", "groupId": "ch11-evacuation-convoy", "rendezvousPortId": "malacca", "people": 40})
	world.state.currentPortId = "malacca"
	check(_outcome("CH-11-S1", world, native) == "success", "CH-11 rescue and withdraw witnesses hold at the rendezvous")
	world.state.currentPortId = "johor"
	check(_outcome("CH-11-S1", world, native) != "success", "CH-11 withdraw fails away from the rendezvous")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "transfer-manifest", "to": "zheng-chenggong", "manifest": {"ships": ["player"], "people": []}})
	check(_outcome("CH-12-S1", world, native) == "success", "CH-12 handoff witness requires the single real transfer")
	check(_outcome("CH-12-S1", world, native, true) == "retreat", "retreat hint is honored as an operation intent")

func _test_port_transaction_witnesses() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	world.call("command", {"type": "sign-charter", "permitId": "ming-coastal-service", "scope": "coastal-escort", "issuer": "ming-coast", "cost": 120, "conditions": ["仅限沿岸护送"], "remote": true})
	native = {"ships": [_ship_entry("ch06-service-convoy", "neutral", "merchant", 100, 16, -515.0, 205.0)]}
	check(_outcome("CH-06-S1", world, native) == "success", "CH-06 charter and escort witnesses combine")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "sign-charter", "permitId": "dutch-malacca-transit", "scope": "transit", "issuer": "voc-malacca", "cost": 150, "conditions": ["仅限转口"], "remote": true})
	world.call("command", {"type": "sign-charter", "permitId": "johor-provisioning-agreement", "scope": "provisioning", "issuer": "johor-court", "cost": 100, "conditions": ["运力担保"], "remote": true})
	check(_outcome("CH-10-S1", world, native) == "success", "CH-10 double charter witnesses hold separately")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "spawn-entity", "entity": {"id": "ch14-transshipment-quay", "kind": "facility", "team": "neutral", "name": "岸上转运栈", "inventory": {"grain": 40}}})
	world.state.currentPortId = "penghu"
	world.call("command", {"type": "resolve-land", "siteId": "ch14-transshipment-quay", "victory": true})
	world.call("command", {"type": "mint-grant", "good": "grain", "quantity": 40})
	world.call("command", {"type": "deliver", "good": "grain", "quantity": 40})
	world.call("command", {"type": "withdraw", "groupId": "ch14-shore-party", "rendezvousPortId": "penghu", "people": 12})
	check(_outcome("CH-14-S1", world, native) == "success", "CH-14 land, deliver and withdraw witnesses combine")
	pair = _fresh()
	world = pair[0]
	native = {"ships": [_ship_entry("ch17-first-leg", "neutral", "merchant", 100, 16, 275.0, -275.0)]}
	world.call("command", {"type": "dispatch-convoy", "dispatchId": "ch17-autonomous-convoy", "route": "xiamen-penghu", "shipIds": ["player"]})
	world.call("command", {"type": "return-dispatch", "dispatchId": "ch17-autonomous-convoy", "resultManifest": {"ships": ["player"]}})
	check(_outcome("CH-17-S1", world, native) == "success", "CH-17 dispatch return receipt witness holds")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "spawn-entity", "entity": {"id": "xiamen-survivors", "kind": "group", "team": "neutral", "name": "受困者", "people": 30}})
	world.call("command", {"type": "spawn-entity", "entity": {"id": "xiamen-reopened-quay", "kind": "facility", "team": "neutral", "name": "重开码头", "inventory": {}}})
	world.call("command", {"type": "spawn-entity", "entity": {"id": "xiamen-repair-watch", "kind": "watch", "team": "neutral", "name": "警戒线"}})
	world.call("command", {"type": "rescue", "targetId": "xiamen-survivors"})
	world.call("command", {"type": "resolve-land", "siteId": "xiamen-reopened-quay", "victory": true})
	check(_outcome("CH-15-S1", world, native) == "success", "CH-15 rescue, land and watch witnesses combine")

func _test_taiwan_witnesses() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	world.state.silver = 5000
	world.state.currentPortId = "xiamen"
	world.call("command", {"type": "buy-ship", "kind": "merchant"})
	var merchant_id: String = str(world.state.fleet[1].id)
	world.call("command", {"type": "spawn-entity", "entity": {"id": "taiwan-expedition-depot", "kind": "depot", "team": "neutral", "name": "积储", "inventory": {"grain": 120, "wood": 60}}})
	world.call("command", {"type": "spawn-entity", "entity": {"id": "taiwan-ready-transports", "kind": "watch", "team": "neutral", "name": "待发船团"}})
	var loaded: Dictionary = world.call("command", {"type": "load-manifest", "manifestId": "expedition-loading-manifest", "fromId": "taiwan-expedition-depot", "people": 0, "cargo": {"grain": 120, "wood": 60}, "ontoShipIds": ["player", merchant_id]})
	check(loaded.get("ok", false), "T01 loads the expedition manifest across the real fleet")
	check(_outcome("T01", world, native) == "success", "T01 load-manifest stockpile witness holds")
	world.state.fleet[0].cargo.grain = 0
	world.state.fleet[0].cargo.wood = 0
	world.state.fleet[1].cargo.grain = 0
	world.state.fleet[1].cargo.wood = 0
	world.state.meta.burned.grain = int(world.state.meta.burned.grain) + 150
	world.state.meta.burned.wood = int(world.state.meta.burned.wood) + 60
	check(_outcome("T01", world, native) != "success", "T01 stockpile invalid once loaded goods vanish")
	pair = _fresh()
	world = pair[0]
	world.state.currentPortId = "penghu"
	native = {"ships": [_ship_entry("taiwan-crossing-transports", "neutral", "merchant", 100, 18, 275.0, -275.0)]}
	check(_outcome("T02", world, native) == "success", "T02 arrive and protect witnesses combine")
	pair = _fresh()
	world = pair[0]
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("dutch-counterattack-1", "hostile", "voc", 0, 20, 300.0, 300.0), _ship_entry("dutch-counterattack-2", "hostile", "patrol", 0, 10, 320.0, 320.0)]}
	world.call("command", {"type": "spawn-entity", "entity": {"id": "heliao-established-bridgehead", "kind": "facility", "team": "neutral", "name": "登陆场", "inventory": {}}})
	check(_outcome("T04", world, native) == "success", "T04 formation neutralize and bridgehead protect hold")
	native.ships[2].hull = 30
	check(_outcome("T04", world, native) != "success", "T04 neutralize fails while a relief ship floats")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "spawn-entity", "entity": {"id": "provintia-garrison", "kind": "garrison", "team": "neutral", "name": "守军", "inventory": {"grain": 60, "iron": 24}, "people": 60}})
	world.call("command", {"type": "sign-terms", "agreementId": "provintia-terms", "terms": {"template": "conditional-surrender-v1"}, "parties": ["player", "provintia-garrison"]})
	world.call("command", {"type": "handover-facilities", "handoverId": "provintia-handover", "facilityId": "provintia-garrison", "portId": "provintia"})
	check(_outcome("T05", world, native) == "success", "T05 terms and handover witnesses combine")
	pair = _fresh()
	world = pair[0]
	world.call("command", {"type": "open-blockade", "watchId": "zeelandia-siege-line", "stationShipIds": ["player"], "linePoints": []})
	world.call("command", {"type": "spawn-entity", "entity": {"id": "zeelandia-wounded-return", "kind": "group", "team": "neutral", "name": "伤员", "people": 20}})
	world.call("command", {"type": "rescue", "targetId": "zeelandia-wounded-return"})
	check(_outcome("T06", world, native) == "success", "T06 blockade watch and rescue witnesses combine")
	world.call("command", {"type": "breach-blockade", "watchId": "zeelandia-siege-line"})
	check(_outcome("T06", world, native) != "success", "T06 blockade fails after a breach")
	pair = _fresh()
	world = pair[0]
	world.state.silver = 5000
	world.state.currentPortId = "xiamen"
	world.call("command", {"type": "buy-ship", "kind": "merchant"})
	var t10_merchant: String = str(world.state.fleet[1].id)
	world.state.currentPortId = "zeelandia"
	world.call("command", {"type": "spawn-entity", "entity": {"id": "zeelandia-garrison", "kind": "garrison", "team": "neutral", "name": "守军", "inventory": {"grain": 80, "iron": 24}, "people": 120}})
	world.call("command", {"type": "spawn-entity", "entity": {"id": "zeelandia-facilities", "kind": "facility", "team": "neutral", "name": "设施", "inventory": {"grain": 60, "wood": 20}}})
	world.call("command", {"type": "sign-terms", "agreementId": "zeelandia-surrender-terms", "terms": {"template": "capitulation-v1"}, "parties": ["player", "zeelandia-garrison"]})
	var evacuated: Dictionary = world.call("command", {"type": "load-manifest", "manifestId": "zeelandia-agreed-evacuation", "fromId": "zeelandia-garrison", "people": 120, "cargo": {"grain": 80, "iron": 24}, "ontoShipIds": ["player", t10_merchant]})
	check(evacuated.get("ok", false), "T10 evacuation manifest moves real people and goods: " + str(evacuated.get("reason", "")))
	var early: Dictionary = fact_script.call("settle", _stage("T10"), _scenario("T10"), world.call("snapshot"), native)
	check(early.outcome == "failure", "T10 incomplete while the fleet is still in port: " + str(early.witnesses))
	world.state.currentPortId = ""
	world.call("command", {"type": "handover-facilities", "handoverId": "zeelandia-final-handover", "facilityId": "zeelandia-facilities", "portId": "zeelandia"})
	var final: Dictionary = fact_script.call("settle", _stage("T10"), _scenario("T10"), world.call("snapshot"), native)
	check(final.outcome == "success", "T10 triple gate settles terms, evacuation and handover together: " + str(final.witnesses))

func _test_settle_time_reverification() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch07-enemy-screen", "hostile", "patrol", 0, 12, 200.0, 200.0), _ship_entry("ch07-friendly-transport", "neutral", "merchant", 100, 18, -200.0, -200.0)]}
	var observed: Array = _facts("CH-07-S1", world, native)
	check(observed.size() == 2, "facts observe both objectives while they hold")
	native.ships[2].hull = 0
	check(_outcome("CH-07-S1", world, native) != "success", "settle re-verification refuses a transport killed after observation")
	pair = _fresh()
	world = pair[0]
	native = {"ships": [_ship_entry("player", "player", "fuchuan", 100, 48, 0.0, 0.0), _ship_entry("ch07-enemy-screen", "hostile", "patrol", 0, 12, 200.0, 200.0), _ship_entry("ch07-friendly-transport", "neutral", "merchant", 100, 18, -200.0, -200.0)]}
	native.ships[1].hull = 40
	check(_outcome("CH-07-S1", world, native) == "partial", "partial outcome allowed for CH-07 with protect only")
	native.ships[1].hull = 0
	world.state.battleActive = true
	check(_outcome("CH-07-S1", world, native) != "success", "unsafe fleet cannot settle success")
	pair = _fresh()
	world = pair[0]
	world.state.currentPortId = "kinmen"
	world.call("command", {"type": "deliver", "good": "grain", "quantity": 30})
	check(_outcome("CH-01-S1", world, native) == "success", "CH-01 deliver holds at settle time")
	world.state.battleActive = true
	check(_outcome("CH-01-S1", world, native) != "success", "battle-active fleet never settles success")

func _test_progress_contract_integration() -> void:
	var pair := _fresh()
	var world: RefCounted = pair[0]
	var native: Dictionary = pair[1]
	world.state.currentPortId = "kinmen"
	world.call("command", {"type": "deliver", "good": "grain", "quantity": 30})
	var progress: RefCounted = progress_script.new()
	check(progress.call("configure", 1661, "story-run").get("ok", false), "progress configures for the adapter run")
	check(progress.call("begin", progress.call("snapshot").revision).get("ok", false), "CH-01 begins")
	var batch: Array = _facts("CH-01-S1", world, native)
	check(progress.call("observe", batch).get("ok", false), "adapter facts pass the trusted fact schema")
	var settled: Dictionary = fact_script.call("settle", _stage("CH-01-S1"), _scenario("CH-01-S1"), world.call("snapshot"), native)
	var result: Dictionary = progress.call("settle", progress.call("snapshot").revision, settled.outcome, settled.safe)
	check(result.get("ok", false), "adapter outcome settles the real progress contract")
	check(result.receipt.outcome == "success" and result.receipt.objectiveProgress["ch01-deliver"] == 1, "receipt records the verified objective progress")
