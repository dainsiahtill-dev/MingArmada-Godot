extends SceneTree

const Splashes = preload("res://game/presentation/water/water_splashes.gd")
const Effects = preload("res://game/presentation/combat/combat_effects.gd")
const Encounter = preload("res://modules/naval_simulation/encounter.gd")
var assertions := 0
var failures := 0

func check(value: bool, reason: String) -> void:
	assertions += 1
	if not value:
		failures += 1
		printerr("FAIL: ",reason)

func _initialize() -> void: _run.call_deferred()
func _water(x: float,z: float,seconds: float) -> float: return x*.001+z*.002+seconds*.02
func _sea(x: float,_z: float) -> bool: return x < 50.0

func _run() -> void:
	var effects := Effects.new()
	root.add_child(effects)
	effects.position = Vector3(90,0,120)
	effects.set_water_sampler(_water)
	effects.set_surface_filter(_sea)
	effects.apply_snapshot({"time":10.5,"projectiles":[]},0.0)
	var event := {"id":"real-shot","projectileId":"ball","type":"splash","time":10.0,"position":{"x":3.0,"y":.211,"z":4.0}}
	effects.apply_events([event,event])
	var presenter: Node3D=effects.get_node("WaterSplashes")
	check(presenter.get_child_count()==1,"actual combat event path deduplicates the fused splash")
	var impact: Node3D=presenter.get_child(0)
	var reference: Node3D=impact.get_node_or_null("ReferenceSplash")
	check(reference != null,"actual combat splash includes exported source geometry and eight authored systems")
	if reference == null:
		effects.free()
		_finish()
		return
	check(impact.get_node("WaterColumn").mesh != null and impact.get_node("UmbrellaShell").mesh != null,"existing strong volume feedback remains alongside the new source layer")
	check(impact.get_node("RippleRing").mesh != null and impact.get_node("WorldDroplets").multimesh.instance_count == 24,"existing wave-conforming ripple and ballistic droplets remain intact")
	check(impact.global_transform == Transform3D.IDENTITY,"translated caller cannot move world-space impact geometry")
	var state: Dictionary=reference.diagnostics()
	check(state.meshes==7 and state.systems==8 and state.capacity==82,"all seven source meshes and exact eight source capacities are represented")
	var meshes: Array=reference.get_node("SourceGeometry").get_children()
	var columns := 0
	var rings := 0
	for node: MeshInstance3D in meshes:
		check(node.material_override.get_shader_parameter("foam_texture") is Texture2D,"each source geometry binds its real imported texture")
		if node.name.begins_with("Cylinder"):
			columns+=1
			var arrays: Array=node.mesh.surface_get_arrays(0)
			check(arrays[Mesh.ARRAY_VERTEX].size()==78 and arrays[Mesh.ARRAY_INDEX].size()==378,"source water column retains exact 78 vertices and 126 triangles")
		else:
			rings+=1
			if node.mesh:
				for point: Vector3 in node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
					check(absf(point.y-_water(point.x,point.z,10.5)-.14)<.000001,"every authored ring corner conforms to the actual accepted sea phase")
	check(columns==2 and rings==5,"source geometry separates two solid columns and five independently animated ring layers")
	var capacities: Array[int]=[]
	for system: MultiMeshInstance3D in reference.get_node("SourceParticles").get_children():
		capacities.append(system.multimesh.instance_count)
		var material: ShaderMaterial=system.multimesh.mesh.surface_get_material(0)
		check(material.get_shader_parameter("foam_texture") is Texture2D,"all eight source systems bind their authored streak or mist dependency")
	check(capacities==[15,4,16,12,8,20,4,3],"real emitter MultiMeshes retain each authored capacity in source system order")
	check(state.particles>0 and state.particles<=82,"authored emitter windows produce finite visible particles at source secondary-splash age")
	var frozen: Dictionary=state.duplicate(true)
	effects.apply_snapshot({"time":10.5,"projectiles":[]},100.0)
	check(reference.diagnostics()==frozen,"wall delta cannot age geometry, UV, alpha or reference particle positions")
	var direct := Splashes.new()
	root.add_child(direct)
	direct.configure(_water); direct.configure_surface_filter(_sea); direct.apply_snapshot(10.5)
	direct.add_event(event)
	check(direct.get_child(0).get_node("ReferenceSplash").diagnostics()==frozen,"delayed event reconstructs the same reference state without frame-sized integration")
	var replica: Node3D=direct.get_child(0).get_node("ReferenceSplash")
	check(not replica.apply_snapshot(NAN,10.5) and not replica.apply_snapshot(.5,INF),"invalid authority inputs cannot enter source curve or trajectory evaluation")
	check(replica.diagnostics()==frozen,"invalid source evaluation leaves all accepted state unchanged")
	_check_authored_curves(replica)
	effects.apply_snapshot({"time":10.6,"projectiles":[]},0.0)
	check(reference.diagnostics().positions != frozen.positions,"accepted event age advances authored world-space particles")
	effects.apply_events([{"id":"sink","type":"sinking-froth","time":10.6,"position":{"x":20,"y":.23,"z":4}}])
	var sink: Node3D=presenter.get_child(1)
	check(sink.get_node_or_null("ReferenceSplash")==null and sink.get_node("SurfaceFroth").mesh!=null,"surface-only sinking preserves froth without a new cannon emitter")
	direct.add_event({"id":"dry","time":10.5,"position":{"x":80,"z":0}})
	check(direct.get_child_count()==1,"dry impact never spawns source geometry or source particles")
	direct.add_event({"id":"coast","time":10.0,"position":{"x":49.8,"y":.25,"z":0}})
	var coastal: Dictionary=direct.get_child(1).get_node("ReferenceSplash").diagnostics()
	check(coastal.positions.all(func(p:Vector3):return p.x<50.0),"source droplets and mist reaching dry land are removed from visible slots")
	effects.apply_snapshot({"time":9.0,"projectiles":[]},0.0)
	check(presenter.get_child_count()==0,"rollback frees every source layer with its existing impact owner")
	direct.apply_snapshot(14.0)
	check(direct.get_child_count()==0,"existing effect lifetime releases new geometry and source emitter pools")
	direct.dispose(); direct.dispose(); direct.free(); effects.free()
	_check_live_surface_filter()
	await _actual_cannon_event()
	_finish()

func _check_live_surface_filter() -> void:
	var presenter := Splashes.new()
	root.add_child(presenter)
	presenter.configure(_water); presenter.configure_surface_filter(_sea); presenter.apply_snapshot(10.5)
	presenter.add_event({"id":"changing-filter","time":10.0,"position":{"x":3,"y":.211,"z":4}})
	var reference: Node3D=presenter.get_child(0).get_node("ReferenceSplash")
	check(reference.diagnostics().particles>0,"active reference slots use the initially shared sea filter")
	presenter.configure_surface_filter(func(_x,_z):return false)
	presenter.apply_snapshot(10.6)
	check(reference.diagnostics().particles==0,"reconfigured shared sea filter reaches already active source slots")
	check(reference.get_node("SourceGeometry").get_children().all(func(node:MeshInstance3D):return not node.visible),"source geometry and source particles use the same reconfigured coast contract")
	presenter.free()

func _check_authored_curves(reference: Node3D) -> void:
	# Independent constants read from original controller 100/101 and 13/14.
	check(reference.apply_snapshot(.05,10.05),"authored source curves can be sought to an initial-ring phase")
	var geometry: Node3D=reference.get_node("SourceGeometry")
	var initial: MeshInstance3D=geometry.get_node("SourceRing_95")
	var secondary: MeshInstance3D=geometry.get_node("SourceRing_113")
	check(absf(float(initial.material_override.get_shader_parameter("opacity"))-.35)<.000001,"initial authored ring alpha plateau is one before the documented readability gain")
	check(not secondary.visible and not geometry.get_node("Cylinder01").visible,"late authored rings and columns stay hidden before their controller start")
	var vertices: PackedVector3Array=initial.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var initial_span: float=vertices[0].distance_to(vertices[1])
	reference.apply_snapshot(.5,10.5)
	vertices=initial.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	check(vertices[0].distance_to(vertices[1])>initial_span*5,"authored parent scale curve expands the exact source ring rather than a static quad")
	check(secondary.visible,"source secondary alpha controller activates at its separate late event phase")
	reference.apply_snapshot(.42520833015441895,10.425208330154419)
	var first: ShaderMaterial=geometry.get_node("Cylinder01").material_override
	var second: ShaderMaterial=geometry.get_node("Cylinder02").material_override
	check(absf(float(first.get_shader_parameter("opacity"))-.025018533691763878*18)<.000001,"first source column retains the exact authored alpha peak before the documented gain")
	check(absf(float(second.get_shader_parameter("opacity"))-.043625954538583755*18)<.000001,"second source column has its distinct authored alpha peak")
	reference.apply_snapshot(.42625001072883606,10.426250010728836)
	check(absf(first.get_shader_parameter("uv_offset").y-(-.7010012269020081))<.000001,"source column uses exact controller V translation instead of a wall-clock UV scroll")
	reference.apply_snapshot(1.7,11.7)
	check(geometry.get_children().all(func(node:MeshInstance3D):return not node.visible),"source mesh alpha tails finish independently of retained legacy ripple lifetime")
	check(reference.diagnostics().particles==0,"base authored particle lifespans and color tails release every source visible slot")
	reference.apply_snapshot(.5,10.5)

func _actual_cannon_event() -> void:
	var encounter := Encounter.new({"mode":"continuous","controllableShipIds":["player"],"referenceGunnery":true,"ships":[{"id":"player","kind":"fuchuan","team":"player","crew":100.0,"position":{"x":0.0,"z":0.0},"sailDeployment":0.0}],"wind":{"direction":{"x":1.0,"y":0.0},"speed":0.0},"oceanWaves":[],"sampleTerrainHeight":func(_x,_z):return -80.0})
	check(encounter.command({"type":"fire","side":"starboard"}).ok,"real encounter launches a finite broadside into open water")
	encounter.drain_events()
	var effects := Effects.new()
	root.add_child(effects); effects.set_water_sampler(func(_x,_z,_t):return 0.0)
	var source_events := 0
	var fused := false
	for tick: int in 360:
		encounter.step(1.0/60.0)
		var events: Array=encounter.drain_events()
		effects.apply_snapshot(encounter.snapshot(),1.0/60.0)
		effects.apply_events(events)
		for event: Dictionary in events:
			if event.type=="splash": source_events+=1
		for impact: Node3D in effects.get_node("WaterSplashes").get_children():
			fused = fused or impact.get_node_or_null("ReferenceSplash") != null
	check(source_events>0 and fused,"actual projectile water collision reaches the new source splash through the unchanged combat event API")
	effects.free()
	await process_frame

func _finish() -> void:
	print("REFERENCE_SPLASH_FUSION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
