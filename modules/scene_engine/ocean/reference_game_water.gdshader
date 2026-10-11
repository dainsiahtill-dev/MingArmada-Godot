// Formal fusion: source planar/depth optics and actual-terrain foam, with the
// approved native color palette, advected normal texture and alpha surf layers.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_always;
#include "res://modules/scene_engine/reference_island_water/source_common.gdshaderinc"
#include "res://modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc"

// Formal game keeps the authoritative five-wave physics profile.
#include "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"

uniform float u_strength = 1.0;
uniform sampler2D u_scene : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D u_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D u_reflection : repeat_disable, filter_linear;

uniform mat4 u_reflection_vp;


uniform float u_foam_width = 1.5;
uniform bool u_use_reflection = true;
uniform bool u_foam = true;
uniform bool u_refraction_enabled = true;
uniform bool u_caustics = true;
uniform sampler2D normal_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D reference_sparkle_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D reference_deep_texture : repeat_enable, filter_linear_mipmap;
uniform sampler2D reference_surface_texture : repeat_enable, filter_linear_mipmap;
uniform bool has_reference_water_textures = false;
uniform vec3 offshore_color = vec3(.12,.48,.66);
uniform vec3 shallow_color = vec3(.18,.73,.73);
#include "res://modules/scene_engine/ocean/coastal_visuals.gdshaderinc"
#include "res://modules/scene_engine/ocean/surface_layers.gdshaderinc"
#include "res://modules/scene_engine/ocean/reference_shore_foam.gdshaderinc"
// Stable formal game metadata/API aliases; source formulas use u_* uniforms.
uniform int visual_style = 1;
uniform bool surface_optics_enabled = true;
uniform bool surface_reflection_enabled = true;
uniform bool surface_refraction_enabled = true;
uniform int surface_reflection_steps = 0;
varying vec3 v_world;
varying vec3 v_normal;

vec3 source_texel(vec3 linear_color) {
	return clamp(reference_to_display(linear_color),vec3(0.0),vec3(1.0));
}
vec3 sample_source_scene(vec2 uv) {
	// WebGL RGBA8 LINEAR filters source display RGB. Godot stores HDR linear
	// light, so convert each texel before the same bilinear interpolation.
	// Values are never rounded after filtering.
	ivec2 size=textureSize(u_scene,0);
	vec2 pixel=uv*vec2(size)-.5;
	ivec2 i=ivec2(floor(pixel));vec2 f=fract(pixel);
	vec3 a=source_texel(texelFetch(u_scene,clamp(i,ivec2(0),size-ivec2(1)),0).rgb);
	vec3 b=source_texel(texelFetch(u_scene,clamp(i+ivec2(1,0),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 c=source_texel(texelFetch(u_scene,clamp(i+ivec2(0,1),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 d=source_texel(texelFetch(u_scene,clamp(i+ivec2(1),ivec2(0),size-ivec2(1)),0).rgb);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
vec3 sample_source_reflection(vec2 uv) {
	// Separate entry point is required by Godot for samplers with different hints.
	ivec2 size=textureSize(u_reflection,0);
	vec2 pixel=uv*vec2(size)-.5;
	ivec2 i=ivec2(floor(pixel));vec2 f=fract(pixel);
	vec3 a=source_texel(texelFetch(u_reflection,clamp(i,ivec2(0),size-ivec2(1)),0).rgb);
	vec3 b=source_texel(texelFetch(u_reflection,clamp(i+ivec2(1,0),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 c=source_texel(texelFetch(u_reflection,clamp(i+ivec2(0,1),ivec2(0),size-ivec2(1)),0).rgb);
	vec3 d=source_texel(texelFetch(u_reflection,clamp(i+ivec2(1),ivec2(0),size-ivec2(1)),0).rgb);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
// Godot reverse-Z and arbitrary lens: depth belongs to the main viewport.
// This replaces the source's fixed WebGL .3/1200 linearDepth expression only.
float linear_depth(vec2 uv,mat4 inverse_projection) {
	float depth=texture(u_depth,uv).r;
	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc=vec3(uv,depth)*2.0-1.0;
	#else
	vec3 ndc=vec3(uv*2.0-1.0,depth);
	#endif
	vec4 view=inverse_projection*vec4(ndc,1.0);
	return -view.z/view.w;
}
void vertex() {
  vec2 base=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
  v_world=vec3(base.x,u_tide+reference_game_height(base,simulation_time),base.y);
  v_normal=reference_game_normal(base,simulation_time);
  VERTEX=(inverse(MODEL_MATRIX)*vec4(v_world,1.0)).xyz;
  NORMAL=inverse(mat3(MODEL_MATRIX))*v_normal;
}
void fragment() {
	vec2 screen_uv=SCREEN_UV;
	float footprint=max(length(dFdx(v_world.xz)),length(dFdy(v_world.xz)));
	float detail_filter=1.0-smoothstep(1.4,5.0,footprint);
	// Preserve the old three advected texture scales, orienting tangent XY into
	// world XZ. Independent rotated flows break the source's sine checkerboard.
	vec2 wind=surface_wind_direction;
	vec2 across=vec2(-wind.y,wind.x);
	vec2 flow_space=vec2(dot(v_world.xz,wind),dot(v_world.xz,across));
	float flow_speed=.25+clamp(surface_wind_speed/14.0,0.0,1.75)*.75;
	vec2 world_uv=flow_space*.008;
	vec2 normal_a=texture(normal_texture,world_uv+vec2(u_time*.015,u_time*.005)*flow_speed).rg*2.0-1.0;
	vec2 normal_b=texture(normal_texture,mat2(vec2(.932,.362),vec2(-.362,.932))*world_uv*1.6-vec2(u_time*.02,0)*flow_speed).rg*2.0-1.0;
	vec2 normal_c=texture(normal_texture,mat2(vec2(.622,-.783),vec2(.783,.622))*world_uv*4.0+vec2(u_time*.04)*flow_speed).rg*2.0-1.0;
	vec2 slopes=(normal_a+normal_b*.8+normal_c*.3)*(.24+surface_detail_strength)*u_strength*detail_filter;
	vec2 world_slopes=wind*slopes.x+across*slopes.y;
	vec3 n=normalize(v_normal+vec3(world_slopes.x,0,world_slopes.y));
	float water_depth=-(VIEW_MATRIX*vec4(v_world,1)).z;
	float optical_depth=max(0.0,linear_depth(screen_uv,INV_PROJECTION_MATRIX)-water_depth);
	// Godot viewport UV has a downward Y axis, unlike WebGL gl_FragCoord.
	vec2 refract_uv=clamp(screen_uv+vec2(n.x,-n.z)*.012*min(optical_depth*.15,1.0),vec2(.002),vec2(.998));
	if(linear_depth(refract_uv,INV_PROJECTION_MATRIX)<water_depth)refract_uv=screen_uv;
	vec3 scene=sample_source_scene(refract_uv);
	vec3 transmit=exp(-vec3(.19,.075,.035)*optical_depth);
	float dry_height=height_at(v_world.xz);
	float shore_depth=max(-dry_height,0.0);
	float shallow_mix=1.0-smoothstep(1.5,17.0,shore_depth);
	// The approved azure/turquoise palette provides absorption's body color;
	// real scene transmittance remains visible through the shallowest water.
	vec3 water_color=mix(offshore_color,shallow_color,shallow_mix);
	float height_factor=smoothstep(-2.0,3.0,v_world.y-u_tide);
	water_color*=.94+height_factor*.10;
	if(has_reference_water_textures) {
		vec3 deep_pattern=texture(reference_deep_texture,v_world.xz*.008+vec2(u_time*.0013,-u_time*.0007)).rgb;
		vec3 surface_pattern=texture(reference_surface_texture,v_world.xz*.035+n.xz*.025+vec2(-u_time*.002,u_time*.001)).rgb;
		float deep_luma=dot(deep_pattern,vec3(.2126,.7152,.0722));
		float surface_luma=dot(surface_pattern,vec3(.2126,.7152,.0722));
		water_color*=1.0+clamp((deep_luma-.46)*.14,-.04,.04)*(1.0-shallow_mix);
		water_color+=vec3(.014,.024,.026)*(surface_luma-.56);
	}
	vec3 refracted=scene*transmit+water_color*(1.0-transmit);
	// Only seabed contribution fades with true depth and the finite terrain
	// window. A visible ship hull is classified separately and retains refraction.
	// This removes the green rectangular floor edge without moving any terrain.
	vec3 opaque_world=reference_opaque_world(refract_uv,INV_PROJECTION_MATRIX,INV_VIEW_MATRIX);
	float opaque_ground=height_at(opaque_world.xz);
	float below_surface=max(u_tide-opaque_world.y,0.0);
	float bottom_gate=reference_bottom_gate(abs(opaque_world.y-opaque_ground),below_surface);
	bottom_gate=max(bottom_gate,smoothstep(10.0,18.0,below_surface));
	float bottom_visibility=reference_bottom_visibility(max(u_tide-opaque_ground,0.0),reference_bottom_window(opaque_world.xz));
	refracted=mix(water_color,refracted,1.0-bottom_gate*(1.0-bottom_visibility));
	if(!u_refraction_enabled)refracted=water_color;
	vec3 view_dir=normalize(u_eye-v_world),reflected_ray=reflect(-view_dir,n);
	vec3 reflection=source_sky(reflected_ray);
	vec4 rp=u_reflection_vp*vec4(v_world,1);
	vec2 ruv=vec2(rp.x/rp.w*.5+.5,.5-rp.y/rp.w*.5)+vec2(n.x,-n.z)*.009;
	if(u_use_reflection&&rp.w>0.0&&all(greaterThan(ruv,vec2(0)))&&all(lessThan(ruv,vec2(1))))reflection=sample_source_reflection(ruv);
	float f=.02+.98*pow(1.0-max(dot(n,view_dir),0.0),5.0);
	vec3 col=mix(refracted,reflection,f);
	vec3 half_vector=normalize(u_sun+view_dir);
	float reflection_lobe=max(dot(n,half_vector),0.0);
	// Small textured glints and a gentle broad lobe retain movement without a
	// large white grid of identical specular crests.
	float broad_spec=pow(reflection_lobe,90.0)*.035;
	float fine_spec=pow(reflection_lobe,250.0)*.19;
	float glint=reference_wind_glint(v_world.xz,n,u_time);
	col+=u_sun_color*(broad_spec+fine_spec*(.35+glint*.65));
	if(has_reference_water_textures) {
		float flecks_a=texture(reference_sparkle_texture,v_world.xz*.075+n.xz*.025+vec2(u_time*.005,u_time*.003)).a;
		float flecks_b=texture(reference_sparkle_texture,v_world.zx*.113+vec2(-u_time*.004,u_time*.006)).a;
		float flecks=smoothstep(.39,.88,flecks_a)*smoothstep(.18,.71,flecks_b);
		flecks*=.20+.80*pow(reflection_lobe,18.0);
		col+=vec3(.085,.11,.10)*flecks*(.55+glint*.45)*detail_filter;
		col+=reference_original_micro_sparkle(v_world.xz,n,u_time,surface_wind_direction,surface_wind_speed,footprint,length(u_eye.xz-v_world.xz),reflection_lobe);
		float whitecaps=reference_whitecap_coverage(v_world.xz,n,u_time,length(u_eye.xz-v_world.xz));
		col=mix(col,vec3(.84,.94,.96),whitecaps*(1.0-shallow_mix*.65));
	}
	// A small pale cyan scattering band softens actual sand/water contact; its
	// genuine-coast gate prevents a white or bright ring around submerged banks.
	float shore_transition=reference_shore_transition(shore_depth,reference_coast_distance(v_world.xz));
	col=mix(col,vec3(.56,.84,.81),shore_transition*.12);
	float depth=v_world.y-dry_height;
	if(u_foam&&depth>=0.0) {
		float foam_noise=texture(normal_texture,v_world.xz*.064+vec2(u_time*.10)).r;
		float shore_noise=texture(normal_texture,v_world.xz*.06+vec2(u_time*.012,-u_time*.009)).g;
		float band=.25+.75*pow(.5+.5*sin(depth*6.0-u_time*2.2+source_value_noise(v_world.xz*.5)*3.0),2.0);
		float edge_mask=texture(coastal_foam_texture_b,v_world.xz*.10+vec2(u_time*.007,-u_time*.005)).a;
		float edge_foam=(1.0-smoothstep(.0,u_foam_width,depth))*band*(.20+.80*smoothstep(.06,.56,edge_mask));
		float surf=coastal_breaker_foam(reference_coast_distance(v_world.xz),shore_depth,dry_height,v_world.xz,u_time,foam_noise,shore_noise);
		col=mix(col,vec3(.89,.96,.94),max(edge_foam*.67,surf*.92));
	}
	float fog=1.0-exp(-length(u_eye-v_world)*.0015);
	// Source default framebuffer also clamps display RGB; no manual 8-bit
	// rounding is applied to filtered scene/reflection samples.
	ALBEDO=reference_to_linear(clamp(mix(col,source_sky(normalize(v_world-u_eye)),fog),vec3(0.0),vec3(1.0)));
	ALPHA=1.0;
}
