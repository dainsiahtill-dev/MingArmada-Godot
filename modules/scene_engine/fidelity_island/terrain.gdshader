shader_type spatial;
uniform float game_land_start = 3.0;
uniform float game_land_end = 12.0;
render_mode unshaded, cull_disabled, fog_disabled;

// Original BHI/UnderDark RGB algebra with an explicit Godot world adapter.
// No geometry displacement. These are original texture samples, not generated noise.
uniform bool use_source_material_field = false;
uniform bool enable_source_lighting = false;
uniform bool use_source_normals = true;
uniform float source_normal_strength : hint_range(0.0, 1.0) = 0.35;
uniform vec2 source_uv_row_x = vec2(0.0);
uniform vec2 source_uv_row_z = vec2(0.0);
uniform vec2 source_uv_offset = vec2(0.0);
uniform vec2 source_column_axis = vec2(1.0, 0.0);
uniform vec2 source_row_axis = vec2(0.0, 1.0);
uniform vec2 source_size = vec2(120.0, 140.0);
uniform float native_texture_scale = 4.0;
uniform vec2 native_texture_offset = vec2(0.0);
uniform float native_cell_span = 63.0;
uniform vec3 native_sand_color = vec3(1.0, 0.9843137255, 1.0);
uniform vec3 native_wet_color = vec3(0.8705882353, 0.8039215686, 0.6274509804);
uniform vec3 source_light_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 source_light_color = vec3(1.0);
uniform vec3 source_ambient = vec3(0.25);
uniform sampler2D source_weight_0 : filter_linear, repeat_disable;
uniform sampler2D source_weight_1 : filter_linear, repeat_disable;
uniform sampler2D source_weight_2 : filter_linear, repeat_disable;
uniform sampler2D source_normal_texture : filter_linear, repeat_disable;
uniform sampler2D source_height_texture : filter_linear, repeat_disable;
// Raw display-space DDS channels. Convert the completed color once below.
uniform sampler2D tex_ocean_1 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ocean_2 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_ocean_3 : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_patch : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_grass_beach : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_forest : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock : filter_linear_mipmap, repeat_enable;
uniform sampler2D tex_rock_forest : filter_linear_mipmap, repeat_enable;

// Retained formal-world appearance/time/reflector contract. The scene owns time.
uniform float simulation_time = 0.0;
uniform bool caustics_enabled = true;
uniform float u_time = 0.0;
uniform float u_tide = 0.0;
uniform vec3 u_sun = vec3(-0.505076, 0.808122, 0.303046);
uniform vec3 u_sun_color = vec3(1.0, 0.95, 0.82);
uniform bool u_clip = true;
uniform bool u_caustics = true;
uniform float game_texture_world_scale = 0.025;
uniform float display_fog_density = 0.0015;
// Only completed-source observers opt into the recovered draw composition.
// Formal game terrain retains the existing opaque material/lighting branch.
uniform bool source_observer_composition = false;
#include "res://modules/scene_engine/fidelity_island/source_water_color.gdshaderinc"
#include "res://modules/scene_engine/ocean/wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_wave_functions.gdshaderinc"

varying vec3 fidelity_world;
varying vec3 fidelity_normal;
varying vec4 observer_w0;
varying vec4 observer_w1;
varying vec3 observer_lit;
varying vec3 observer_under_color;
varying float observer_alpha;
varying vec2 observer_texture_uv;

vec3 display_to_linear(vec3 color) {
	vec3 low = color / 12.92;
	vec3 high = pow(max((color + vec3(0.055)) / 1.055, vec3(0.0)), vec3(2.4));
	return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

vec3 retained_sky(vec3 ray) {
	float h = clamp(ray.y, 0.0, 1.0);
	vec3 color = mix(vec3(0.55, 0.76, 0.81), vec3(0.13, 0.37, 0.58), pow(h, 0.55));
	color = mix(color, vec3(0.80, 0.55, 0.35), clamp((1.0-u_sun.y)*0.45, 0.0, 0.5)*(1.0-h));
	float s = max(dot(ray, u_sun), 0.0);
	return color + u_sun_color*(pow(s, 320.0)*1.1 + pow(s, 16.0)*0.1);
}

void vertex() {
	fidelity_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	fidelity_normal = MODEL_NORMAL_MATRIX * NORMAL;
	if (source_observer_composition) {
		vec2 uv = vec2(dot(source_uv_row_x, fidelity_world.xz), dot(source_uv_row_z, fidelity_world.xz)) + source_uv_offset;
		vec4 a = textureLod(source_weight_0, uv, 0.0);
		vec4 b = textureLod(source_weight_1, uv, 0.0);
		vec4 sand = textureLod(source_weight_2, uv, 0.0);
		vec3 native_normal = textureLod(source_normal_texture, uv, 0.0).xyz;
		vec2 horizontal = source_column_axis * native_normal.x - source_row_axis * native_normal.y;
		vec3 normal = vec3(horizontal.x, native_normal.z, horizontal.y);
		observer_lit = clamp(dot(-source_light_direction, normal) * source_light_color + source_ambient, vec3(0.0), vec3(1.0));
		vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
		float normalized_z = completed_forward_clip_z(clip) / source_fog_values.x;
		// VSTerrain fog is step*(Z-start)/range, unlike the water's saturate.
		float fog = source_fog_enabled ? step(source_fog_values.y, normalized_z) * (normalized_z - source_fog_values.y) / source_fog_values.z : 0.0;
		observer_alpha = dot(a, vec4(1.0)) + dot(b, vec4(1.0)) + sand.x + sand.y;
		observer_under_color = source_fog_color * fog + (1.0 - fog) * (sand.x * native_sand_color + sand.y * native_wet_color) * observer_lit;
		observer_w0 = a * (1.0 - fog);
		observer_w1 = b * (1.0 - fog);
		observer_texture_uv = (uv * source_size - vec2(0.5)) * (native_texture_scale / native_cell_span) + native_texture_offset;
	}
}

void fragment() {
	if (u_clip && CAMERA_POSITION_WORLD.y < u_tide-0.02 && fidelity_world.y < u_tide-0.02) {
		discard;
	}
	vec3 normal = normalize(fidelity_normal);
	vec3 source_lighting_normal = normal;
	float height = fidelity_world.y-u_tide;
	vec2 source_uv = vec2(dot(source_uv_row_x, fidelity_world.xz), dot(source_uv_row_z, fidelity_world.xz)) + source_uv_offset;
	bool inside_source = all(greaterThanEqual(source_uv, vec2(0.0))) && all(lessThanEqual(source_uv, vec2(1.0)));
	vec2 texture_uv = fidelity_world.xz * game_texture_world_scale;
	vec4 w0 = vec4(0.0);
	vec4 w1 = vec4(0.0);
	vec4 w2 = vec4(0.0);
	if (use_source_material_field && inside_source) {
		w0 = texture(source_weight_0, source_uv);
		w1 = texture(source_weight_1, source_uv);
		w2 = texture(source_weight_2, source_uv);
		texture_uv = (source_uv*source_size-vec2(0.5)) * (native_texture_scale/native_cell_span) + native_texture_offset;
		if (use_source_normals) {
			vec3 source_normal = texture(source_normal_texture, source_uv).xyz;
			vec2 horizontal = source_column_axis*source_normal.x - source_row_axis*source_normal.y;
			vec3 adapted_normal = vec3(horizontal.x, source_normal.z, horizontal.y);
			source_lighting_normal = adapted_normal;
			normal = normalize(mix(normal, normalize(adapted_normal), source_normal_strength));
		}
	} else {
		// Other ports retain their own geometry; only these imported materials are reused.
		// This is an authored height/slope adapter, never another island's original BHI.
		float slope = 1.0-clamp(normal.y, 0.0, 1.0);
		float rock = smoothstep(0.22, 0.64, slope)*smoothstep(0.2, 3.0, height);
		rock = max(rock, smoothstep(80.0, 140.0, height)*0.6);
		float land = smoothstep(game_land_start, game_land_end, height)*(1.0-rock);
		float wet = 1.0-smoothstep(-0.3, 1.5, height);
		float beach = (1.0-land-rock)*(1.0-wet);
		float seabed = (1.0-land-rock)*wet;
		w0 = vec4(seabed*0.36, seabed*0.24, seabed*0.16, land*0.22);
		w1 = vec4(land*0.28, rock*0.6, rock*0.4, land*0.5);
		w2 = vec4(beach, seabed*0.24, 0.0, 0.0);
	}
	// Id order: 1,2,3,16 | 17,32,33,64 | 48,49. No weight normalization.
	float weight_sum = dot(w0, vec4(1.0)) + dot(w1, vec4(1.0)) + w2.x + w2.y;
	vec3 underdark = w2.x*native_sand_color + w2.y*native_wet_color;
	vec3 albedo = underdark*clamp(weight_sum, 0.0, 1.0);
	albedo += texture(tex_ocean_1, texture_uv).rgb*w0.x;
	albedo += texture(tex_ocean_2, texture_uv).rgb*w0.y;
	albedo += texture(tex_ocean_3, texture_uv).rgb*w0.z;
	albedo += texture(tex_grass_patch, texture_uv).rgb*w0.w;
	albedo += texture(tex_grass_beach, texture_uv).rgb*w1.x;
	albedo += texture(tex_rock, texture_uv).rgb*w1.y;
	albedo += texture(tex_rock_forest, texture_uv).rgb*w1.z;
	albedo += texture(tex_forest, texture_uv).rgb*w1.w;
	// Original UnderDark is SrcAlpha/InvSrcAlpha over earlier background, then
	// additive passes. Godot's opaque terrain must also provide that background.
	// Use an actual source seabed sample for the unfilled part, not a renormalizer.
	albedo += texture(tex_ocean_1, texture_uv).rgb*(1.0-clamp(weight_sum, 0.0, 1.0));
	vec3 lighting = vec3(0.35, 0.43, 0.44) + u_sun_color*max(dot(normal, normalize(u_sun)), 0.0)*0.75;
	if (enable_source_lighting) {
		// Native VS consumes its raw decoded normal; do not substitute a modern
		// normalization into the optional original local-light equation.
		lighting = clamp(dot(-source_light_direction, source_lighting_normal)*source_light_color + source_ambient, vec3(0.0), vec3(1.0));
	}
	vec3 color = albedo*lighting;
	if (source_observer_composition) {
		// Recovered draw order: original NR water, UnderDark SrcAlpha/InvSrcAlpha,
		// then One/One weighted texture passes. Preserve original vertex values.
		vec3 additive = texture(tex_ocean_1, observer_texture_uv).rgb * observer_w0.x;
		additive += texture(tex_ocean_2, observer_texture_uv).rgb * observer_w0.y;
		additive += texture(tex_ocean_3, observer_texture_uv).rgb * observer_w0.z;
		additive += texture(tex_grass_patch, observer_texture_uv).rgb * observer_w0.w;
		additive += texture(tex_grass_beach, observer_texture_uv).rgb * observer_w1.x;
		additive += texture(tex_rock, observer_texture_uv).rgb * observer_w1.y;
		additive += texture(tex_rock_forest, observer_texture_uv).rgb * observer_w1.z;
		additive += texture(tex_forest, observer_texture_uv).rgb * observer_w1.w;
		vec3 background = completed_background_at(fidelity_world, CAMERA_POSITION_WORLD, VIEW_MATRIX, PROJECTION_MATRIX);
		float under_alpha = clamp(observer_alpha, 0.0, 1.0);
		color = observer_under_color * under_alpha + background * (1.0 - under_alpha) + additive * observer_lit;
		ALBEDO = display_to_linear(clamp(color, vec3(0.0), vec3(1.0)));
	} else {
	// Retain the existing game's underwater caustic accent as a target-game
	// effect. It is not evidence for Pirates' Caust%02d animation or shader.
	if (height < 0.0 && u_caustics && caustics_enabled) {
		vec2 p = fidelity_world.xz*0.85;
		float a = sin(p.x+sin(p.y*1.3+u_time*0.8));
		float b = sin(p.y+sin(p.x*1.2-u_time*0.6));
		float caustic = pow(max(0.0, 1.0-abs(a+b)*1.4), 9.0);
		color += vec3(0.24, 0.38, 0.24)*caustic*exp(height*0.3);
	}
	vec3 eye = CAMERA_POSITION_WORLD;
	float fog = 1.0-exp(-length(eye-fidelity_world)*display_fog_density);
	ALBEDO = display_to_linear(clamp(mix(color, retained_sky(normalize(fidelity_world-eye)), fog), vec3(0.0), vec3(1.0)));
	}
}
