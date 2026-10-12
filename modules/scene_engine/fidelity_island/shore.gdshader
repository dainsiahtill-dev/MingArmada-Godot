shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
#include "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"

uniform sampler2D shore_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform mat3 texture_matrix;
uniform float controller_alpha = 0.0;
uniform float source_alpha_threshold = 0.078431372549;
uniform float edge_softness = 0.0;
uniform bool follow_surface = false;
uniform float surface_tide = 0.0;
uniform float surface_height_offset = 0.035;
varying vec2 original_uv;

void vertex() {
	if (follow_surface) {
		// Godot presentation adaptation only: the exact same current five-wave
		// and coastal-height contract as the retained formal game's water.
		// Mapped render meshes are refined for this wavelength in shore.gd;
		// the source observer leaves this disabled and retains its fixed mesh.
		vec3 world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz;
		world_position.y = surface_tide
			+ reference_game_height(world_position.xz,simulation_time)
			+ surface_height_offset;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_position,1.0)).xyz;
	}
	original_uv = UV;
	UV = (texture_matrix * vec3(UV,1.0)).xy;
}

void fragment() {
	vec4 color = texture(shore_texture, UV);
	float edge = 1.0;
	// Exact mode uses the authored texture's transparent ends. This optional
	// small extra feather is explicitly a mapped Godot presentation adaptation.
	if (edge_softness > 0.0) {
		edge = smoothstep(0.0,edge_softness,original_uv.y)
			* smoothstep(0.0,edge_softness,1.0-original_uv.y);
	}
	float alpha = color.a * controller_alpha * edge;
	if (alpha < source_alpha_threshold) { discard; }
	ALBEDO = color.rgb;
	ALPHA = alpha;
}
