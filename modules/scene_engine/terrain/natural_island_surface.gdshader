shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;

// Authored natural height/slope adapter; original display-space DDS samples.
// Scene injects clock and water state. Land vertices remain untouched.
uniform sampler2D tex_ocean_1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ocean_2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ocean_3 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_patch : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_beach : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_forest : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock_forest : filter_linear_mipmap, repeat_enable;
uniform vec3 native_sand_color = vec3(1.0, 0.9843137255, 1.0);
uniform vec3 native_wet_color = vec3(0.8705882353, 0.8039215686, 0.6274509804);
uniform float texture_world_scale = 0.025;
uniform float forest_start = 1.5;
uniform float forest_end = 4.5;
uniform float ridge_start = 24.0;
uniform float ridge_end = 43.0;
uniform float ridge_rock_strength : hint_range(0.0, 1.0) = 0.76;
uniform float rock_slope_start = 0.30;
uniform float rock_slope_end = 0.65;
uniform float slope_rock_strength : hint_range(0.0, 1.0) = 0.90;
uniform float rock_pattern_world_scale = 0.045;
uniform float rock_pattern_strength : hint_range(0.0, 0.25) = 0.10;
uniform float rock_forest_mix : hint_range(0.0, 1.0) = 0.20;
uniform float display_fog_density = 0.0002;
uniform vec3 deep_color = vec3(0.12, 0.48, 0.66);
uniform float simulation_time = 0.0;
uniform float u_time = 0.0;
uniform float u_tide = 0.0;
uniform vec3 u_sun = vec3(-0.505076, 0.808122, 0.303046);
uniform vec3 u_sun_color = vec3(1.0, 0.95, 0.82);
uniform bool u_clip = true;
uniform bool u_caustics = true;
uniform bool caustics_enabled = true;
uniform float caustic_strength : hint_range(0.0,1.0) = 0.45;
uniform sampler2D reference_caustics_texture : repeat_enable, filter_linear_mipmap;

// Descriptor uniforms stay compatible with the old water/surface transfer.
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"
#include "res://modules/scene_engine/reference_island_water/reference_terrain_common.gdshaderinc"

varying vec3 island_world;
varying vec3 island_normal;

void vertex() {
	island_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	island_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	// Per-pass camera supports the retained mirrored reflection camera.
	if (u_clip && CAMERA_POSITION_WORLD.y < u_tide-0.02 && island_world.y < u_tide-0.02) {
		discard;
	}
	vec3 normal = normalize(island_normal);
	float height = island_world.y-u_tide;
	// Rise/run grade gives broad hills a useful slope range. 1-normal.y
	// compressed grade0.3..0.6 to0.04..0.14 and hid the original stone.
	float slope = length(normal.xz)/max(normal.y,0.05);
	vec2 uv = island_world.xz*texture_world_scale;
	vec3 grass_patch = texture(tex_grass_patch,uv).rgb;
	vec3 grass_beach = texture(tex_grass_beach,uv).rgb;
	vec3 forest_texture = texture(tex_forest,uv).rgb;
	vec3 rock_texture = texture(tex_rock,uv).rgb;
	vec3 rock_forest = texture(tex_rock_forest,uv).rgb;
	vec3 ocean_floor = texture(tex_ocean_1,uv).rgb*0.45 + texture(tex_ocean_2,uv).rgb*0.35 + texture(tex_ocean_3,uv).rgb*0.20;
	float grain = dot(texture(tex_grass_beach,uv*3.8).rgb,vec3(0.2126,0.7152,0.0722));
	// Dry source sand is nearly white; original wet sand supplies warm mineral
	// hue. Imported texture detail stays small, avoiding crater-like patches.
	vec3 warm_sand = mix(native_sand_color,native_wet_color,0.82)*vec3(0.95,0.89,0.72);
	vec3 sand = warm_sand*(0.90+0.16*grain);
	vec3 wet_sand = mix(native_wet_color*vec3(0.72,0.78,0.70),ocean_floor,0.22);
	vec3 forest = forest_texture*0.62+grass_patch*0.25+grass_beach*0.13;
	forest = mix(forest,vec3(0.25,0.36,0.13),0.16);
	// The original rock DDS is warm mineral stone; rockforest supplies small
	// green interruptions without washing the full mountain back to grass.
	vec3 rock = mix(rock_texture,rock_forest,rock_forest_mix)*vec3(0.94,0.93,0.86);
	float steep_rock = smoothstep(rock_slope_start,rock_slope_end,slope)*smoothstep(4.0,14.0,height)*slope_rock_strength;
	float ridge_rock = smoothstep(ridge_start,ridge_end,height)*ridge_rock_strength;
	// Both scales sample continuous world position. Restrained modulation
	// follows an already broad rock mass; it cannot create isolated craters.
	float rock_pattern = reference_value_noise(island_world.xz*rock_pattern_world_scale)*0.7;
	rock_pattern += reference_value_noise(island_world.xz*rock_pattern_world_scale*2.7+vec2(13.2,-7.1))*0.3;
	float rock_weight = clamp(max(steep_rock,ridge_rock)*(1.0+(rock_pattern-0.5)*rock_pattern_strength),0.0,0.94);
	float forest_weight = smoothstep(forest_start,forest_end,height)*(1.0-rock_weight);
	vec3 albedo = mix(wet_sand,sand,smoothstep(-0.3,0.6,height));
	albedo = albedo*(1.0-forest_weight-rock_weight)+forest*forest_weight+rock*rock_weight;
	float diffuse = max(dot(normal,normalize(u_sun)),0.0);
	vec3 color = albedo*(vec3(0.35,0.43,0.44)+u_sun_color*diffuse*0.75);
	if (height < 0.0) {
		// Deep bed tends toward the old sea color instead of an opaque brown
		// rectangle visible through far water. Near floor keeps sand/texture.
		color = mix(color,deep_color,smoothstep(2.0,20.0,-height));
		if (u_caustics && caustics_enabled) {
			// Original waterdetail contains curved, irregular refracted light.
			// Opposing flows and a small nonlinear warp avoid a static tile/net.
			vec2 p=island_world.xz*0.06;
			vec2 warp=vec2(sin(p.y*3.1+u_time*0.24),cos(p.x*2.7-u_time*0.21))*0.035;
			vec2 flow=vec2(u_time*0.003,-u_time*0.002);
			mat2 rotation=mat2(vec2(0.819,0.574),vec2(-0.574,0.819));
			float light_a=dot(texture(reference_caustics_texture,p+warp+flow).rgb,vec3(0.2126,0.7152,0.0722));
			float light_b=dot(texture(reference_caustics_texture,rotation*p*1.31-warp-flow).rgb,vec3(0.2126,0.7152,0.0722));
			float caustic=smoothstep(0.55,0.86,light_a)*0.6+smoothstep(0.55,0.86,light_b)*0.4;
			// Fine lines converge to faint illumination at unresolved distances.
			float footprint=max(length(dFdx(p)),length(dFdy(p)))*256.0;
			caustic*=1.0-smoothstep(2.0,10.0,footprint);
			color += vec3(0.24,0.38,0.24)*caustic*exp(height*0.3)*caustic_strength;
		}
	}
	vec3 eye = CAMERA_POSITION_WORLD;
	float fog = 1.0-exp(-length(eye-island_world)*display_fog_density);
	vec3 display_color = clamp(mix(color,reference_sky(normalize(island_world-eye)),fog),vec3(0.0),vec3(1.0));
	ALBEDO = reference_display_to_linear(display_color);
}
