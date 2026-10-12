extends SceneTree
## Actual source oracle and runtime consumer checks; no wall-time thresholds.
const SAMPLER_PATH := "res://modules/scene_engine/fidelity_island/compiled_shore_sampler.gd"
const Surf = preload("res://modules/scene_engine/terrain/natural_shore_surf.gd")
const Field = preload("res://modules/scene_engine/terrain/natural_island_field.gd")
const Source = preload("res://modules/scene_engine/fidelity_island/mesh_asset.gd")
const Authored = preload("res://modules/scene_engine/fidelity_island/shore.gd")
const Native = preload("res://modules/scene_engine/fidelity_island/native_math.gd")
const Ocean = preload("res://modules/scene_engine/ocean/reference_game_water.gdshader")
const Waves = preload("res://modules/contracts/wave_descriptor.gd")
var assertions := 0
var failures := 0
class CountingSampler extends RefCounted:
	var delegate: RefCounted
	var calls := 0
	var texture_matrix := Basis.IDENTITY
	var alpha_phase := 0.0
	func sample(index: int,time: float) -> Dictionary:
		calls += 1
		var state: Dictionary = delegate.sample(index,time)
		texture_matrix = delegate.texture_matrix; alpha_phase = delegate.alpha_phase
		return state
func _initialize() -> void: _run.call_deferred()
func check(ok: bool,detail: String) -> void:
	assertions += 1
	if not ok: failures += 1; printerr("FAIL SHORE hotpath: ",detail)
func _bits(value: float) -> int:
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_float(0,value)
	return bytes.decode_u32(0)
func _from_bits(value: int) -> float:
	var bytes := PackedByteArray(); bytes.resize(4); bytes.encode_u32(0,value)
	return bytes.decode_float(0)
func _basis_bytes(basis: Basis) -> PackedByteArray:
	return PackedFloat32Array([basis.x.x,basis.x.y,basis.x.z,basis.y.x,basis.y.y,basis.y.z,basis.z.x,basis.z.y,basis.z.z]).to_byte_array()
func _equivalent(sampler: RefCounted,source: Dictionary,index: int,time: float) -> bool:
	var expected: Dictionary = Authored.authored_state(source.meshes[index],source.curves,time)
	var state: Dictionary = sampler.sample(index,time)
	for key in ["translationU","scaleU","alpha"]:
		if _bits(state[key]) != _bits(expected[key]): return false
	var clock := Native.ControllerClock.new(source.meshes[index].controllers.alpha)
	var mapped: float = clock.advance(time)
	var controller: Dictionary = source.meshes[index].controllers.alpha
	var phase: float = (mapped-float(controller.start_time))/(float(controller.stop_time)-float(controller.start_time))
	if sampler.alpha_phase != phase: return false
	return _basis_bytes(sampler.texture_matrix) == Native.texture_transform(source.meshes[index].texture,expected).to_byte_array()
func _run() -> void:
	var source: Dictionary = Source.read_json("res://assets/data/fidelity_island/shore-scene.json")
	check(source.meshes.size()==8,"all eight actual authored meshes remain the source")
	check(ResourceLoader.exists(SAMPLER_PATH),"a prepared stateless source sampler replaces per-packet clock construction")
	if ResourceLoader.exists(SAMPLER_PATH):
		var sampler: RefCounted = load(SAMPLER_PATH).new()
		check(sampler.configure(source),"actual controller/curve/texture descriptors prepare once")
		var random := RandomNumberGenerator.new(); random.seed = 613705
		var bit_error := false
		for i in 4096:
			var value: float = random.randf_range(-1.0,1.0)*pow(10.0,random.randf_range(-40.0,35.0))
			bit_error = bit_error or _bits(sampler.call("_f32",value)) != _bits(Native.f32(value))
		check(not bit_error,"reused float32 storage equals the original encode/decode bits across 4096 magnitudes")
		for value: float in [0.0,-0.0,1.0000000596046448,1.0000001788139343,-1.0000000596046448,1.401298464324817e-45,7.006492321624085e-46,3.4028234663852886e38]:
			check(_bits(sampler.call("_f32",value))==_bits(Native.f32(value)),"binary32 signed zero, tie and finite extremes retain original bits")
		for index in 8:
			var times: Array[float] = [0.0,0.000001,12.0,29.966665,29.96666717529297,30.0,60.0,18.0,1.0,-0.001,0.0,3600.0,18000.0,1000000.25]
			for controller: Dictionary in source.meshes[index].controllers.values():
				var boundary: float = (float(controller.stop_time)-float(controller.phase))/float(controller.frequency)
				for offset: float in [-0.00001,0.0,0.00001]: times.append(boundary+offset)
			var error := false
			for time: float in times: error = error or not _equivalent(sampler,source,index,time)
			check(not error,"source mesh %d preserves binary32 alpha/UV, distinct periods, exact boundaries and rewind"%index)
			var key_boundary_error := false
			for name: String in ["translation","scale","alpha"]:
				var controller: Dictionary = source.meshes[index].controllers[name]
				for key: Dictionary in source.curves[name].keys:
					if float(key.time)<=0.0: continue
					var bits: int = _bits(float(key.time))
					var lower: float = _from_bits(bits-1); var exact: float = _from_bits(bits); var upper: float = _from_bits(bits+1)
					for mapped: float in [lower,(lower+exact)*0.5,exact,(exact+upper)*0.5,upper]:
						var time: float = (mapped-float(controller.phase))/float(controller.frequency)
						key_boundary_error = key_boundary_error or not _equivalent(sampler,source,index,time)
			check(not key_boundary_error,"source mesh %d preserves all real key predecessor/successor and halfway float32 boundaries"%index)
		var random_sample_error := false
		for i in 4096:
			var index: int = random.randi_range(0,7)
			var time: float = random.randf_range(-90.0,36000.0)
			random_sample_error = random_sample_error or not _equivalent(sampler,source,index,time)
		check(not random_sample_error,"4096 independent eight-source times preserve original curve bits, alpha phase and matrix bytes")
	var field := Field.new(); check(field.configure({"resolution":65}),"real accepted terrain builds")
	var surf := Surf.new(); root.add_child(surf); check(surf.configure(field),"actual source packet consumer configures")
	var initial: Dictionary = surf.diagnostics()
	check(initial.states.size()==initial.patchCount and initial.patchCount>16,"first t=0 applies every real packet rather than being skipped")
	var original_state: Dictionary = surf.get("_states")[0]
	surf.apply_snapshot({"time":0.0},0.0)
	check(is_same(original_state,surf.get("_states")[0]),"same-time real consumer retains its computed state object instead of rebuilding it")
	var has_sampler := false
	for property: Dictionary in surf.get_property_list(): has_sampler = has_sampler or property.name == "_sampler"
	check(has_sampler,"consumer owns its prepared sampler for its entire configured lifetime")
	if has_sampler:
		var spy := CountingSampler.new(); spy.delegate = surf.get("_sampler"); surf.set("_sampler",spy)
		surf.apply_snapshot({"time":0.0},0.0)
		check(spy.calls==0,"same accepted initial time performs no source controller resampling")
		var packet_error := false
		for seconds: float in [12.0,12.000000001,30.0,29.96666717529297,60.0,6.0]:
			var before: int = spy.calls; surf.apply_snapshot({"time":seconds},0.0)
			check(spy.calls-before==initial.patchCount,"each changed accepted time samples every packet exactly once, including rewind")
			var state: Dictionary = surf.diagnostics()
			for i in state.packets.size():
				var packet: Dictionary = state.packets[i]
				var expected: Dictionary = Authored.authored_state(source.meshes[packet.sourceIndex],source.curves,seconds*packet.clockSpeed+packet.clockOffset)
				var actual: Dictionary = state.states[i]
				packet_error = packet_error or _bits(actual.translationU)!=_bits(expected.translationU) or _bits(actual.scaleU)!=_bits(expected.scaleU) or _bits(actual.nativeAlpha)!=_bits(expected.alpha)
			var sampled: int = spy.calls; surf.apply_snapshot({"time":seconds,"focus":Vector2(600,-400)},20.0)
			check(spy.calls==sampled and surf.diagnostics().states==state.states,"same time with new focus/render delta preserves state without computation")
		check(not packet_error,"real seeded packet speeds/offsets consume exact eight-mesh authored curves")
		var before_invalid: int = spy.calls; surf.apply_snapshot({"time":NAN},0.0)
		check(spy.calls==before_invalid,"invalid clock does not sample or poison cached state")
		var ocean := ShaderMaterial.new(); ocean.shader=Ocean
		var components := PackedVector4Array()
		for wave: Array in Waves.original_components(): components.append(Vector4(wave[0],wave[1],wave[2],wave[3]))
		ocean.set_shader_parameter("wave_components",components); ocean.set_shader_parameter("wave_count",5); ocean.set_shader_parameter("simulation_time",6.0)
		ocean.set_shader_parameter("surface_visual_scale",0.2); ocean.set_shader_parameter("u_tide",0.75)
		check(surf.sync_surface_state(ocean),"surface uniforms still update independently of same-time controller cache")
		var material: ShaderMaterial = surf.get_child(0).material_override
		check(material.get_shader_parameter("surface_tide")==0.75 and material.get_shader_parameter("surface_visual_scale")==0.2,"same-time tide and visual field edits reach actual shader")
		ocean.set_shader_parameter("surface_visual_scale",0.4); ocean.set_shader_parameter("u_tide",-0.25)
		check(surf.sync_surface_state(ocean) and material.get_shader_parameter("surface_tide")==-0.25 and material.get_shader_parameter("surface_visual_scale")==0.4,"material identity never hides changed live ocean values")
		var coast_image := Image.create(2,2,false,Image.FORMAT_RF); coast_image.fill(Color(2.0,0.0,0.0))
		var coast_texture := ImageTexture.create_from_image(coast_image)
		var old_component: Vector4 = components[0]
		components[0] = Vector4(components[0].x+0.125,components[0].y,components[0].z,components[0].w)
		check(surf.get("_surface_state").wave_components[0]==old_component and surf.get("_surface_state").wave_components[0]!=components[0],"actual cached PackedArray snapshot cannot alias a caller component mutation")
		check(material.get_shader_parameter("wave_components")[0]==old_component,"actual ShaderMaterial retains its submitted old components until an explicit synchronization")
		ocean.set_shader_parameter("wave_components",components); ocean.set_shader_parameter("coast_distance_texture",coast_texture); ocean.set_shader_parameter("has_coast_distance",true)
		check(surf.sync_surface_state(ocean) and material.get_shader_parameter("wave_components")==components and material.get_shader_parameter("coast_distance_texture")==coast_texture and material.get_shader_parameter("has_coast_distance")==true,"same-clock changed wave values and a new coast texture invalidate the actual uniform cache")
		check(surf.diagnostics().geometryBuilds==initial.geometryBuilds and surf.diagnostics().packets==initial.packets,"optimization retains all actual mesh/packet population")
	surf.dispose(); check(surf.get_child_count()==0,"dispose releases all actual waves")
	if has_sampler:
		check(surf.get("_sampler")==null and surf.get("_surface_state").is_empty(),"dispose clears prepared sampling and surface caches")
		check(surf.configure(field) and surf.diagnostics().states==initial.states,"reconfigure starts with the same complete t=0 source output")
		surf.dispose()
	surf.free()
	print("NATURAL_SHORE_HOTPATH assertions=%d failures=%d"%[assertions,failures]); quit(1 if failures else 0)
