extends "res://modules/scene_engine/fidelity_fx/cloud_render_compiler.gd"
## Independent candidate compiler injected only into the weather laboratory.
const TrialKernel = preload("res://modules/scene_engine/fidelity_fx/cloud_transform_kernel.gd")
var batched := true
func _multiply_matrix(a: Array, b: Array) -> Array:
	if batched: return TrialKernel.multiply(a, b)
	var result: Array = []
	for i in 9:
		var row := int(i/3); var col := i%3
		result.append(_f32(float(a[row*3])*float(b[col])+float(a[row*3+1])*float(b[3+col])+float(a[row*3+2])*float(b[6+col])))
	return result
func _transform_vector(matrix: Array, vector: Array) -> Array:
	if batched: return TrialKernel.transform(matrix, vector)
	var result: Array = []
	for row in 3: result.append(_f32(float(matrix[row*3])*float(vector[0])+float(matrix[row*3+1])*float(vector[1])+float(matrix[row*3+2])*float(vector[2])))
	return result
func _transform_transpose(matrix: Array, vector: Array) -> Array:
	if batched: return TrialKernel.transpose_transform(matrix, vector)
	var result: Array = []
	for col in 3: result.append(_f32(float(matrix[6+col])*float(vector[2])+float(matrix[3+col])*float(vector[1])+float(matrix[col])*float(vector[0])))
	return result
