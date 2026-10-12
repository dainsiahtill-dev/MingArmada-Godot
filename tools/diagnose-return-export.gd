extends SceneTree
## One detached CPU reproduction from an immutable real full-precision checkpoint.
## No Storage, game scene, GPU capture, user-slot write or source-state repair.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Codec = preload("res://game/domain/persistence/save_codec.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Layout = preload("res://game/scenes/common/reference_geography.gd")
const JOURNEY = "res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"
const DIRECTORY = "res://docs/migration/evidence/opening-story/return-export-diagnostic"
var assertions := 0
var failures := 0
var runtime := Runtime.new()

func _initialize() -> void: run.call_deferred()
func check(value: bool, detail: String) -> bool:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ", detail)
	return value
func write_bytes(path: String, bytes: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not check(file != null, "diagnostic bytes write: " + path): return false
	file.store_string(bytes); file.flush()
	var okay := file.get_error() == OK; file.close()
	return check(okay and FileAccess.get_file_as_string(path) == bytes, "diagnostic exact byte readback: " + path)
func differences(before: Variant, after: Variant, path: String = "state") -> Array:
	var result: Array = []
	if before is Dictionary and after is Dictionary:
		var keys: Array = before.keys()
		for key: String in after:
			if not key in keys: keys.append(key)
		for key: String in keys:
			if not before.has(key) or not after.has(key): result.append({"path": path + "." + key, "beforeExists": before.has(key), "afterExists": after.has(key), "before": before.get(key), "after": after.get(key)})
			else: result.append_array(differences(before[key], after[key], path + "." + key))
	elif before is Array and after is Array:
		if before.size() != after.size(): result.append({"path": path, "before": before, "after": after})
		else:
			for index in before.size(): result.append_array(differences(before[index], after[index], path + "[" + str(index) + "]"))
	elif not Codec._equal(before, after): result.append({"path": path, "before": before, "after": after})
	return result
func run() -> void:
	var journey_sha := FileAccess.get_sha256(JOURNEY)
	var record: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(JOURNEY))
	if not check(record.failures == 0 and record.actualSafeReturn, "actual successful safe-return record"): finish(); return
	var checkpoint: String = record.get("confirmedCheckpointJson", "")
	var decoded: Dictionary = Codec.decode(checkpoint)
	if not check(decoded.get("ok", false) and Codec._equal(decoded.get("state"), record.final.campaign), "confirmed exact full-precision native checkpoint equals real final campaign"): finish(); return
	for source: String in record.sourceHashes:
		if not check(FileAccess.get_sha256("res://" + source) == record.sourceHashes[source], "frozen source hash: " + source): finish(); return
	if not check(not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(DIRECTORY)), "fresh diagnostic evidence directory"): finish(); return
	if not check(DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY)) == OK, "diagnostic directory created"): finish(); return
	if not write_bytes(DIRECTORY + "/source-confirmed-checkpoint-v2.json", checkpoint): finish(); return
	var heights := Height.new()
	var geography: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	if not check(heights.configure_ports(geography, true, Layout.options()), "actual formal geography"): finish(); return
	runtime.enable_reference_enhancements()
	if not check(runtime.configure(heights.sample_height).get("ok", false), "detached real native Runtime configure"): finish(); return
	var adopted: Dictionary = runtime.adopt_save(checkpoint, null)
	if not check(adopted.get("ok", false), "normal strict native adopt: " + str(adopted.get("reason", ""))): finish(); return
	runtime.set_pause("loading", false)
	var accepted: Dictionary = runtime.command({"type": "accept-convoy", "contractId": "convoy-002", "commandId": "return-export-diagnostic-accept", "expectedRevision": runtime.snapshot().campaign.revision})
	if not check(accepted.get("ok", false), "legitimate real twenty-grain acceptance: " + str(accepted.get("reason", ""))): finish(); return
	var before: Dictionary = runtime.snapshot()
	var second: Dictionary = before.campaign.contracts["convoy-002"]
	if not check(second.status == "active" and second.voyageIds.size() == 2 and second.voyageIds.all(func(id): return before.campaign.vessels[before.campaign.voyages[id].vesselId].cargo.grain == 10), "real original two ships each carry ten grain"): finish(); return
	var exported: Dictionary = runtime.export_save(Time.get_datetime_string_from_system(true) + ".000Z")
	if not check(exported.get("ok", false), "one normal export with full native safety: " + str(exported.get("reason", ""))): finish(); return
	var after: Dictionary = runtime.snapshot()
	var saved: Dictionary = Codec.decode(exported.json)
	if not check(saved.get("ok", false) and Codec._equal(saved.state, after.campaign), "exact exported decoded state equals actual post-export campaign"): finish(); return
	if not write_bytes(DIRECTORY + "/normal-export-v2.json", exported.json): finish(); return
	if not write_bytes(DIRECTORY + "/before.json", JSON.stringify(before, "\t", false, true)): finish(); return
	if not write_bytes(DIRECTORY + "/after.json", JSON.stringify(after, "\t", false, true)): finish(); return
	var all_diffs := differences(before.campaign, after.campaign)
	var material_diffs: Array = []
	for difference: Dictionary in all_diffs:
		var path: String = difference.path
		if path == "state.revision" or path.ends_with(".revision") or ".controlsObserved." in path or ".controlsProjection." in path: continue
		material_diffs.append(difference)
	var summary := {"mode": "headless detached real checkpoint/accept/export diagnosis; no storage or GPU", "journeySha256": journey_sha, "diagnosticSourceSha256": FileAccess.get_sha256("res://tools/diagnose-return-export.gd"), "sourceHashes": record.sourceHashes, "normalExportSha256": FileAccess.get_sha256(DIRECTORY + "/normal-export-v2.json"), "nativeIdsBefore": before.naval.ships.map(func(ship): return ship.id), "capturedShipIdsBefore": before.runtime.policy.capturedShipIds, "portBefore": before.campaign.currentPortId, "allFieldDiffs": all_diffs, "materialDiffs": material_diffs, "decodedDiffs": differences(after.campaign, saved.state), "assertions": assertions, "failures": failures}
	check(FileAccess.get_sha256(JOURNEY) == journey_sha, "immutable real source record unchanged")
	write_bytes(DIRECTORY + "/diagnostic-result.json", JSON.stringify(summary, "\t", false, true))
	print("RETURN_EXPORT_DIAGNOSTIC materialDiffs=", material_diffs.size(), " allFieldDiffs=", all_diffs.size())
	finish()
func finish() -> void:
	runtime.dispose()
	print("RETURN_EXPORT_DIAGNOSTIC_COMPLETE assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
