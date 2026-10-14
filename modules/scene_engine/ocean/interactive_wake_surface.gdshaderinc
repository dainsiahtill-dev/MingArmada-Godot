// One-way ship interaction. Published RGBA: height metres, dH/dX, dH/dZ,
// persistent foam density. Texture and world bounds belong to one publication.
uniform bool interactive_wake_enabled = false;
uniform sampler2D interactive_wake_surface : repeat_disable, filter_linear;
uniform sampler2D interactive_wake_foam_texture : repeat_enable, filter_linear_mipmap;
uniform vec4 interactive_wake_bounds = vec4(0.0);
uniform int interactive_wake_debug = 0;

vec4 interactive_wake_at(vec2 world_xz) {
	if(!interactive_wake_enabled) return vec4(0.0);
	vec2 span=interactive_wake_bounds.zw-interactive_wake_bounds.xy;
	if(any(lessThanEqual(span,vec2(0.0)))) return vec4(0.0);
	vec2 uv=(world_xz-interactive_wake_bounds.xy)/span;
	// Never clamp a nonzero edge pixel across the rest of the infinite ocean.
	if(any(lessThan(uv,vec2(0.0)))||any(greaterThan(uv,vec2(1.0)))) return vec4(0.0);
	vec4 field=textureLod(interactive_wake_surface,uv,0.0);
	// A visual dry gate supplements, but does not replace, solver land masking.
	if(mask_dry_terrain && height_at(world_xz)>u_tide+.035) return vec4(0.0);
	return field;
}

vec3 interactive_wake_normal(vec3 base_normal,vec2 height_gradient) {
	return normalize(vec3(base_normal.x/max(base_normal.y,.001)-height_gradient.x,1.0,
		base_normal.z/max(base_normal.y,.001)-height_gradient.y));
}

float interactive_wake_foam_grain(vec2 world_xz,float seconds) {
	// Actual original 256x64 froth alpha, with isotropic world texel density.
	// Two slow differently oriented samples animate bubble breakup; this is
	// shading detail only. Birth, transport and lifetime remain in the GPU field.
	mat2 rotation=mat2(vec2(.766044,.642788),vec2(-.642788,.766044));
	float a=texture(interactive_wake_foam_texture,world_xz*vec2(.18,.72)+seconds*vec2(.025,-.018)).a;
	float b=texture(interactive_wake_foam_texture,(rotation*world_xz)*vec2(.29,1.16)+seconds*vec2(-.016,.021)).a;
	return .22+.78*smoothstep(.18,.72,sqrt(max(a*b,0.0)));
}
