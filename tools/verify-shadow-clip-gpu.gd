extends "res://tools/shadow_candidate_probe.gd"
## Independent GPU candidate only: the production backend shader is untouched.
## Positive per-vertex homogeneous rescaling represents the same finite point.
class NormalizedClipBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	var compile_matches:=0
	var vertex_hash:=""
	var fragment_hash:=""
	var mesh_calls:=0
	func _compile(vertex:String,fragment:String)->RID:
		if vertex==VERTEX_SOURCE:
			compile_matches+=1
			vertex=vertex.replace("gl_Position=params.mvp*vec4(position,1.0);","float scale=max(1.0,max(abs(position.x),max(abs(position.y),abs(position.z)))); gl_Position=params.mvp*vec4(position/scale,1.0/scale);")
			vertex_hash=vertex.sha256_text();fragment_hash=fragment.sha256_text()
		return super._compile(vertex,fragment)
	func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
		mesh_calls+=1;return super._mesh_record(volume,retained)
	func candidate_diagnostics()->Dictionary:return {"mode":"normalized-clip","compileMatches":compile_matches,"vertexSHA256":vertex_hash,"fragmentSHA256":fragment_hash,"meshCalls":mesh_calls}
func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/normalized-clip-candidate"
	super._initialize()
func _make_backend()->RefCounted:return NormalizedClipBackend.new()
