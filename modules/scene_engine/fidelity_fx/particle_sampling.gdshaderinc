#ifndef FIDELITY_PARTICLE_SAMPLING
#define FIDELITY_PARTICLE_SAMPLING
// Current completed assets use native CC (0) or WW (3), filter mode 2.
// Separate hardware samplers preserve clamp edges at EVERY original mip;
// clamping only UV to base-level half texels would wrap coarse mip borders.
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_texture_repeat : source_color, filter_linear_mipmap, repeat_enable;
uniform bool source_repeat = false;
uniform vec4 display_tint : source_color = vec4(1.0);
uniform float emission_gain = 0.0;
uniform float soft_depth_distance = 0.0;
uniform sampler2D particle_scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
vec4 fidelity_particle_sample(vec2 source_uv) {
	return source_repeat ? texture(source_texture_repeat, source_uv) : texture(source_texture, source_uv);
}
float fidelity_particle_depth_fade(vec2 screen_uv, float particle_view_z, mat4 inverse_projection) {
	if (soft_depth_distance <= 0.0) return 1.0;
	float depth = texture(particle_scene_depth, screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth * 2.0 - 1.0);
#else
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth);
#endif
	vec4 scene_view = inverse_projection * vec4(ndc, 1.0);
	if (abs(scene_view.w) < 0.00001) return 1.0;
	float gap = -scene_view.z / scene_view.w + particle_view_z;
	return smoothstep(0.0, soft_depth_distance, gap);
}
#endif
