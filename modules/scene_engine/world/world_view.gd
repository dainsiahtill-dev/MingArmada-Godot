extends Node3D
## Generic world composition. Receives plain geography and read-only samplers.

const TerrainChunk = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
const ProjectedOcean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const VegetationLibrary = preload("res://modules/scene_engine/assets/vegetation_library.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const IslandDetails = preload("res://modules/scene_engine/world/island_details.gd")
const FidelityMaterial = preload("res://modules/scene_engine/fidelity_island/terrain_material.gd")
const FidelityVegetation = preload("res://modules/scene_engine/fidelity_island/vegetation.gd")
const NaturalWorld = preload("res://modules/scene_engine/terrain/natural_world.gd")
const Atmosphere = preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const SourceEffects = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const TerrainWetMask = preload("res://modules/scene_engine/water/terrain_wet_mask.gd")
const PIER_DECK_HEIGHT := 4.2 # Above the authored offshore 3.5m wave envelope.
var _height_sampler: Callable
var _camera: Camera3D
var _ocean: MeshInstance3D
var _ports: Array = []
var _chunks: Dictionary = {}
var _distant_chunks: Dictionary = {}
var _port_visuals: Array[Dictionary] = []
var _port_building_sites: Array = []
const MAX_DISTANT_CHUNKS := 128
var _owned: Array[Node] = []
var _vegetation_library: RefCounted
var _chunk_size := 250.0
var _resolution := 32
var _radius := 2
var _vegetation := true
var _collision := true
var _builds := 0
var _disposed := true
var _simulation_time := 0.0
var _shore_field: RefCounted
var _near_shore_texture: ImageTexture
var _near_shore_center := Vector2i(2147483647,2147483647)
var _interactive_water_mask: Dictionary = {}
var _interactive_water_mask_error := "world-unconfigured"
var _interactive_water_mask_all_wet := false
var _interactive_water_mask_revision := 0
var _shore_spray: Node3D
var _visual_style := 1
var _island_details: Node3D
var _fidelity_profiles: Array = []
var _fidelity_materials: Array[ShaderMaterial] = []
var _fidelity_vegetation: Array[Node3D] = []
var _fidelity_shores: Array[Node3D] = []
var _static_islands: RefCounted
var _natural_world: Node3D
var _static_shore_resolution := 512
var _sea_visual_scale := 1.0
var _display_fog_density := 0.0015
var atmosphere: RefCounted
var _atmosphere_options: Dictionary = {}
var _weather_epoch := ""
var _source_lighting: Dictionary = {}
var _native_environment: Environment
var _native_sun: DirectionalLight3D

func bind_environment(environment: Environment, sun: DirectionalLight3D) -> void:
	_native_environment=environment;_native_sun=sun
	_apply_source_lighting()

func _apply_source_lighting() -> void:
	if _source_lighting.is_empty():return
	var d:Array=_source_lighting.get("direction",[0.0,1.0,0.0])
	var direction:=Vector3(d[0],d[1],d[2]).normalized()
	var rgb:Array=_source_lighting.get("color",[1.0,1.0,1.0])
	var ambient:Array=_source_lighting.get("ambientColor",[0.4,0.4,0.4])
	if is_instance_valid(_native_sun):
		_native_sun.basis=Basis.looking_at(-direction,Vector3.RIGHT if absf(direction.dot(Vector3.UP))>0.999 else Vector3.UP)
		_native_sun.light_color=Color(rgb[0],rgb[1],rgb[2]);_native_sun.light_energy=float(_source_lighting.get("energy",1.0))
	if _native_environment!=null:_native_environment.ambient_light_color=Color(ambient[0],ambient[1],ambient[2])
	if not is_instance_valid(_ocean):return
	var material:=_ocean.material_override as ShaderMaterial
	if material:
		material.set_shader_parameter("sun_position",direction*100000.0)
		material.set_shader_parameter("u_sun",direction)
		material.set_shader_parameter("u_sun_color",Vector3(rgb[0],rgb[1],rgb[2]))
	var sky:ShaderMaterial=_ocean.get_sky_material()
	if sky:
		sky.set_shader_parameter("u_sun",direction)
		sky.set_shader_parameter("u_sun_color",Vector3(rgb[0],rgb[1],rgb[2]))

func configure(height_sampler: Callable, wave_descriptors: Array = [], options: Dictionary = {}) -> bool:
	# A quality rebuild may replace sea and terrain without throwing away the
	# source cloud delta history. Different land placements rebuild weather.
	var retained_atmosphere: RefCounted = atmosphere
	var retained_options := _atmosphere_options.duplicate(true)
	var retained_epoch := _weather_epoch
	atmosphere = null
	dispose()
	if not height_sampler.is_valid():
		_invalidate_interactive_water_mask("invalid-height-sampler")
		if retained_atmosphere: retained_atmosphere.dispose()
		return false
	atmosphere = retained_atmosphere
	_atmosphere_options = retained_options
	_weather_epoch = retained_epoch
	_disposed = false
	_height_sampler = height_sampler
	_camera = options.get("camera")
	_ports = options.get("ports", []).duplicate(true)
	_chunk_size = clampf(float(options.get("chunk_size", 250.0)), 25.0, 1000.0)
	_resolution = clampi(int(options.get("resolution", 32)), 4, 128)
	_radius = clampi(int(options.get("chunk_radius", 2)), 0, 4)
	_vegetation = bool(options.get("vegetation", true))
	_collision = bool(options.get("collision", true))
	_visual_style = int(options.get("visual_style", 1))
	_vegetation_library = VegetationLibrary.new()
	_ocean = ProjectedOcean.new()
	_ocean.name = "Ocean"
	add_child(_ocean)
	_owned.append(_ocean)
	var texture: Texture2D = options.get("normal_texture")
	if texture == null and ResourceLoader.exists("res://assets/textures/waternormals.jpg"):
		texture = load("res://assets/textures/waternormals.jpg") as Texture2D
	_ocean.configure(_camera, texture, int(options.get("ocean_resolution", 80)), float(options.get("ocean_distance", 3000.0)))
	_ocean.set_surface_quality(String(options.get("quality","balanced")))
	var effective_waves: Array = Descriptor.original_descriptors() if wave_descriptors.is_empty() else wave_descriptors.duplicate(true)
	if not _ocean.set_wave_descriptors(effective_waves):
		dispose()
		return false
	if _ocean.has_method("set_visual_style"):
		_ocean.set_visual_style(int(options.get("visual_style", 1)))
	_ocean.configure_reflection(_camera)
	_ocean.enable_surface_optics(_visual_style == 1)
	if _visual_style == 1: _ocean.set_projection_padding(0.10)
	_build_ports()
	if not _configure_natural_islands(options):
		dispose(); return false
	if not _configure_fidelity_islands(options):
		dispose(); return false
	if not _configure_visual_scale(options):
		dispose(); return false
	_configure_shore(effective_waves)
	if _visual_style == 1 and bool(options.get("island_details",true)) and not _ports.is_empty():
		_island_details = IslandDetails.new(); add_child(_island_details); _owned.append(_island_details)
		if not _island_details.configure(_height_sampler,_ports,{"quality":options.get("quality","balanced"),"focus_distance":_chunk_size*(_radius+1),"reduced_motion":options.get("reduced_motion",false),"terrain_support":_island_supported,"existing_buildings":_port_building_sites,"native_forest":not _fidelity_profiles.is_empty() or is_instance_valid(_natural_world)}):
			dispose(); return false
	_update_window(Vector2.ZERO)
	if is_instance_valid(_static_islands) or is_instance_valid(_natural_world): _sync_terrain_surface()
	if _island_details: _island_details.apply_snapshot({"time":0.0,"focus":Vector2.ZERO})
	if not _configure_atmosphere(options): dispose(); return false
	return true

func _configure_atmosphere(options: Dictionary) -> bool:
	if not is_instance_valid(_camera):
		if atmosphere: atmosphere.dispose()
		atmosphere = null; _atmosphere_options.clear()
		return true
	var fog_placements: Array[Transform3D] = []
	for port: Dictionary in _ports:
		var x := float(port.get("islandX",port.get("x",0.0)))
		var z := float(port.get("islandZ",port.get("z",0.0)))
		var land_height := float(_height_sampler.call(x,z))
		if not is_finite(land_height) or land_height <= 0.0: continue
		# Thin clear-weather fog stays on accepted island land, outside fleet lanes.
		fog_placements.append(Transform3D(Basis.IDENTITY.scaled(Vector3(3.0,1.0,3.0)),Vector3(x,land_height+1.5,z)))
	# Source unit-dome geometry needs a distant meter-scale sky in normal play;
	# the standalone observer's 160/36 placement would sit among these islands.
	var settings := {"crt_seed":1,"cloud_sky_radius":minf(2800.0,_camera.far*0.65),"cloud_sky_height":380.0,"cloud_bounds_layer":true,"cloud_min_height":80.0,"cloud_height_variation":40.0,"fog_placements":fog_placements,"fog_opacity":0.035}
	if atmosphere and settings == _atmosphere_options:
		atmosphere.set_reduced_motion(bool(options.get("reduced_motion",false)))
		return true
	if atmosphere: atmosphere.dispose()
	atmosphere = Atmosphere.new()
	_atmosphere_options = settings.duplicate(true)
	settings.reduced_motion = bool(options.get("reduced_motion",false))
	var receipt: Dictionary = atmosphere.configure(self,SourceEffects.load_manifest(),settings)
	if not receipt.get("ok",false): push_error("Shared source atmosphere: "+String(receipt.get("error","unknown configuration error")))
	return bool(receipt.get("ok",false))

func set_reduced_motion(enabled: bool) -> void:
	if atmosphere: atmosphere.set_reduced_motion(enabled)

func _configure_visual_scale(options: Dictionary) -> bool:
	var native_scale := not _fidelity_profiles.is_empty() or is_instance_valid(_natural_world)
	var scale: Variant = options.get("sea_visual_scale",1.5 if not _fidelity_profiles.is_empty() else 1.0)
	var fog: Variant = options.get("display_fog_density",0.00035 if native_scale else 0.0015)
	if not (scale is int or scale is float) or not is_finite(float(scale)) or float(scale) <= 0.0: return false
	if not (fog is int or fog is float) or not is_finite(float(fog)) or float(fog) < 0.0: return false
	_sea_visual_scale = float(scale)
	_display_fog_density = float(fog)
	# These are presentation uniforms only. The accepted five wave components,
	# physics sampler and all world-space terrain/ship coordinates stay intact.
	var sea_material := _ocean.material_override as ShaderMaterial
	if sea_material:
		sea_material.set_shader_parameter("surface_visual_scale",_sea_visual_scale)
		sea_material.set_shader_parameter("mask_dry_terrain",is_instance_valid(_static_islands) or is_instance_valid(_natural_world))
		sea_material.set_shader_parameter("display_fog_density",_display_fog_density)
		# The curved ocean fronts lead; authored surf adds detail to the same phase.
		# Keep contact residue quieter than the approaching wave heads.
		sea_material.set_shader_parameter("coastal_breaker_strength",0.36 if is_instance_valid(_natural_world) else 1.0)
		sea_material.set_shader_parameter("shoreline_residue_strength",0.38 if is_instance_valid(_natural_world) else 1.0)
	for material: ShaderMaterial in _fidelity_materials:
		material.set_shader_parameter("display_fog_density",_display_fog_density)
	if is_instance_valid(_natural_world):
		for mesh: MeshInstance3D in _natural_world.get_meshes():
			(mesh.material_override as ShaderMaterial).set_shader_parameter("display_fog_density",_display_fog_density)
	return true

func _configure_natural_islands(options: Dictionary) -> bool:
	var owner: Object=_height_sampler.get_object()
	if owner==null or not owner.has_method("natural_terrain_grids"): return true
	var grids: Array=owner.natural_terrain_grids()
	if grids.is_empty(): return true
	_natural_world=NaturalWorld.new(); _natural_world.name="StaticNaturalWorld"
	add_child(_natural_world); _owned.append(_natural_world)
	var settings:=options.duplicate(); settings.vegetation=_vegetation; settings.existing_buildings=_port_building_sites
	_static_shore_resolution=clampi(int(options.get("static_shore_resolution",512)),256,512)
	return _natural_world.configure(grids,_height_sampler,settings)

func _configure_fidelity_islands(options: Dictionary) -> bool:
	if is_instance_valid(_natural_world): return true
	if _visual_style != 1 or not options.get("fidelity_islands",true): return true
	var owner: Object = _height_sampler.get_object()
	if owner == null or not owner.has_method("reference_profiles"): return true
	var profiles: Array = owner.reference_profiles()
	if profiles.is_empty(): return true
	for source: Dictionary in profiles:
		var mapping: Dictionary = source.duplicate(true)
		if mapping.get("id") != "cat_island": mapping.material_kind = "game_adapted"
		var material: ShaderMaterial = FidelityMaterial.create_material({},mapping)
		if material == null: return false
		_fidelity_profiles.append(mapping)
		_fidelity_materials.append(material)
	if bool(options.get("fidelity_island_geometry",true)):
		var geometry_path := "res://modules/scene_engine/fidelity_island/static_islands.gd"
		if not ResourceLoader.exists(geometry_path): return false
		var geometry_script: GDScript = load(geometry_path)
		_static_islands = geometry_script.new()
		if not _static_islands.configure(_fidelity_profiles,_height_sampler,_fidelity_materials): return false
		var island_root := Node3D.new()
		island_root.name = "StaticSourceIslands"
		add_child(island_root); _owned.append(island_root)
		for island: MeshInstance3D in _static_islands.get_meshes(): island_root.add_child(island)
		_static_shore_resolution = clampi(int(options.get("static_shore_resolution",512)),256,512)
	if _vegetation:
		var trees := FidelityVegetation.new()
		add_child(trees); _owned.append(trees)
		if not trees.configure(_fidelity_profiles,_height_sampler,{"mode":"mapped","existing_buildings":_port_building_sites}): return false
		_fidelity_vegetation.append(trees)
	var shore_path := "res://modules/scene_engine/fidelity_island/shore.gd"
	if not ResourceLoader.exists(shore_path): return false
	var shore_script: GDScript = load(shore_path)
	for mapping: Dictionary in _fidelity_profiles:
		# Original Cat surf is bound to its own silhouette. Other port shapes keep
		# their existing sampler-driven shoreline instead of receiving false surf.
		if mapping.get("id") != "cat_island": continue
		var surf: Node3D = shore_script.new()
		add_child(surf); _owned.append(surf)
		if not surf.configure(mapping,_height_sampler,{"mode":"mapped"}): return false
		_fidelity_shores.append(surf)
	return true

func _configure_shore(wave_descriptors: Array = []) -> void:
	var path := "res://modules/scene_engine/ocean/shore_field.gd"
	if _visual_style == 0 or _ports.is_empty():
		_interactive_water_mask_all_wet=true
		_interactive_water_mask={};_interactive_water_mask_error="";_interactive_water_mask_revision+=1
		return
	_interactive_water_mask_all_wet=false
	_invalidate_interactive_water_mask("awaiting-height-lattice")
	if not ResourceLoader.exists(path) or not _ocean.has_method("set_shore_field"):
		_invalidate_interactive_water_mask("shore-field-unavailable")
		return
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for port: Dictionary in _ports:
		var center := Vector2(float(port.islandX), float(port.islandZ))
		var reach := Vector2(float(port.radius), float(port.radius) * 0.82) + Vector2.ONE * 100.0
		minimum = minimum.min(center - reach)
		maximum = maximum.max(center + reach)
	if is_instance_valid(_natural_world):
		var owner: Object=_height_sampler.get_object()
		for entry: Dictionary in owner.natural_terrain_grids():
			var bounds: Rect2=entry.bounds
			minimum=minimum.min(bounds.position); maximum=maximum.max(bounds.end)
	if is_instance_valid(_static_islands):
		# Fit the complete rotated finite source grids once. Camera movement never
		# resamples this field or creates a new near/far terrain lattice.
		for island: MeshInstance3D in _static_islands.get_meshes():
			var bounds: AABB = island.get_aabb()
			for index in 8:
				var vertex: Vector3 = island.global_transform * bounds.get_endpoint(index)
				minimum = minimum.min(Vector2(vertex.x,vertex.z)-Vector2.ONE*20.0)
				maximum = maximum.max(Vector2(vertex.x,vertex.z)+Vector2.ONE*20.0)
	var shore_script = load(path)
	_shore_field = shore_script.new()
	var resolution := _static_shore_resolution if is_instance_valid(_static_islands) or is_instance_valid(_natural_world) else 1024
	if _shore_field.configure(_height_sampler, Rect2(minimum, maximum - minimum), resolution):
		_ocean.set_shore_field(_shore_field.get_texture(), _shore_field.get_bounds(), _shore_field.get_coast_texture())
	if is_instance_valid(_static_islands) or is_instance_valid(_natural_world):
		_configure_static_shore_field(Rect2(minimum,maximum-minimum))
	var spray_path := "res://modules/scene_engine/ocean/shore_spray.gd"
	if ResourceLoader.exists(spray_path):
		var spray_script = load(spray_path)
		_shore_spray = spray_script.new()
		if _shore_spray.configure(_height_sampler, Rect2(minimum, maximum - minimum), 160):
			if not wave_descriptors.is_empty(): _shore_spray.set_wave_descriptors(wave_descriptors)
			if _shore_field: _shore_spray.set_shore_field(_shore_field.get_texture(), _shore_field.get_bounds(), _shore_field.get_coast_texture())
			add_child(_shore_spray)
			_owned.append(_shore_spray)
		else:
			_shore_spray.free()
			_shore_spray = null

func _configure_static_shore_field(bounds: Rect2) -> void:
	if not _ocean.has_method("set_near_shore_field"):
		_invalidate_interactive_water_mask("near-shore-field-unavailable");return
	_invalidate_interactive_water_mask("building-static-height-lattice")
	var side := _static_shore_resolution
	var heights := PackedFloat32Array()
	heights.resize(side*side)
	for row in side:
		for column in side:
			var point := bounds.position+bounds.size*Vector2(column,row)/float(side-1)
			var value := sample_rendered_terrain_height(point.x,point.y)
			# Preserve submerged shoals between finite source islands. They remain
			# navigation heights from the injected owner, with no rendered land grid.
			if not is_finite(value): value = float(_height_sampler.call(point.x,point.y))
			if not is_finite(value):
				_invalidate_interactive_water_mask("nonfinite-static-terrain-height");return
			heights[row*side+column] = value
	if not _cache_interactive_water_mask(heights,side,bounds):return
	var image := Image.create_from_data(side,side,false,Image.FORMAT_RF,heights.to_byte_array())
	_near_shore_texture = ImageTexture.create_from_image(image)
	_ocean.set_near_shore_field(_near_shore_texture,Vector4(bounds.position.x,bounds.position.y,bounds.end.x,bounds.end.y))

func get_interactive_water_mask_revision() -> int:
	return _interactive_water_mask_revision

func get_interactive_water_mask() -> Dictionary:
	if not _interactive_water_mask_error.is_empty():
		return {"valid":false,"error":_interactive_water_mask_error,"revision":_interactive_water_mask_revision}
	if _interactive_water_mask_all_wet:return {}
	var result:=_interactive_water_mask.duplicate(false)
	if result.has("data"):result.data=(_interactive_water_mask.data as PackedByteArray).duplicate()
	return result

func _invalidate_interactive_water_mask(reason: String) -> void:
	# Keep the last complete bytes internally, but never present stale/unknown
	# data as a valid new domain or as the intentional empty/all-wet contract.
	_interactive_water_mask_error=reason
	_interactive_water_mask_revision+=1

func _cache_interactive_water_mask(heights: PackedFloat32Array,side: int,bounds: Rect2) -> bool:
	if _interactive_water_mask_all_wet:
		_interactive_water_mask={};_interactive_water_mask_error="";_interactive_water_mask_revision+=1
		return true
	var candidate:=TerrainWetMask.build(heights,side,bounds)
	if not candidate.valid:
		_invalidate_interactive_water_mask(str(candidate.error));return false
	_interactive_water_mask_revision+=1
	candidate.revision=_interactive_water_mask_revision
	_interactive_water_mask=candidate
	_interactive_water_mask_error=""
	return true

func apply_snapshot(snapshot: Dictionary, consumed: float = 0.0) -> void:
	if _disposed:
		return
	var next_epoch := String(snapshot.get("battleId",""))
	if not next_epoch.is_empty() and next_epoch != _weather_epoch:
		if atmosphere: atmosphere.reset_timeline()
		_weather_epoch = next_epoch
	# Runtime time is authoritative, including pause and rewind. No wall clock.
	var seconds := float(snapshot.get("time", _simulation_time))
	if is_finite(seconds):
		_simulation_time = seconds
		_ocean.set_simulation_time(seconds)
		if is_instance_valid(_shore_spray):
			_shore_spray.set_simulation_time(seconds)
	if snapshot.get("wind") is Dictionary:
		var wind: Dictionary = snapshot.wind
		var direction: Dictionary = wind.get("direction",{})
		_ocean.set_surface_wind(Vector2(float(direction.get("x",1.0)),float(direction.get("y",direction.get("z",0.0)))),float(wind.get("speed",0.0)))
	var focus := Vector2.ZERO
	if snapshot.has("focus"):
		var point = snapshot.focus
		if point is Vector2:
			focus = point
		elif point is Dictionary:
			focus = Vector2(float(point.get("x", 0.0)), float(point.get("z", 0.0)))
	elif is_instance_valid(_camera):
		focus = Vector2(_camera.global_position.x, _camera.global_position.z)
	if is_finite(focus.x) and is_finite(focus.y):
		_update_window(focus)
	_sync_terrain_surface()
	_ocean.update_projection()
	if _island_details:
		_island_details.apply_snapshot({"time":_simulation_time,"focus":focus},consumed)
	for trees: Node3D in _fidelity_vegetation:
		trees.apply_snapshot({"time":_simulation_time,"focus":focus},consumed)
	for surf: Node3D in _fidelity_shores:
		surf.sync_surface_state(_ocean.material_override as ShaderMaterial)
		surf.apply_snapshot(_simulation_time)
	if is_instance_valid(_natural_world): _natural_world.apply_snapshot({"time":_simulation_time,"focus":focus},consumed)
	var environment:Dictionary=snapshot.get("environment",{})
	if environment.get("lighting",{}).get("target") is Dictionary:
		_source_lighting=environment.lighting.target.duplicate(true)
	_apply_source_lighting()
	if atmosphere:
		var reflected_view:Camera3D=null
		var reflection_target:SubViewport=_ocean.get_reflection_viewport()
		if is_instance_valid(reflection_target) and reflection_target.render_target_update_mode!=SubViewport.UPDATE_DISABLED:
			reflected_view=_ocean.get_reflection_camera()
		atmosphere.apply_snapshot(snapshot,_camera,Vector3(focus.x,0.0,focus.y),reflected_view)
	# consumed is accepted for shared presentation API; this world does not bill it.
	if consumed < 0.0:
		return

func _update_window(focus: Vector2) -> void:
	if is_instance_valid(_static_islands) or is_instance_valid(_natural_world):
		_update_port_support()
		return
	var center := Vector2i(floori(focus.x / _chunk_size), floori(focus.y / _chunk_size))
	var active: Dictionary = {}
	for row in range(center.y - _radius, center.y + _radius + 1):
		for column in range(center.x - _radius, center.x + _radius + 1):
			var key := Vector2i(column, row)
			active[key] = true
	for key in _chunks.keys():
		if not active.has(key):
			var chunk: Node = _chunks[key]
			_owned.erase(chunk)
			chunk.free()
			_chunks.erase(key)
	for coordinate: Vector2i in active:
		if _chunks.has(coordinate):
			continue
		var chunk := TerrainChunk.new()
		if not chunk.configure(_height_sampler, coordinate, _chunk_size, _resolution, _collision, {"detailed": _visual_style == 1}):
			chunk.free()
			continue
		chunk.name = "Terrain_%d_%d" % [coordinate.x, coordinate.y]
		add_child(chunk)
		_owned.append(chunk)
		_chunks[coordinate] = chunk
		_sync_chunk_surface(chunk)
		_builds += 1
		if _vegetation and _fidelity_profiles.is_empty():
			_vegetation_library.populate(chunk, _height_sampler, coordinate, _chunk_size, _resolution, _ports)
	_update_distant_islands(focus, active)
	_update_near_shore_field(center)
	_update_port_support()

func _update_port_support() -> void:
	for entry: Dictionary in _port_visuals:
		var supported := _island_supported(entry.center, entry.radius)
		for node: Node3D in entry.nodes: node.visible = supported

func _update_near_shore_field(center: Vector2i) -> void:
	if _visual_style != 1 or not is_instance_valid(_ocean) or not _ocean.has_method("set_near_shore_field") or center == _near_shore_center: return
	_invalidate_interactive_water_mask("building-near-height-lattice")
	# Use the same vertex lattice and Float32 triangle surface as the actual near
	# terrain. This field controls visible foam/refraction, not physics attenuation.
	var tiles := _radius * 2 + 1
	var side := tiles * _resolution + 1
	var minimum := Vector2(float(center.x-_radius)-0.5,float(center.y-_radius)-0.5)*_chunk_size
	var maximum := minimum + Vector2.ONE * tiles * _chunk_size
	var heights := PackedFloat32Array(); heights.resize(side*side)
	for row in side:
		for column in side:
			var point := minimum+Vector2(column,row)*(_chunk_size/_resolution)
			var coordinate := Vector2i(floori(point.x/_chunk_size+0.5),floori(point.y/_chunk_size+0.5))
			var chunk: Node3D = _chunks.get(coordinate)
			var value := NAN
			if is_instance_valid(chunk) and chunk.has_method("sample_mesh_height"):
				value = float(chunk.sample_mesh_height(point.x,point.y))
			if not is_finite(value): value = float(_height_sampler.call(point.x,point.y))
			if not is_finite(value):
				_invalidate_interactive_water_mask("nonfinite-near-terrain-height");return
			heights[row*side+column] = value
	if not _cache_interactive_water_mask(heights,side,Rect2(minimum,maximum-minimum)):return
	var image := Image.create_from_data(side,side,false,Image.FORMAT_RF,heights.to_byte_array())
	_near_shore_texture = ImageTexture.create_from_image(image)
	_ocean.set_near_shore_field(_near_shore_texture,Vector4(minimum.x,minimum.y,maximum.x,maximum.y))
	_near_shore_center = center

func _update_distant_islands(focus: Vector2, near_chunks: Dictionary) -> void:
	# Far ports remain visible, so their islands must have terrain beneath them.
	# These coarse tiles have no physics or vegetation and never overlap near tiles.
	var active: Dictionary = {}
	for port: Dictionary in _ports:
		var island := Vector2(float(port.get("islandX", 0.0)), float(port.get("islandZ", 0.0)))
		var radius := maxf(0.0, float(port.get("radius", 0.0)))
		if not is_finite(island.x) or not is_finite(island.y) or not is_finite(radius):
			continue
		var reach := Vector2.ONE * (radius + _chunk_size * 0.1)
		var minimum := Vector2i(floori((island.x - reach.x + _chunk_size * 0.5) / _chunk_size), floori((island.y - reach.y + _chunk_size * 0.5) / _chunk_size))
		var maximum := Vector2i(floori((island.x + reach.x + _chunk_size * 0.5) / _chunk_size), floori((island.y + reach.y + _chunk_size * 0.5) / _chunk_size))
		for row in range(minimum.y, maximum.y + 1):
			for column in range(minimum.x, maximum.x + 1):
				var coordinate := Vector2i(column, row)
				if near_chunks.has(coordinate) or active.size() >= MAX_DISTANT_CHUNKS:
					continue
				active[coordinate] = true
	for coordinate in _distant_chunks.keys():
		if not active.has(coordinate):
			var chunk: Node = _distant_chunks[coordinate]
			_owned.erase(chunk)
			chunk.free()
			_distant_chunks.erase(coordinate)
	for coordinate: Vector2i in active:
		if _distant_chunks.has(coordinate):
			continue
		var chunk := TerrainChunk.new()
		if not chunk.configure(_height_sampler, coordinate, _chunk_size, mini(16, _resolution), false, {"detailed": _visual_style == 1}):
			chunk.free()
			continue
		chunk.name = "DistantTerrain_%d_%d" % [coordinate.x, coordinate.y]
		add_child(chunk)
		_owned.append(chunk)
		_distant_chunks[coordinate] = chunk
		_sync_chunk_surface(chunk)

func _sync_chunk_surface(chunk: Node3D) -> void:
	if not _fidelity_profiles.is_empty():
		var point := Vector2(chunk.position.x,chunk.position.z)
		var closest := 0
		var distance := INF
		for index in _fidelity_profiles.size():
			var center: Vector2 = _fidelity_profiles[index].islandCenter
			var candidate := point.distance_squared_to(center)
			if candidate < distance: closest=index; distance=candidate
		chunk.material_override = _fidelity_materials[closest]
	if _visual_style == 1 and is_instance_valid(_ocean):
		chunk.sync_surface_state(_ocean.material_override as ShaderMaterial)

func _sync_terrain_surface() -> void:
	if _visual_style != 1: return
	if is_instance_valid(_natural_world):
		var reflection_target:SubViewport=_ocean.get_reflection_viewport()
		var reflection_disabled:=is_instance_valid(reflection_target) and reflection_target.render_target_update_mode==SubViewport.UPDATE_DISABLED
		# A missing viewport is incomplete view information, rather than proof that
		# reflection is disabled. Null main forces the conservative full path.
		var main_view:Camera3D=_camera if is_instance_valid(reflection_target) else null
		# set_simulation_time already synchronized the real mirror. Shore owners
		# retain camera references and read fresh frusta at both sync and apply.
		_natural_world.set_view_cameras(main_view,_ocean.get_reflection_camera(),not reflection_disabled)
		_natural_world.sync_surface_state(_ocean.material_override as ShaderMaterial,{"time":_simulation_time})
		return
	if is_instance_valid(_static_islands):
		for island: MeshInstance3D in _static_islands.get_meshes():
			island.sync_surface_state(_ocean.material_override as ShaderMaterial)
		return
	# Near and far tiles share the accepted sea clock and immutable wave/shore data.
	for chunk: Node3D in _chunks.values(): _sync_chunk_surface(chunk)
	for chunk: Node3D in _distant_chunks.values(): _sync_chunk_surface(chunk)

func _island_supported(center: Vector2, radius: float) -> bool:
	if is_instance_valid(_natural_world): return _natural_world.supports(center,radius)
	if is_instance_valid(_static_islands): return _static_islands.supports(center,radius)
	var reach := radius + _chunk_size * 0.1
	var minimum := Vector2i(floori((center.x - reach + _chunk_size * 0.5) / _chunk_size), floori((center.y - reach + _chunk_size * 0.5) / _chunk_size))
	var maximum := Vector2i(floori((center.x + reach + _chunk_size * 0.5) / _chunk_size), floori((center.y + reach + _chunk_size * 0.5) / _chunk_size))
	if (maximum.x - minimum.x + 1) * (maximum.y - minimum.y + 1) > _chunks.size() + _distant_chunks.size():
		return false
	for row in range(minimum.y, maximum.y + 1):
		for column in range(minimum.x, maximum.x + 1):
			var key := Vector2i(column, row)
			if not _chunks.has(key) and not _distant_chunks.has(key): return false
	return true

func _build_ports() -> void:
	var root := Node3D.new()
	root.name = "Ports"
	add_child(root)
	_owned.append(root)
	var wood := _material("785033")
	var walls := _material("ddd7c5")
	var roof := _material("a6573e")
	var height_owner: Object=_height_sampler.get_object()
	var natural: bool=height_owner!=null and height_owner.has_method("natural_islands") and not height_owner.natural_islands().is_empty()
	for port: Dictionary in _ports:
		var group := Node3D.new()
		group.name = String(port.get("id", "Port"))
		group.position = Vector3(float(port.x), 0.0, float(port.z))
		group.rotation.y = atan2(float(port.islandX) - float(port.x), float(port.islandZ) - float(port.z))
		root.add_child(group)
		var visuals: Array[Node3D] = [group]
		var approach:=Vector2(float(port.islandX)-float(port.x),float(port.islandZ)-float(port.z)).normalized()
		var landing_distance := 54.0
		if natural:
			# Fit only presentation to the accepted terrain. Canonical port anchors,
			# finite island grids and native ship depths remain unchanged.
			for distance in range(1,ceili(float(port.radius)*2.8)):
				var probe := Vector2(float(port.x),float(port.z))+approach*distance
				if float(_height_sampler.call(probe.x,probe.y))>=1.5:
					landing_distance=float(distance); break
		var landing:=Vector2(float(port.x),float(port.z))+approach*landing_distance
		if natural: group.set_meta("real_shore_landing",landing)
		var deck_end := landing_distance-7.2 if natural else 47.5
		var pier := _box(group, Vector3(8,0.5,deck_end+7.5), Vector3(0,PIER_DECK_HEIGHT,(deck_end-7.5)*0.5), wood)
		pier.name = "PierDeck"
		for z in range(-4, ceili(deck_end), 9):
			for x: float in [-3.1, 3.1]:
				var bottom := -6.75
				if natural:
					var world_point := group.transform*Vector3(x,0,z)
					bottom=float(_height_sampler.call(world_point.x,world_point.z))-0.35
				_box(group,Vector3(0.55,3.95-bottom,0.55),Vector3(x,(3.95+bottom)*0.5,z),wood)
		# A visible stair joins the elevated pier to real beach elevation.
		var landing_height:=float(_height_sampler.call(landing.x,landing.y))
		if is_finite(landing_height) and landing_height>0.4 and landing_height<PIER_DECK_HEIGHT:
			for step in 6:
				var top:=lerpf(PIER_DECK_HEIGHT+0.25,landing_height+0.12,float(step+1)/6.0)
				_box(group,Vector3(5.6,0.30,1.24),Vector3(0,top-0.15,(deck_end+0.6 if natural else 47.5)+step*1.2),wood)
		for index in 9:
			var x := float(port.islandX) + cos(index * 2.15) * float(port.radius) * 0.42
			var z := float(port.islandZ) + sin(index * 2.15) * float(port.radius) * 0.32
			var height := float(_height_sampler.call(x, z))
			if height < 2.0 or not is_finite(height):
				continue
			var width := 8.0 + (index % 3) * 2.0
			var yaw:=index*0.7
			var basis:=Basis(Vector3.UP,yaw)
			var supported:=true
			for side_x: float in [-width*0.5,width*0.5]:
				for side_z: float in [-3.5,3.5]:
					var offset:=basis*Vector3(side_x,0,side_z)
					var footing:=float(_height_sampler.call(x+offset.x,z+offset.z))
					if not is_finite(footing) or footing<0.5 or absf(footing-height)>1.0: supported=false
			if not supported: continue
			var house := Node3D.new()
			house.position = Vector3(x, height, z)
			house.rotation.y = yaw
			root.add_child(house)
			visuals.append(house)
			_port_building_sites.append({"position":Vector2(x,z),"radius":maxf(width,7.0)*0.6})
			var wall_height := 4.0 + index % 2
			_box(house,Vector3(width+0.4,1.3,7.4),Vector3(0,-0.55,0),walls)
			_box(house, Vector3(width, wall_height, 7), Vector3(0, wall_height / 2.0, 0), walls)
			_box(house, Vector3(width * 0.32, wall_height * 0.65, 0.15), Vector3(0, wall_height * 0.325, 3.58), wood)
			for side: float in [-1.0, 1.0]:
				var slope := _box(house, Vector3(width + 2, 0.35, 5.04), Vector3(0, wall_height + 1.4, side * 1.96), roof)
				slope.rotation.x = side * 0.42
			_box(house, Vector3(width + 2, 0.4, 0.55), Vector3(0, wall_height + 2.8, 0), roof)
		_port_visuals.append({"center":Vector2(float(port.islandX),float(port.islandZ)),"radius":float(port.radius),"nodes":visuals})

func _material(hex: String) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(hex)
	material.roughness = 0.95
	return material

func _box(parent: Node3D, dimensions: Vector3, point: Vector3, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = dimensions
	node.mesh = box
	node.material_override = material
	node.position = point
	parent.add_child(node)
	return node

func get_ocean() -> MeshInstance3D:
	return _ocean

func get_chunk_count() -> int:
	return _chunks.size()

func get_chunk_build_count() -> int:
	return _builds

func get_chunks() -> Array:
	return _chunks.values()

func get_distant_chunks() -> Array:
	return _distant_chunks.values()

func get_static_island_meshes() -> Array:
	if is_instance_valid(_natural_world): return _natural_world.get_meshes()
	return _static_islands.get_meshes() if is_instance_valid(_static_islands) else []

func sample_rendered_terrain_height(x: float,z: float) -> float:
	if is_instance_valid(_natural_world): return _natural_world.sample_mesh_height(x,z)
	if is_instance_valid(_static_islands): return _static_islands.sample_mesh_height(x,z)
	var height := NAN
	for chunk: Node3D in _chunks.values()+_distant_chunks.values():
		var candidate: float=chunk.sample_mesh_height(x,z)
		if is_finite(candidate): height=candidate if not is_finite(height) else maxf(height,candidate)
	return height

func fidelity_diagnostics() -> Dictionary:
	var materials: Array=[]
	for material: ShaderMaterial in _fidelity_materials: materials.append(FidelityMaterial.diagnostics(material))
	var vegetation: Array=[]
	for trees: Node3D in _fidelity_vegetation: vegetation.append(trees.diagnostics())
	var shore: Array=[]
	for surf: Node3D in _fidelity_shores: shore.append(surf.diagnostics())
	var geometry: Dictionary = _static_islands.diagnostics() if is_instance_valid(_static_islands) else {}
	if is_instance_valid(_natural_world):
		geometry=_natural_world.diagnostics()
		vegetation=geometry.vegetation
	if is_instance_valid(_static_islands):
		# Capture the bound mesh resources, rather than only the materials retained
		# by World, so GPU evidence can reveal accidental binding replacement.
		var bindings: Array = []
		var meshes: Array = _static_islands.get_meshes()
		for index in meshes.size():
			var mesh_material: ShaderMaterial = meshes[index].material_override as ShaderMaterial
			bindings.append({"profile":meshes[index].get_meta("source_profile",""),
				"matchesOwnedMaterial":mesh_material == _fidelity_materials[index],
				"shader":mesh_material.shader.resource_path if mesh_material and mesh_material.shader else "",
				"usesSourceBhi":mesh_material.get_shader_parameter("use_source_material_field") if mesh_material else false})
		geometry["meshMaterialBindings"] = bindings
	return {"profiles":_fidelity_profiles.duplicate(true),"materials":materials,"vegetation":vegetation,"shore":shore,
		"geometryMode":"static_natural" if is_instance_valid(_natural_world) else ("static_source" if is_instance_valid(_static_islands) else "camera_chunks"),"geometry":geometry,
		"staticShoreResolution":_static_shore_resolution if is_instance_valid(_static_islands) or is_instance_valid(_natural_world) else 0,
		"seaVisualScale":_sea_visual_scale,"displayFogDensity":_display_fog_density,
		"heightSamplerChanged":false,"waveDescriptorsChanged":false}

func dispose() -> void:
	_disposed = true
	_interactive_water_mask.clear();_interactive_water_mask_all_wet=false
	_invalidate_interactive_water_mask("world-disposed")
	_source_lighting.clear();_native_environment=null;_native_sun=null
	if atmosphere: atmosphere.dispose()
	atmosphere = null; _atmosphere_options.clear()
	_weather_epoch = ""
	if is_instance_valid(_natural_world): _natural_world.dispose()
	if is_instance_valid(_static_islands): _static_islands.dispose()
	for node in _owned:
		if is_instance_valid(node):
			node.free()
	_owned.clear()
	_chunks.clear()
	_distant_chunks.clear()
	_port_visuals.clear()
	_port_building_sites.clear()
	_fidelity_profiles.clear()
	_fidelity_materials.clear()
	_fidelity_vegetation.clear()
	_fidelity_shores.clear()
	_static_islands = null
	_natural_world = null
	_static_shore_resolution = 512
	_sea_visual_scale = 1.0
	_display_fog_density = 0.0015
	_ocean = null
	_shore_field = null
	_near_shore_texture = null
	_near_shore_center = Vector2i(2147483647,2147483647)
	_shore_spray = null
	_island_details = null
	_vegetation_library = null
	_height_sampler = Callable()
	_camera = null
