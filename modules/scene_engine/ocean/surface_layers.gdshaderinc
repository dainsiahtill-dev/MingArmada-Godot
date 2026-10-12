// Fragment-only layers. Buoyancy and projected geometry retain their original waves.
uniform sampler2D reference_whitecaps_texture : repeat_enable, filter_linear_mipmap;
uniform vec2 surface_wind_direction = vec2(1.0, 0.0);
uniform float surface_wind_speed = 14.0;
uniform float surface_detail_strength = 0.09;
#include "res://modules/scene_engine/ocean/stochastic_alpha.gdshaderinc"
#include "res://modules/scene_engine/ocean/surface_detail_lod.gdshaderinc"

float reference_whitecap_coverage(vec2 p, vec3 macro_normal, float seconds, float view_distance, float height_above_tide) {
	vec2 wind_direction = length(surface_wind_direction) > .00001 ? normalize(surface_wind_direction) : vec2(1.0,0.0);
	vec2 across = vec2(-wind_direction.y, wind_direction.x);
	vec2 flow_space = vec2(dot(p, wind_direction), dot(p, across));
	float speed = clamp(surface_wind_speed,0.0,60.0);
	float drift = seconds * (0.012 + speed * 0.0007);
	// Original foam0024 carries a large front, not an isotropic noise tile.
	// Read it as small crest fragments with independent stable positions; retain
	// the wind bearing while varying orientation enough to remove matching stamps.
	vec2 uv_a = flow_space * vec2(0.12, 0.17) - vec2(drift * 2.7,0.0);
	vec2 uv_b = flow_space * vec2(0.163, 0.127) + vec2(drift * 1.3,-drift * .47) + vec2(.31,.73);
	float a = reference_stochastic_alpha(reference_whitecaps_texture,uv_a,17u,.38);
	float b = reference_stochastic_alpha(reference_whitecaps_texture,uv_b,71u,.53);
	float mask = smoothstep(0.23,0.73,a) * smoothstep(0.18,0.64,b);
	// Geometry-authoritative steep upper crests qualify; optical normal-map
	// bumps cannot paint foam on flat water. Shoreline breaking remains separate.
	float crest = smoothstep(0.08,0.25,length(macro_normal.xz));
	float upper_crest = smoothstep(0.05,0.65,height_above_tide);
	float wind = smoothstep(4.0,22.0,speed);
	// Gradually remove subpixel flecks in the distance; horizon never turns white.
	float detail = 1.0 - smoothstep(160.0, 850.0, view_distance);
	float resolved=min(reference_surface_alpha_visibility(reference_whitecaps_texture,uv_a,12.0),reference_surface_alpha_visibility(reference_whitecaps_texture,uv_b,12.0));
	return mask * crest * upper_crest * wind * detail * resolved * surface_detail_strength;
}

float reference_whitecap_coverage(vec2 p, vec3 normal, float seconds, float view_distance) {
	return reference_whitecap_coverage(p,normal,seconds,view_distance,1.0);
}

float reference_wind_glint(vec2 p, vec3 normal, float seconds) {
	vec2 across = vec2(-surface_wind_direction.y, surface_wind_direction.x);
	vec2 uv = vec2(dot(p, across) * 0.095, dot(p, surface_wind_direction) * 0.052);
	uv -= vec2(0.0, seconds * surface_wind_speed * 0.00055);
	float fleck = reference_stochastic_alpha(reference_sparkle_texture,uv + normal.xz * 0.022,113u,3.14159265);
	return smoothstep(0.48, 0.91, fleck) * smoothstep(1.0, 16.0, surface_wind_speed) * reference_surface_alpha_visibility(reference_sparkle_texture,uv,4.0);
}

float reference_surface_flecks(vec2 p,vec3 normal,float seconds,float light_alignment) {
	vec2 uv_a=p*.075+normal.xz*.025+vec2(seconds*.005,seconds*.003);
	vec2 uv_b=p.yx*.113+vec2(-seconds*.004,seconds*.006);
	float a=reference_stochastic_alpha(reference_sparkle_texture,uv_a,131u,3.14159265);
	float b=reference_stochastic_alpha(reference_sparkle_texture,uv_b,197u,3.14159265);
	float flecks=smoothstep(.39,.88,a)*smoothstep(.18,.71,b);
	float resolved=min(reference_surface_alpha_visibility(reference_sparkle_texture,uv_a,4.0),reference_surface_alpha_visibility(reference_sparkle_texture,uv_b,4.0));
	return flecks*(.04+.96*pow(clamp(light_alignment,0.0,1.0),18.0))*resolved;
}
