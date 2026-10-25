extends "res://tests/test_cloud_billboard_reuse.gd"
## Production contract: exact output/ownership and measured duplicate work.
class ProductionProbe extends "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd":
	var transpose_calls:=0
	var transpose_rotations:Array=[]
	func _transform_transpose(matrix:Array,vector:Array)->Array:
		transpose_calls+=1
		transpose_rotations.append(var_to_bytes(matrix))
		return super._transform_transpose(matrix,vector)
	func reset_probe()->void:
		transpose_calls=0;transpose_rotations.clear()

func make_candidate()->RefCounted:return ProductionProbe.new()

func finish()->void:
	print("CLOUD_BILLBOARD_PRODUCTION_WORK baselineTransposeCalls=",baseline_ring_calls," candidateTransposeCalls=",candidate_ring_calls)
	print("CLOUD_BILLBOARD_PRODUCTION_TESTS assertions=",assertions," failures=",failures)
	quit(1 if failures else 0)
