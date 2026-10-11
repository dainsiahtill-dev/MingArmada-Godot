// Fragment-only light and foam detail. No displacement or independent clock.
vec2 coastal_cell_seed(vec2 cell) {
	vec2 value = vec2(dot(cell, vec2(127.1, 311.7)), dot(cell, vec2(269.5, 183.3)));
	return fract(sin(value) * 43758.5453);
}

float coastal_caustic_network(vec2 world_xz, float seconds, vec2 ripple) {
	// A slowly distorted cellular network reads as refracted light on the bottom,
	// rather than diagonal stripes sliding across the entire sea.
	vec2 p = world_xz * 0.28 + ripple * 0.32;
	p += vec2(sin(p.y * 0.9 + seconds * 0.32), cos(p.x * 0.8 - seconds * 0.27)) * 0.20;
	vec2 cell = floor(p);
	vec2 local = fract(p);
	float nearest = 8.0;
	float second = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 offset = vec2(float(x), float(y));
			vec2 seed = coastal_cell_seed(cell + offset);
			vec2 center = 0.5 + sin(seed * 6.2831853 + vec2(seconds * 0.23, -seconds * 0.19)) * 0.34;
			vec2 delta = offset + center - local;
			float distance_squared = dot(delta, delta);
			if (distance_squared < nearest) {
				second = nearest;
				nearest = distance_squared;
			} else {
				second = min(second, distance_squared);
			}
		}
	}
	float edge = max(second - nearest, 0.0);
	float antialias = max(fwidth(edge), 0.018);
	// A wider pixel filter must reduce line energy; otherwise distant cells turn
	// into a bright tiled blanket instead of faint light below the surface.
	float filtered_line = 1.0 - smoothstep(0.018, 0.055 + antialias, edge);
	return filtered_line * min(0.060 / antialias, 1.0);
}

vec3 coastal_sand_bottom(vec2 world_xz, vec2 ripple) {
	// The sand stays fixed in world space. Only its refracted image is distorted.
	vec2 p = world_xz + ripple * 0.65;
	float ripple_band = sin(p.x * 1.15 + sin(p.y * 0.37) * 1.6);
	float grain = fract(sin(dot(floor(p * 1.4), vec2(12.9898, 78.233))) * 43758.5453);
	float mottling = sin(p.x * 0.045 + sin(p.y * 0.033)) * cos(p.y * 0.061);
	return vec3(0.45, 0.69, 0.58) + vec3(ripple_band * 0.020 + grain * 0.012 + mottling * 0.032);
}

float coastal_foam_random(vec2 cell) {
	return fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453);
}

float coastal_foam_patch(vec2 p) {
	vec2 cell = floor(p);
	vec2 local = fract(p);
	vec2 blend = local * local * (3.0 - 2.0 * local);
	return mix(
		mix(coastal_foam_random(cell), coastal_foam_random(cell + vec2(1.0, 0.0)), blend.x),
		mix(coastal_foam_random(cell + vec2(0.0, 1.0)), coastal_foam_random(cell + vec2(1.0)), blend.x),
		blend.y
	);
}

float coastal_breaker_foam(float coast_distance, float shore_depth, float dry_height, vec2 world_xz, float seconds, float foam_noise, float shore_noise) {
	// The distance field contains genuine land/water crossings. A submerged bank
	// can show bottom light but cannot acquire a false circular surf outline.
	float wet = 1.0 - smoothstep(-0.10, 0.65, dry_height);
	float shoal = 1.0 - smoothstep(6.0, 11.0, shore_depth);
	float zone = (1.0 - smoothstep(19.0, 25.0, coast_distance)) * wet * shoal;
	float patch = coastal_foam_patch(world_xz * 0.075);
	float phase = coast_distance * 1.05 + seconds * 1.50;
	phase += (shore_noise - 0.5) * 1.15 + (patch - 0.5) * 0.80;
	// Positive offsets lie offshore of the advancing crest: water there has
	// already broken. Distance from that crest gives foam age without a new
	// clock or texture history. Use derivatives before wrapping the phase so
	// the cycle seam does not falsely widen the filter.
	float pixel_width = max(fwidth(phase) / 1.05, 0.035);
	float crest_offset = (fract(phase / 6.2831853 + 0.5) - 0.5) * (6.2831853 / 1.05);
	float front = 1.0 - smoothstep(0.12, 0.43 + pixel_width, abs(crest_offset));
	front *= min(0.43 / (0.43 + pixel_width), 1.0);
	float breakup = smoothstep(0.34, 0.64, patch * 0.78 + shore_noise * 0.22);
	// Resolve grains only when the screen footprint can show them. At distance
	// they converge to their coverage, rather than sparkling or becoming a net.
	float grain_visibility = 1.0 - smoothstep(0.14, 0.65, length(fwidth(world_xz)));
	float grain = coastal_foam_random(floor(world_xz * 2.25));
	float crest_grain = mix(0.58, smoothstep(0.30, 0.77, grain), grain_visibility);
	float tail_grain = mix(0.40, smoothstep(0.42, 0.88, grain), grain_visibility);
	float breaker = front * breakup * (0.35 + crest_grain * 0.65);
	// A roughly 2-second, 2.65 m trail follows outside the narrow white head.
	// Its ramp starts at the head; opacity then decays before the next cycle.
	float tail_birth = smoothstep(-0.08 - pixel_width, 0.48 + pixel_width, crest_offset);
	float tail_life = 1.0 - smoothstep(0.55, 2.65, crest_offset);
	float tail_decay = exp(-max(crest_offset, 0.0) * 0.42);
	float tail = tail_birth * tail_life * tail_decay * breakup * (0.16 + tail_grain * 0.84) * 0.48;
	float erosion = smoothstep(0.30, 0.77, foam_noise);
	float shore_pulse = 0.30 + 0.70 * (0.5 + 0.5 * cos(phase));
	float lace = (1.0 - smoothstep(0.8, 3.1, coast_distance)) * erosion * breakup * shore_pulse * 0.30;
	float coast_energy = clamp(0.96 - coast_distance * 0.010, 0.0, 1.0);
	return clamp((breaker + tail + lace) * coast_energy * zone, 0.0, 0.82);
}
