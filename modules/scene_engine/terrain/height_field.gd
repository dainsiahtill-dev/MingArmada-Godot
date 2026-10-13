extends RefCounted
## Numeric terrain authority: natural cached triangles for the formal campaign;
## explicit original-profile or historical ridge providers for source fixtures.
## This module owns no business port catalog and imports no simulation rules.

const ReferenceProfile = preload("res://modules/scene_engine/terrain/reference_island_profile.gd")
const NaturalField = preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const ShoalField = preload("res://modules/scene_engine/terrain/shoal_field.gd")
# One maximum Wake presentation: 32 trails * (64 ribbon rows * 5 columns
# plus three attached waves of 15 rows * 5 columns). Extra points remain exact
# uncached queries rather than growing a scope beyond its presentation budget.
const SAMPLING_SCOPE_CAPACITY := 17440

class SamplingScope:
	extends RefCounted
	var _provider: RefCounted
	var _token: int
	var _revision: int
	func _init(provider: RefCounted, token: int, revision: int) -> void:
		_provider = provider; _token = token; _revision = revision
	func finish() -> void:
		if _provider == null: return
		_provider.call("_finish_sampling_scope",_token,_revision)
		_provider = null
	func _notification(what: int) -> void:
		# Godot has already invalidated this guard's instance during PREDELETE;
		# dispatch directly to the still-retained provider, not through self.
		if what == NOTIFICATION_PREDELETE and _provider != null:
			_provider.call("_finish_sampling_scope",_token,_revision)
			_provider = null

var _ports: Array = []
var _reference_profiles: Array = []
var _natural_fields: Array = []
var _natural_shoal: RefCounted
var _home_x := 0.0
var _home_z := 0.0
var _length := 0.0
var _ux := 0.0
var _uz := 0.0
var _sampling_revision := 0
var _sampling_next_token := 0
var _sampling_scopes: Array[Dictionary] = []

func configure_ports(ports: Array, include_shoal_shelf: bool = true, options: Dictionary = {}) -> bool:
	_sampling_revision += 1
	_sampling_scopes.clear()
	if options.has("natural_islands") and not options.natural_islands is bool: return false
	if options.get("natural_islands",false) and options.get("reference_islands",false): return false
	var radius_scale: Variant=options.get("natural_radius_scale",0.8)
	var resolution: Variant=options.get("natural_resolution",257)
	var seeds: Variant=options.get("natural_seeds",{})
	var radius_by_port: Variant=options.get("natural_radius_by_port",{})
	if not (radius_scale is int or radius_scale is float) or not is_finite(float(radius_scale)) or float(radius_scale)<=0.0 or float(radius_scale)>1.0: return false
	if not resolution is int or resolution<17 or resolution>1025 or not seeds is Dictionary or not radius_by_port is Dictionary: return false
	if options.has("reference_islands") and not options.reference_islands is bool: return false
	if options.has("reference_art") and (not options.reference_art is Dictionary or not ReferenceProfile.valid_art_options(options.reference_art)): return false
	if options.has("reference_art_by_profile"):
		if not options.reference_art_by_profile is Dictionary: return false
		for id: Variant in options.reference_art_by_profile:
			if not id is String or id not in ReferenceProfile.IDS: return false
			var override: Variant=options.reference_art_by_profile[id]
			if not override is Dictionary: return false
			var merged: Dictionary=options.get("reference_art",{}).duplicate()
			merged.merge(override,true)
			if not ReferenceProfile.valid_art_options(merged): return false
	if options.has("reference_profiles"):
		if not options.reference_profiles is Dictionary: return false
		for id: Variant in options.reference_profiles:
			if not id is String or not options.reference_profiles[id] is String or options.reference_profiles[id] not in ReferenceProfile.IDS: return false
	for port in ports:
		if not port is Dictionary:
			return false
		for key in ["x", "z", "islandX", "islandZ", "radius", "peak"]:
			if options.get("reference_islands",false) and (not port.has(key) or not (port[key] is int or port[key] is float)): return false
			if not port.has(key) or not is_finite(float(port[key])):
				return false
		if float(port.radius) <= 0.0:
			return false
	var profiles: Array=[]
	var natural_fields: Array=[]
	var natural_shoal: RefCounted
	if options.get("natural_islands",false):
		for index in ports.size():
			var port: Dictionary=ports[index]
			var field:=NaturalField.new()
			var seed_value: Variant=seeds.get(port.get("id",""),1661+index)
			var center:=Vector2(float(port.islandX),float(port.islandZ))
			var port_scale: Variant=radius_by_port.get(port.get("id",""),radius_scale)
			if not (port_scale is int or port_scale is float) or not is_finite(float(port_scale)) or float(port_scale)<=0.0 or float(port_scale)>1.0: return false
			var radius:=float(port.radius)*float(port_scale)
			if not field.configure({"seed":seed_value,"center":center,"radius":radius,"peak":float(port.peak),"resolution":resolution}): return false
			natural_fields.append({"id":port.get("id",str(index)),"field":field,"seed":seed_value,"center":center,"radius":radius,"peak":float(port.peak),"bounds":field.bounds()})
		if include_shoal_shelf and ports.size()>=2:
			natural_shoal=ShoalField.new()
			if not natural_shoal.configure(Vector2(float(ports[0].x),float(ports[0].z)),Vector2(float(ports[1].x),float(ports[1].z))): return false
	if options.get("reference_islands",false):
		for index in ports.size():
			var port: Dictionary=ports[index]
			var layout: Dictionary=options.get("reference_profiles",{})
			var id: String=str(port.get("referenceProfile",layout.get(port.get("id",""),ReferenceProfile.IDS[index%ReferenceProfile.IDS.size()])))
			var data: Dictionary=ReferenceProfile.load_source(id)
			var profile:=ReferenceProfile.new()
			var art: Dictionary=options.get("reference_art",{}).duplicate()
			art.merge(options.get("reference_art_by_profile",{}).get(id,{}),true)
			if data.is_empty() or not profile.configure(port,data,id,art): return false
			profiles.append(profile)
	_ports = ports.duplicate(true)
	_reference_profiles=profiles
	_natural_fields=natural_fields
	_natural_shoal=natural_shoal
	_length = 0.0
	if include_shoal_shelf and _ports.size() >= 2:
		_home_x = float(_ports[0].x)
		_home_z = float(_ports[0].z)
		var dx := float(_ports[1].x) - _home_x
		var dz := float(_ports[1].z) - _home_z
		_length = sqrt(dx * dx + dz * dz)
		if _length > 0.0:
			_ux = dx / _length
			_uz = dz / _length
	return true

func sample_height(x: float, z: float) -> float:
	if not is_finite(x) or not is_finite(z):
		return NAN
	if _sampling_scopes.is_empty(): return _sample_height_uncached(x,z)
	var scope: Dictionary = _sampling_scopes.back()
	var heights: Dictionary = scope.heights
	if heights.has(x):
		var existing: Dictionary = heights[x]
		if existing.has(z): return float(existing[z])
	var result := _sample_height_uncached(x,z)
	if int(scope.entries) < SAMPLING_SCOPE_CAPACITY:
		if not heights.has(x): heights[x] = {}
		var row: Dictionary = heights[x]
		row[z] = result
		scope.entries = int(scope.entries)+1
	return result

func begin_sampling_scope() -> RefCounted:
	_sampling_next_token += 1
	_sampling_scopes.append({"token":_sampling_next_token,"heights":{},"entries":0})
	# The provider retains only token/cache data, never the guard. Returning or
	# explicitly finishing the guard can therefore release this cache without
	# a RefCounted ownership cycle.
	return SamplingScope.new(self,_sampling_next_token,_sampling_revision)

func _finish_sampling_scope(token: int, revision: int) -> void:
	if revision != _sampling_revision: return
	for index in _sampling_scopes.size():
		if int(_sampling_scopes[index].token) == token:
			_sampling_scopes.remove_at(index)
			return

func _sample_height_uncached(x: float, z: float) -> float:
	var height := -24.0
	if not _natural_fields.is_empty():
		for island: Dictionary in _natural_fields: height=maxf(height,island.field.sample_triangle_height(x,z))
		if _natural_shoal!=null: height=maxf(height,_natural_shoal.sample_triangle_height(x,z))
		return height
	if not _reference_profiles.is_empty():
		for profile: RefCounted in _reference_profiles: height=maxf(height,float(profile.sample_height(x,z)))
	else:
		for island: Dictionary in _ports:
			var dx := (x - float(island.islandX)) / float(island.radius)
			var dz := (z - float(island.islandZ)) / (float(island.radius) * 0.82)
			var d2 := dx * dx + dz * dz
			if d2 < 1.0:
				var body := pow(1.0 - d2, 1.65)
				var ridge := (sin(x * 0.044 + z * 0.018) + sin(z * 0.056 - x * 0.013)) * 2.2 * body
				height = maxf(height, -24.0 + (float(island.peak) + 24.0) * body + ridge)
	if _length > 0.0:
		var along := (x - _home_x) * _ux + (z - _home_z) * _uz
		var across := -(x - _home_x) * _uz + (z - _home_z) * _ux
		var end_distance := maxf(maxf(_length * 0.32 - along, 0.0), along - _length * 0.68)
		var distance := sqrt(across * across + end_distance * end_distance)
		if distance < 135.0:
			var t := clampf((135.0 - distance) / 45.0, 0.0, 1.0)
			height = maxf(height, -24.0 + 21.6 * t * t * (3.0 - 2.0 * t))
	return height

func reference_profiles() -> Array:
	var results: Array=[]
	for profile: RefCounted in _reference_profiles: results.append(profile.diagnostics())
	return results

func natural_islands() -> Array:
	return _natural_fields.duplicate(true)

func natural_terrain_grids() -> Array:
	var result := natural_islands()
	if _natural_shoal!=null: result.append({"id":"supply-shoal","field":_natural_shoal,"bounds":_natural_shoal.bounds(),"shoal":true})
	return result

func sample_data(x: float, z: float) -> Dictionary:
	var height := sample_height(x, z)
	return {"height": height, "normalized": 0.6 + height / (50.0 if height < 0.0 else 150.0), "isUnderwater": height < 0.0}
