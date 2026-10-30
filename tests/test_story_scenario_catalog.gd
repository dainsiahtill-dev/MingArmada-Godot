extends SceneTree
## Scenario content contract: 30 stages bind 1:1 to catalog objectives, and the
## strict loader refuses any drift, unknown world reference or forged binding.

const SCENARIOS_PATH := "res://game/domain/story_campaign/scenarios.gd"
const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
var assertions: int = 0
var failures: int = 0
var scenarios_script: GDScript
var catalog_script: GDScript

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	scenarios_script = load(SCENARIOS_PATH) as GDScript
	catalog_script = load(CATALOG_PATH) as GDScript
	if not check(scenarios_script != null and catalog_script != null, "scenario and catalog modules load"):
		_finish()
		return
	_test_geography()
	_test_stage_binding()
	_test_pins_and_opening()
	_test_mutation_rejections()
	_finish()

func _finish() -> void:
	print("STORY_SCENARIO_CATALOG assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)

func _content() -> Dictionary:
	var loaded: Dictionary = scenarios_script.call("load_content")
	check(loaded.get("ok", false), "scenario content loads and validates: " + str(loaded.get("reason", "")))
	return loaded.get("data", {})

func _clone(content: Dictionary) -> Dictionary:
	return content.duplicate(true)

func _test_geography() -> void:
	var geo: Dictionary = scenarios_script.call("geography")
	check(geo.get("ok", false), "geography loads and validates: " + str(geo.get("reason", "")))
	var ports: Array = geo.data.ports
	check(ports.size() == 17, "geography declares the schematic port set")
	var seen := {}
	for entry: Dictionary in ports:
		check(not seen.has(entry.id), "geography port id unique: " + str(entry.id))
		seen[entry.id] = true
		check(entry.prices.size() == 6 and entry.stock.size() == 6, "geography port economy complete: " + str(entry.id))
	check(str(geo.data.scaleNote).contains("示意"), "geography keeps the schematic scale disclaimer")

func _test_stage_binding() -> void:
	var content := _content()
	if content.is_empty():
		return
	var stages: Array = catalog_script.call("stages")
	check(stages.size() == 30 and content.stages.size() == 30, "scenario covers all thirty catalog stages")
	for stage: Dictionary in stages:
		var entry: Dictionary = content.stages.get(stage.id, {})
		check(not entry.is_empty(), "scenario entry exists for " + str(stage.id))
		check(entry.get("mode", "") == stage.mode, "scenario mode matches catalog for " + str(stage.id))
		var settlements: Dictionary = entry.get("settlements", {})
		check(settlements.size() == stage.objectives.size(), "settlement count matches objectives for " + str(stage.id))
		for objective: Dictionary in stage.objectives:
			var settlement: Dictionary = settlements.get(objective.id, {})
			check(settlement.get("kind", "") == objective.kind, "settlement kind matches objective for " + str(stage.id) + "/" + str(objective.id))

func _test_pins_and_opening() -> void:
	var content := _content()
	if content.is_empty():
		return
	var ch09: Dictionary = content.stages["CH-09-S1"]
	var envoy_bound: bool = false
	for entity: Dictionary in ch09.entities:
		if entity.id == "ryukyu-envoy-vessel":
			envoy_bound = true
	check(envoy_bound, "CH-09 scenario materializes the Ryukyu envoy vessel")
	check(ch09.settlements["ch09-escort"].targetId == "ryukyu-envoy-vessel", "CH-09 escort binds the envoy vessel")
	var t10: Dictionary = content.stages["T10"]
	check(t10.settlements["t10-terms"].has("agreementId") and t10.settlements["t10-evacuation"].has("manifestId") and t10.settlements["t10-handover"].has("handoverId"), "T10 binds terms, evacuation and handover records")
	var ch02: Dictionary = content.stages["CH-02-S1"]
	check(ch02.misstepPolicy.wrongTargetId == "ch02-decoy-merchant", "CH-02 misstep policy names the decoy target")
	var opening: Dictionary = scenarios_script.call("opening")
	check(not opening.is_empty() and opening.homePort == "xiamen", "session opening assembles from geography")
	check(opening.ports.size() == 17 and opening.ports[0].has("stockCaps") and opening.ports[0].has("prices"), "session opening ports carry economics")
	check(opening.fleet[0].id == "player" and opening.fleet[0].cargo.grain == 30, "session opening fleet matches campaign start")

func _test_mutation_rejections() -> void:
	var content := _content()
	if content.is_empty():
		return
	var cases := []
	var dropped := _clone(content)
	dropped.stages.erase("T10")
	cases.append(["missing stage refused", dropped])
	var extra := _clone(content)
	extra.stages["T99"] = content.stages["T10"].duplicate(true)
	cases.append(["unknown stage refused", extra])
	var wrong_kind := _clone(content)
	wrong_kind.stages["CH-01-S1"].settlements["ch01-deliver"].kind = "capture"
	cases.append(["wrong settlement kind refused", wrong_kind])
	var renamed := _clone(content)
	renamed.stages["CH-01-S1"].settlements = {"ghost-objective": {"kind": "deliver", "portId": "kinmen", "good": "grain", "quantity": 30}}
	cases.append(["renamed objective refused", renamed])
	var ghost_port := _clone(content)
	ghost_port.stages["CH-01-S1"].settlements["ch01-deliver"].portId = "atlantis"
	cases.append(["unknown port refused", ghost_port])
	var wrong_mode := _clone(content)
	wrong_mode.stages["CH-01-S1"].mode = "trade"
	cases.append(["wrong mode refused", wrong_mode])
	var dupe_entity := _clone(content)
	dupe_entity.stages["CH-02-S1"].entities.append(content.stages["CH-02-S1"].entities[0].duplicate(true))
	cases.append(["duplicate entity refused", dupe_entity])
	var broken_setup := _clone(content)
	broken_setup.stages["CH-02-S1"].entities[0].setup.erase("hull")
	cases.append(["ship setup without hull refused", broken_setup])
	var ghost_target := _clone(content)
	ghost_target.stages["CH-07-S1"].settlements["ch07-protect"].targetIds = ["ghost-ship"]
	cases.append(["ghost protect target refused", ghost_target])
	var extra_field := _clone(content)
	extra_field.stages["CH-12-S1"].settlements["ch12-handoff"] = {"kind": "handoff", "reward": 500}
	cases.append(["handoff extra field refused", extra_field])
	var extra_stockpile := _clone(content)
	extra_stockpile.stages["CH-20-S1"].settlements["ch20-grain"] = {"kind": "stockpile", "good": "grain", "quantity": 160, "bonus": 1}
	cases.append(["stockpile extra field refused", extra_stockpile])
	for entry: Array in cases:
		var result: Dictionary = scenarios_script.call("validate", entry[1])
		check(not result.get("ok", true), str(entry[0]))
	check(scenarios_script.call("validate", content).get("ok", false), "pristine content still validates after mutations")
	var first: Dictionary = scenarios_script.call("scenario", "CH-01-S1")
	first.settlements["ch01-deliver"].quantity = 9999
	var second: Dictionary = scenarios_script.call("scenario", "CH-01-S1")
	check(int(second.settlements["ch01-deliver"].quantity) == 30, "scenario reads return detached copies")
