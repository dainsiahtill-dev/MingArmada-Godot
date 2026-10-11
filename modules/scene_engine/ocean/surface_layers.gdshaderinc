// Fragment-only layers. Buoyancy and projected geometry retain their original waves.
uniform sampler2D reference_whitecaps_texture : repeat_enable, filter_linear_mipmap;
uniform vec2 surface_wind_direction = vec2(1.0, 0.0);
uniform float surface_wind_speed = 14.0;
uniform float surface_detail_strength = 0.09;

float reference_whitecap_coverage(vec2 p, vec3 normal, float seconds, float view_distance) {
	vec2 across = vec2(-surface_wind_direction.y, surface_wind_direction.x);
	vec2 flow_space = vec2(dot(p, surface_wind_direction), dot(p, across));
	float drift = seconds * (0.012 + surface_wind_speed * 0.0007);
	float a = texture(reference_whitecaps_texture, flow_space * vec2(0.024, 0.038) - vec2(drift, 0.0)).a;
	float b = texture(reference_whitecaps_texture, flow_space.yx * vec2(0.041, 0.029) + vec2(drift * 0.51, drift * 0.13)).a;
	float mask = smoothstep(0.16, 0.75, a) * smoothstep(0.23, 0.67, b);
	float crest = smoothstep(0.04, 0.30, length(normal.xz));
	float wind = smoothstep(2.0, 22.0, surface_wind_speed);
	// Gradually remove subpixel flecks in the distance; horizon never turns white.
	float detail = 1.0 - smoothstep(160.0, 850.0, view_distance);
	return mask * (0.30 + crest * 0.70) * wind * detail * surface_detail_strength;
}

float reference_wind_glint(vec2 p, vec3 normal, float seconds) {
	vec2 across = vec2(-surface_wind_direction.y, surface_wind_direction.x);
	vec2 uv = vec2(dot(p, across) * 0.095, dot(p, surface_wind_direction) * 0.052);
	uv -= vec2(0.0, seconds * surface_wind_speed * 0.00055);
	float fleck = texture(reference_sparkle_texture, uv + normal.xz * 0.022).a;
	return smoothstep(0.48, 0.91, fleck) * smoothstep(1.0, 16.0, surface_wind_speed);
}
