shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix;
#include "res://modules/scene_engine/water/hull_contact_depth.gdshaderinc"
// UV.x is real distance from bow toward stern. Advection uses integrated
// travel distance, so stopped boats don't keep pumping a fast scrolling sheet.
uniform float flow_distance=0.0;
uniform float visual_time=0.0;
uniform float strength=0.0;
uniform float side_phase=0.0;
uniform float impact_strength=0.0;
uniform float turn_bias=0.0;
float foam_hash(vec2 p) {
	vec3 q=fract(vec3(p.xyx)*0.1031);
	q+=dot(q,q.yzx+33.33);
	return fract((q.x+q.y)*q.z);
}
float foam_noise(vec2 p) {
	vec2 cell=floor(p), f=fract(p);
	f=f*f*(3.0-2.0*f);
	return mix(mix(foam_hash(cell),foam_hash(cell+vec2(1,0)),f.x),mix(foam_hash(cell+vec2(0,1)),foam_hash(cell+vec2(1,1)),f.x),f.y);
}
float foam_cloud(vec2 p) {
	return 0.57*foam_noise(p)+0.28*foam_noise(p*2.03+vec2(8.1,3.4))+0.15*foam_noise(p*4.11+vec2(2.7,9.2));
}
void fragment() {
	vec2 moving=vec2((UV.x-flow_distance)*1.6,UV.y*3.8+side_phase);
	float turbulence=foam_cloud(moving);
	float fine=foam_noise(moving*8.0+vec2(0.0,visual_time*0.23));
	float cross_fade=smoothstep(0.015,0.18,UV.y)*(1.0-smoothstep(0.58,1.0,UV.y));
	float broken=smoothstep(0.27,0.66,turbulence);
	float stream_center=0.24+0.1*foam_noise(vec2(moving.x*0.7,side_phase));
	float stream=1.0-smoothstep(0.025,0.13,abs(UV.y-stream_center));
	float filament_center=0.43+0.06*foam_noise(vec2(moving.x*1.1,side_phase+3.2));
	float filament=(1.0-smoothstep(0.012,0.06,abs(UV.y-filament_center)))*smoothstep(0.36,0.64,fine);
	float entry=impact_strength*exp(-pow((UV.x-0.8)/1.1,2.0));
	float foam=(broken*0.63+stream*0.26+filament*0.11)*(0.57+fine*0.43)*(1.0+entry*0.3);
	ALBEDO=mix(vec3(0.60,0.80,0.86),vec3(0.88,0.96,0.98),fine);
	ALPHA=clamp(foam*cross_fade*COLOR.a*strength*(1.0+turn_bias),0.0,0.74)*contact_depth_fade(SCREEN_UV,VERTEX.z,INV_PROJECTION_MATRIX,0.05);
}
