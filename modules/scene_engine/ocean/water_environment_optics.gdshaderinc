#ifndef REFERENCE_WATER_ENVIRONMENT_OPTICS_INCLUDED
#define REFERENCE_WATER_ENVIRONMENT_OPTICS_INCLUDED
// Game presentation adapter for a rough, blue sea. The complete advected
// normals still light the water body, refract nearby objects and make glints.
// A finer ripple cannot turn that entire pixel into an ideal white sky mirror.
// This is not an original Pirates shader or a physical wave-profile change.
uniform bool water_legacy_optics = false;
uniform float water_environment_ripple_gain : hint_range(0.0,1.0) = 0.16;
uniform float water_environment_horizon_weight : hint_range(0.02,1.0) = 0.52;

vec3 reference_water_environment_normal(vec3 optical_macro_normal, vec2 ripple_slopes, float detail_gain) {
	return normalize(optical_macro_normal + vec3(ripple_slopes.x,0.0,ripple_slopes.y) * clamp(detail_gain,0.0,1.0));
}

// Schlick's angular shape with an explicit rough-sea display envelope. The
// real same-world planar reflection remains sampled; normal incidence keeps
// its 2% response. Full mirror tuning (1) gives the previous Schlick limit.
float reference_water_environment_fresnel(float normal_view, float horizon_weight) {
	float incidence = clamp(normal_view,0.0,1.0);
	float peak = clamp(horizon_weight,0.02,1.0);
	return 0.02 + (peak-0.02) * pow(1.0-incidence,5.0);
}
#endif
