#ifndef REFERENCE_SURFACE_DETAIL_LOD_INCLUDED
#define REFERENCE_SURFACE_DETAIL_LOD_INCLUDED
// Fragment-only, image-space filtering. A feature's pixel span determines its
// visibility; camera distance cannot remove a resolved near-water ripple.
uniform float surface_ripple_light_strength = 0.4;

float reference_surface_band_visibility(float texel_footprint, float feature_width) {
	return 1.0 - smoothstep(feature_width * 0.5, feature_width * 2.0, max(texel_footprint, 0.0));
}

float reference_surface_ripple_light(float normal_light, float flat_light, float strength) {
	return clamp(1.0 + (normal_light - flat_light) * strength, 0.84, 1.16);
}

float reference_surface_specular_power(float normal_variance, float original_power) {
	return original_power / (1.0 + original_power * max(normal_variance, 0.0));
}

float reference_surface_texture_footprint(sampler2D source, vec2 uv) {
	vec2 size = vec2(textureSize(source, 0));
	return max(length(dFdx(uv) * size), length(dFdy(uv) * size));
}

float reference_surface_alpha_visibility(sampler2D source, vec2 uv, float feature_width) {
	return reference_surface_band_visibility(reference_surface_texture_footprint(source, uv), feature_width);
}

vec2 reference_surface_normal_band(sampler2D source, vec2 uv, float feature_width) {
	vec2 dx = dFdx(uv), dy = dFdy(uv);
	vec2 size = vec2(textureSize(source, 0));
	float footprint = max(length(dx * size), length(dy * size));
	// Gradients belong to the continuous advected UV, never a random tile ID.
	vec2 slope = textureGrad(source, uv, dx, dy).rg * 2.0 - 1.0;
	return slope * reference_surface_band_visibility(footprint, feature_width);
}
#endif
