uniform vec4 wave_components[8];
uniform int wave_count = 5;

float configured_wave_height(vec2 p, float seconds) {
	float height = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i < wave_count) {
			vec4 wave = wave_components[i];
			height += wave.x * sin(dot(p, wave.yz) + wave.w * seconds);
		}
	}
	return height;
}
