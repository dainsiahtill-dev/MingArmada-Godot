shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, fog_disabled;

uniform sampler2D original_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D original_clamped_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 original_material = vec4(1.0);
uniform vec3 source_environment_color = vec3(1.0);
uniform float display_opacity : hint_range(0.0, 1.0) = 1.0;
uniform float original_alpha_threshold = -1.0;
uniform mat3 original_uv_matrix = mat3(1.0);
uniform bool source_wrap_u = true;
uniform bool source_wrap_v = true;
uniform vec2 source_half_texel = vec2(0.0);
uniform bool source_billboard_enabled = false;
uniform mat3 source_billboard_rotation = mat3(1.0);
uniform vec3 source_billboard_origin = vec3(0.0);
uniform float source_billboard_scale = 1.0;
uniform mat4 source_billboard_relative = mat4(1.0);

mat3 source_mode0_view_rotation(mat3 parent_rotation, mat3 view_basis) {
	// Original 0x546230 mode0, expressed through the source->Godot axis map.
	// Source local Y is Godot -Z; the adjusted columns are X, Z, -Y.
	mat3 local = transpose(parent_rotation);
	vec3 direction = local * view_basis[2];
	vec3 up = local * view_basis[1];
	vec3 right = local * view_basis[0];
	float span = length(vec2(up.z, right.z));
	vec3 x_axis;
	vec3 source_y_axis;
	if (span <= 0.0000009999999974752427) {
		x_axis = -right;
		source_y_axis = -up;
	} else {
		float up_weight = -up.z / span;
		float right_weight = right.z / span;
		x_axis = up * right_weight + right * up_weight;
		source_y_axis = up * up_weight - right * right_weight;
	}
	return parent_rotation * mat3(x_axis, direction, -source_y_axis);
}

void vertex() {
	if (source_billboard_enabled) {
		vec3 original_local = (source_billboard_relative * vec4(VERTEX,1.0)).xyz;
		vec3 world_position = source_billboard_origin + source_mode0_view_rotation(source_billboard_rotation,mat3(INV_VIEW_MATRIX)) * original_local * source_billboard_scale;
		VERTEX = (inverse(MODEL_MATRIX) * vec4(world_position,1.0)).xyz;
	}
}

void fragment() {
	vec2 original_uv = (original_uv_matrix * vec3(UV, 1.0)).xy;
	// Actual source assets use WW clouds and CC fog. Hardware address state must
	// remain correct at every authored mip, including coarse border footprints.
	vec4 texel;
	if (source_wrap_u && source_wrap_v) texel=texture(original_texture,original_uv);
	else texel=texture(original_clamped_texture,original_uv);
	vec4 sample_color = texel * original_material;
	if (sample_color.a <= original_alpha_threshold) discard;
	ALBEDO = sample_color.rgb * source_environment_color;
	// Target weather strength follows the source alpha test, preserving its
	// authored cutoff even when clear-weather ground fog is very faint.
	ALPHA = sample_color.a * display_opacity;
}
