shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never;
#include "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc"
uniform sampler2D shore_texture : source_color, filter_linear_mipmap, repeat_disable;
uniform sampler2D normal_texture : filter_linear_mipmap, repeat_enable;
uniform float surface_visual_scale = 1.0;
uniform mat3 texture_matrix;
uniform float controller_alpha = 0.0;
uniform float packet_u_metres = 4.0;
uniform float source_crest_u = 0.80859375;
uniform float crest_half_width = 0.40;
uniform float foam_tail_length = 1.35;
uniform float surface_tide = 0.0;
uniform float source_alpha_threshold = 0.078431372549;
uniform vec4 source_uv_bounds = vec4(0.0,0.0,3.0,1.0);
varying vec2 original_uv;
varying vec2 world_xz;
void vertex() {
	vec3 point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
	world_xz=point.xz;
	point.y=surface_tide+reference_game_height(point.xz,simulation_time)+0.055;
	VERTEX=(inverse(MODEL_MATRIX)*vec4(point,1.0)).xyz;
	original_uv=UV;
	UV=(texture_matrix*vec3(UV,1.0)).xy;
}
void fragment() {
	if (height_at(world_xz)>surface_tide+0.015) discard;
	vec2 sample_uv=UV;
	float behind_front=(0.75-UV.x)*packet_u_metres;
	// GAME fusion adapter: the real curved ocean crest is the only advancing
	// trajectory. Reanchor the strongest mean-alpha source column to that crest,
	// rather than intersecting
	// a separate slow Native front with a narrow gate and losing both heads.
	// Recovered scale still sets metres per source U, recovered alpha controls
	// each paired segment's life. Translation remains exact source diagnostics;
	// it is deliberately not a second rendered 30-second trajectory here.
	if (has_coast_distance&&has_shore_field) {
		float distance=reference_coast_distance(world_xz);
		float shore_noise=texture(normal_texture,world_xz*0.06*surface_visual_scale+vec2(simulation_time*0.012,-simulation_time*0.009)).g;
		float phase=coastal_advance_phase(distance,world_xz,simulation_time,shore_noise);
		behind_front=coastal_advance_offset(phase);
		sample_uv.x=source_crest_u-behind_front/packet_u_metres;
	}
	vec4 color=texture(shore_texture,sample_uv);
	// Native coarse mips have nonzero edge alpha. CLAMP_TO_EDGE alone extends
	// those border pixels through the translated UV domain as pale rectangular
	// tails. Keep original mips but give the moving image a finite, soft border.
	vec2 texel=vec2(1.0)/vec2(textureSize(shore_texture,0));
	vec2 filter_width=max(fwidth(sample_uv),texel)*1.5;
	vec2 sample_edge=smoothstep(vec2(0.0),filter_width,sample_uv)*smoothstep(vec2(0.0),filter_width,vec2(1.0)-sample_uv);
	vec2 local=(original_uv-source_uv_bounds.xy)/(source_uv_bounds.zw-source_uv_bounds.xy);
	float feather=smoothstep(0.0,0.08,local.y)*smoothstep(0.0,0.08,1.0-local.y);
	feather*=smoothstep(0.0,0.02,local.x)*smoothstep(0.0,0.02,1.0-local.x);
	feather*=sample_edge.x*sample_edge.y;
	// Adapt the original alpha image into a short, thin advancing stroke and
	// weaker broken residue. Drawing its complete ellipse made white pads.
	// Positive distance lies offshore behind the fused inward-moving front.
	float native_filter=max(fwidth(sample_uv.x)*packet_u_metres,0.025);
	float crest=1.0-smoothstep(crest_half_width*0.35,crest_half_width+native_filter,abs(behind_front));
	crest*=min(crest_half_width/(crest_half_width+native_filter),1.0);
	float residue=smoothstep(0.03,0.22+native_filter,behind_front)*(1.0-smoothstep(foam_tail_length*0.35,foam_tail_length,behind_front));
	float thin_wash=max(crest,residue*0.36);
	float shore_zone=has_coast_distance?1.0-smoothstep(9.0,13.5,reference_coast_distance(world_xz)):1.0;
	ALBEDO=color.rgb;
	ALPHA=color.a*controller_alpha*feather*thin_wash*shore_zone;
	// Native DXT3 alpha is quantized to 1/15. Drawing its one-step tail below
	// the authored threshold turned invisible water into hazy straight marks.
	if (ALPHA<source_alpha_threshold) discard;
}
