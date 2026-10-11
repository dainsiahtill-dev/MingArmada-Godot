extends SceneTree
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Storage = preload("res://game/persistence/save_coordinator.gd")
var failures := 0
var assertions := 0
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",detail)
func _initialize() -> void:
	var path := "user://migration-verification/checkpoint-%d.json"%OS.get_process_id()
	var storage := Storage.new(path)
	var runtime := Runtime.new(); runtime.configure(func(_x: float,_z: float) -> float: return -24.0)
	check(runtime.check_safety().ok,"actual initial fleet satisfies source checkpoint conditions")
	check(runtime.save_checkpoint(storage,"2026-10-11T00:00:00.000Z").ok,"real file checkpoint writes validated source-compatible v2 bytes")
	var first: String = storage.read_checkpoint().json
	var packet: Dictionary = runtime.snapshot()
	check(runtime.command({"type":"accept-convoy","commandId":"disk-test-accept","expectedRevision":packet.campaign.revision}).ok,"business can proceed after checkpoint")
	check(runtime.save_checkpoint(storage,"2026-10-11T00:01:00.000Z").ok,"second real write replaces checkpoint")
	check(storage.read_backup().json == first,"backup preserves previous verified bytes exactly")
	var second: String = storage.read_checkpoint().json
	check(not storage.write_checkpoint("{invalid}").ok and storage.read_checkpoint().json == second,"invalid bytes cannot replace current checkpoint")
	var before: Dictionary = runtime.snapshot()
	check(not runtime.adopt_save("{invalid}",storage).ok and runtime.snapshot().campaign == before.campaign and storage.read_checkpoint().json == second,"invalid import changes neither live authority nor disk slot")
	var blocked_directory := path+".blocked"; DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_directory))
	var blocked := Storage.new(blocked_directory)
	check(not runtime.adopt_save(first,blocked).ok and runtime.snapshot().campaign == before.campaign,"actual destination directory rejection leaves old live session untouched")
	check(runtime.adopt_save(first,storage,"2026-10-11T00:02:00.000Z").ok,"safe import validates native candidate before swapping it")
	packet = runtime.snapshot()
	check(packet.runtime.generation == before.runtime.generation+1 and packet.runtime.paused and packet.campaign.contracts["convoy-001"].status == "offered","import changes generation, keeps candidate paused, restores prior business")
	check(storage.read_backup().json == second,"successful import retains prior disk bytes for recovery")
	check(packet.campaign.simulationSeconds == 0,"load does not invent offline progress")
	runtime.dispose()
	for suffix in ["",".backup",".rollback",".staged",".blocked.staged"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_directory))
	print("SAVE_COORDINATOR_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
