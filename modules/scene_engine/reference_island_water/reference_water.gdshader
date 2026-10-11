shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_always;
#include "res://modules/scene_engine/reference_island_water/source_common.gdshaderinc"

uniform vec4 u_waves[4];
uniform vec4 u_speeds = vec4(1.4,1.8,2.2,2.8);
uniform float u_strength = 1.0;
uniform sampler2D u_scene : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D u_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D u_reflection : repeat_disable, filter_linear;
uniform sampler2D u_height : repeat_disable, filter_nearest;
uniform mat4 u_reflection_vp;
uniform float u_extent = 160.0;
uniform float u_terrain_resolution = 160.0;
uniform float u_foam_width = 1.5;
uniform bool u_use_reflection = true;
uniform bool u_foam = true;
varying vec3 v_world;
varying vec3 v_normal;

vec3 source_texel(vec3 linear_color) {
	return clamp(reference_to_display(linear_color),vec3(0.0),vec3(1.0));
}
vec3 sample_source_scene(vec2 uv) {
	// WebGL RGBA8 LINEAR filters source display RGB. Godot stores HDR linear
	// light, so convert each texel before the same bilinear interpolation.
	// Values are never rounded after filtering.
	ivec2 size=textureSize(u_scene,0);
	vec2 pixel=uv*vec2(size)-.5;
	ivec2 i=ivec2(floor(pixel));vec2 f=fract(pixel);
	vec3 a=source_texel(texelFetch(u_scene,clamp(i,ivec2(0),size-ivec2(1)),0).rgb);
	vec3 b=source_texel(texelFetch(u_scene,clamp(i+ivec2(1,0),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 c=source_texel(texelFetch(u_scene,clamp(i+ivec2(0,1),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 d=source_texel(texelFetch(u_scene,clamp(i+ivec2(1),ivec2(0),size-ivec2(1)),0).rgb);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
vec3 sample_source_reflection(vec2 uv) {
	// Separate entry point is required by Godot for samplers with different hints.
	ivec2 size=textureSize(u_reflection,0);
	vec2 pixel=uv*vec2(size)-.5;
	ivec2 i=ivec2(floor(pixel));vec2 f=fract(pixel);
	vec3 a=source_texel(texelFetch(u_reflection,clamp(i,ivec2(0),size-ivec2(1)),0).rgb);
	vec3 b=source_texel(texelFetch(u_reflection,clamp(i+ivec2(1,0),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 c=source_texel(texelFetch(u_reflection,clamp(i+ivec2(0,1),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 d=source_texel(texelFetch(u_reflection,clamp(i+ivec2(1),ivec2(0),size-ivec2(1)),0).rgb);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
void wave_filtered(vec2 base,float footprint,out vec3 pos,out vec3 normal) {
	pos=vec3(base.x,u_tide,base.y);vec3 dx=vec3(1,0,0),dz=vec3(0,0,1);
	for(int i=0;i<4;i++) {
		vec2 d=u_waves[i].xy;float k=u_waves[i].w,len=6.28318530718/k;
		float wave_filter=1.0-smoothstep(len*.25,len*.5,footprint),A=u_waves[i].z*u_strength*wave_filter;
		float theta=k*dot(d,base)-u_speeds[i]*u_time,s=sin(theta),c=cos(theta),q=.42;
		pos+=vec3(q*A*d.x*c,A*s,q*A*d.y*c);
		dx+=vec3(-q*A*k*d.x*d.x*s,A*k*d.x*c,-q*A*k*d.x*d.y*s);
		dz+=vec3(-q*A*k*d.x*d.y*s,A*k*d.y*c,-q*A*k*d.y*d.y*s);
	}
	normal=normalize(cross(dz,dx));
}
float raw_height(vec2 uv) {return texelFetch(u_height,ivec2(round(uv*u_terrain_resolution)),0).r;}
float height_at(vec2 p) {
	vec2 uv=p/u_extent+.5;
	if(any(lessThan(uv,vec2(0)))||any(greaterThan(uv,vec2(1))))return -20.0;
	vec2 pixel=uv*u_terrain_resolution,i=min(floor(pixel),vec2(u_terrain_resolution-1.0)),f=pixel-i;
	float a=raw_height(i/u_terrain_resolution),b=raw_height((i+vec2(1,0))/u_terrain_resolution),c=raw_height((i+vec2(0,1))/u_terrain_resolution),d=raw_height((i+1.0)/u_terrain_resolution);
	return f.x+f.y<=1.0?a+(b-a)*f.x+(c-a)*f.y:d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
}
// Godot reverse-Z and arbitrary lens: depth belongs to the main viewport.
// This replaces the source's fixed WebGL .3/1200 linearDepth expression only.
float linear_depth(vec2 uv,mat4 inverse_projection) {
	float depth=texture(u_depth,uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc=vec3(uv,depth)*2.0-1.0;
	#else
	vec3 ndc=vec3(uv*2.0-1.0,depth);
	#endif
	vec4 view=inverse_projection*vec4(ndc,1.0);
	return -view.z/view.w;
}
void vertex() {
	vec3 displaced,normal;
	wave_filtered((MODEL_MATRIX*vec4(VERTEX,1.0)).xz,UV.x,displaced,normal);
	v_world=displaced;v_normal=normal;
	VERTEX=(inverse(MODEL_MATRIX)*vec4(v_world,1.0)).xyz;
	NORMAL=(inverse(mat3(MODEL_MATRIX))*v_normal);
}
void fragment() {
	vec2 screen_uv=SCREEN_UV;
	vec3 ripple=vec3(sin(v_world.x*2.1+u_time*2.0)+cos(v_world.z*1.7-u_time),0,cos(v_world.z*2.4+u_time*1.4)+sin(v_world.x*1.4-u_time));
	float footprint=max(length(dFdx(v_world.xz)),length(dFdy(v_world.xz)));
	float detail_filter=1.0-smoothstep(.4,1.3,footprint);
	vec3 n=normalize(v_normal+ripple*.035*u_strength*detail_filter);
	float water_depth=-(VIEW_MATRIX*vec4(v_world,1)).z;
	float optical_depth=max(0.0,linear_depth(screen_uv,INV_PROJECTION_MATRIX)-water_depth);
	// Godot viewport UV has a downward Y axis, unlike WebGL gl_FragCoord.
	vec2 refract_uv=clamp(screen_uv+vec2(n.x,-n.z)*.012*min(optical_depth*.15,1.0),vec2(.002),vec2(.998));
	if(linear_depth(refract_uv,INV_PROJECTION_MATRIX)<water_depth)refract_uv=screen_uv;
	vec3 scene=sample_source_scene(refract_uv);
	vec3 transmit=exp(-vec3(.19,.075,.035)*optical_depth);
	vec3 water_color=mix(vec3(.04,.40,.38),vec3(.012,.11,.19),1.0-exp(-optical_depth*.08));
	vec3 refracted=scene*transmit+water_color*(1.0-transmit);
	vec3 view_dir=normalize(u_eye-v_world),reflected_ray=reflect(-view_dir,n);
	vec3 reflection=source_sky(reflected_ray);
	vec4 rp=u_reflection_vp*vec4(v_world,1);
	vec2 ruv=vec2(rp.x/rp.w*.5+.5,.5-rp.y/rp.w*.5)+vec2(n.x,-n.z)*.009;
	if(u_use_reflection&&rp.w>0.0&&all(greaterThan(ruv,vec2(0)))&&all(lessThan(ruv,vec2(1))))reflection=sample_source_reflection(ruv);
	float f=.02+.98*pow(1.0-max(dot(n,view_dir),0.0),5.0);
	vec3 col=mix(refracted,reflection,f);
	float spec=pow(max(dot(n,normalize(u_sun+view_dir)),0.0),110.0);
	col+=u_sun_color*spec*.7;
	float depth=v_world.y-height_at(v_world.xz);
	if(u_foam&&depth>=0.0) {
		float band=.35+.65*pow(.5+.5*sin(depth*6.0-u_time*2.2+source_value_noise(v_world.xz*.5)*3.0),2.0);
		float foam=(1.0-smoothstep(.0,u_foam_width,depth))*band;
		col=mix(col,vec3(.85,.94,.91),foam*.86);
	}
	float fog=1.0-exp(-length(u_eye-v_world)*.0015);
	// Source default framebuffer also clamps display RGB; no manual 8-bit
	// rounding is applied to filtered scene/reflection samples.
	ALBEDO=reference_to_linear(clamp(mix(col,source_sky(normalize(v_world-u_eye)),fog),vec3(0.0),vec3(1.0)));
	ALPHA=1.0;
}
