#ifndef REFERENCE_MACRO_WAVE_OPTICS_INCLUDED
#define REFERENCE_MACRO_WAVE_OPTICS_INCLUDED
// Fragment optics only. Physical waves and projected vertex positions retain
// the authoritative profile. Continuous phase derivatives detect unresolved
// waves even when adjacent cosine samples alias to the same normal.
float reference_macro_wave_visibility(float phase_footprint) {
	// Keep well-resolved waves unchanged; gently merge compressed wave detail
	// into the broad sea response before it reaches the two-pixel Nyquist limit.
	return 1.0 - smoothstep(6.28318530718 / 24.0, 6.28318530718 / 4.0, max(phase_footprint, 0.0));
}

// Display contrast adaptation, separate from frequency filtering. The original
// sky/Fresnel response magnifies regular long-wave slopes at grazing angles.
// Preserve nearby water even for a low ship camera, and preserve steep views.
float reference_macro_grazing_visibility(float view_elevation, float view_distance) {
	return 1.0 - smoothstep(180.0, 800.0, max(view_distance, 0.0)) * (1.0 - smoothstep(0.05, 0.40, abs(view_elevation)));
}

vec3 reference_optical_wave_normal(vec2 point, float seconds, vec2 point_dx, vec2 point_dy) {
	float wave = 0.0;
	vec2 gradient = vec2(0.0);
	for (int i = 0; i < 8; i++) {
		if (i < wave_count) {
			vec4 w = wave_components[i];
			float phase = dot(point, w.yz) + w.w * seconds;
			float phase_footprint = max(abs(dot(point_dx, w.yz)), abs(dot(point_dy, w.yz)));
			float visible = reference_macro_wave_visibility(phase_footprint);
			wave += w.x * sin(phase) * visible;
			gradient += w.x * cos(phase) * w.yz * visible;
		}
	}
	// Preserve the same shore attenuation and its product-rule derivative.
	// At close views every visibility is exactly one, reproducing the current
	// per-fragment normal rather than returning to coarse interpolated normals.
	if (coastal_attenuation && has_shore_field) {
		vec2 uv = (point - shore_bounds.xy) / (shore_bounds.zw - shore_bounds.xy);
		if (reference_inside(uv)) {
			float depth = -reference_global_height(point);
			float t = clamp(depth / 8.0, 0.0, 1.0);
			float scale = t * t * (3.0 - 2.0 * t);
			float derivative = 6.0 * t * (1.0 - t) / 8.0;
			vec2 ground_gradient = vec2(reference_global_height(point + vec2(.5,0)) - reference_global_height(point - vec2(.5,0)), reference_global_height(point + vec2(0,.5)) - reference_global_height(point - vec2(0,.5)));
			gradient = gradient * scale - wave * derivative * ground_gradient;
		}
	}
	return normalize(vec3(-gradient.x, 1.0, -gradient.y));
}
#endif
