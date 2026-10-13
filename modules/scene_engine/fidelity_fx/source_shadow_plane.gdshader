shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_always, cull_disabled;
// Original NiAlphaProperty 4845, GREATER 0; inherited Z flags 3.
uniform sampler2D source_texture : source_color, filter_linear_mipmap, repeat_enable;
void fragment() {
	vec4 sample_color=texture(source_texture,UV);
	if(sample_color.a<=0.0) discard;
	ALBEDO=sample_color.rgb;
	ALPHA=sample_color.a;
}
