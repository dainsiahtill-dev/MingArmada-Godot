extends Node3D
## World-space impact volume and wave-conforming rings from event/native time.
const Foam = preload("res://game/presentation/water/pirates_foam.gdshader")
const Volume = preload("res://game/presentation/water/splash_volume.gd")
const VolumeShader = preload("res://game/presentation/water/splash_volume.gdshader")
const Reference = preload("res://game/presentation/water/reference_splash.gd")
const FidelityReference = preload("res://modules/scene_engine/fidelity_fx/presentation.gd")
const FROTH := "res://assets/textures/pirates_reference/fx_waterfroth_003.dds.png"
const COLUMN := "res://assets/textures/pirates_reference/fx_water_splash_004.dds.png"
const STREAK := "res://assets/textures/pirates_reference/fx_streakin_001.dds.png"
const MIST := "res://assets/textures/pirates_reference/fx_mist_01.dds.png"
const RINGS := "res://assets/textures/pirates_reference/fx_water_splash_rings_01.dds.png"
const SPRAY := "res://assets/textures/pirates_reference/water spash.tga.png"
const SPRAY_DETAIL := "res://assets/textures/pirates_reference/fx_water_splash_02.dds.png"
const MAX_SPLASHES := 32
const DURATION := 2.8
const GRID := 8
var _water: Callable
var _time := -1.0
var _splashes: Array = []
var _seen: Dictionary = {}
var _surface_filter: Callable
var _reference_camera: Camera3D
var _sea_cache: Dictionary = {}
var _sea_sampling := false
var _pending_snapshot := false
var _pending_same_time := false

func _sea_callback() -> Callable:
	# Keep the original no-filter path invalid, including SourceEffect's fast
	# unfiltered render path. The valid callback identity stays stable.
	return _sample_sea if _surface_filter.is_valid() else Callable()

func _sample_sea(x: float,z: float) -> bool:
	if not _surface_filter.is_valid(): return true
	if not _sea_sampling: return bool(_surface_filter.call(x,z))
	# Array components retain the original double XZ; no Vector2 conversion,
	# spatial quantization or tolerance may merge distinct terrain samples.
	var key := [x,z]
	if not _sea_cache.has(key): _sea_cache[key] = bool(_surface_filter.call(x,z))
	return bool(_sea_cache[key])

func _begin_sea_sampling() -> bool:
	var was_active := _sea_sampling
	if not was_active:
		_sea_cache.clear(); _sea_sampling = true
	return was_active

func _end_sea_sampling(was_active: bool) -> void:
	if not was_active:
		_sea_sampling = false; _sea_cache.clear()

func configure_reference_backend(camera: Camera3D) -> void:
	finish_snapshot()
	_reference_camera = camera
	for splash: Dictionary in _splashes:
		if splash.has("fidelity"): splash.reference.set_camera(camera)

func configure_surface_filter(sea_at: Callable) -> void:
	finish_snapshot()
	_surface_filter = sea_at
	_sea_cache.clear(); _sea_sampling = false
	var sampler := _sea_callback()
	for splash: Dictionary in _splashes:
		if splash.has("reference"): splash.reference.configure_surface_filter(sampler)

func configure(water_sampler: Callable) -> void:
	finish_snapshot()
	dispose(); _water = water_sampler

func apply_snapshot(now: float) -> void:
	begin_snapshot(now)
	finish_snapshot()

func begin_snapshot(now: float) -> void:
	# Every accepted appTime is completed before another one is submitted.
	# Workers own only source Runtime state/mesh math; water stays on main.
	finish_snapshot()
	if not is_finite(now) or now < 0.0: return
	if _time >= 0 and now < _time: _clear()
	_pending_same_time = now == _time
	_time = now
	_pending_snapshot = true
	if not _pending_same_time:
		for id in _seen.keys():
			if now-float(_seen[id]) >= DURATION: _seen.erase(id)
		for index in range(_splashes.size()-1,-1,-1):
			var splash: Dictionary = _splashes[index]; var age := now-float(splash.time)
			if age < 0.0 or age >= DURATION:
				_free_splash(splash); _splashes.remove_at(index)
	for splash: Dictionary in _splashes:
		if splash.has("fidelity"): splash.reference.begin_snapshot(now-float(splash.time),now)

func finish_snapshot() -> void:
	if not _pending_snapshot: return
	var same_time := _pending_same_time
	_pending_snapshot = false; _pending_same_time = false
	if same_time:
		# Paused camera changes still reproject source billboards. Their own
		# accepted-age memo freezes native particles; generic water stays intact.
		var was_active := _begin_sea_sampling()
		for splash: Dictionary in _splashes:
			if splash.has("fidelity"): splash.reference.apply_snapshot(_time-float(splash.time),_time)
		_end_sea_sampling(was_active)
		return
	for index in range(_splashes.size()-1,-1,-1):
		var splash: Dictionary = _splashes[index]
		_update(splash,_time-float(splash.time))

func has_pending_snapshot() -> bool:
	return _pending_snapshot

func add_event(event: Dictionary) -> void:
	finish_snapshot()
	var stamp := float(event.get("time",_time)); var age := _time-stamp
	var id := String(event.get("id",""))
	var size := float(event.get("scale",1.0))
	if _time < 0.0 or not is_finite(stamp) or stamp < 0.0 or not is_finite(size) or age < 0.0 or age >= DURATION or not _water.is_valid() or _splashes.size() >= MAX_SPLASHES or (not id.is_empty() and _seen.has(id)): return
	size = clampf(size,0.2,2.0)
	var point: Dictionary = event.get("position",{})
	var origin := Vector2(float(point.get("x",NAN)),float(point.get("z",NAN)))
	if not origin.is_finite() or not Volume.sea(_sea_callback(),origin): return
	var node := Node3D.new(); node.name = "Splash_"+String(event.get("id","")); add_child(node)
	node.top_level = true # Event coordinates stay world-space under translated parents.
	node.global_transform = Transform3D.IDENTITY
	var ring := MeshInstance3D.new(); ring.name = "RippleRing"; node.add_child(ring)
	var ring_material := _material(RINGS); ring.material_override = ring_material
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var spray := MeshInstance3D.new(); spray.name = "WaterSpray"; node.add_child(spray)
	spray.mesh = _spray_mesh()
	var spray_material := _material(SPRAY); spray_material.set_shader_parameter("billboard",true)
	spray_material.set_shader_parameter("detail_texture",load(SPRAY_DETAIL))
	spray_material.render_priority = 4
	spray.material_override = spray_material; spray.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var column := _volume_node("WaterColumn",node)
	var shell := _volume_node("UmbrellaShell",node)
	column.material_override.set_shader_parameter("foam_texture",load(COLUMN))
	shell.material_override.set_shader_parameter("foam_texture",load(COLUMN))
	var mist := MeshInstance3D.new(); mist.name = "WeakMist"; mist.mesh = _spray_mesh(); node.add_child(mist)
	var mist_material := _material(MIST); mist_material.render_priority = 4
	mist_material.set_shader_parameter("detail_texture",load(MIST)); mist_material.set_shader_parameter("billboard",true)
	mist.material_override = mist_material; mist.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var surface_only := bool(event.get("surface_only",false))
	var froth: MeshInstance3D = _volume_node("SurfaceFroth",node) if surface_only else null
	var drops := MultiMeshInstance3D.new(); drops.name = "WorldDroplets"; node.add_child(drops)
	drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pool := MultiMesh.new(); pool.transform_format = MultiMesh.TRANSFORM_3D; pool.use_colors = true
	var droplet := Volume.droplet_mesh()
	var drop_material := ShaderMaterial.new(); drop_material.shader = VolumeShader
	drop_material.set_shader_parameter("foam_texture",load(STREAK)); drop_material.set_shader_parameter("opacity",0.85)
	drop_material.render_priority = 5; droplet.surface_set_material(0,drop_material)
	pool.mesh = droplet; pool.instance_count = Volume.DROPLETS; drops.multimesh = pool
	var birth_height := float(point.get("y",Volume.height(_water,origin,stamp)))
	if not is_finite(birth_height): birth_height = Volume.height(_water,origin,stamp)
	var splash := {"node":node,"ring":ring,"spray":spray,"mist":mist,"ring_material":ring_material,"spray_material":spray_material,"origin":origin,"time":stamp,"column":column,"shell":shell,"drops":drops,"birth_origin":Vector3(origin.x,birth_height,origin.y),"seed":absi(id.hash()),"active_drops":0,"scale":size,"surface_only":surface_only,"froth":froth}
	if not surface_only:
		if is_instance_valid(_reference_camera):
			var reference := FidelityReference.new(); reference.name = "FidelityReferenceSplash"; node.add_child(reference)
			var variant := 1+posmod(splash.seed,3)
			if reference.configure("cannon_ball_splash_0%d.nif"%variant,{"origin":splash.birth_origin,"scale":size,"seed":splash.seed,"water":_water,"sea":_sea_callback(),"camera":_reference_camera,"clock_mode":"native"}): splash.reference = reference; splash.fidelity = true
			else: reference.free()
		else:
			var reference := Reference.new(); reference.name = "ReferenceSplash"; node.add_child(reference)
			if reference.configure(splash.birth_origin,size,splash.seed,_water,_sea_callback()): splash.reference = reference
			else: reference.free()
	if not id.is_empty(): _seen[id] = stamp
	_splashes.append(splash); _update(splash,age)

func _volume_node(label: String, parent: Node3D) -> MeshInstance3D:
	var node := MeshInstance3D.new(); node.name = label; parent.add_child(node)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new(); material.shader = VolumeShader; material.render_priority = 4
	material.set_shader_parameter("foam_texture",load(FROTH)); node.material_override = material
	return node

func _material(path: String) -> ShaderMaterial:
	var material := ShaderMaterial.new(); material.shader = Foam
	material.render_priority = 3 # Surface rings follow ocean/shore, retaining depth testing.
	material.set_shader_parameter("foam_texture",load(path))
	material.set_shader_parameter("foam_tint",Color(0.83,0.96,1.0))
	return material

func _spray_mesh() -> ArrayMesh:
	# Feathered ellipse prevents rectangular mist corners. The original alpha
	# supplies internal detail; the retained Pak7 fallback uses the same carrier.
	const SEGMENTS := 24
	const BANDS := 8
	var vertices := PackedVector3Array([Vector3.ZERO])
	var uvs := PackedVector2Array([Vector2(0.5,0.5)])
	var colors := PackedColorArray([Color.WHITE]); var indices := PackedInt32Array()
	for band in range(1,BANDS+1):
		var radius := float(band)/BANDS
		var alpha := 1.0-smoothstep(0.28,1.0,radius)
		for segment in SEGMENTS:
			var angle := TAU*segment/SEGMENTS
			var offset := Vector2(cos(angle),sin(angle))*radius
			vertices.append(Vector3(offset.x*1.3,offset.y*1.4,0.0))
			uvs.append(Vector2(0.5,0.5)+offset*0.5); colors.append(Color(1,1,1,alpha))
			var a := 1+(band-1)*SEGMENTS+segment
			var b := 1+(band-1)*SEGMENTS+(segment+1)%SEGMENTS
			if band == 1: indices.append_array(PackedInt32Array([0,a,b]))
			else:
				var previous_a := a-SEGMENTS; var previous_b := b-SEGMENTS
				indices.append_array(PackedInt32Array([previous_a,a,previous_b,previous_b,a,b]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _update(splash: Dictionary, age: float) -> void:
	var was_active := _begin_sea_sampling()
	var surface_filter := _sea_callback()
	var radius := (0.8+age*2.4)*float(splash.scale)
	var vertices := PackedVector3Array(); var uvs := PackedVector2Array()
	var colors := PackedColorArray(); var indices := PackedInt32Array()
	var wet: Array[bool] = []
	for row in GRID+1:
		for column in GRID+1:
			var uv := Vector2(float(column)/GRID,float(row)/GRID)
			var p: Vector2 = splash.origin+(uv-Vector2(0.5,0.5))*radius*2.0
			var height := float(_water.call(p.x,p.y,_time))
			if not is_finite(height): height = 0.0
			vertices.append(Vector3(p.x,height+0.10,p.y)); uvs.append(uv); colors.append(Color.WHITE)
			wet.append(Volume.sea(surface_filter,p))
			if row < GRID and column < GRID:
				var a := row*(GRID+1)+column; var b := a+GRID+1
				indices.append_array(PackedInt32Array([a,b,a+1,a+1,b,b+1]))
	var arrays: Array = []; arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices; arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colors; arrays[Mesh.ARRAY_INDEX] = indices
	var valid := PackedInt32Array()
	for i in range(0,indices.size(),3):
		if wet[indices[i]] and wet[indices[i+1]] and wet[indices[i+2]]: valid.append_array(PackedInt32Array([indices[i],indices[i+1],indices[i+2]]))
	arrays[Mesh.ARRAY_INDEX] = valid
	var mesh := ArrayMesh.new()
	if not valid.is_empty(): mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	splash.ring.mesh = mesh
	splash.ring_material.set_shader_parameter("opacity",pow(1.0-age/DURATION,1.35)*0.70)
	if splash.surface_only:
		splash.column.visible = false; splash.shell.visible = false
		splash.drops.visible = false; splash.spray.visible = false; splash.mist.visible = false
		splash.active_drops = 0; splash.droplet_positions = []
		splash.froth.mesh = Volume.surface_froth(splash.origin,radius*0.75,_time,_water,surface_filter)
		splash.froth.visible = splash.froth.mesh != null
		splash.froth.material_override.set_shader_parameter("opacity",pow(1.0-age/DURATION,1.35)*0.38)
		_end_sea_sampling(was_active)
		return
	var spray_life := clampf(1.0-age/0.9,0.0,1.0)
	splash.spray.visible = false # Kept as the existing mask fallback; default uses original mist dependency.
	splash.spray.position = Vector3(splash.origin.x,Volume.height(_water,splash.origin,_time)+(0.6+age*0.8)*float(splash.scale),splash.origin.y)
	splash.spray.scale = Vector3.ONE*(1.0+age*0.7)*float(splash.scale)
	splash.spray_material.set_shader_parameter("opacity",spray_life*0.10)
	splash.mist.visible = spray_life > 0.0
	splash.mist.position = splash.spray.position; splash.mist.scale = splash.spray.scale
	splash.mist.material_override.set_shader_parameter("opacity",spray_life*0.08)
	var volume_fade := 1.0-smoothstep(0.18,0.95,age)
	for component: MeshInstance3D in [splash.column,splash.shell]:
		component.visible = volume_fade > 0.001
		if component.visible:
			component.mesh = Volume.build(splash.birth_origin,age,_time,component == splash.shell,_water,surface_filter,splash.scale)
			component.material_override.set_shader_parameter("opacity",volume_fade*(0.55 if component == splash.shell else 0.72))
	var cloud := Volume.update_droplets(splash.drops.multimesh,splash.birth_origin,age,splash.seed,_time,_water,surface_filter,splash.scale)
	splash.active_drops = cloud.active; splash.droplet_positions = cloud.positions
	if splash.has("reference"): splash.reference.apply_snapshot(age,_time)
	_end_sea_sampling(was_active)

func diagnostics() -> Dictionary:
	finish_snapshot()
	var drops := 0
	var positions: Array[Vector3] = []
	for splash: Dictionary in _splashes:
		drops += int(splash.active_drops); positions.append_array(splash.droplet_positions)
	var sources: Array=[]
	for splash: Dictionary in _splashes:
		if splash.has("fidelity"): sources.append(splash.reference.diagnostics())
	return {"splashes":_splashes.size(),"accepted_time":_time,"droplets":drops,"droplet_capacity":_splashes.size()*Volume.DROPLETS,"droplet_positions":positions,"fidelity_sources":sources,"pending_snapshot":_pending_snapshot}

func _free_splash(splash: Dictionary) -> void:
	# Dispose joins and discards source work before its Node/resources disappear.
	# No generic geometry or doomed source payload is presented during teardown.
	if splash.has("reference"): splash.reference.dispose()
	splash.node.free()

func _clear() -> void:
	_pending_snapshot = false; _pending_same_time = false
	_sea_cache.clear(); _sea_sampling = false
	for splash: Dictionary in _splashes: _free_splash(splash)
	_splashes.clear()
	_seen.clear()

func dispose() -> void:
	_clear(); _water = Callable(); _surface_filter = Callable(); _reference_camera = null; _time = -1.0

func _exit_tree() -> void: dispose()
