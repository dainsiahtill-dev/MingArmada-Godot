extends SceneTree

const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
var Catalog
var assertions := 0
var failures := 0

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: ", message)

func reject(content: Variant, message: String) -> void:
	var result: Dictionary = Catalog.validate(content)
	check(result.get("ok") == false and typeof(result.get("reason")) == TYPE_STRING and not result.get("reason", "").is_empty(), message)

func _initialize() -> void:
	check(FileAccess.file_exists(CATALOG_PATH), "story campaign catalog exists")
	if not FileAccess.file_exists(CATALOG_PATH):
		finish()
		return
	Catalog = load(CATALOG_PATH)
	if Catalog == null:
		check(false, "story campaign catalog loads")
		finish()
		return
	var loaded: Dictionary = Catalog.load_content()
	check(loaded.get("ok") == true and loaded.get("reason") == "", "authored campaign loads through strict validator")
	if not loaded.get("ok", false):
		finish()
		return
	var content: Dictionary = loaded.data
	check(content.id == "zheng-family-v1" and content.schemaVersion == 1, "campaign has stable versioned identity")
	check(content.chapters.size() == 24 and Catalog.stages().size() == 30, "continuous campaign contains 24 chapters and 30 actionable stages")
	check(content.protagonists.size() == 2 and content.protagonists[0].id == "zheng-zhilong" and content.protagonists[1].id == "zheng-chenggong", "father and son keep separate stable identities")
	var flattened: Array = Catalog.stages()
	check(flattened[0].id == "CH-01-S1" and flattened[19].id == "CH-20-S1" and flattened[20].id == "T01" and flattened[29].id == "T10", "early stages precede continuous Taiwan stages")
	for i in range(24):
		var chapter: Dictionary = content.chapters[i]
		check(chapter.id == "CH%02d" % (i + 1) and chapter.order == i + 1, "chapter stable ID and chronological order %d" % (i + 1))
		check(chapter.act == int(i / 4) + 1 and chapter.difficulty.tier == int(i / 4) + 1 and chapter.difficulty.newRules == 1, "chapter has gradual six-act learning budget %d" % (i + 1))
		check(chapter.protagonistId == ("zheng-zhilong" if i < 12 else "zheng-chenggong"), "single protagonist transition after chapter twelve %d" % (i + 1))
		for stage: Dictionary in chapter.stages:
			var projected: Dictionary = Catalog.stage(stage.id)
			check(projected.chapterId == chapter.id and projected.protagonistId == chapter.protagonistId and projected.year == chapter.year and projected.act == chapter.act and projected.difficulty == chapter.difficulty, "flattened stage retains its chapter context " + stage.id)
			check(projected.objectives == stage.objectives and projected.recovery == stage.recovery and projected.partialAllowed == stage.partialAllowed, "flattening retains real objective and recovery definitions " + stage.id)
	for pair in [["CH21", ["T01", "T02", "T03"]], ["CH22", ["T04", "T05"]], ["CH23", ["T06", "T07", "T08"]], ["CH24", ["T09", "T10"]]]:
		var stage_ids: Array = []
		for stage: Dictionary in Catalog.chapter(pair[0]).stages:
			stage_ids.append(stage.id)
		check(stage_ids == pair[1], "Taiwan stages belong to their exact chapter " + pair[0])
	var terminal: Dictionary = Catalog.stage("T10")
	var terminal_kinds: Array = []
	for objective: Dictionary in terminal.objectives:
		terminal_kinds.append(objective.kind)
	check(terminal_kinds == ["accept-terms", "evacuation-complete", "port-handover"] and not terminal.partialAllowed, "ending requires agreement, actual evacuation and handover")
	check(Catalog.stage("CH-12-S1").mode == "handoff" and not Catalog.stage("CH-12-S1").partialAllowed, "father-son handoff is mandatory")
	check(Catalog.stage("absent").is_empty() and Catalog.chapter("absent").is_empty(), "unknown identities return no fabricated definition")
	var modes: Array = []
	for stage: Dictionary in flattened:
		if not stage.mode in modes:
			modes.append(stage.mode)
		if stage.id.begins_with("T"):
			check(not stage.partialAllowed, "Taiwan mandatory milestone cannot settle partially " + stage.id)
	check(modes.size() == 8, "content covers all eight executor contracts")
	check(Catalog.chapter("CH09").regionIds.has("REG-03") and Catalog.chapter("CH10").regionIds.has("REG-06"), "Ryukyu and Malacca have distinct regional routes")
	var envoy_arrival := false
	for objective: Dictionary in Catalog.stage("CH-09-S1").objectives:
		if objective.kind == "escort-arrived" and objective.target == "ryukyu-envoy-vessel":
			envoy_arrival = true
	check(envoy_arrival, "Ryukyu rescue and permit cannot replace actual envoy-vessel arrival")
	check(Catalog.chapter("CH16").regionIds.has("REG-05") and Catalog.chapter("CH16").regionIds.has("REG-03") and Catalog.chapter("CH16").regionIds.has("REG-07"), "later optional trade connects Manila, Japan and Java")
	# Mutating any returned nested value must not corrupt later catalog reads.
	content.chapters[0].stages[0].objectives[0].required = 900
	flattened[0].difficulty.tier = 6
	var fetched_stage: Dictionary = Catalog.stage("CH-01-S1")
	fetched_stage.objectives[0].target = "forged-target"
	var fetched_chapter: Dictionary = Catalog.chapter("CH01")
	fetched_chapter.drama.want = "forged-drama"
	var fresh: Dictionary = Catalog.load_content().data
	check(fresh.chapters[0].stages[0].objectives[0].required == 1 and Catalog.stage("CH-01-S1").difficulty.tier == 1, "load and flattened results are detached deep copies")
	check(Catalog.stage("CH-01-S1").objectives[0].target != "forged-target" and Catalog.chapter("CH01").drama.want != "forged-drama", "individual stage and chapter results are detached deep copies")
	content = fresh
	for malformed: Variant in [null, [], "campaign", 1, true]:
		reject(malformed, "non-dictionary content rejected")
	for key: String in ["schemaVersion", "id", "title", "protagonists", "chapters"]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.erase(key)
		reject(mutant, "missing campaign field rejected " + key)
	for key: String in ["id", "order", "act", "title", "protagonistId", "year", "regionIds", "drama", "teaches", "reuses", "difficulty", "stages"]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].erase(key)
		reject(mutant, "missing chapter field rejected " + key)
	for key: String in ["id", "mode", "title", "briefing", "objectives", "recovery", "partialAllowed"]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].stages[0].erase(key)
		reject(mutant, "missing stage field rejected " + key)
	for key: String in ["id", "kind", "target", "required", "unit"]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].stages[0].objectives[0].erase(key)
		reject(mutant, "missing objective field rejected " + key)
	for value: Variant in [0, -1, 1.5, true, "1", INF, NAN, null]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].stages[0].objectives[0].required = value
		reject(mutant, "objective count must be finite positive integer " + str(value))
	for value: Variant in [0, 7, 1.5, true, "1", INF, NAN]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].difficulty.tier = value
		reject(mutant, "difficulty rejects invalid tier " + str(value))
	for value: Variant in [true, INF, NAN, "1623", null]:
		var mutant: Dictionary = content.duplicate(true)
		mutant.chapters[0].year = value
		reject(mutant, "chapter year rejects invalid numeric type " + str(value))
	var mutant: Dictionary = content.duplicate(true)
	mutant.chapters[23].stages.pop_back()
	reject(mutant, "missing terminal T10 rejected")
	mutant = content.duplicate(true)
	mutant.chapters[11].protagonistId = "zheng-chenggong"
	reject(mutant, "early protagonist handoff rejected")
	mutant = content.duplicate(true)
	for index in range(mutant.chapters[8].stages[0].objectives.size() - 1, -1, -1):
		if mutant.chapters[8].stages[0].objectives[index].kind == "escort-arrived":
			mutant.chapters[8].stages[0].objectives.remove_at(index)
	reject(mutant, "Ryukyu stage cannot omit actual envoy-vessel arrival")
	mutant = content.duplicate(true)
	for objective: Dictionary in mutant.chapters[8].stages[0].objectives:
		if objective.kind == "escort-arrived":
			objective.target = "unrelated-envoy-vessel"
	reject(mutant, "Ryukyu stage must bring the rescued envoy vessel to port")
	for recipient: String in ["zheng-zhilong", "nonexistent-recipient"]:
		mutant = content.duplicate(true)
		mutant.chapters[11].stages[0].objectives[0].target = recipient
		reject(mutant, "handoff recipient must be Zheng Chenggong " + recipient)
	mutant = content.duplicate(true)
	mutant.chapters[11].stages[0].objectives[0].required = 2
	reject(mutant, "handoff is exactly one actual manifest")
	mutant = content.duplicate(true)
	mutant.chapters[11].stages[0].objectives[0].unit = "silver"
	reject(mutant, "handoff unit must describe the manifest")
	mutant = content.duplicate(true)
	mutant.chapters[1].stages[0].id = "CH-01-S1"
	reject(mutant, "duplicate stage identity rejected")
	mutant = content.duplicate(true)
	mutant.chapters[1].stages[0].objectives[0].id = mutant.chapters[0].stages[0].objectives[0].id
	reject(mutant, "duplicate objective identity rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].difficulty.tier = 2
	reject(mutant, "valid but wrong learning tier rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].difficulty.newRules = 2
	reject(mutant, "chapter cannot silently expand new-rule burden")
	mutant = content.duplicate(true)
	mutant.chapters[0].difficulty.simultaneousObjectives = 4
	reject(mutant, "simultaneous objective burden bounded")
	mutant = content.duplicate(true)
	mutant.chapters[0].difficulty.pressure = "impossible"
	reject(mutant, "unknown pressure rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].stages[0].mode = "instant-victory"
	reject(mutant, "forged executor mode rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].stages[0].objectives[0].kind = "instant-victory"
	reject(mutant, "forged objective kind rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].regionIds = ["REG-99"]
	reject(mutant, "unknown world region rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].stages[0].recovery = "  "
	reject(mutant, "empty recovery path rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].stages[0].partialAllowed = 1
	reject(mutant, "partial flag requires boolean")
	mutant = content.duplicate(true)
	mutant.chapters[20].stages[0].partialAllowed = true
	reject(mutant, "mandatory Taiwan objective cannot become partial")
	mutant = content.duplicate(true)
	mutant.chapters[23].stages[1].objectives.pop_back()
	reject(mutant, "ending cannot omit actual port handover")
	mutant = content.duplicate(true)
	mutant.protagonists[1].id = "zheng-zhilong"
	reject(mutant, "duplicate protagonist rejected")
	mutant = content.duplicate(true)
	mutant.chapters[0].stages[0].objectives = []
	reject(mutant, "stages require actual objective definitions")
	finish()

func finish() -> void:
	print("STORY_CAMPAIGN_CATALOG assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures > 0 else 0)
