shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, depth_test_disabled, blend_mix, fog_disabled;
#include "res://modules/scene_engine/fidelity_fx/particle_sampling.gdshaderinc"
uniform float accepted_time=0.0;
uniform float trail_distance_m=0.0;
uniform float lifetime_seconds=14.0;
void fragment() {
	float age=max(accepted_time-UV2.x,0.0);
	float across=abs(UV2.y);
	float behind=max(trail_distance_m-UV.y,0.0);
	// UV is measured in world metres. Positive longitudinal phase moves detail
	// toward older water, instead of dragging it forward onto the ship. Birth
	// speed is frozen per row; pause freezes age and every advection phase.
	float birth_speed_mps=COLOR.r*12.0;
	vec2 metres=vec2(UV.x,UV.y+age*(.5+birth_speed_mps*.22));
	mat2 rotate_a=mat2(vec2(.921061,.389418),vec2(-.389418,.921061));
	mat2 rotate_b=mat2(vec2(.745174,-.666870),vec2(.666870,.745174));
	vec2 uv_a=rotate_a*(metres*vec2(.72,.43))+vec2(age*.10,0.0);
	vec4 source=fidelity_particle_sample(uv_a);
	vec2 uv_b=rotate_b*(metres*vec2(1.13,.71))+vec2(.47,-age*.17)+(source.a-.5)*vec2(.23,.17);
	float second=fidelity_particle_sample(uv_b).a;
	float grain=smoothstep(.22,.75,source.a*.6+second*.4);
	float breakup=smoothstep(.20,.68,second);
	float center=exp(-across*across*3.0);
	float birth=smoothstep(0.0,.12,age);
	float fresh=(1.0-smoothstep(.7,3.2,age))*(1.0-smoothstep(8.0,14.0,behind));
	float foam=center*grain*fresh*.34;
	float diffuse=(1.0-smoothstep(.05,1.0,across))*(grain*.6+breakup*.4)*smoothstep(.4,1.5,age)*(1.0-smoothstep(3.0,lifetime_seconds,age))*.055;
	// Side ripples are short, irregular pieces, never two permanent rails.
	float side=exp(-pow((across-(.65+.13*(second-.5)))/.18,2.0));
	float ripple=side*smoothstep(.35,.80,source.a*second)*pow(.5+.5*sin(UV.y*.9-age*2.2),4.0)*(1.0-smoothstep(1.0,4.5,age))*.02;
	float edge=1.0-smoothstep(.8,1.0,across);
	ALBEDO=source.rgb;
	ALPHA=clamp((foam+diffuse+ripple)*birth*edge*COLOR.a,0.0,.42)*fidelity_particle_depth_fade(SCREEN_UV,VERTEX.z,INV_PROJECTION_MATRIX);
}
