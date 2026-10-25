"""Copy the unedited built-in image_gen outputs into the project."""
from pathlib import Path
import hashlib, json, shutil, struct

root = Path(__file__).resolve().parents[2]
source = Path(r'C:/Users/dains/.codex/generated_images/01a172ba-3d47-7490-88ee-52dc41a9c20a')
out = root / 'assets/textures/hero_fuchuan_v2'
out.mkdir(parents=True, exist_ok=True)
images = {
    'weathered-hull-wood': 'exec-8e5efa7a-7e87-4b05-b660-e717466f0917.png',
    'sunworn-deck-wood': 'exec-831f0a04-cc04-4994-b099-e8cbd4761d42.png',
    'antique-hemp-sail': 'exec-6bd43552-ffe8-46f5-904a-af148b2de691.png',
    'aged-forged-iron': 'exec-105acc9f-08dd-4786-96fe-92f92604e8c4.png',
}
items = []
for name, filename in images.items():
    target = out / (name + '.png')
    shutil.copy2(source / filename, target)
    data = target.read_bytes()
    width, height = struct.unpack('>II', data[16:24])
    items.append({'id': name, 'path': target.relative_to(root).as_posix(), 'sourceFilename': filename, 'bytes': len(data), 'width': width, 'height': height, 'sha256': hashlib.sha256(data).hexdigest()})
(out / 'provenance.json').write_text(json.dumps({'generator': 'built-in image_gen', 'prompts': 'assets/production/hero-fuchuan-blender/texture-prompts-v2.json', 'pixelEdits': 'none; original generated images copied byte-for-byte', 'usage': 'sRGB base color only, not measured PBR maps', 'images': items}, indent=2), encoding='utf-8')
backup = root / 'assets/production/hero-fuchuan-blender/build_hero_fuchuan-v1.py'
if not backup.exists():shutil.copy2(root / 'tools/blender/build_hero_fuchuan.py', backup)
print(json.dumps(items, indent=2))
