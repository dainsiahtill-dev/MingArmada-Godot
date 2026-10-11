"""Read-only verification of retained review data against the original PNGs."""
from pathlib import Path
from collections import Counter
import csv
import hashlib
import json
from PIL import Image

root = Path(__file__).resolve().parents[2]
manifest = json.loads((root / 'provenance/pirates-water-library.json').read_text(encoding='utf-8'))
source = Path(manifest['source_root']).resolve()
inventory = manifest['inventory']
assets = manifest['assets']
live = {p.resolve() for p in source.glob('Pak*/*.png')}
recorded = {Path(a['source_path']).resolve() for a in inventory}
assert live == recorded and len(inventory) == len(recorded) == 3840
assert len(assets) == len({a['source_path'] for a in assets}) == 486
for item in inventory:
    path = Path(item['source_path']).resolve()
    assert path.is_relative_to(source)
    data = path.read_bytes()
    assert len(data) == item['byte_length'], path
    assert hashlib.sha256(data).hexdigest() == item['sha256'], path
for item in assets:
    path = Path(item['source_path'])
    assert hashlib.sha256(path.read_bytes()).hexdigest() == item['sha256'], path
    with Image.open(path) as original:
        image = original.convert('RGBA')
        assert image.size == (item['width'], item['height']), path
        alpha = image.getchannel('A')
        assert alpha.getextrema() == (item['alpha_min'], item['alpha_max']), path
        fraction = 1 - alpha.histogram()[0] / (image.width * image.height)
        assert abs(fraction - item['alpha_nonzero_fraction']) <= 1e-6, path
        constant = all(low == high for low, high in image.convert('RGB').getextrema())
        assert constant == item['rgb_constant'], path
counts = Counter(a['disposition'] for a in assets)
assert dict(counts) == manifest['counts']['dispositions']
usable = [a for a in assets if a['disposition'] in ('recommended', 'backup')]
assert len(usable) == 121
assert sum(not a['previously_supplied'] for a in usable) == 96
with (root / 'docs/migration/pirates-water-library.csv').open(encoding='utf-8-sig', newline='') as file:
    assert len(list(csv.DictReader(file))) == 486
receipt = {'inventory_png_verified': 3840, 'classified_png_channels_verified': 486,
           'recommended_and_backup': 121, 'new_recommended_and_backup': 96,
           'dispositions': dict(counts), 'failures': [],
           'scope': 'Fresh hashes, PNG dimensions, alpha, RGB constant classification, source boundaries and CSV. Human judgments and original runtime roles are not proven by this verifier.'}
output = root / 'docs/migration/evidence/pirates-water-library-verification.json'
output.write_text(json.dumps(receipt, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')
print('WATER_LIBRARY_VERIFY_PASS ' + json.dumps(receipt, ensure_ascii=False))
