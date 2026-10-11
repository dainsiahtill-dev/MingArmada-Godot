shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

uniform sampler2D foam_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec3 foam_tint : source_color = vec3(0.83,0.96,1.0);
uniform float opacity = 1.0;
uniform vec2 uv_offset = vec2(0.0);
uniform bool billboard = false;
varying vec4 authored_color;

void vertex() {
	authored_color = COLOR;
	if (billboard) {
		MODELVIEW_MATRIX = VIEW_MATRIX * mat4(
			INV_VIEW_MATRIX[0]*length(MODEL_MATRIX[0].xyz),
			INV_VIEW_MATRIX[1]*length(MODEL_MATRIX[1].xyz),
			INV_VIEW_MATRIX[2]*length(MODEL_MATRIX[2].xyz),
			MODEL_MATRIX[3]);
	}
}

void fragment() {
	// Source RGB is almost constant; its original alpha defines the splash.
	// Vertex feathering is reserved for mist carriers and shoreline clipping.
	float mask = texture(foam_texture,UV+uv_offset).a;
	ALBEDO = foam_tint*authored_color.rgb;
	ALPHA = clamp(mask*authored_color.a*opacity,0.0,1.0);
}
