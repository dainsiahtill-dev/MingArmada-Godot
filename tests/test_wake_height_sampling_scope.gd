extends SceneTree
## The terrain kernel is real 257-resolution natural triangles. Counters only
## delegate; the uncached production Wake is the complete geometry oracle.
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Runtime = preload("res://game/runtime/naval_practice_runtime.gd")
const Catalog = preload("res://game/domain/legacy/catalog.gd")
const Geography = preload("res://game/scenes/common/reference_geography.gd")
const Sea = preload("res://game/presentation/world/naval_world_view.gd")
const Wake = preload("res://game/presentation/water/wake_trails.gd")
const STEP := 1.0 / 60.0

class Ledger:
	extends RefCounted
	var kernel_calls := 0
	var coordinates: Dictionary = {}
	func reset() -> void:
		kernel_calls = 0
		coordinates.clear()

class CountedTriangles:
	extends RefCounted
	var original: RefCounted
	var ledger: Ledger
	func sample_triangle_height(x: float, z: float) -> float:
		ledger.kernel_calls += 1
		ledger.coordinates[var_to_bytes([x,z]).hex_encode()] = true
		return original.sample_triangle_height(x,z)

class Callbacks:
	extends RefCounted
	var runtime: RefCounted
	var surface: Node3D
	var field: RefCounted
	var calls: Array = []
	var scope_begins := 0
	var dry := false
	func water(x: float, z: float, now: float) -> float:
		calls.append(["water",x,z,now])
		return runtime.sample_water_height(x,z,now)
	func sea(x: float, z: float) -> bool:
		calls.append(["sea",x,z])
		var result: bool = surface._surface_is_water(x,z)
		return result and not dry
	func begin_scope() -> RefCounted:
		scope_begins += 1
		return field.call("begin_sampling_scope")

var assertions := 0
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, detail: String) -> bool:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL wake height scope: ",detail)
	return ok

func _instrument(field: RefCounted, ledger: Ledger) -> void:
	var islands: Array = field.get("_natural_fields")
	for island: Dictionary in islands:
		var counted := CountedTriangles.new()
		counted.original = island.field
		counted.ledger = ledger
		island.field = counted

func _configured_height(ledger: Ledger) -> RefCounted:
	var field := Height.new()
	check(field.configure_ports(Catalog.DATA.PORTS,false,Geography.options()),"real formal 257-resolution natural terrain configures")
	_instrument(field,ledger)
	return field

func _guard(field: RefCounted) -> RefCounted:
	return field.call("begin_sampling_scope")

func _abandon_guard(field: RefCounted, x: float, z: float) -> void:
	var guard: RefCounted = _guard(field)
	field.sample_height(x,z)
	check(guard != null,"scope guard owns its finite lifetime until function return")

func _provider_lifetimes() -> void:
	var ledger := Ledger.new()
	var field: RefCounted = _configured_height(ledger)
	var island_count: int = field.get("_natural_fields").size()
	var x := -469.25
	var z := -57.25
	var expected: float = field.sample_height(x,z)
	ledger.reset()
	field.sample_height(x,z); field.sample_height(x,z)
	check(ledger.kernel_calls == 2*island_count,"outside scope every call still evaluates the original pure terrain kernel")
	if not check(field.has_method("begin_sampling_scope"),"numeric provider exposes an ephemeral sampling scope"):
		return
	var outer: RefCounted = _guard(field)
	if not check(outer != null and outer.has_method("finish"),"scope returns a releasable RefCounted guard"):
		return
	ledger.reset()
	check(field.sample_height(x,z) == expected and field.sample_height(x,z) == expected,"exact repeated doubles retain original height")
	check(ledger.kernel_calls == island_count,"scope evaluates identical doubles exactly once")
	var near_x := x+0.000001
	check(Vector2(x,z) == Vector2(near_x,z),"near-double fixture shares one float32 Vector2 but different float64 input")
	var oracle := Height.new()
	check(oracle.configure_ports(Catalog.DATA.PORTS,false,Geography.options()),"near-double uncached oracle configures")
	var near_expected: float = oracle.sample_height(near_x,z)
	check(near_expected != expected,"near-double fixture crosses a real triangle slope")
	check(field.sample_height(near_x,z) == near_expected,"float64 coordinate keys never merge rounded Vector2 neighbours")
	check(ledger.kernel_calls == 2*island_count,"distinct float64 x creates a distinct terrain request")
	var near_z := z+0.000001
	check(field.sample_height(x,near_z) == oracle.sample_height(x,near_z),"distinct float64 z retains independent exact height")
	check(ledger.kernel_calls == 3*island_count,"cache distinguishes both numeric axes")
	var before_invalid := ledger.kernel_calls
	check(is_nan(field.sample_height(NAN,z)) and is_nan(field.sample_height(x,INF)),"nonfinite coordinates preserve NAN validation")
	check(ledger.kernel_calls == before_invalid,"nonfinite inputs never enter terrain evaluation or numeric memo")
	var inner: RefCounted = _guard(field)
	field.sample_height(x,z); field.sample_height(x,z)
	check(ledger.kernel_calls == before_invalid+island_count,"nested scope owns its own bounded presentation cache")
	inner.call("finish"); inner.call("finish")
	field.sample_height(x,z)
	check(ledger.kernel_calls == before_invalid+island_count,"finishing an inner token twice restores outer cache without releasing it")
	outer.call("finish")
	field.sample_height(x,z); field.sample_height(x,z)
	check(ledger.kernel_calls == before_invalid+3*island_count,"explicit finish resumes uncached public sampling")
	ledger.reset()
	_abandon_guard(field,x,z)
	field.sample_height(x,z)
	check(ledger.kernel_calls == 2*island_count,"RAII releases guard on function return without a provider reference cycle")
	outer = _guard(field)
	field.sample_height(x,z)
	inner = _guard(field)
	ledger.reset()
	outer.call("finish")
	field.sample_height(x,z); field.sample_height(x,z)
	check(ledger.kernel_calls == island_count,"out-of-order release cannot close another active token")
	inner.call("finish")
	field.sample_height(x,z)
	check(ledger.kernel_calls == 2*island_count,"last active token closes after out-of-order outer release")
	outer = _guard(field)
	field.sample_height(x,z)
	var changed: Dictionary = Geography.options()
	changed.natural_seeds = {"xiamen":2011,"kinmen":2012,"forward-supply":2013}
	check(field.configure_ports(Catalog.DATA.PORTS,false,changed),"provider reconfiguration commits new natural terrain during a scope")
	check(oracle.configure_ports(Catalog.DATA.PORTS,false,changed),"independent oracle commits identical new terrain")
	var changed_expected: float = oracle.sample_height(x,z)
	check(changed_expected != expected,"new generation fixture actually changes terrain height")
	check(field.sample_height(x,z) == changed_expected,"configure invalidates all old scoped terrain values")
	_instrument(field,ledger)
	inner = _guard(field)
	ledger.reset()
	outer.call("finish")
	field.sample_height(x,z); field.sample_height(x,z)
	check(ledger.kernel_calls == island_count,"stale pre-configure guard cannot release a fresh revision token")
	inner.call("finish")
	field.sample_height(x,z)
	check(ledger.kernel_calls == 2*island_count,"fresh revision guard restores uncached operation when finished")
	outer = null; inner = null
	var bounded: RefCounted = _guard(field)
	ledger.reset()
	for index in range(17440): field.sample_height(10000.0+float(index)*0.001,10000.0)
	check(ledger.kernel_calls == 17440*island_count,"one scope covers the entire 32-trail maximum vertex budget")
	field.sample_height(10000.0,10000.0)
	check(ledger.kernel_calls == 17440*island_count,"full scope retains earlier exact coordinate entries")
	field.sample_height(11000.0,10000.0); field.sample_height(11000.0,10000.0)
	check(ledger.kernel_calls == 17442*island_count,"additional coordinates remain exact uncached queries beyond the bounded budget")
	bounded.call("finish")

func _material(material: Material) -> Array:
	if not material is ShaderMaterial: return []
	var shader_material: ShaderMaterial = material
	var result: Array = [shader_material.shader.resource_path,shader_material.render_priority]
	for parameter: String in ["foam_texture","detail_texture","ribbon","alpha_floor"]:
		var value: Variant = shader_material.get_shader_parameter(parameter)
		result.append(value.resource_path if value is Resource else value)
	return result

func _capture(wake: Node3D) -> Dictionary:
	var trails: Dictionary = wake.get("_trails")
	var result: Dictionary = {"diagnostics":wake.diagnostics(),"poses":wake.get("_poses").duplicate(true),"trails":{}}
	for id: String in trails:
		var trail: Dictionary = trails[id]
		var nodes: Array[MeshInstance3D] = [trail.node]
		for part: String in trail.waves: nodes.append(trail.waves[part])
		var captured: Array = []
		for node: MeshInstance3D in nodes:
			var arrays: Array = []
			if node.mesh != null and node.mesh.get_surface_count(): arrays=node.mesh.surface_get_arrays(0)
			captured.append({"name":node.name,"visible":node.visible,"transform":node.global_transform,"arrays":arrays,"material":_material(node.material_override)})
		result.trails[id] = {"samples":trail.samples.duplicate(true),"continuous":trail.continuous,"nodes":captured}
	return result

func _wake_oracle() -> void:
	var candidate_ledger := Ledger.new()
	var oracle_ledger := Ledger.new()
	var candidate_height: RefCounted = _configured_height(candidate_ledger)
	var oracle_height: RefCounted = _configured_height(oracle_ledger)
	var runtime := Runtime.new()
	check(runtime.configure(candidate_height.sample_height,{"mode":"sail"}).get("ok",false),"real three-ship sail authority and five-wave sampler configure")
	var oracle_runtime := Runtime.new()
	check(oracle_runtime.configure(oracle_height.sample_height,{"mode":"sail"}).get("ok",false),"independent uncached wave sampler configures")
	var candidate_surface := Sea.new(); candidate_surface.set("_height",candidate_height.sample_height)
	var oracle_surface := Sea.new(); oracle_surface.set("_height",oracle_height.sample_height)
	var candidate_calls := Callbacks.new()
	candidate_calls.runtime=runtime; candidate_calls.surface=candidate_surface; candidate_calls.field=candidate_height
	var oracle_calls := Callbacks.new()
	oracle_calls.runtime=oracle_runtime; oracle_calls.surface=oracle_surface; oracle_calls.field=oracle_height
	var candidate := Wake.new(); var oracle := Wake.new()
	root.add_child(candidate); root.add_child(oracle)
	candidate.configure(candidate_calls.water); candidate.configure_surface_filter(candidate_calls.sea)
	oracle.configure(oracle_calls.water); oracle.configure_surface_filter(oracle_calls.sea)
	var supported: bool = candidate.has_method("configure_sampling_scope") and candidate_height.has_method("begin_sampling_scope")
	check(supported,"Wake accepts an optional capability factory owned by its terrain provider")
	if supported: candidate.call("configure_sampling_scope",candidate_calls.begin_scope)
	var compared_frames := 0
	var dedup_frames := 0
	var previous: Dictionary = {}
	for frame in range(85):
		if frame > 0:
			for tick in range(6):
				runtime.advance(STEP); runtime.drain_events()
		var native: Dictionary = runtime.snapshot().naval
		candidate_calls.calls.clear(); oracle_calls.calls.clear()
		candidate_ledger.reset(); oracle_ledger.reset()
		candidate.apply_snapshot(native); oracle.apply_snapshot(native)
		compared_frames += 1
		check(_capture(candidate) == _capture(oracle),"accepted frame %d retains every vertex/UV/color/index, pose, sample, attached wave and material" % frame)
		check(candidate_calls.calls == oracle_calls.calls,"accepted frame %d retains exact water/sea callback count, ordering, double coordinates and appTime" % frame)
		check(oracle_ledger.kernel_calls == oracle_calls.calls.size()*Catalog.DATA.PORTS.size(),"standalone default Wake frame %d preserves every original terrain callback evaluation" % frame)
		if not oracle_calls.calls.is_empty():
			dedup_frames += 1
			check(candidate_ledger.kernel_calls*2 <= oracle_ledger.kernel_calls,"accepted frame %d eliminates paired pure terrain kernel evaluation" % frame)
			var first: Array = candidate_calls.calls[0]
			var before: int = candidate_ledger.kernel_calls
			candidate_height.sample_height(float(first[1]),float(first[2]))
			check(candidate_ledger.kernel_calls == before+Catalog.DATA.PORTS.size(),"accepted frame %d explicitly finishes its memo before returning to public callers" % frame)
		previous = native
	check(compared_frames == 85 and dedup_frames > 70,"full real runtime trace exercises mature ribbons and all attached wave geometry")
	check(int(candidate.diagnostics().samples) == 192 and int(candidate.diagnostics().attached_waves) == 9,"three moving ships retain all 64 trail samples and nine attached 3D foam meshes")
	var scopes_before: int = candidate_calls.scope_begins
	candidate_calls.calls.clear()
	candidate.apply_snapshot(previous)
	check(candidate_calls.calls.is_empty() and candidate_calls.scope_begins == scopes_before,"duplicate native timestamp does not open a scope or resample geometry")
	candidate.apply_snapshot({"time":NAN,"ships":[]})
	check(candidate_calls.scope_begins == scopes_before,"invalid native timestamp does not acquire a terrain scope")
	for dry: bool in [true,false]:
		candidate_calls.dry=dry; oracle_calls.dry=dry
		for tick in range(6): runtime.advance(STEP); runtime.drain_events()
		var native: Dictionary = runtime.snapshot().naval
		candidate.apply_snapshot(native); oracle.apply_snapshot(native)
		check(_capture(candidate) == _capture(oracle),"live dry-mask change retains all triangle filtering and restores wet geometry")
		if dry:
			for trail: Dictionary in candidate.get("_trails").values():
				check(trail.node.mesh == null,"fully dry trail produces no ribbon triangles")
	var rewound: Dictionary = runtime.snapshot().naval.duplicate(true)
	rewound.time=0.0
	candidate.apply_snapshot(rewound); oracle.apply_snapshot(rewound)
	check(_capture(candidate) == _capture(oracle),"native rewind releases prior history and retains oracle state")
	candidate.configure(candidate_calls.water); candidate.configure_surface_filter(candidate_calls.sea)
	candidate_calls.scope_begins=0
	candidate.apply_snapshot(rewound)
	rewound.time=0.1
	candidate.apply_snapshot(rewound)
	check(candidate_calls.scope_begins == 0,"Wake configure clears previous factory so standalone defaults remain uncached")
	candidate.dispose(); oracle.dispose()
	candidate.free(); oracle.free()
	candidate_surface.free(); oracle_surface.free()
	runtime.dispose(); oracle_runtime.dispose()

func _run() -> void:
	_provider_lifetimes()
	_wake_oracle()
	print("WAKE_HEIGHT_SAMPLING_SCOPE_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
