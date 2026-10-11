// Original water_spaarkle alpha shapes + wind-advected fine highlight layer.
// WaterSparkle/OceanWaterSparkle shader semantics motivate mask multiplication;
// no evidence claims this PNG's exact original shader binding has been recovered.
uniform sampler2D reference_original_sparkle_texture : repeat_enable, filter_linear_mipmap;
uniform float reference_original_sparkle_strength = 1.0;

// Returns a bounded display-RGB increment for the existing optical expression.
// Neither geometry nor wave descriptors are changed; no private shader TIME.
vec3 reference_original_micro_sparkle(vec2 world_xz,vec3 normal,float accepted_seconds,vec2 wind_direction,float wind_speed,float footprint,float view_distance,float light_alignment) {
	float wind_length=length(wind_direction);
	vec2 wind=wind_length>.00001?wind_direction/wind_length:vec2(1.0,0.0);
	vec2 across=vec2(-wind.y,wind.x);
	vec2 p=vec2(dot(world_xz,across),dot(world_xz,wind));
	float speed=clamp(wind_speed,0.0,60.0);
	float drift=accepted_seconds*(.008+speed*.00055);
	vec2 uv_a=p*vec2(.052,.046)-vec2(0.0,drift)+normal.xz*.018;
	// Different scale/rotation/phase modulates bright flecks without a common
	// square lattice. Source RGB is almost constant; the sparse image is alpha.
	vec2 uv_b=mat2(vec2(.891,.454),vec2(-.454,.891))*p*vec2(.073,.061)+vec2(drift*.31,-drift*.47)+vec2(.37,.19);
	float alpha_a=texture(reference_original_sparkle_texture,uv_a).a;
	float alpha_b=texture(reference_original_sparkle_texture,uv_b).a;
	// Unresolved alpha averages to ~.096, below the first threshold, rather
	// than turning the sea white. Explicit footprint/distance fades remain.
	float flecks=smoothstep(.18,.72,alpha_a)*(.35+.65*smoothstep(.08,.55,alpha_b));
	float resolved=1.0-smoothstep(.18,1.3,max(footprint,0.0));
	float visible=1.0-smoothstep(180.0,800.0,max(view_distance,0.0));
	float moving=smoothstep(.5,16.0,speed);
	float lit=.20+.80*pow(clamp(light_alignment,0.0,1.0),16.0);
	float energy=flecks*resolved*visible*moving*lit*clamp(reference_original_sparkle_strength,0.0,1.0);
	return vec3(.045,.061,.064)*energy;
}
