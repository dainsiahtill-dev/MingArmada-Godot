shader_type spatial;
render_mode cull_disabled;

uniform float damage_stage = 0.0;
uniform bool sail_surface = false;
uniform float original_roughness = 0.85;
uniform vec4 original_color : source_color = vec4(1.0);
uniform int tear_count = 0;
uniform vec4 tears[12];
uniform bool use_reference_damage = false;
uniform sampler2D reference_damage : source_color, filter_linear_mipmap, repeat_disable;

float noise_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec3 base = COLOR.rgb * original_color.rgb;
	float severity = damage_stage / (sail_surface ? 4.0 : 5.0);
	if (sail_surface) {
		float scorch = 0.0;
		if (use_reference_damage) {
			vec4 damage = texture(reference_damage, UV);
			// Reference RGB is constant brown; alpha is surviving cloth, not color.
			// Original SailShader.NSF uses alpha test >= 160/255, clamped UV0.
			if (damage.a < 0.62745098) { discard; }
			vec2 edge_step = vec2(0.006);
			float edge_alpha = min(min(texture(reference_damage, UV + vec2(edge_step.x, 0.0)).a, texture(reference_damage, UV - vec2(edge_step.x, 0.0)).a), min(texture(reference_damage, UV + vec2(0.0, edge_step.y)).a, texture(reference_damage, UV - vec2(0.0, edge_step.y)).a));
			base = mix(base, damage.rgb, (1.0 - edge_alpha) * 0.48);
		} else {
			for (int i = 0; i < 12; i++) {
				if (i >= tear_count) { break; }
				vec4 tear = tears[i];
				vec2 delta = UV - tear.xy;
				float c = cos(tear.w);
				float s = sin(tear.w);
				vec2 axis = vec2(c * delta.x - s * delta.y, s * delta.x + c * delta.y);
				vec2 shaped = axis / (tear.z * vec2(0.42, 1.5));
				float angle = atan(shaped.y, shaped.x);
				// Long woven splits with uneven torn edges, no cell/grid repetition.
				float edge = length(shaped) / (0.89 + sin(angle * 5.0 + float(i)) * 0.17 + sin(angle * 11.0 + tear.x * 23.0) * 0.08);
				if (edge < 1.0) { discard; }
				scorch = max(scorch, (1.0 - smoothstep(1.0, 2.0 + severity * 0.5, edge)) * (0.36 + severity * 0.44));
			}
			base = mix(base, vec3(0.10, 0.055, 0.025), scorch * 0.9);
		}
	} else {
		if (use_reference_damage) {
			vec4 damage = texture(reference_damage, UV);
			// Hull alpha weights the damage RGB layer. Geometry remains opaque.
			base = mix(base, damage.rgb * base, damage.a);
		} else {
			vec2 grid = UV * vec2(38.0, 13.0);
			float seed = noise_cell(floor(grid));
			float crack = (1.0 - smoothstep(0.018, 0.055, abs(fract(grid.x) - 0.5))) * step(seed, severity * 0.72);
			base = mix(base, vec3(0.045, 0.022, 0.012), crack * severity);
			base *= 1.0 - severity * 0.27;
		}
	}
	ALBEDO = base;
	ROUGHNESS = clamp(original_roughness + severity * 0.1, 0.0, 1.0);
}
