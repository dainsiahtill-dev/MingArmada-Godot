extends SceneTree

const Model = preload("res://modules/scene_engine/fx/reference_particle_model.gd")
var checks := 0
var failures := 0

func _init() -> void:
	call_deferred("_run")

func _check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL reference particle model: " + message)

func _run() -> void:
	var group := {"interpolation": 1, "keys": [{"time": 0.0, "value": 0.0}, {"time": 0.1, "value": 20.0}, {"time": 0.2, "value": 0.0}]}
	_check(is_equal_approx(Model.scalar_key(group, 0.05), 10.0), "linear key sample")
	_check(is_equal_approx(Model.rate_integral(group, 0.0, 0.2), 2.0), "analytic triangular birth rate")
	var active := [{"time": 0.0, "value": 1}, {"time": 0.001, "value": 0}]
	var narrow := Model.birth_schedule({"fields": {"frequency": 1.0, "phase": 0.0, "start_time": 0.0, "stop_time": 1.0}, "data": {"fields": {"float_keys": {"interpolation": 1, "keys": [{"time": 0.0, "value": 3000.0}]}, "visibility_keys": active}}}, 1.0, 64)
	_check(narrow.size() == 3, "three births in a one-millisecond authored active window")
	for birth in narrow:
		_check(birth > 0.0 and birth < 0.001, "narrow births never quantized to frame time")
	_check(is_equal_approx(Model.grow_fade(0.25, 2.0, {"grow_time": 0.5, "fade_time": 0.5, "grow_generation": 0, "fade_generation": 0}), 0.5), "native GrowFade grow")
	_check(is_equal_approx(Model.grow_fade(1.75, 2.0, {"grow_time": 0.5, "fade_time": 0.5, "grow_generation": 0, "fade_generation": 0}), 0.5), "native GrowFade fade")
	var a = Model.new()
	var b = Model.new()
	_check(a.configure(), "load complete source definitions")
	_check(b.configure(), "independent model")
	_check(not a.spawn("fx_cannon_fire_01", "nan", 0.0, Vector3.ZERO, Basis.IDENTITY, 1, {"scale": NAN}), "nonfinite override rejected")
	_check(not a.spawn("fx_cannon_fire_01", "bad-type", 0.0, Vector3.ZERO, Basis.IDENTITY, 1, {"source_origin": "text"}), "invalid transform type rejected")
	_check(not a.set_time(NAN), "nonfinite accepted clock rejected")
	_check(not a.set_time(1.0, Vector3(INF, 0, 0)), "nonfinite wind rejected")
	_check(a.diagnostics().accepted_time == 0.0 and a.diagnostics().effects == 0, "invalid input leaves state atomic")
	_check(Model.birth_schedule({"fields": {"start_time": 2.0, "stop_time": 1.0}}, 1.0, 64).is_empty(), "invalid controller interval rejected")
	var names := ["fx_cannon_fire_01", "fx_cannon_fire_02", "fx_cannon_fire_03", "fx_cannon_hit_impact01", "fx_cannon_hit_blowout01", "fx_ship_destruction_explosion", "fx_burning_smoke_low_damage", "fx_burning_smoke_medium_damage", "fx_burning_smoke_high_damage", "fx_burning_smoke_sinking"]
	for i in names.size():
		_check(a.spawn(names[i], "event%d" % i, 0.0, Vector3(5, 2, 7), Basis.IDENTITY, 123 + i), "full source effect " + names[i])
	_check(not a.spawn(names[0], "event0", 0.0, Vector3.ZERO, Basis.IDENTITY, 123), "dedup event ID")
	a.set_time(1.0, Vector3(2, 0, 0))
	_check(a.diagnostics().source_systems == 276 and a.diagnostics().alive_particles > 0, "complete data and live particles")
	_check(a.diagnostics().effect_layers["fx_cannon_fire_01"] == 11, "all eleven source cannon-fire layers")
	_check(b.spawn(names[0], "event0", 0.0, Vector3(5, 2, 7), Basis.IDENTITY, 123), "deterministic match event")
	for t in [0.01, 0.02, 0.2, 0.5, 1.0]:
		b.set_time(t, Vector3(2, 0, 0))
	var aa: Array = a.snapshot().filter(func(p: Dictionary) -> bool: return p.event_id == "event0")
	_check(aa == b.snapshot(), "constant wind/frame subdivision produces identical particle state")
	var late = Model.new()
	late.configure()
	late.set_time(1.0, Vector3(2, 0, 0))
	late.spawn(names[0], "event0", 0.0, Vector3(5, 2, 7), Basis.IDENTITY, 123)
	late.set_time(1.0, Vector3(2, 0, 0))
	_check(late.snapshot() == aa, "late event accepted at its actual age")
	var persistent = Model.new()
	persistent.configure()
	persistent.spawn("fx_burning_smoke_low_damage", "smoke", 0.0, Vector3.ZERO, Basis.IDENTITY, 52)
	persistent.set_emitter_transform("smoke", Vector3(100, 0, 0), Basis.IDENTITY, 2.0)
	persistent.set_time(2.0)
	var old: Array = persistent.snapshot()
	persistent.set_emitter_transform("smoke", Vector3(200, 0, 0), Basis.IDENTITY, 2.1)
	persistent.set_time(2.1)
	var now := {}
	for p in persistent.snapshot():
		now[p.id] = p
	var compared := 0
	for p in old:
		if now.has(p.id):
			_check(absf(now[p.id].position.x - p.position.x) < 20.0, "world-space smoke does not teleport with ship")
			compared += 1
	_check(compared > 0, "world-space comparison exercised")
	persistent.stop("smoke")
	persistent.set_time(20.0)
	_check(persistent.snapshot().is_empty(), "stopped smoke ages out")
	a.set_time(0.1)
	_check(a.snapshot().is_empty() and a.diagnostics().rewinds == 1, "rewind clears effects and dedup ledger")
	_check(a.spawn(names[0], "event0", 0.1, Vector3.ZERO, Basis.IDENTITY, 123), "ID reusable after rewind")
	a.dispose()
	_check(not a.spawn(names[0], "disposed", 0.1, Vector3.ZERO, Basis.IDENTITY, 123), "disposed model refuses events")
	print(JSON.stringify({"test": "reference_particle_model", "checks": checks, "failures": failures}))
	print("REFERENCE_PARTICLE_MODEL_TESTS assertions=",checks," failures=",failures)
	quit(0 if failures == 0 else 1)
