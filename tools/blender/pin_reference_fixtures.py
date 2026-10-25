"""Keep historical narrow-barque regression fixtures pinned to their source.
New authored hull is exercised independently by test_hero_fuchuan_water.gd.
"""
from pathlib import Path
import shutil,json
root=Path(__file__).resolve().parents[2]
evidence=root/'docs/production/hero-fuchuan-2026-10-25'
for name in ['test_hull_contact_froth.gd','test_hull_waterline_heave_profile.gd','test_hull_waterline_profile.gd','test_reference_damage_textures.gd','test_reference_ship_damage.gd']:
    path=root/'tests'/name
    baseline=evidence/(name+'.baseline')
    if not baseline.exists():shutil.copy2(path,baseline)
    text=path.read_text(encoding='utf-8')
    if 'const Reference=' not in text:
        text=text.replace('extends SceneTree','extends SceneTree\n# Recorded original-hull fixtures; authored flagship has a separate water test.\nconst Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")',1)
        text=text.replace('actor.configure(kind)','actor.configure(kind,null,Reference.new())').replace('actor.configure("fuchuan")','actor.configure("fuchuan",null,Reference.new())')
        for owner in ['view','healthy']:
            for argument in ['kind','"fuchuan"','"voc"']:
                text=text.replace(owner+'.configure('+argument+')',owner+'.configure('+argument+',null,Reference.new())')
        path.write_text(text,encoding='utf-8')
path=root/'assets/research/catalog.json'; data=json.loads(path.read_text(encoding='utf-8'))
if data['topics'][0]['id']=='hero-fuchuan':data['topics'].append(data['topics'].pop(0))
path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
print('Historical source fixtures pinned; appended new lab topic without changing prior order.')
