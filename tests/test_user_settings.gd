extends SceneTree
var failures := 0
var assertions := 0
const Text = preload("res://game/domain/legacy/utf16_text.gd")
func check(ok: bool, detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", detail)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	if not ResourceLoader.exists("res://game/persistence/user_settings.gd"):
		check(false,"settings store must persist and validate source settings"); _finish(); return
	var Store = load("res://game/persistence/user_settings.gd")
	var path := "user://migration-verification/settings-%d.json" % OS.get_process_id()
	var store = Store.new(path)
	var missing: Dictionary = store.load_settings()
	check(missing.ok and missing.reason == "settings-not-found" and missing.settings.handling == "assisted" and missing.settings.musicVolume == 0.7,"missing file exposes reason and source assisted/music defaults")
	check(missing.settings.cameraShake == 0 and missing.settings.cameraFollow and missing.settings.horizonStability == 1 and not missing.settings.reducedMotion,"first launch keeps stable source camera defaults")
	var result: Dictionary = store.update_settings({"quality":"high","soundVolume":-2.0,"musicVolume":2.0,"handlingMode":"realistic","cameraFollow":false})
	check(result.ok and result.settings.soundVolume == 0 and result.settings.musicVolume == 1 and result.settings.handling == "realistic","finite numeric patch clamps and handling alias maps to canonical source field")
	var bytes := FileAccess.get_file_as_string(path)
	check(JSON.parse_string(bytes).version == 1,"verified settings file is versioned")
	var reloaded = Store.new(path)
	check(reloaded.load_settings().ok and reloaded.snapshot() == store.snapshot(),"fresh store reloads actual disk settings including partial updates")
	var before: Dictionary = store.snapshot()
	result = store.update_settings({"sound":false,"musicVolume":NAN})
	check(not result.ok and result.reason == "settings-invalid-musicVolume" and store.snapshot() == before and FileAccess.get_file_as_string(path) == bytes,"mixed invalid patch changes neither settings nor disk")
	check(not store.update_settings({"quality":"ultra"}).ok and not store.update_settings({"sound":"yes"}).ok and not store.update_settings({"unknown":true}).ok,"invalid enum/type/unknown field are explicit refusals")
	var detached: Dictionary = store.snapshot(); detached.sound = false
	check(store.snapshot().sound,"returned settings cannot mutate live state")
	var name := "海".repeat(23)+"😀"
	check(store.update_settings({"captainName":name}).ok,"source UTF16 name truncation can persist a split surrogate")
	var expected_units: Array = Text.native_units("海".repeat(23)); expected_units.append(0xd83d)
	check(Text.utf16_units(store.snapshot().captainName) == expected_units,"captain name uses 24 source UTF16 units rather than Unicode scalar count")
	check(reloaded.load_settings().ok and Text.utf16_units(reloaded.snapshot().captainName) == expected_units,"split UTF16 code unit survives actual JSON write and reload")
	var recovery_bytes := FileAccess.get_file_as_string(path)
	var recovery := FileAccess.open(path+".rollback",FileAccess.WRITE); recovery.store_string(recovery_bytes); recovery.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	check(reloaded.load_settings().ok and Text.utf16_units(reloaded.snapshot().captainName) == expected_units,"interrupted replacement reads real rollback file without losing confirmed settings")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path+".rollback"))
	var file := FileAccess.open(path,FileAccess.WRITE); file.store_string("{bad json"); file.close()
	result = reloaded.load_settings()
	check(not result.ok and result.reason == "settings-invalid-json" and result.settings.sound and result.settings.musicVolume == 0.7,"corrupt file restores defaults and actual load reason")
	file = FileAccess.open(path,FileAccess.WRITE); file.store_string('{"version":2,"settings":{"sound":false}}'); file.close()
	check(reloaded.load_settings().reason == "settings-unsupported-version" and reloaded.snapshot().sound,"future version cannot silently overwrite defaults")
	file = FileAccess.open(path,FileAccess.WRITE); file.store_string('{"version":1,"settings":{"quality":"ultra","sound":false,"cameraShake":9,"horizonStability":-5}}'); file.close()
	result = reloaded.load_settings()
	check(result.ok and result.reason == "settings-normalized" and result.settings.quality == "balanced" and not result.settings.sound and result.settings.cameraShake == 1 and result.settings.horizonStability == 0,"load uses source field fallback and finite bounds")
	var blocked_path := path+".directory"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(blocked_path))
	var blocked = Store.new(blocked_path)
	check(blocked.load_settings().reason == "settings-read-failed","directory destination reports actual read failure")
	before = blocked.snapshot(); result = blocked.update_settings({"sound":false})
	check(not result.ok and blocked.snapshot() == before,"real destination replacement failure preserves live settings")
	# A real native panel emits patches; applying snapshots never causes business commands.
	var Panel = load("res://game/ui/settings/settings_panel.gd")
	if Panel:
		var panel = Panel.new(); root.add_child(panel); panel.build()
		var patches: Array = []; panel.settings_requested.connect(func(patch: Dictionary): patches.append(patch))
		panel.open(store.snapshot(),"settings-write-failed")
		check(panel.visible and panel.get_node("Center/Panel/Column/Reason").text.contains("写入"),"panel shows actual persistence refusal in Chinese")
		check(patches.is_empty(),"applying readonly snapshot emits no request")
		var toggle = panel.get_node("Center/Panel/Column/Scroll/Fields/sound/Value")
		toggle.toggled.emit(false)
		check(patches == [{"sound":false}],"native toggle emits only intended patch")
		panel.close(); check(not panel.visible,"panel close hides native overlay"); panel.queue_free()
	else: check(false,"native settings panel exists")
	for suffix in ["",".staged",".backup",".rollback"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(path+suffix))
		if FileAccess.file_exists(blocked_path+suffix): DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path+suffix))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(blocked_path))
	await process_frame
	_finish()
func _finish() -> void:
	print("USER_SETTINGS_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
