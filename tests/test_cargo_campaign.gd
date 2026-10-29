extends SceneTree
## Constructed events exercise real Campaign/codec/Bridge boundaries, not live combat proof.

const Campaign = preload("res://game/domain/mingqi/campaign.gd")
const SaveCodec = preload("res://game/domain/persistence/save_codec.gd")
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func envelope(state: Dictionary) -> String:
	return JSON.stringify({"version":2,"campaignId":state.campaignId,"mode":"mingqi-1650","savedAtUtc":"2026-10-29T00:00:00.000Z","simulationSeconds":state.simulationSeconds,"state":state},"",false,true)

func same_data(a: Variant, b: Variant) -> bool:
	# JSON restores integer-valued numbers as floats; the existing domain accepts
	# both. Container equality is type-sensitive, so compare their numeric value.
	if typeof(a) in [TYPE_INT,TYPE_FLOAT] and typeof(b) in [TYPE_INT,TYPE_FLOAT]:
		return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size(): return false
		for key: Variant in a:
			if not b.has(key) or not same_data(a[key],b[key]): return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size(): return false
		for index in a.size():
			if not same_data(a[index],b[index]): return false
		return true
	return a == b

func fixture(cargo: Dictionary, suffix: String = "flagship"):
	var campaign = Campaign.new(1650,"林船长","cargo-test")
	var state: Dictionary = campaign.snapshot()
	state.vessels["cargo-test-"+suffix].cargo = cargo.duplicate(true)
	check(campaign.restore(envelope(state)), "constructed initial cargo passes real save contract")
	check(campaign.advance(10.0, state.vessels.keys()).ok, "fixture uses accepted business time")
	return campaign

func observation(campaign) -> Dictionary:
	var state: Dictionary = campaign.snapshot()
	var ships: Array = []
	for vessel: Dictionary in state.vessels.values():
		var ship := {"id":vessel.id,"controlsSequence":1,"visual":{"position":{"x":vessel.pose.position.x,"y":0.0,"z":vessel.pose.position.z},"velocity":{"x":0.0,"y":0.0,"z":0.0},"heading":vessel.pose.heading},"hull":vessel.damage.hull,"sail":vessel.damage.sail,"crew":vessel.crew.able,"ammo":vessel.combat.ammo.duplicate(true),"ammoType":vessel.combat.ammoType,"cooldownSeconds":vessel.combat.cooldownSeconds.duplicate(true)}
		ship.merge(vessel.controls.duplicate(true))
		ships.append(ship)
	return {"battleId":"cargo-battle","tick":120,"time":2.0,"ships":ships}

func hit(campaign, id: String = "hit-1", ammo: String = "solid", located: bool = true) -> Dictionary:
	var vessel: Dictionary = campaign.snapshot().vessels["cargo-test-flagship"]
	var event := {"id":id,"type":"hit","time":1.5,"shipId":"cargo-test-enemy","targetId":"cargo-test-flagship","ammo":ammo,"damage":{"hull":0.0,"sail":0.0,"crew":0.0}}
	if located:
		event.position = {"x":vessel.pose.position.x+2.0,"y":4.0,"z":vessel.pose.position.z}
	return event

func native_ship(snapshot: Dictionary, id: String) -> Dictionary:
	for ship: Dictionary in snapshot.ships:
		if ship.id == id:
			return ship
	return {}

func _run() -> void:
	var campaign = fixture({"grain":12,"silk":9})
	var native := observation(campaign)
	var event := hit(campaign)
	check(campaign.sync_near(native,[event]).ok, "located solid hit commits through real Campaign boundary")
	var state: Dictionary = campaign.snapshot()
	var receipt_id := "cargo-test:cargo-battle:hit-1"
	check(same_data(state.vessels["cargo-test-flagship"].cargo,{"grain":7,"silk":9}), "existing grain-first five-unit balance retained")
	var receipt: Dictionary = state.settlements[receipt_id]
	check(receipt.kind == "cargo-loss" and receipt.get("details",{}).get("kind") == "cargo-drop", "committed cargo loss carries structured drop cause")
	var alternative = fixture({"silk":9})
	check(alternative.sync_near(observation(alternative),[hit(alternative)]).ok and same_data(alternative.snapshot().vessels["cargo-test-flagship"].cargo,{"silk":4}), "non-grain solid loss changes actual cargo, not only props")
	if not check(campaign.has_method("cargo_presentation") and Runtime.new().has_method("cargo_presentation"), "Campaign and Runtime expose committed cargo presentation"):
		_finish()
		return
	if not check(receipt.has("details"), "structured receipt available for persistence assertions"):
		_finish()
		return
	var details: Dictionary = receipt.details
	check(details.quantity == 5 and details.goodId == "grain" and details.sourceEventId == "hit-1" and details.shipId == "cargo-test-flagship" and details.sourceShipId == "cargo-test-enemy", "details identify actual removed good and both ships")
	check(details.dropId == receipt_id+":cargo" and details.eventTime == 1.5 and details.nativeTime == 2.0 and details.nativeTick == 120 and details.campaignTime == 10.0, "drop ties native cause to accepted business receipt time")
	check(details.hasImpact and details.originKind == "event-position" and details.impactPosition == event.position, "real impact position reaches persisted detail")
	var projection: Dictionary = campaign.call("cargo_presentation")
	check(projection.epoch == "cargo-test" and projection.time == 10.0 and projection.manifests.size() == state.vessels.size() and same_data(projection.manifests["cargo-test-flagship"],{"grain":7,"silk":9}), "presentation includes detached actual manifests for all vessels")
	check(projection.drops == [details], "only committed loss detail creates a drop projection")
	projection.manifests["cargo-test-flagship"].grain = 900
	projection.drops[0].quantity = 999
	check(campaign.snapshot() == state and campaign.call("cargo_presentation").drops == [details], "presentation callers cannot mutate cargo or receipts")
	check(campaign.sync_near(native,[event]).ok, "same native event may be observed again")
	check(same_data(campaign.snapshot().vessels["cargo-test-flagship"].cargo,{"grain":7,"silk":9}) and campaign.call("cargo_presentation").drops.size() == 1, "receipt replay never repeats debit or creates another drop")
	var encoded: String = campaign.serialize()
	check(not encoded.is_empty() and SaveCodec.decode(encoded).get("ok",false), "new cargo detail survives strict save encoding")
	var restored = Campaign.new()
	check(restored.restore(encoded) and same_data(restored.call("cargo_presentation"),campaign.call("cargo_presentation")), "save restore reconstructs same committed cargo projection")
	check(restored.sync_near(native,[event]).ok and same_data(restored.snapshot().vessels["cargo-test-flagship"].cargo,{"grain":7,"silk":9}), "replay after restore cannot duplicate debit")
	state = campaign.snapshot()
	for mutation: String in ["unknown-good","quantity-zero","quantity-six","quantity-fraction","quantity-bool","drop-id","receipt-id","source-event","foreign-ship","other-ship","other-source","future-event","future-tick","business-clock","impact-type","impact-axis","origin-pair","origin-speed","extra-key","cause-order","cause-missing"]:
		var forged: Dictionary = state.duplicate(true)
		var bad: Dictionary = forged.settlements[receipt_id].details
		match mutation:
			"unknown-good": bad.goodId = "gold"
			"quantity-zero": bad.quantity = 0
			"quantity-six": bad.quantity = 6
			"quantity-fraction": bad.quantity = 1.5
			"quantity-bool": bad.quantity = true
			"drop-id": bad.dropId = "foreign:drop"
			"receipt-id": forged.settlements[receipt_id].id = "foreign:receipt"
			"source-event": bad.sourceEventId = "other-hit"
			"foreign-ship": bad.shipId = "foreign-ship"
			"other-ship": bad.shipId = "cargo-test-fast"
			"other-source": bad.sourceShipId = "cargo-test-fast"
			"future-event": bad.eventTime = 2.1
			"future-tick": bad.nativeTick = 121
			"business-clock": bad.campaignTime = 9.0
			"impact-type": bad.hasImpact = "true"
			"impact-axis": bad.impactPosition.y = true
			"origin-pair": bad.originKind = "vessel-pose"
			"origin-speed": bad.originPose.speed = -1.0
			"extra-key": bad.unverifiedCargo = 5
			"cause-order","cause-missing":
				for entry: Dictionary in forged.chronicle:
					if entry.id == receipt_id:
						if mutation == "cause-order": entry.causeIds.reverse()
						else: entry.causeIds.remove_at(0)
		check(not SaveCodec.decode(envelope(forged)).get("ok",false), "save rejects inconsistent cargo detail: " + mutation)
	var legacy: Dictionary = state.duplicate(true)
	legacy.settlements[receipt_id].erase("details")
	check(SaveCodec.decode(envelope(legacy)).get("ok",false), "old cargo-loss receipt without details remains valid")
	var old_event = fixture({"grain":8})
	check(old_event.sync_near(observation(old_event),[hit(old_event,"old-hit","solid",false)]).ok and old_event.snapshot().vessels["cargo-test-flagship"].cargo.grain == 3, "old near-sync hit without position retains five-unit debit")
	check(old_event.call("cargo_presentation").drops.is_empty() and not old_event.serialize().is_empty(), "old unlocated hit preserves save compatibility without invented visual birth")
	var trader = fixture({"grain":2})
	check(trader.command({"type":"buy","commandId":"cargo-buy","expectedRevision":trader.snapshot().revision,"good":"grain","quantity":3}).ok and trader.call("cargo_presentation").manifests["cargo-test-flagship"].grain == 5, "actual purchase updates visible cargo manifest")
	check(trader.command({"type":"sell","commandId":"cargo-sell","expectedRevision":trader.snapshot().revision,"good":"grain","quantity":2}).ok and trader.call("cargo_presentation").manifests["cargo-test-flagship"].grain == 3 and trader.call("cargo_presentation").drops.is_empty(), "actual sale never masquerades as dropped cargo")
	for ammo: String in ["chain","grape"]:
		var non_loss = fixture({"grain":8,"iron":3})
		check(non_loss.sync_near(observation(non_loss),[hit(non_loss,"no-loss",ammo)]).ok and same_data(non_loss.snapshot().vessels["cargo-test-flagship"].cargo,{"grain":8,"iron":3}) and non_loss.call("cargo_presentation").drops.is_empty(), ammo+" does not create cargo loss or props")
	var atomic = fixture({"grain":12})
	var before: Dictionary = atomic.snapshot()
	var invalid := hit(atomic,"bad-position")
	invalid.position.y = NAN
	check(not atomic.sync_near(observation(atomic),[hit(atomic,"valid-first"),invalid]).ok and atomic.snapshot() == before, "invalid later hit rolls back complete cargo/receipt batch")
	check(atomic.call("cargo_presentation").drops.is_empty(), "rejected transaction cannot leak a visual drop")
	invalid = hit(atomic,"future")
	invalid.time = 2.01
	check(not atomic.sync_near(observation(atomic),[invalid]).ok and atomic.snapshot() == before, "future hit rejects without cargo mutation")
	var refused: Dictionary = atomic.reconcile_near(observation(atomic),[hit(atomic,"refused")],before.vessels.keys(),func(_vessels: Array,_state: Dictionary) -> Dictionary:return {"ok":false,"reason":"fixture-native-refusal"})
	check(not refused.ok and atomic.snapshot() == before and atomic.call("cargo_presentation").drops.is_empty(), "native projection refusal leaves cargo and visual receipt uncommitted")
	check(campaign.advance(40.0,state.vessels.keys()).ok and campaign.call("cargo_presentation").drops.is_empty(), "forty accepted seconds retire visual projection without deleting receipt")
	check(campaign.snapshot().settlements.has(receipt_id), "visual expiry preserves durable loss accounting")
	_runtime_bridge()
	_finish()

func _runtime_bridge() -> void:
	var session = fixture({"wood":9}, "fast")
	var runtime = Runtime.new()
	if not check(runtime.configure(func(_x:float,_z:float)->float:return -24.0,session).ok, "real runtime/Bridge accepts constructed cargo fixture"):
		return
	var before: Dictionary = runtime.snapshot()
	var alternate_save: String = runtime.campaign.serialize()
	check(not alternate_save.is_empty(), "same-clock alternate branch serializes before cargo loss")
	var ship := native_ship(before.naval,"cargo-test-fast")
	check(ship.stats.cargoMass == 900 and absf(ship.dimensions.draft-1.09)<0.000001, "Bridge projects actual pre-loss mass and draft")
	var point: Dictionary = ship.visual.position
	runtime.simulation.encounter._emit({"type":"hit","shipId":"cargo-test-flagship","targetId":"cargo-test-fast","ammo":"solid","position":{"x":point.x+1.0,"y":point.y+2.0,"z":point.z},"damage":{"hull":0.0,"sail":0.0,"crew":0.0}})
	runtime.bridge.capture()
	check(runtime.call("cargo_presentation").drops.is_empty() and runtime.call("cargo_presentation").manifests["cargo-test-fast"].wood == 9, "raw observed hit does not bypass business commit")
	check(runtime.bridge.sync().ok, "real Bridge commits constructed hit and reconciles native load")
	var after: Dictionary = runtime.snapshot()
	ship = native_ship(after.naval,"cargo-test-fast")
	check(after.campaign.vessels["cargo-test-fast"].cargo.wood == 4 and ship.stats.cargoMass == 400 and absf(ship.dimensions.draft-1.04)<0.000001, "same transaction decreases cargo, native mass and draft consistently")
	var exposed: Dictionary = runtime.call("cargo_presentation")
	var authority: Dictionary = runtime.campaign.call("cargo_presentation")
	check(exposed.time == authority.time and exposed.manifests == authority.manifests and exposed.drops == authority.drops and exposed.drops.size() == 1 and exposed.epoch == "cargo-test:runtime:"+str(before.runtime.generation), "Runtime proxy preserves committed data and scopes visuals to live generation")
	var committed: Dictionary = runtime.call("cargo_presentation")
	check(runtime.bridge.sync().ok and runtime.call("cargo_presentation") == committed, "Bridge refresh cannot debit or emit committed loss again")
	if check(runtime.adopt_save(alternate_save).ok, "real adoption accepts same-campaign same-time alternate branch"):
		var loaded: Dictionary = runtime.call("cargo_presentation")
		check(loaded.time == committed.time and loaded.epoch != committed.epoch and loaded.epoch == "cargo-test:runtime:"+str(before.runtime.generation+1), "successful same-clock adoption changes visual epoch without relying on rewind")
		check(loaded.drops.is_empty() and loaded.manifests["cargo-test-fast"].wood == 9, "alternate branch owns its original cargo and no previous branch drops")
		check(not runtime.adopt_save("{invalid").ok and runtime.call("cargo_presentation") == loaded, "failed adoption preserves current generation and cargo projection")
	runtime.dispose()

func _finish() -> void:
	print("CARGO_CAMPAIGN_TEST_COMPLETE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
