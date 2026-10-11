shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled, shadows_disabled;

uniform float simulation_time = 0.0;
uniform sampler2D spray_mask_texture : repeat_disable, filter_linear_mipmap;
uniform sampler2D coast_distance_texture : repeat_disable, filter_linear;
uniform bool has_coast_distance_field = false;
varying float lifetime_alpha;
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"

float wave_height(vec2 p) {
	return coastal_wave_height(p, simulation_time);
}

void vertex() {
	float seed = INSTANCE_CUSTOM.x;
	vec3 center = MODEL_MATRIX[3].xyz;
	float coast_distance = 100000.0;
	float shore_gate = 0.0;
	if (has_shore_field && has_coast_distance_field) {
		vec2 shore_uv = (center.xz - shore_bounds.xy) / (shore_bounds.zw - shore_bounds.xy);
		if (all(greaterThanEqual(shore_uv, vec2(0.0))) && all(lessThanEqual(shore_uv, vec2(1.0)))) {
			coast_distance = texture(coast_distance_texture, shore_uv).r;
			float depth = -texture(shore_height_texture, shore_uv).r;
			shore_gate = (1.0 - smoothstep(4.0, 7.0, coast_distance)) * smoothstep(0.15, 0.40, depth);
			shore_gate *= 1.0 - smoothstep(1.25, 1.7, depth);
		}
	}
	// The crest travels inland at the same 1.5 rad/s phase as the water's surf.
	// A small seed offset varies nearby droplets without a second clock.
	float cycle = fract((coast_distance * 1.05 + simulation_time * 1.50) / 6.2831853 + seed * .06);
	float age = cycle * (6.2831853 / 1.50);
	center.y += wave_height(center.xz);
	center += vec3(sin(seed * 80.0) * age * .65, max(0.0, 3.6 * age - 4.9 * age * age), cos(seed * 80.0) * age * .65);
	lifetime_alpha = (1.0 - smoothstep(.11, .18, cycle)) * smoothstep(0.0, .018, cycle) * shore_gate;
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], vec4(center, 1.0));
	VERTEX.xy *= .65 + INSTANCE_CUSTOM.y * .6;
}

void fragment() {
	float radius = length(UV - .5);
	// Source RGB is constant white: only alpha contains scattered water drops.
	float droplets = texture(spray_mask_texture, UV).a;
	ALBEDO = vec3(.90, .98, 1.0);
	ALPHA = (1.0 - smoothstep(.25, .5, radius)) * smoothstep(.025, .24, droplets) * lifetime_alpha * .65;
}
