extends RefCounted
## Exact source expression order; batch only the final binary32 stores.
## Array() detaches each returned value from the temporary typed storage.
static func multiply(a: Array, b: Array) -> Array:
	return Array(PackedFloat32Array([
		float(a[0])*float(b[0])+float(a[1])*float(b[3])+float(a[2])*float(b[6]),
		float(a[0])*float(b[1])+float(a[1])*float(b[4])+float(a[2])*float(b[7]),
		float(a[0])*float(b[2])+float(a[1])*float(b[5])+float(a[2])*float(b[8]),
		float(a[3])*float(b[0])+float(a[4])*float(b[3])+float(a[5])*float(b[6]),
		float(a[3])*float(b[1])+float(a[4])*float(b[4])+float(a[5])*float(b[7]),
		float(a[3])*float(b[2])+float(a[4])*float(b[5])+float(a[5])*float(b[8]),
		float(a[6])*float(b[0])+float(a[7])*float(b[3])+float(a[8])*float(b[6]),
		float(a[6])*float(b[1])+float(a[7])*float(b[4])+float(a[8])*float(b[7]),
		float(a[6])*float(b[2])+float(a[7])*float(b[5])+float(a[8])*float(b[8])]))

static func transform(matrix: Array, vector: Array) -> Array:
	return Array(PackedFloat32Array([
		float(matrix[0])*float(vector[0])+float(matrix[1])*float(vector[1])+float(matrix[2])*float(vector[2]),
		float(matrix[3])*float(vector[0])+float(matrix[4])*float(vector[1])+float(matrix[5])*float(vector[2]),
		float(matrix[6])*float(vector[0])+float(matrix[7])*float(vector[1])+float(matrix[8])*float(vector[2])]))

static func transpose_transform(matrix: Array, vector: Array) -> Array:
	return Array(PackedFloat32Array([
		float(matrix[6])*float(vector[2])+float(matrix[3])*float(vector[1])+float(matrix[0])*float(vector[0]),
		float(matrix[7])*float(vector[2])+float(matrix[4])*float(vector[1])+float(matrix[1])*float(vector[0]),
		float(matrix[8])*float(vector[2])+float(matrix[5])*float(vector[1])+float(matrix[2])*float(vector[0])]))
