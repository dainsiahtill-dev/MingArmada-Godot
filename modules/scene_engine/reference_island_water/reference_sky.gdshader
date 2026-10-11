shader_type sky;
#include "res://modules/scene_engine/reference_island_water/source_common.gdshaderinc"
void sky() {
	// Source sky writes into RGBA8; preserve its display-range boundary in HDR.
	COLOR=reference_to_linear(clamp(source_sky(normalize(EYEDIR)),vec3(0.0),vec3(1.0)));
}
