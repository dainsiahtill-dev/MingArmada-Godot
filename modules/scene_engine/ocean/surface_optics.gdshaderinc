// Current viewport opaque copy excludes this transparent ocean automatically.
// Forward+/Mobile use reverse Z [0,1]; Compatibility uses [-1,1] NDC.
uniform sampler2D surface_scene_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D surface_depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool surface_optics_enabled = false;
uniform bool surface_reflection_enabled = false;
uniform bool surface_refraction_enabled = false;
uniform int surface_reflection_steps = 16;
uniform float surface_reflection_strength = 0.26;
uniform float surface_refraction_strength = 0.42;

vec3 optics_view_position(vec2 uv, float raw_depth, mat4 inverse_projection) {
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, raw_depth) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, raw_depth);
#endif
	vec4 view = inverse_projection * vec4(ndc, 1.0);
	return view.xyz / max(abs(view.w), 0.000001) * sign(view.w);
}

vec3 optics_transmittance(float thickness) {
	return exp(-vec3(0.16, 0.065, 0.028) * clamp(thickness, 0.0, 80.0));
}

// Return alpha=confidence. Below-surface geometry and screen edges are rejected.
vec4 optics_screen_reflection(vec3 origin, vec3 normal_view, float water_y,
		mat4 projection, mat4 inverse_projection, mat4 inverse_view) {
	vec3 ray = reflect(normalize(origin), normal_view);
	float distance_along_ray = 0.45;
	float stride = 0.55;
	for (int i = 0; i < 24; i++) {
		if (i >= surface_reflection_steps) { break; }
		vec3 position_view = origin + normal_view * 0.075 + ray * distance_along_ray;
		if (position_view.z >= -0.05) { break; }
		vec4 projected = projection * vec4(position_view, 1.0);
		if (projected.w <= 0.000001) { break; }
		vec2 uv = projected.xy / projected.w * 0.5 + 0.5;
		if (any(lessThan(uv, vec2(0.002))) || any(greaterThan(uv, vec2(0.998)))) { break; }
		float raw_depth = textureLod(surface_depth_texture, uv, 0.0).r;
		vec3 scene_view = optics_view_position(uv, raw_depth, inverse_projection);
		float difference = -position_view.z + scene_view.z;
		vec3 scene_world = (inverse_view * vec4(scene_view, 1.0)).xyz;
		if (difference >= 0.0 && difference < 1.3 + distance_along_ray * 0.012 && scene_world.y > max(0.04, water_y + 0.03)) {
			float edge = smoothstep(0.0, 0.06, min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y)));
			float reach = 1.0 - smoothstep(50.0, 110.0, distance_along_ray);
			return vec4(textureLod(surface_scene_texture, uv, 1.0).rgb, edge * reach);
		}
		distance_along_ray += stride;
		stride *= 1.22;
	}
	return vec4(0.0);
}

vec3 reference_surface_optics(vec3 working_water, vec3 world, vec3 normal_world,
		vec2 screen_uv, mat4 view_matrix, mat4 projection,
		mat4 inverse_projection, mat4 inverse_view) {
	vec3 water_view = (view_matrix * vec4(world, 1.0)).xyz;
	vec3 normal_view = normalize(mat3(view_matrix) * normal_world);
	float raw_depth = textureLod(surface_depth_texture, screen_uv, 0.0).r;
	vec3 opaque_view = optics_view_position(screen_uv, raw_depth, inverse_projection);
	float thickness = max(0.0, -opaque_view.z + water_view.z);
	vec3 result = working_water;
	if (surface_refraction_enabled) {
		// Refraction must not pull a foreground hull into the water behind it.
		vec2 refracted_uv = clamp(screen_uv + normal_view.xy * 0.006 * smoothstep(0.0, 3.0, thickness), vec2(0.002), vec2(0.998));
		float displaced_raw = textureLod(surface_depth_texture, refracted_uv, 0.0).r;
		vec3 displaced_view = optics_view_position(refracted_uv, displaced_raw, inverse_projection);
		if (-displaced_view.z < -water_view.z + 0.08) { refracted_uv = screen_uv; }
		vec3 transmitted = optics_transmittance(thickness);
		vec3 opaque_color = textureLod(surface_scene_texture, refracted_uv, 0.0).rgb;
		vec3 absorbed = opaque_color * transmitted + working_water * (vec3(1.0) - transmitted);
		float shallow_visibility = 1.0 - smoothstep(1.0, 22.0, thickness);
		result = mix(result, absorbed, shallow_visibility * surface_refraction_strength);
	}
	if (surface_reflection_enabled) {
		vec4 reflected = optics_screen_reflection(water_view, normal_view, world.y, projection, inverse_projection, inverse_view);
		float fresnel = 0.02 + 0.98 * pow(1.0 - max(dot(normalize(-water_view), normal_view), 0.0), 5.0);
		// A readable art-directed floor retains small boat reflections overhead.
		float amount = reflected.a * surface_reflection_strength * (0.35 + fresnel * 0.65);
		result = mix(result, reflected.rgb, amount);
	}
	return result;
}
