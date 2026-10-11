// Local sand/water transition and submerged terrain contribution only.
// Original dynamic lace, normal textures, palette, reflection and waves stay intact.
float reference_bottom_visibility(float ground_depth, float border_distance) {
	return (1.0-smoothstep(8.0,22.0,max(ground_depth,0.0)))*smoothstep(0.0,48.0,max(border_distance,0.0));
}

float reference_bottom_gate(float ground_difference, float below_surface) {
	return (1.0-smoothstep(2.0,6.0,max(ground_difference,0.0)))*smoothstep(0.25,2.0,max(below_surface,0.0));
}

float reference_shore_transition(float shore_depth, float coast_distance) {
	return (1.0-smoothstep(0.3,3.2,max(shore_depth,0.0)))*(1.0-smoothstep(3.0,14.0,max(coast_distance,0.0)));
}

float reference_bottom_window(vec2 point) {
	vec4 area=shore_bounds;
	if(has_reference_near_field)area=reference_near_bounds;
	if(!has_reference_near_field&&!has_shore_field)return 0.0;
	vec4 edges=vec4(point-area.xy,area.zw-point);
	return min(min(edges.x,edges.y),min(edges.z,edges.w));
}

vec3 reference_opaque_world(vec2 uv,mat4 inverse_projection,mat4 inverse_view) {
	float depth=texture(u_depth,uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc=vec3(uv,depth)*2.0-1.0;
	#else
	vec3 ndc=vec3(uv*2.0-1.0,depth);
	#endif
	vec4 point=inverse_view*inverse_projection*vec4(ndc,1.0);
	return point.xyz/point.w;
}
