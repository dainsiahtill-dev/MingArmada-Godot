"""Read-only raster validation, never edits or synthesizes artwork."""
import hashlib
import json
from pathlib import Path
from datetime import datetime, timezone
from PIL import Image

directory = Path(__file__).resolve().parent
reader = directory.parent / 'zheng-zhilong'
manifest = json.loads((directory / 'candidate-manifest.json').read_text(encoding='utf-8'))
records = []
for item in manifest['illustrations']:
    file = reader / item['image']
    try:
        with Image.open(file) as raster:
            raster.verify()
        with Image.open(file) as raster:
            raster.load()
            width, height = raster.size
            mode, format_name = raster.mode, raster.format
        digest = hashlib.sha256(file.read_bytes()).hexdigest()
        records.append({'id': item['id'], 'image': item['image'], 'width': width, 'height': height, 'mode': mode, 'format': format_name, 'sha256': digest, 'passed': format_name == 'PNG' and width == item['width'] and height == item['height'] and digest == item['sha256']})
    except Exception as error:
        records.append({'id': item['id'], 'passed': False, 'error': str(error)})
report = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'sourceSha256': manifest['sourceSha256'], 'passed': len(records) == 44 and all(x['passed'] for x in records), 'scope': 'Pillow verify then full load of every PNG. Read only; no pixel transformation. Not browser rendering or historical verification.', 'images': records}
(directory / 'decode-verification.json').write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'passed': report['passed'], 'images': len(records), 'sourceSha256': report['sourceSha256']}))
raise SystemExit(0 if report['passed'] else 1)
