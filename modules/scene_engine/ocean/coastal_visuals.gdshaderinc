// Fragment-only light and foam detail. No displacement or independent clock.
uniform sampler2D coastal_foam_texture_a : repeat_enable, filter_linear_mipmap;
uniform sampler2D coastal_foam_texture_b : repeat_enable, filter_linear_mipmap;
uniform bool has_coastal_foam_textures = false;
uniform float shoreline_residue_strength : hint_range(0.0,1.0) = 1.0;

#include "res://modules/scene_engine/ocean/coastal_caustics.gdshaderinc"

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

float coastal_advance_phase(float coast_distance, vec2 world_xz, float seconds, float shore_noise) {
	float patch = coastal_foam_patch(world_xz * 0.075);
	return coast_distance * 1.05 + seconds * 1.50 + (shore_noise - 0.5) * 1.15 + (patch - 0.5) * 0.80;
}

float coastal_advance_offset(float phase) {
	return (fract(phase / 6.2831853 + 0.5) - 0.5) * (6.2831853 / 1.05);
}

float coastal_breaker_foam(float coast_distance, float shore_depth, float dry_height, vec2 world_xz, float seconds, float foam_noise, float shore_noise) {
	// The distance field contains genuine land/water crossings. A submerged bank
	// can show bottom light but cannot acquire a false circular surf outline.
	float wet = 1.0 - smoothstep(-0.10, 0.65, dry_height);
	float shoal = 1.0 - smoothstep(6.0, 11.0, shore_depth);
	float zone = (1.0 - smoothstep(19.0, 25.0, coast_distance)) * wet * shoal;
	float patch = coastal_foam_patch(world_xz * 0.075);
	float phase = coastal_advance_phase(coast_distance, world_xz, seconds, shore_noise);
	// Positive offsets lie offshore of the advancing crest: water there has
	// already broken. Distance from that crest gives foam age without a new
	// clock or texture history. Use derivatives before wrapping the phase so
	// the cycle seam does not falsely widen the filter.
	float pixel_width = max(fwidth(phase) / 1.05, 0.035);
	float crest_offset = coastal_advance_offset(phase);
	// The source masks are constant-color RGBA. Their alpha holds an uneven
	// front at V=.6-.72 and trailing foam below it. Feed crest distance to V,
	// so the photographed edge advances with the actual shoreline wave phase.
	float along_coast = (world_xz.x + world_xz.y * 0.47) * 0.085;
	float head_mask = 1.0;
	float tail_mask = 1.0;
	float residue_mask = 1.0;
	if (has_coastal_foam_textures) {
		vec2 head_uv = vec2(along_coast + seconds * 0.013, 0.65 + clamp(crest_offset, -0.5, 2.65) * 0.11);
		vec2 tail_uv = vec2(along_coast * 0.83 - seconds * 0.009 + 0.31, 0.69 + max(crest_offset, 0.0) * 0.112);
		// Unresolved reference texels converge to coverage, so their fine lattice
		// does not sparkle or become a white blanket at a distant coast.
		float mask_footprint = max(length(fwidth(head_uv)), length(fwidth(tail_uv)));
		float mask_detail = 1.0 - smoothstep(0.025, 0.12, mask_footprint);
		float head_alpha = texture(coastal_foam_texture_a, head_uv).a;
		float tail_alpha = texture(coastal_foam_texture_b, tail_uv).a;
		head_mask = mix(0.58, smoothstep(0.025, 0.46, head_alpha), mask_detail);
		// Older foam loses its fine threads first, exposing the clear shallows.
		float erosion_threshold = 0.025 + max(crest_offset, 0.0) * 0.065;
		tail_mask = mix(0.24, smoothstep(erosion_threshold, erosion_threshold + 0.24, tail_alpha), mask_detail);
		float residue_alpha = texture(coastal_foam_texture_b, vec2(along_coast * 0.79 + seconds * 0.006, 0.83 + (shore_noise - 0.5) * 0.08)).a;
		residue_mask = mix(0.22, smoothstep(0.08, 0.45, residue_alpha), mask_detail);
	}
	float front = 1.0 - smoothstep(0.12, 0.43 + pixel_width, abs(crest_offset));
	front *= min(0.43 / (0.43 + pixel_width), 1.0);
	// Adjacent advancing fronts use different coverage. The cycle boundary lies
	// opposite the crest, where this wave has already faded, so the irregular
	// sections change between waves without popping on a visible head.
	float cycle = floor(phase / 6.2831853 + 0.5);
	float cycle_patch = coastal_foam_patch(world_xz * 0.11 + vec2(cycle * 3.731, cycle * 8.137));
	float breakup = smoothstep(0.34, 0.64, patch * 0.48 + shore_noise * 0.22 + cycle_patch * 0.30);
	// Resolve grains only when the screen footprint can show them. At distance
	// they converge to their coverage, rather than sparkling or becoming a net.
	float grain_visibility = 1.0 - smoothstep(0.14, 0.65, length(fwidth(world_xz)));
	// Continuous filtered grain: hashing floored world cells stamped visible
	// 0.444 m square tiles along the wave heads in close native GPU captures.
	float grain = coastal_foam_patch(world_xz * 2.25);
	float crest_grain = mix(0.58, smoothstep(0.30, 0.77, grain), grain_visibility);
	float tail_grain = mix(0.40, smoothstep(0.42, 0.88, grain), grain_visibility);
	float breaker = front * breakup * (0.35 + crest_grain * 0.65) * head_mask;
	// A roughly 2-second, 2.65 m trail follows outside the narrow white head.
	// Its ramp starts at the head; opacity then decays before the next cycle.
	float tail_birth = smoothstep(-0.08 - pixel_width, 0.48 + pixel_width, crest_offset);
	float tail_life = 1.0 - smoothstep(0.55, 2.65, crest_offset);
	float tail_decay = exp(-max(crest_offset, 0.0) * 0.42);
	float tail = tail_birth * tail_life * tail_decay * breakup * (0.16 + tail_grain * 0.84) * 0.48 * tail_mask;
	float erosion = smoothstep(0.30, 0.77, foam_noise);
	float shore_pulse = 0.30 + 0.70 * (0.5 + 0.5 * cos(phase));
	// Contact lace remains continuous through the invisible wave-cycle seam.
	// Only the moving head/trail use the changing per-wave coverage above.
	float contact_breakup = smoothstep(0.34, 0.64, patch * 0.78 + shore_noise * 0.22);
	float lace = (1.0 - smoothstep(0.8, 3.1, coast_distance)) * erosion * contact_breakup * shore_pulse * 0.30 * residue_mask * shoreline_residue_strength;
	float coast_energy = clamp(0.96 - coast_distance * 0.010, 0.0, 1.0);
	return clamp((breaker + tail + lace) * coast_energy * zone, 0.0, 0.82);
}
