extends "res://tools/capture-opening-story.gd"
## Reuse the real opening/mouse journey, with fresh output and slot protection.
const Paths = preload("res://tools/qa-journey-paths.gd")
var original_slots: Dictionary = {}
var owned_slots: Array[String] = []
var capture_labels: Array[String] = []
var output_owned := false
var slot_owned := false
var clarity_sources: Dictionary = {}

func _initialize() -> void:
	if "--self-test" in OS.get_cmdline_user_args(): guard_tests.call_deferred()
	else: guarded_run.call_deferred()

func output_allowed(value: String) -> bool:
	# The shared JSON guard checks every directory component, Windows aliases
	# and existing links without creating anything. The directory must also be new.
	return Paths.output(["--output=" + value + "/capture-result.json"]).ok and not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(value)) and not FileAccess.file_exists(value)

func slot_hashes() -> Dictionary:
	var result: Dictionary = {}
	for path: String in ["user://saves/mingqi-v2.json", "user://saves/legacy-v1.json", "user://settings.json"]:
		for suffix: String in ["", ".backup", ".rollback", ".staged"]:
			var full := path + suffix
			result[full] = {"exists": FileAccess.file_exists(full), "sha256": FileAccess.get_sha256(full) if FileAccess.file_exists(full) else ""}
	return result

func guarded_run() -> void:
	var requested := ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--output=") and requested.is_empty(): requested = argument.trim_prefix("--output=")
		else: check(false, "unknown or duplicate clarity capture argument")
	check(not requested.is_empty() and output_allowed(requested), "explicit fresh output under opening-story evidence required")
	check(DisplayServer.get_name() != "headless", "clarity capture requires the native GPU")
	if failures: await finish(); return
	directory = requested
	check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory)) == OK, "create unused clarity evidence output")
	if failures: await finish(); return
	output_owned = true
	original_slots = slot_hashes()
	var prefix := "user://tests/opening-story-capture-%s" % OS.get_process_id()
	for suffix: String in ["-v2.json", "-v1.json", "-settings.json"]:
		for extension: String in ["", ".backup", ".rollback", ".staged"]:
			var full := prefix + suffix + extension
			owned_slots.append(full)
			check(not FileAccess.file_exists(full), "unused isolated opening slot")
	if failures: await finish(); return
	slot_owned = true
	for path: String in ["tools/capture-opening-clarity.gd", "tools/capture-opening-story.gd", "tools/qa-journey-paths.gd", "game/ui/mingqi/mingqi_interface.gd", "modules/naval_simulation/encounter.gd", "modules/naval_simulation/navigation/approach_clearance.gd", "modules/naval_simulation/navigation/wet_route_egress.gd", "game/domain/mingqi/second_voyage_aftermath.gd"]:
		clarity_sources[path] = FileAccess.get_sha256("res://" + path)
	await super.run()

func button(id: String) -> bool:
	if id == "contract_accept_convoy-001":
		var previous_size := root.size
		for dimensions: Vector2i in [Vector2i(1600, 900), Vector2i(1280, 720)]:
			root.size = dimensions; root.content_scale_size = dimensions
			await frames(8); scene._present(0)
			var offered: Label = scene.interface.find_child("contract_convoy-001", true, false)
			check(offered != null and offered.text.contains("接单前也计时") and offered.text.contains("期限剩余"), "actual offered deadline explains preparation timing")
			if offered:
				var parent := offered.get_parent()
				while parent:
					if parent is ScrollContainer: parent.ensure_control_visible(offered)
					parent = parent.get_parent()
				await frames(3)
			await capture("first-commission-offered-" + str(dimensions.x))
		root.size = previous_size; root.content_scale_size = previous_size; await frames(8)
	return await super.button(id)

func capture(label: String) -> void:
	await super.capture(label)
	capture_labels.append(label)
	var path := directory + "/" + label + ".json"
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	data.sourceHashes.merge(clarity_sources)
	var file := FileAccess.open(path, FileAccess.WRITE)
	check(file != null, "clarity capture source manifest")
	if file: file.store_string(JSON.stringify(data, "\t")); file.close()

func finish() -> void:
	if main:
		main.queue_free(); await frames(4); main = null
	var cleaned := true
	if slot_owned:
		for path: String in owned_slots:
			if FileAccess.file_exists(path): cleaned = DirAccess.remove_absolute(ProjectSettings.globalize_path(path)) == OK and cleaned
			cleaned = not FileAccess.file_exists(path) and cleaned
	var after := slot_hashes() if not original_slots.is_empty() else {}
	if slot_owned:
		check(cleaned, "only newly owned isolated slots removed")
		check(after == original_slots, "all twelve original user slot states unchanged")
		for path: String in clarity_sources: check(FileAccess.get_sha256("res://" + path) == clarity_sources[path], "capture source unchanged: " + path)
	if output_owned:
		var file := FileAccess.open(directory + "/run-result.json", FileAccess.WRITE)
		check(file != null, "record current native clarity result")
		if file:
			file.store_string(JSON.stringify({"captures": captures, "captureLabels": capture_labels, "assertions": assertions, "failures": failures, "originalSlotsBefore": original_slots, "originalSlotsAfter": after, "originalSlotsUnchanged": after == original_slots, "isolatedSlotsCleaned": cleaned, "userDataDir": ProjectSettings.globalize_path("user://"), "sourceHashes": clarity_sources, "scope": "Actual MainScene opening and native mouse controls. PNG sidecars are visual witnesses, not full-precision saves."}, "\t")); file.close()
	await super.finish()

func guard_tests() -> void:
	check(not output_allowed(""), "empty output rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/native"), "existing historical output rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/../outside"), "traversal rejected")
	check(not output_allowed("res://tools/new-output"), "outside evidence rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/new-output/"), "empty final component rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/new-output."), "Windows trailing dot alias rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/new-output:stream"), "Windows alternate stream rejected")
	check(not output_allowed("res://docs/migration/evidence/opening-story/CON"), "Windows device alias rejected")
	check(output_allowed("res://docs/migration/evidence/opening-story/clarity-guard-" + str(OS.get_process_id())), "fresh output accepted without creating it")
	print("OPENING_CLARITY_CAPTURE_GUARDS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
