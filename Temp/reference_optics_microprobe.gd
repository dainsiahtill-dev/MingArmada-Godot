extends SceneTree

const Ocean = preload("res://modules/scene_engine/ocean/projected_ocean.gd")
const Terrain = preload("res://modules/scene_engine/terrain/terrain_chunk.gd")
const PARAMS := ["simulation_time", "wave_components", "wave_count", "shore_bounds", "has_shore_field", "shore_height_texture", "coastal_attenuation"]

class TimedOcean extends Ocean:
	var upload_us := 0
	var upload_calls := 0
	func _upload_grid() -> void:
		var start := Time.get_ticks_usec()
		super._upload_grid()
		upload_us += Time.get_ticks_usec() - start
		upload_calls += 1

func _initialize() -> void: _run.call_deferred()

func _reads(material: ShaderMaterial, repeat_count: int, iterations: int) -> float:
	var start := Time.get_ticks_usec()
	for _frame in iterations:
		for _chunk in repeat_count:
			for key: String in PARAMS:
				material.get_shader_parameter(key)
	return float(Time.get_ticks_usec() - start) / iterations / 1000.0

func _sync(material: ShaderMaterial, chunks: Array, changing: bool, iterations: int) -> float:
	var start := Time.get_ticks_usec()
	for frame in iterations:
		material.set_shader_parameter("simulation_time", float(frame) if changing else 0.0)
		for chunk: Node3D in chunks:
			chunk.sync_surface_state(material)
	return float(Time.get_ticks_usec() - start) / iterations / 1000.0

func _run() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1600,900)
	root.add_child(viewport)
	var camera := Camera3D.new()
	camera.fov = 55
	camera.near = 0.5
	camera.far = 4000
	viewport.add_child(camera)
	camera.position = Vector3(33,24,-39)
	camera.look_at(Vector3.ZERO)
	var ocean := TimedOcean.new()
	viewport.add_child(ocean)
	ocean.configure(camera,load("res://assets/textures/waternormals.jpg"),80)
	var material: ShaderMaterial = ocean.material_override
	var chunks: Array = []
	for index in 49:
		var chunk := Terrain.new()
		chunk.configure(func(_x:float,_z:float): return -30.0,Vector2i(index,0),250,4,false,{"detailed":true})
		viewport.add_child(chunk)
		chunk.sync_surface_state(material)
		chunks.append(chunk)
	var trials: Array = []
	for _trial in 4:
		trials.append({"reads_49x7_mean_ms":_reads(material,49,500), "reads_1x7_mean_ms":_reads(material,1,500), "sync49_same_time_mean_ms":_sync(material,chunks,false,200), "sync49_changed_time_mean_ms":_sync(material,chunks,true,200)})
	var start := Time.get_ticks_usec()
	for _frame in 1000: ocean.update_projection()
	var stationary_ms := float(Time.get_ticks_usec()-start)/1000.0/1000.0
	ocean.upload_us=0
	ocean.upload_calls=0
	var samples: Array[float] = []
	for frame in 120:
		camera.position = Vector3(33.0+frame*.06,24,-39)
		var before := Time.get_ticks_usec()
		ocean.update_projection()
		samples.append(float(Time.get_ticks_usec()-before)/1000.0)
	var mean := 0.0
	for value in samples: mean += value / samples.size()
	samples.sort()
	print("OPTICS_MICROPROBE ",JSON.stringify({"schema":"reference-optics-cpu-microprobe-v1","scope":"headless CPU only; no GPU render or FPS baseline","engine":Engine.get_version_info().string,"viewport":[1600,900],"segments":80,"vertices":6561,"chunks":49,"trials":trials,"stationary_projection_mean_ms":stationary_ms,"moving_projection_mean_ms":mean,"moving_projection_p95_ms":samples[floori((samples.size()-1)*.95)],"moving_upload_mean_ms":float(ocean.upload_us)/maxi(1,ocean.upload_calls)/1000.0,"moving_upload_calls":ocean.upload_calls}))
	viewport.free()
	quit()
