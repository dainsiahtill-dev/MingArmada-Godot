#ifndef FIDELITY_PARTICLE_SAMPLING
#define FIDELITY_PARTICLE_SAMPLING
// Native CC/CW/WC/WW address modes, original filter mode 2.
// Separate hardware samplers preserve clamp edges at EVERY original mip;
// clamping only UV to base-level half texels would wrap coarse mip borders.
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D source_texture_repeat : source_color, filter_linear_mipmap, repeat_enable;
uniform bool source_repeat = false;
uniform int source_clamp_mode = 0;
uniform int source_mip_count = 1;
uniform vec4 display_tint : source_color = vec4(1.0);
uniform float emission_gain = 0.0;
uniform float soft_depth_distance = 0.0;
uniform sampler2D particle_scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
vec3 fidelity_particle_wrap_weights(float uv, float extent) {
	float position = fract(uv) * extent - 0.5;
	float first = floor(position);
	return vec3(mod(first + extent, extent), mod(first + 1.0 + extent, extent), position - first);
}
vec4 fidelity_particle_mixed_mip(vec2 source_uv, float level, bool wrap_u) {
	vec2 dimensions = vec2(textureSize(source_texture, int(level)));
	float extent = wrap_u ? dimensions.x : dimensions.y;
	vec3 neighbours = fidelity_particle_wrap_weights(wrap_u ? source_uv.x : source_uv.y, extent);
	vec2 a = source_uv;
	vec2 b = source_uv;
	if (wrap_u) { a.x = (neighbours.x + 0.5) / extent; b.x = (neighbours.y + 0.5) / extent; }
	else { a.y = (neighbours.x + 0.5) / extent; b.y = (neighbours.y + 0.5) / extent; }
	// The other axis retains hardware clamp-to-edge at this exact mip. These
	// samples are wrapped-axis texel centres, so their hardware blend is only
	// along the clamped axis; the original wrapped-axis blend is explicit.
	return mix(textureLod(source_texture, a, level), textureLod(source_texture, b, level), neighbours.z);
}
vec4 fidelity_particle_sample(vec2 source_uv) {
	if (source_clamp_mode == 0 || source_clamp_mode == 3) {
		return source_repeat ? texture(source_texture_repeat, source_uv) : texture(source_texture, source_uv);
	}
	vec2 dimensions = vec2(textureSize(source_texture, 0));
	vec2 dx = dFdx(source_uv) * dimensions;
	vec2 dy = dFdy(source_uv) * dimensions;
	float last_level = float(source_mip_count - 1);
	float level = clamp(0.5 * log2(max(max(dot(dx, dx), dot(dy, dy)), 0.00000001)), 0.0, last_level);
	float low = floor(level);
	float high = min(low + 1.0, last_level);
	bool wrap_u = source_clamp_mode == 2;
	return mix(fidelity_particle_mixed_mip(source_uv, low, wrap_u), fidelity_particle_mixed_mip(source_uv, high, wrap_u), level - low);
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
