extends RefCounted
## Standalone source PracticeInspector. Owns minigames, never a career or storage.
const Duel = preload("res://game/domain/encounters/duel.gd")
const Land = preload("res://game/domain/encounters/land_battle.gd")
const Treasure = preload("res://game/domain/encounters/treasure.gd")
const Banquet = preload("res://game/domain/encounters/banquet.gd")
const TARGETS = {"duel":"voc-captain","landBattle":"taiwan-fort","treasure":"treasure-cove","banquet":"xiamen"}
var _model: RefCounted
var _request: Dictionary = {}
var _sequence := 0
var _revision := 0
var _disposed := false
var _suspended := false
static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func start(kind: String = "duel") -> Dictionary:
	if _disposed: return _no("practice-disposed")
	if not TARGETS.has(kind): return _no("invalid-practice-kind")
	var candidate: RefCounted
	match kind:
		"duel": candidate=Duel.new(1661,"normal",{"crew":48,"enemyCrew":38,"morale":100})
		"landBattle": candidate=Land.new(1661,"normal")
		"treasure": candidate=Treasure.new(1661,"normal",TARGETS[kind])
		"banquet": candidate=Banquet.new(1661,"normal")
	if not candidate.last_error.is_empty(): return _no(candidate.last_error)
	_model=candidate; _sequence+=1; _revision+=1
	_request={"id":"practice-%d"%_sequence,"generation":_sequence,"kind":kind,"targetId":TARGETS[kind],"practice":true,"seed":1661,"difficulty":"normal","context":{"playerName":"沈沧海"},"paused":false,"settled":false,"acceptedSeconds":0.0}
	_request.started=kind in ["landBattle","treasure"]
	return {"ok":true,"id":_request.id}
func snapshot() -> Dictionary:
	if _request.is_empty() or _disposed: return {}
	var packet := _request.duplicate(true)
	packet.state=_model.snapshot(); packet.result=packet.state.get("result"); packet.revision=_revision
	packet.paused=packet.paused or _suspended
	return packet
func set_suspended(value: bool) -> void: _suspended=value
func advance(seconds: float) -> float:
	if _disposed or _request.is_empty() or not _request.started or _request.paused or _suspended or _model.state.phase!="active" or not is_finite(seconds) or seconds<=0 or not _model.has_method("step"): return 0
	var before: float = _model.state.get("elapsed",0)
	_model.step(minf(seconds,30)); var accepted: float = maxf(0,_model.state.get("elapsed",0)-before)
	_request.acceptedSeconds+=accepted
	if accepted>0: _revision+=1
	return accepted
func command(intent: Dictionary) -> Dictionary:
	if _disposed or _request.is_empty(): return _no("practice-unavailable")
	if intent.get("id")!=_request.id or intent.get("generation",_sequence)!=_sequence: return _no("stale-encounter")
	if intent.has("expectedRevision") and intent.expectedRevision!=_revision: return _no("stale-practice-revision")
	var type: String = intent.get("type","")
	if type=="encounter-begin":
		if _request.started or _request.paused or _suspended or _model.state.phase!="active": return _no("practice-begin-unavailable")
		_request.started=true; _revision+=1; return {"ok":true}
	if type=="encounter-pause":
		if not _request.started: return _no("practice-not-started")
		if not intent.get("value") is bool: return _no("invalid-encounter-pause")
		_request.paused=intent.value; _revision+=1; return {"ok":true}
	if type=="encounter-retry":
		if _model.state.phase=="active": return _no("practice-still-active")
		return start(_request.kind)
	if type=="encounter-settle":
		for key in ["result","reward","score","success"]:
			if intent.has(key): return _no("forged-encounter-result")
		if _request.settled: return _no("encounter-already-settled")
		if _model.state.phase=="active" or _model.state.result==null: return _no("encounter-result-unavailable")
		_request.settled=true
		_request.settlement={"mode":"practice","rawScore":_model.state.result.score,"paid":0}
		_revision+=1; return {"ok":true,"practice":true}
	if type=="encounter-close":
		if _model.state.phase=="active": _model.retreat()
		_request.clear(); _model=null; _revision+=1; return {"ok":true}
	if _request.paused or _suspended: return _no("encounter-paused")
	if _request.settled or _model.state.phase!="active": return _no("encounter-already-complete")
	if type=="encounter-retreat":
		if not _model.retreat(): return _no("encounter-retreat-refused")
		_revision+=1; return {"ok":true}
	if type!="encounter-action": return _no("invalid-encounter-intent")
	if not _request.started: return _no("practice-not-started")
	var action = intent.get("action"); var accepted := false; var before: Dictionary = _model.snapshot()
	if _request.kind in ["duel","banquet"]:
		if not action is String: return _no("invalid-encounter-action")
		accepted=_model.action(action)
	else:
		if not action is Dictionary: return _no("invalid-encounter-action")
		if _request.kind=="treasure":
			if action.get("type")=="move" and action.get("direction") is String: accepted=_model.move(action.direction)
			elif action.get("type")=="dig": accepted=_model.dig()
			else: return _no("invalid-encounter-action")
		else:
			match action.get("type"):
				"select":
					if not action.get("id") is String: return _no("invalid-encounter-action")
					accepted=_model.select(action.id)
				"move": accepted=_model.move(action.get("x"),action.get("y"))
				"attack":
					if not action.get("id") is String: return _no("invalid-encounter-action")
					accepted=_model.attack(action.id)
				"end-turn": accepted=_model.endTurn()
				_: return _no("invalid-encounter-action")
	if accepted or _model.snapshot()!=before:
		_revision+=1; return {"ok":true,"accepted":accepted}
	return _no("encounter-action-refused")
func dispose() -> void:
	_disposed=true; _request.clear(); _model=null
