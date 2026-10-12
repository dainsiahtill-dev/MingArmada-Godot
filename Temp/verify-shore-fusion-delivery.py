"""Collect scoped evidence without replacing the project's full test matrix."""
import hashlib
import json
from pathlib import Path

root = Path(__file__).resolve().parents[1]
base = root / "docs/migration/evidence/integrated-world"
reports = {}
for name in ("combined-tests-v3", "surf-tests-v3", "ocean-tests-v3", "physical-waves-v3"):
    path = base / "shore-fusion-headless" / (name + ".json")
    report = json.loads(path.read_text(encoding="utf-8"))
    assert report["summary"]["passedAll"]
    reports[name] = {"path": path.relative_to(root).as_posix(), "summary": report["summary"]}
gpu = {}
hashes = {}
for name in ("shore-fusion-motion-v3", "shore-fusion-world-v3"):
    path = base / name / "capture-result.json"
    report = json.loads(path.read_text(encoding="utf-8"))
    assert report["failures"] == 0
    assert report["captures"]
    for capture in report["captures"]:
        png = path.parent / (capture["label"] + ".png")
        assert hashlib.sha256(png.read_bytes()).hexdigest() == capture["imageSha256"]
        for resource, expected in capture.get("productionShaderHashes", {}).items():
            actual = hashlib.sha256((root / resource.removeprefix("res://")).read_bytes()).hexdigest()
            assert actual == expected
            hashes[resource] = actual
    log = (root / "Temp" / ("fusion-motion-v3.log" if "motion" in name else "fusion-world-v3.log")).read_text(encoding="utf-8")
    assert not any(token in log for token in ("SCRIPT ERROR", "Shader compilation failed", "Parse Error", "ERROR:"))
    gpu[name] = {"path": path.relative_to(root).as_posix(), "captures": len(report["captures"]), "failures": report["failures"], "gpu": report["gpu"]}
island_hash = hashlib.sha256((root / "modules/scene_engine/terrain/natural_island_field.gd").read_bytes()).hexdigest()
assert island_hash == "37983951b5a8a6b90e7639bc9983a8cc8d8f117cb65e0e84457b25f189b4cf03"
motion = json.loads((base / "shore-fusion-motion-v3/motion-proof.json").read_text(encoding="utf-8"))
assert motion["decodedPixelsEqualNativePng"] and motion["frames"] == 42
proof = {
    "schemaVersion": 1,
    "scope": "Two advancing shore waves fused in the existing shared Godot game presentation; this is not whole-project or user visual acceptance.",
    "composition": {
        "primary": "Existing coast-distance curved fronts drive the only advancing phase, strength .36 (previous .18).",
        "detail": "Original surf texture and 8 mips; selected authored quad dimensions, co-located pairs, deterministic staggered clocks, source alpha plus game lifecycle, texture crest reanchored to the same phase.",
        "contact": "Edge wash and contact lace use independent .38 residue multiplier; lace uses continuous coverage through cycle seams.",
        "grain": "Owner-controlled native GPU isolation demonstrated fixed 0.444m cells; continuous grain removes square stamps.",
        "physics": "Existing five-wave displacement retained; accepted island generator unchanged.",
    },
    "headless": reports, "gpu": gpu, "productionShaderHashes": hashes,
    "islandGeneratorSha256": island_hash,
    "motion": motion,
    "independentReview": "Contact cycle seam found and corrected; reviewer inspected 9 current key PNGs and current shader hashes, without GPU runs or edits.",
    "inspectionLimits": "Dense capture covers 6.0..10.1s at .1s intervals plus sparse lifecycle 18/24/29/30/36s; no claim about all possible subframe states, target performance, unrelated full-matrix failures or unfinished world art.",
}
output = base / "shore-fusion-delivery-v3.json"
assert not output.exists()
output.write_text(json.dumps(proof, indent=2, ensure_ascii=False), encoding="utf-8")
print(json.dumps({"tests": sum(r["summary"]["selected"] for r in reports.values()), "testFailures": 0, "captures": sum(r["captures"] for r in gpu.values()), "captureFailures": 0, "currentShaderHashesMatch": True, "islandUnchanged": True, "losslessMotionFrames": motion["frames"], "evidence": output.relative_to(root).as_posix()}))
