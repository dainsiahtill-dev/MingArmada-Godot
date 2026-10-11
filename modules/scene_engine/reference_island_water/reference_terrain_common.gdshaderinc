// Direct display-space math port from island-water/demo/shaders.mjs common.
vec3 reference_sky(vec3 ray) {
	float h = clamp(ray.y, 0.0, 1.0);
	vec3 col = mix(vec3(0.55, 0.76, 0.81), vec3(0.13, 0.37, 0.58), pow(h, 0.55));
	col = mix(col, vec3(0.80, 0.55, 0.35), clamp((1.0-u_sun.y)*0.45, 0.0, 0.5)*(1.0-h));
	float s = max(dot(ray, u_sun), 0.0);
	return col + u_sun_color*(pow(s, 320.0)*1.1+pow(s, 16.0)*0.1);
}

float reference_noise(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7)))*43758.5453);
}

float reference_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(reference_noise(i), reference_noise(i+vec2(1.0,0.0)), f.x), mix(reference_noise(i+vec2(0.0,1.0)), reference_noise(i+vec2(1.0)), f.x), f.y);
}

vec3 reference_display_to_linear(vec3 display_color) {
	vec3 low = display_color/12.92;
	vec3 high = pow(max((display_color+vec3(0.055))/1.055, vec3(0.0)), vec3(2.4));
	return mix(high, low, lessThanEqual(display_color, vec3(0.04045)));
}
