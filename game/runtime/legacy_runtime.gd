extends RefCounted
## Legacy career authority. Domain owns money/quests; Native owns sea motion/combat.
const Session = preload("res://game/domain/legacy/adventure_session.gd")
const Text = preload("res://game/domain/legacy/utf16_text.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
const Simulation = preload("res://game/runtime/sailing_simulation.gd")
const Waves = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const SaveCoordinator = preload("res://game/persistence/save_coordinator.gd")
const Coordinator = preload("res://game/runtime/legacy_encounter_coordinator.gd")
const PAUSES = ["player","tactical","panel","menu","blur","hidden","loading","error","result","surrender","encounter"]
const RESOLUTIONS = ["resolve-boarding","resolve-land","resolve-treasure","resolve-banquet"]
var voyage: RefCounted
var session: RefCounted:
	get: return voyage
var simulation: RefCounted
var encounter_coordinator: RefCounted
var _height: Callable
var _waves: RefCounted
var _generation := 0
var _revision := 0
var _pauses: Dictionary = {}
var _handling_mode := "assisted"
var _notice := ""
var _disposed := false
var _available: Array = []
var _captured: Dictionary = {}
var _events: Array = []
var _unsynced: Array = []
var _synced_time := 0.0
var _navigation_time := -INF
var _last_fire := -INF
var _pause_epoch := 0
var _surrender_prompt: Dictionary = {}
var _last_verified := ""
var _last_receipt: Dictionary = {}
var _storage: RefCounted
var _checkpoint_time := 0.0
static func _no(reason: String) -> Dictionary: return {"ok":false,"reason":reason}
static func _finite(value) -> bool: return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))
static func _ship(state: Dictionary,id: String) -> Dictionary:
	for ship: Dictionary in state.get("ships",[]):
		if ship.id == id: return ship
	return {}
static func _distance(a: Dictionary,b: Dictionary) -> float: return Vector2(a.x-b.x,a.z-b.z).length()
static func _terminal(native: Dictionary) -> bool: return native.get("status") in ["victory","defeat","surrendered"]
static func validate_save(raw: String) -> Dictionary:
	var candidate = Session.new()
	return {"ok":true} if candidate.restore(raw) else _no(candidate.last_error)
func configure(height_sampler: Callable,options: Dictionary = {}) -> Dictionary:
	if not height_sampler.is_valid(): return _no("invalid-terrain-sampler")
	var domain_options := options.duplicate(); domain_options.erase("storage")
	var candidate = Session.new(domain_options)
	if candidate.state.is_empty(): return _no(candidate.last_error)
	_height = height_sampler; _waves = Waves.new(); _waves.configure(_height)
	if options.get("initialDock",true):
		var dock: Dictionary = candidate.command({"type":"dock","portId":"xiamen"})
		if not dock.ok: return dock
	var setups := _adapt(candidate)
	var bundle := _build(candidate,setups,{})
	if not bundle.ok: return bundle
	if candidate.state.currentPortId != null:
		var anchored: Dictionary = bundle.simulation.encounter.anchorFleet(candidate.state.fleet.map(func(s): return s.id))
		if not anchored.ok: return anchored
		bundle.simulation.refresh_snapshot(); candidate.syncDockedFleet(bundle.simulation.snapshot())
	if simulation: simulation.set_paused(true)
	if encounter_coordinator: encounter_coordinator.dispose()
	voyage = candidate; simulation = bundle.simulation; _available = setups; _captured.clear()
	_generation += 1; _revision = 0; _pauses.clear(); _disposed = false; _notice = ""
	_events.clear(); _unsynced.clear(); _synced_time = 0; _last_fire = -INF; _navigation_time = -INF; _checkpoint_time = 0; _surrender_prompt.clear()
	_storage = options.get("storage"); _last_verified = ""; _last_receipt.clear()
	encounter_coordinator = Coordinator.new(self)
	_flush(true); _update_navigation(true); _update_pause()
	return {"ok":true}
func _adapt(owner: RefCounted) -> Array:
	var state: Dictionary = owner.snapshot(); var forward := Vector2(cos(state.heading),sin(state.heading)); var ally := 0
	var setups: Array = owner.navalSetup()+owner.ambientNavalSetup()
	for setup: Dictionary in setups:
		var fleet = owner.find_by(state.fleet,setup.id)
		setup.stats = setup.get("stats",{}).duplicate(true)
		if fleet != null:
			setup.stats.cargoMass = owner.cargo_size(fleet.cargo)*100
			if fleet.id != state.flagshipId:
				ally += 1
				if not fleet.has("position") or _distance(setup.position,state.position)<1:
					var lateral := 32 if ally%2 else -32; var behind := 48*int(ceil(ally/2.0))
					setup.position = {"x":state.position.x-forward.x*behind-forward.y*lateral,"z":state.position.z-forward.y*behind+forward.x*lateral}
		for objective: Dictionary in state.activeObjectives:
			if objective.get("targetId")==setup.id and objective.kind=="rescue" and objective.progress<.5: setup.sailDeployment = 0
	return setups
func _selected(setups: Array,state: Dictionary,excluded: Dictionary,initial: bool=false) -> Array:
	var native: Dictionary = {} if initial or not simulation else simulation.snapshot()
	var player := _ship(native,state.flagshipId); var position: Dictionary = player.get("visual",{}).get("position",state.position)
	var retain: bool = not native.is_empty() and (not native.get("projectiles",[]).is_empty() or native.time-_last_fire<1)
	var radius := 350 if initial else 450; var selected: Array = []
	for setup: Dictionary in setups:
		if excluded.has(setup.id): continue
		if setup.team != "hostile": selected.append(setup); continue
		if state.currentPortId != null: continue
		var live := _ship(native,setup.id)
		if _distance(live.get("visual",{}).get("position",setup.position),position)<=radius or not live.is_empty() and retain: selected.append(setup)
	if retain and state.currentPortId==null:
		for ship: Dictionary in native.ships:
			if ship.team=="hostile" and not excluded.has(ship.id) and not selected.any(func(s): return s.id==ship.id): selected.append(_live_setup(ship))
	return selected
func _live_setup(ship: Dictionary) -> Dictionary:
	var setup := {"id":ship.id,"name":ship.name,"kind":ship.kind,"team":ship.team,"position":{"x":ship.visual.position.x,"z":ship.visual.position.z},"heading":ship.visual.heading,"speed":Vector2(ship.visual.velocity.x,ship.visual.velocity.z).length()}
	for field in ["hull","sail","crew","ammo","stats","cooldownSeconds","ammoType","rudder","sailAngle","autoTrim","sailDeployment"]: setup[field] = ship[field]
	return setup.duplicate(true)
func _native(state: Dictionary,setups: Array) -> RefCounted:
	var descriptors: Array = Descriptor.original_descriptors()
	for wave: Dictionary in descriptors: wave.direction = {"x":wave.direction.x,"y":wave.direction.z}
	return Encounter.new({"playerId":state.flagshipId,"ships":setups,"seed":state.seed,"wind":state.weather.wind,"battleId":"legacy-%d-%d-%d"%[_generation+1,Time.get_ticks_usec(),randi()],"sampleTerrainHeight":_height,"oceanWaves":descriptors,"waveSampler":_waves})
func _validate_all(owner: RefCounted,setups: Array) -> Dictionary:
	var native := _native(owner.snapshot(),setups)
	return {"ok":true} if native.last_error.is_empty() else _no(native.last_error)
func _build(owner: RefCounted,setups: Array,excluded: Dictionary) -> Dictionary:
	var valid := _validate_all(owner,setups)
	if not valid.ok: return valid
	var native := _native(owner.snapshot(),_selected(setups,owner.snapshot(),excluded,true))
	if not native.last_error.is_empty(): return _no(native.last_error)
	var input := Simulation.new(native); input.set_handling_mode(_handling_mode)
	return {"ok":true,"simulation":input}
func _collect() -> void:
	if not simulation: return
	var incoming: Array = simulation.drain_events(); _events.append_array(incoming); _unsynced.append_array(incoming)
	for event: Dictionary in incoming:
		if event.type=="fire": _last_fire = maxf(_last_fire,event.time)
func _flush(force: bool=false) -> void:
	if not voyage or not simulation: return
	_collect()
	var native: Dictionary = simulation.snapshot(); var elapsed := maxf(0,native.time-_synced_time)
	if not force and _unsynced.is_empty() and elapsed<.1-1e-8: return
	var old_day: int = voyage.state.day; var old_seen: int = voyage.meta.seenEvents.size(); var old_rescued: int = voyage.meta.rescuedTargets.size(); var incoming := _unsynced; _unsynced = []
	voyage.syncNaval(native,incoming)
	if elapsed>0: voyage.advance(elapsed)
	_synced_time = native.time
	if old_day!=voyage.state.day or old_seen!=voyage.meta.seenEvents.size() or old_rescued!=voyage.meta.rescuedTargets.size(): _revision += 1
	var changed: bool = _available.any(func(s): return not _ship(native,s.id).is_empty() and _ship(native,s.id).team != s.team)
	if old_day != voyage.state.day or changed or incoming.any(func(e): return e.type in ["sink","victory","defeat"]):
		_available = _adapt(voyage)
		if not _terminal(native): _reconcile(true)
	if _terminal(native): _pauses.result = true; _update_pause()
func _reconcile(force: bool=false) -> Dictionary:
	if _terminal(simulation.snapshot()): return {"ok":true}
	var setups := _selected(_available,voyage.snapshot(),_captured)
	var ids: Array = setups.map(func(s): return s.id); ids.sort()
	var current: Array = simulation.snapshot().ships.map(func(s): return s.id); current.sort()
	if not force and ids==current: return {"ok":true}
	if not force:
		_flush(true); _available = _adapt(voyage); setups = _selected(_available,voyage.snapshot(),_captured)
		if _terminal(simulation.snapshot()): return {"ok":true}
	var result: Dictionary = simulation.encounter.reconcileShips(setups)
	if not result.ok: return result
	result = simulation.encounter.setPlayerId(voyage.state.flagshipId)
	if not result.ok: return result
	result = simulation.encounter.setWind(voyage.state.weather.wind)
	simulation.refresh_snapshot(); _update_navigation(true); voyage.syncNaval(simulation.snapshot(),[])
	return result
func _update_navigation(force: bool=false) -> void:
	var native: Dictionary = simulation.snapshot()
	if not force and native.time-_navigation_time<.5: return
	_navigation_time = native.time
	var player := _ship(native,native.playerId)
	if player.is_empty(): return
	var ambient: Dictionary = voyage.ambientWaypoints(); var ally := 0
	for ship: Dictionary in native.ships:
		if ship.id==player.id or ship.hull<=0: continue
		var target = null; var update := false
		if ambient.has(ship.id): target = ambient[ship.id]; update = true
		elif ship.team=="player":
			ally += 1; var lateral := 32 if ally%2 else -32; var behind := 48*int(ceil(ally/2.0)); var heading: float = player.visual.heading
			target = {"x":player.visual.position.x-cos(heading)*behind-sin(heading)*lateral,"z":player.visual.position.z-sin(heading)*behind+cos(heading)*lateral}; update = true
		elif ship.team=="neutral":
			update = true
			for objective: Dictionary in voyage.state.activeObjectives:
				if objective.get("targetId")==ship.id and objective.kind in ["escort","rescue"]:
					var quest = voyage.find_by(voyage.state.quests,objective.questId); var port = voyage.port(quest.get("destinationPortId"))
					if not (objective.kind=="rescue" and objective.progress<.5) and port != null: target = {"x":port.x,"z":port.z}
		if update: simulation.encounter.navigate(ship.id,target)
	simulation.refresh_snapshot()
func is_paused() -> bool: return not _pauses.is_empty()
func notify(message: String) -> void: _notice = message
func _update_pause() -> void:
	if not simulation or not voyage: return
	voyage.setPaused(is_paused()); simulation.set_paused(is_paused() or voyage.state.currentPortId != null or voyage.state.career.retired)
func set_pause(reason: String,active: bool) -> Dictionary:
	if _disposed or not simulation: return _no("runtime-disposed")
	if not reason in PAUSES: return _no("invalid-pause-reason")
	_flush(true); _pause_epoch += 1
	if active: _pauses[reason] = true
	else:
		if reason=="surrender" and (not _surrender_prompt.is_empty() or voyage.state.has("pendingSurrenderReceipt")): return _no("请先完成投降确认或结果")
		if reason=="result" and _terminal(simulation.snapshot()): return _no("请先确认海战结果并继续航程")
		_pauses.erase(reason)
	_update_pause(); return {"ok":true}
func _manual_gate() -> Dictionary:
	return _sea_command_gate(true)
func _sea_command_gate(include_panel: bool) -> Dictionary:
	if _disposed or not simulation: return _no("runtime-disposed")
	# Panels suspend the sea clock/manual controls; their directed intents remain usable.
	var blocked := _pauses.keys().any(func(reason): return include_panel or reason!="panel")
	if blocked or voyage.state.currentPortId != null or voyage.state.career.retired or _terminal(simulation.snapshot()) or not _surrender_prompt.is_empty() or voyage.state.has("pendingSurrenderReceipt"): return _no("请先出港并继续航程")
	return {"ok":true}
func set_held(code: String,active: bool) -> Dictionary:
	if not simulation: return _no("runtime-disposed")
	if not code in ["KeyW","KeyS","KeyA","KeyD","ArrowUp","ArrowDown","ArrowLeft","ArrowRight","BracketLeft","BracketRight"]: return _no("invalid-held-control")
	if active:
		var gate := _manual_gate()
		if not gate.ok: return gate
	simulation.set_held(code,active); return {"ok":true}
func set_sails(value: float) -> Dictionary:
	var gate := _manual_gate()
	if not gate.ok: return gate
	if not is_finite(value) or value<0 or value>1: return _no("invalid-sails")
	simulation.set_sails(value); _revision += 1; return {"ok":true}
func toggle_trim() -> Dictionary:
	var gate := _manual_gate()
	if not gate.ok: return gate
	simulation.toggle_trim(); _revision += 1; return {"ok":true}
func set_handling_mode(mode: String) -> Dictionary:
	if not mode in ["assisted","realistic"]: return _no("invalid-handling-mode")
	_handling_mode = mode
	if simulation: simulation.set_handling_mode(mode)
	return {"ok":true}
func _intent_gate(input: Dictionary) -> Dictionary:
	if _disposed or not voyage or not simulation: return _no("runtime-disposed")
	if input.has("generation") and input.generation != _generation: return _no("stale-generation")
	if input.has("expectedRevision") and input.expectedRevision != _revision: return _no("stale-revision")
	if not input.get("type") is String: return _no("无效操作")
	return {"ok":true}
func _business_gate(input: Dictionary,internal: bool=false) -> Dictionary:
	if not _surrender_prompt.is_empty() or voyage.state.has("pendingSurrenderReceipt"): return _no("请先完成投降确认或结果")
	if input.type in ["surrender","acknowledge-surrender"]: return _no("请通过投降确认或继续航程处理")
	if not internal and input.type in RESOLUTIONS: return _no("挑战结果须由当前原生模型结算")
	if not internal and encounter_coordinator and encounter_coordinator.has_active(): return _no("请先完成当前挑战")
	if _terminal(simulation.snapshot()): return _no("请先确认海战结果并继续航程")
	if input.type=="dock" and simulation.encounter.hasPendingCombat(): return _no("炮击尚未结束，请待炮弹落定后靠港")
	return {"ok":true}
func _stage(input: Dictionary,internal: bool=false) -> Dictionary:
	var gate := _business_gate(input,internal)
	if not gate.ok: return gate
	var candidate = Session.new()
	if not candidate.restore(voyage.serialize()): return _no(candidate.last_error)
	candidate.setPaused(is_paused()); candidate.syncNaval(simulation.snapshot(),[])
	var request := input.duplicate(true)
	if request.type=="rename" and request.get("name") is String: request.name = Text.encode_native(request.name)
	var result: Dictionary = candidate.command(request)
	if not result.ok: return result
	var prepared = Session.new()
	if not prepared.restore(candidate.serialize()): return _no(prepared.last_error)
	prepared.setPaused(is_paused()); prepared.latestNaval = simulation.snapshot()
	var setups := _adapt(prepared); var valid := _validate_all(prepared,setups)
	if not valid.ok: return valid
	var excluded := _captured.duplicate()
	if request.type=="resolve-boarding" and request.success: excluded[request.targetId] = true
	var selected := _selected(setups,prepared.snapshot(),excluded)
	var native: Dictionary = simulation.snapshot()
	var revival: bool = selected.any(func(s): return s.get("hull",100)>0 and not _ship(native,s.id).is_empty() and _ship(native,s.id).hull<=0)
	var docked: bool = voyage.state.currentPortId != null and not simulation.encounter.hasPendingCombat()
	if revival and not docked: return _no("沉没船只须安全靠港后修复")
	var replacement = null
	if request.type=="depart" or docked and (revival or _ship(native,native.playerId).get("hull",0)<=0):
		var bundle := _build(prepared,setups,excluded)
		if not bundle.ok: return bundle
		replacement = bundle.simulation
	return {"ok":true,"candidate":prepared,"setups":setups,"selected":selected,"excluded":excluded,"replacement":replacement,"receipt":result}
func preview_command(input: Dictionary) -> Dictionary:
	var gate := _intent_gate(input)
	if not gate.ok: return gate
	if input.type=="start-encounter": return encounter_coordinator.preview_start(input)
	if input.type in ["native-action","navigate","set-sails","trim"]: return _preview_native(input)
	if input.type=="begin-surrender": return surrender_eligibility()
	if input.type=="export-save" or input.type=="save": return _safe_checkpoint()
	if input.type=="import-save": return _safe_checkpoint()
	if input.type in ["pause","set-handling-mode"]: return {"ok":true}
	var staged := _stage(input)
	return staged.receipt.duplicate(true) if staged.ok else staged
func preview(input: Dictionary) -> Dictionary: return preview_command(input)
func _preview_native(input: Dictionary) -> Dictionary:
	var gate := _sea_command_gate(input.type!="navigate")
	if not gate.ok: return gate
	if input.type=="set-sails": return {"ok":true} if _finite(input.get("value")) and input.value>=0 and input.value<=1 else _no("invalid-sails")
	if input.type=="trim": return {"ok":true}
	if input.type=="navigate":
		var point = input.get("point")
		if point!=null and (not point is Dictionary or not _finite(point.get("x")) or not _finite(point.get("z"))): return _no("Invalid waypoint")
		var clone := _native(voyage.snapshot(),simulation.snapshot().ships.map(_live_setup))
		if not clone.last_error.is_empty(): return _no(clone.last_error)
		return clone.navigate(voyage.state.flagshipId,point)
	var action = input.get("action",input.get("command"))
	if not action is Dictionary or action.get("type") not in ["controls","fire","select-ammo"]: return _no("invalid-native-action")
	if not action.get("shipId",voyage.state.flagshipId) is String or voyage.find_by(voyage.state.fleet,action.get("shipId",voyage.state.flagshipId))==null: return _no("Ship not owned by captain")
	var clone := _native(voyage.snapshot(),simulation.snapshot().ships.map(_live_setup))
	if not clone.last_error.is_empty(): return _no(clone.last_error)
	return clone.command(action)
func command(input: Dictionary) -> Dictionary:
	var gate := _intent_gate(input)
	if not gate.ok: return gate
	var type: String = input.type
	if type=="pause": return set_pause(input.get("reason","player"),input.get("value",input.get("active",true)))
	if type=="set-handling-mode": return set_handling_mode(input.get("mode",""))
	if type=="set-sails": return set_sails(input.get("value",NAN))
	if type=="trim": return toggle_trim()
	if type=="begin-surrender": return begin_surrender()
	if type=="cancel-surrender": return cancel_surrender(input.get("token",{}))
	if type=="confirm-surrender": return confirm_surrender(input.get("token",{}))
	if type in ["acknowledge-result","resume-voyage"]: return resume_voyage()
	if type=="start-encounter": return encounter_coordinator.start(input)
	if type.begins_with("encounter-"): return encounter_coordinator.command(input)
	if type in ["native-action","navigate"]:
		gate = _preview_native(input)
		if not gate.ok: return gate
		var result: Dictionary = simulation.encounter.navigate(voyage.state.flagshipId,input.get("point")) if type=="navigate" else simulation.encounter.command(input.get("action",input.get("command")))
		if result.ok: simulation.refresh_snapshot(); _flush(true); _revision += 1
		return result
	if type=="save": return save_checkpoint(_storage)
	if type=="export-save": return export_last_verified_checkpoint() if input.get("kind")=="backup" else export_save()
	if type=="import-save": return adopt_save(input.get("json",""),_storage)
	_flush(true)
	return _apply_business(input)
func _apply_business(input: Dictionary,internal: bool=false) -> Dictionary:
	var staged := _stage(input,internal)
	if not staged.ok: return staged
	if staged.replacement == null:
		var result: Dictionary = simulation.encounter.reconcileShips(staged.selected)
		if not result.ok: return result
		result = simulation.encounter.setPlayerId(staged.candidate.state.flagshipId)
		if not result.ok: return result
		result = simulation.encounter.setWind(staged.candidate.state.weather.wind)
		if not result.ok: return result
		if input.type=="dock":
			result = simulation.encounter.anchorFleet(staged.candidate.state.fleet.map(func(s): return s.id))
			if not result.ok: return result
	else: _replace(staged.replacement)
	voyage.commitFrom(staged.candidate); _available = staged.setups; _captured = staged.excluded
	simulation.refresh_snapshot(); _update_navigation(true); voyage.syncNaval(simulation.snapshot(),[])
	if voyage.state.currentPortId != null: voyage.syncDockedFleet(simulation.snapshot())
	_revision += 1; _update_pause()
	var receipt: Dictionary = staged.receipt
	if _storage and _safe_checkpoint().ok: receipt.save = save_checkpoint(_storage)
	return receipt
func _replace(next: RefCounted) -> void:
	if simulation: simulation.set_paused(true)
	simulation = next; _generation += 1; _synced_time = 0; _navigation_time = -INF; _last_fire = -INF; _checkpoint_time = 0
	_events.clear(); _unsynced.clear()
func advance(seconds: float) -> float:
	if _disposed or not simulation or not is_finite(seconds) or seconds<=0: return 0
	if encounter_coordinator and encounter_coordinator.has_active(): encounter_coordinator.advance(seconds)
	if is_paused() or voyage.state.currentPortId != null or voyage.state.career.retired or _terminal(simulation.snapshot()): return 0
	var before: float = simulation.snapshot().time
	simulation.advance(seconds); _flush(true)
	var accepted: float = simulation.snapshot().time-before
	if not _terminal(simulation.snapshot()):
		var reconciled := _reconcile()
		if not reconciled.ok: _notice = reconciled.reason; _pauses.error = true; _update_pause()
		_update_navigation()
	if _storage and simulation.snapshot().time-_checkpoint_time>=30-1e-8 and _safe_checkpoint().ok: save_checkpoint(_storage)
	return accepted
func surrender_eligibility() -> Dictionary:
	var gate := _sea_command_gate(false)
	if not gate.ok: return gate
	if simulation.snapshot().status != "active": return _no("须在旗舰存活的真实交战中投降")
	var native: Dictionary = simulation.snapshot()
	if _ship(native,voyage.state.flagshipId).get("hull",0)<=0: return _no("旗舰已沉没")
	return {"ok":true} if native.ships.any(func(s): return s.team=="hostile" and s.hull>0 and not _captured.has(s.id) and _available.any(func(a): return a.id==s.id and a.team=="hostile")) else _no("没有可受降的未结算敌舰")
static func _same_token(a: Dictionary,b: Dictionary) -> bool: return a.get("battleId")==b.get("battleId") and a.get("tick")==b.get("tick") and a.get("lossDigest")==b.get("lossDigest")
func begin_surrender() -> Dictionary:
	var gate := surrender_eligibility()
	if not gate.ok: return gate
	simulation.refresh_snapshot(); _flush(true)
	var preview: Dictionary = voyage.quoteSurrender()
	if not preview.ok: return preview
	var was := _pauses.duplicate(); set_pause("surrender",true)
	_surrender_prompt = {"quote":preview.quote.duplicate(true),"pauseEpoch":_pause_epoch,"pauses":was}
	_revision += 1; return preview.duplicate(true)
func cancel_surrender(token: Dictionary) -> Dictionary:
	if _surrender_prompt.is_empty() or not _same_token(token,_surrender_prompt.quote.token): return _no("投降确认已失效")
	var prompt := _surrender_prompt; _surrender_prompt = {}
	_pauses.erase("surrender")
	if prompt.pauseEpoch==_pause_epoch: _pauses = prompt.pauses
	_revision += 1; _update_pause(); return {"ok":true}
func confirm_surrender(token: Dictionary) -> Dictionary:
	if _surrender_prompt.is_empty() or not _same_token(token,_surrender_prompt.quote.token) or _surrender_prompt.pauseEpoch != _pause_epoch or voyage.state.has("pendingSurrenderReceipt"): return _no("投降确认已失效")
	simulation.refresh_snapshot(); _flush(true)
	var preview: Dictionary = voyage.quoteSurrender()
	if not preview.ok: return preview
	if not _same_token(token,preview.quote.token): return _no("投降条件已变化，请重新确认")
	var candidate = Session.new()
	if not candidate.restore(voyage.serialize()): return _no(candidate.last_error)
	candidate.setPaused(true); candidate.syncNaval(simulation.snapshot(),[])
	var result: Dictionary = candidate.command({"type":"surrender","token":token})
	if not result.ok: return result
	var setups := _adapt(candidate); var bundle := _build(candidate,setups,{})
	if not bundle.ok: return bundle
	var accepted: Dictionary = simulation.encounter.command({"type":"surrender","request":{"battleId":token.battleId,"tick":token.tick,"captorId":preview.quote.terms.captor.id}})
	if not accepted.ok: return accepted
	voyage.commitFrom(candidate); _available = setups; _surrender_prompt.clear(); _revision += 1
	simulation.refresh_snapshot(); _collect(); _pauses.result = true; _update_pause()
	result.surrenderReceipt = voyage.state.pendingSurrenderReceipt.duplicate(true)
	if _storage: result.save = save_checkpoint(_storage)
	return result
func resume_voyage() -> Dictionary:
	if not _surrender_prompt.is_empty(): return _no("请先完成投降确认")
	_flush(true)
	if not _terminal(simulation.snapshot()) and not voyage.state.has("pendingSurrenderReceipt"): return _no("当前没有待确认海战结果")
	var candidate = Session.new()
	if not candidate.restore(voyage.serialize()): return _no(candidate.last_error)
	if candidate.state.has("pendingSurrenderReceipt"):
		var acknowledged: Dictionary = candidate.command({"type":"acknowledge-surrender","battleId":candidate.state.pendingSurrenderReceipt.quote.token.battleId})
		if not acknowledged.ok: return acknowledged
	var setups := _adapt(candidate); var bundle := _build(candidate,setups,{})
	if not bundle.ok: return bundle
	voyage.commitFrom(candidate); _available = setups; _captured.clear(); _replace(bundle.simulation)
	_pauses.erase("result"); _pauses.erase("surrender"); _revision += 1; _update_navigation(true); _update_pause()
	if voyage.state.currentPortId != null:
		simulation.encounter.anchorFleet(voyage.state.fleet.map(func(s): return s.id)); simulation.refresh_snapshot(); voyage.syncDockedFleet(simulation.snapshot())
	else: voyage.syncNaval(simulation.snapshot(),[])
	return {"ok":true,"navalChanged":true}
func _safe_checkpoint(owner: RefCounted=null,native: Dictionary={}) -> Dictionary:
	if _disposed or not voyage: return _no("runtime-disposed")
	if not _surrender_prompt.is_empty() or encounter_coordinator and encounter_coordinator.has_active(): return _no("请先完成当前确认或挑战")
	if _pauses.has("error"): return _no("runtime-error")
	var authority: RefCounted = owner if owner else voyage
	var actual: Dictionary = native if not native.is_empty() else simulation.snapshot()
	if actual.status=="surrendered" and not authority.state.has("pendingSurrenderReceipt"): return _no("投降尚未完成生涯结算，无法存档")
	if authority.flagship().hull<=0 or _ship(actual,authority.state.flagshipId).get("hull",0)<=0: return _no("旗舰已经沉没，请先完成救援或在港修复后存档")
	if authority.state.battleActive or simulation.encounter.hasPendingCombat(): return _no("交战或炮击尚未结束，请在安全海面或靠港后存档")
	return {"ok":true}
func export_save() -> Dictionary:
	_flush(true); var safe := _safe_checkpoint()
	return {"ok":true,"json":voyage.serialize()} if safe.ok else safe
func export_last_verified_checkpoint() -> Dictionary:
	return {"ok":true,"json":_last_verified} if not _last_verified.is_empty() else _no("没有上次已验证的安全存档")
func save_checkpoint(storage: RefCounted=null) -> Dictionary:
	var exported := export_save(); _checkpoint_time = simulation.snapshot().time if simulation else 0
	if not exported.ok: _last_receipt = exported; return exported
	var adapter: RefCounted = storage if storage else _storage
	if not adapter: adapter = SaveCoordinator.new("user://saves/legacy-v1.json",validate_save)
	if adapter is SaveCoordinator: adapter.validator = validate_save
	var written: Dictionary = adapter.write_checkpoint(exported.json)
	_last_receipt = written.duplicate(true)
	if written.ok: _last_verified = exported.json; _last_receipt.bytes = exported.json.to_utf8_buffer().size()
	return _last_receipt.duplicate(true)
func adopt_save(raw: String,storage: RefCounted=null) -> Dictionary:
	var safe := _safe_checkpoint()
	if not safe.ok: return safe
	var candidate = Session.new()
	if not candidate.restore(raw): return _no(candidate.last_error)
	if candidate.state.battleActive: return _no("交战存档缺少完整炮击状态，请导入安全航程存档")
	if candidate.flagship().hull<=0: return _no("旗舰已经沉没")
	var checkpoint: String = candidate.serialize(); var setups := _adapt(candidate); var bundle := _build(candidate,setups,{})
	if not bundle.ok: return bundle
	var adapter: RefCounted = storage if storage else _storage
	if adapter:
		if adapter is SaveCoordinator: adapter.validator = validate_save
		var written: Dictionary = adapter.write_checkpoint(checkpoint)
		if not written.ok: return written
		_last_verified = checkpoint
	if encounter_coordinator: encounter_coordinator.dispose()
	voyage = candidate; _available = setups; _captured.clear(); _replace(bundle.simulation)
	encounter_coordinator = Coordinator.new(self); _surrender_prompt.clear(); _pauses.erase("error"); _pauses.erase("result"); _pauses.erase("surrender")
	_revision += 1; _update_pause(); _update_navigation(true)
	if voyage.state.currentPortId != null:
		simulation.encounter.anchorFleet(voyage.state.fleet.map(func(s): return s.id)); simulation.refresh_snapshot(); voyage.syncDockedFleet(simulation.snapshot())
	else: voyage.syncNaval(simulation.snapshot(),[])
	return {"ok":true,"bytes":checkpoint.to_utf8_buffer().size()}
func snapshot() -> Dictionary:
	if not voyage or not simulation: return {}
	_flush(true)
	var safe := _safe_checkpoint()
	return {"adventure":voyage.snapshot(),"naval":simulation.snapshot(),"runtime":{"generation":_generation,"revision":_revision,"paused":is_paused(),"pauseReasons":_pauses.keys(),"handlingMode":_handling_mode,"handlingStatus":simulation.handling_status(),"notice":_notice,"canSave":safe.ok,"saveReason":safe.get("reason",""),"surrenderQuote":_surrender_prompt.get("quote"),"surrenderEligibility":surrender_eligibility(),"pendingSurrenderReceipt":voyage.state.get("pendingSurrenderReceipt"),"encounter":encounter_coordinator.snapshot() if encounter_coordinator else null,"lastSaveReceipt":_last_receipt}}.duplicate(true)
func native_snapshot() -> Dictionary: return simulation.encounter.snapshot() if simulation else {}
func render_snapshot() -> Dictionary: return simulation.render_snapshot() if simulation else {}
func drain_events() -> Array:
	_collect(); var incoming := _events; _events = []; return incoming.duplicate(true)
func drain_results() -> Array: return simulation.drain_results() if simulation else []
func sample_water_height(x: float,z: float,seconds: float=NAN) -> float:
	return _waves.sample(x,z,simulation.snapshot().time if is_nan(seconds) and simulation else 0 if is_nan(seconds) else seconds).height if _waves else 0
func dispose() -> void:
	_disposed = true; _generation += 1; _events.clear(); _unsynced.clear(); _surrender_prompt.clear()
	if encounter_coordinator: encounter_coordinator.dispose()
	if simulation: simulation.set_paused(true)
	encounter_coordinator = null; simulation = null; voyage = null
