"""Hash native PNGs and assemble labelled contact sheets for manual review.

The sheets are derived inspection aids. The adjacent original PNG/JSON pairs
remain the actual GPU evidence; no pixels in those captures are changed.
"""
import hashlib
import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageOps

ROOT = Path(__file__).resolve().parents[2]
EVIDENCE = ROOT / "docs/migration/evidence"
DEST = EVIDENCE / "reference-implementation"
GROUPS = ("reference-implementation", "reference-implementation-qa", "reference-implementation-events", "reference-implementation-optics")


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    records = []
    for group in GROUPS:
        for path in sorted((EVIDENCE / group).glob("*.png")):
            if path.name.startswith(("contact-sheet-", "demo-")):
                continue
            metadata = path.with_suffix(".json")
            if not metadata.is_file():
                raise RuntimeError(f"Missing native metadata: {path}")
            data = json.loads(metadata.read_text(encoding="utf-8"))
            with Image.open(path) as image:
                size = list(image.size)
            records.append({"group": group, "label": path.stem, "png": str(path),
                            "sha256": sha256(path), "dimensions": size,
                            "metadata": str(metadata), "metadataSha256": sha256(metadata),
                            "route": data.get("route"), "gpu": data.get("gpu"),
                            "scope": data.get("scope")})
    sheets = []
    for page, start in enumerate(range(0, len(records), 6), 1):
        items = records[start:start + 6]
        sheet = Image.new("RGB", (1600, 3 * 478), "#162329")
        draw = ImageDraw.Draw(sheet)
        for index, record in enumerate(items):
            x = index % 2 * 800
            y = index // 2 * 478
            with Image.open(record["png"]) as image:
                thumb = ImageOps.contain(image.convert("RGB"), (800, 450))
                sheet.paste(thumb, (x + (800 - thumb.width) // 2, y))
            draw.text((x + 8, y + 455), f'{start + index + 1:02d} {record["group"]}: {record["label"]}', fill="white")
        path = DEST / f"contact-sheet-{page}.png"
        sheet.save(path)
        sheets.append({"path": str(path), "sha256": sha256(path), "captureIndices": list(range(start + 1, start + len(items) + 1))})
    output = {"schema": "ming-armada-reference-native-visual-index-v1", "captureCount": len(records),
              "captures": records, "contactSheets": sheets,
              "scope": "Original Godot GPU PNG/JSON pairs; contact sheets are derived viewing aids. Manual inspection is recorded separately in the acceptance report. Fixed capture ticks do not measure FPS."}
    (DEST / "visual-index.json").write_text(json.dumps(output, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE_VISUAL_INDEX captures={len(records)} sheets={len(sheets)} failures=0")


if __name__ == "__main__":
    main()
