uniform float damage_stage = 0.0;
uniform bool sail_surface = false;
uniform float original_roughness = 0.85;
uniform vec4 original_color : source_color = vec4(1.0);
uniform bool use_original_vertex_color = true;
uniform bool use_original_albedo = false;
uniform sampler2D original_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform vec2 original_uv_scale = vec2(1.0);
uniform vec2 original_uv_offset = vec2(0.0);
uniform float original_alpha_cutoff = 0.0;
uniform bool use_source_hull_layers = false;
uniform sampler2D original_player : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D original_upgrade : source_color, filter_linear_mipmap, repeat_enable;
uniform bool original_has_damage_uv = false;
uniform bool reference_damage_uv2 = false;
uniform int tear_count = 0;
uniform vec4 tears[12];
uniform bool use_reference_damage = false;
uniform sampler2D reference_damage : source_color, filter_linear_mipmap, repeat_disable;

float noise_cell(vec2 cell) {
	return fract(sin(dot(cell, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 source_uv = UV * original_uv_scale + original_uv_offset;
	vec4 source = use_original_albedo ? texture(original_albedo, source_uv) : vec4(1.0);
	vec4 tint = original_color * (use_original_vertex_color ? COLOR : vec4(1.0));
	// Hull base alpha selects wood versus player color; original final alpha
	// comes from its vertex/material channel, not this compositing weight.
	if ((use_source_hull_layers ? tint.a : source.a * tint.a) < original_alpha_cutoff) { discard; }
	vec3 base = source.rgb * tint.rgb;
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
		if (use_source_hull_layers) {
			// Original PSShipHull four-layer alpha priority, with current Godot
			// lighting. Missing source UV1 never gets an invented damage mapping.
			vec4 player = texture(original_player, source_uv);
			vec4 upgrade = texture(original_upgrade, source_uv);
			vec4 damage = (use_reference_damage && original_has_damage_uv) ? texture(reference_damage, UV2) : vec4(0.0);
			float one = clamp(damage.a + upgrade.a, 0.0, 1.0);
			float two = clamp(one + source.a, 0.0, 1.0);
			base = (damage.rgb * damage.a + upgrade.rgb * (one - damage.a) + source.rgb * (two - one) + player.rgb * (1.0 - two)) * tint.rgb;
		} else if (use_reference_damage) {
			vec4 damage = texture(reference_damage, reference_damage_uv2 ? UV2 : UV);
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
#ifdef PRESERVE_SOURCE_ALPHA
	ALPHA = clamp(source.a * tint.a, 0.0, 1.0);
#endif
	ROUGHNESS = clamp(original_roughness + severity * 0.1, 0.0, 1.0);
}
