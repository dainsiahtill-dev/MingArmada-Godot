shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;
#include "res://modules/scene_engine/fidelity_fx/particle_sampling.gdshaderinc"
// Target presentation: preserve the authored UV/RGBA, add metre-scale flowing
// detail from the SAME source alpha texture so compressed strips do not become
// a continuous bright outline. Use opaque depth, as with the scene wake overlay.
uniform float alpha_threshold = -1.0;
uniform mat4 hull_world_to_local;
uniform float froth_visual_time = 0.0;
uniform float froth_flow_speed = 1.5;
varying vec3 froth_world_position;
void vertex() {
	froth_world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
}
void fragment() {
	vec4 pixel=fidelity_particle_sample(UV)*COLOR*display_tint;
	if (alpha_threshold>=0.0 && pixel.a<=alpha_threshold) discard;
	vec3 hull=(hull_world_to_local*vec4(froth_world_position,1.0)).xyz;
	vec2 detail_uv=hull.xz*vec2(0.45,0.30)+froth_visual_time*vec2(0.07,0.30*froth_flow_speed);
	float detail=fidelity_particle_sample(detail_uv).a;
	float breakup=mix(0.06,1.0,smoothstep(0.28,0.72,detail));
	ALBEDO=pixel.rgb;
	EMISSION=pixel.rgb*emission_gain;
	ALPHA=pixel.a*breakup*fidelity_particle_depth_fade(SCREEN_UV,VERTEX.z,INV_PROJECTION_MATRIX);
}
