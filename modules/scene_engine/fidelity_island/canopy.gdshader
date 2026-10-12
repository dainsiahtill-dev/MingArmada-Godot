shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_always;

uniform sampler2D original_image : source_color, filter_linear_mipmap, repeat_enable;
uniform bool is_canopy = true;
uniform vec4 cxd[64];
uniform float native_unit_scale = 1.0;
uniform vec3 light_direction = vec3(0.0, -1.0, 0.0);
uniform vec3 light_color = vec3(1.0);
uniform vec3 ambient_color = vec3(0.45);
uniform float ambient_alpha = 0.225;
uniform vec3 material_ambient = vec3(1.0);
uniform vec3 material_diffuse = vec3(1.0);
uniform vec3 material_emissive = vec3(0.0);
uniform float material_alpha = 1.0;
uniform float alpha_threshold = 0.2745098039215686;
uniform bool custom_fog = false;
uniform vec3 fog_values = vec3(0.00003333333333333, 0.4, 1.6666667);
uniform vec3 fog_color = vec3(0.65, 0.77, 0.84);

varying vec3 original_lighting;
varying float original_cull;
varying float original_fog;

void vertex() {
	vec4 control = vec4(0.0, 1.0, 1.0, 0.0);
	if (is_canopy) {
		// Original Geometry5C5860 bytes enter CUSTOM0 unchanged. The native
		// C8/C78 map is (1,10,8,.5) and (6,.04,0,1), not the stale comments.
		vec4 packed_color = CUSTOM0 / 255.0;
		float fx = packed_color.b;
		float fy = packed_color.a;
		int k = int((packed_color.r * 6.0 + 0.04) * 8.0 + (packed_color.g * 6.0 + 0.04));
		control = cxd[k] * (1.0-fx) * (1.0-fy)
			+ cxd[k+8] * fx * (1.0-fy)
			+ cxd[k+1] * (1.0-fx) * fy
			+ cxd[k+9] * fx * fy;
		VERTEX.y += control.x * native_unit_scale;
		vec3 light = clamp(dot(-light_direction, NORMAL) * light_color + ambient_color, vec3(0.0), vec3(1.0));
		original_lighting = min(1.0, control.z + ambient_alpha) * light;
	} else {
		original_lighting = clamp(max(0.0, dot(-light_direction, NORMAL)) * light_color * material_diffuse
			+ ambient_color * material_ambient + material_emissive, vec3(0.0), vec3(1.0));
	}
	// Exact mode uses offset0/keep1. Formal-world adaptation uses one height
	// correction per recovered tree group and an authority/building mask, while
	// retaining the original rigid geometry, CXD and packed-color interpolation.
	VERTEX.y += CUSTOM1.x;
	original_cull = min(control.y - 0.5, CUSTOM1.y - 0.5);
	vec3 view_position = (MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = length(view_position) * fog_values.x;
	original_fog = clamp(step(fog_values.y, n) * (n-fog_values.y) * fog_values.z, 0.0, 1.0);
}

void fragment() {
	if (original_cull < 0.0) { discard; }
	vec4 texel = texture(original_image, UV);
	float alpha = texel.a * material_alpha;
	// TCanopy overrides the NIF22 threshold with GREATER70/255. Palm keeps
	// its authored GREATER75/255. Equality must be discarded in both paths.
	if (alpha <= alpha_threshold) { discard; }
	vec3 color = texel.rgb * original_lighting;
	if (custom_fog) { color = mix(color, fog_color, original_fog); }
	ALBEDO = color;
	ALPHA = alpha;
}
