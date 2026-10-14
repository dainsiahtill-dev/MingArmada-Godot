extends SceneTree
## Real Control -> existing native transaction; no gameplay completion fixture.
const Runtime = preload("res://game/runtime/mingqi_runtime.gd")
const Interface = preload("res://game/ui/mingqi/mingqi_interface.gd")
var assertions := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL voyage closure UI: ", message)
func press(ui, id: String) -> void:
	var button = ui.find_child(id, true, false)
	check(button is Button and not button.disabled, "enabled existing control " + id)
	if button is Button and not button.disabled: button.pressed.emit()
func _initialize() -> void: run.call_deferred()
func run() -> void:
	var runtime := Runtime.new()
	check(runtime.configure(func(_x: float, _z: float) -> float: return -24.0).ok, "real runtime configured")
	var ui = Interface.new()
	root.add_child(ui)
	await process_frame
	var results: Array = []
	ui.command_requested.connect(func(intent):
		results.append(runtime.command(intent))
		ui.apply_snapshot(runtime.snapshot()))
	ui.apply_snapshot(runtime.snapshot())
	check(runtime.snapshot().story.has("flow"), "runtime publishes tested read-only flow")
	check(ui.find_child("voyage_progress", true, false) is Label, "deadline visible in ordinary HUD")
	check(ui.find_child("voyage_upgrade_open", true, false) is Button, "journal offers concrete own-ship service route")
	if failures:
		ui.free(); runtime.dispose(); finish(); return
	check(ui.find_child("voyage_save", true, false).text.contains("继续海上明旗 · 1650"), "Continue guidance uses real main-menu title")
	check(ui.find_child("story_scene_old-ledger", true, false).get_index() < ui.find_child("voyage_closure", true, false).get_index(), "preparation presents meaningful choices before later port-services guidance")
	check(ui.find_child("voyage_progress", true, false).text.contains("30:00"), "offered deadline visible before acceptance")
	ui.open_panel("story")
	press(ui, "story_choice_old-ledger_settle-wages")
	check(ui.find_child("voyage_decisions", true, false).text.contains("80两") and runtime.snapshot().campaign.captain.silver == 570, "choice feedback reflects actual payment")
	var original: Dictionary = runtime.snapshot().campaign
	press(ui, "voyage_upgrade_open")
	check(ui.find_child("panel_port", true, false).visible and ui.get("_form").service_ship == original.campaignId + "-heritage", "shortcut selects real own ship")
	check(runtime.snapshot().campaign == original, "navigation shortcut performs no purchase")
	press(ui, "service_refit")
	check(runtime.snapshot().campaign.captain.silver == 420 and runtime.snapshot().campaign.works.size() == 1, "normal refit deducts exact quote once")
	check(ui.find_child("voyage_upgrade", true, false).text.contains("120秒"), "pending actual work remaining time visible")
	check(ui.find_child("service_refit", true, false).disabled, "repeat refit blocked by live work")
	var complete_work := "--complete-refit" in OS.get_cmdline_user_args()
	for step in (601 if complete_work else 5):
		runtime.advance(0.2)
		if step % 50 == 0: await process_frame
	ui.apply_snapshot(runtime.snapshot())
	if complete_work:
		check(runtime.snapshot().campaign.vessels[original.campaignId + "-heritage"].profileId == "heritage-sails", "120 accepted seconds completes real refit")
		check(ui.find_child("voyage_upgrade", true, false).text.contains("已完成") and ui.find_child("voyage_upgrade", true, false).text.contains("1.10"), "upgrade feedback reads actual completed profile")
	else:
		check(runtime.snapshot().campaign.vessels[original.campaignId + "-heritage"].profileId == "heritage", "short ordinary test never accelerates work completion")
		check(ui.find_child("voyage_upgrade", true, false).text.contains("119秒"), "work countdown follows accepted second")
	var exported := runtime.export_save("2026-10-14T00:00:00.000Z")
	check(exported.ok, "existing full-fleet safety gate accepts real checkpoint")
	if exported.ok:
		var saved: Dictionary = runtime.snapshot().campaign
		check(runtime.adopt_save(exported.json).ok, "normal restore rebuilds real work and payment")
		runtime.set_pause("loading", false)
		ui.apply_snapshot(runtime.snapshot())
		check(runtime.snapshot().campaign.captain.silver == saved.captain.silver and JSON.parse_string(JSON.stringify(runtime.snapshot().campaign.works)) == JSON.parse_string(JSON.stringify(saved.works)), "Continue projection preserves actual work and money")
		check(ui.find_child("service_refit", true, false).disabled, "restored active or completed upgrade cannot charge again")
	ui.open_panel("story")
	press(ui, "voyage_save_open")
	check(ui.is_menu_open() and ui.find_child("save", true, false).disabled == not runtime.snapshot().runtime.canSave, "checkpoint shortcut enters real guarded save menu")
	check(ui.find_child("voyage_save", true, false).text.contains("继续航程"), "safe Continue path explicitly explained")
	ui.free(); runtime.dispose()
	finish()
func finish() -> void:
	print("VOYAGE_FLOW_UI_PASS assertions=", assertions, " failures=", failures)
	quit(1 if failures else 0)
