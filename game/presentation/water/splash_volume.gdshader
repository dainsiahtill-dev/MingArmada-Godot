shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float opacity : hint_range(0.0,1.0) = 0.7;
varying float vertex_alpha;
void vertex() { vertex_alpha = COLOR.a; }
void fragment() {
	// Original splash/streak/froth RGB is nearly constant. Alpha is the mask.
	float detail = texture(foam_texture,UV).a;
	float strands = 0.72+0.28*sin(UV.x*83.0+UV.y*7.0);
	ALBEDO = vec3(0.83,0.96,1.0);
	ALPHA = opacity * vertex_alpha * strands * smoothstep(0.008,0.45,detail);
}
