extends RefCounted
## Story encounter coordinator: request identity + native minigame instance.
## Presentation never supplies a result — settlements come from the model and
## land in story world commands with live gate re-checks. Thin fork of the
## legacy coordinator guards (forged-result, practice isolation, context fence).
const Duel = preload("res://game/domain/encounters/duel.gd")
const Land = preload("res://game/domain/encounters/land_battle.gd")
var _runtime: WeakRef
var _model: RefCounted
var _request: Dictionary = {}
var _sequence := 0
var _disposed := false

func _init(owner: RefCounted) -> void:
	_runtime = weakref(owner)

static func _no(reason: String) -> Dictionary: return {"ok": false, "reason": reason}

func has_active() -> bool:
	return not _disposed and not _request.is_empty()

func _owner():
	return _runtime.get_ref() if _runtime else null

func preview_start(input: Dictionary) -> Dictionary:
	var owner = _owner()
	if _disposed or owner == null: return _no("runtime-disposed")
	if has_active(): return _no("请先完成当前挑战")
	var kind = input.get("kind")
	if kind not in ["duel", "landBattle"] or not input.get("targetId") is String or str(input.targetId).is_empty(): return _no("invalid-encounter-request")
	return {"ok": true}

func start(input: Dictionary) -> Dictionary:
	var owner = _owner()
	if owner == null: return _no("runtime-disposed")
	var gate := preview_start(input)
	if not gate.ok: return gate
	var kind: String = str(input.kind)
	var target: String = str(input.targetId)
	var practice: bool = bool(input.get("practice", false))
	var seed_value: int = (int(owner.world.state.seed) + int(owner.world.state.day) * 31 + _sequence) & 0xffffffff
	var context: Dictionary = {}
	var model: RefCounted
	if kind == "duel":
		var native: Dictionary = owner.native_snapshot()
		var own: Dictionary = _ship(native, str(owner.world.state.flagshipId))
		var enemy: Dictionary = _ship(native, target)
		if own.is_empty() or enemy.is_empty(): return _no("接舷目标已离开当前海域")
		context = {"crew": int(own.crew), "enemyCrew": int(enemy.crew), "morale": 100}
		model = Duel.new(seed_value, "normal", context)
	else:
		model = Land.new(seed_value, "normal")
	if not model.last_error.is_empty(): return _no(str(model.last_error))
	_sequence += 1
	_request = {"id": "story-mini-%d-%d" % [owner._generation, _sequence], "generation": owner._generation, "kind": kind, "targetId": target, "practice": practice, "settled": false, "paused": false, "acceptedSeconds": 0.0}
	_model = model
	owner.set_pause("encounter", true)
	return {"ok": true, "id": _request.id}

func snapshot():
	if not has_active(): return null
	var packet := _request.duplicate(true)
	packet.state = _model.snapshot()
	packet.result = packet.state.get("result")
	return packet

func advance(seconds: float) -> float:
	var owner = _owner()
	if not has_active() or owner == null or _request.generation != owner._generation or _request.paused or _request.settled or _model.state.get("phase", "") != "active" or not is_finite(seconds) or seconds <= 0:
		return 0
	if owner.is_paused() and owner.pause_reasons() != ["encounter"]:
		return 0
	if not _model.has_method("step"):
		return 0
	var before: float = float(_model.state.get("elapsed", 0))
	_model.step(minf(seconds, 30.0))
	var accepted: float = maxf(0.0, float(_model.state.get("elapsed", 0)) - before)
	_request.acceptedSeconds += accepted
	return accepted

func command(input: Dictionary) -> Dictionary:
	if _disposed or not has_active(): return _no("encounter-unavailable")
	var owner = _owner()
	if owner == null: return _no("runtime-disposed")
	if input.get("id") != _request.id or input.get("generation", owner._generation) != _request.generation: return _no("stale-encounter")
	var type: String = str(input.get("type", ""))
	if type == "encounter-pause":
		if not input.get("value") is bool: return _no("invalid-encounter-pause")
		_request.paused = input.value
		return {"ok": true}
	if type == "encounter-close":
		if not _request.settled and _model.state.get("phase", "") == "active":
			_model.retreat()
		_request.clear()
		_model = null
		owner.set_pause("encounter", false)
		return {"ok": true}
	if type == "encounter-settle":
		if input.has("result") or input.has("reward") or input.has("score") or input.has("success"): return _no("forged-encounter-result")
		return _settle(str(input.get("disposition", "capture")))
	if _request.settled or _model.state.get("phase", "") != "active": return _no("encounter-already-complete")
	if type == "encounter-retreat":
		if not _model.retreat(): return _no("encounter-retreat-refused")
		return {"ok": true}
	if type != "encounter-action": return _no("invalid-encounter-intent")
	var action = input.get("action")
	var accepted := false
	if _request.kind == "duel":
		if not action is String: return _no("invalid-encounter-action")
		accepted = _model.action(action)
	else:
		if not action is Dictionary: return _no("invalid-encounter-action")
		if action.get("type") == "select" and action.get("id") is String: accepted = _model.select(str(action.id))
		elif action.get("type") == "move": accepted = _model.move(int(action.get("x", -1)), int(action.get("y", -1)))
		elif action.get("type") == "attack" and action.get("id") is String: accepted = _model.attack(str(action.id))
		elif action.get("type") == "end-turn": accepted = _model.endTurn()
		else: return _no("invalid-encounter-action")
	return {"ok": true, "accepted": accepted}

func _settle(disposition: String) -> Dictionary:
	var owner = _owner()
	if _request.settled: return _no("encounter-already-settled")
	var result = _model.state.get("result")
	if result == null or _model.state.get("phase", "") == "active": return _no("encounter-result-unavailable")
	if _request.kind == "duel" and disposition not in ["capture", "plunder", "release"]: return _no("invalid-boarding-disposition")
	var request: Dictionary
	if _request.kind == "duel":
		request = {"type": "resolve-boarding", "targetId": _request.targetId, "captured": bool(result.success), "disposition": disposition, "battleId": "story-mini-%d" % _sequence}
	else:
		request = {"type": "resolve-land", "siteId": _request.targetId, "victory": bool(result.success)}
	if result.has("injury"):
		request.injury = result.injury
	var receipt: Dictionary = owner.settle_encounter(request)
	if not receipt.ok: return receipt
	_request.settled = true
	return receipt

func _ship(native: Dictionary, id: String) -> Dictionary:
	for entry: Dictionary in native.get("ships", []):
		if str(entry.get("id", "")) == id:
			return entry
	return {}

func dispose() -> void:
	_disposed = true
	_request.clear()
	_model = null
	_runtime = null
