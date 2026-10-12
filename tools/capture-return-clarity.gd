extends "res://tools/capture-opening-return.gd"
## The reviewed strict Continue journey plus visible wrong-port repayment hints.
const Paths = preload("res://tools/qa-journey-paths.gd")

func run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	if not "--preflight-only" in args:
		var outputs := args.filter(func(arg: String): return arg.begins_with("--output="))
		if not check(outputs.size() == 1, "one explicit output for current return capture"): await finish(); return
		var target: String = outputs[0].trim_prefix("--output=")
		if not check(Paths.output(["--output=" + target + "/capture-result.json"]).ok and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(target)), "fresh return output components and links verified"): await finish(); return
	await super.run()

func current_source_hashes() -> Dictionary:
	var result := super.current_source_hashes()
	for path: String in ["tools/capture-return-clarity.gd", "tools/qa-journey-paths.gd", "modules/naval_simulation/navigation/approach_clearance.gd", "modules/naval_simulation/navigation/wet_route_egress.gd", "game/domain/mingqi/second_voyage_aftermath.gd"]:
		result[path] = FileAccess.get_sha256("res://" + path)
	return result

func capture(label: String, dimensions: Vector2i) -> bool:
	if not await super.capture(label, dimensions): return false
	if label.begins_with("steward-consequence-"):
		var repayment: Button = await focus_control("repay_debt")
		if not repayment: return false
		var reason: Label = await focus_control("repay_debt_reason")
		if not reason: return false
		if not check(repayment.disabled and reason.visible and reason.text.contains("厦门林家商行"), "actual Kinmen repayment paragraph directs captain to Xiamen"): return false
		if not await super.capture("xiamen-repayment-hint-" + str(dimensions.x), dimensions): return false
	return true
