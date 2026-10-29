extends SceneTree
## Synthetic progress fixtures only. Never acceptance of real sailing/trade/combat.
const DEMO_PATH := "res://game/research/demos/story_campaign_flow_experiment.gd"
const STEP := 1.0 / 60.0
var assertions := 0
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(value: bool, reason: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL STORY CAMPAIGN DEMO: ", reason)
	return value

func finish() -> void:
	print("STORY_CAMPAIGN_FLOW_DEMO assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)

func advance_actions(demo: Node3D, count: int) -> void:
	for _i in count: demo.advance(.25)

func run() -> void:
	# A missing implementation must fail an assertion, never preload parsing.
	if not check(FileAccess.file_exists(DEMO_PATH), "independent campaign progress demo exists"):
		finish(); return
	var script: Script = load(DEMO_PATH)
	if not check(script != null and script.can_instantiate(), "campaign progress demo loads"):
		finish(); return
	var demo: Node3D = script.new()
	check(demo.configure({"paused":true}).get("ok", false) and demo.get_child_count() == 0, "pre-tree configuration owns no presentation")
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1100, 720)
	viewport.own_world_3d = true
	root.add_child(viewport)
	viewport.add_child(demo)
	await process_frame
	var initial: Dictionary = demo.inspection_snapshot()
	if not check(initial.get("ready", false), "dashboard and in-memory progress are ready"):
		printerr(initial.get("error", "")); demo.free(); viewport.free(); finish(); return
	check(initial.topic == "story-campaign-flow" and initial.scope == "synthetic-progress-fixture; no real gameplay completion", "synthetic scope is explicit")
	check(initial.presentation == "dashboard" and initial.text.contains("主线进度合成实验 · 非真实任务通关"), "visible header declares evidence boundary")
	check(initial.tick == 0 and initial.time == 0.0 and initial.fixed_step == STEP, "accepted time starts at zero independently of story year")
	check(initial.resources.world == 0 and initial.resources.runtime == 0 and initial.resources.storage == 0, "no world/runtime/persistent storage owner")
	check(not demo.is_processing() and not demo.is_physics_processing(), "host alone advances experiment")
	demo.advance(100.0)
	check(demo.inspection_snapshot().progress == initial.progress and demo.inspection_snapshot().tick == 0, "pause freezes facts, receipts and time")
	check(demo.set_parameter("camera_mode", "current").get("ok", false), "current chapter reading view selected")
	var reading: Dictionary = demo.inspection_snapshot()
	check(reading.progress == initial.progress and reading.tick == initial.tick and reading.transitionCount == 0, "paused camera selection cannot change authority")
	check(reading.text != initial.text, "camera changes presentation")
	for invalid: Dictionary in [{"fixture":"invented"},{"paused":1},{"seed":true},{"camera_mode":"near"},{"unknown":true}]:
		check(not demo.configure(invalid).get("ok", true) and demo.inspection_snapshot() == reading, "invalid options preserve dashboard: " + str(invalid))
	check(demo.set_parameter("fixture", "recover").get("reset_required", false), "changing fixture requests host reset")
	demo.set_paused(false)
	demo.advance(STEP * .5)
	check(demo.inspection_snapshot().tick == 0, "fractional step waits")
	demo.advance(STEP * .5)
	check(demo.inspection_snapshot().tick == 1 and demo.inspection_snapshot().progress.phase == "briefing", "one accepted tick cannot skip briefing")
	demo.reset_experiment({"paused":false,"camera_mode":"overview"})
	demo.advance(1.0)
	var capped: Dictionary = demo.inspection_snapshot()
	check(capped.tick == 15 and capped.time == .25 and capped.progress.phase == "active", "quarter-second cap accepts one state machine action")
	advance_actions(demo, 119)
	var complete: Dictionary = demo.inspection_snapshot()
	check(complete.error.is_empty() and complete.progress.phase == "complete" and complete.progress.stageIndex == 30, "declared fixture completes all thirty progress stages")
	check(complete.progress.receipts.size() == 30 and complete.transitionCount == 120, "each stage begins, observes, settles and continues once")
	check(complete.progress.protagonistId == "zheng-chenggong" and not complete.progress.handoff.is_empty(), "synthetic CH12 handoff reaches son exactly once")
	check(complete.time == 30.0, "thirty story stages consume thirty accepted seconds, never story payroll years")
	demo.reset_experiment()
	advance_actions(demo, 120)
	check(demo.inspection_snapshot().progress == complete.progress, "same seed and fixture reproduce exact receipts")
	demo.reset_experiment({"fixture":"recover"})
	advance_actions(demo, 123)
	var recovered: Dictionary = demo.inspection_snapshot()
	check(recovered.progress.phase == "complete" and recovered.progress.receipts.size() == 31, "failure and retry fixture subsequently reaches all thirty stages")
	check(recovered.progress.receipts[0].outcome == "failure" and recovered.progress.receipts[1].attempt == 2, "failure receipt survives retry with a distinct attempt")
	demo.reset_experiment({"fixture":"missing-handover"})
	advance_actions(demo, 120)
	var blocked: Dictionary = demo.inspection_snapshot()
	check(blocked.blocked and blocked.currentStage.id == "T10" and blocked.progress.phase == "active", "missing port handover stays at active T10")
	check(blocked.progress.receipts.size() == 29 and blocked.error.is_empty(), "missing declared evidence cannot create a final receipt")
	advance_actions(demo, 20)
	check(demo.inspection_snapshot().progress == blocked.progress and demo.inspection_snapshot().transitionCount == blocked.transitionCount, "blocked fixture never spins rejected settlement commands")
	demo.set_paused(true)
	var paused: Dictionary = demo.inspection_snapshot()
	demo.set_camera_mode("current")
	demo.advance(.25)
	check(demo.inspection_snapshot().tick == paused.tick and demo.inspection_snapshot().progress == paused.progress, "blocked paused camera preserves every accepted fact")
	viewport.size = Vector2i(1,1)
	await process_frame
	viewport.size = Vector2i(760,600)
	await process_frame
	var layout: Dictionary = demo.inspection_snapshot().ui
	check(layout.panel.position.x >= 0 and layout.panel.position.y >= 0 and layout.panel.end.x <= 760.0 and layout.panel.end.y <= 600.0, "dashboard recovers bounded rect after one-pixel resize")
	demo.dispose()
	var disposed: Dictionary = demo.inspection_snapshot()
	check(disposed.disposed and not disposed.ready and disposed.progress.is_empty() and demo.get_child_count() == 0, "dispose releases dashboard and synthetic progress")
	demo.free()
	viewport.free()
	await process_frame
	finish()
