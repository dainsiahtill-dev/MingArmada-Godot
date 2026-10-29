"""Read-only asset audit after bounded UV canonicalizer rejection."""
import hashlib
import importlib.util
import json
from pathlib import Path
import struct

ROOT = Path(__file__).resolve().parents[4]
EVIDENCE = Path(__file__).resolve().parent
sha256 = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
script = ROOT / 'tools/blender/build_hero_fuchuan_r8_proxy.py'
archive = EVIDENCE / 'failed-wrapper.py'
assert not archive.exists(), 'preserve original audit outputs'
archive.write_bytes(script.read_bytes())
canonicalizer = ROOT / 'tools/blender/canonicalize_palette_uv.py'
spec = importlib.util.spec_from_file_location('palette_uv', canonicalizer)
uv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(uv)
result = {'status': 'failed immutable candidate; do not overwrite',
          'wrapperSHA256': sha256(script), 'canonicalizerSHA256': sha256(canonicalizer),
          'outputs': {}, 'rudderComparison': []}
paths = [ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r8a.blend']
paths.extend(sorted((ROOT / 'assets/models/hero_fuchuan_v3_r8a').iterdir()))
result['outputs'] = {path.relative_to(ROOT).as_posix(): {'sha256': sha256(path), 'bytes': path.stat().st_size}
                     for path in paths if path.is_file()}
audit = json.loads((ROOT / 'docs/research/evidence/hero-fuchuan/r7c-palette-20261026/final-audit-01/post-build-audit.json').read_text(encoding='utf-8'))
old = json.loads((ROOT / 'docs/production/hero-fuchuan-2026-10-26-art/v3-r7c-palette-01/palette-build.json').read_text(encoding='utf-8'))
anchors = dict(old['sourcesAfter'])
anchors.update({key: value['sha256'] for key, value in audit['files'].items()
                if key.startswith(('tools/blender/', 'assets/models/hero_fuchuan_v3_r7c/',
                                   'assets/production/hero-fuchuan-blender/', 'assets/textures/hero_fuchuan_r7/'))})
result['originalSourcesAgainstPriorReceipts'] = {
    key: {'referenceSHA256': value, 'currentSHA256': sha256(ROOT / key), 'same': value == sha256(ROOT / key)}
    for key, value in anchors.items()}
result['sourceEvidenceBoundary'] = 'Current hashes against existing R6/R7c receipts; failed build did not reach its after-hash receipt. This does not reconstruct a missing build-time after snapshot.'
for lod in range(3):
    candidate = uv._Glb((ROOT / f'assets/models/hero_fuchuan_v3_r8a/fuchuan-lod{lod}.glb').read_bytes())
    _, ca, ci = candidate.rudder()
    for version in ['r6', 'r7c']:
        reference = uv._Glb((ROOT / f'assets/models/hero_fuchuan_v3_{version}/fuchuan-lod{lod}.glb').read_bytes())
        _, ra, ri = reference.rudder()
        offsets = zip(uv._component_offsets(ra['TEXCOORD_0']), uv._component_offsets(ca['TEXCOORD_0']))
        differences = []
        for index, (source, destination) in enumerate(offsets):
            if reference.raw[source:source + 4] == candidate.raw[destination:destination + 4]:
                continue
            original = struct.unpack_from('<f', reference.raw, source)[0]
            current = struct.unpack_from('<f', candidate.raw, destination)[0]
            differences.append({'component': index, 'reference': original, 'candidate': current,
                                'delta': abs(original - current)})
        result['rudderComparison'].append({
            'lod': lod, 'referenceVersion': version,
            'positionExact': reference.packed(ra['POSITION']) == candidate.packed(ca['POSITION']),
            'normalExact': reference.packed(ra['NORMAL']) == candidate.packed(ca['NORMAL']),
            'indicesExact': reference.packed(ri) == candidate.packed(ci),
            'changedUVComponents': differences,
            'maxDelta': max([value['delta'] for value in differences], default=0)})
report = EVIDENCE / 'failed-export-audit.json'
assert not report.exists()
report.write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
summary = dict(result)
summary['originalAnchorChecks'] = len(anchors)
summary['originalAnchorChecksAllSame'] = all(value['same'] for value in result['originalSourcesAgainstPriorReceipts'].values())
del summary['originalSourcesAgainstPriorReceipts']
summary['rudderComparison'] = [{key: value for key, value in item.items() if key != 'changedUVComponents'} |
                              {'changedUVComponents': len(item['changedUVComponents'])}
                              for item in result['rudderComparison']]
print(json.dumps(summary, indent=2))
