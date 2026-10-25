extends RefCounted
## Optional same-topic visual experiment. No independent clock or simulation.
const Atmosphere=preload("res://modules/scene_engine/fidelity_fx/atmosphere.gd")
const Baseline=preload("res://game/research/fixtures/cloud_billboard_baseline.gd")
const Candidate=preload("res://game/research/demos/architecture_billboard_candidate.gd")
const Adapter=preload("res://game/research/demos/architecture_compiler_adapter.gd")

class ObservedAtmosphere extends Atmosphere:
	var published:Array=[]
	var weather_camera_bytes:=PackedByteArray()
	func _apply_weather(environment:Dictionary,camera:Dictionary,view:Camera3D,reflection:Camera3D)->void:
		# Research-only observation adaptation. Production weather CPU matrices
		# are cached by source time although shader billboards use current view.
		# Restore accepted producer clocks and repaint on camera change so full
		# diagnostic state hashes have no redundant previous-camera dependency.
		var bytes:=var_to_bytes(camera)
		if bytes!=weather_camera_bytes:
			var packets:Array=environment.get("worldClouds",[])
			var weather:Array=get("_weather")
			for index in mini(weather.size(),packets.size()):
				if packets[index].has("controllerState"):weather[index].stateTime=-INF
			weather_camera_bytes=bytes
		super._apply_weather(environment,camera,view,reflection)
	func _update_group(records:Array,meshes:Array,placement:Transform3D,scale_adaptation:float)->void:
		published.append({"states":meshes,"placement":placement,"scale":scale_adaptation})
		super._update_group(records,meshes,placement,scale_adaptation)

var _baseline:RefCounted
var _candidate:RefCounted
var _baseline_parent:Node3D
var _candidate_parent:Node3D
var _variant:="candidate"
var _ready:=false
var _exact:=true
var _baseline_hash:=""
var _candidate_hash:=""
var _source_time:=0.0
var _baseline_impl:RefCounted
var _candidate_impl:RefCounted
var _baseline_adapter:RefCounted
var _candidate_adapter:RefCounted

func configure(parent:Node3D)->Dictionary:
	dispose()
	if not is_instance_valid(parent):return {"ok":false,"reason":"cloud-pair-parent-unavailable"}
	var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/data/fidelity_fx/manifest.json"))
	_baseline_parent=Node3D.new();_baseline_parent.name="BaselineClouds";parent.add_child(_baseline_parent)
	_candidate_parent=Node3D.new();_candidate_parent.name="CandidateClouds";parent.add_child(_candidate_parent)
	_baseline_impl=Baseline.new();_candidate_impl=Candidate.new()
	_baseline_adapter=Adapter.new(_baseline_impl);_candidate_adapter=Adapter.new(_candidate_impl)
	_baseline=ObservedAtmosphere.new();_baseline.set("_render_compiler",_baseline_adapter)
	_candidate=ObservedAtmosphere.new();_candidate.set("_render_compiler",_candidate_adapter)
	if _baseline.get("_render_compiler")!=_baseline_adapter or _candidate.get("_render_compiler")!=_candidate_adapter:
		dispose();return {"ok":false,"reason":"research-compiler-injection-rejected"}
	var options:Dictionary={"crt_seed":1,"cloud_sky_radius":2600.0,"cloud_bounds_layer":true,"fog_placements":[Transform3D(Basis.IDENTITY,Vector3(0,4,0))],"fog_opacity":.035}
	var a:Dictionary=_baseline.configure(_baseline_parent,manifest,options)
	var b:Dictionary=_candidate.configure(_candidate_parent,manifest,options)
	if not a.ok or not b.ok:
		dispose();return {"ok":false,"reason":"paired-source-atmosphere-unavailable"}
	_ready=true;_exact=true;select_variant(_variant)
	return {"ok":true,"ready":true}

func select_variant(value:String)->void:
	if value not in ["baseline","candidate"]:return
	_variant=value
	# Keep the exact same visible nodes/materials/RIDs. The hidden observer
	# runs the opposite calculation; role switches replace CPU delegates only.
	if _baseline_adapter!=null:
		if _baseline_adapter.use_implementation(_baseline_impl if value=="baseline" else _candidate_impl):
			for index in _baseline.get("_cloud_cache").size():_baseline.get("_cloud_cache")[index]={}
	if _candidate_adapter!=null:
		if _candidate_adapter.use_implementation(_candidate_impl if value=="baseline" else _baseline_impl):
			for index in _candidate.get("_cloud_cache").size():_candidate.get("_cloud_cache")[index]={}
	if is_instance_valid(_baseline_parent):_baseline_parent.visible=true
	if is_instance_valid(_candidate_parent):_candidate_parent.visible=false

static func _hash(bytes:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(bytes)
	return context.finish().hex_encode()

func apply_snapshot(snapshot:Dictionary,camera:Camera3D,reflection_camera:Camera3D=null)->void:
	if not _ready:return
	_baseline.published.clear();_candidate.published.clear()
	_baseline.apply_snapshot(snapshot,camera,Vector3.ZERO,reflection_camera)
	_candidate.apply_snapshot(snapshot,camera,Vector3.ZERO,reflection_camera)
	var a:=var_to_bytes(_baseline.published);var b:=var_to_bytes(_candidate.published)
	_exact=_exact and a==b
	_baseline_hash=_hash(a if _variant=="baseline" else b)
	_candidate_hash=_hash(b if _variant=="baseline" else a)
	_source_time=float(snapshot.get("environment",{}).get("acceptedTime",snapshot.get("time",0.0)))

func inspection_snapshot()->Dictionary:
	var carrier:RefCounted=_baseline.get("_render_compiler") if _baseline!=null else null
	var observer:RefCounted=_candidate.get("_render_compiler") if _candidate!=null else null
	var carrier_path:String=carrier.implementation().get_script().resource_path if carrier!=null else ""
	var observer_path:String=observer.implementation().get_script().resource_path if observer!=null else ""
	var paths:Dictionary={"baseline":carrier_path if _variant=="baseline" else observer_path,"candidate":observer_path if _variant=="baseline" else carrier_path}
	return {"enabled":true,"ready":_ready,"variant":_variant,"exact":_exact,"baselineHash":_baseline_hash,"candidateHash":_candidate_hash,"sourceTime":_source_time,"compilerPaths":paths,"visibleCarrierId":_baseline_parent.get_instance_id() if is_instance_valid(_baseline_parent) else 0,"visibleCarrierCount":int(is_instance_valid(_baseline_parent) and _baseline_parent.visible)+int(is_instance_valid(_candidate_parent) and _candidate_parent.visible),"resources":{"renderers":int(_baseline!=null)+int(_candidate!=null),"parents":int(is_instance_valid(_baseline_parent))+int(is_instance_valid(_candidate_parent))},"hashContract":"SHA256(var_to_bytes(all delivered cloud/fog/weather states, placement and scale)); fixed visible carrier, opposite hidden observer; identical camera and accepted packet; diagnostic overhead outside CPU batch scope","observationAdaptation":"Research only: camera changes repaint weather CPU billboard cache from accepted producer controllerState. Original production cache behavior untouched; this is not proof of an existing GPU visual defect."}

func dispose()->void:
	_ready=false
	if _baseline!=null:_baseline.dispose()
	if _candidate!=null:_candidate.dispose()
	_baseline=null;_candidate=null
	_baseline_impl=null;_candidate_impl=null;_baseline_adapter=null;_candidate_adapter=null
	if is_instance_valid(_baseline_parent):_baseline_parent.free()
	if is_instance_valid(_candidate_parent):_candidate_parent.free()
	_baseline_parent=null;_candidate_parent=null
	_baseline_hash="";_candidate_hash="";_source_time=0.0;_exact=true
