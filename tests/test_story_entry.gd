extends SceneTree
## Story formal entry wiring: router accepts story/story-continue, the scene
## exposes the router contract, and the menu carries the campaign buttons.

const Router = preload("res://game/runtime/game_router.gd")
const Menu = preload("res://game/ui/menu/main_menu.gd")
const StoryScene = preload("res://game/scenes/story/story_scene.gd")
var assertions: int = 0
var failures: int = 0

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	assertions += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	var router: RefCounted = Router.new()
	check(router.MODES.has("story") and router.MODES.has("story-continue"), "router registers the story modes")
	var view: Dictionary = router.call("view_model")
	check(view.has("hasStorySave"), "view model exposes the story save flag")
	var prepared: Dictionary = router.call("prepare_entry", {"type": "start", "mode": "story", "name": "郑芝龙", "generation": router.generation, "nonce": 1})
	check(prepared.get("ok", false) and prepared.mode == "story", "story entry prepares: " + str(prepared.get("reason", "")))
	var candidate: Dictionary = prepared
	var scene: Dictionary = router.call("create_scene", candidate)
	check(scene.get("ok", false), "story scene creates through the router: " + str(scene.get("reason", "")))
	if scene.get("ok", false):
		var node: Node = scene.scene
		check(node.get("startup_options") != null and node.get("initial_save") != null and node.get("storage") != null, "story scene exposes the router contract properties")
		check(node.get("storage") == router.story_storage, "story scene binds the story save slot")
		# The epilogue ledger only needs a configured runtime; the mounted scene
		# boot is covered by the input test (which also proves the help panel).
		node.runtime.call("configure", func(_x: float, _z: float) -> float: return -24.0, {"seed": 1661, "runId": "story-entry-acts"})
		var summary: Dictionary = node.runtime.call("voyage_summary")
		check((summary.get("acts", []) as Array).size() == 6, "the epilogue carries the six-act retrospective")
		var open_acts := true
		for act: Dictionary in summary.get("acts", []):
			open_acts = open_acts and not bool(act.get("done", true))
		check(open_acts, "a fresh voyage shows every act unfinished")
		var journal: Array = node.runtime.call("voyage_journal")
		check(journal.size() == 1 and str(journal[0]).contains("世界开账"), "the voyage journal opens with the first log line")
		node.free()
	var forged: Dictionary = router.call("prepare_entry", {"type": "story-continue", "mode": "story-continue", "name": "郑芝龙", "generation": router.generation, "nonce": 2})
	check(not forged.get("ok", true), "continuing without a story save is refused")
	var menu: Node = Menu.new()
	get_root().add_child(menu)
	check(menu != null, "menu builds with story entries")
	check(menu.find_child("story", true, false) != null, "menu carries the story entry button")
	check(menu.find_child("story-continue", true, false) != null, "menu carries the story continue button")
	menu.free()
	_finish()

func _finish() -> void:
	print("STORY_ENTRY assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
