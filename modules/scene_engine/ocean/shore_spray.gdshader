shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float simulation_time = 0.0;
varying float lifetime_alpha;
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"

float wave_height(vec2 p) {
	return coastal_wave_height(p, simulation_time);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	float cycle = fract(simulation_time * .34 + seed);
	float age = cycle * 2.9;
	vec3 center = MODEL_MATRIX[3].xyz;
	center.y += wave_height(center.xz);
	center += vec3(sin(seed * 80.0) * age * .8, max(0.0, 3.6 * age - 4.9 * age * age), cos(seed * 80.0) * age * .8);
	lifetime_alpha = (1.0 - smoothstep(.13, .26, cycle)) * smoothstep(0.0, .025, cycle);
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
	VERTEX.xy *= .65 + INSTANCE_CUSTOM.y * .6;
}

void fragment() {
	float radius = length(UV - .5);
	ALBEDO = vec3(.90, .98, 1.0);
	ALPHA = (1.0 - smoothstep(.12, .5, radius)) * lifetime_alpha * .6;
}
