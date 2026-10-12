#ifndef MING_ARMADA_COASTAL_CAUSTICS_INCLUDED
#define MING_ARMADA_COASTAL_CAUSTICS_INCLUDED

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

#endif
