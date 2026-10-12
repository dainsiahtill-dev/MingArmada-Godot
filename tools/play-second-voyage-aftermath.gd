extends "res://tools/capture-return-clarity.gd"
## Genuine second-voyage checkpoint -> native mouse choice -> disk save -> Continue.
## One branch per invocation. No injected poses, injuries, cargo or business state.
const Aftermath = preload("res://game/domain/mingqi/second_voyage_aftermath.gd")
const Continued = preload("res://tools/play-continued-voyage.gd")
var branch := ""

func current_source_hashes() -> Dictionary:
	var hashes := super.current_source_hashes()
	hashes["tools/play-second-voyage-aftermath.gd"] = FileAccess.get_sha256("res://tools/play-second-voyage-aftermath.gd")
	return hashes

func journey_failure(record: Variant) -> String:
	if not record is Dictionary: return "journey-not-object"
	if record.get("failures", -1) != 0: return "journey-has-failures"
	if record.get("actualSafeReturn") != true: return "journey-safe-return-unconfirmed"
	if record.get("terrain") != "same formal game terrain": return "journey-not-formal-terrain"
	var inventory := _inventory_reason(record)
	if not inventory.is_empty(): return inventory
	if not record.get("final") is Dictionary or not record.final.get("campaign") is Dictionary: return "journey-final-campaign-missing"
	var state: Dictionary = record.final.campaign
	if state.get("currentPortId") != "xiamen": return "journey-not-at-xiamen"
	if not record.final.get("runtime", {}).get("canSave", false): return "journey-full-fleet-save-unconfirmed"
	if not record.get("confirmedCheckpointJson") is String or record.confirmedCheckpointJson.is_empty(): return "journey-checkpoint-missing"
	var ct: Dictionary = state.get("contracts", {}).get("convoy-002", {})
	var claim: Dictionary = state.get("settlements", {}).get(str(state.get("campaignId", "")) + ":convoy-002:claim", {})
	if ct.get("status") != "settled" or claim.get("kind") != "claim-convoy" or ct.get("receiptId") != claim.get("id"): return "journey-second-claim-missing"
	var details: Dictionary = claim.get("details", {})
	if details.get("contractId") != "convoy-002" or details.get("delivered") != 20 or details.get("lost") != 0 or details.get("baseReward") != 200 or details.get("bonus") != 50: return "journey-full-on-time-claim-missing"
	if state.get("settlements", {}).has(str(state.get("campaignId", "")) + ":story:second-return"): return "journey-aftermath-already-chosen"
	var decoded := Codec.decode(record.confirmedCheckpointJson)
	if not decoded.get("ok", false) or not Codec._equal(decoded.state, state): return "journey-checkpoint-mismatch"
	return ""

func _inventory_reason(record: Dictionary) -> String:
	var hashes: Variant = record.get("sourceHashes")
	if not hashes is Dictionary or hashes.is_empty(): return "journey-source-inventory-missing"
	var required: Array = Continued.SOURCES.duplicate()
	required.append("tools/qa-journey-checkpoint.gd")
	if hashes.size() != required.size() or required.any(func(path): return not hashes.has(path)): return "journey-source-inventory-incomplete"
	for path: String in required:
		if not hashes[path] is String or hashes[path].length() != 64 or FileAccess.get_sha256("res://" + path) != hashes[path]: return "journey-source-inventory-mismatch"
	return ""

func run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	for argument: String in args:
		if argument.begins_with("--journey=") and journey_path.is_empty(): journey_path = argument.trim_prefix("--journey=")
		elif argument.begins_with("--output=") and directory.is_empty(): directory = argument.trim_prefix("--output=")
		elif argument.begins_with("--choice=") and branch.is_empty(): branch = argument.trim_prefix("--choice=")
		elif argument == "--preflight-only": preflight_only = true
		else: check(false, "unknown or duplicate aftermath argument: " + argument)
	if not check(branch in Aftermath.CHOICES, "one explicit lawful branch") or failures: await finish(); return
	var input := Paths.input_journey(args)
	if not check(input.get("ok", false), "confined immutable journey input"): await finish(); return
	journey_path = input.path
	if not check(not directory.is_empty() and Paths.output(["--output=" + directory + "/capture-result.json"]).get("ok", false) and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(directory)), "fresh confined aftermath output; no overwrite"): directory = ""; await finish(); return
	var parser := Codec.new()
	var parsed: Variant = parser._parse(FileAccess.get_file_as_string(journey_path))
	if not check(parser.error.is_empty(), "input journey passes strict full-precision JSON parser: " + parser.error): await finish(); return
	var reason := journey_failure(parsed)
	if not check(reason.is_empty(), "successful actual second voyage required: " + reason): await finish(); return
	source_record = parsed; source_campaign = parsed.final.campaign.duplicate(true)
	source_hashes = current_source_hashes()
	for path: String in source_record.get("sourceHashes", {}):
		if not check(FileAccess.get_sha256("res://" + path) == source_record.sourceHashes[path], "current-source actual second voyage: " + path): await finish(); return
	saved_json = source_record.confirmedCheckpointJson
	summary = {"choice":branch,"journeyPath":journey_path,"journeySha256":FileAccess.get_sha256(journey_path),"inputCampaignSimulationSeconds":source_campaign.simulationSeconds,"journeyFailures":0,"actualSafeReturn":true,"journeySourceHashes":source_record.sourceHashes.duplicate(true),"captureSourceHashes":source_hashes.duplicate(true),"restoration":"Byte-exact normal actual second-voyage checkpoint; normal Router validation and MainScene Continue.","scope":"Genuine captain voyage input, native mouse transactions and normal disk Save/Continue. No synthetic casualties, all-chapters, performance or human fun claim."}
	var validator := Router.new()
	var validation: Dictionary = validator._validate(saved_json, "mingqi")
	if not check(validation.get("ok", false), "normal Router full native safety: " + str(validation.get("reason", ""))): await finish(); return
	if preflight_only: await finish(); return
	if not check(DisplayServer.get_name() != "headless", "visible native GPU required"): await finish(); return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "new evidence directory"): directory = ""; await finish(); return
	output_owned = true
	var slots: Array[String] = []
	for path: String in ["user://saves/mingqi-v2.json", "user://saves/legacy-v1.json", "user://settings.json"]:
		for suffix: String in ["", ".backup", ".rollback", ".staged"]: slots.append(path + suffix)
	original_slots = file_hashes(slots)
	isolated_prefix = "user://tests/second-aftermath-" + str(OS.get_process_id())
	for suffix: String in ["-v2.json", "-v1.json", "-settings.json"]:
		for extension: String in ["", ".backup", ".rollback", ".staged"]:
			if not check(not FileAccess.file_exists(isolated_prefix + suffix + extension), "new isolated slot identity"): await finish(); return
	isolated_owned = true
	var storage := Storage.new(isolated_prefix + "-v2.json")
	if not check(storage.write_checkpoint(saved_json).get("ok", false) and FileAccess.get_file_as_string(storage.path) == saved_json, "seed and read byte-exact normal voyage checkpoint"): await finish(); return
	if not _write_exact(directory + "/input-native-save-v2.json", saved_json): await finish(); return
	summary.inputNativeSaveSha256 = FileAccess.get_sha256(directory + "/input-native-save-v2.json")
	root.unresizable = true; root.size = Vector2i(1600, 900); root.content_scale_size = root.size
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	main = packed.instantiate()
	main.router = Router.new({"mingqi_storage":storage,"legacy_storage":Storage.new(isolated_prefix + "-v1.json", Legacy.validate_save),"settings_storage":Settings.new(isolated_prefix + "-settings.json")})
	root.add_child(main); await frames(8)
	var entry: Button = main.menu.find_child("mingqi-continue", true, false)
	if not check(entry != null and not entry.disabled, "real main-menu Continue enabled"): await finish(); return
	main.menu._scroll.ensure_control_visible(entry); await frames(3); await click(entry)
	if not await resume_entry() or not preserve_material(source_campaign, scene.runtime.snapshot().campaign, "visible unchanged voyage restoration"): await finish(); return
	if not await button("nav_story"): await finish(); return
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = dimensions; root.content_scale_size = dimensions; await frames(8)
		if not await focus_control("story_bill_second-return") or not await capture("before-choice-" + str(dimensions.x), dimensions): await finish(); return
	var before: Dictionary = scene.runtime.snapshot().campaign
	if not await button("story_choice_second-return_" + branch): await finish(); return
	var after: Dictionary = scene.runtime.snapshot().campaign
	var receipt: Dictionary = after.settlements.get(after.campaignId + ":story:second-return", {})
	if not check(receipt.get("details", {}).get("choiceId") == branch and receipt.get("details", {}).get("portId") == "xiamen", "mouse choice creates actual once-only observed-port receipt"): await finish(); return
	if not check(after.captain.silver == before.captain.silver - (50 if branch == "share-proceeds" else 0) and after.debt == before.debt, "actual choice payment and unchanged debt"): await finish(); return
	summary.choiceReceipt = receipt.duplicate(true); summary.beforeChoice = before; summary.afterChoice = after
	for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
		root.size = dimensions; root.content_scale_size = dimensions; await frames(8)
		if not await focus_control("story_outcome_second-return") or not await capture("after-choice-" + str(dimensions.x), dimensions): await finish(); return
	if branch == "return-xiamen":
		var quantity: SpinBox = await focus_control("debt_quantity")
		if not check(quantity != null and quantity.editable, "real independent repayment input available"): await finish(); return
		var line := quantity.get_line_edit(); await click(line)
		var select_all := InputEventKey.new(); select_all.keycode = KEY_A; select_all.ctrl_pressed = true; select_all.pressed = true
		Input.parse_input_event(select_all); await process_frame
		select_all = select_all.duplicate(); select_all.pressed = false; Input.parse_input_event(select_all); await process_frame
		for digit: String in ["1", "0", "0"]:
			var key := InputEventKey.new(); key.keycode = digit.unicode_at(0); key.unicode = digit.unicode_at(0); key.pressed = true
			Input.parse_input_event(key); await process_frame
			key = key.duplicate(); key.pressed = false; Input.parse_input_event(key); await process_frame
		if not check(line.text == "100", "actual native keyboard enters100"): await finish(); return
		if not await button("repay_debt"): await finish(); return
		var paid: Dictionary = scene.runtime.snapshot().campaign
		if not check(paid.debt.principal == after.debt.principal - 100 and paid.captain.silver == after.captain.silver - 100 and paid.reputations.merchantCredit == after.reputations.merchantCredit, "separate real partial payment100, no premature cleared-debt credit"): await finish(); return
		summary.afterRepayment = paid
		for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
			root.size = dimensions; root.content_scale_size = dimensions; await frames(8)
			if not await focus_control("story_objective") or not await capture("actual-partial-repayment-" + str(dimensions.x), dimensions): await finish(); return
	var expected_packet: Dictionary = scene.runtime.snapshot()
	var expected: Dictionary = expected_packet.campaign
	var export_context := {"kind":"normal-ui-save-checkpoint","safe":expected_packet.runtime.canSave,"portId":expected.currentPortId,"nativeIds":expected_packet.naval.ships.map(func(ship):return ship.id),"capturedShipIds":expected_packet.runtime.policy.capturedShipIds.duplicate()}
	if not check(scene.runtime.check_safety().get("ok", false), "all-fleet normal save safety remains required"): await finish(); return
	if not await button("menu_open") or not await button("save_and_menu"): await finish(); return
	if not check(main.current_scene == null and main.menu.visible, "normal save-and-menu completes"): await finish(); return
	var disk: Dictionary = storage.read_checkpoint()
	if not check(disk.get("ok", false), "normal disk checkpoint read") or not _write_exact(directory + "/normal-ui-save-v2.json", disk.get("json", "")): await finish(); return
	var decoded := Codec.decode(disk.json)
	if not check(decoded.get("ok", false), "actual paid branch passes strict V2 codec") or not preserve_material(expected, decoded.state, "normal saved branch", export_context): await finish(); return
	summary.saveReadback = {"diskRead":true,"checkpointStateVerified":true,"normalUiSaveSha256":FileAccess.get_sha256(directory + "/normal-ui-save-v2.json"),"slotSha256":FileAccess.get_sha256(storage.path),"exportOwnershipContext":export_context}
	entry = main.menu.find_child("mingqi-continue", true, false)
	main.menu._scroll.ensure_control_visible(entry); await frames(3); await click(entry)
	if not await resume_entry() or not preserve_material(decoded.state, scene.runtime.snapshot().campaign, "normal paid-branch Continue"): await finish(); return
	summary.saveReadback.ok = true
	if not await button("nav_story") or not await focus_control("story_outcome_second-return") or not await capture("save-readback-1280", Vector2i(1280, 720)): await finish(); return
	unchanged_sources()
	await finish()

func _write_exact(path: String, bytes: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "new exact-byte evidence file"): return false
	file.store_string(bytes); file.flush(); var okay := file.get_error() == OK; file.close()
	return check(okay and FileAccess.get_file_as_string(path) == bytes, "exact-byte witness readback")

func _guard_tests() -> void:
	check(journey_failure(null) == "journey-not-object", "nonobject rejected before scene/Storage")
	check(journey_failure({"failures":1}) == "journey-has-failures", "failed actual voyage never seeds a branch")
	check(journey_failure({"failures":0,"actualSafeReturn":false}) == "journey-safe-return-unconfirmed", "delivery without return cannot seed a branch")
	check(journey_failure({"failures":0,"actualSafeReturn":true,"terrain":"flat control"}) == "journey-not-formal-terrain", "flat test is not formal actual journey")
	check(journey_failure({"failures":0,"actualSafeReturn":true,"terrain":"same formal game terrain","sourceHashes":{}}) == "journey-source-inventory-missing", "empty provenance is rejected before scene/Storage")
	check(journey_failure({"failures":0,"actualSafeReturn":true,"terrain":"same formal game terrain","sourceHashes":{"game/domain/mingqi/second_voyage_aftermath.gd":FileAccess.get_sha256("res://game/domain/mingqi/second_voyage_aftermath.gd")}}) == "journey-source-inventory-incomplete", "a single good source cannot stand for complete voyage provenance")
	var hashes: Dictionary = {}
	for path: String in Continued.SOURCES: hashes[path] = FileAccess.get_sha256("res://" + path)
	hashes["tools/qa-journey-checkpoint.gd"] = FileAccess.get_sha256("res://tools/qa-journey-checkpoint.gd")
	check(_inventory_reason({"sourceHashes":hashes}).is_empty(), "complete actual current inventory is accepted")
	var changed: Dictionary = hashes.duplicate()
	changed.erase("modules/naval_simulation/navigation/wet_route_egress.gd")
	check(_inventory_reason({"sourceHashes":changed}) == "journey-source-inventory-incomplete", "missing existing safety source rejected")
	changed = hashes.duplicate(); changed["game/domain/mingqi/second_voyage_aftermath.gd"] = "0".repeat(64)
	check(_inventory_reason({"sourceHashes":changed}) == "journey-source-inventory-mismatch", "aftermath source drift rejected")
	changed = hashes.duplicate(); changed["game/domain/mingqi/second_voyage_aftermath.gd"] = 123
	check(_inventory_reason({"sourceHashes":changed}) == "journey-source-inventory-mismatch", "nonstring digest rejected")
	check(_inventory_reason({"sourceHashes":[]}) == "journey-source-inventory-missing", "nondictionary inventory rejected")
	check(not Aftermath.CHOICES.has("fake"), "unknown branch rejected")
	print("SECOND_AFTERMATH_CAPTURE_GUARDS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
