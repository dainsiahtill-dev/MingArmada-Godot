extends SceneTree
## State-based coverage: water effects consume authority snapshots and events.
var assertions := 0
var failures := 0

func check(ok: bool, message: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL: ", message)

func _initialize() -> void: _run.call_deferred()

func _water(x: float, z: float, seconds: float) -> float:
	return sin(x * 0.07 + seconds) * 0.4 + cos(z * 0.09 + seconds) * 0.2

func _ship(x: float, z: float, heading: float, speed: float) -> Dictionary:
	return {"id":"vessel", "hull":100.0, "dimensions":{"length":20.0,"width":5.0}, "visual":{"position":{"x":x,"y":0.0,"z":z},"heading":heading,"velocity":{"x":cos(heading)*speed,"z":sin(heading)*speed}}}

func _connections(mesh: ArrayMesh) -> Dictionary:
	# Five cross-sections per observed stern row. Inspect rendered topology,
	# not private break flags: no triangle may bridge an unobserved voyage leg.
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var pairs := {}; var largest := 0.0
	for offset in range(0,indices.size(),3):
		for edge in 3:
			var a := int(indices[offset+edge]/5); var b := int(indices[offset+(edge+1)%3]/5)
			if a == b: continue
			pairs["%d:%d" % [mini(a,b),maxi(a,b)]] = true
			var first: Vector3 = vertices[a*5+2]; var second: Vector3 = vertices[b*5+2]
			largest = maxf(largest,Vector2(first.x,first.z).distance_to(Vector2(second.x,second.z)))
	return {"rows":vertices.size()/5,"pairs":pairs.size(),"largest":largest}

func _check_resumption(wakes: Node3D, mode: String) -> void:
	wakes.configure(_water)
	for step in 10: wakes.apply_snapshot({"time":80.0+step*0.2,"ships":[_ship(step*0.6,0,0,3)]})
	var original: MeshInstance3D = wakes.get_child(0)
	if mode == "pause":
		for step in 5: wakes.apply_snapshot({"time":81.8,"ships":[_ship(5.4,0,0,0)]})
	else:
		for step in 5:
			var vessel := _ship(5.4-(step+1)*0.6,0,0,-3) if mode == "reverse" else _ship(5.4,(step+1)*0.6,0,0)
			if mode == "side": vessel.visual.velocity = {"x":0.0,"z":3.0}
			wakes.apply_snapshot({"time":82.0+step*0.2,"ships":[vessel]})
	for step in 6:
		var x := 3.0+step*0.6 if mode == "reverse" else 6.0+step*0.6
		wakes.apply_snapshot({"time":83.0+step*0.2,"ships":[_ship(x,3.0 if mode == "side" else 0.0,0,3)]})
	var topology := _connections(wakes.get_child(0).mesh)
	check(topology.largest < 0.8, mode+" resumption cannot bridge the unrecorded motion gap")
	check(topology.pairs == topology.rows-1 if mode == "pause" else topology.pairs < topology.rows-1, mode+" preserves the appropriate continuous or separated wake segments")
	check(is_instance_valid(original) and wakes.get_child_count() == 1 and wakes.get_child(0) == original, mode+" resumption retains old foam in the existing bounded mesh")

func _check_wake_mask(arrays: Array) -> void:
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var peak := 0.0; var soft_edges := true
	for row in colors.size()/5:
		peak = maxf(peak,colors[row*5+2].a)
		soft_edges = soft_edges and colors[row*5].a < 0.001 and colors[row*5+4].a < 0.001
		soft_edges = soft_edges and colors[row*5+1].a <= colors[row*5+2].a*0.65
	check(soft_edges, "wake cross-section alpha smoothly fades away from its centerline")
	check(colors[7].a < peak*0.4, "wake head fades over multiple observed rows rather than a flat cut")
	check(colors[colors.size()-8].a < peak*0.3, "wake tail fades over multiple observed rows rather than a flat cut")

func _check_spray_mask(spray: MeshInstance3D) -> void:
	var arrays := spray.mesh.surface_get_arrays(0)
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	var ellipse := true; var feathered := true; var softened := false
	for index in uvs.size():
		var radius := (uvs[index]-Vector2(0.5,0.5)).length()*2.0
		ellipse = ellipse and radius <= 1.0001
		if radius > 0.99: feathered = feathered and colors.size() > index and colors[index].a < 0.001
		if colors.size() > index and radius > 0.5 and radius < 0.99 and colors[index].a > 0.01 and colors[index].a < 0.8: softened = true
	check(ellipse, "splash geometry cannot cover rectangular billboard corners")
	check(feathered and softened, "splash ellipse has a broad translucent perimeter")
	var source: Texture2D = spray.material_override.get_shader_parameter("foam_texture")
	var mask := source.get_image(); var occupied := 0
	for y in mask.get_height():
		for x in mask.get_width():
			if mask.get_pixel(x,y).a > 0.01: occupied += 1
	check(float(occupied)/(mask.get_width()*mask.get_height()) < 0.4, "splash primary alpha is sparse droplets rather than a filled cloud square")
	check(spray.material_override.get_shader_parameter("detail_texture") is Texture2D, "dense splash02 texture is retained only as internal droplet detail")

func _run() -> void:
	var wake_path := "res://game/presentation/water/wake_trails.gd"
	var wake_script = load(wake_path) if FileAccess.file_exists(wake_path) else null
	check(wake_script != null, "native curved Pirates wake presenter exists")
	if wake_script:
		var wakes = wake_script.new(); root.add_child(wakes); wakes.configure(_water)
		wakes.apply_snapshot({"time":0.0,"ships":[_ship(0,0,0,0)]})
		wakes.apply_snapshot({"time":1.0,"ships":[_ship(0,0,0,0)]})
		check(wakes.diagnostics().trails == 0, "stationary ship produces no rectangular wake")
		for step in 16:
			var angle := float(step) * 0.06
			wakes.apply_snapshot({"time":2.0+step*0.2,"ships":[_ship(step*0.8,step*step*0.045,angle,4)]})
		check(wakes.diagnostics().trails == 1 and wakes.diagnostics().samples > 3, "accepted movement leaves a continuous curved trail")
		var mesh_node: MeshInstance3D = wakes.get_child(0)
		check(mesh_node.material_override.render_priority > 2, "wake draws after transparent sea and shoreline passes")
		check(mesh_node.material_override.get_shader_parameter("foam_texture") is Texture2D, "wake binds imported original mask texture")
		check(mesh_node.material_override.get_shader_parameter("detail_texture") is Texture2D, "wake binds imported Pak3 froth texture")
		var before: Array = mesh_node.mesh.surface_get_arrays(0)
		_check_wake_mask(before)
		var x_values := {}; var z_values := {}
		for vertex: Vector3 in before[Mesh.ARRAY_VERTEX]:
			x_values[snappedf(vertex.x,0.01)] = true; z_values[snappedf(vertex.z,0.01)] = true
			check(absf(vertex.y - _water(vertex.x,vertex.z,5.0) - wakes.SURFACE_OFFSET) < 0.0001, "each wake vertex conforms to authority water height")
		check(x_values.size() > 5 and z_values.size() > 5, "wake geometry follows turning stern rather than one rectangle")
		wakes.apply_snapshot({"time":5.0,"ships":[_ship(12,10,0.8,4)]})
		check(before == mesh_node.mesh.surface_get_arrays(0), "unchanged authority time freezes wake despite changed presentation pose")
		wakes.apply_snapshot({"time":0.5,"ships":[_ship(0,0,0,4)]})
		check(wakes.diagnostics().trails == 0 and wakes.diagnostics().samples == 0, "authority rollback clears future trail")
		for step in 100:
			wakes.apply_snapshot({"time":1.0+step*0.2,"ships":[_ship(step,0,0,5)]})
		check(wakes.diagnostics().samples <= wakes.MAX_SAMPLES, "long voyages retain a bounded trail history")
		wakes.apply_snapshot({"time":30.0,"ships":[_ship(99,0,0,0)]})
		check(wakes.diagnostics().trails == 0, "stopping releases fully faded wake")
		wakes.apply_snapshot({"time":31.0,"ships":[_ship(100,0,0,5)]})
		wakes.apply_snapshot({"time":31.2,"ships":[_ship(101,0,0,5)]})
		wakes.apply_snapshot({"time":31.4,"ships":[]})
		check(wakes.diagnostics().trails == 0, "removed ships release owned trails")
		for step in 180:
			wakes.apply_snapshot({"time":40.0+step/60.0,"ships":[_ship(step*0.05,0,0,3)]})
		check(wakes.diagnostics().trails == 1 and wakes.diagnostics().samples > 3, "normal sixty-Hz small movement accumulates a visible wake")
		var sunk := _ship(20,0,0,4); sunk.hull = 0.0
		wakes.apply_snapshot({"time":60.0,"ships":[sunk]})
		check(wakes.diagnostics().trails == 0, "sunk vessel cannot seed a new wake")
		wakes.configure(_water)
		for step in 12:
			wakes.apply_snapshot({"time":62.0+step*0.2,"ships":[_ship(-step*0.6,0,0,-3)]})
		check(wakes.diagnostics().trails == 0, "reverse travel does not emit a wake from the wrong stern")
		wakes.configure(_water)
		for step in 12:
			var lateral := _ship(0,step*0.6,0,0); lateral.visual.velocity = {"x":0.0,"z":3.0}
			wakes.apply_snapshot({"time":65.0+step*0.2,"ships":[lateral]})
		check(wakes.diagnostics().trails == 0, "pure side drift does not emit a stern wake")
		for mode: String in ["reverse","side","pause"]: _check_resumption(wakes,mode)
		wakes.configure(_water)
		var fleet: Array = []
		for index in 80:
			var vessel := _ship(0,index*20.0,0,4); vessel.id = "fleet-%d"%index; fleet.append(vessel)
		wakes.apply_snapshot({"time":70.0,"ships":fleet})
		for vessel: Dictionary in fleet: vessel.visual.position.x = 1.0
		wakes.apply_snapshot({"time":70.2,"ships":fleet})
		check(wakes.diagnostics().trails <= 32 and wakes.get_child_count() <= 32, "dense fleet obeys the shared visible wake budget")
		wakes.dispose(); wakes.dispose(); wakes.free()
	var effects_script = load("res://game/presentation/combat/combat_effects.gd")
	var effects = effects_script.new(); root.add_child(effects)
	check(effects.has_method("set_water_sampler"), "combat presenter accepts authority water sampler")
	if effects.has_method("set_water_sampler"):
		effects.set_water_sampler(_water)
		effects.apply_snapshot({"time":4.0,"projectiles":[]},0.0)
		var event := {"id":"water-shot","type":"splash","time":4.0,"position":{"x":3.0,"y":0.0,"z":4.0}}
		var unchanged := event.duplicate(true)
		effects.apply_events([event]); effects.apply_events([event])
		check(effects.diagnostics().splashes == 1, "one real splash event spawns one textured effect and deduplicates replay")
		check(event == unchanged, "water presentation does not mutate authority events")
		check(effects.diagnostics().puffs == 0, "water splash uses source textures rather than sphere puffs")
		var splash = effects.get_node("WaterSplashes")
		var ring: MeshInstance3D = splash.get_child(0).get_child(0)
		check(ring.material_override.render_priority > 2, "impact ripple draws after transparent sea and shoreline passes")
		check(splash.get_child(0).get_child(1).material_override.render_priority > ring.material_override.render_priority, "water spray draws after its transparent ripple plane")
		check(ring.material_override.get_shader_parameter("foam_texture") is Texture2D, "splash binds original imported ripple mask")
		check(splash.get_child(0).get_child(1).material_override.get_shader_parameter("foam_texture") is Texture2D, "splash binds original imported spray mask")
		_check_spray_mask(splash.get_child(0).get_child(1))
		var first: Array = ring.mesh.surface_get_arrays(0)
		effects.apply_snapshot({"time":4.0,"projectiles":[]},0.5)
		check(first == ring.mesh.surface_get_arrays(0), "paused authority time freezes splash even with wall delta")
		effects.apply_snapshot({"time":4.7,"projectiles":[]},0.0)
		check(first != ring.mesh.surface_get_arrays(0), "accepted time expands splash with zero wall delta")
		effects.apply_snapshot({"time":3.0,"projectiles":[]},0.0)
		check(effects.diagnostics().splashes == 0 and effects.diagnostics().events == 0, "rollback clears future splash and event cache")
		effects.apply_snapshot({"time":4.0,"projectiles":[]},0.0); effects.apply_events([event])
		effects.apply_snapshot({"time":10.0,"projectiles":[]},0.0)
		check(effects.diagnostics().splashes == 0, "expired splash releases meshes")
		effects.apply_events([event])
		check(effects.diagnostics().splashes == 0, "expired event does not resurrect splash")
		effects.apply_snapshot({"time":11.0,"projectiles":[]},0.0)
		var events: Array = []
		for index in 100: events.append({"id":"budget-%d"%index,"type":"splash","time":11.0,"position":{"x":index,"y":0.0,"z":0.0}})
		effects.apply_events(events)
		check(effects.diagnostics().splashes <= splash.MAX_SPLASHES, "simultaneous cannon splashes obey mesh budget")
		effects.dispose(); effects.dispose()
	effects.free()
	print("PIRATES_WATER_EFFECT_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
