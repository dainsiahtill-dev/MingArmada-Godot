extends SceneTree
## Root-operated GPU math probe. No CPU copy replaces the production wave math:
## compute GLSL embeds the actual integration/wave includes and actual material RFs.
## --offline reports only RF approximation; --check-only does not execute this probe.
const World = preload("res://modules/scene_engine/world/world_view.gd")
const Height = preload("res://modules/scene_engine/terrain/height_field.gd")
const Coastal = preload("res://modules/physics_engine/ocean/coastal_wave_field.gd")
const Descriptor = preload("res://modules/contracts/wave_descriptor.gd")
const INCLUDE := "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"
const WAVE_INCLUDE := "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
const MATH_TOLERANCE_METERS := 0.002
const CANONICAL_TOLERANCE_METERS := 0.05
var world: Node3D
var camera: Camera3D
var heights: RefCounted
var coastal: RefCounted
var rf_coastal: RefCounted
var field: Image
var bounds: Vector4
var near_field: Image
var near_bounds: Vector4
var queries := PackedVector4Array()
var rd: RenderingDevice
var owned: Array[RID] = []
var failures := 0
var assertions := 0

func _initialize() -> void: run.call_deferred()
func check(value: bool, message: String) -> void:
	assertions += 1
	if not value: failures += 1; printerr("FAIL: ",message)

func _rf_height(x: float,z: float) -> float:
	return _sample_rf(field,bounds,Vector2(x,z),false)

func _sample_rf(image: Image,area: Vector4,point: Vector2,triangular: bool) -> float:
	var uv := (point-Vector2(area.x,area.y))/Vector2(area.z-area.x,area.w-area.y)
	if uv.x<0 or uv.x>1 or uv.y<0 or uv.y>1: return -20.0
	var pixel := uv*Vector2(image.get_width()-1,image.get_height()-1)
	var ix := mini(floori(pixel.x),image.get_width()-2)
	var iy := mini(floori(pixel.y),image.get_height()-2)
	var f := pixel-Vector2(ix,iy)
	var a := image.get_pixel(ix,iy).r; var b := image.get_pixel(ix+1,iy).r
	var c := image.get_pixel(ix,iy+1).r; var d := image.get_pixel(ix+1,iy+1).r
	if triangular:
		return a+(b-a)*f.x+(c-a)*f.y if f.x+f.y<=1.0 else d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y)
	return lerpf(lerpf(a,b,f.x),lerpf(c,d,f.x),f.y)

func _visible_height(point: Vector2) -> float:
	if near_field:
		var uv := (point-Vector2(near_bounds.x,near_bounds.y))/Vector2(near_bounds.z-near_bounds.x,near_bounds.w-near_bounds.y)
		if uv.x>=0 and uv.x<=1 and uv.y>=0 and uv.y<=1: return _sample_rf(near_field,near_bounds,point,true)
	return _rf_height(point.x,point.y)

func _configure() -> bool:
	var ports: Array = JSON.parse_string(FileAccess.get_file_as_string("res://game/data/mingqi_geography.json"))
	heights=Height.new()
	check(heights.has_method("reference_profiles"),"formal reference island sampler must be source-ready before this probe")
	if failures: return false
	check(heights.configure_ports(ports,true,preload("res://game/scenes/common/reference_geography.gd").options()),"actual formal Mingqi reference geography accepted")
	check(heights.reference_profiles().size()==ports.size(),"every formal island uses its source height profile")
	coastal=Coastal.new(); check(coastal.configure(heights.sample_height),"canonical Coastal field accepted")
	camera=Camera3D.new(); root.add_child(camera); camera.position=Vector3(0,120,160); camera.look_at(Vector3.ZERO); camera.current=true
	world=World.new(); root.add_child(world)
	check(world.configure(heights.sample_height,Descriptor.original_descriptors(),{"camera":camera,"ports":ports,"resolution":16,"chunk_radius":1,"vegetation":false,"island_details":false,"collision":false,"visual_style":1}),"actual formal WorldView accepted")
	world.apply_snapshot({"time":17.25,"focus":Vector2(float(ports[0].islandX),float(ports[0].islandZ))},0.0)
	var material: ShaderMaterial = world.get_ocean().material_override
	check(material.shader.resource_path=="res://modules/scene_engine/ocean/reference_game_water.gdshader","probe reads actual formal integration material")
	var uploaded: Variant=material.get_shader_parameter("wave_components")
	check(uploaded is PackedVector4Array and uploaded.size()==8 and material.get_shader_parameter("wave_count")==5,"actual production upload contains all five configured waves")
	var global_texture: Texture2D=material.get_shader_parameter("shore_height_texture")
	var near_texture: Texture2D=material.get_shader_parameter("reference_near_height_texture")
	check(global_texture!=null and near_texture!=null,"actual world owns both required RF textures")
	if failures: return false
	field=global_texture.get_image()
	bounds=material.get_shader_parameter("shore_bounds")
	near_field=near_texture.get_image()
	near_bounds=material.get_shader_parameter("reference_near_bounds")
	check(field!=null and near_field!=null and not field.is_empty() and not near_field.is_empty(),"RF texture image readback is nonempty")
	if failures: return false
	check(field.get_format()==Image.FORMAT_RF and near_field.get_format()==Image.FORMAT_RF and field.get_width()>1 and field.get_height()>1 and near_field.get_width()>1 and near_field.get_height()>1,"actual images are usable Float32 RF lattices")
	check(material.get_shader_parameter("has_shore_field")==true and material.get_shader_parameter("has_reference_near_field")==true and material.get_shader_parameter("coastal_attenuation")==true,"production flags enable real global attenuation and near triangles")
	if failures: return false
	rf_coastal=Coastal.new(); check(rf_coastal.configure(_rf_height),"RF-backed CPU Coastal uses existing physics implementation")
	for port: Dictionary in ports:
		for angle in 16:
			var heading := TAU*angle/16.0
			for fraction: float in [.6,.72,.8,.88,.96,1.05]:
				var x := float(port.islandX)+cos(heading)*float(port.radius)*fraction
				var z := float(port.islandZ)+sin(heading)*float(port.radius)*.82*fraction
				for seconds: float in [0.0,1.25,17.25,80.0]: queries.append(Vector4(x,z,seconds,0))
	for row in 17:
		for column in 17:
			queries.append(Vector4(lerpf(near_bounds.x,near_bounds.z,(column+.13)/17.0),lerpf(near_bounds.y,near_bounds.w,(row+.37)/17.0),17.25,0))
	for point: Vector2 in [Vector2(bounds.x,bounds.y),Vector2(bounds.z,bounds.w),Vector2(bounds.x-100,bounds.y-100),Vector2(bounds.z+100,bounds.w+100)]:
		queries.append(Vector4(point.x,point.y,17.25,0))
	return failures==0

func _source() -> String:
	var source := FileAccess.get_file_as_string(INCLUDE)
	check(source.count("#include \""+WAVE_INCLUDE+"\"")==1,"production include still binds production configured_wave_height")
	source=source.replace("#include \""+WAVE_INCLUDE+"\"",FileAccess.get_file_as_string(WAVE_INCLUDE))
	var uniforms := RegEx.new(); uniforms.compile("(?m)^\\s*uniform\\s+[^\\n]+;\\s*$")
	source=uniforms.sub(source,"",true)
	return """#version 450
layout(local_size_x=64,local_size_y=1,local_size_z=1) in;
layout(set=0,binding=0,std430) readonly buffer QueryBuffer {vec4 q[];};
layout(set=0,binding=1,std430) writeonly buffer ResultBuffer {vec4 result[];};
layout(set=0,binding=2) uniform sampler2D shore_height_texture;
layout(set=0,binding=3) uniform sampler2D coast_distance_texture;
layout(set=0,binding=4) uniform sampler2D reference_near_height_texture;
layout(set=0,binding=5,std140) uniform ActualMaterialUniforms {
 vec4 wave_components[8]; vec4 shore_bounds; vec4 reference_near_bounds;
 vec4 flags; vec4 control;
};
#define wave_count int(flags.x)
#define has_shore_field (flags.y>0.5)
#define coastal_attenuation (flags.z>0.5)
#define has_coast_distance (flags.w>0.5)
#define has_reference_near_field (control.x>0.5)
#define simulation_time control.y
"""+source+"""
void main() {
 uint i=gl_GlobalInvocationID.x; if(i>=uint(q.length()))return;
 vec2 point=q[i].xy; float seconds=q[i].z;
 result[i]=vec4(reference_game_height(point,seconds),reference_global_height(point),height_at(point),reference_game_normal(point,seconds).y);
}
"""

func _keep(value: RID) -> RID: owned.append(value); return value
func _buffer_uniform(binding: int,value: RID,kind: int) -> RDUniform:
	var uniform := RDUniform.new(); uniform.binding=binding; uniform.uniform_type=kind; uniform.add_id(value); return uniform
func _texture_uniform(binding: int,image: Image,sampler: RID) -> RDUniform:
	var format := RDTextureFormat.new(); format.format=RenderingDevice.DATA_FORMAT_R32_SFLOAT
	format.width=image.get_width(); format.height=image.get_height(); format.texture_type=RenderingDevice.TEXTURE_TYPE_2D
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var texture := _keep(rd.texture_create(format,RDTextureView.new(),[image.get_data()]))
	var uniform := RDUniform.new(); uniform.binding=binding; uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
	uniform.add_id(sampler); uniform.add_id(texture); return uniform

func _gpu(source: String) -> PackedFloat32Array:
	rd=RenderingServer.create_local_rendering_device()
	check(rd!=null,"real RenderingDevice available; dummy/headless result is not GPU proof")
	if rd==null: return PackedFloat32Array()
	var shader_source := RDShaderSource.new(); shader_source.source_compute=source
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	check(spirv.compile_error_compute.is_empty(),"actual production include compiles as compute: "+spirv.compile_error_compute)
	if not spirv.compile_error_compute.is_empty(): return PackedFloat32Array()
	var shader := _keep(rd.shader_create_from_spirv(spirv))
	var inputs := PackedFloat32Array()
	for query: Vector4 in queries: inputs.append_array(PackedFloat32Array([query.x,query.y,query.z,query.w]))
	var output := PackedByteArray(); output.resize(inputs.size()*4)
	var input_buffer := _keep(rd.storage_buffer_create(inputs.size()*4,inputs.to_byte_array()))
	var output_buffer := _keep(rd.storage_buffer_create(output.size(),output))
	var material: ShaderMaterial=world.get_ocean().material_override
	var parameters := PackedFloat32Array()
	for component: Vector4 in material.get_shader_parameter("wave_components"): parameters.append_array(PackedFloat32Array([component.x,component.y,component.z,component.w]))
	parameters.append_array(PackedFloat32Array([bounds.x,bounds.y,bounds.z,bounds.w,near_bounds.x,near_bounds.y,near_bounds.z,near_bounds.w,float(material.get_shader_parameter("wave_count")),1.0 if material.get_shader_parameter("has_shore_field") else 0.0,1.0 if material.get_shader_parameter("coastal_attenuation") else 0.0,1.0 if material.get_shader_parameter("has_coast_distance") else 0.0,1.0 if material.get_shader_parameter("has_reference_near_field") else 0.0,float(material.get_shader_parameter("simulation_time")),0.0,0.0]))
	var parameter_buffer := _keep(rd.uniform_buffer_create(parameters.size()*4,parameters.to_byte_array()))
	var sampler_state := RDSamplerState.new(); sampler_state.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST; sampler_state.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	var sampler := _keep(rd.sampler_create(sampler_state))
	var coast: Image=(material.get_shader_parameter("coast_distance_texture") as Texture2D).get_image()
	var bindings: Array[RDUniform]=[_buffer_uniform(0,input_buffer,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),_buffer_uniform(1,output_buffer,RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER),_texture_uniform(2,field,sampler),_texture_uniform(3,coast,sampler),_texture_uniform(4,near_field,sampler),_buffer_uniform(5,parameter_buffer,RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER)]
	var uniform_set := _keep(rd.uniform_set_create(bindings,shader,0))
	var pipeline := _keep(rd.compute_pipeline_create(shader))
	var list := rd.compute_list_begin(); rd.compute_list_bind_compute_pipeline(list,pipeline); rd.compute_list_bind_uniform_set(list,uniform_set,0)
	rd.compute_list_dispatch(list,int(ceil(float(queries.size())/64.0)),1,1); rd.compute_list_end(); rd.submit(); rd.sync()
	return rd.buffer_get_data(output_buffer).to_float32_array()

func _evaluate(gpu: PackedFloat32Array=PackedFloat32Array()) -> Dictionary:
	var result := {"samples":queries.size(),"gpuExecuted":not gpu.is_empty(),"maxRfGroundApproximationMeters":0.0,"maxRfGroundApproximationInsideMeters":0.0,"outsideGlobalFieldSamples":0,"maxRfWaveApproximationMeters":0.0,"maxGpuVsRfCpuHeightMeters":0.0,"maxGpuVsCanonicalCpuHeightMeters":0.0,"maxGpuGroundFetchErrorMeters":0.0,"maxGpuVisibleTriangleErrorMeters":0.0,"worstRfWavePoint":Vector4.ZERO}
	check(gpu.is_empty() or gpu.size()==queries.size()*4,"complete GPU buffer readback")
	for i: int in queries.size():
		var q: Vector4=queries[i]; var point:=Vector2(q.x,q.y)
		var canonical: float=coastal.sample_height(q.x,q.y,q.z)
		var approximate: float=rf_coastal.sample_height(q.x,q.y,q.z)
		var ground_error := absf(_rf_height(q.x,q.y)-float(heights.sample_height(q.x,q.y)))
		var wave_error := absf(approximate-canonical)
		check(wave_error<=CANONICAL_TOLERANCE_METERS,"sampled actual RF approximation stays below declared 5cm stage bound")
		result.maxRfGroundApproximationMeters=maxf(result.maxRfGroundApproximationMeters,ground_error)
		if q.x<bounds.x or q.x>bounds.z or q.y<bounds.y or q.y>bounds.w: result.outsideGlobalFieldSamples+=1
		else: result.maxRfGroundApproximationInsideMeters=maxf(result.maxRfGroundApproximationInsideMeters,ground_error)
		if wave_error>result.maxRfWaveApproximationMeters: result.maxRfWaveApproximationMeters=wave_error; result.worstRfWavePoint=q
		# S'(depth)<=0.1875/m and sum amplitudes=3.5m, hence 0.65625*m.
		check(wave_error<=ground_error*.65625+1e-10,"canonical/RF attenuation error obeys analytical bound")
		if not gpu.is_empty():
			var measured := float(gpu[i*4]); var math_error := absf(measured-approximate)
			check(is_finite(measured) and math_error<=MATH_TOLERANCE_METERS,"actual GPU wave agrees with RF-backed CPU Coastal")
			check(absf(measured-canonical)<=CANONICAL_TOLERANCE_METERS,"actual GPU vs canonical CPU stays below declared 5cm stage bound")
			check(is_finite(float(gpu[i*4+3])) and float(gpu[i*4+3])>=0.0 and float(gpu[i*4+3])<=1.00001,"GPU normal readback is finite and upward")
			result.maxGpuVsRfCpuHeightMeters=maxf(result.maxGpuVsRfCpuHeightMeters,math_error)
			result.maxGpuVsCanonicalCpuHeightMeters=maxf(result.maxGpuVsCanonicalCpuHeightMeters,absf(measured-canonical))
			var global_fetch_error := absf(float(gpu[i*4+1])-_rf_height(q.x,q.y))
			var visible_fetch_error := absf(float(gpu[i*4+2])-_visible_height(point))
			check(is_finite(global_fetch_error) and global_fetch_error<=MATH_TOLERANCE_METERS,"actual GPU endpoint RF fetch agrees with field values")
			check(is_finite(visible_fetch_error) and visible_fetch_error<=MATH_TOLERANCE_METERS,"actual GPU near triangle fetch agrees with real vertex RF surface")
			result.maxGpuGroundFetchErrorMeters=maxf(result.maxGpuGroundFetchErrorMeters,global_fetch_error)
			result.maxGpuVisibleTriangleErrorMeters=maxf(result.maxGpuVisibleTriangleErrorMeters,visible_fetch_error)
	return result

func run() -> void:
	if not _configure(): _finish(); return
	var source := _source()
	var offline := OS.get_cmdline_user_args().has("--offline")
	var measured := PackedFloat32Array() if offline else _gpu(source)
	var report := _evaluate(measured)
	report.engine=Engine.get_version_info(); report.gpu=RenderingServer.get_video_adapter_name()
	report.sourceSha256={INCLUDE:FileAccess.get_sha256(INCLUDE),WAVE_INCLUDE:FileAccess.get_sha256(WAVE_INCLUDE),"res://modules/scene_engine/ocean/reference_game_water.gdshader":FileAccess.get_sha256("res://modules/scene_engine/ocean/reference_game_water.gdshader"),"probe":FileAccess.get_sha256("res://tools/probe-reference-world-gpu.gd")}
	report.shader=world.get_ocean().material_override.shader.resource_path
	report.referenceProfiles=heights.reference_profiles()
	report.mathToleranceMeters=MATH_TOLERANCE_METERS
	report.canonicalToleranceMeters=CANONICAL_TOLERANCE_METERS
	report.readbackFloatCount=measured.size()
	report.waveCount=world.get_ocean().material_override.get_shader_parameter("wave_count")
	report.rfSizes={"global":[field.get_width(),field.get_height()],"near":[near_field.get_width(),near_field.get_height()]}
	report.scope="Actual integration include + actual material wave uniforms/RF on GPU. Canonical CPU comparison includes measured RF geography approximation. Does not prove final vertex raster interpolation or ocean appearance."
	report.assertions=assertions; report.failures=failures
	print("REFERENCE_WORLD_GPU_MATH_REPORT ",JSON.stringify(report))
	if not offline and not measured.is_empty():
		var path := "res://docs/migration/evidence/reference-world-integration/gpu-math-probe.json"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
		var file := FileAccess.open(path,FileAccess.WRITE)
		check(file!=null,"GPU evidence file opens")
		if file: file.store_string(JSON.stringify(report,"\t")); file.close()
	_finish()

func _finish() -> void:
	if rd:
		for index in range(owned.size()-1,-1,-1):
			if owned[index].is_valid(): rd.free_rid(owned[index])
		owned.clear(); rd.free(); rd=null
	if world: world.dispose(); world.free(); world=null
	if camera: camera.free(); camera=null
	print("REFERENCE_WORLD_GPU_MATH_PROBE assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
