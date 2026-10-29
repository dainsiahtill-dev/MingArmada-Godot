extends Node3D
## Read-only cargo projection on actual deck support; no inventory/crew authority.
const Models = preload("res://game/presentation/cargo/cargo_models.gd")
const DeckSupport = preload("res://game/presentation/crew/deck_stations.gd")
const AssetLibrary = preload("res://modules/scene_engine/assets/asset_library.gd")
const GOODS := Models.GOODS
const SHIP_KINDS := ["fuchuan", "fisherman", "merchant", "voc", "patrol", "heavy"]
const MODEL_SCALE := .72
const BOX_SIZE := Vector3(.95, 1.1, .95)
const HALF_FOOTPRINT := .475
const SCAN_STEP := .65
const WALKWAY_HALF_WIDTH := .7
const STATION_CLEARANCE := .95
const OBSTACLE_MARGIN := .1
const MIN_NORMAL_Y := .94
const MAX_HEIGHT_SPREAD := .15
const MAIN_DECK_ALLOWANCE := .65
const SUPPORT_LIFT := .005
const MERCHANT_SCALE := .5
const MERCHANT_STATION_CLEARANCE := .65
const MERCHANT_SCAN_STEP := .325
static var _crew_rest_cache: Dictionary = {}
var _provider = Models.new()
var _model: Node3D
var _deck
var _kind := ""
var _slots: Array[Dictionary] = []
var _instances: Dictionary = {}
var _manifest: Dictionary = {}
var _overflow: Array[String] = []
var _time := 0.0
var _frame := Transform3D.IDENTITY
var _source_bounds := AABB()
var _candidate_count := 0
var _scan_count := 0
var _disposed := true
var _layout_profile: Dictionary = {}
var _main_deck_band: Dictionary = {}

func _ready() -> void:
	refresh_transform()

func configure(model: Node3D, kind: String) -> Dictionary:
	# Prepare first: a bad replacement cannot destroy the current accepted view.
	if not kind in SHIP_KINDS: return _rejected("unsupported_ship_kind")
	if not is_instance_valid(model) or not model.is_inside_tree(): return _rejected("source_model_not_attached")
	if model == self or model.is_ancestor_of(self): return _rejected("cargo_view_must_be_outside_source_model")
	var next_frame := model.global_transform
	if not _finite_frame(next_frame): return _rejected("invalid_source_transform")
	var next_deck = DeckSupport.new()
	if not next_deck.configure(kind, model): return _rejected("actual_deck_support_unavailable")
	var profile := {"model_scale":MODEL_SCALE,"box_size":BOX_SIZE,"scan_step":SCAN_STEP,"station_clearance":STATION_CLEARANCE}
	var band := {"method":"authored_deck_bounds_baseline","high":float(next_deck.bounds.position.y)+MAIN_DECK_ALLOWANCE}
	if kind == "merchant":
		# support-probe-05: actual mixed hull/deck source, twelve slots at this
		# scale/clearance/grid. The fuchuan baseline remains numerically unchanged.
		var worker := _original_crew_bounds()
		if worker.is_empty(): return _rejected("original_worker_bounds_unavailable")
		profile={"model_scale":MERCHANT_SCALE,"box_size":BOX_SIZE*(MERCHANT_SCALE/MODEL_SCALE),"scan_step":MERCHANT_SCAN_STEP,"station_clearance":MERCHANT_STATION_CLEARANCE,"crew_rest_bounds":worker.bounds,"crew_rest_margin":.05}
		band=_dominant_exposed_band(next_deck)
	var placement := _find_slots(next_deck,band,profile)
	_clear_instances()
	_model = model
	_deck = next_deck
	_kind = kind
	_slots = placement.slots
	_candidate_count = int(placement.candidate_count)
	_scan_count = int(placement.scan_count)
	_source_bounds = next_deck.bounds
	_layout_profile = profile
	_main_deck_band = band
	_manifest.clear()
	_overflow.clear()
	_time = 0.0
	_frame = next_frame
	_disposed = false
	set_as_top_level(true)
	refresh_transform()
	return {"ok": true, "complete": _slots.size() == GOODS.size(), "reason": "" if _slots.size() == GOODS.size() else "insufficient_safe_slots", "available_slots": _slots.size(), "required_slots": GOODS.size(), "candidate_count": _candidate_count, "scan_count": _scan_count}

func apply_manifest(cargo: Dictionary, accepted_time: float) -> Dictionary:
	if _disposed: return _rejected("not_configured")
	if not is_finite(accepted_time) or accepted_time < 0.0: return _rejected("invalid_accepted_time")
	var next_manifest: Dictionary = {}
	for key in cargo:
		if not (key is String or key is StringName) or not str(key) in GOODS: return _rejected("unsupported_good")
		var value = cargo[key]
		if not (value is int or value is float): return _rejected("invalid_quantity")
		var quantity := float(value)
		if not is_finite(quantity) or quantity < 0.0: return _rejected("invalid_quantity")
		next_manifest[str(key)] = quantity
	# Resolve every required new resource before changing a node or its metadata.
	var staged: Dictionary = {}
	var next_overflow: Array[String] = []
	for index in GOODS.size():
		var good: String = GOODS[index]
		if float(next_manifest.get(good, 0.0)) <= 0.0: continue
		if index >= _slots.size():
			next_overflow.append(good)
			continue
		if _instances.has(good): continue
		var instance: Node3D = _provider.get_model(good)
		if instance == null:
			for created: Node3D in staged.values(): created.free()
			return _rejected("cargo_asset_unavailable:" + good)
		staged[good] = instance
	for good: String in _instances.keys():
		if float(next_manifest.get(good, 0.0)) <= 0.0 or next_overflow.has(good):
			var old: Node3D = _instances[good]
			_instances.erase(good)
			old.free()
	for good: String in staged:
		var created: Node3D = staged[good]
		add_child(created)
		_instances[good] = created
	for index in GOODS.size():
		var good: String = GOODS[index]
		if not _instances.has(good): continue
		var instance: Node3D = _instances[good]
		instance.position = _slots[index].local_position
		instance.rotation = Vector3.ZERO
		instance.scale = Vector3.ONE * float(_layout_profile.get("model_scale",MODEL_SCALE))
		instance.visible = true
		instance.set_meta("cargo_quantity", float(next_manifest[good]))
		instance.set_meta("cargo_slot_index", index)
	_manifest = next_manifest
	_overflow = next_overflow
	_time = accepted_time
	refresh_transform()
	return {"ok": true, "complete": _overflow.is_empty(), "visible_goods": _instances.size(), "overflow_goods": _overflow.duplicate(), "accepted_time": _time, "available_slots": _slots.size()}

func refresh_transform() -> Dictionary:
	if _disposed: return _rejected("not_configured")
	if not is_instance_valid(_model) or not _model.is_inside_tree():
		visible = false
		return _rejected("source_model_not_attached")
	var next := _model.global_transform
	if not _finite_frame(next): return _rejected("invalid_source_transform")
	_frame = next
	# This independent node copies the real LOD0 frame, including sink/roll once.
	# It is never parented under LOD0, so LOD visibility cannot suppress cargo.
	if is_inside_tree(): global_transform = _frame
	else: transform = _frame
	visible = true
	return {"ok": true}

func anchor(good: String) -> Dictionary:
	if _disposed or not _instances.has(good): return {}
	var index := GOODS.find(good)
	var local: Vector3 = _slots[index].local_position
	return {"good": good, "quantity": float(_manifest[good]), "slot_index": index, "position": _frame * local, "local_position": local, "slot_bounds": _slots[index].slot_bounds, "accepted_time": _time}

func snapshot() -> Dictionary:
	var records: Array[Dictionary] = []
	for index in GOODS.size():
		var good: String = GOODS[index]
		if not _instances.has(good): continue
		var instance: Node3D = _instances[good]
		var local: Vector3 = _slots[index].local_position
		records.append({"good": good, "quantity": float(_manifest[good]), "slot_index": index, "local_anchor": local, "world_anchor": _frame * local, "slot_bounds": _slots[index].slot_bounds, "visible": instance.visible and visible, "asset_path": str(instance.get_meta("cargo_asset_path", ""))})
	return {"configured": not _disposed, "disposed": _disposed, "kind": _kind, "accepted_time": _time, "manifest": _manifest.duplicate(true), "goods": records, "slots": _slots.duplicate(true), "available_slots": _slots.size(), "required_slots": GOODS.size(), "overflow_goods": _overflow.duplicate(), "all_requested_visible": _overflow.is_empty(), "frame": _frame, "source_bounds": _source_bounds, "source_attached": is_instance_valid(_model) and _model.is_inside_tree(), "candidate_count": _candidate_count, "scan_count": _scan_count, "layout_profile":_layout_profile.duplicate(true), "main_deck_band":_main_deck_band.duplicate(true)}

func dispose() -> void:
	_clear_instances()
	_model = null
	_deck = null
	_kind = ""
	_slots.clear()
	_manifest.clear()
	_overflow.clear()
	_time = 0.0
	_frame = Transform3D.IDENTITY
	_source_bounds = AABB()
	_candidate_count = 0
	_scan_count = 0
	_layout_profile.clear()
	_main_deck_band.clear()
	_disposed = true

func _clear_instances() -> void:
	for instance: Node3D in _instances.values():
		if is_instance_valid(instance): instance.free()
	_instances.clear()

func _rejected(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

func _finite_frame(value: Transform3D) -> bool:
	return value.origin.is_finite() and value.basis.x.is_finite() and value.basis.y.is_finite() and value.basis.z.is_finite()

func _original_crew_bounds() -> Dictionary:
	if not _crew_rest_cache.is_empty(): return _crew_rest_cache.duplicate(true)
	var library := AssetLibrary.new()
	var model: Node3D=library.instantiate_model("res://assets/models/sailors/sailor-lod0.glb")
	if model==null:
		library.dispose()
		return {}
	# Local transforms suffice on this detached read-only original model.
	var gather := DeckSupport.new()
	var bounds: AABB=gather._bounds(model,model)
	model.free();library.dispose()
	if bounds.size.x<=0.0 or bounds.size.y<=0.0 or bounds.size.z<=0.0:return {}
	_crew_rest_cache={"bounds":bounds,"source":"res://assets/models/sailors/sailor-lod0.glb","scope":"static original mesh envelope; work-pose GPU validation remains separate"}
	return _crew_rest_cache.duplicate(true)

func _dominant_exposed_band(deck) -> Dictionary:
	# A fixed source census is independent of cargo count and package scale.
	# Highest real upward support excludes hidden lower hull triangles; area is
	# estimated by fixed .65m sample cells, never by the merged mesh's keel bound.
	var bounds: AABB=deck.bounds
	var heights: Array[float]=[]
	var nx:=maxi(0,int(floor((bounds.size.x-BOX_SIZE.x)/SCAN_STEP))+1)
	var nz:=maxi(0,int(floor((bounds.size.z-BOX_SIZE.z)/SCAN_STEP))+1)
	for iz in nz:
		for ix in nx:
			var support: Dictionary=deck.sample(bounds.position.x+HALF_FOOTPRINT+float(ix)*SCAN_STEP,bounds.position.z+HALF_FOOTPRINT+float(iz)*SCAN_STEP)
			if support.is_empty() or support.normal.y<MIN_NORMAL_Y:continue
			var point: Vector3=support.point
			if point.is_finite() and point.y>.05:heights.append(point.y)
	if heights.is_empty():return {}
	heights.sort()
	var best_start:=0;var best_end:=0;var end:=0
	for start in heights.size():
		end=maxi(end,start)
		while end<heights.size() and heights[end]-heights[start]<=MAIN_DECK_ALLOWANCE:end+=1
		if end-start>best_end-best_start:best_start=start;best_end=end
	return {"method":"dominant_exposed_surface_band","low":heights[best_start],"high":heights[best_start]+MAIN_DECK_ALLOWANCE,"observed_high":heights[best_end-1],"samples":best_end-best_start,"total_samples":heights.size(),"sampled_area_m2":float(best_end-best_start)*SCAN_STEP*SCAN_STEP}

func _find_slots(deck,band:Dictionary,profile:Dictionary) -> Dictionary:
	var selected: Array[Dictionary] = []
	var safe_candidates := 0
	var scanned := 0
	if band.is_empty():return {"slots":selected,"candidate_count":0,"scan_count":0}
	var bounds: AABB = deck.bounds
	var size:Vector3=profile.box_size
	var step:float=profile.scan_step
	var half_x:float=HALF_FOOTPRINT if size==BOX_SIZE else size.x*.5
	var half_z:float=HALF_FOOTPRINT if size==BOX_SIZE else size.z*.5
	var nx := maxi(0, int(floor((bounds.size.x - size.x) / step)) + 1)
	var nz := maxi(0, int(floor((bounds.size.z - size.z) / step)) + 1)
	for iz in nz:
		var z := bounds.position.z + half_z + float(iz) * step
		for ix in nx:
			var x := bounds.position.x + half_x + float(ix) * step
			scanned += 1
			var slot := _candidate(deck, x, z,band,profile)
			if slot.is_empty(): continue
			safe_candidates += 1
			var collision := false
			for other: Dictionary in selected:
				if (slot.slot_bounds as AABB).intersects(other.slot_bounds):
					collision = true
					break
			if collision: continue
			slot.index = selected.size()
			slot.good = GOODS[selected.size()]
			selected.append(slot)
			if selected.size() == GOODS.size():
				return {"slots": selected, "candidate_count": safe_candidates, "scan_count": scanned}
	return {"slots": selected, "candidate_count": safe_candidates, "scan_count": scanned}

func _candidate(deck, x: float, z: float,band:Dictionary,profile:Dictionary) -> Dictionary:
	var size:Vector3=profile.box_size
	var half_x:float=HALF_FOOTPRINT if size==BOX_SIZE else size.x*.5
	var half_z:float=HALF_FOOTPRINT if size==BOX_SIZE else size.z*.5
	var clearance:float=profile.station_clearance
	var footprint := AABB(Vector3(x - half_x, 0, z - half_z), size)
	if footprint.position.x < WALKWAY_HALF_WIDTH and footprint.end.x > -WALKWAY_HALF_WIDTH: return {}
	# Station/walk tests are horizontal and reject cheaply before triangle queries.
	for station: Dictionary in deck.stations:
		var p: Vector3 = station.position
		if _point_box_distance(Vector2(p.x, p.z), footprint) < clearance: return {}
		if station.has("patrol"):
			var end: Vector3 = station.patrol
			if _segment_box_distance(Vector2(p.x, p.z), Vector2(end.x, end.z), footprint) < clearance: return {}
	var samples := PackedVector3Array()
	var low := INF
	var high := -INF
	var normal := Vector3.UP
	for offset: Vector2 in [Vector2.ZERO, Vector2(-half_x, -half_z), Vector2(-half_x, half_z), Vector2(half_x, -half_z), Vector2(half_x, half_z)]:
		var support: Dictionary = deck.sample(x + offset.x, z + offset.y)
		if support.is_empty(): return {}
		var point: Vector3 = support.point
		var slope: Vector3 = support.normal
		if not point.is_finite() or not slope.is_finite() or slope.y < MIN_NORMAL_Y: return {}
		if point.y > float(band.high): return {}
		if band.has("low") and point.y<float(band.low)-1e-5:return {}
		if samples.is_empty(): normal = slope
		samples.append(point)
		low = minf(low, point.y)
		high = maxf(high, point.y)
	if high - low > MAX_HEIGHT_SPREAD: return {}
	var local := Vector3(x, high + SUPPORT_LIFT, z)
	var box := AABB(local + Vector3(-half_x, 0, -half_z), size)
	for obstacle: AABB in deck._obstacles:
		if box.intersects(obstacle.grow(OBSTACLE_MARGIN)): return {}
	if profile.has("crew_rest_bounds"):
		var rest:AABB=profile.crew_rest_bounds
		for station:Dictionary in deck.stations:
			var basis:=Basis(Quaternion(Vector3.UP,station.normal))*Basis(Vector3.UP,station.heading)
			var actor_box:AABB=Transform3D(basis,station.position)*rest.grow(float(profile.crew_rest_margin))
			if station.has("patrol"):actor_box=actor_box.merge(AABB(actor_box.position+(station.patrol-station.position),actor_box.size))
			if box.intersects(actor_box):return {}
	return {"local_position": local, "slot_bounds": box, "support_points": samples, "normal": normal, "support_height_spread": high - low}

func _point_box_distance(point: Vector2, box: AABB) -> float:
	return point.distance_to(Vector2(clampf(point.x, box.position.x, box.end.x), clampf(point.y, box.position.z, box.end.z)))

func _point_segment_distance(point: Vector2, a: Vector2, b: Vector2) -> float:
	var delta := b - a
	var length_sq := delta.length_squared()
	if length_sq <= 1e-12: return point.distance_to(a)
	return point.distance_to(a + delta * clampf((point - a).dot(delta) / length_sq, 0.0, 1.0))

func _segment_box_distance(a: Vector2, b: Vector2, box: AABB) -> float:
	var distance := minf(_point_box_distance(a, box), _point_box_distance(b, box))
	if distance <= 0.0: return 0.0
	var corners: Array[Vector2] = [Vector2(box.position.x, box.position.z), Vector2(box.end.x, box.position.z), Vector2(box.end.x, box.end.z), Vector2(box.position.x, box.end.z)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[index], corners[(index + 1) % 4]) != null: return 0.0
		distance = minf(distance, _point_segment_distance(corners[index], a, b))
	return distance
