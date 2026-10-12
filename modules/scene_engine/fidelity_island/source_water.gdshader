shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;

// Completed demo's VSOceanWaterEMBM / PSOceanWaterEMBM_NR observation branch.
// Raw DDS display RGB; the alpha-.4 water draw precedes the original terrain.
// Godot uses a composed display color and a no-depth-write transparent queue
// draw so submerged source surf meshes remain visible below the Z0 plane.
#include "res://modules/scene_engine/fidelity_island/source_water_color.gdshaderinc"
uniform sampler2D source_opaque_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform bool source_terrain_composition_enabled = false;
uniform vec2 source_terrain_min = vec2(0.0);
uniform vec2 source_terrain_max = vec2(0.0);
varying vec2 source_uv0;
varying vec2 source_uv1;
varying float source_fog;

vec3 display_to_linear(vec3 color) {
	vec3 low = color / 12.92;
	vec3 high = pow(max((color + vec3(0.055)) / 1.055, vec3(0.0)), vec3(2.4));
	return mix(high, low, lessThanEqual(color, vec3(0.04045)));
}

void vertex() {
	float period = source_time >= 0.0 ? 45.0 : -45.0;
	float phase = period * fract(source_time / period) * 0.0222222;
	vec2 U = (UV * source_scale) * 45.0;
	source_uv0 = vec2(U.x + phase, U.y);
	source_uv1 = vec2(1.0 - U.x, 1.0 - U.y - phase);
	vec4 clip = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	// Godot uses reverse-Z. Recover the completed WebGL camera's forward D3D
	// clip Z before applying the recovered source fog registers.
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	float forward_clip_z = (clip.w - clip.z) * 0.5;
	#else
	float forward_clip_z = clip.w - clip.z;
	#endif
	source_fog = clamp((forward_clip_z / source_fog_values.x - source_fog_values.y) / source_fog_values.z, 0.0, 1.0);
}

void fragment() {
	if (source_terrain_composition_enabled) {
		float depth = texture(source_opaque_depth, SCREEN_UV).r;
		#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, depth) * 2.0 - 1.0;
		#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth);
		#endif
		vec4 opaque_view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
		vec3 opaque = (INV_VIEW_MATRIX * vec4(opaque_view.xyz / opaque_view.w, 1.0)).xyz;
		// The opaque source field has already composed the earlier NR draw with
		// UnderDark and additive layers. Repainting it would erase its weight fade.
		if (depth > 0.0 && opaque.y <= source_water_plane_y + 0.01 &&
			all(greaterThanEqual(opaque.xz, source_terrain_min - vec2(0.1))) &&
			all(lessThanEqual(opaque.xz, source_terrain_max + vec2(0.1)))) discard;
	}
	vec3 A = clamp(source_water_ambient * 1.5, vec3(0.0), vec3(1.0));
	vec3 P = texture(source_water_texture, source_uv0).rgb * texture(source_water_texture, source_uv1).rgb;
	vec3 nr = A * P + (vec3(1.0) - A) * A;
	vec3 fogged = mix(nr, source_fog_color, source_fog_enabled ? source_fog : 0.0);
	vec3 completed = fogged * 0.4 + source_fog_color * 0.6;
	ALBEDO = display_to_linear(clamp(completed, vec3(0.0), vec3(1.0)));
	ALPHA = 1.0;
}
