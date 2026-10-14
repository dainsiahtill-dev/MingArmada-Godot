extends "res://tools/shadow_candidate_probe.gd"
## One factor: an absent reverse-Z receiver must not receive a stencil shadow.
class ReceiverBackend extends "res://modules/scene_engine/fidelity_fx/source_shadow_rd.gd":
	var compile_matches:=0
	var vertex_hash:=""
	var fragment_hash:=""
	var mesh_calls:=0
	func _compile(vertex:String,fragment:String)->RID:
		if fragment==FRAGMENT_SOURCE:
			compile_matches+=1
			fragment=fragment.replace("if(gl_FragCoord.z < receiver) discard;","if(receiver <= 0.0 || gl_FragCoord.z < receiver) discard;")
			vertex_hash=vertex.sha256_text();fragment_hash=fragment.sha256_text()
		return super._compile(vertex,fragment)
	func _mesh_record(volume:Dictionary,retained:Dictionary)->Dictionary:
		mesh_calls+=1;return super._mesh_record(volume,retained)
	func candidate_diagnostics()->Dictionary:return {"mode":"reject-empty-receiver","compileMatches":compile_matches,"vertexSHA256":vertex_hash,"fragmentSHA256":fragment_hash,"meshCalls":mesh_calls}
func _initialize()->void:
	output="res://docs/research/evidence/shadow-edges/receiver-candidate"
	super._initialize()
func _make_backend()->RefCounted:return ReceiverBackend.new()
