"""Index unmodified native PNGs; create labeled contact sheets for manual review."""
from pathlib import Path
import hashlib
import json
from PIL import Image, ImageDraw, ImageChops, ImageStat

ROOT = Path(__file__).resolve().parents[2]
DIRECTORY = ROOT / "docs/migration/evidence/reference-demo-port"

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

records = []
for metadata in sorted(DIRECTORY.glob("*.json")):
    if metadata.name in {"visual-index.json", "manual-review.json"}: continue
    data = json.loads(metadata.read_text(encoding="utf-8"))
    if "snapshot" not in data: continue
    record = {"label":metadata.stem,"metadata":str(metadata),"metadataSha256":sha(metadata),"snapshot":data["snapshot"],"images":[]}
    for suffix in ["", "-ui"]:
        path = metadata.with_name(metadata.stem+suffix+".png")
        with Image.open(path) as image:
            record["images"].append({"path":str(path),"sha256":sha(path),"size":list(image.size),"controls":bool(suffix)})
    records.append(record)

sheets=[]
for start in range(0,len(records),3):
    sheet=Image.new("RGB",(1520,1440),(16,25,32))
    draw=ImageDraw.Draw(sheet)
    for row,record in enumerate(records[start:start+3]):
        for column,entry in enumerate(record["images"]):
            with Image.open(entry["path"]) as image:
                image=image.convert("RGB"); image.thumbnail((744,444))
                sheet.paste(image,(column*760+8,row*480+8))
            draw.text((column*760+12,row*480+456),record["label"]+(" [native UI]" if entry["controls"] else " [3D viewport]"),fill="white")
    target=DIRECTORY/f"contact-{start//3+1:02d}.jpg"
    sheet.save(target,quality=93)
    sheets.append({"path":str(target),"sha256":sha(target),"labels":[r["label"] for r in records[start:start+3]]})

differences=[]
for first,second in [("clear","paused"),("clear","reflection-off"),("clear","foam-off"),("clear","caustics-off"),("clear","waves-off"),("low-angle","low-angle-reflection-off")]:
    with Image.open(DIRECTORY/(first+".png")) as a,Image.open(DIRECTORY/(second+".png")) as b:
        delta=ImageChops.difference(a.convert("RGB"),b.convert("RGB"))
        differences.append({"first":first,"second":second,"samePixels":delta.getbbox() is None,"meanAbsoluteRgb":ImageStat.Stat(delta).mean,"scope":"Same native camera and accepted time; effect state differs except pause. Not a WebGL/Godot pixel equivalence claim."})

output={"schema":"ming-armada-reference-demo-native-index-v1","captureStates":len(records),"nativePngCount":sum(len(r["images"]) for r in records),"captures":records,"contactSheets":sheets,"nativeDifferences":differences,"scope":"Actual GPU PNGs remain unmodified. Contact sheets are derived viewing aids; no performance conclusions."}
(DIRECTORY/"visual-index.json").write_text(json.dumps(output,ensure_ascii=False,indent=2),encoding="utf-8")
print(f"REFERENCE_DEMO_VISUAL_INDEX states={len(records)} pngs={output['nativePngCount']} sheets={len(sheets)} failures=0")
print(json.dumps(differences,ensure_ascii=False))
