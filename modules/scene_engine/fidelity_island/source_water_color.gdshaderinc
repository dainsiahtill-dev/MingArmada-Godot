// Shared original NR backdrop; raw source DDS display RGB, not local light.
uniform sampler2D source_water_texture : repeat_enable, filter_linear_mipmap;
uniform float source_time = 12.0;
uniform float source_scale = 1.0;
uniform vec3 source_water_ambient = vec3(0.48882356, 0.57509804, 0.76333338);
uniform vec3 source_fog_color = vec3(0.45882356, 0.69411767, 0.85098046);
uniform vec3 source_fog_values = vec3(30000.0, 0.4, 0.6);
uniform bool source_fog_enabled = true;
uniform vec2 source_water_uv_row_x = vec2(0.00045, 0.0);
uniform vec2 source_water_uv_row_z = vec2(0.0, 0.00045);
uniform vec2 source_water_uv_offset = vec2(0.0);
uniform float source_water_plane_y = 0.0;
uniform float source_water_tile_span = 100000.0;

float completed_forward_clip_z(vec4 clip) {
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	return (clip.w - clip.z) * 0.5;
	#else
	return clip.w - clip.z;
	#endif
}

float completed_source_fog(vec3 point, mat4 view, mat4 projection) {
	vec4 clip = projection * view * vec4(point, 1.0);
	return clamp((completed_forward_clip_z(clip) / source_fog_values.x - source_fog_values.y) / source_fog_values.z, 0.0, 1.0);
}

vec2 completed_water_uv(vec2 world_xz) {
	return vec2(dot(source_water_uv_row_x, world_xz), dot(source_water_uv_row_z, world_xz)) + source_water_uv_offset;
}

float completed_pool_fog(vec3 point, mat4 view, mat4 projection) {
	// The source clamps fog at the four original huge-pool vertices before
	// perspective-correct interpolation, not at each pixel's view depth.
	vec2 cell = fract(completed_water_uv(point.xz) / 45.0);
	vec2 corner = point.xz - cell * source_water_tile_span;
	float a = completed_source_fog(vec3(corner.x, source_water_plane_y, corner.y), view, projection);
	float b = completed_source_fog(vec3(corner.x, source_water_plane_y, corner.y + source_water_tile_span), view, projection);
	float c = completed_source_fog(vec3(corner.x + source_water_tile_span, source_water_plane_y, corner.y), view, projection);
	float d = completed_source_fog(vec3(corner.x + source_water_tile_span, source_water_plane_y, corner.y + source_water_tile_span), view, projection);
	if (cell.x + cell.y <= 1.0) return a * (1.0 - cell.x - cell.y) + b * cell.y + c * cell.x;
	return b * (1.0 - cell.x) + c * (1.0 - cell.y) + d * (cell.x + cell.y - 1.0);
}

vec3 completed_nr_background(vec2 uv, float fog) {
	float period = source_time >= 0.0 ? 45.0 : -45.0;
	float phase = period * fract(source_time / period) * 0.0222222;
	vec2 U = uv * source_scale;
	vec2 first = vec2(U.x + phase, U.y);
	vec2 second = vec2(1.0 - U.x, 1.0 - U.y - phase);
	vec3 A = clamp(source_water_ambient * 1.5, vec3(0.0), vec3(1.0));
	vec3 P = texture(source_water_texture, first).rgb * texture(source_water_texture, second).rgb;
	vec3 nr = A * P + (vec3(1.0) - A) * A;
	vec3 fogged = mix(nr, source_fog_color, source_fog_enabled ? fog : 0.0);
	return fogged * 0.4 + source_fog_color * 0.6;
}

vec3 completed_background_at(vec3 surface_point, vec3 eye, mat4 view, mat4 projection) {
	// Sample the earlier water draw at this pixel's water-plane ray hit. Using
	// the submerged terrain XZ would slide the background at oblique cameras.
	vec3 ray = surface_point - eye;
	float t = (source_water_plane_y - eye.y) / min(ray.y, -0.000001);
	vec3 water = eye + ray * t;
	water.y = source_water_plane_y;
	return completed_nr_background(completed_water_uv(water.xz), completed_pool_fog(water, view, projection));
}
