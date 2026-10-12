from pathlib import Path

root = Path('game/presentation/ships')
shader = root / 'ship_damage.gdshader'
source = shader.read_text(encoding='utf-8')
assert source.count('render_mode cull_disabled;') == 1
body = source.split('render_mode cull_disabled;', 1)[1].lstrip()
assert body.count('\tALBEDO = base;') == 1
body = body.replace('\tALBEDO = base;', '\tALBEDO = base;\n#ifdef PRESERVE_SOURCE_ALPHA\n\tALPHA = clamp(source.a * tint.a, 0.0, 1.0);\n#endif')
(root / 'ship_damage_surface.gdshaderinc').write_text(body, encoding='utf-8')
shader.write_text('shader_type spatial;\nrender_mode cull_disabled;\n#include "res://game/presentation/ships/ship_damage_surface.gdshaderinc"\n', encoding='utf-8')
(root / 'ship_damage_alpha.gdshader').write_text('shader_type spatial;\nrender_mode cull_disabled, depth_prepass_alpha;\n#define PRESERVE_SOURCE_ALPHA\n#include "res://game/presentation/ships/ship_damage_surface.gdshaderinc"\n', encoding='utf-8')
