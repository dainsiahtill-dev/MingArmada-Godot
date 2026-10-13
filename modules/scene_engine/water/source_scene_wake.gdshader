shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;
#include "res://modules/scene_engine/fidelity_fx/particle_sampling.gdshaderinc"
// Target rendering adapter: original coarse mips contain nonzero edge alpha,
// and the original last drawn row is still opaque enough to reveal a hard cap.
// Keep source texture, RGB, row alpha and body opacity; feather only boundaries.
// The formal sea writes depth in the transparent pass. Its projected triangles
// differ from this broad source ribbon, so fixed-function depth cuts the foam.
// Test the opaque-pass depth copy instead, via fidelity_particle_depth_fade.
// Surface supplies a positive contact distance: ships/terrain still occlude us.
uniform float alpha_threshold = -1.0;
uniform float tail_v = 0.0;
uniform float tail_span_v = 0.0;
void fragment() {
	vec4 pixel = fidelity_particle_sample(UV) * COLOR * display_tint;
	if (alpha_threshold >= 0.0 && pixel.a <= alpha_threshold) discard;
	float edges = smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x));
	float terminal = abs(tail_span_v) > 0.000001 ? smoothstep(0.0, 1.0, (UV.y - tail_v) / tail_span_v) : 1.0;
	ALBEDO = pixel.rgb;
	EMISSION = pixel.rgb * emission_gain;
	ALPHA = pixel.a * edges * terminal * fidelity_particle_depth_fade(SCREEN_UV, VERTEX.z, INV_PROJECTION_MATRIX);
}
