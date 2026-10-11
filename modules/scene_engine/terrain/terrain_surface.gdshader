shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// Formal-world adapter keeps terrainVS/terrainFS expressions and world noise.
// display-space source shading is converted once for its linear framebuffer.
uniform float simulation_time = 0.0;
uniform bool caustics_enabled = true;
uniform vec3 sand_color = vec3(.72,.58,.29);
uniform vec3 grass_color = vec3(.13,.23,.063);
uniform vec3 rock_color = vec3(.25,.22,.16);
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"

uniform float u_time = 0.0;
uniform float u_tide = 0.0;
uniform vec3 u_eye = vec3(-87.0,116.0,115.0);
uniform vec3 u_sun = vec3(-0.505076,0.808122,0.303046);
uniform vec3 u_sun_color = vec3(1.0,0.95,0.82);
uniform bool u_clip = true;
uniform bool u_caustics = true;

varying vec3 reference_world;
varying vec3 reference_normal;

#include "res://modules/scene_engine/reference_island_water/reference_terrain_common.gdshaderinc"

void vertex() {
	reference_world = (MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	reference_normal = MODEL_NORMAL_MATRIX*NORMAL;
}

void fragment() {
	// The mirrored camera shares World3D and materials with the main camera.
	// Main preview cameras stay above water; only the mirrored pass clips land.
	if (u_clip && CAMERA_POSITION_WORLD.y < u_tide-0.02 && reference_world.y < u_tide-0.02) {
		discard;
	}
	vec3 n = normalize(reference_normal);
	float h = reference_world.y-u_tide;
	float slope = 1.0-n.y;
	float grain = reference_value_noise(reference_world.xz*2.0);
	float large = reference_value_noise(reference_world.xz*0.12);
	vec3 sand = vec3(0.74,0.66,0.45)*(0.90+0.18*grain);
	vec3 wet = vec3(0.39,0.42,0.30)*(0.9+0.15*grain);
	vec3 grass = mix(vec3(0.17,0.29,0.09),vec3(0.28,0.40,0.13),large);
	vec3 rock = mix(vec3(0.28,0.29,0.27),vec3(0.47,0.46,0.38),grain);
	vec3 albedo = mix(wet,sand,smoothstep(-0.3,1.5,h));
	albedo = mix(albedo,grass,smoothstep(1.4,4.0,h)*(1.0-smoothstep(0.32,0.65,slope)));
	albedo = mix(albedo,rock,smoothstep(0.28,0.70,slope)*smoothstep(1.0,4.0,h));
	float diffuse = max(dot(n,u_sun),0.0);
	vec3 col = albedo*(vec3(0.35,0.43,0.44)+u_sun_color*diffuse*0.75);
	if (h < 0.0 && u_caustics && caustics_enabled) {
		vec2 p = reference_world.xz*0.85;
		float a = sin(p.x+sin(p.y*1.3+u_time*0.8));
		float b = sin(p.y+sin(p.x*1.2-u_time*0.6));
		float caustic = pow(max(0.0,1.0-abs(a+b)*1.4),9.0);
		col += vec3(0.24,0.38,0.24)*caustic*exp(h*0.3);
	}
	// Camera position, rather than a mutable material uniform, is per render pass.
	vec3 eye = CAMERA_POSITION_WORLD;
	float fog = 1.0-exp(-length(eye-reference_world)*0.0015);
	// Source scene/reflection targets are RGBA8: their write clamps display RGB.
	// Keep filtered samples continuous; emulate the bound, not a second quantizer.
	vec3 display_color = clamp(mix(col,reference_sky(normalize(reference_world-eye)),fog),vec3(0.0),vec3(1.0));
	ALBEDO = reference_display_to_linear(display_color);
}
