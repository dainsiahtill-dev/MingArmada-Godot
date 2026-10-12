shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
#include "res://modules/scene_engine/fidelity_fx/particle_sampling.gdshaderinc"
uniform float alpha_threshold = -1.0;
void fragment() {
	vec4 pixel = fidelity_particle_sample(UV) * COLOR * display_tint;
	if (alpha_threshold >= 0.0 && pixel.a <= alpha_threshold) discard;
	ALBEDO = pixel.rgb;
	EMISSION = pixel.rgb * emission_gain;
	ALPHA = pixel.a * fidelity_particle_depth_fade(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX);
}
