extends RefCounted
## Production-reusable coordinator; one-way presentation only.
## One binding coordinator acknowledges the complete ocean texture/bounds pair.
const Field = preload("res://modules/scene_engine/water/interactive_wake_field.gd")
const Producer = preload("res://modules/scene_engine/water/ship_water_interaction.gd")
const MAX_ACTORS := 3
var _ocean: Object
var _water := Callable()
var _field: RefCounted
var _producer := Producer.new()
var _factory := Callable()
var _field_options: Dictionary = {}
var _mask: Dictionary = {}
var _mask_digest := ""
var _configured := false
var _disposed := false
var _error := ""
var _epoch := ""
var _epoch_set := false
var _last_time := NAN
var _center := Vector2.ZERO
var _live: Dictionary = {}
var _history: Dictionary = {}
var _selected: Array[String] = []
var _covered: Array[String] = []
var _results: Dictionary = {}
var _records: Dictionary = {}
var _bound_ids: Array[String] = []
var _bound_record: Dictionary = {}
var _bound_generation := -1
var _bound_bounds := Vector4.ZERO
var _bound := false
var _resets := 0
var _excluded: Dictionary = {}

func configure(ocean: Object, water: Callable, wet_mask: Dictionary, options: Dictionary = {}) -> Dictionary:
	if _disposed or _configured:return {"ok":false,"error":"System disposed or already configured"}
	if not water.is_valid():return {"ok":false,"error":"Invalid water callable"}
	_configured=true;_ocean=ocean;_water=water
	_factory=options.get("field_factory",Callable())
	_field_options=options.get("field_options",options).duplicate(true)
	_field_options.erase("field_factory");_field_options.erase("field_options");_field_options.erase("wet_mask")
	var normalized:=_normalize_mask(wet_mask)
	if not normalized.ok:_error=normalized.error;return {"ok":false,"error":_error}
	_mask=normalized.mask;_mask_digest=_digest(_mask)
	_create_field()
	return {"ok":_error.is_empty(),"error":_error,"pending":_field!=null}

func _normalize_mask(value: Dictionary) -> Dictionary:
	if value.get("valid",true)!=true:return {"ok":false,"error":"Terrain mask explicitly invalid"}
	if value.is_empty():return {"ok":true,"mask":{}}
	var n: Variant=value.get("resolution")
	var bounds: Variant=value.get("bounds")
	var data: Variant=value.get("data")
	if not n is int or n<=0 or n>4096 or not bounds is Vector4 or not bounds.is_finite():
		return {"ok":false,"error":"Invalid terrain mask geometry"}
	if bounds.z<=bounds.x or bounds.w<=bounds.y or not data is PackedByteArray or data.size()!=n*n:
		return {"ok":false,"error":"Invalid terrain mask bytes or bounds"}
	# revision/cell_m are producer metadata, not GPU options or mask identity.
	return {"ok":true,"mask":{"resolution":n,"bounds":bounds,"data":data.duplicate()}}
func _digest(value: Dictionary) -> String:
	var hashing:=HashingContext.new();hashing.start(HashingContext.HASH_SHA256)
	hashing.update(var_to_bytes(value));return hashing.finish().hex_encode()
func _clear_binding() -> void:
	if is_instance_valid(_ocean) and _ocean.has_method("bind_interactive_wake_field"):
		_ocean.bind_interactive_wake_field(null,Vector4.ZERO,false)
	_bound=false;_bound_generation=-1;_bound_bounds=Vector4.ZERO;_bound_ids.clear();_covered.clear()
func _create_field() -> void:
	if _disposed:return
	_error=""
	_field=_factory.call() if _factory.is_valid() else Field.new()
	if _field==null:_error="Field factory returned no owner";return
	var options:=_field_options.duplicate(true);options.wet_mask=_mask.duplicate(true)
	var result: Dictionary=_field.configure(options)
	if not result.get("ok",false):
		_error=str(result.get("error","Field configuration failed"));_field.dispose();_field=null
func _reset_field(reason: String) -> void:
	_clear_binding()
	if _field!=null:_field.dispose()
	_field=null;_producer.clear();_history.clear();_results.clear();_records.clear();_selected.clear()
	_bound_record.clear()
	_last_time=NAN;_resets+=1;_excluded={"reset":reason}
	_create_field()

func set_ocean(new_ocean: Object, wet_mask: Dictionary) -> Dictionary:
	if _disposed:return diagnostics()
	_clear_binding();_ocean=new_ocean
	var normalized:=_normalize_mask(wet_mask)
	if not normalized.ok:
		if _field!=null:_field.dispose()
		_field=null;_producer.clear();_history.clear();_results.clear();_records.clear();_selected.clear();_last_time=NAN
		_bound_record.clear()
		_mask_digest="";_error=normalized.error;return diagnostics()
	var digest:=_digest(normalized.mask)
	if digest!=_mask_digest or _field==null:
		_mask=normalized.mask;_mask_digest=digest;_reset_field("mask-changed")
	return poll()

func _anchor(attachment: Dictionary) -> Vector2:
	var profile: Dictionary=attachment.get("surfaceProfile",{})
	if profile.get("hullToWorld") is Transform3D:
		var pos: Vector3=profile.hullToWorld.origin
		if pos.is_finite():return Vector2(pos.x,pos.z)
	return Vector2(INF,INF)
func _field_bounds(center: Vector2) -> Vector4:
	var extent:=float(_field_options.get("extent_m",96.0))
	var cell:=extent/float(_field_options.get("resolution",256))
	var minimum: Vector2=(center/cell).floor()*cell-Vector2.ONE*extent*0.5
	return Vector4(minimum.x,minimum.y,minimum.x+extent,minimum.y+extent)
func _margin() -> float:
	return float(_field_options.get("edge_cells",12.0))*float(_field_options.get("extent_m",96.0))/float(_field_options.get("resolution",256))
func _fits(result: Dictionary, bounds: Vector4, current_attachment: Dictionary = {}) -> bool:
	var emitters: Array=result.get("emitters",[])
	if emitters.size()!=5:return false
	var transform: Variant=current_attachment.get("surfaceProfile",{}).get("hullToWorld")
	var probes: Array=result.get("diagnostics",{}).get("probes",[])
	for i in emitters.size():
		var point: Vector3=emitters[i].position
		if transform is Transform3D and probes.size()==5:point=transform*probes[i].local_position
		var margin:=_margin()+float(emitters[i].radius)
		if not point.is_finite() or point.x<bounds.x+margin or point.z<bounds.y+margin or point.x>bounds.z-margin or point.z>bounds.w-margin:return false
	return true
func _center_from(result: Dictionary) -> Vector2:
	var d: Dictionary=result.diagnostics
	var emitters: Array=result.emitters
	var rear: Vector3=(emitters[0].position+emitters[1].position)*0.5
	var forward3: Vector3=emitters[4].position-rear
	var forward:=Vector2(forward3.x,forward3.z).normalized()
	var stern: Vector3=d.stern
	var extent:=float(_field_options.get("extent_m",96.0))
	return Vector2(stern.x,stern.z)-forward*(extent*0.5-float(d.length_m)-8.0)
func _sample(id: String, actor: Dictionary, seconds: float) -> Dictionary:
	var result: Dictionary=_producer.sample(id,actor.attachment,seconds,_water,true)
	if result.get("diagnostics",{}).get("accepted",false):_history[id]=true
	return result
func _selection(seconds: float, focus_id: String) -> Dictionary:
	var candidates: Array=[]
	var focus_anchor: Vector2=_anchor(_live[focus_id].attachment) if _live.has(focus_id) else _center
	if not focus_anchor.is_finite():focus_anchor=_center
	for id: String in _live:
		var distance:=_anchor(_live[id].attachment).distance_squared_to(focus_anchor)
		candidates.append({"id":id,"distance":distance,"focus":id==focus_id})
	candidates.sort_custom(func(a,b):
		if a.focus!=b.focus:return a.focus
		return str(a.id)<str(b.id) if a.distance==b.distance else a.distance<b.distance)
	var selected: Array[String]=[];var results: Dictionary={};var chosen_center:=_center
	var centered:=false;var warp:=false;var accepted_count:=0
	_excluded={}
	for candidate: Dictionary in candidates:
		var id: String=candidate.id
		if selected.size()>=MAX_ACTORS:_excluded[id]="actor-capacity";continue
		var result:=_sample(id,_live[id],seconds)
		if not result.get("diagnostics",{}).get("accepted",false):_excluded[id]=result.get("diagnostics",{}).get("reason","invalid");continue
		accepted_count+=1
		if not centered:chosen_center=_center_from(result);centered=true
		if not _fits(result,_field_bounds(chosen_center)):
			_excluded[id]="outside-safe-field";_producer.forget(id);_history.erase(id);continue
		selected.append(id);results[id]=result
		if result.diagnostics.reason in ["teleport","rewind","profile-changed","gap"]:warp=true
	for id: String in _history.keys():
		if id not in selected:_producer.forget(id);_history.erase(id)
	return {"ids":selected,"results":results,"center":chosen_center,"warp":warp,"accepted_count":accepted_count}

func apply_snapshot(seconds: float, focus_id: String, actors: Array, epoch: String) -> Dictionary:
	if _disposed or not _configured:return diagnostics()
	if not is_finite(seconds) or seconds<0.0 or seconds>1e12:
		var invalid:=diagnostics();invalid.input_error="Invalid accepted time";return invalid
	var live: Dictionary={}
	for actor in actors:
		if not actor is Dictionary or not actor.get("id") is String or actor.id.is_empty():continue
		if not actor.get("hull_alive",true) or not actor.get("attachment") is Dictionary:continue
		if live.has(actor.id):continue
		live[actor.id]={"attachment":actor.attachment.duplicate(true)}
	_live=live
	# Removals apply even during pause; they must not hide an actor behind stale coverage.
	for id: String in _history.keys():
		if not _live.has(id):_producer.forget(id);_history.erase(id);_results.erase(id);_selected.erase(id)
	if _field==null:return poll()
	if (_epoch_set and epoch!=_epoch) or (not is_nan(_last_time) and seconds<_last_time):
		_reset_field("epoch-or-rewind")
	_epoch=epoch;_epoch_set=true
	if _field==null:return poll()
	if seconds==_last_time:return poll()
	var selection:=_selection(seconds,focus_id)
	if selection.warp:
		_reset_field("actor-warp")
		if _field==null:return poll()
		selection=_selection(seconds,focus_id)
	_selected=selection.ids;_results=selection.results;_center=selection.center
	var emitters: Array=[];var wakes: Array=[]
	for id: String in _selected:
		var result: Dictionary=_results[id]
		emitters.append_array(result.emitters)
		if not result.wake.is_empty():wakes.append(result.wake)
	# Empty fleets still age historical foam; invalid nonempty input does not invent force.
	if selection.accepted_count>0 or _live.is_empty():
		_records[seconds]=_selected.duplicate()
		# Preserve the oldest in-flight record plus the latest fifteen queued candidates.
		while _records.size()>16:
			var keys:=_records.keys();keys.sort();_records.erase(keys[1])
		_last_time=seconds
		_field.advance(seconds,_center,emitters,wakes)
	return poll()

func poll() -> Dictionary:
	if _disposed or _field==null:_covered.clear();return diagnostics()
	var state: Dictionary=_field.diagnostics()
	if not str(state.get("error","")).is_empty():
		_error=str(state.error);_clear_binding();return diagnostics()
	var surface: Dictionary=_field.acquire_surface()
	if surface.is_empty():_covered.clear();return diagnostics()
	if not is_instance_valid(_ocean) or not _ocean.has_method("bind_interactive_wake_field"):
		_bound=false;_covered.clear();return diagnostics()
	var generation:=int(surface.generation)
	if generation!=_bound_generation or not _bound:
		var bound: bool=_ocean.bind_interactive_wake_field(surface.texture,surface.bounds,true)
		if not bound:_bound=false;_covered.clear();return diagnostics()
		_bound=true;_bound_generation=generation;_bound_bounds=surface.bounds
		var applied:bool=int(state.get("resets",0))>0
		var ids:Array=_records.get(float(surface.time),[]) if applied else []
		# Quality rebuild can bind the same already-consumed field generation.
		if ids.is_empty() and applied and int(_bound_record.get("generation",-2))==generation:
			ids=_bound_record.get("ids",[])
		_bound_ids.assign(ids)
		_bound_record={"generation":generation,"ids":_bound_ids.duplicate()}
		_field.acknowledge_surface(generation)
		if applied:
			for key in _records.keys():
				if float(key)<=float(surface.time):_records.erase(key)
	_covered.clear()
	for id: String in _bound_ids:
		if id in _selected and _live.has(id) and _results.has(id) and _fits(_results[id],_bound_bounds,_live[id].attachment):_covered.append(id)
	return diagnostics()
func covered_actor_ids() -> Array[String]:return _covered.duplicate()
func diagnostics() -> Dictionary:
	return {"configured":_configured,"disposed":_disposed,"error":_error,"epoch":_epoch,"resets":_resets,
		"time":0.0 if is_nan(_last_time) else _last_time,"center":_center,"selected":_selected.duplicate(),"covered":_covered.duplicate(),
		"bound":_bound,"bound_generation":_bound_generation,"bound_bounds":_bound_bounds,"mask_digest":_mask_digest,
		"excluded":_excluded.duplicate(true),"history_actors":_history.size(),"pending_records":_records.size(),
		"field":_field.diagnostics() if _field!=null else {}}
func dispose() -> void:
	if _disposed:return
	_disposed=true;_clear_binding()
	if _field!=null:_field.dispose()
	_field=null;_producer.clear();_history.clear();_live.clear();_results.clear();_records.clear();_selected.clear()
	_bound_record.clear()
