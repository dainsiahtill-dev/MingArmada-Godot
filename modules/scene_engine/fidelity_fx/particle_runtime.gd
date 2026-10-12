extends RefCounted
## Source-bound replay facade. Product seek uses explicit 120Hz observer, not game fps.
## advance_native exposes original variable-dt operations for controlled experiments.
const Math = preload("res://modules/scene_engine/fidelity_fx/native_particle_math.gd")
const Replay = preload("res://modules/scene_engine/fidelity_fx/native_particle_replay.gd")
const FREQUENCY := 120
const MODIFIERS := ["NiPSysAgeDeathModifier","NiPSysBoxEmitter","NiPSysSpawnModifier","NiPSysGrowFadeModifier","NiPSysColorModifier","NiPSysGravityModifier","NiPSysPositionModifier","NiPSysBoundUpdateModifier"]
var _asset: Dictionary = {}
var _blocks: Dictionary = {}
var _seed := 1
var _canonical
var _replay
var _native
var _tick := 0
var _grid_advances := 0
var _rebuilds := 0
var _max_time := 0.0
var _last_error := ""
var _time_input: Dictionary = {}

func _fail(message: String) -> bool:
	_last_error = message
	return false

static func _number(value) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _integer(value) -> bool:
	return _number(value) and float(value) == floor(float(value))

static func _wire_floats(value):
	# JSON is copied unchanged on disk. Native fractional numeric fields are float32.
	if value is Dictionary:
		for key in value: value[key] = _wire_floats(value[key])
	elif value is Array:
		for i in value.size(): value[i] = _wire_floats(value[i])
	elif value is float and value != floor(value): return Math.f32(value)
	return value

func _valid_references(value, index: Dictionary) -> bool:
	if value is Dictionary:
		if value.has("ref"):
			if not _integer(value.ref) or not index.has(int(value.ref)): return _fail("Missing source reference")
			if value.has("type") and value.type != index[int(value.ref)].type: return _fail("Source reference type mismatch")
		for child in value.values():
			if not _valid_references(child,index): return false
	elif value is Array:
		for child in value:
			if not _valid_references(child,index): return false
	elif value is float and not is_finite(value): return _fail("Nonfinite source number")
	return true

func _valid_keys(group, components: int, allow_empty := false) -> bool:
	if not group is Dictionary or not group.get("keys") is Array: return _fail("Missing original key group")
	var keys: Array = group.keys
	if keys.is_empty(): return true if allow_empty else _fail("Empty original key fallback unverified")
	if not _integer(group.get("interpolation")) or int(group.interpolation) not in [1,2]: return _fail("Unsupported original key interpolation")
	if components != 1 and int(group.interpolation) != 1: return _fail("Unsupported non-scalar cubic keys")
	var previous := -INF
	for key in keys:
		if not key is Dictionary or not _number(key.get("time")) or float(key.time) < previous: return _fail("Invalid source key time/order")
		if keys.size() > 1 and float(key.time) == previous: return _fail("Duplicate source key interval")
		previous = float(key.time)
		if components == 1:
			if not _number(key.get("value")): return _fail("Invalid source scalar key")
			if int(group.interpolation) == 2 and (not _number(key.get("forward")) or not _number(key.get("backward"))): return _fail("Missing original cubic tangents")
		else:
			if not key.get("value") is Dictionary: return _fail("Invalid source vector/color key")
			for component in (["x","y","z"] if components == 3 else ["r","g","b","a"]):
				if not _number(key.value.get(component)): return _fail("Invalid source key component")
	return true

func _valid_controller(fields: Dictionary) -> bool:
	for key in ["frequency","phase","start_time","stop_time"]:
		if not _number(fields.get(key)): return _fail("Missing original controller " + key)
	if not _integer(fields.get("flags")) or not int(fields.flags)&8: return _fail("Inactive or invalid original controller")
	if fields.start_time > fields.stop_time: return _fail("Invalid original controller interval")
	return true

func _valid_controller_chain(block: Dictionary, index: Dictionary) -> bool:
	var seen := {}
	var ref = block.fields.get("controller")
	while ref != null:
		var id: int = int(ref.ref)
		if seen.has(id): return _fail("Cyclic original controller chain")
		seen[id] = true
		ref = index[id].fields.get("next_controller")
	return true

func _valid_scene(id: int, index: Dictionary, visiting: Dictionary, worlds: Dictionary) -> bool:
	if visiting.has(id): return _fail("Cyclic original scene hierarchy")
	visiting[id] = true
	worlds[id] = true
	var block: Dictionary = index[id]
	if block.type not in ["NiNode","NiParticleSystem","NiTriShape","NiTriStrips"]: return _fail("Unsupported original scene node " + str(block.type))
	var fields: Dictionary = block.fields
	if not fields.get("rotation") is Dictionary or not fields.get("translation") is Dictionary or not _number(fields.get("scale")) or fields.scale <= 0.0: return _fail("Invalid original source transform")
	for component in ["x","y","z"]:
		if not _number(fields.translation.get(component)): return _fail("Invalid original translation")
	for component in ["m_11","m_21","m_31","m_12","m_22","m_32","m_13","m_23","m_33"]:
		if not _number(fields.rotation.get(component)): return _fail("Invalid original matrix")
	for ref in fields.get("children",[]):
		if not _valid_scene(int(ref.ref),index,visiting,worlds): return false
	visiting.erase(id)
	return true

func _valid_source(source: Dictionary, index: Dictionary) -> bool:
	if not source.get("blocks") is Array or source.blocks.is_empty() or not source.get("roots") is Array or source.roots.is_empty() or not source.get("name") is String: return _fail("Complete source asset dictionary required")
	for block in source.blocks:
		if not block is Dictionary or not _integer(block.get("id")) or not block.get("fields") is Dictionary or not block.get("type") is String: return _fail("Invalid original source block")
		if index.has(int(block.id)): return _fail("Duplicate original source block")
		index[int(block.id)] = block
	if not _valid_references(source,index): return false
	var worlds := {}
	for root in source.roots:
		if not _integer(root) or not index.has(int(root)): return _fail("Missing original scene root")
		if not _valid_scene(int(root),index,{},worlds): return false
	var system_count := 0
	for block in source.blocks:
		var fields: Dictionary = block.fields
		if not _valid_controller_chain(block,index): return false
		if str(block.type).ends_with("Controller") or str(block.type).ends_with("Ctlr"):
			if not _valid_controller(fields): return false
		match block.type:
			"NiKeyframeController":
				var data: Dictionary = index[int(fields.data.ref)].fields
				if not _valid_keys(data.get("translations"),3,true) or not _valid_keys(data.get("scales"),1,true): return false
				if data.get("num_rotation_keys",0) != 0:
					if data.get("rotation_type") != 4 or not _integer(data.get("rotation_order")) or int(data.rotation_order) not in range(6) or not data.get("xyz_rotations") is Array or data.xyz_rotations.size() != 3: return _fail("Unsupported original rotation variant or missing Euler wire order")
					for group in data.xyz_rotations:
						if not _valid_keys(group,1,true): return false
			"NiPSysEmitterCtlr":
				var data: Dictionary = index[int(fields.data.ref)].fields
				if not _valid_keys(data.get("float_keys"),1) or not data.get("visibility_keys") is Array or data.visibility_keys.is_empty(): return _fail("Empty original emitter visibility fallback unverified")
				var previous := -INF
				for key in data.visibility_keys:
					if not key is Dictionary or not _number(key.get("time")) or float(key.time) < previous: return _fail("Invalid original emitter visibility keys")
					if not key.get("value") is bool and (not _integer(key.get("value")) or int(key.value) not in [0,1]): return _fail("Invalid original emitter visibility value")
					previous = float(key.time)
			"NiTextureTransformController":
				if fields.get("texture_slot") != 0 or not _integer(fields.get("operation")) or int(fields.operation) not in range(5): return _fail("Unsupported original texture slot/operation")
				if not _valid_keys(index[int(fields.data.ref)].fields.get("data"),1): return false
			"NiAlphaController":
				if not _valid_keys(index[int(fields.data.ref)].fields.get("data"),1): return false
			"NiTexturingProperty":
				var desc = fields.get("base_texture")
				if not desc is Dictionary or not desc.get("source") is Dictionary: return _fail("Original base texture required")
				if desc.get("has_texture_transform",false) and (not _integer(desc.get("transform_type")) or int(desc.transform_type) not in [0,1]): return _fail("Unsupported original texture transform")
				for controller in _chain_blocks(block,index):
					if controller.type != "NiTextureTransformController": return _fail("Unsupported original texturing controller")
			"NiMaterialProperty":
				for controller in _chain_blocks(block,index):
					if controller.type != "NiAlphaController": return _fail("Unsupported original material controller")
			"NiVisController":
				if index[int(fields.data.ref)].fields.get("keys",[]).is_empty(): return _fail("Empty original visibility fallback unverified")
			"NiParticleSystem":
				system_count += 1
				if not worlds.has(int(block.id)) or not fields.get("modifiers") is Array or not fields.get("properties") is Array or not fields.get("data") is Dictionary or not fields.get("world_space") is bool: return _fail("Incomplete original particle system")
				var types := {}
				for controller in _chain_blocks(block,index):
					if controller.type not in ["NiPSysEmitterCtlr","NiPSysUpdateCtlr","NiPSysResetOnLoopCtlr"]: return _fail("Unsupported original particle controller")
					types[controller.type] = true
				for required in ["NiPSysEmitterCtlr","NiPSysUpdateCtlr","NiPSysResetOnLoopCtlr"]:
					if not types.has(required): return _fail("Missing original particle controller " + required)
				var modifiers := {}
				for ref in fields.modifiers:
					var modifier: Dictionary = index[int(ref.ref)]
					if modifier.type not in MODIFIERS or not _integer(modifier.fields.get("order")) or not modifier.fields.get("active") is bool: return _fail("Unsupported original modifier " + str(modifier.type))
					modifiers[modifier.type] = true
				if not modifiers.has("NiPSysBoxEmitter"): return _fail("Original Box emitter required")
				var data: Dictionary = index[int(fields.data.ref)].fields
				if not _integer(data.get("num_vertices")) or not _integer(data.get("num_active")) or data.num_vertices < 0 or data.num_vertices > 65535 or data.num_active < 0 or data.num_active > data.num_vertices: return _fail("Invalid original particle pool capacity")
				for key in ["vertices","particle_descriptions","vertex_colors","radii","sizes"]:
					if not data.get(key) is Array or data[key].size() != int(data.num_vertices): return _fail("Incomplete original particle buffer " + key)
			"NiPSysAgeDeathModifier":
				if fields.get("spawn_on_death") != false: return _fail("Unsupported original SpawnOnDeath branch")
			"NiPSysBoxEmitter":
				if not fields.get("emitter_object") is Dictionary or not worlds.has(int(fields.emitter_object.ref)): return _fail("Missing original emitter world transform")
				for key in ["speed","speed_variation","declination","declination_variation","planar_angle","planar_angle_variation","life_span","life_span_variation","initial_radius","width","height","depth"]:
					if not _number(fields.get(key)): return _fail("Missing original Box field " + key)
			"NiPSysColorModifier":
				if not _valid_keys(index[int(fields.data.ref)].fields.get("data"),4): return false
			"NiPSysGravityModifier":
				if not _integer(fields.get("force_type")) or int(fields.force_type) not in [0,1] or fields.get("turbulence") != 0: return _fail("Unsupported original gravity branch")
				if not fields.get("gravity_object") is Dictionary or not worlds.has(int(fields.gravity_object.ref)): return _fail("Missing original gravity world transform")
			"NiPSysBoundUpdateModifier":
				if not _integer(fields.get("update_skip")): return _fail("Invalid original bounds update counter")
			"NiTriShape", "NiTriStrips":
				if not fields.get("data") is Dictionary: return _fail("Missing original mesh data")
				var data: Dictionary = index[int(fields.data.ref)]
				if not data.get("effective_triangles") is Array or not data.fields.get("vertices") is Array or not data.fields.get("uv_sets") is Array: return _fail("Complete original mesh buffers required")
	if system_count == 0: return _fail("Original particle systems required")
	return true

static func _chain_blocks(block: Dictionary, index: Dictionary) -> Array:
	var out := []
	var ref = block.fields.get("controller")
	while ref != null:
		var controller: Dictionary = index[int(ref.ref)]
		out.append(controller)
		ref = controller.fields.get("next_controller")
	return out

func configure(asset: Dictionary, seed: int = 1) -> bool:
	if seed < 0 or seed > 0xffffffff: return _fail("Explicit uint32 original CRT state required")
	var source: Dictionary = asset.duplicate(true)
	var index := {}
	if not _valid_source(source,index): return false
	source = _wire_floats(source)
	var duration := 0.0
	for block in source.blocks:
		if block.fields.has("stop_time"): duration = maxf(duration,float(block.fields.stop_time))
	if not is_finite(Math.f32(duration)) or duration <= 0.0: return _fail("Explicit finite source clip required")
	_asset = source
	_blocks = index
	_seed = seed
	_max_time = Math.f32(duration)
	_grid_advances = 0
	_rebuilds = 0
	_last_error = ""
	reset()
	return true

func reset() -> void:
	if _asset.is_empty(): return
	_canonical = Replay.new(_asset,_seed,_blocks)
	_canonical.advance(0.0)
	_tick = 0
	_rebuilds += 1
	_replay = _canonical.fork()
	_native = null
	_time_input = {"kind":"canonical float32 120Hz grid plus at most one display endpoint","frequency":FREQUENCY,"gridTick":0,"lastGridTime":0.0,"endpointTime":null,"endpointDeltaSeconds":0.0,"canonicalGridAdvances":_grid_advances,"rebuilds":_rebuilds}

func seek(input: float) -> Array:
	if _asset.is_empty() or not is_finite(input) or input < 0.0 or not is_finite(Math.f32(input)) or Math.f32(input) > _max_time:
		_last_error = "Observer seek must be finite and within explicit source clip"
		return []
	var target: float = Math.f32(input)
	var tick: int = int(floor(target*FREQUENCY))
	while Math.f32((tick+1)/float(FREQUENCY)) <= target: tick += 1
	while Math.f32(tick/float(FREQUENCY)) > target: tick -= 1
	if tick < _tick: reset()
	while _tick < tick:
		_tick += 1
		_canonical.advance(_tick/float(FREQUENCY))
		_grid_advances += 1
	# Endpoint never becomes retained grid state, including a repeated endpoint seek.
	_replay = _canonical.fork()
	var grid_time: float = _canonical.time
	var endpoint: bool = target != grid_time
	if endpoint: _replay.advance(target)
	_time_input = {"kind":"canonical float32 120Hz grid plus at most one display endpoint","frequency":FREQUENCY,"gridTick":_tick,"lastGridTime":grid_time,"endpointTime":target if endpoint else null,"endpointDeltaSeconds":target-grid_time if endpoint else 0.0,"canonicalGridAdvances":_grid_advances,"rebuilds":_rebuilds}
	_last_error = ""
	return snapshot()

func advance(time: float) -> Array:
	return seek(time)

func advance_native(time: float) -> Array:
	if _asset.is_empty() or not is_finite(time) or not is_finite(Math.f32(time)):
		_last_error = "Native advance requires finite explicit appTime"
		return []
	if _native == null: _native = Replay.new(_asset,_seed,_blocks)
	_native.advance(time)
	_replay = _native
	_time_input = {"kind":"original variable-dt appTime sequence; first update records visibility without births","appTime":Math.f32(time),"frequency":null,"gridTick":null}
	_last_error = ""
	return snapshot()

func snapshot() -> Array:
	return _replay.snapshot() if _replay != null else []

func source_state() -> Dictionary:
	return _replay.source_state() if _replay != null else {}

func authored_meshes(time: float) -> Array:
	if _replay == null or not is_finite(time) or time < 0.0 or Math.f32(time) > _max_time: return []
	return _replay.authored_meshes(Math.f32(time)).duplicate(true)

func meshes(camera: Dictionary) -> Array:
	if _replay == null: return []
	for basis in ["right","up","direction"]:
		if not camera.get(basis) is Array or camera[basis].size() != 3:
			_last_error = "Explicit native camera direction/up/right arrays required"
			return []
		for component in camera[basis]:
			if not _number(component):
				_last_error = "Finite native camera basis required"
				return []
	return _replay.meshes(camera).duplicate(true)

func diagnostics() -> Dictionary:
	var layers := []
	var active := 0
	var births := 0
	var requested := 0
	var deaths := 0
	if _replay != null:
		for system in _replay.systems:
			var pool = system.pool
			active += pool.num_active
			births += pool.births
			requested += pool.requested
			deaths += pool.deaths
			var order := []
			for modifier in system.modifiers: order.append({"type":modifier.type,"order":modifier.fields.order})
			layers.append({"block":system.block.id,"name":system.block.name,"capacity":pool.capacity,"active":pool.num_active,"pendingCount":pool.pending_count,"pendingStart":pool.pending_start,"births":pool.births,"requested":pool.requested,"deaths":pool.deaths,"modifierOrder":order,"world":system.world.duplicate(true),"bounds":system.bounds.duplicate(true),"boundCounter":system.boundCounter})
	return {"configured":not _asset.is_empty(),"asset":_asset.get("name",""),"systems":layers.size(),"system_count":layers.size(),"particles":active,"active":active,"births":births,"requested":requested,"deaths":deaths,"rng_state":_replay.rng.state if _replay != null else _seed,"rng_draws":_replay.rng.draws if _replay != null else 0,"time":_replay.time if _replay != null else null,"max_time":_max_time,"time_input":_time_input.duplicate(true),"layers":layers,"last_error":_last_error,"source_scope":"35 selected native particle systems and authored splash meshes; seed explicit; 120Hz observer is adapter; D3D lighting/raster/vertex-color upload unresolved"}
