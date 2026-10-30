extends SceneTree
## Sailing category: real native sail to the destination port, real dock gate,
## real delivery settlement, real stage settle + failure/retry through the
## story runtime. No fabricated facts.

const RUNTIME_PATH := "res://game/runtime/story_runtime.gd"
var assertions: int = 0
var failures: int = 0
var runtime_script: GDScript

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	runtime_script = load(RUNTIME_PATH) as GDScript
	if not check(runtime_script != null, "story runtime loads"):
		_finish()
		return
	_test_real_sail_and_delivery()
	_test_dock_gate_refusal()
	_finish()

func _finish() -> void:
	print("STORY_SAILING_ADAPTER assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _runtime() -> RefCounted:
	var runtime: RefCounted = runtime_script.new()
	# Real speed and real waves prove the sailing; ambient traffic has its own
	# test and would eat the runner budget here.
	runtime.fixture_no_traffic = true
	var configured: Dictionary = runtime.call("configure", func(_x: float, _z: float) -> float: return -24.0, {"seed": 1661, "runId": "story-sailing"})
	check(configured.get("ok", false), "story runtime configures: " + str(configured.get("reason", "")))
	return runtime

func _flagship_position(runtime: RefCounted) -> Dictionary:
	var native: Dictionary = runtime.call("native_snapshot")
	for entry: Dictionary in native.ships:
		if str(entry.id) == "player":
			return entry.visual.position
	return {}

func _distance(a: Dictionary, b: Dictionary) -> float:
	return sqrt(pow(float(a.x) - float(b.x), 2) + pow(float(a.z) - float(b.z), 2))

func _sail_to(runtime: RefCounted, target: Dictionary, limit: int) -> int:
	runtime.call("command", {"type": "set-sails", "value": 1.0})
	runtime.call("command", {"type": "navigate", "point": {"x": float(target.x), "z": float(target.z)}})
	var ticks := 0
	while ticks < limit:
		runtime.call("step_fixed")
		ticks += 1
		if ticks % 8 == 0 and _distance(_flagship_position(runtime), target) <= 55.0:
			break
	return ticks

func _test_real_sail_and_delivery() -> void:
	var runtime := _runtime()
	var snapshot: Dictionary = runtime.call("snapshot")
	check(snapshot.world.currentPortId == "xiamen", "opening starts docked at Xiamen")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "CH-01 begins against the real progress contract")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "real depart from Xiamen")
	var kinmen: Dictionary = snapshot.world.ports.kinmen
	var ticks: int = _sail_to(runtime, kinmen, 20000)
	check(ticks < 20000, "real native sail reaches Kinmen anchorage in %d ticks" % ticks)
	check(runtime.call("command", {"type": "dock", "portId": "kinmen"}).get("ok", false), "real dock gate accepts arrival")
	check(runtime.call("command", {"type": "deliver", "good": "grain", "quantity": 30}).get("ok", false), "real delivery settles cargo at Kinmen")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and settled.get("outcome", "") == "success", "CH-01 settles success from real action: " + str(settled.get("reason", settled.get("outcome", ""))))
	var state: Dictionary = runtime.call("snapshot").progress
	check(state.receipts.size() == 1 and state.receipts[0].outcome == "success", "stage receipt recorded once")
	check(runtime.call("command", {"type": "continue-story"}).get("ok", false), "continue to CH-02")
	print("sail ticks: ", ticks)

func _test_dock_gate_refusal() -> void:
	var runtime := _runtime()
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "retry case begins CH-01")
	check(runtime.call("command", {"type": "depart"}).get("ok", false), "retry case departs")
	var kinmen: Dictionary = runtime.call("snapshot").world.ports.kinmen
	runtime.call("command", {"type": "navigate", "point": {"x": float(kinmen.x) + 200.0, "z": float(kinmen.z)}})
	for tick in 400:
		runtime.call("step_fixed")
	var far: Dictionary = runtime.call("command", {"type": "dock", "portId": "kinmen"})
	check(not far.get("ok", true), "dock refused beyond the anchorage radius")
	var settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(settled.get("ok", false) and settled.get("outcome", "") == "failure", "unfinished delivery settles failure")
	check(runtime.call("command", {"type": "retry-stage"}).get("ok", false), "retry keeps the world and rebinds CH-01")
	var state: Dictionary = runtime.call("snapshot").progress
	check(int(state.attempt) == 2, "second attempt recorded")
	check(runtime.call("command", {"type": "begin-stage"}).get("ok", false), "second attempt begins")
	var retry_settled: Dictionary = runtime.call("command", {"type": "settle-stage"})
	check(retry_settled.get("ok", false) and retry_settled.get("outcome", "") == "failure", "retry attempt also settles honestly without action")
