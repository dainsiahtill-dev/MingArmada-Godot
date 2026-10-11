uniform sampler2D shore_height_texture : repeat_disable, filter_linear;
uniform vec4 shore_bounds = vec4(0.0);
uniform bool has_shore_field = false;
uniform bool coastal_attenuation = false;

float coastal_wave_height(vec2 point, float seconds) {
	float wave = configured_wave_height(point, seconds);
	if (!coastal_attenuation || !has_shore_field) { return wave; }
	vec2 uv = (point - shore_bounds.xy) / (shore_bounds.zw - shore_bounds.xy);
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return wave; }
	float depth = -texture(shore_height_texture, uv).r;
	return wave * smoothstep(0.0, 8.0, depth);
}
