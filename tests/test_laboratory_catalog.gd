extends SceneTree
var assertions := 0
var failures := 0
func check(ok: bool, reason: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ",reason)
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	check(FileAccess.file_exists("res://game/research/catalog.gd"),"research catalog must exist")
	if failures: _finish(); return
	var script: GDScript = load("res://game/research/catalog.gd")
	var catalog: RefCounted = script.new()
	var receipt: Dictionary = catalog.load_catalog()
	check(receipt.get("ok",false),"bundled research catalog loads")
	var topics: Array = catalog.topics()
	check(topics.size() == 15,"existing subjects plus whole-mainline progress research registered")
	var ids: Dictionary = {}
	for topic: Dictionary in topics:
		check(not ids.has(topic.id),"unique subject identity")
		ids[topic.id] = true
		var paper: Dictionary = catalog.read_paper(topic.id)
		check(paper.get("ok",false),"bundled paper readable: "+topic.id)
		if paper.get("ok",false):
			for heading: String in script.PAPER_SECTIONS:
				check(paper.text.contains("## "+heading),"paper contains research section "+heading+": "+topic.id)
		check(topic.retrospective == (topic.id not in ["wake-flow","architecture-convergence-2026-10-21","hero-fuchuan","antique-cartography","broadside-receipt-readability","crew-role-effects","naval-combat-atmosphere","cargo-deck-drift","ship-fire-control","story-campaign-flow"]),"historical and prospective research are distinguished")
		check(not catalog.demo_path(topic.id).is_empty(),"all visual subjects have a registered independent demo: "+topic.id)
	for required: String in ["hull-contact","ocean-surface","shore-surf","weather-shadow","shadow-edges","wake-flow","architecture-convergence-2026-10-21","hero-fuchuan","antique-cartography","broadside-receipt-readability","crew-role-effects","naval-combat-atmosphere","cargo-deck-drift","ship-fire-control"]:
		check(ids.has(required),"expected visual research subject: "+required)
	var broadside: Dictionary = catalog.topic("broadside-receipt-readability")
	check(ids.has("story-campaign-flow") and catalog.topic("story-campaign-flow").get("abstract", "").contains("合成进度"), "mainline preview explicitly distinguishes synthetic progress from real gameplay")
	check(broadside.get("abstract","").contains("固定步 GPU 对照已完成") and broadside.get("abstract","").contains("真实游戏与玩家体验待验证"),"research summary distinguishes fixed-step GPU from unverified gameplay")
	check(not catalog.read_paper("not-a-topic").get("ok",true),"unknown topic rejected")
	check(catalog.demo_path("not-a-topic").is_empty(),"unknown demo cannot load script")
	check(not catalog.read_reference("C:/Windows/system.ini").get("ok",true),"absolute host path rejected")
	check(not catalog.read_reference("res://../../outside.gd").get("ok",true),"path traversal rejected")
	check(not catalog.read_reference("res://game/runtime/game_router.gd").get("ok",true),"unregistered source rejected")
	var detached: Array = catalog.topics(); detached[0].title = "mutated"
	check(catalog.topics()[0].title != "mutated","catalog snapshots isolate consumers")
	var bad: Dictionary = catalog.validate_catalog({"schemaVersion":1,"topics":[{"id":"x","title":"x","paper":"res://game/runtime/game_router.gd"}]})
	check(not bad.ok,"unstructured/non-paper registration rejected")
	bad = catalog.validate_catalog({"schemaVersion":1,"topics":[topics[0],topics[0]]})
	check(not bad.ok,"duplicate registrations rejected")
	var reader: GDScript = load("res://game/research/paper_reader.gd")
	check(reader != null,"research paper renderer available")
	if reader:
		var rendered: String = reader.to_bbcode("# 标题\n\n## 方法\n[img]C:/host[/img]\n```gdscript\nprint('[url=cmd]x[/url]')\n```")
		check(rendered.contains("[font_size=28]") and rendered.contains("[b]标题[/b]"),"paper titles rendered")
		check(not rendered.contains("[img]C:/host"),"paper cannot inject rich-text image commands")
		check(not rendered.contains("[url=cmd]"),"code examples cannot inject clickable commands")
	_finish()
func _finish() -> void:
	print("LABORATORY_CATALOG_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
