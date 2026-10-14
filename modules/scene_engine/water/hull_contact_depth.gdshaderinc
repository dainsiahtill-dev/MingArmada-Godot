// The ocean is a transparent depth-writing surface. Use the opaque depth copy
// to hide contact foam behind hulls/terrain without hard ocean cuts.
uniform sampler2D contact_scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
float contact_depth_fade(vec2 screen_uv, float view_z, mat4 inverse_projection, float distance) {
	float depth=texture(contact_scene_depth,screen_uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc=vec3(screen_uv*2.0-1.0,depth*2.0-1.0);
#else
	vec3 ndc=vec3(screen_uv*2.0-1.0,depth);
#endif
	vec4 scene=inverse_projection*vec4(ndc,1.0);
	if (abs(scene.w)<0.00001) return 1.0;
	return smoothstep(0.0,distance,-scene.z/scene.w+view_z);
}
