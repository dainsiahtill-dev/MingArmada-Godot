shader_type spatial;
render_mode unshaded, world_vertex_coords, cull_disabled, depth_draw_never, blend_mix, fog_disabled, shadows_disabled;

uniform sampler2D normal_texture : repeat_enable, filter_linear_mipmap;
uniform float simulation_time = 0.0;
uniform vec3 camera_position = vec3(0.0);
uniform vec3 sun_position = vec3(300.0, 150.0, 100.0);

// Existing THREE.Color(hex) uniform values are already sRGB -> linear.
// Deliberately omit source_color: preserve those inputs, then the original
// shader's second pow(2.2) conversion, rather than silently correcting it.
uniform vec3 color_deep = vec3(0.0, 0.2501582847191642, 0.28314874041918053);
uniform vec3 color_shallow = vec3(0.0, 0.46778379610254284, 0.4178850708380236);
uniform vec3 color_foam = vec3(1.0);
// Balanced/low Three RenderPass writes the custom shader's raw numbers directly
// to the screen. Forward+ encodes linear ALBEDO to sRGB after this shader. With
// Environment.TONE_MAPPER_LINEAR, this explicit inverse preserves the original
// displayed water RGB. Set false to inspect the initial native-linear baseline.
uniform bool direct_screen_output = true;
// User-approved Godot art direction: bright blue offshore, turquoise shallows,
// animated shore breakers. The original profile remains available as style 0.
uniform int visual_style = 1;
uniform sampler2D coast_distance_texture : repeat_disable, filter_linear;
uniform bool has_coast_distance = false;
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc"

varying vec3 world_position;
varying float wave_height;

float original_wave_height(vec2 p) {
	// Exact five-wave expansion of the original sin(a)cos(b) vertex shader.
	return coastal_wave_height(p, simulation_time);
}

vec3 original_to_linear(vec3 color) {
	return pow(color, vec3(2.2));
}

vec3 direct_screen_to_working_linear(vec3 color) {
	// No RGB clamp: original white specular may exceed 1 before screen output.
	vec3 low = color / 12.92;
	vec3 high = pow((max(color, vec3(0.0)) + vec3(0.055)) / 1.055, vec3(2.4));
	return mix(low, high, step(vec3(0.04045), color));
}

void vertex() {
	wave_height = original_wave_height(VERTEX.xz);
	VERTEX.y += wave_height;
	world_position = VERTEX;
}

void fragment() {
	vec2 world_xz = world_position.xz;
	vec2 world_uv = world_xz * 0.008;
	vec3 n1 = texture(normal_texture, world_uv + vec2(simulation_time * 0.015, simulation_time * 0.005)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(normal_texture, world_uv * 1.6 - vec2(simulation_time * 0.02, 0.0)).rgb * 2.0 - 1.0;
	vec3 n3 = texture(normal_texture, world_uv * 4.0 + vec2(simulation_time * 0.04)).rgb * 2.0 - 1.0;
	vec3 normal = normalize(n1 + n2 * 0.8 + n3 * 0.3 + vec3(0.0, 3.5, 0.0));

	vec3 view_direction = normalize(camera_position - world_position);
	vec3 light_direction = normalize(sun_position);
	vec3 half_vector = normalize(light_direction + view_direction);
	float n_dot_v = max(dot(view_direction, vec3(0.0, 1.0, 0.0)), 0.0);
	float fresnel = pow(1.0 - n_dot_v, 3.0);
	float specular = pow(max(dot(normal, half_vector), 0.0), 250.0) * 1.5;

	vec3 deep = original_to_linear(color_deep);
	vec3 shallow = original_to_linear(color_shallow);
	vec3 foam = original_to_linear(color_foam);
	float height_factor = smoothstep(-2.0, 3.0, wave_height);
	vec3 base_water = mix(deep, shallow, height_factor * 0.6 + 0.1);
	vec3 water_color = mix(base_water, shallow * 1.2, fresnel * 0.6);

	vec2 debris_uv = world_xz * 0.04;
	vec2 flow1 = vec2(simulation_time * 0.025, simulation_time * 0.01);
	vec2 flow2 = vec2(-simulation_time * 0.015, simulation_time * 0.02);
	float noise_d1 = texture(normal_texture, debris_uv + flow1).r;
	float noise_d2 = texture(normal_texture, debris_uv * 0.7 + flow2).g;
	float spot1 = smoothstep(0.62, 0.66, noise_d1);
	float spot2 = smoothstep(0.40, 0.80, noise_d2);
	float debris = spot1 * spot2;
	debris *= wave_height * 0.2 + 0.9;
	water_color = mix(water_color, vec3(0.95, 0.98, 1.0), debris * 0.5);

	// The source's shore mask is zero. It only has this crest/noise foam.
	float foam_noise = texture(normal_texture, world_uv * 8.0 + vec2(simulation_time * 0.1)).r;
	float foam_factor = wave_height * 0.5 + foam_noise * 0.8;
	float foam_coverage = smoothstep(2.0, 2.3, foam_factor);
	vec3 final_color = mix(water_color, foam, foam_coverage) + vec3(specular);
	float output_alpha = clamp(0.45 + fresnel * 0.5 + foam_coverage, 0.0, 1.0);
	if (visual_style == 1) {
		float shore_depth = 50.0;
		float dry_height = -50.0;
		float coast_distance = 1000.0;
		if (has_shore_field) {
			vec2 shore_uv = (world_xz - shore_bounds.xy) / (shore_bounds.zw - shore_bounds.xy);
			if (all(greaterThanEqual(shore_uv, vec2(0.0))) && all(lessThanEqual(shore_uv, vec2(1.0)))) {
				dry_height = texture(shore_height_texture, shore_uv).r;
				shore_depth = max(-dry_height, 0.0);
				if (has_coast_distance) { coast_distance = texture(coast_distance_texture, shore_uv).r; }
			}
		}
		float shallow_mix = 1.0 - smoothstep(1.5, 17.0, shore_depth);
		float bottom_visibility = (1.0 - smoothstep(0.4, 10.0, shore_depth)) * (1.0 - smoothstep(0.0, 0.7, dry_height));
		vec3 azure = vec3(0.12, 0.48, 0.66);
		vec3 turquoise = vec3(0.18, 0.73, 0.73);
		vec3 bright_water = mix(azure, turquoise, shallow_mix);
		bright_water *= 0.94 + height_factor * 0.13;
		bright_water *= 0.92 + max(dot(normal, light_direction), 0.0) * 0.18;
		if (bottom_visibility > 0.001) {
			vec3 sand_bottom = coastal_sand_bottom(world_xz, normal.xz);
			float caustic = coastal_caustic_network(world_xz, simulation_time, normal.xz);
			bright_water = mix(bright_water, sand_bottom, bottom_visibility * 0.20);
			bright_water += vec3(0.035, 0.050, 0.038) * caustic * bottom_visibility;
		}
		bright_water = mix(bright_water, vec3(0.34, 0.72, 0.79), fresnel * 0.21);
		bright_water += vec3(specular * 0.32);
		bright_water = mix(bright_water, vec3(0.71, 0.89, 0.93), clamp(debris * 0.12, 0.0, 0.16));
		float shore_noise = texture(normal_texture, world_xz * 0.06 + vec2(simulation_time * 0.012, -simulation_time * 0.009)).g;
		float shore_foam = coastal_breaker_foam(coast_distance, shore_depth, dry_height, world_xz, simulation_time, foam_noise, shore_noise);
		float rolling_crest = smoothstep(2.05, 2.65, foam_factor) * 0.18;
		bright_water = mix(bright_water, vec3(0.91, 0.97, 0.95), max(shore_foam, rolling_crest));
		final_color = bright_water;
		// Deep water must hide the edge of the streamed seabed. Keep the same
		// 0.78 base opacity at the shallowest visible bottom.
		output_alpha = clamp(1.0 - bottom_visibility * 0.22 + fresnel * 0.07 + shore_foam * 0.22, 0.0, 1.0);
	}

	float distance_xz = length(camera_position.xz - world_xz);
	float fog_factor = smoothstep(100.0, 1500.0, distance_xz);
	vec3 fog_color = visual_style == 1 ? vec3(0.53, 0.81, 0.92) : original_to_linear(vec3(0.53, 0.81, 0.92));
	final_color = mix(final_color, fog_color, fog_factor);

	ALBEDO = direct_screen_output ? direct_screen_to_working_linear(final_color) : final_color;
	ALPHA = output_alpha;
}
