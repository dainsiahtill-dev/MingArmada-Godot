#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
uniform float simulation_time = 0.0;
uniform sampler2D shore_height_texture : repeat_disable, filter_nearest;
uniform vec4 shore_bounds = vec4(0.0);
uniform bool has_shore_field = false;
uniform bool coastal_attenuation = true;
uniform sampler2D coast_distance_texture : repeat_disable, filter_nearest;
uniform bool has_coast_distance = false;
uniform sampler2D reference_near_height_texture : repeat_disable, filter_nearest;
uniform vec4 reference_near_bounds = vec4(0.0);
uniform bool has_reference_near_field = false;

float reference_rf_height(sampler2D image,vec2 uv,bool triangular) {
	ivec2 size=textureSize(image,0);
	vec2 pixel=uv*vec2(size-ivec2(1));
	ivec2 i=ivec2(min(floor(pixel),vec2(size-ivec2(2))));vec2 f=pixel-vec2(i);
	float a=texelFetch(image,i,0).r,b=texelFetch(image,i+ivec2(1,0),0).r;
	float c=texelFetch(image,i+ivec2(0,1),0).r,d=texelFetch(image,i+ivec2(1),0).r;
	if(triangular)return f.x+f.y<=1.0?a+(b-a)*f.x+(c-a)*f.y:d+(c-d)*(1.0-f.x)+(b-d)*(1.0-f.y);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
bool reference_inside(vec2 uv) {return all(greaterThanEqual(uv,vec2(0.0)))&&all(lessThanEqual(uv,vec2(1.0)));}
float reference_global_height(vec2 point) {
	if(!has_shore_field)return -20.0;
	vec2 uv=(point-shore_bounds.xy)/(shore_bounds.zw-shore_bounds.xy);
	if(!reference_inside(uv))return -20.0;
	return reference_rf_height(shore_height_texture,uv,false);
}
float height_at(vec2 point) {
	if(has_reference_near_field) {
		vec2 uv=(point-reference_near_bounds.xy)/(reference_near_bounds.zw-reference_near_bounds.xy);
		if(reference_inside(uv))return reference_rf_height(reference_near_height_texture,uv,true);
	}
	return reference_global_height(point);
}
float reference_coast_distance(vec2 point) {
	if(!has_coast_distance||!has_shore_field)return 1000.0;
	vec2 uv=(point-shore_bounds.xy)/(shore_bounds.zw-shore_bounds.xy);
	if(!reference_inside(uv))return 1000.0;
	return reference_rf_height(coast_distance_texture,uv,false);
}
float reference_game_height(vec2 point,float seconds) {
	float wave=configured_wave_height(point,seconds);
	if(!coastal_attenuation||!has_shore_field)return wave;
	vec2 uv=(point-shore_bounds.xy)/(shore_bounds.zw-shore_bounds.xy);
	if(!reference_inside(uv))return wave;
	return wave*smoothstep(0.0,8.0,-reference_global_height(point));
}
vec3 reference_game_normal(vec2 point,float seconds) {
	float wave=configured_wave_height(point,seconds);
	vec2 gradient=vec2(0.0);
	for(int i=0;i<8;i++) {
		if(i<wave_count) {
			vec4 w=wave_components[i];
			gradient+=w.x*cos(dot(point,w.yz)+w.w*seconds)*w.yz;
		}
	}
	if(coastal_attenuation&&has_shore_field) {
		vec2 uv=(point-shore_bounds.xy)/(shore_bounds.zw-shore_bounds.xy);
		if(reference_inside(uv)) {
			float depth=-reference_global_height(point);
			float t=clamp(depth/8.0,0.0,1.0),scale=t*t*(3.0-2.0*t);
			float derivative=6.0*t*(1.0-t)/8.0;
			vec2 ground_gradient=vec2(reference_global_height(point+vec2(.5,0))-reference_global_height(point-vec2(.5,0)),reference_global_height(point+vec2(0,.5))-reference_global_height(point-vec2(0,.5)));
			gradient=gradient*scale-wave*derivative*ground_gradient;
		}
	}
	return normalize(vec3(-gradient.x,1.0,-gradient.y));
}
