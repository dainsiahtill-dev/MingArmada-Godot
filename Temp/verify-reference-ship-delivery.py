import datetime
import hashlib
import json
from pathlib import Path
import re
import struct
import subprocess

ROOT = Path(__file__).resolve().parents[1]
EVIDENCE = ROOT / 'docs/migration/evidence/integrated-world'
DEST = EVIDENCE / 'reference-ships-delivery-v1.json'

def read(path):
    return json.loads(path.read_text(encoding='utf-8'))

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def resource(path):
    assert path.startswith('res://'), path
    return ROOT / path[6:]

assert not DEST.exists(), 'Preserve earlier delivery receipts'
manifest_path = ROOT / 'assets/data/fidelity_naval/ships-manifest.json'
manifest = read(manifest_path)
models = []
for kind, row in manifest['mappings'].items():
    assert sha(resource(row['modelPath'])) == row['convertedSha256'], kind
    assert sha(resource(row['sourceJsonPath'])) == row['sourceJsonSha256'], kind
    models.append({k: row[k] for k in ['family', 'modelPath', 'convertedSha256', 'foldedControl', 'lodPolicy', 'renderedTriangles']} | {'kind': kind})
assert len(models) == 6

dds = sorted((ROOT / 'assets/textures/fidelity_naval').glob('*.dds'))
mips = sum(max(1, struct.unpack_from('<I', p.read_bytes(), 28)[0]) for p in dds)
assert len(dds) == 24 and mips == 215, (len(dds), mips)
asset_run = subprocess.run(['rtk', 'proxy', 'node', '--test', 'tests/test_reference_ship_import.mjs'], cwd=ROOT, capture_output=True, text=True, encoding='utf-8')
assert asset_run.returncode == 0 and re.search(r'tests 12\b', asset_run.stdout) and re.search(r'fail 0\b', asset_run.stdout), asset_run.stdout[-2000:]

captures = []
for folder, count in [('reference-ships-native-v5', 23), ('ship-material-layers-v2', 8)]:
    base = EVIDENCE / folder
    result = read(base / 'capture-result.json')
    assert result['failures'] == 0 and len(result['captures']) == count
    assert len(list(base.glob('*.png'))) == count
    images = []
    for capture in result['captures']:
        label = capture['label']
        meta = read(base / (label + '.json'))
        image = base / (label + '.png')
        assert sha(image) == meta['imageSha256'], label
        dimensions = list(struct.unpack_from('>II', image.read_bytes(), 16))
        if folder == 'reference-ships-native-v5':
            assert dimensions == [1600, 900], label
        for key in ['modelManifestSha256', 'shipModelManifestSha256']:
            if key in meta: assert meta[key] == sha(manifest_path), label
        for key in ['productionShaderHashes', 'shipPresentationHashes']:
            for path, expected in meta.get(key, {}).items():
                assert sha(resource(path)) == expected, (label, path)
        for key, path in {
            'materialShaderSha256': 'game/presentation/ships/ship_damage.gdshader',
            'damageShaderBodySha256': 'game/presentation/ships/ship_damage_surface.gdshaderinc',
            'alphaShaderSha256': 'game/presentation/ships/ship_damage_alpha.gdshader',
        }.items():
            if key in meta: assert meta[key] == sha(ROOT / path), (label, key)
        if 'error' in meta: assert meta['error'] <= 0.02, (label, meta['error'])
        images.append({'path': str(image.relative_to(ROOT)).replace('\\', '/'), 'sha256': sha(image), 'dimensions': dimensions})
    for suffix in ['stdout', 'stderr']:
        log = ROOT / 'Temp' / (folder + '.' + suffix + '.log')
        assert log.exists(), log
        assert not re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:)', log.read_text(encoding='utf-8')), log
    captures.append({'directory': str(base.relative_to(ROOT)).replace('\\', '/'), 'failures': 0, 'gpu': result['gpu'], 'images': images})

fire = read(EVIDENCE / 'reference-ships-native-v5/source-player-fire-contract.json')
assert fire['playerId'] == 'player' and fire['ammoAfter'] < fire['ammoBefore']
assert len(fire['events']) == len(fire['effects']) == 1
assert fire['events'][0]['shipId'] == fire['effects'][0]['shipId'] == 'player'
assert fire['events'][0]['id'] == fire['effects'][0]['eventId']
for tick in [9, 30, 90, 180]:
    scene = read(EVIDENCE / ('reference-ships-native-v5/formal-battle-%03d.json' % tick))
    player = next(s for s in scene['snapshot']['naval']['ships'] if s['id'] == 'player')
    assert player['ammo']['solid'] == fire['ammoAfter']

headless = []
assertions = 0
for name in ['reference-ships-tests-final-v4.json', 'reference-ships-materials-final-v4.json', 'reference-ships-dismast-final-v4.json', 'reference-ships-event-time-final-v4.json']:
    report = read(EVIDENCE / name)
    assert report['summary']['passedAll'] and report['summary']['failed'] == 0
    for run in report['runs']:
        assert run['passed'] and run['exitCode'] == 0 and not run['timedOut']
        assert not re.search(r'(?m)^(?:ERROR:|SCRIPT ERROR:|FAIL:)', run['stderr'])
        match = re.search(r'assertions=(\d+) failures=0\b', run['stdout'])
        assert match, run['test']
        assertions += int(match[1])
        headless.append({'test': run['test'], 'assertions': int(match[1]), 'report': str((EVIDENCE / name).relative_to(ROOT)).replace('\\', '/')})
assert len(headless) == 7 and assertions == 8202, (len(headless), assertions)

receipt = {
    'schemaVersion': 1,
    'verifiedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    'projectRoot': str(ROOT),
    'scope': 'Six temporary original western ship appearances integrated into current native Godot menu, ShipBook and actual career/naval scenes; existing gameplay authority preserved.',
    'manifestSha256': sha(manifest_path),
    'models': models,
    'textures': {'originalDDS': len(dds), 'authoredMipLevels': mips},
    'assetChecks': {'command': 'rtk proxy node --test tests/test_reference_ship_import.mjs', 'passed': 12, 'failed': 0, 'skipped': 0, 'stdout': asset_run.stdout},
    'headless': {'scripts': len(headless), 'assertions': assertions, 'failures': 0, 'runs': headless},
    'native': captures,
    'playerFire': fire,
    'visualInspection': {'nativeV5PNGsViewed': 23, 'controlledDamage': 'ShipBook dismast snapshot is a presentation inspection, not a claim that this screenshot records an actual combat dismast.'},
    'saveScope': 'Capture uses non-writing in-memory legacy and Mingqi save slots; its final zero-write assertion passed.',
    'limitations': ['Temporary western hulls and pirate flags are identified in the ShipBook; not historical Chinese models.', 'Source lowend geometry is shared across three independent visual LOD instances; distinct original LOD scheduling is not restored.', 'Five families use actual native closed-cloth target geometry; Barque uses an explicitly identified game morph around the real sail top.', 'Native Godot shading and controls are adapted; full original DX9 cloth/rendering is not claimed.', 'Focused ship tests and actual GPU captures passed; no full-suite or performance conclusion.'],
    'failures': 0,
}
DEST.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'receipt': str(DEST), 'models': 6, 'DDS': len(dds), 'mips': mips, 'assetChecks': 12, 'headlessScripts': len(headless), 'assertions': assertions, 'nativePNGs': 23, 'materialPNGs': 8, 'playerAmmo': [fire['ammoBefore'], fire['ammoAfter']], 'failures': 0}))
