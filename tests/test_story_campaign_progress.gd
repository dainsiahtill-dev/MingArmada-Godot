extends SceneTree
## Synthetic trusted facts prove only the progress contract, never real gameplay.

const PROGRESS_PATH := "res://game/domain/story_campaign/progress.gd"
const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
var checks: int = 0
var failures: int = 0
var progress_script: GDScript
var stages: Array = []

func _init() -> void:
	call_deferred("_run")

func check(value: bool, label: String) -> bool:
	checks += 1
	if not value:
		failures += 1
		print("FAIL: ", label)
	return value

func _run() -> void:
	if not check(FileAccess.file_exists(PROGRESS_PATH), "mainline progress contract exists"):
		_finish()
		return
	progress_script = load(PROGRESS_PATH) as GDScript
	if not check(progress_script != null, "mainline progress contract loads"):
		_finish()
		return
	if not check(FileAccess.file_exists(CATALOG_PATH), "progress uses actual mainline catalog"):
		_finish()
		return
	var catalog_script: GDScript = load(CATALOG_PATH) as GDScript
	stages = catalog_script.call("stages")
	if not check(stages.size() == 30, "fixture covers twenty early stages and ten Taiwan stages"):
		_finish()
		return
	_test_initial_contract()
	_test_trusted_evidence()
	_test_partial_and_retreat()
	_test_all_stages_and_save_guards()
	_test_retry_rejects_old_attempt_callback()
	_test_repeated_failures_archive_without_blocking_mainline()
	_finish()

func _fixture(run_id: String = "fixture") -> RefCounted:
	var progress: RefCounted = progress_script.new()
	var configured: Dictionary = progress.call("configure", 1661, run_id)
	check(configured.get("ok", false), "deterministic progress configures: " + run_id)
	return progress

func _snapshot(progress: RefCounted) -> Dictionary:
	return progress.call("snapshot")

func _fact(stage: Dictionary, objective: Dictionary, run_id: String, suffix: String = "complete", attempt: int = 1) -> Dictionary:
	return {"id":str(stage.id) + ":" + str(objective.id) + ":" + suffix,"runId":run_id,"stageId":stage.id,"attempt":attempt,"objectiveId":objective.id,"progress":objective.required,"source":"world-snapshot"}

func _facts(stage: Dictionary, run_id: String, attempt: int = 1) -> Array:
	var facts: Array = []
	for objective: Dictionary in stage.objectives:
		facts.append(_fact(stage, objective, run_id, "complete", attempt))
	return facts

func _success(progress: RefCounted, facts: Array) -> void:
	check(progress.call("observe", facts).get("ok", false), "trusted fixture facts accepted")
	check(progress.call("settle", _snapshot(progress).revision, "success", true).get("ok", false), "full safe fixture result accepted")

func _same(a: Variant, b: Variant) -> bool:
	if typeof(a) in [TYPE_INT, TYPE_FLOAT] and typeof(b) in [TYPE_INT, TYPE_FLOAT]:
		return a == b
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key: Variant in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for index: int in a.size():
			if not _same(a[index], b[index]):
				return false
		return true
	return a == b

func _roundtrip(progress: RefCounted, label: String) -> void:
	var restored: RefCounted = progress_script.new()
	var raw: String = progress.call("serialize")
	var result: Dictionary = restored.call("restore", raw)
	check(not raw.is_empty() and result.get("ok", false) and _same(_snapshot(restored), _snapshot(progress)), "strict save roundtrip: " + label)

func _reject_save(progress: RefCounted, forged: Dictionary, label: String) -> void:
	var before: Dictionary = _snapshot(progress)
	var result: Dictionary = progress.call("restore", JSON.stringify(forged))
	check(not result.get("ok", true) and _snapshot(progress) == before, "atomic invalid save rejection: " + label)

func _reject_observation(progress: RefCounted, facts: Array, label: String) -> void:
	var before: Dictionary = _snapshot(progress)
	var result: Dictionary = progress.call("observe", facts)
	check(not result.get("ok", true) and _snapshot(progress) == before, "atomic invalid observation rejection: " + label)

func _test_initial_contract() -> void:
	var progress: RefCounted = _fixture()
	var initial: Dictionary = _snapshot(progress)
	check(initial.stageIndex == 0 and initial.phase == "briefing" and initial.attempt == 1 and initial.revision == 0, "first stage briefing has deterministic counters")
	check(initial.campaignId == "zheng-family-v1" and initial.protagonistId == "zheng-zhilong" and not initial.handoff.done, "father starts campaign before handoff")
	var expected_keys: Array = ["schemaVersion","campaignId","runId","seed","revision","stageIndex","phase","attempt","protagonistId","objectiveProgress","seenEvidence","receipts","failureArchive","handoff"]
	var keys: Array = initial.keys()
	keys.sort()
	expected_keys.sort()
	check(keys == expected_keys, "save owns exactly progress fields and no world money, cargo, healing or ships")
	check(initial.failureArchive.is_empty(), "new campaign has no invented archived outcomes")
	var inspected: Dictionary = progress.call("inspection_snapshot")
	check(inspected.scope == "progress-contract-only; real-world adapters pending" and inspected.currentStage.id == "CH-01-S1", "inspection labels synthetic progress scope and current catalog stage")
	inspected.state.stageIndex = 29
	inspected.currentStage.objectives.clear()
	var detached: Dictionary = progress.call("snapshot")
	detached.handoff.done = true
	detached.objectiveProgress.clear()
	check(_snapshot(progress) == initial and not progress.call("inspection_snapshot").currentStage.objectives.is_empty(), "state and inspection callers cannot mutate authoritative progress or catalog")
	check(not progress.call("configure", 1661, "").get("ok", true) and _snapshot(progress) == initial, "invalid reconfigure is atomic")
	check(not progress.call("begin", 99).get("ok", true) and _snapshot(progress) == initial, "begin rejects stale revision")
	check(not progress.call("continue_story", 0).get("ok", true) and not progress.call("retry", 0).get("ok", true), "briefing cannot skip stage or retry unattempted work")
	_reject_observation(progress, _facts(stages[0], "fixture"), "briefing has no active evidence channel")
	_roundtrip(progress, "initial")
	for mutation: String in ["extra-key","schema","seed-bool","seed-fraction","revision-bool","revision-future","stage-skipped","forged-ending","early-son","extra-objective","progress-negative","progress-fraction","evidence-without-progress","early-handoff","unknown-phase"]:
		var forged: Dictionary = initial.duplicate(true)
		var first_objective: String = str(stages[0].objectives[0].id)
		match mutation:
			"extra-key": forged.worldMoney = 100
			"schema": forged.schemaVersion = 2
			"seed-bool": forged.seed = true
			"seed-fraction": forged.seed = 1661.5
			"revision-bool": forged.revision = true
			"revision-future": forged.revision = 100000
			"stage-skipped": forged.stageIndex = 1
			"forged-ending":
				forged.stageIndex = 30
				forged.phase = "complete"
			"early-son": forged.protagonistId = "zheng-chenggong"
			"extra-objective": forged.objectiveProgress.fake = 1
			"progress-negative": forged.objectiveProgress[first_objective] = -1
			"progress-fraction": forged.objectiveProgress[first_objective] = 0.5
			"evidence-without-progress":
				var fact: Dictionary = _fact(stages[0], stages[0].objectives[0], "fixture")
				forged.seenEvidence[fact.id] = fact
			"early-handoff": forged.handoff = {"done":true,"receiptId":"forged","from":"zheng-zhilong","to":"zheng-chenggong"}
			"unknown-phase": forged.phase = "won"
		_reject_save(progress, forged, mutation)
	var before: Dictionary = _snapshot(progress)
	check(not progress.call("restore", "{broken").get("ok", true) and not progress.call("restore", "[]").get("ok", true) and _snapshot(progress) == before, "malformed JSON and non-object restore preserve existing state")

func _test_trusted_evidence() -> void:
	var progress: RefCounted = _fixture("evidence")
	check(progress.call("begin", 0).get("ok", false), "briefing begins with expected revision")
	var active: Dictionary = _snapshot(progress)
	check(active.phase == "active" and active.revision == 1, "begin records active transition")
	check(not progress.call("begin", 1).get("ok", true) and not progress.call("settle", 1, "success", true).get("ok", true) and _snapshot(progress) == active, "active task cannot restart or win without objectives")
	check(progress.call("observe", []).get("ok", false) and _snapshot(progress) == active, "empty observation is idempotent")
	var first: Dictionary = _fact(stages[0], stages[0].objectives[0], "evidence")
	for mutation: String in ["wrong-run","wrong-stage","wrong-objective","wrong-attempt","missing-attempt","attempt-bool","attempt-fraction","bad-source","missing-source","extra-key","progress-bool","progress-nan","progress-fraction","progress-negative","progress-over","id-empty","id-nonstring"]:
		var bad: Dictionary = first.duplicate(true)
		match mutation:
			"wrong-run": bad.runId = "another-run"
			"wrong-stage": bad.stageId = "T10"
			"wrong-objective": bad.objectiveId = "fake"
			"wrong-attempt": bad.attempt = 2
			"missing-attempt": bad.erase("attempt")
			"attempt-bool": bad.attempt = true
			"attempt-fraction": bad.attempt = 1.5
			"bad-source": bad.source = "ui-click"
			"missing-source": bad.erase("source")
			"extra-key": bad.pretendReward = 50
			"progress-bool": bad.progress = true
			"progress-nan": bad.progress = NAN
			"progress-fraction": bad.progress = 0.5
			"progress-negative": bad.progress = -1
			"progress-over": bad.progress = int(first.progress) + 1
			"id-empty": bad.id = ""
			"id-nonstring": bad.id = 12
		_reject_observation(progress, [first, bad], mutation)
	check(progress.call("observe", [first]).get("ok", false), "trusted normalized internal fact updates objective")
	var observed: Dictionary = _snapshot(progress)
	check(observed.revision == 2 and observed.seenEvidence.size() == 1 and observed.objectiveProgress[first.objectiveId] == first.progress, "unique fact increments revision once and absolute objective progress")
	first.progress = 0
	check(_snapshot(progress) == observed, "observation input is detached after commit")
	var replay: Dictionary = observed.seenEvidence.values()[0].duplicate(true)
	check(progress.call("observe", [replay, replay]).get("ok", false) and _snapshot(progress) == observed, "identical repeated evidence cannot duplicate progress or revision")
	var changed: Dictionary = replay.duplicate(true)
	changed.source = "naval-snapshot"
	_reject_observation(progress, [changed], "same id with changed original fact")
	var lower: Dictionary = replay.duplicate(true)
	lower.id += ":older-absolute"
	lower.progress = 0
	check(progress.call("observe", [lower]).get("ok", false) and _snapshot(progress).objectiveProgress[replay.objectiveId] == replay.progress, "older absolute observation cannot subtract accepted objective progress")
	check(not progress.call("settle", _snapshot(progress).revision, "success", false).get("ok", true), "unsafe location blocks successful settlement")
	_roundtrip(progress, "active evidence with older absolute fact")
	_success(progress, _facts(stages[0], "evidence"))
	var review: Dictionary = _snapshot(progress)
	check(review.phase == "review" and review.receipts.size() == 1 and review.receipts[0].outcome == "success", "one full result creates one durable review receipt")
	check(not progress.call("settle", review.revision, "success", true).get("ok", true) and _snapshot(progress) == review, "repeated settlement cannot duplicate receipt")
	check(not progress.call("retry", review.revision).get("ok", true) and not progress.call("continue_story", review.revision - 1).get("ok", true) and _snapshot(progress) == review, "success cannot retry or continue with stale revision")
	_reject_observation(progress, [replay], "review evidence channel closed")
	_roundtrip(progress, "successful review")
	for mutation: String in ["receipt-duplicate","receipt-id","receipt-revision","receipt-stage","receipt-attempt","receipt-progress","receipt-source","receipt-outcome","receipt-unsafe","receipt-extra","fact-progress","attempt-skipped"]:
		var forged: Dictionary = review.duplicate(true)
		var receipt: Dictionary = forged.receipts[0]
		match mutation:
			"receipt-duplicate": forged.receipts.append(receipt.duplicate(true))
			"receipt-id": receipt.id = "foreign"
			"receipt-revision": receipt.revision += 1
			"receipt-stage": receipt.stageId = "T10"
			"receipt-attempt": receipt.attempt = 2
			"receipt-progress": receipt.objectiveProgress[replay.objectiveId] = 0
			"receipt-source": receipt.evidence[replay.id].source = "ui-click"
			"receipt-outcome": receipt.outcome = "partial"
			"receipt-unsafe": receipt.safe = false
			"receipt-extra": receipt.money = 200
			"fact-progress": forged.seenEvidence[replay.id].progress = 0
			"attempt-skipped": forged.attempt = 2
		_reject_save(progress, forged, mutation)

func _test_partial_and_retreat() -> void:
	var progress: RefCounted = _fixture("partial")
	var chosen: int = -1
	for index: int in stages.size():
		if stages[index].partialAllowed:
			chosen = index
			break
	if not check(chosen >= 0, "catalog contains explicit partial-success recovery path"):
		return
	for index: int in chosen:
		check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "fixture advances to partial-enabled task")
		_success(progress, _facts(stages[index], "partial"))
		check(progress.call("continue_story", _snapshot(progress).revision).get("ok", false), "successful earlier task advances exactly once")
	check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "partial-enabled task starts")
	var before: Dictionary = _snapshot(progress)
	check(not progress.call("settle", before.revision, "partial", true).get("ok", true) and _snapshot(progress) == before, "zero progress cannot be called partial success")
	var fact: Dictionary = _fact(stages[chosen], stages[chosen].objectives[0], "partial", "partial")
	fact.progress = 1
	check(progress.call("observe", [fact]).get("ok", false), "partial fixture records nonzero actual objective evidence")
	check(progress.call("settle", _snapshot(progress).revision, "partial", true).get("ok", false), "permitted partial outcome records recovery")
	var recovery: Dictionary = _snapshot(progress)
	check(recovery.phase == "recovery" and recovery.stageIndex == chosen and recovery.receipts.back().outcome == "partial", "partial outcome never advances chapter or stage")
	check(not progress.call("continue_story", recovery.revision).get("ok", true) and _snapshot(progress) == recovery, "recovery cannot continue as full victory")
	_roundtrip(progress, "partial recovery")
	check(progress.call("retry", recovery.revision).get("ok", false), "recovery opens another attempt without rewriting world assets")
	var retry: Dictionary = _snapshot(progress)
	check(retry.phase == "briefing" and retry.stageIndex == chosen and retry.attempt == 2 and retry.seenEvidence.is_empty(), "retry clears only current progress and increments attempt")
	for value: Variant in retry.objectiveProgress.values():
		check(value == 0, "retry does not inherit successful objective claims")
	check(progress.call("begin", retry.revision).get("ok", false), "recovery retry starts")
	check(progress.call("settle", _snapshot(progress).revision, "retreat", false).get("ok", false), "retreat records honest outcome while unsafe")
	check(_snapshot(progress).receipts.back().outcome == "retreat" and _snapshot(progress).phase == "recovery" and _snapshot(progress).stageIndex == chosen, "retreat preserves stage and its own result")
	_roundtrip(progress, "retreat recovery")
	var forbidden: RefCounted = _fixture("no-partial")
	if not stages[0].partialAllowed:
		check(forbidden.call("begin", 0).get("ok", false), "nonpartial stage begins")
		check(forbidden.call("observe", _facts(stages[0], "no-partial")).get("ok", false), "nonpartial task receives evidence")
		check(not forbidden.call("settle", _snapshot(forbidden).revision, "partial", true).get("ok", true), "stage without partial permission rejects partial outcome")

func _test_all_stages_and_save_guards() -> void:
	var progress: RefCounted = _fixture("whole-mainline")
	var handoff_id: String = ""
	for index: int in stages.size():
		var stage: Dictionary = stages[index]
		var before: Dictionary = _snapshot(progress)
		check(before.stageIndex == index and before.phase == "briefing", "ordered stage is reachable without skip: " + str(stage.id))
		check(before.protagonistId == ("zheng-zhilong" if index < 12 else "zheng-chenggong"), "protagonist changes only after CH12: " + str(stage.id))
		check(progress.call("begin", before.revision).get("ok", false), "first attempt begins: " + str(stage.id))
		check(progress.call("settle", _snapshot(progress).revision, "failure", false).get("ok", false), "every stage can record honest failure: " + str(stage.id))
		var failed: Dictionary = _snapshot(progress)
		check(failed.phase == "recovery" and failed.stageIndex == index and failed.receipts.back().outcome == "failure", "failure retains current stage: " + str(stage.id))
		_roundtrip(progress, str(stage.id) + " failure")
		check(progress.call("retry", failed.revision).get("ok", false), "every failed stage retries: " + str(stage.id))
		check(_snapshot(progress).attempt == 2 and _snapshot(progress).stageIndex == index, "retry changes only attempt: " + str(stage.id))
		_roundtrip(progress, str(stage.id) + " retry briefing")
		check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "second attempt begins: " + str(stage.id))
		_roundtrip(progress, str(stage.id) + " active")
		var facts: Array = _facts(stage, "whole-mainline", 2)
		if str(stage.id) == "T10":
			var no_handover: Array = []
			for fact: Dictionary in facts:
				var objective_kind: String = ""
				for objective: Dictionary in stage.objectives:
					if objective.id == fact.objectiveId:
						objective_kind = str(objective.kind)
				if objective_kind != "port-handover":
					no_handover.append(fact)
			check(no_handover.size() < facts.size(), "T10 fixture requires actual port-handover objective")
			check(progress.call("observe", no_handover).get("ok", false), "T10 other obligations can be observed separately")
			var missing: Dictionary = _snapshot(progress)
			check(not progress.call("settle", missing.revision, "success", true).get("ok", true) and _snapshot(progress) == missing, "T10 cannot end campaign before port handover")
		_success(progress, facts)
		_roundtrip(progress, str(stage.id) + " review")
		var review: Dictionary = _snapshot(progress)
		check(review.phase == "review" and review.stageIndex == index and review.receipts.size() == (index + 1) * 2, "success waits for explicit continuation and has unique attempt receipt: " + str(stage.id))
		if index == 11:
			check(not review.handoff.done and review.protagonistId == "zheng-zhilong", "CH12 review retains father before single progress handoff")
		check(progress.call("continue_story", review.revision).get("ok", false), "only full review continues: " + str(stage.id))
		var continued: Dictionary = _snapshot(progress)
		check(continued.stageIndex == index + 1 and continued.attempt == 1, "continuation advances exactly one stage and resets attempt")
		if index >= 11:
			check(continued.handoff.done and continued.handoff.from == "zheng-zhilong" and continued.handoff.to == "zheng-chenggong", "handoff records identities without invented world transfer")
			if index == 11:
				handoff_id = str(continued.handoff.receiptId)
			check(not handoff_id.is_empty() and continued.handoff.receiptId == handoff_id, "handoff receipt remains exactly once throughout son stages")
		_roundtrip(progress, str(stage.id) + " continued")
	var complete: Dictionary = _snapshot(progress)
	check(complete.phase == "complete" and complete.stageIndex == 30 and complete.receipts.size() == 60 and complete.protagonistId == "zheng-chenggong", "only thirty successful stage receipts and T10 continuation complete mainline")
	check(complete.objectiveProgress.is_empty() and complete.seenEvidence.is_empty() and progress.call("inspection_snapshot").currentStage.is_empty(), "complete state has no fabricated thirty-first task")
	check(not progress.call("begin", complete.revision).get("ok", true) and not progress.call("continue_story", complete.revision).get("ok", true) and not progress.call("retry", complete.revision).get("ok", true) and _snapshot(progress) == complete, "terminal progress cannot begin, retry or settle another chapter")
	for mutation: String in ["lost-handoff","foreign-handoff","skipped-history","success-without-evidence","duplicate-id","wrong-son","ending-without-final","final-failure","unknown-receipt-key"]:
		var forged: Dictionary = complete.duplicate(true)
		match mutation:
			"lost-handoff": forged.handoff = {"done":false,"receiptId":"","from":"","to":""}
			"foreign-handoff": forged.handoff.receiptId = "other-run:handoff"
			"skipped-history": forged.receipts.remove_at(2)
			"success-without-evidence": forged.receipts.back().evidence.clear()
			"duplicate-id": forged.receipts.back().id = forged.receipts[0].id
			"wrong-son": forged.protagonistId = "zheng-zhilong"
			"ending-without-final": forged.receipts.pop_back()
			"final-failure": forged.receipts.back().outcome = "failure"
			"unknown-receipt-key": forged.receipts.back().restoredShips = 3
		_reject_save(progress, forged, mutation)

func _test_retry_rejects_old_attempt_callback() -> void:
	var progress: RefCounted = _fixture("late-callback")
	var late_callback: Array = _facts(stages[0], "late-callback")
	check(progress.call("begin", 0).get("ok", false), "first attempt starts before asynchronous result is pending")
	check(progress.call("settle", _snapshot(progress).revision, "failure", false).get("ok", false), "first attempt fails before its delayed callback arrives")
	check(progress.call("retry", _snapshot(progress).revision).get("ok", false), "failed asynchronous attempt retries")
	check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "second attempt begins before old callback arrives")
	_reject_observation(progress, late_callback, "delayed callback from failed attempt cannot fulfill new attempt")
	var waiting: Dictionary = _snapshot(progress)
	check(not progress.call("settle", waiting.revision, "success", true).get("ok", true) and _snapshot(progress) == waiting, "new attempt still requires its own actual evidence after old callback")
	var missing_attempt: Dictionary = _fact(stages[0], stages[0].objectives[0], "late-callback")
	missing_attempt.erase("attempt")
	_reject_observation(progress, [missing_attempt], "trusted callback must identify its attempt")
	var current_facts: Array = _facts(stages[0], "late-callback", 2)
	check(progress.call("observe", current_facts).get("ok", false), "current-attempt callback remains accepted after retry")
	check(progress.call("settle", _snapshot(progress).revision, "success", true).get("ok", false), "only current-attempt evidence can settle retried task")
	_roundtrip(progress, "current attempt after rejecting old callback")
	var settled: Dictionary = _snapshot(progress)
	var forged: Dictionary = settled.duplicate(true)
	if forged.seenEvidence.size() > 0:
		forged.seenEvidence.values()[0]["attempt"] = 1
		_reject_save(progress, forged, "stored current evidence cannot claim previous attempt")
	forged = settled.duplicate(true)
	if forged.receipts.back().evidence.size() > 0:
		forged.receipts.back().evidence.values()[0]["attempt"] = 1
		_reject_save(progress, forged, "immutable receipt evidence must belong to receipt attempt")

func _test_repeated_failures_archive_without_blocking_mainline() -> void:
	var progress: RefCounted = _fixture("many-failures")
	for index: int in 300:
		if not check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "repeated failure attempt can begin: " + str(index + 1)):
			return
		var fact: Dictionary = _fact(stages[0], stages[0].objectives[0], "many-failures", "failure-" + str(index + 1), int(_snapshot(progress).attempt))
		if not check(progress.call("observe", [fact]).get("ok", false), "each failed attempt records its own evidence: " + str(index + 1)):
			return
		if not check(progress.call("settle", _snapshot(progress).revision, "failure", false).get("ok", false), "more than 256 outcomes remain settleable: " + str(index + 1)):
			return
		if not check(progress.call("retry", _snapshot(progress).revision).get("ok", false), "more than 256 failures remain retryable: " + str(index + 1)):
			return
	var recovered: Dictionary = _snapshot(progress)
	check(recovered.stageIndex == 0 and recovered.attempt == 301 and recovered.phase == "briefing" and not recovered.handoff.done, "three hundred failures neither advance stage nor consume next stage")
	if not check(recovered.get("failureArchive", {}) is Dictionary and not recovered.get("failureArchive", {}).is_empty() and recovered.receipts.size() <= 256, "failed history compacts into bounded per-stage archive"):
		return
	var archive: Dictionary = recovered.failureArchive["CH-01-S1"]
	check(archive.attempts > 0 and archive.evidenceCount == archive.attempts and archive.outcomes.failure == archive.attempts and archive.outcomes.partial == 0 and archive.outcomes.retreat == 0, "archive retains failed attempt and evidence totals without inventing success")
	_roundtrip(progress, "three hundred failures with compacted history")
	for mutation: String in ["archive-stage","archive-attempts","archive-evidence","archive-revision","archive-success","archive-outcome-count","archive-extra","archive-cannot-skip","archive-cannot-end"]:
		var forged: Dictionary = recovered.duplicate(true)
		var bad: Dictionary = forged.failureArchive["CH-01-S1"]
		match mutation:
			"archive-stage": bad.stageId = "T10"
			"archive-attempts": bad.attempts += 1
			"archive-evidence": bad.evidenceCount += 1
			"archive-revision": bad.throughRevision += 1
			"archive-success": bad.outcomes.success = 1
			"archive-outcome-count": bad.outcomes.failure -= 1
			"archive-extra": bad.objectiveProgress = {"forged":1}
			"archive-cannot-skip": forged.stageIndex = 1
			"archive-cannot-end":
				forged.stageIndex = 30
				forged.phase = "complete"
		_reject_save(progress, forged, mutation)
	for index: int in stages.size():
		if not check(progress.call("begin", _snapshot(progress).revision).get("ok", false), "mainline remains beginable after many failures: " + str(stages[index].id)):
			return
		var facts: Array = _facts(stages[index], "many-failures", int(_snapshot(progress).attempt))
		_success(progress, facts)
		if not check(progress.call("continue_story", _snapshot(progress).revision).get("ok", false), "mainline remains continueable after many failures: " + str(stages[index].id)):
			return
		_roundtrip(progress, "archived failures then " + str(stages[index].id))
	var complete: Dictionary = _snapshot(progress)
	var successes: int = 0
	var failures_retained: int = 0
	for receipt: Dictionary in complete.receipts:
		if receipt.outcome == "success":
			successes += 1
		else:
			failures_retained += 1
	var archived: Dictionary = complete.failureArchive["CH-01-S1"]
	check(complete.phase == "complete" and complete.stageIndex == 30 and successes == 30 and complete.receipts.size() <= 256 and failures_retained + int(archived.attempts) == 300, "three hundred failures still permit all thirty successful stages with every success retained")
	_roundtrip(progress, "complete campaign with bounded failed history")

func _finish() -> void:
	print("STORY_CAMPAIGN_PROGRESS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)
