"""Archive task-scoped receipts and hash the actual flagship delivery."""
from pathlib import Path
import datetime, hashlib, json, shutil

root = Path(__file__).resolve().parents[2]
out = root / 'docs/production/hero-fuchuan-2026-10-25'
archive = out / 'regression'
archive.mkdir(parents=True, exist_ok=True)
recovery = root / 'Temp/hero-fuchuan/recovery-final'
summary = json.loads((recovery / 'summary.json').read_text(encoding='utf-8'))
assert summary.get('finishedAtUtc'), 'Recovery suite is still running'
shutil.copy2(root / 'Temp/hero-fuchuan/full-suite.json', archive / 'full-suite-initial.json')
shutil.copy2(recovery / 'summary.json', archive / 'recovery-summary.json')
runs = []
for receipt in summary['receipts']:
    path = root / receipt['file']
    shutil.copy2(path, archive / path.name)
    runs.extend(json.loads(path.read_text(encoding='utf-8'))['runs'])
sources = [
    'tools/blender/build_hero_fuchuan.py',
    'assets/production/hero-fuchuan-blender/hero-fuchuan.blend',
    'assets/models/hero_fuchuan/manifest.json',
    'modules/scene_engine/assets/hero_ship_provider.gd',
    'game/presentation/ships/ship_view.gd',
    'game/presentation/ships/ship_damage.gd',
    'game/presentation/ships/ship_damage_surface.gdshaderinc',
    'game/presentation/crew/deck_stations.gd',
    'game/presentation/world/source_water_packet.gd',
    'game/research/demos/hero_fuchuan_experiment.gd',
    'game/scenes/ship_book/ship_book.gd',
    'tests/test_hero_fuchuan.gd',
    'tests/test_hero_fuchuan_rig.gd',
    'tests/test_hero_fuchuan_water.gd',
    'tools/verify-hero-fuchuan-gpu.gd',
]
model = json.loads((root / 'assets/models/hero_fuchuan/manifest.json').read_text(encoding='utf-8'))
for lod in model['lods']:
    assert hashlib.sha256((root / lod['path']).read_bytes()).hexdigest() == lod['sha256'], lod['path']
    sources.append(lod['path'])
sources += [str(p.relative_to(root)).replace('\\', '/') for p in (out / 'native-play').glob('*.png')]
sources += [str((out / p).relative_to(root)).replace('\\', '/') for p in ['blender-hero.png', 'hero-rig-continuous-v5.mp4', 'gpu-final-v5/manifest.json']]
unique = {r['test']: r for r in runs}
manifest = {
    'createdAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'scope': 'Authored flagship delivery. Initial full run and final directed recovery are distinct receipts. Controlled GPU rig video is not native gameplay video.',
    'initialFullSuite': json.loads((archive / 'full-suite-initial.json').read_text(encoding='utf-8'))['summary'],
    'recovery': {'uniqueTests': len(unique), 'passed': sum(r['passed'] for r in unique.values()), 'failed': [r['test'] for r in unique.values() if not r['passed']]},
    'artifacts': [{'path': p, 'bytes': (root / p).stat().st_size, 'sha256': hashlib.sha256((root / p).read_bytes()).hexdigest()} for p in sources],
}
(out / 'final-delivery-manifest.json').write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({k:v for k,v in manifest.items() if k != 'artifacts'}, ensure_ascii=False))
