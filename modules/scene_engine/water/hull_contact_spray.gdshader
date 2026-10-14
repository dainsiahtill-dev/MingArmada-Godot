shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;
#include "res://modules/scene_engine/water/hull_contact_depth.gdshaderinc"
// A small elongated water droplet, not a large photographed froth billboard.
void fragment() {
	vec2 p=(UV-0.5)*2.0;
	float radius=length(p*vec2(1.05,0.80));
	float edge=1.0-smoothstep(0.40,1.0,radius);
	float glint=1.0-smoothstep(0.0,0.55,length(p-vec2(-0.22,-0.20)));
	ALBEDO=mix(vec3(0.47,0.74,0.83),vec3(0.93,0.99,1.0),glint);
	ALPHA=edge*COLOR.a*0.62*contact_depth_fade(SCREEN_UV,VERTEX.z,INV_PROJECTION_MATRIX,0.06);
}
