shader_type spatial;
render_mode cull_disabled, depth_prepass_alpha;
#define PRESERVE_SOURCE_ALPHA
#include "res://game/presentation/ships/ship_damage_surface.gdshaderinc"
