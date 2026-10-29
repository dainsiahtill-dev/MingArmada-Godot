extends SceneTree
const ViewPath := "res://game/presentation/cargo/cargo_world_view.gd"
const Ship = preload("res://game/presentation/ships/ship_view.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Damage = preload("res://game/domain/mingqi/cargo_damage.gd")
var checks := 0
var failures := 0
func _initialize() -> void: _run.call_deferred()
func check(value: bool, message: String) -> bool:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",message)
	return value
func _run() -> void:
	if not check(ResourceLoader.exists(ViewPath),"cargo world projection exists"): _finish(); return
	var encounter := Encounter.new({"battleId":"cargo-test","ships":[{"id":"merchant","kind":"fuchuan","team":"player","position":{"x":0.0,"z":0.0}}],"playerId":"merchant"})
	var native: Dictionary = encounter.snapshot()
	var ship := Ship.new(); root.add_child(ship)
	check(ship.configure("fuchuan"),"real authored ship configured")
	var timed: Dictionary = native.ships[0].duplicate(true); timed.time = 0.0
	ship.apply_snapshot(timed,native.wind,0.0)
	var model: Node3D = ship.get("_models")[0]
	var view = load(ViewPath).new(); root.add_child(view)
	check(view.configure(func(_x:float,_z:float,_t:float)->float:return 0.0,func(id:String)->Dictionary:return {"model":model,"kind":"fuchuan"} if id=="merchant" else {}).ok,"injected real model and sea configure")
	var packet := {"epoch":"campaign","time":0.0,"manifests":{"merchant":{"grain":10,"wood":4}},"drops":[]}
	var original := packet.duplicate(true)
	check(view.apply_snapshot(native,packet).ok,"committed manifest accepted")
	var state: Dictionary = view.inspection_snapshot()
	check(state.decks.merchant.goods.size()==2 and state.floating.is_empty(),"cargo loaded on safe deck without fake drops")
	var plan := Damage.plan(packet.manifests.merchant,{"id":"hit1","campaignId":"campaign","battleId":"cargo-test","vesselId":"merchant","sourceShipId":"merchant","ammo":"solid","nativeTick":1,"eventTime":0.0,"nativeTime":0.0,"campaignTime":0.0,"pose":{"position":{"x":0.0,"z":0.0},"heading":0.0,"speed":0.0},"position":{"x":2.0,"y":3.0,"z":0.0}})
	check(plan.ok and plan.loss==5,"authority planner supplies actual loss")
	packet.manifests.merchant=plan.afterCargo; packet.drops=[plan.details]
	view.apply_snapshot(native,packet)
	check(view.inspection_snapshot().floating.size()==1,"committed loss spawns one representative lot")
	packet.time=2.0; native.time=2.0
	view.apply_snapshot(native,packet)
	var wet: Dictionary=view.inspection_snapshot()
	check(wet.floating.size()==1 and wet.floating[0].phase=="floating","authored cargo lands on actual sampled sea")
	var splashes: Array=view.drain_splashes()
	check(splashes.size()==1 and splashes[0].type=="splash","one real crossing produces one splash")
	var paused: Dictionary=view.inspection_snapshot()
	view.apply_snapshot(native,packet)
	check(view.inspection_snapshot().floating==wet.floating and view.drain_splashes().is_empty(),"pause and repeated receipt cannot move or duplicate")
	check(view.inspection_snapshot()==paused,"paused replay of committed drop is fully idempotent including diagnostics")
	packet.manifests.merchant={}; view.apply_snapshot(native,packet)
	check(view.inspection_snapshot().decks.merchant.goods.is_empty() and view.inspection_snapshot().floating.size()==1,"unloading only removes deck props; no extra debris")
	packet.epoch="other"; packet.drops=[]; view.apply_snapshot(native,packet)
	check(view.inspection_snapshot().floating.is_empty(),"new campaign clears floating ownership")
	check(original.manifests.merchant.grain==10 and native.ships[0].hull==100.0,"renderer never changes business stock or native hull")
	var merchant:=Ship.new();root.add_child(merchant);check(merchant.configure("merchant"),"actual merchant model configures")
	merchant.apply_snapshot(timed,native.wind,0.0)
	var merchant_model:Node3D=merchant.get("_models")[0]
	var merchant_view=load(ViewPath).new();root.add_child(merchant_view)
	merchant_view.configure(func(_x:float,_z:float,_t:float)->float:return 0.0,func(_id:String)->Dictionary:return {"model":merchant_model,"kind":"merchant"})
	merchant_view.apply_snapshot(native,{"epoch":"merchant-scale","time":2.0,"manifests":{"merchant":plan.afterCargo},"drops":[plan.details]})
	var deck_scale:float=merchant_view.inspection_snapshot().decks.merchant.layout_profile.model_scale
	check(deck_scale==0.5 and merchant_view.get("_floating")[plan.details.dropId].scale==Vector3.ONE*deck_scale,"merchant package retains its authored on-deck scale after ejection")
	merchant_view.dispose();merchant_view.free();merchant.dispose();merchant.free()
	view.dispose(); check(view.inspection_snapshot().decks.is_empty() and view.inspection_snapshot().floating.is_empty(),"dispose releases all instances")
	view.free(); ship.dispose(); ship.free(); _finish()
func _finish() -> void:
	print("CARGO_WORLD_VIEW checks=%d failures=%d"%[checks,failures]); quit(1 if failures else 0)
