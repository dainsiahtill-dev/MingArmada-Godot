shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

uniform sampler2D original_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 original_material = vec4(1.0);
uniform float display_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float original_alpha_threshold = -1.0;
uniform mat3 original_uv_matrix = mat3(1.0);
uniform bool source_wrap_u = true;
uniform bool source_wrap_v = true;
uniform vec2 source_half_texel = vec2(0.0);

void fragment() {
	vec2 original_uv = (original_uv_matrix * vec3(UV, 1.0)).xy;
	// The sampler retains trilinear original mips. TexDesc axes clamp separately.
	if (!source_wrap_u) original_uv.x = clamp(original_uv.x, source_half_texel.x, 1.0 - source_half_texel.x);
	if (!source_wrap_v) original_uv.y = clamp(original_uv.y, source_half_texel.y, 1.0 - source_half_texel.y);
	vec4 sample_color = texture(original_texture, original_uv) * original_material;
	if (sample_color.a <= original_alpha_threshold) discard;
	ALBEDO = sample_color.rgb;
	// Target weather strength follows the source alpha test, preserving its
	// authored cutoff even when clear-weather ground fog is very faint.
	ALPHA = sample_color.a * display_opacity;
}
