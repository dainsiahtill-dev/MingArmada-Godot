"""Keep frozen-source oracles on the model from which they were recorded."""
from pathlib import Path
import shutil

root = Path(__file__).resolve().parents[2]
evidence = root / 'docs/production/hero-fuchuan-2026-10-25'
replacements = {
    'test_shadow_directed_boundary_candidate.gd': [('ship.configure("fuchuan")', 'ship.configure("fuchuan",null,Reference.new())')],
    'test_target_shadow_boundary.gd': [('ship.configure("fuchuan")', 'ship.configure("fuchuan",null,Reference.new())')],
    'test_ship_pose_roles.gd': [('candidate.configure(kind,library)', 'candidate.configure(kind,library,Reference.new())')],
    'test_ship_water_interaction.gd': [('ship.configure(kind)', 'ship.configure(kind,null,Reference.new())')],
    'test_source_environment_consumers.gd': [('marker_actor.configure(kind)', 'marker_actor.configure(kind,null,Reference.new())')],
    'test_wake_flow_attachment.gd': [('ship.configure(kind)', 'ship.configure(kind,null,Reference.new())')],
}
for name, pairs in replacements.items():
    path = root / 'tests' / name
    baseline = evidence / (name + '.baseline')
    if not baseline.exists():
        shutil.copy2(path, baseline)
    source = path.read_text(encoding='utf-8')
    if 'const Reference=' in source:
        continue
    for before, after in pairs:
        assert before in source, (name, before)
        source = source.replace(before, after)
    source = source.replace('extends SceneTree', 'extends SceneTree\n# Frozen source geometry oracle. Ordinary/default hero entry remains covered separately.\nconst Reference=preload("res://modules/scene_engine/assets/ship_model_provider.gd")', 1)
    path.write_text(source, encoding='utf-8')
    print(name)
