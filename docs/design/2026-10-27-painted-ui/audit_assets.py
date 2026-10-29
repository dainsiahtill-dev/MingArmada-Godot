"""Read-only PNG alpha audit; enrich ASSETS.json. No image modification."""
from pathlib import Path
from PIL import Image
from collections import Counter
import hashlib, json
root = Path(__file__).resolve().parents[3]
manifest_path = Path(__file__).with_name("ASSETS.json")
data = json.loads(manifest_path.read_text(encoding="utf-8"))
for asset in data["assets"]:
    for source in asset.get("source_contract", {}).get("files", []):
        source["sha256"] = hashlib.sha256((root/source["path"]).read_bytes()).hexdigest()
    path = root / asset["path"]
    raw = path.read_bytes()
    with Image.open(path) as im:
        rgba = im.convert("RGBA")
        alpha = rgba.getchannel("A")
        hist = alpha.histogram()
        bbox = alpha.getbbox()
        opaque_bbox = alpha.point(lambda a: 255 if a == 255 else 0).getbbox()
        asset["size"] = list(im.size)
        asset["mode"] = im.mode
        asset["sha256"] = hashlib.sha256(raw).hexdigest()
        asset["bytes"] = len(raw)
        asset["source_byte_identical"] = raw == Path(asset["generation_source"]).read_bytes()
        asset["alpha"] = {
            "min": alpha.getextrema()[0], "max": alpha.getextrema()[1],
            "fully_transparent_pixels": hist[0], "fully_opaque_pixels": hist[255],
            "partial_alpha_pixels": sum(hist[1:255]),
            "nonzero_bbox_xyxy": list(bbox) if bbox else None,
            "opaque_bbox_xyxy": list(opaque_bbox) if opaque_bbox else None,
            "transparent_fraction": hist[0] / (im.width * im.height),
            "center_rgba": rgba.getpixel((im.width//2, im.height//2)),
            "has_real_transparency": hist[0] > 0 and hist[255] > 0
        }
        # Edge-color statistics only; do not edit generated pixels.
        pixels = rgba.get_flattened_data() if hasattr(rgba, "get_flattened_data") else rgba.getdata()
        asset["alpha"]["partial_alpha_top_rgb"] = [
            [list(c), n] for c, n in Counter((r,g,b) for r,g,b,a in pixels
                if 0 < a < 255).most_common(3)
        ]
        assert asset["source_byte_identical"], f"Source bytes changed: {path}"
        assert asset["alpha"]["has_real_transparency"], f"Missing genuine alpha: {path}"
        print(json.dumps({k:asset[k] for k in ["key","size","mode","sha256","alpha"]}))
manifest_path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+"\n",encoding="utf-8")
