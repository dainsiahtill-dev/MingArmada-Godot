extends SceneTree
## Naval category: live native hull transitions settle neutralize/protect
## witnesses, with re-verification and an honest failure before the screen is
## cleared. Live gunnery loops are native-tested; battle damage here is applied
## to the live native roster and re-verified at settle time.

const Support = preload("res://tests/story_walkthrough_support.gd")
var assertions: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	var runtime: RefCounted = Support.setup("story-naval")
	check(Support.advance_to(runtime, 6), "playthrough reaches CH-07 with real settlements")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-07 begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "CH-07 transitions to Quanzhou")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "fleet deploys to the screen")
	var early: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(early.get("ok", false) and str(early.get("outcome", "")) == "partial", "protect-only partial while the screen still floats")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry rebinds the battle")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	check(runtime.call("command", {"type": "transition"}).get("ok", false), "second attempt transitions")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "second attempt deploys")
	Support.damage(runtime, "ch07-enemy-screen")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and str(settled.get("outcome", "")) == "success", "neutralize plus protect settle together")
	check(settled.witnesses["ch07-protect"].ok == true, "protect witness re-verifies the transport alive now")
	_finish()

func _finish() -> void:
	print("STORY_NAVAL_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
