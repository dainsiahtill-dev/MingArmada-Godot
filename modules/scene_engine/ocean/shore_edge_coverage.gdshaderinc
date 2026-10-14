#ifndef SHORE_EDGE_COVERAGE_INCLUDED
#define SHORE_EDGE_COVERAGE_INCLUDED
// Pure local coverage. Width and all clearances are vertical world metres.
float reference_shore_edge_coverage(float dry_clearance, float water_clearance, float optical_vertical_depth, float width) {
	if(width <= 0.0) return 1.0;
	float terrain_clearance = min(dry_clearance,water_clearance);
	float clearance = max(0.0,min(terrain_clearance,optical_vertical_depth));
	// Screen-depth edges may belong to ships: beyond this actual terrain band
	// they must not fade deep water. Smoothly disable the correction, not step it.
	float near_terrain = 1.0-smoothstep(width,2.0*width,max(terrain_clearance,0.0));
	return mix(1.0,smoothstep(0.0,width,clearance),near_terrain);
}

// Preserve both endpoints; lower weight only reveals more background locally.
float reference_shore_edge_water_weight(float coverage, float weight) {
	return coverage*mix(clamp(weight,0.0,1.0),1.0,coverage);
}
#endif
