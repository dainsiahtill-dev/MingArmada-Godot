shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix, fog_disabled;
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float alpha_threshold = -1.0;
void fragment() {
	vec4 pixel = texture(source_texture, UV) * COLOR;
	if (alpha_threshold >= 0.0 && pixel.a <= alpha_threshold) discard;
	ALBEDO = pixel.rgb;
	ALPHA = pixel.a;
}
