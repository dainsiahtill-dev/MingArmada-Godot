extends SceneTree
## Fresh build-only evidence write checks. No Runtime advance.
var assertions := 0
var failures := 0
func check(value: bool, label: String) -> void:
	assertions+=1
	if not value: failures+=1; printerr("FAIL: ",label)
func _initialize() -> void:
	var driver = load("res://tools/play-opening-story-journey.gd")
	var methods: Array = driver.get_script_method_list()
	var available: bool = methods.any(func(method): return method.name=="write_verified")
	check(available,"first journey has verified writer")
	if available:
		var path := "res://build/port-approach-work/qa-first-evidence-write-"+str(Time.get_ticks_usec())+".json"
		var bytes := JSON.stringify({"fullPrecision":1.2345678901234567},"\t",false,true)
		var written: Dictionary = driver.write_verified(path,bytes)
		check(written.ok and written.writeError==OK and written.readbackExact,"fresh bytes flushed and verified exactly")
		check(FileAccess.get_file_as_string(path)==bytes,"exact full precision evidence readback")
		check(not driver.write_verified(path,"replacement").ok and FileAccess.get_file_as_string(path)==bytes,"existing evidence never overwritten")
		check(not driver.write_verified("res://build/port-approach-work",bytes).ok,"directory output rejected")
		print("FIRST_JOURNEY_EVIDENCE_FIXTURE path=",path)
	print("FIRST_JOURNEY_EVIDENCE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
