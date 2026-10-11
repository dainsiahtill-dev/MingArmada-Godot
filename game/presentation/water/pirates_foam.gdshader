shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 foam_tint : source_color = vec3(0.82, 0.94, 0.96);
uniform float opacity : hint_range(0.0, 1.0) = 1.0;
uniform float alpha_floor = 0.0;
uniform bool ribbon = false;
uniform bool billboard = false;
varying vec4 trail_color;

void vertex() {
	trail_color = COLOR;
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0] * length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1] * length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2] * length(MODEL_MATRIX[2].xyz),
			MODEL_MATRIX[3]);
	}
}

void fragment() {
	vec4 source = texture(foam_texture, UV);
	float mask = smoothstep(alpha_floor, 0.72, source.a);
	float edge = smoothstep(0.0, 0.22, UV.x) * (1.0 - smoothstep(0.78, 1.0, UV.x));
	if (ribbon) {
		// Pak3 froth is a constant cyan RGB strip: only its alpha is a mask.
		float detail = smoothstep(0.134, 0.75, texture(detail_texture, vec2(UV.x, UV.y * 2.4)).a);
		// Detail modulates existing foam; never fills transparent texture gaps.
		mask = smoothstep(max(alpha_floor, 0.12), 0.82, source.a) * mix(0.35, 1.0, detail);
	} else if (billboard) {
		float radius = length((UV - vec2(0.5)) * 2.0);
		edge = 1.0 - smoothstep(0.55, 1.0, radius);
		float detail = texture(detail_texture, UV).a;
		mask = smoothstep(0.008, 0.40, source.a) * mix(0.60, 1.0, detail);
	} else {
		edge *= smoothstep(0.0, 0.13, UV.y) * (1.0 - smoothstep(0.87, 1.0, UV.y));
	}
	ALBEDO = foam_tint;
	ALPHA = mask * edge * opacity * trail_color.a;
}
