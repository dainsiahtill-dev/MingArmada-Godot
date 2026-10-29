extends RefCounted
## Progress only. Trusted internal adapter facts are not a player command API.
## This module never owns world money, ships, cargo, crew, healing or rewards.

const CATALOG_PATH := "res://game/domain/story_campaign/catalog.gd"
const CAMPAIGN_ID := "zheng-family-v1"
const SCOPE := "progress-contract-only; real-world adapters pending"
const MAX_FACTS := 64
const MAX_RECEIPTS := 256
# Defensive numeric boundary, independent of the bounded raw-history window.
# A stage permits one million attempts; reaching it never grants a victory.
const MAX_ATTEMPTS := 1000000
const MAX_REVISION := MAX_ATTEMPTS * (MAX_FACTS + 3) * 30
const MAX_SAVE_BYTES := 16777216
const STATE_KEYS := ["schemaVersion","campaignId","runId","seed","revision","stageIndex","phase","attempt","protagonistId","objectiveProgress","seenEvidence","receipts","failureArchive","handoff"]
const FACT_KEYS := ["id","runId","stageId","attempt","objectiveId","progress","source"]
const RECEIPT_KEYS := ["id","runId","stageId","stageIndex","attempt","outcome","safe","objectiveProgress","evidence","revision"]
const ARCHIVE_KEYS := ["stageId","stageIndex","attempts","evidenceCount","outcomes","throughRevision"]
const FAILURE_OUTCOMES := ["failure","partial","retreat"]
const HANDOFF_KEYS := ["done","receiptId","from","to"]
const SOURCES := ["naval-snapshot","business-receipt","encounter-result","world-snapshot"]
const PHASES := ["briefing","active","review","recovery","complete"]
const OUTCOMES := ["success","partial","failure","retreat"]

var _state: Dictionary = {}
var _stages: Array = []

func configure(seed: int = 1661, run_id: String = "fixture") -> Dictionary:
	if not _token(run_id, 96) or not _integer(seed, -2147483648, 2147483647):
		return _error("invalid campaign seed or run id")
	var catalog: Dictionary = _load_catalog()
	if not catalog.ok:
		return _error(str(catalog.reason))
	var stages: Array = catalog.stages
	var initial: Dictionary = {"schemaVersion":1,"campaignId":CAMPAIGN_ID,"runId":run_id,"seed":seed,"revision":0,"stageIndex":0,"phase":"briefing","attempt":1,"protagonistId":stages[0].protagonistId,"objectiveProgress":_empty_progress(stages[0]),"seenEvidence":{},"receipts":[],"failureArchive":{},"handoff":_empty_handoff()}
	_stages = stages
	_state = initial
	return _accepted(true)

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func inspection_snapshot() -> Dictionary:
	var stage: Dictionary = {}
	if not _state.is_empty() and int(_state.stageIndex) < _stages.size():
		stage = _stages[int(_state.stageIndex)].duplicate(true)
	return {"state":snapshot(),"currentStage":stage,"scope":SCOPE}

func begin(expected_revision: int) -> Dictionary:
	var guard: Dictionary = _guard(expected_revision, "briefing")
	if not guard.ok:
		return guard
	_state.phase = "active"
	_state.revision += 1
	return _accepted(true)

func observe(facts: Array) -> Dictionary:
	if _state.is_empty() or _state.phase != "active":
		return _error("evidence requires an active stage")
	if facts.size() > MAX_FACTS:
		return _error("evidence batch exceeds limit")
	var stage: Dictionary = _stages[int(_state.stageIndex)]
	var next: Dictionary = _state.duplicate(true)
	var added: int = 0
	for value: Variant in facts:
		var validated: Dictionary = _validate_fact(value, stage, str(_state.runId), int(_state.attempt))
		if not validated.ok:
			return _error(str(validated.reason))
		var fact: Dictionary = validated.fact
		var id: String = str(fact.id)
		if next.seenEvidence.has(id):
			if next.seenEvidence[id] != fact:
				return _error("evidence id conflicts with original fact")
			continue
		if next.seenEvidence.size() >= MAX_FACTS:
			return _error("stage evidence exceeds limit")
		next.seenEvidence[id] = fact
		next.objectiveProgress[fact.objectiveId] = maxi(int(next.objectiveProgress[fact.objectiveId]), int(fact.progress))
		added += 1
	if added == 0:
		return _accepted(false)
	# One revision per unique accepted fact makes the saved revision reproducible
	# from retained original facts, independently of observation batch size.
	next.revision += added
	_state = next
	return _accepted(true)

func settle(expected_revision: int, outcome: String, safe: bool) -> Dictionary:
	var guard: Dictionary = _guard(expected_revision, "active")
	if not guard.ok:
		return guard
	var stage: Dictionary = _stages[int(_state.stageIndex)]
	if not _outcome_valid(outcome, safe, _state.objectiveProgress, stage):
		return _error("outcome lacks required objectives, safety or partial permission")
	var next: Dictionary = _state.duplicate(true)
	if not _make_receipt_room(next):
		return _error("no retried failure available for bounded history archive")
	var revision: int = int(_state.revision) + 1
	var receipt: Dictionary = {"id":_receipt_id(str(_state.runId), str(stage.id), int(_state.attempt)),"runId":_state.runId,"stageId":stage.id,"stageIndex":_state.stageIndex,"attempt":_state.attempt,"outcome":outcome,"safe":safe,"objectiveProgress":_state.objectiveProgress.duplicate(true),"evidence":_state.seenEvidence.duplicate(true),"revision":revision}
	next.receipts.append(receipt)
	next.revision = revision
	next.phase = "review" if outcome == "success" else "recovery"
	_state = next
	var result: Dictionary = _accepted(true)
	result.receipt = receipt.duplicate(true)
	return result

func continue_story(expected_revision: int) -> Dictionary:
	var guard: Dictionary = _guard(expected_revision, "review")
	if not guard.ok:
		return guard
	var next_index: int = int(_state.stageIndex) + 1
	_state.stageIndex = next_index
	_state.attempt = 1
	_state.revision += 1
	_state.seenEvidence = {}
	_state.handoff = _handoff_for(next_index, _state.receipts)
	if next_index == _stages.size():
		_state.phase = "complete"
		_state.objectiveProgress = {}
	else:
		_state.phase = "briefing"
		_state.protagonistId = _stages[next_index].protagonistId
		_state.objectiveProgress = _empty_progress(_stages[next_index])
	return _accepted(true)

func retry(expected_revision: int) -> Dictionary:
	var guard: Dictionary = _guard(expected_revision, "recovery")
	if not guard.ok:
		return guard
	if int(_state.attempt) >= MAX_ATTEMPTS:
		return _error("campaign attempt limit reached")
	_state.attempt += 1
	_state.revision += 1
	_state.phase = "briefing"
	_state.objectiveProgress = _empty_progress(_stages[int(_state.stageIndex)])
	_state.seenEvidence = {}
	return _accepted(true)

func serialize() -> String:
	if _state.is_empty():
		return ""
	return JSON.stringify(_state)

func restore(raw: String) -> Dictionary:
	if raw.is_empty() or raw.to_utf8_buffer().size() > MAX_SAVE_BYTES:
		return _error("save is empty or exceeds limit")
	var parser: JSON = JSON.new()
	if parser.parse(raw) != OK:
		return _error("invalid save JSON")
	var catalog: Dictionary = _load_catalog()
	if not catalog.ok:
		return _error(str(catalog.reason))
	var validated: Dictionary = _validate_state(parser.data, catalog.stages)
	if not validated.ok:
		return _error(str(validated.reason))
	# Both assignments follow complete validation. A rejected save preserves the
	# existing state, cached catalog and all previously accepted receipts.
	_stages = catalog.stages
	_state = validated.state
	return _accepted(true)

func _load_catalog() -> Dictionary:
	if not FileAccess.file_exists(CATALOG_PATH):
		return {"ok":false,"reason":"mainline catalog unavailable"}
	var script: GDScript = load(CATALOG_PATH) as GDScript
	if script == null:
		return {"ok":false,"reason":"mainline catalog cannot load"}
	var content: Dictionary = script.call("load_content")
	if not content.get("ok", false):
		return {"ok":false,"reason":"mainline catalog invalid: " + str(content.get("reason", "unknown"))}
	var stages: Array = script.call("stages")
	if stages.size() != 30:
		return {"ok":false,"reason":"mainline requires thirty ordered stages"}
	return {"ok":true,"stages":stages.duplicate(true)}

func _guard(expected_revision: int, phase: String) -> Dictionary:
	if _state.is_empty():
		return _error("progress is not configured")
	if expected_revision != int(_state.revision):
		return _error("stale progress revision")
	if _state.phase != phase:
		return _error("operation requires " + phase)
	return {"ok":true,"reason":""}

func _accepted(changed: bool) -> Dictionary:
	return {"ok":true,"reason":"","changed":changed,"revision":int(_state.get("revision", 0))}

func _error(reason: String) -> Dictionary:
	return {"ok":false,"reason":reason,"changed":false,"revision":int(_state.get("revision", 0))}

func _token(value: Variant, maximum: int) -> bool:
	if not value is String or value.is_empty() or value.length() > maximum or value.strip_edges() != value:
		return false
	for index: int in value.length():
		if value.unicode_at(index) < 32 or value.unicode_at(index) == 127:
			return false
	return true

func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	if typeof(value) == TYPE_INT:
		return value >= minimum and value <= maximum
	if typeof(value) == TYPE_FLOAT:
		return is_finite(value) and value == floor(value) and value >= minimum and value <= maximum
	return false

func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true

func _empty_progress(stage: Dictionary) -> Dictionary:
	var progress: Dictionary = {}
	for objective: Dictionary in stage.objectives:
		progress[objective.id] = 0
	return progress

func _empty_handoff() -> Dictionary:
	return {"done":false,"receiptId":"","from":"","to":""}

func _handoff_for(stage_index: int, receipts: Array) -> Dictionary:
	if stage_index < 12:
		return _empty_handoff()
	for receipt: Dictionary in receipts:
		if receipt.stageId == "CH-12-S1" and receipt.outcome == "success":
			return {"done":true,"receiptId":str(receipt.id) + ":handoff","from":"zheng-zhilong","to":"zheng-chenggong"}
	return _empty_handoff()

func _receipt_id(run_id: String, stage_id: String, attempt: int) -> String:
	return run_id + ":" + stage_id + ":" + str(attempt)

func _make_receipt_room(state: Dictionary) -> bool:
	if state.receipts.size() < MAX_RECEIPTS:
		return true
	# Only old, already-retried non-success attempts may lose their raw facts.
	# Every success remains in the ordered prefix and still proves its objectives.
	for index: int in state.receipts.size():
		var receipt: Dictionary = state.receipts[index]
		if receipt.outcome == "success":
			continue
		var retried: bool = int(receipt.stageIndex) < int(state.stageIndex) or (receipt.stageIndex == state.stageIndex and int(receipt.attempt) < int(state.attempt))
		if not retried:
			continue
		var stage_id: String = str(receipt.stageId)
		var archive: Dictionary = state.failureArchive.get(stage_id, {"stageId":stage_id,"stageIndex":receipt.stageIndex,"attempts":0,"evidenceCount":0,"outcomes":{"failure":0,"partial":0,"retreat":0},"throughRevision":0})
		if int(receipt.attempt) != int(archive.attempts) + 1:
			return false
		archive.attempts += 1
		archive.evidenceCount += receipt.evidence.size()
		archive.outcomes[receipt.outcome] += 1
		archive.throughRevision = receipt.revision
		state.failureArchive[stage_id] = archive
		state.receipts.remove_at(index)
		return true
	return false

func _validate_fact(value: Variant, stage: Dictionary, run_id: String, attempt: int) -> Dictionary:
	if not _keys(value, FACT_KEYS):
		return {"ok":false,"reason":"fact fields do not match trusted fact schema"}
	var fact: Dictionary = value
	if not _token(fact.id, 160) or not fact.runId is String or fact.runId != run_id or not fact.stageId is String or fact.stageId != stage.id:
		return {"ok":false,"reason":"fact identity belongs to another run or stage"}
	if not _integer(fact.attempt, attempt, attempt):
		return {"ok":false,"reason":"fact belongs to another stage attempt"}
	if not fact.source is String or not SOURCES.has(fact.source) or not fact.objectiveId is String:
		return {"ok":false,"reason":"fact source or objective is invalid"}
	var objective: Dictionary = {}
	for candidate: Dictionary in stage.objectives:
		if candidate.id == fact.objectiveId:
			objective = candidate
			break
	if objective.is_empty() or not _integer(fact.progress, 0, int(objective.required)):
		return {"ok":false,"reason":"fact progress is not a bounded absolute objective count"}
	var normalized: Dictionary = fact.duplicate(true)
	normalized.attempt = attempt
	normalized.progress = int(fact.progress)
	return {"ok":true,"fact":normalized}

func _validate_evidence(value: Variant, stage: Dictionary, run_id: String, attempt: int) -> Dictionary:
	if not value is Dictionary or value.size() > MAX_FACTS:
		return {"ok":false,"reason":"evidence map invalid or exceeds limit"}
	var evidence: Dictionary = {}
	var progress: Dictionary = _empty_progress(stage)
	for key: Variant in value:
		var validated: Dictionary = _validate_fact(value[key], stage, run_id, attempt)
		if not validated.ok:
			return validated
		var fact: Dictionary = validated.fact
		if not key is String or key != fact.id:
			return {"ok":false,"reason":"evidence map key differs from original fact id"}
		evidence[key] = fact
		progress[fact.objectiveId] = maxi(int(progress[fact.objectiveId]), int(fact.progress))
	return {"ok":true,"evidence":evidence,"progress":progress}

func _validate_progress(value: Variant, stage: Dictionary) -> Dictionary:
	var expected: Dictionary = _empty_progress(stage)
	if not _keys(value, expected.keys()):
		return {"ok":false,"reason":"objective progress keys differ from current stage"}
	var progress: Dictionary = {}
	for objective: Dictionary in stage.objectives:
		if not _integer(value[objective.id], 0, int(objective.required)):
			return {"ok":false,"reason":"objective progress is not a bounded integer"}
		progress[objective.id] = int(value[objective.id])
	return {"ok":true,"progress":progress}

func _outcome_valid(outcome: String, safe: bool, progress: Dictionary, stage: Dictionary) -> bool:
	if not OUTCOMES.has(outcome):
		return false
	var all_met: bool = true
	var any_met: bool = false
	for objective: Dictionary in stage.objectives:
		var amount: int = int(progress.get(objective.id, 0))
		all_met = all_met and amount == int(objective.required)
		any_met = any_met or amount > 0
	if outcome == "success":
		return all_met and safe
	if outcome == "partial":
		return bool(stage.partialAllowed) and any_met
	return true

func _validate_archives(value: Variant, stages: Array) -> Dictionary:
	if not value is Dictionary or value.size() > stages.size():
		return {"ok":false,"reason":"failure archive is not a bounded per-stage map"}
	var archives: Dictionary = {}
	for key: Variant in value:
		var entry: Variant = value[key]
		if not key is String or not _keys(entry, ARCHIVE_KEYS) or not _integer(entry.stageIndex, 0, stages.size() - 1):
			return {"ok":false,"reason":"failure archive fields or stage index invalid"}
		var stage: Dictionary = stages[int(entry.stageIndex)]
		if entry.stageId != key or key != stage.id or not _integer(entry.attempts, 1, MAX_ATTEMPTS - 1):
			return {"ok":false,"reason":"failure archive stage identity or attempts invalid"}
		var attempts: int = int(entry.attempts)
		if not _integer(entry.evidenceCount, 0, attempts * MAX_FACTS) or not _integer(entry.throughRevision, 1, MAX_REVISION) or not _keys(entry.outcomes, FAILURE_OUTCOMES):
			return {"ok":false,"reason":"failure archive evidence, revision or outcomes invalid"}
		var outcomes: Dictionary = {}
		var total: int = 0
		for outcome: String in FAILURE_OUTCOMES:
			if not _integer(entry.outcomes[outcome], 0, attempts):
				return {"ok":false,"reason":"failure archive outcome count invalid"}
			outcomes[outcome] = int(entry.outcomes[outcome])
			total += int(outcomes[outcome])
		if total != attempts or (int(outcomes.partial) > 0 and (not stage.partialAllowed or int(entry.evidenceCount) < int(outcomes.partial))):
			return {"ok":false,"reason":"failure archive totals or partial permission inconsistent"}
		archives[key] = {"stageId":key,"stageIndex":int(entry.stageIndex),"attempts":attempts,"evidenceCount":int(entry.evidenceCount),"outcomes":outcomes,"throughRevision":int(entry.throughRevision)}
	return {"ok":true,"archives":archives}

func _validate_state(value: Variant, stages: Array) -> Dictionary:
	if not _keys(value, STATE_KEYS):
		return {"ok":false,"reason":"save fields do not match progress schema"}
	var state: Dictionary = value
	if not _integer(state.schemaVersion, 1, 1) or state.campaignId != CAMPAIGN_ID or not _token(state.runId, 96) or not _integer(state.seed, -2147483648, 2147483647):
		return {"ok":false,"reason":"save identity or seed invalid"}
	if not _integer(state.revision, 0, MAX_REVISION) or not _integer(state.stageIndex, 0, stages.size()) or not _integer(state.attempt, 1, MAX_ATTEMPTS) or not state.phase is String or not PHASES.has(state.phase):
		return {"ok":false,"reason":"save counters or phase invalid"}
	if not state.receipts is Array or state.receipts.size() > MAX_RECEIPTS or not _keys(state.handoff, HANDOFF_KEYS) or not state.handoff.done is bool:
		return {"ok":false,"reason":"save receipt history or handoff invalid"}
	var validated_archives: Dictionary = _validate_archives(state.failureArchive, stages)
	if not validated_archives.ok:
		return validated_archives
	var archives: Dictionary = validated_archives.archives
	var consumed_archives: Dictionary = {}
	var normalized_receipts: Array = []
	var cursor: int = 0
	var attempt: int = 1
	var base_revision: int = 0
	for value_receipt: Variant in state.receipts:
		if cursor >= stages.size() or not _keys(value_receipt, RECEIPT_KEYS):
			return {"ok":false,"reason":"receipt follows ending or has unknown fields"}
		var receipt: Dictionary = value_receipt
		var stage: Dictionary = stages[cursor]
		if attempt == 1 and archives.has(stage.id):
			var archive: Dictionary = archives[stage.id]
			# Each archived attempt was already retried: begin + unique facts +
			# settlement + retry. Its last settlement precedes that retry by one.
			var after_archive: int = base_revision + int(archive.attempts) * 3 + int(archive.evidenceCount)
			if int(archive.throughRevision) != after_archive - 1:
				return {"ok":false,"reason":"failure archive revision does not replay previous prefix"}
			base_revision = after_archive
			attempt += int(archive.attempts)
			consumed_archives[stage.id] = true
		if not _integer(receipt.stageIndex, cursor, cursor) or not _integer(receipt.attempt, attempt, attempt) or receipt.stageId != stage.id or receipt.runId != state.runId or receipt.id != _receipt_id(str(state.runId), str(stage.id), attempt):
			return {"ok":false,"reason":"receipt skips or duplicates stage attempt identity"}
		if not receipt.outcome is String or not receipt.safe is bool:
			return {"ok":false,"reason":"receipt outcome or safety type invalid"}
		var evidence: Dictionary = _validate_evidence(receipt.evidence, stage, str(state.runId), attempt)
		var progress: Dictionary = _validate_progress(receipt.objectiveProgress, stage)
		if not evidence.ok or not progress.ok:
			return {"ok":false,"reason":"receipt evidence or objective progress invalid"}
		if evidence.progress != progress.progress or not _outcome_valid(str(receipt.outcome), receipt.safe, progress.progress, stage):
			return {"ok":false,"reason":"receipt outcome contradicts retained evidence"}
		var receipt_revision: int = base_revision + 2 + evidence.evidence.size()
		if not _integer(receipt.revision, receipt_revision, receipt_revision):
			return {"ok":false,"reason":"receipt revision does not replay accepted transitions"}
		var normalized_receipt: Dictionary = receipt.duplicate(true)
		normalized_receipt.stageIndex = cursor
		normalized_receipt.attempt = attempt
		normalized_receipt.revision = receipt_revision
		normalized_receipt.objectiveProgress = progress.progress
		normalized_receipt.evidence = evidence.evidence
		normalized_receipts.append(normalized_receipt)
		base_revision = receipt_revision + 1
		if receipt.outcome == "success":
			cursor += 1
			attempt = 1
		else:
			attempt += 1
	if consumed_archives.size() != archives.size():
		return {"ok":false,"reason":"failure archive has no reachable retained stage receipt"}
	var stage_index: int = int(state.stageIndex)
	var phase: String = str(state.phase)
	var normalized_progress: Dictionary = {}
	var normalized_evidence: Dictionary = {}
	var expected_revision: int = base_revision
	var expected_attempt: int = attempt
	var expected_stage: int = cursor
	if phase in ["review", "recovery"]:
		if normalized_receipts.is_empty():
			return {"ok":false,"reason":"settled phase requires its own unique receipt"}
		var last: Dictionary = normalized_receipts.back()
		expected_stage = int(last.stageIndex)
		expected_attempt = int(last.attempt)
		expected_revision = int(last.revision)
		normalized_progress = last.objectiveProgress.duplicate(true)
		normalized_evidence = last.evidence.duplicate(true)
		if phase != ("review" if last.outcome == "success" else "recovery"):
			return {"ok":false,"reason":"settled phase contradicts last receipt"}
	elif phase == "complete":
		if cursor != stages.size() or normalized_receipts.is_empty() or normalized_receipts.back().outcome != "success":
			return {"ok":false,"reason":"ending lacks ordered final successful receipt"}
		expected_attempt = 1
		if not state.objectiveProgress is Dictionary or not state.objectiveProgress.is_empty() or not state.seenEvidence is Dictionary or not state.seenEvidence.is_empty():
			return {"ok":false,"reason":"ending retains a fabricated active objective"}
	else:
		if cursor >= stages.size():
			return {"ok":false,"reason":"all stage receipts require complete phase"}
		var evidence: Dictionary = _validate_evidence(state.seenEvidence, stages[cursor], str(state.runId), attempt)
		var progress: Dictionary = _validate_progress(state.objectiveProgress, stages[cursor])
		if not evidence.ok or not progress.ok or evidence.progress != progress.progress:
			return {"ok":false,"reason":"current progress contradicts original evidence"}
		normalized_progress = progress.progress
		normalized_evidence = evidence.evidence
		if phase == "briefing":
			if not normalized_evidence.is_empty():
				return {"ok":false,"reason":"briefing cannot contain active evidence"}
		else:
			expected_revision += 1 + normalized_evidence.size()
	if stage_index != expected_stage or int(state.attempt) != expected_attempt or int(state.revision) != expected_revision:
		return {"ok":false,"reason":"current counters do not replay ordered attempts"}
	if phase in ["review", "recovery"]:
		var current_progress: Dictionary = _validate_progress(state.objectiveProgress, stages[stage_index])
		var current_evidence: Dictionary = _validate_evidence(state.seenEvidence, stages[stage_index], str(state.runId), expected_attempt)
		if not current_progress.ok or not current_evidence.ok or current_progress.progress != normalized_progress or current_evidence.evidence != normalized_evidence:
			return {"ok":false,"reason":"settled current facts differ from immutable result receipt"}
	var expected_protagonist: String = str(stages[mini(stage_index, stages.size() - 1)].protagonistId)
	if not state.protagonistId is String or state.protagonistId != expected_protagonist or state.handoff != _handoff_for(stage_index, normalized_receipts):
		return {"ok":false,"reason":"protagonist or single handoff contradicts completed prefix"}
	var normalized: Dictionary = state.duplicate(true)
	normalized.schemaVersion = 1
	normalized.seed = int(state.seed)
	normalized.revision = expected_revision
	normalized.stageIndex = stage_index
	normalized.attempt = expected_attempt
	normalized.objectiveProgress = normalized_progress
	normalized.seenEvidence = normalized_evidence
	normalized.receipts = normalized_receipts
	normalized.failureArchive = archives
	return {"ok":true,"state":normalized}
