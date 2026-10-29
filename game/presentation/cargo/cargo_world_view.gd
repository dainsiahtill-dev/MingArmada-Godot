extends Node3D
## Receipt-only cargo presentation. No inventory mutation, recovery or own clock.
const Deck = preload("res://game/presentation/cargo/cargo_deck_view.gd")
const Models = preload("res://game/presentation/cargo/cargo_models.gd")
const DriftPath := "res://game/presentation/cargo/cargo_drift.gd"
var _provider := Models.new()
var _ship_provider: Callable
var _drift: RefCounted
var _decks: Dictionary = {}
var _source_ids: Dictionary = {}
var _floating: Dictionary = {}
var _submitted: Dictionary = {}
var _epoch := ""
var _time := -1.0
var _ready_view := false
var _errors: Array = []

func configure(water: Callable, ship_provider: Callable) -> Dictionary:
	if not water.is_valid() or not ship_provider.is_valid(): return {"ok":false,"reason":"invalid-cargo-providers"}
	var script = load(DriftPath)
	if script == null: return {"ok":false,"reason":"cargo-drift-unavailable"}
	var prepared: RefCounted = script.new()
	if not prepared.configure(water,{"launch_spread":0.8}): return {"ok":false,"reason":"cargo-drift-configure"}
	dispose()
	_drift=prepared; _ship_provider=ship_provider; _ready_view=true
	set_as_top_level(true); transform=Transform3D.IDENTITY
	return {"ok":true}

static func _finite(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

func apply_snapshot(native: Dictionary, cargo: Dictionary) -> Dictionary:
	if not _ready_view: return {"ok":false,"reason":"cargo-not-ready"}
	if not cargo.get("epoch") is String or cargo.epoch.is_empty() or not _finite(cargo.get("time")) or cargo.time<0.0 or not _finite(native.get("time")) or native.time<0.0 or not cargo.get("manifests") is Dictionary or not cargo.get("drops") is Array:
		return {"ok":false,"reason":"invalid-cargo-packet"}
	for id: Variant in cargo.manifests:
		if not id is String or not cargo.manifests[id] is Dictionary: return {"ok":false,"reason":"invalid-manifest"}
		for good: Variant in cargo.manifests[id]:
			var count: Variant=cargo.manifests[id][good]
			if not good in Models.GOODS or not _finite(count) or count<0.0 or count!=floor(float(count)) or count>9007199254740991.0: return {"ok":false,"reason":"invalid-manifest-quantity"}
	if _epoch != cargo.epoch or float(cargo.time)<_time:
		_clear_visuals(); _drift.reset()
	_epoch=cargo.epoch; _time=float(cargo.time); _errors.clear()
	var live: Dictionary = {}
	for id: String in cargo.manifests:
		var source: Dictionary = _ship_provider.call(id)
		var model: Node3D=source.get("model")
		if not is_instance_valid(model) or not model.is_inside_tree(): continue
		live[id]=true
		if _source_ids.get(id,0)!=model.get_instance_id():
			_release_deck(id)
			var deck := Deck.new(); add_child(deck)
			var receipt: Dictionary=deck.configure(model,str(source.get("kind","")))
			if not receipt.get("ok",false):
				_errors.append({"ship":id,"reason":receipt.get("reason")}); deck.free(); continue
			_decks[id]=deck; _source_ids[id]=model.get_instance_id()
		if _decks.has(id):
			var receipt: Dictionary=_decks[id].apply_manifest(cargo.manifests[id],_time)
			if not receipt.get("ok",false) or not receipt.get("complete",true): _errors.append({"ship":id,"receipt":receipt})
	for id: String in _decks.keys():
		if not live.has(id): _release_deck(id)
	for id: String in _submitted.keys():
		if _time-float(_submitted[id])>=40.0: _submitted.erase(id)
	for details: Variant in cargo.drops:
		if not details is Dictionary: continue
		var id: String=str(details.get("dropId",""))
		if _submitted.has(id): continue
		if _finite(details.get("campaignTime")) and _time-float(details.campaignTime)>=40.0: continue
		var accepted: Dictionary=_drift.add_drop(details,_time)
		if accepted.get("ok",false): _submitted[id]=float(details.campaignTime)
	_drift.advance(_time,float(native.time),native.get("wind",{}))
	var active: Dictionary = {}
	for lot: Dictionary in _drift.snapshot():
		var id: String=lot.dropId; active[id]=true
		if not _floating.has(id):
			var model: Node3D=_provider.get_model(lot.goodId)
			if model==null: _errors.append({"drop":id,"reason":"cargo-model-unavailable"}); continue
			var package_scale: float=Deck.MODEL_SCALE
			if _decks.has(str(lot.shipId)):
				package_scale=float(_decks[str(lot.shipId)].snapshot().layout_profile.model_scale)
			add_child(model); model.scale=Vector3.ONE*package_scale; _floating[id]=model
		var model: Node3D=_floating[id]
		model.position=Vector3(lot.position[0],lot.position[1],lot.position[2])
		model.rotation=Vector3(lot.rotation[0],lot.rotation[1],lot.rotation[2])
		model.set_meta("cargo_quantity",lot.quantity)
		model.set_meta("cargo_drop_id",id)
		for child: Node in model.find_children("*","GeometryInstance3D",true,false): child.transparency=1.0-float(lot.alpha)
		if model is GeometryInstance3D: model.transparency=1.0-float(lot.alpha)
	for id: String in _floating.keys():
		if not active.has(id): _floating[id].free(); _floating.erase(id)
	return {"ok":_errors.is_empty(),"errors":_errors.duplicate(true)}

func drain_splashes() -> Array:
	return _drift.drain_splashes() if _drift else []

func inspection_snapshot() -> Dictionary:
	var decks: Dictionary={}
	for id: String in _decks: decks[id]=_decks[id].snapshot()
	return {"ready":_ready_view,"epoch":_epoch,"time":_time,"decks":decks,"floating":_drift.snapshot() if _drift else [],"drift":_drift.diagnostics() if _drift else {},"errors":_errors.duplicate(true),"floating_nodes":_floating.size()}

func _release_deck(id: String) -> void:
	if _decks.has(id): _decks[id].dispose(); _decks[id].free(); _decks.erase(id)
	_source_ids.erase(id)

func _clear_visuals() -> void:
	_submitted.clear()
	for id: String in _decks.keys(): _release_deck(id)
	for model: Node3D in _floating.values(): model.free()
	_floating.clear()

func dispose() -> void:
	_ready_view=false; _clear_visuals()
	if _drift: _drift.dispose()
	_drift=null; _ship_provider=Callable(); _epoch=""; _time=-1.0; _errors.clear()

func _exit_tree() -> void: dispose()
