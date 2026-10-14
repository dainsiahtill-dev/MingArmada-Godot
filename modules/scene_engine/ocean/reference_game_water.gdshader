// Formal fusion: source planar/depth optics and actual-terrain foam, with the
// approved native color palette, advected normal texture and alpha surf layers.
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_always;
// Default preserves the formal game. Source-island observers cover kilometres.
uniform float display_fog_density = 0.0015;
// Texture/detail scale is a presentation adapter. Wave positions, authority
// heights, coastline distance and physics are still evaluated in world metres.
uniform float surface_visual_scale = 1.0;
uniform bool mask_dry_terrain = false;
// Local shoreline coverage, validated against the zero-width baseline in the
// laboratory. Zero remains an exact rollback; units are vertical world metres.
uniform float shore_edge_feather_m : hint_range(0.0,1.0) = 0.6;
// Independent local translucency; one restores the same-width coverage response.
uniform float shore_edge_water_weight : hint_range(0.0,1.0) = 0.55;
#include "res://modules/scene_engine/reference_island_water/source_common.gdshaderinc"
#include "res://modules/scene_engine/ocean/reference_sparkle_fusion.gdshaderinc"

// Formal game keeps the authoritative five-wave physics profile.
#include "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"
#include "res://modules/scene_engine/ocean/macro_wave_optics.gdshaderinc"
#include "res://modules/scene_engine/ocean/water_environment_optics.gdshaderinc"

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
// Curved analytic fronts own the advancing trajectory; authored surf follows
// their phase and supplies irregular texture detail on the same wave heads.
uniform float coastal_breaker_strength : hint_range(0.0,1.0) = 1.0;
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
#include "res://modules/scene_engine/ocean/shore_edge_coverage.gdshaderinc"
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
	// Preserve the old three advected texture scales, orienting tangent XY into
	// world XZ. Independent rotated flows break the source's sine checkerboard.
	vec2 wind=surface_wind_direction;
	vec2 across=vec2(-wind.y,wind.x);
	vec2 flow_space=vec2(dot(v_world.xz,wind),dot(v_world.xz,across));
	float flow_speed=.25+clamp(surface_wind_speed/14.0,0.0,1.75)*.75;
	vec2 world_uv=flow_space*.008*surface_visual_scale;
	mat2 rotate_b=mat2(vec2(.932,.362),vec2(-.362,.932));
	mat2 rotate_c=mat2(vec2(.622,-.783),vec2(.783,.622));
	// Preserve original 1/1.6/4 frequency bands. Each reads actual normal mips
	// and loses only its unresolved frequencies; broad flow outlives fine ripples.
	vec2 normal_a=reference_surface_normal_band(normal_texture,world_uv+vec2(u_time*.015,u_time*.005)*flow_speed,24.0);
	vec2 normal_b=transpose(rotate_b)*reference_surface_normal_band(normal_texture,rotate_b*world_uv*1.6-vec2(u_time*.02,0)*flow_speed,16.0);
	vec2 normal_c=transpose(rotate_c)*reference_surface_normal_band(normal_texture,rotate_c*world_uv*4.0+vec2(u_time*.04)*flow_speed,8.0);
	vec2 slopes=(normal_a+normal_b*.8+normal_c*.3)*(.24+surface_detail_strength)*u_strength;
	vec2 world_slopes=wind*slopes.x+across*slopes.y;
	// Projected grid triangles are large offshore. Interpolating their normals
	// turns specular ridges into straight spokes at the coast. Evaluate the same
	// retained five-wave derivative at the pixel; geometry/physics stay intact.
	vec3 macro_normal=reference_game_normal(v_world.xz,simulation_time);
	vec3 optical_macro_normal=reference_optical_wave_normal(v_world.xz,simulation_time,dFdx(v_world.xz),dFdy(v_world.xz));
	vec3 optical_view=u_eye-v_world;
	float grazing_visibility=reference_macro_grazing_visibility(normalize(optical_view).y,length(optical_view));
	if(grazing_visibility<1.0)optical_macro_normal=normalize(mix(vec3(0,1,0),optical_macro_normal,grazing_visibility));
	vec3 n=normalize(optical_macro_normal+vec3(world_slopes.x,0,world_slopes.y));
	float water_depth=-(VIEW_MATRIX*vec4(v_world,1)).z;
	float optical_depth=max(0.0,linear_depth(screen_uv,INV_PROJECTION_MATRIX)-water_depth);
	// Godot viewport UV has a downward Y axis, unlike WebGL gl_FragCoord.
	vec2 refract_uv=clamp(screen_uv+vec2(n.x,-n.z)*.012*min(optical_depth*.15,1.0),vec2(.002),vec2(.998));
	if(linear_depth(refract_uv,INV_PROJECTION_MATRIX)<water_depth)refract_uv=screen_uv;
	vec3 scene=sample_source_scene(refract_uv);
	vec3 transmit=exp(-vec3(.19,.075,.035)*optical_depth);
	float dry_height=height_at(v_world.xz);
	// Sparse projected-water vertices can interpolate above a low island even
	// when each vertex's waves are attenuated correctly. A per-fragment height
	// gate keeps the retained ocean from painting foam/refraction over dry land.
	if(mask_dry_terrain && dry_height > u_tide + .035) discard;
	float shore_depth=max(-dry_height,0.0);
	float shallow_mix=1.0-smoothstep(1.5,17.0,shore_depth);
	// The approved azure/turquoise palette provides absorption's body color;
	// real scene transmittance remains visible through the shallowest water.
	vec3 water_color=mix(offshore_color,shallow_color,shallow_mix);
	float height_factor=smoothstep(-2.0,3.0,v_world.y-u_tide);
	water_color*=.94+height_factor*.10;
	// Body scattering shows smooth moving normals even away from the mirror
	// direction. Neutral multiplicative light preserves the approved hue and
	// adds no white alpha flecks to make nearby water appear detailed.
	vec3 light_direction=normalize(u_sun);
	water_color*=reference_surface_ripple_light(dot(n,light_direction),light_direction.y,surface_ripple_light_strength);
	if(has_reference_water_textures) {
		vec3 deep_pattern=texture(reference_deep_texture,v_world.xz*.008*surface_visual_scale+vec2(u_time*.0013,-u_time*.0007)).rgb;
		vec3 surface_pattern=texture(reference_surface_texture,v_world.xz*.035*surface_visual_scale+n.xz*.025+vec2(-u_time*.002,u_time*.001)).rgb;
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
	// Keep full texture normals for the blue body, refraction and small glints.
	// Their old perfect-mirror Fresnel made moderate ripples become broad white
	// bands. Environment reflection sees the same macro waves with gentler
	// moving texture slopes, plus an explicit rough-sea angular response.
	vec3 reflection_normal=n;
	if(!water_legacy_optics) reflection_normal=reference_water_environment_normal(optical_macro_normal,world_slopes,water_environment_ripple_gain);
	vec3 view_dir=normalize(u_eye-v_world),reflected_ray=reflect(-view_dir,reflection_normal);
	vec3 reflection=source_sky(reflected_ray);
	vec4 rp=u_reflection_vp*vec4(v_world,1);
	vec2 ruv=vec2(rp.x/rp.w*.5+.5,.5-rp.y/rp.w*.5)+vec2(reflection_normal.x,-reflection_normal.z)*.009;
	if(u_use_reflection&&rp.w>0.0&&all(greaterThan(ruv,vec2(0)))&&all(lessThan(ruv,vec2(1))))reflection=sample_source_reflection(ruv);
	float f=.02+.98*pow(1.0-max(dot(n,view_dir),0.0),5.0);
	if(!water_legacy_optics) f=reference_water_environment_fresnel(dot(reflection_normal,view_dir),water_environment_horizon_weight);
	vec3 col=mix(refracted,reflection,f);
	vec3 half_vector=normalize(u_sun+view_dir);
	float reflection_lobe=max(dot(n,half_vector),0.0);
	// Small textured glints and a gentle broad lobe retain movement without a
	// large white grid of identical specular crests.
	vec3 normal_dx=dFdx(n),normal_dy=dFdy(n);
	float normal_variance=.5*(dot(normal_dx,normal_dx)+dot(normal_dy,normal_dy));
	float broad_power=reference_surface_specular_power(normal_variance,90.0);
	float fine_power=reference_surface_specular_power(normal_variance,250.0);
	// Widen unresolved lobes while reducing peak energy by the same ratio.
	float broad_spec=pow(reflection_lobe,broad_power)*.035*(broad_power/90.0);
	float fine_spec=pow(reflection_lobe,fine_power)*.19*(fine_power/250.0);
	float glint=reference_wind_glint(v_world.xz*surface_visual_scale,n,u_time);
	// The fine lobe belongs to actual small glints. Its old 35% untextured floor
	// connected resolved highlights into pale straight strips even with no glint.
	col+=u_sun_color*(broad_spec+fine_spec*glint);
	if(has_reference_water_textures) {
		float flecks=reference_surface_flecks(v_world.xz*surface_visual_scale,n,u_time,reflection_lobe);
		col+=vec3(.085,.11,.10)*flecks*(.55+glint*.45);
		col+=reference_original_micro_sparkle(v_world.xz*surface_visual_scale,n,u_time,surface_wind_direction,surface_wind_speed,footprint*surface_visual_scale,length(u_eye.xz-v_world.xz),reflection_lobe);
		float whitecaps=reference_whitecap_coverage(v_world.xz*surface_visual_scale,macro_normal,u_time,length(u_eye.xz-v_world.xz),v_world.y-u_tide);
		col=mix(col,vec3(.84,.94,.96),whitecaps*(1.0-shallow_mix*.65));
	}
	// A small pale cyan scattering band softens actual sand/water contact; its
	// genuine-coast gate prevents a white or bright ring around submerged banks.
	float shore_transition=reference_shore_transition(shore_depth,reference_coast_distance(v_world.xz));
	col=mix(col,vec3(.56,.84,.81),shore_transition*.12);
	float depth=v_world.y-dry_height;
	if(u_foam&&depth>=0.0) {
		float foam_noise=texture(normal_texture,v_world.xz*.064*surface_visual_scale+vec2(u_time*.10)).r;
		float shore_noise=texture(normal_texture,v_world.xz*.06*surface_visual_scale+vec2(u_time*.012,-u_time*.009)).g;
		float band=.25+.75*pow(.5+.5*sin(depth*6.0-u_time*2.2+source_value_noise(v_world.xz*.5)*3.0),2.0);
		// This original texture contains a directed foam front. Regular XY tiling
		// stamped identical white pads along the beach. Read its alpha through the
		// established continuous stochastic sampler, retaining the moving wash.
		float edge_mask=reference_stochastic_alpha(coastal_foam_texture_b,v_world.xz*.10*surface_visual_scale+vec2(u_time*.007,-u_time*.005),211u,3.14159265);
		float edge_foam=(1.0-smoothstep(.0,u_foam_width,depth))*band*(.20+.80*smoothstep(.06,.56,edge_mask));
		float surf=coastal_breaker_foam(reference_coast_distance(v_world.xz),shore_depth,dry_height,v_world.xz,u_time,foam_noise,shore_noise)*coastal_breaker_strength;
		col=mix(col,vec3(.89,.96,.94),max(edge_foam*.67*shoreline_residue_strength,surf*.92));
	}
	float fog=1.0-exp(-length(u_eye-v_world)*display_fog_density);
	// Source default framebuffer also clamps display RGB; no manual 8-bit
	// rounding is applied to filtered scene/reflection samples.
	ALBEDO=reference_to_linear(clamp(mix(col,source_sky(normalize(v_world-u_eye)),fog),vec3(0.0),vec3(1.0)));
	// Fade to the actual unrefracted opaque pixel at both the dry mask and
	// water/terrain intersection. Keep islands opaque and the existing depth path.
	if(shore_edge_feather_m>0.0 && mask_dry_terrain && (has_shore_field || has_reference_near_field)) {
		float coverage=reference_shore_edge_coverage(u_tide+.035-dry_height,v_world.y-dry_height,optical_depth*abs(view_dir.y),shore_edge_feather_m);
		if(coverage<1.0) {
			float water_weight=reference_shore_edge_water_weight(coverage,shore_edge_water_weight);
			ALBEDO=mix(texture(u_scene,screen_uv).rgb,ALBEDO,water_weight);
		}
	}
	ALPHA=1.0;
}
