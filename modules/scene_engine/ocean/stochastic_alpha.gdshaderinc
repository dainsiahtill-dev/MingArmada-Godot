#ifndef REFERENCE_STOCHASTIC_ALPHA_INCLUDED
#define REFERENCE_STOCHASTIC_ALPHA_INCLUDED
// Blend three translated/rotated readings of the ACTUAL source alpha bitmap.
// Vertex seeds live in advected world coordinates. No time/camera hash, texture
// replacement, hard cell boundary, or derivative through a random offset.
uint reference_alpha_hash(ivec2 vertex, uint salt) {
	uint value = uint(vertex.x) * 1597334677u ^ uint(vertex.y) * 3812015801u ^ salt;
	value = (value ^ (value >> 16u)) * 2246822519u;
	value = (value ^ (value >> 13u)) * 3266489917u;
	return value ^ (value >> 16u);
}

float reference_alpha_vertex(sampler2D source, vec2 uv, ivec2 vertex, uint salt, float angle_range, vec2 dx, vec2 dy) {
	uint bits = reference_alpha_hash(vertex, salt);
	float angle = (float(bits & 65535u) / 65535.0 * 2.0 - 1.0) * angle_range;
	vec2 offset = vec2(float((bits >> 8u) & 65535u), float((bits >> 16u) & 65535u)) / 65535.0;
	float c = cos(angle), s = sin(angle);
	mat2 rotation = mat2(vec2(c, s), vec2(-s, c));
	return textureGrad(source, rotation * (uv - vec2(vertex)) + offset, rotation * dx, rotation * dy).a;
}

float reference_stochastic_alpha(sampler2D source, vec2 uv, uint salt, float angle_range) {
	// Compute gradients before floor/hash; a cell crossing must not select an
	// unrelated blurry mip or generate a sparkle when the camera moves.
	vec2 dx = dFdx(uv), dy = dFdy(uv);
	ivec2 cell = ivec2(floor(uv));
	vec2 local = fract(uv);
	ivec2 a, b, c;
	vec3 weights;
	if (local.x + local.y <= 1.0) {
		a = cell; b = cell + ivec2(0, 1); c = cell + ivec2(1, 0);
		weights = vec3(1.0 - local.x - local.y, local.y, local.x);
	} else {
		a = cell + ivec2(1, 1); b = cell + ivec2(1, 0); c = cell + ivec2(0, 1);
		weights = vec3(local.x + local.y - 1.0, 1.0 - local.y, 1.0 - local.x);
	}
	weights = weights * weights * (vec3(3.0) - 2.0 * weights);
	weights /= weights.x + weights.y + weights.z;
	return reference_alpha_vertex(source, uv, a, salt, angle_range, dx, dy) * weights.x
		+ reference_alpha_vertex(source, uv, b, salt, angle_range, dx, dy) * weights.y
		+ reference_alpha_vertex(source, uv, c, salt, angle_range, dx, dy) * weights.z;
}
#endif
