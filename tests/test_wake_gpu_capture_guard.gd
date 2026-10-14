extends SceneTree
const Driver = preload("res://tools/verify-wake-production-gpu.gd")
const Contact = preload("res://modules/scene_engine/water/hull_contact_froth.gd")
const Source = preload("res://modules/scene_engine/water/source_froth.gd")
var assertions := 0
var failures := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL wake GPU capture guard: ", detail)
func _initialize() -> void:
	var script: Script = Driver
	var names: Array = []
	for method in script.get_script_method_list(): names.append(str(method.name))
	check("capture_inventory_valid" in names, "capture helper validates complete nonzero inventory")
	check("froth_diagnostic" in names, "capture helper uses typed public froth diagnostics")
	if failures: finish(); return
	check(not script.call("capture_inventory_valid", [], false, false), "zero captures always fails")
	var records: Array = []
	for label in script.call("expected_capture_labels",false,false): records.append({"label":label})
	check(script.call("capture_inventory_valid",records,false,false), "all seven standard captures accepted")
	records.append(records[0])
	check(not script.call("capture_inventory_valid",records,false,false), "duplicate extra capture rejected")
	records.clear()
	for label in script.call("expected_capture_labels",true,true): records.append({"label":label})
	check(records.size() == 11 and script.call("capture_inventory_valid",records,true,true), "enabled probes require exact eleven labels")
	var contact := Contact.new()
	var data: Dictionary = script.call("froth_diagnostic",contact)
	check(data.kind == "target-hull-contact" and data.diagnostics == contact.diagnostics(), "current Contact records actual public diagnostics without old surface access")
	var source := Source.new()
	var source_data: Dictionary = script.call("froth_diagnostic",source)
	check(source_data.ok and source_data.kind == "authored-source-froth" and source_data.diagnostics == source.diagnostics(), "original authored Froth diagnostic route retained")
	check(not script.call("froth_diagnostic",RefCounted.new()).ok, "unknown froth implementation rejected explicitly")
	contact.dispose(); source.dispose(); finish()
func finish() -> void:
	print("WAKE_GPU_CAPTURE_GUARD_PASS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
