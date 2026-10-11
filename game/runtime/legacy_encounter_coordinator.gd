extends RefCounted
## Request identity + native minigame instance. Presentation never supplies a result.
const Duel = preload("res://game/domain/encounters/duel.gd")
const Land = preload("res://game/domain/encounters/land_battle.gd")
const Treasure = preload("res://game/domain/encounters/treasure.gd")
const Banquet = preload("res://game/domain/encounters/banquet.gd")
const Text = preload("res://game/domain/legacy/utf16_text.gd")
var _runtime: WeakRef
var _model: RefCounted
var _request: Dictionary = {}
var _sequence := 0
var _disposed := false
func _init(owner: RefCounted) -> void: _runtime = weakref(owner)
static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
func has_active() -> bool: return not _disposed and not _request.is_empty()
func _owner(): return _runtime.get_ref() if _runtime else null
func _gate(input: Dictionary) -> Dictionary:
	var owner = _owner()
	if _disposed or owner==null or not has_active(): return _no("encounter-unavailable")
	if input.get("id") != _request.id or owner._generation != _request.generation: return _no("stale-encounter")
	return {"ok":true}
func _resolution(kind: String,target: String) -> Dictionary:
	if kind=="duel": return {"type":"resolve-boarding","targetId":target,"success":true,"disposition":"plunder"}
	if kind=="landBattle": return {"type":"resolve-land","siteId":target,"victory":true}
	if kind=="treasure": return {"type":"resolve-treasure","siteId":target,"found":true}
	return {"type":"resolve-banquet","portId":target,"score":0}
func preview_start(input: Dictionary) -> Dictionary:
	var owner = _owner()
	if _disposed or owner==null: return _no("runtime-disposed")
	if has_active(): return _no("请先完成当前挑战")
	var kind = input.get("kind"); var target = input.get("targetId")
	if kind not in ["duel","landBattle","treasure","banquet"] or not target is String or target.is_empty(): return _no("invalid-encounter-request")
	if input.has("practice") and not input.practice is bool: return _no("invalid-practice-mode")
	if not owner._surrender_prompt.is_empty() or owner.voyage.state.has("pendingSurrenderReceipt") or owner._terminal(owner.simulation.snapshot()) or owner.voyage.state.career.retired: return _no("请先完成当前确认或结果")
	if input.get("practice",false): return {"ok":true}
	var candidate = owner.Session.new()
	if not candidate.restore(owner.voyage.serialize()): return _no(candidate.last_error)
	candidate.latestNaval = owner.simulation.snapshot()
	if kind in ["landBattle","treasure"]:
		var site = candidate.find_by(candidate.C.LAND_SITES,target)
		if site==null or site.kind != ("treasure" if kind=="treasure" else "fort"): return _no("此地点没有对应挑战")
		var visited: Dictionary = candidate.command({"type":"visit-land","siteId":target})
		if not visited.ok: return visited
	return candidate.command(_resolution(kind,target))
func start(input: Dictionary) -> Dictionary:
	var owner = _owner()
	if owner!=null: owner._flush(true)
	var gate := preview_start(input)
	if not gate.ok: return gate
	var kind: String = input.kind; var target: String = input.targetId; var practice: bool = input.get("practice",false)
	var state: Dictionary = owner.voyage.snapshot(); var hash_value: int = state.seed
	# Array.from(source target) iterates Unicode code points, then charCodeAt(0).
	for character in target:
		var point: int = character.unicode_at(0); var unit: int = 0xd800+((point-0x10000)>>10) if point>0xffff else point
		hash_value = (owner.voyage.imul32(hash_value,31)+unit)&0xffffffff
	var seed_value: int = (hash_value+int(state.day))&0xffffffff
	var context := {"portId":state.currentPortId,"day":state.day,"boardingContext":null}
	var native_model: RefCounted
	if kind=="duel":
		if not practice:
			var native: Dictionary = owner.simulation.snapshot(); var own: Dictionary = owner._ship(native,native.playerId); var enemy: Dictionary = owner._ship(native,target)
			if own.is_empty() or enemy.is_empty(): return _no("接舷目标已离开当前海域")
			context.boardingContext = {"crew":own.crew,"enemyCrew":enemy.crew,"morale":state.player.morale}
			context.opponent = {"id":enemy.id,"name":enemy.name,"kind":enemy.kind,"crew":enemy.crew,"hull":enemy.hull,"maxHull":enemy.maxHull}
		native_model = Duel.new(seed_value,"normal",context.boardingContext)
	elif kind=="landBattle": native_model = Land.new(seed_value,"normal")
	elif kind=="treasure": native_model = Treasure.new(seed_value,"normal",target)
	else: native_model = Banquet.new(seed_value,"normal")
	if not native_model.last_error.is_empty(): return _no(native_model.last_error)
	if not practice and kind in ["landBattle","treasure"]:
		var visit: Dictionary = owner._apply_business({"type":"visit-land","siteId":target},true)
		if not visit.ok: return visit
	_sequence += 1
	_request = {"id":"legacy-mini-%d-%d"%[owner._generation,_sequence],"generation":owner._generation,"kind":kind,"targetId":target,"practice":practice,"seed":seed_value,"difficulty":"normal","context":context,"settled":false,"acceptedSeconds":0.0,"paused":false,"receipt":null}
	_model = native_model; owner.set_pause("encounter",true); owner._revision += 1
	return {"ok":true,"id":_request.id}
func snapshot():
	if not has_active(): return null
	var packet := _request.duplicate(true); packet.state = _model.snapshot(); packet.model = packet.state.duplicate(true); packet.result = packet.state.get("result"); packet.identity = {"id":packet.id,"generation":packet.generation}
	return packet
func advance(seconds: float) -> float:
	var owner = _owner()
	if not has_active() or owner==null or _request.generation!=owner._generation or _request.paused or _request.settled or _model.state.phase!="active" or not is_finite(seconds) or seconds<=0: return 0
	if _externally_paused(): return 0
	if not _model.has_method("step"): return 0
	var before: float = _model.state.get("elapsed",0); _model.step(minf(seconds,30))
	var accepted: float = maxf(0,_model.state.get("elapsed",0)-before)
	_request.acceptedSeconds += accepted
	return accepted
func _externally_paused() -> bool:
	var owner = _owner()
	if owner==null: return true
	# The launching page keeps sea simulation suspended, independent of this model.
	for reason in ["player","tactical","menu","blur","hidden","loading","error","result","surrender"]:
		if owner._pauses.has(reason): return true
	return false
func command(input: Dictionary) -> Dictionary:
	var gate := _gate(input)
	if not gate.ok: return gate
	var owner = _owner(); var type: String = input.type
	if type=="encounter-pause":
		if not input.get("value") is bool: return _no("invalid-encounter-pause")
		_request.paused = input.value; owner._revision += 1; return {"ok":true}
	if type=="encounter-retry":
		if not _request.practice or _model.state.phase=="active": return _no("career-encounter-retry-forbidden")
		var next := {"type":"start-encounter","kind":_request.kind,"targetId":_request.targetId,"practice":true}
		_request.clear(); _model = null; owner._pauses.erase("encounter"); owner._update_pause()
		return start(next)
	if type=="encounter-close":
		if not _request.settled:
			if _model.state.phase=="active": _model.retreat()
			var receipt := _settle("release")
			if not receipt.ok: return receipt
		_request.clear(); _model = null; owner._pauses.erase("encounter"); owner._revision += 1; owner._update_pause()
		return {"ok":true}
	if type=="encounter-settle":
		if input.has("result") or input.has("reward") or input.has("score") or input.has("success"): return _no("forged-encounter-result")
		return _settle(input.get("disposition","capture"))
	if _request.settled or _model.state.phase!="active": return _no("encounter-already-complete")
	if _request.paused or _externally_paused(): return _no("encounter-paused")
	if type=="encounter-retreat":
		if not _model.retreat(): return _no("encounter-retreat-refused")
		owner._revision += 1; return {"ok":true}
	if type!="encounter-action": return _no("invalid-encounter-intent")
	var action = input.get("action"); var accepted := false; var before: Dictionary = _model.snapshot()
	if _request.kind in ["duel","banquet"]:
		if not action is String: return _no("invalid-encounter-action")
		accepted = _model.action(action)
	elif _request.kind=="treasure":
		if not action is Dictionary: return _no("invalid-encounter-action")
		if action.get("type")=="move" and action.get("direction") is String: accepted = _model.move(action.direction)
		elif action.get("type")=="dig": accepted = _model.dig()
		else: return _no("invalid-encounter-action")
	else:
		if not action is Dictionary: return _no("invalid-encounter-action")
		if action.get("type")=="select" and action.get("id") is String: accepted = _model.select(action.id)
		elif action.get("type")=="move": accepted = _model.move(action.get("x"),action.get("y"))
		elif action.get("type")=="attack" and action.get("id") is String: accepted = _model.attack(action.id)
		elif action.get("type")=="end-turn": accepted = _model.endTurn()
		else: return _no("invalid-encounter-action")
	if accepted or _model.snapshot()!=before: owner._revision += 1; return {"ok":true,"accepted":accepted}
	return _no("encounter-action-refused")
func _settle(disposition: String) -> Dictionary:
	var owner = _owner()
	if _request.settled: return _no("encounter-already-settled")
	var result = _model.state.get("result")
	if result==null or _model.state.phase=="active": return _no("encounter-result-unavailable")
	if disposition not in ["capture","plunder","release"]: return _no("invalid-boarding-disposition")
	var before: Dictionary = owner.voyage.snapshot(); var score: int = int(result.score)
	if _request.kind=="banquet":
		var maximum := 0
		for index in 14: maximum += 100+mini(50,index*5)
		score = clampi(int(floor(float(result.score)/maximum*100+.5)),0,100)
	var receipt := {"ok":true,"practice":true}
	if not _request.practice:
		if owner.voyage.state.currentPortId!=_request.context.portId or owner.voyage.state.day!=_request.context.day: return _no("encounter-context-changed")
		var request := _resolution(_request.kind,_request.targetId)
		if _request.kind=="duel": request.success = result.success; request.injury = result.injury; request.disposition = disposition
		elif _request.kind=="landBattle": request.victory = result.success; request.injury = result.injury
		elif _request.kind=="treasure": request.found = result.success; request.injury = result.injury
		else:
			request.score = score
		receipt = owner._apply_business(request,true)
		if not receipt.ok: return receipt
	var after: Dictionary = owner.voyage.snapshot()
	_request.settlement = {"mode":"practice" if _request.practice else "career","rawScore":result.score,"score":score,"paid":receipt.get("cost",0),"before":_social_state(owner,before),"after":_social_state(owner,after)}
	_request.settled = true; _request.receipt = receipt.duplicate(true); owner._revision += 1
	return receipt
func _social_state(owner: RefCounted,state: Dictionary) -> Dictionary:
	var social := {"silver":state.player.silver,"morale":state.player.morale,"fame":state.player.fame,"relations":state.relations.duplicate(true)}
	var port = owner.voyage.port(_request.context.portId)
	if port!=null: social.relation = state.relations[port.faction]
	return social
func dispose() -> void:
	_disposed = true; _request.clear(); _model = null; _runtime = null
