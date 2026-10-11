import {readFileSync,writeFileSync} from 'node:fs';
const root='C:/Users/dains/Documents/Git/ming-armada/';
let code=readFileSync(root+'modules/scene_engine/reference_island_water/reference_water.gdshader','utf8');
const replace=(before,after)=>{if(!code.includes(before))throw new Error('Missing source segment '+before.slice(0,70));code=code.replace(before,after);};
replace('uniform vec4 u_waves[4];','// Formal game keeps the authoritative five-wave physics profile.\n#include "res://modules/scene_engine/ocean/integration_wave_functions.gdshaderinc"');
replace('uniform vec4 u_speeds = vec4(1.4,1.8,2.2,2.8);','');
replace('uniform sampler2D u_height : repeat_disable, filter_nearest;','');
replace('uniform float u_extent = 160.0;','');
replace('uniform float u_terrain_resolution = 160.0;','');
replace('uniform bool u_foam = true;',`uniform bool u_foam = true;
uniform bool u_refraction_enabled = true;
uniform bool u_caustics = true;
// Stable formal game metadata/API aliases; source formulas use u_* uniforms.
uniform int visual_style = 1;
uniform vec2 surface_wind_direction = vec2(1.0,0.0);
uniform float surface_wind_speed = 14.0;
uniform float surface_detail_strength = .09;
uniform sampler2D reference_whitecaps_texture : repeat_enable, filter_linear_mipmap;
uniform bool surface_optics_enabled = true;
uniform bool surface_reflection_enabled = true;
uniform bool surface_refraction_enabled = true;
uniform int surface_reflection_steps = 0;`);
const waveStart=code.indexOf('void wave_filtered('),depthStart=code.indexOf('// Godot reverse-Z');
if(waveStart<0||depthStart<waveStart)throw new Error('wave/height boundaries missing');
code=code.slice(0,waveStart)+code.slice(depthStart);
const vertexStart=code.indexOf('void vertex()'),fragmentStart=code.indexOf('void fragment()');
code=code.slice(0,vertexStart)+`void vertex() {
  vec2 base=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
  v_world=vec3(base.x,u_tide+reference_game_height(base,simulation_time),base.y);
  v_normal=reference_game_normal(base,simulation_time);
  VERTEX=(inverse(MODEL_MATRIX)*vec4(v_world,1.0)).xyz;
  NORMAL=inverse(mat3(MODEL_MATRIX))*v_normal;
}
`+code.slice(fragmentStart);
replace('vec3 refracted=scene*transmit+water_color*(1.0-transmit);','vec3 refracted=scene*transmit+water_color*(1.0-transmit);\n\tif(!u_refraction_enabled)refracted=water_color;');
code='// Direct source waterFS transplant; regenerate with Temp/compose_reference_game_water.mjs.\n'+code;
writeFileSync(root+'modules/scene_engine/ocean/reference_game_water.gdshader',code);
console.log('COMPOSE_REFERENCE_GAME_WATER',code.length);
