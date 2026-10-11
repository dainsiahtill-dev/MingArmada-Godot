extends SceneTree

const Assist = preload("res://game/runtime/manual_sailing_assist.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void:
	var assist := Assist.new()
	var ship := {"kind":"fuchuan", "visual":{"heading":0.0,"velocity":{"x":0.0,"z":0.0}}}
	var wind := {"direction":{"x":1.0,"y":0.0},"speed":12.0}
	var input := {"forward":true,"backward":false,"turn":0.0,"turnIntent":0.0,"sailIntent":0.8,"autoTrim":true,"manualTrim":false}
	var calls := {"count":0}
	var heading := func() -> Dictionary: calls.count += 1; return {"ok":true,"heading":1.2}
	for i in 59: assist.advance(1.0/60,ship,wind,input,heading)
	check(not assist.active() and calls.count == 0,"recovery does not trigger before one accepted second")
	assist.advance(1.0/60,ship,wind,input,heading)
	check(assist.active() and calls.count == 1,"native route check runs once after actual stall")
	var controls: Dictionary = assist.controls(ship,input)
	check(controls.recovery and controls.turnIntent == 1.0 and controls.sailDeployment == 0.0,"recovery furls sails and turns toward validated heading")
	ship.visual.heading = 1.2
	assist.advance(1.0,ship,wind,input,heading)
	check(absf(assist.controls(ship,input).sailDeployment-0.4)<1e-12,"sails gradually restore after escaping wind cone")
	assist.advance(1.0,ship,wind,input,heading)
	check(not assist.active(),"two accepted seconds finish sail restoration")
	ship.visual.heading = 0.0
	assist.advance(2.0,ship,wind,input,heading)
	check(calls.count == 1,"held forward cannot restart recovery without a fresh press")
	assist.release_forward()
	assist.advance(1.0,ship,wind,input,heading)
	check(calls.count == 2 and assist.active(),"fresh forward intent permits a new validated recovery")
	assist.advance(18.0,ship,wind,input,heading)
	check(assist.status().phase == "blocked" and not assist.active(),"bounded recovery timeout prevents indefinite automated turns")
	assist.release_forward()
	input.turn = 1.0
	assist.advance(1.0,ship,wind,input,heading)
	check(assist.status().phase == "turning" and not assist.active(),"manual turn overrides assistance")
	input.turn = 0.0; input.backward = true; input.sailIntent = 0.04
	assist.advance(1.0,ship,wind,input,heading)
	check(assist.controls(ship,input).braking and assist.status().phase == "braking","braking only starts after sails furl")
	var before: Dictionary = assist.status()
	assist.advance(NAN,ship,wind,input,heading)
	check(before == assist.status(),"invalid elapsed time has no side effect")
	print("MANUAL_SAILING_ASSIST_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
