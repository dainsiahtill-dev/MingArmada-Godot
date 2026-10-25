"""Decode every generated model sheet; does not edit images."""
import json
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from PIL import Image

files = sorted(Path('assets/production/model-kit-v1').rglob('multiview-v*.png'))
errors, dimensions = [], Counter()
for image_path in files:
    try:
        with Image.open(image_path) as image:
            image.load()
            dimensions[f'{image.width}x{image.height}'] += 1
    except Exception as error:
        errors.append({'path': image_path.as_posix(), 'error': str(error)})
result = {'checkedAt': datetime.now(timezone.utc).isoformat(), 'files': len(files),
          'dimensions': dict(dimensions), 'errors': errors, 'valid': not errors}
Path('docs/production/model-preproduction-2026-10-24/verification-image-decode.json').write_text(
    json.dumps(result, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps(result, ensure_ascii=False))
raise SystemExit(1 if errors else 0)
