"""Build the sunfaded R9b candidate with the frozen R9 image-only contract."""
from pathlib import Path
import build_hero_fuchuan_r9 as build

def main():
    root = Path(__file__).resolve().parents[2]
    build.PNG = root / 'assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png'
    build.EXPECTED_PNG_SHA = 'f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970'
    build.TARGET = root / 'assets/models/hero_fuchuan_v3_r9b'
    build.NEW_BLEND = root / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
    build.RECEIPT = build.EVIDENCE / 'blender-r9b.json'
    build.LOG = build.EVIDENCE / 'blender-r9b.log'
    build.MANIFEST = build.TARGET / 'manifest.json'
    build.REVISION = 'r9b'
    build.main()


if __name__ == '__main__':
    main()
