extends SceneTree

const MODEL_PATH := "res://game/presentation/cargo/cargo_drift.gd"
var checks := 0
var failures := 0
var model_script: Script

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func drop(id: String = "cargo-1", good: String = "wood", born: float = 0.0) -> Dictionary:
	return {"kind":"cargo-drop","battleId":"near-3","sourceEventId":"hit-7","shipId":"merchant","sourceShipId":"pirate","goodId":good,"quantity":5,"nativeTick":120,"eventTime":1.5,"nativeTime":2.0,"campaignTime":born,"originPose":{"position":{"x":0.0,"z":0.0},"heading":0.0,"speed":0.0},"impactPosition":{"x":2.0,"y":3.0,"z":0.0},"hasImpact":true,"originKind":"event-position","dropId":id,"policy":"grain-first-5-v1"}

func make_model(options: Dictionary = {}):
	var model = model_script.new()
	check(model.configure(func(_x: float, _z: float, _time: float) -> float: return 0.0, options), "flat-water model configures")
	return model

func find_lot(model, id: String) -> Dictionary:
	for item: Dictionary in model.snapshot():
		if item.dropId == id:
			return item
	return {}

func _run() -> void:
	if not check(ResourceLoader.exists(MODEL_PATH), "cargo drift model exists"):
		_finish()
		return
	model_script = load(MODEL_PATH)
	if not check(model_script != null, "cargo drift model loads"):
		_finish()
		return
	var model = make_model()
	var source := drop()
	var source_copy := source.duplicate(true)
	check(model.add_drop(source, 0.0).ok, "committed drop accepted")
	model.advance(0.0, 100.0, {})
	var initial := find_lot(model, "cargo-1")
	check(initial.phase == "airborne" and initial.position == [2.0,3.0,0.0], "initial visual uses actual impact position")
	model.advance(0.25, 100.25, {})
	var airborne := find_lot(model, "cargo-1")
	check(airborne.phase == "airborne" and absf(airborne.position[0]-2.625)<0.000001 and absf(airborne.position[1]-3.1934375)<0.000001, "airborne follows outward launch and analytical gravity")
	model.advance(1.5, 101.5, {})
	var floating := find_lot(model, "cargo-1")
	check(floating.phase == "floating" and floating.position[1] < 0.0, "real sea crossing produces immersed floating state")
	check(floating.goodId == "wood" and floating.quantity == 5 and floating.shipId == "merchant" and floating.sourceEventId == "hit-7", "rendered lot retains real source and economic quantity")
	var splashes: Array = model.drain_splashes()
	check(splashes.size() == 1 and splashes[0].id == "cargo-1:water" and splashes[0].time >= 100.0 and splashes[0].time <= 101.5, "one water-entry splash uses visual sea clock")
	check(model.drain_splashes().is_empty(), "drain never repeats same splash")
	var paused: Array = model.snapshot()
	model.advance(1.5, 101.5, {})
	check(model.snapshot() == paused and model.drain_splashes().is_empty(), "repeated accepted time freezes pose and births")
	check(not model.add_drop(source, 1.5).ok, "duplicate receipt rejected")
	model.advance(38.5, 138.5, {})
	check(absf(find_lot(model,"cargo-1").alpha-0.5)<0.000001, "last three campaign seconds fade without duplicate lifetime extension")
	model.advance(40.0, 140.0, {})
	check(model.snapshot().is_empty(), "lot expires at original birth plus lifetime")
	check(not model.add_drop(source, 40.0).ok and model.diagnostics().seen == 0, "expired replay cannot rebirth and dedup cache expires")
	check(source == source_copy, "motion never changes committed receipt or cargo quantity")
	var future_model = make_model()
	check(not future_model.add_drop(drop("future","grain",5.0),4.0).ok and future_model.diagnostics().seen == 0, "future receipt rejected without consuming ID")
	check(future_model.add_drop(drop("future","grain",5.0),5.0).ok, "same future ID can be accepted when its time arrives")
	var malformed := drop("bad")
	malformed.hasImpact = false
	malformed.originKind = "vessel-pose"
	check(not future_model.add_drop(malformed,5.0).ok, "vessel-centre fallback never fabricates a visual drop")
	for invalid in [NAN,INF,true,"3",null]:
		malformed = drop("bad-impact")
		malformed.impactPosition.y = invalid
		check(not future_model.add_drop(malformed,5.0).ok, "invalid impact coordinate rejected")
	for field: String in ["dropId","sourceEventId","shipId","sourceShipId","battleId"]:
		malformed = drop("bad-identity")
		malformed[field] = ""
		check(not future_model.add_drop(malformed,5.0).ok, "missing source identity rejected: " + field)
	for quantity in [-1,0,0.5,NAN,true]:
		malformed = drop("bad-quantity")
		malformed.quantity = quantity
		check(not future_model.add_drop(malformed,5.0).ok, "invalid quantity rejected")
	malformed = drop("unknown","unknown")
	check(not future_model.add_drop(malformed,5.0).ok, "unknown goods cannot create props")
	var capacity = make_model({"max_lots":2,"lifetime":4.0})
	check(capacity.add_drop(drop("a"),0.0).ok and capacity.add_drop(drop("b"),0.0).ok, "configured lot capacity accepts first two")
	check(not capacity.add_drop(drop("c"),0.0).ok and capacity.diagnostics().lots == 2 and capacity.diagnostics().seen == 2, "full pool refuses new visual without evicting committed display")
	capacity.advance(4.0,4.0,{})
	check(capacity.diagnostics().lots == 0 and capacity.diagnostics().seen == 0, "expired lots and dedup entries are bounded together")
	for index in 25:
		var at := 5.0 + index*5.0
		capacity.add_drop(drop("batch-"+str(index),"wood",at),at)
		capacity.advance(at+4.0,at+4.0,{})
	check(capacity.diagnostics().lots == 0 and capacity.diagnostics().seen == 0 and capacity.diagnostics().queued_splashes <= 2, "long runs bound active state, dedup cache and undrained splash queue")
	var wind := {"direction":{"x":1.0,"y":0.0},"speed":10.0}
	var calm = make_model()
	var windy = make_model()
	calm.add_drop(drop("wind"),0.0)
	windy.add_drop(drop("wind"),0.0)
	calm.advance(2.0,2.0,{})
	windy.advance(2.0,2.0,wind)
	var calm_start := find_lot(calm,"wind")
	var wind_start := find_lot(windy,"wind")
	calm.advance(7.0,7.0,{})
	windy.advance(7.0,7.0,wind)
	var wind_end := find_lot(windy,"wind")
	check(absf(wind_end.position[0]-wind_start.position[0]+1.0)<0.00001 and absf(find_lot(calm,"wind").position[0]-calm_start.position[0])<0.00001, "world-space float drifts opposite FROM wind at 0.02 speed")
	var late = make_model()
	late.add_drop(drop("wind"),7.0)
	late.advance(7.0,7.0,wind)
	check(late.snapshot() == windy.snapshot(), "late reconstruction matches same constant-wind accepted timeline")
	var detached: Array = windy.snapshot()
	detached[0].position[0] = 999.0
	check(find_lot(windy,"wind").position[0] != 999.0, "snapshot arrays do not alias live model state")
	var moving = make_model()
	var moving_drop := drop("moving")
	moving_drop.originPose.speed = 4.0
	moving.add_drop(moving_drop,0.0)
	moving_drop.originPose.position.x = 9000.0
	moving_drop.impactPosition.x = 9000.0
	moving.advance(0.25,0.25,{})
	check(absf(find_lot(moving,"moving").position[0]-3.625)<0.000001, "launch inherits heading speed and detached source never follows ship edits")
	var sea = model_script.new()
	check(sea.configure(func(_x:float,_z:float,t:float)->float:return sin(t)*0.1), "time-varying sea configures")
	sea.add_drop(drop("sea"),0.0)
	sea.advance(2.0,102.0,{})
	var sea_before := find_lot(sea,"sea")
	sea.advance(2.0,102.5,{})
	var sea_after := find_lot(sea,"sea")
	check(absf((sea_after.position[1]-sea_before.position[1])-(sin(102.5)-sin(102.0))*0.1)<0.000001 and sea_after.age == sea_before.age and sea_after.position[0] == sea_before.position[0], "business age freezes while supplied visual sea phase can refresh height")
	var water_control := {"invalid":false}
	var recover = model_script.new()
	check(recover.configure(func(_x:float,_z:float,_t:float)->float:return NAN if water_control.invalid else 0.0), "guarded sea configures")
	recover.add_drop(drop("recover"),0.0)
	recover.advance(2.0,2.0,{})
	var last_valid: Array = recover.snapshot()
	water_control.invalid = true
	recover.advance(2.5,2.5,{})
	check(recover.snapshot() == last_valid and recover.diagnostics().invalid_water_samples > 0, "nonfinite water never contaminates last finite render state")
	water_control.invalid = false
	recover.advance(3.0,3.0,{})
	check(find_lot(recover,"recover").age == 3.0, "finite water recovery resumes accepted trajectory")
	var wind_reference = make_model()
	var wind_interrupted = model_script.new()
	var wind_water := {"invalid":false}
	check(wind_interrupted.configure(func(_x:float,_z:float,_t:float)->float:return NAN if wind_water.invalid else 0.0), "wind-change recovery model configures")
	wind_reference.add_drop(drop("wind-recovery"),0.0)
	wind_interrupted.add_drop(drop("wind-recovery"),0.0)
	var from_positive_x := {"direction":{"x":1.0,"y":0.0},"speed":10.0}
	var from_negative_x := {"direction":{"x":-1.0,"y":0.0},"speed":10.0}
	wind_reference.advance(2.0,2.0,from_positive_x)
	wind_interrupted.advance(2.0,2.0,from_positive_x)
	var last_wind_render: Array = wind_interrupted.snapshot()
	wind_water.invalid = true
	wind_reference.advance(3.0,3.0,from_negative_x)
	wind_interrupted.advance(3.0,3.0,from_negative_x)
	check(wind_interrupted.snapshot() == last_wind_render, "water sample failure freezes finite visual output during accepted wind change")
	wind_water.invalid = false
	wind_reference.advance(4.0,4.0,from_negative_x)
	wind_interrupted.advance(4.0,4.0,from_negative_x)
	check(wind_interrupted.snapshot() == wind_reference.snapshot(), "water sample recovery retains all accepted wind segments")
	var heavy = make_model()
	for good: String in ["wood","iron","porcelain"]:
		heavy.add_drop(drop(good,good),0.0)
	heavy.advance(6.0,6.0,{})
	check(find_lot(heavy,"iron").phase == "sinking" and find_lot(heavy,"iron").position[1] < find_lot(heavy,"wood").position[1]-1.0 and find_lot(heavy,"wood").phase == "floating" and find_lot(heavy,"porcelain").phase == "floating", "iron packaging sinks after short float while wood and porcelain remain afloat")
	heavy.advance(12.0,12.0,{})
	check(find_lot(heavy,"porcelain").phase == "sinking" and find_lot(heavy,"wood").phase == "floating", "porcelain packaging sinks after longer float")
	heavy.advance(1.0,1.0,{})
	check(heavy.snapshot().is_empty() and heavy.diagnostics().seen == 0 and heavy.drain_splashes().is_empty(), "accepted clock rewind clears prior timeline")
	check(heavy.add_drop(drop("wood"),1.0).ok, "reset timeline may explicitly rebuild same receipt")
	heavy.reset()
	check(heavy.snapshot().is_empty() and heavy.diagnostics().seen == 0, "explicit epoch reset clears all visual ownership")
	heavy.dispose()
	check(not heavy.add_drop(drop(),0.0).ok, "disposed model cannot accept more receipts")
	for owned in [model,future_model,capacity,calm,windy,late,moving,sea,recover,wind_reference,wind_interrupted]:
		owned.dispose()
	_scatter_contract()
	_finish()

func _scatter_contract() -> void:
	var baseline = make_model()
	var zero = make_model({"launch_spread":0.0})
	baseline.add_drop(drop("scatter-a"),0.0)
	zero.add_drop(drop("scatter-a"),0.0)
	baseline.advance(0.75,0.75,{})
	zero.advance(0.75,0.75,{})
	check(zero.snapshot() == baseline.snapshot(), "explicit zero spread preserves analytical baseline exactly")
	var first = make_model({"launch_spread":0.8})
	var reordered = make_model({"launch_spread":0.8})
	var a := drop("scatter-a")
	var b := drop("scatter-b")
	b.sourceEventId = "hit-8"
	var a_before := a.duplicate(true)
	var b_before := b.duplicate(true)
	first.add_drop(a,0.0)
	first.add_drop(b,0.0)
	reordered.add_drop(b,0.0)
	reordered.add_drop(a,0.0)
	first.advance(0.0,0.0,{})
	check(find_lot(first,"scatter-a").position == [2.0,3.0,0.0] and find_lot(first,"scatter-b").position == [2.0,3.0,0.0], "scatter changes velocity without fabricating different birth positions")
	first.advance(0.75,0.75,{})
	reordered.advance(0.75,0.75,{})
	var first_a := find_lot(first,"scatter-a")
	var first_b := find_lot(first,"scatter-b")
	check(absf(float(first_a.position[2])-float(first_b.position[2])) > 0.05, "distinct receipt IDs separate along outward tangent with spread enabled")
	check(absf(float(first_a.rotation[1])-float(first_b.rotation[1])) > 0.02, "distinct receipt IDs gain a small independent spin")
	check(first_a == find_lot(reordered,"scatter-a") and first_b == find_lot(reordered,"scatter-b"), "scatter depends on stable receipt ID rather than insertion order")
	check(a == a_before and b == b_before and first_a.quantity == 5 and first_b.quantity == 5 and first_a.sourceEventId == "hit-7" and first_b.sourceEventId == "hit-8", "scatter preserves committed quantities, source identities and caller data")
	var late = make_model({"launch_spread":0.8})
	late.add_drop(a,0.75)
	late.advance(0.75,0.75,{})
	check(find_lot(late,"scatter-a") == first_a, "late replay reconstructs same ID scatter exactly")
	for invalid in [-0.1,NAN,INF,true]:
		var rejected = model_script.new()
		check(not rejected.configure(func(_x:float,_z:float,_t:float)->float:return 0.0,{"launch_spread":invalid}), "invalid scatter parameter rejected")
		rejected.dispose()
	for owned in [baseline,zero,first,reordered,late]:
		owned.dispose()

func _finish() -> void:
	print("CARGO_DRIFT_TEST_COMPLETE checks=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
