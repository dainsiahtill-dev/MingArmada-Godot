"""Verify current far-water captures, near preservation, and scoped regressions."""
import hashlib
import json
import subprocess
from pathlib import Path
import numpy as np
from PIL import Image

root = Path(__file__).resolve().parents[1]
base = root / "docs/migration/evidence/integrated-world"
output = base / "far-water-delivery-v2.json"
assert not output.exists(), "Preserve earlier evidence"
captures = {}
hashes = {}
for folder, logname in (("far-water-final-v2", "far-water-final-v2.log"), ("far-water-regression-ab-v2", "far-water-regression-ab-v2.log")):
    record = json.loads((base / folder / "capture-result.json").read_text(encoding="utf-8"))
    assert record["failures"] == 0
    for item in record["captures"]:
        path = base / folder / (item["label"] + ".png")
        assert hashlib.sha256(path.read_bytes()).hexdigest() == item["imageSha256"]
        for resource, expected in item.get("productionShaderHashes", {}).items():
            actual = hashlib.sha256((root / resource.removeprefix("res://")).read_bytes()).hexdigest()
            assert expected == actual
            hashes[resource] = actual
    log = (root / "Temp" / logname).read_text(encoding="utf-8")
    assert not any(token in log for token in ("SCRIPT ERROR", "Parse Error", "Shader compilation failed", "ERROR:"))
    captures[folder] = {"captures": len(record["captures"]), "failures": 0, "gpu": record["gpu"]}

tests = {}
for name in ("ocean-v2", "physical-waves-v2", "combined-v2", "shore-v2"):
    path = base / "far-water-tests" / (name + ".json")
    record = json.loads(path.read_text(encoding="utf-8"))
    assert record["summary"]["passedAll"]
    tests[name] = record["summary"]
math = subprocess.run(["rtk", "proxy", "node", "--test", "tests/test_macro_wave_optics.mjs"], cwd=root, text=True, capture_output=True, encoding="utf-8")
assert math.returncode == 0, math.stdout + math.stderr
assert "pass 11" in math.stdout and "fail 0" in math.stdout and "skipped 0" in math.stdout
(base / "far-water-tests/macro-math-v2.log").write_text(math.stdout + math.stderr, encoding="utf-8")

def rgb(path):
    return np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)

ab = base / "far-water-regression-ab-v2"
preservation = {}
for name, roi in (("near", (340, 400, 1500, 850)), ("near-low", (400, 600, 1500, 850))):
    x0, y0, x1, y1 = roi
    fixed = rgb(ab / ("regression-" + name + "-fixed.png"))
    original = rgb(ab / ("regression-" + name + "-unfiltered.png"))
    difference = np.abs(fixed[y0:y1, x0:x1] - original[y0:y1, x0:x1])
    assert np.max(difference) == 0.0
    preservation[name] = {"roi": roi, "meanChannelDifference": float(difference.mean()), "maxChannelDifference": float(difference.max()), "identicalPixelFraction": 1.0}

def horizontal_bands(path):
    rows = rgb(path)[215:300, 1050:1530].mean(axis=(1, 2))
    return float(np.sqrt(np.mean(np.diff(rows) ** 2)))

before = horizontal_bands(ab / "regression-far-unfiltered.png")
after = horizontal_bands(ab / "regression-far-fixed.png")
assert after / before < 0.45
island = hashlib.sha256((root / "modules/scene_engine/terrain/natural_island_field.gd").read_bytes()).hexdigest()
assert island == "37983951b5a8a6b90e7639bc9983a8cc8d8f117cb65e0e84457b25f189b4cf03"
proof = {
    "schemaVersion": 1,
    "scope": "Existing shared Godot water material: distant optical wave banding repair. Scoped static/motion-sample evidence; not whole-project visual acceptance.",
    "rootCause": "Owner-controlled single-layer GPU isolation: flat optical macro and flat Fresnel remove the reproduced bands; no texture-normal, no additive specular and no body light retain them.",
    "frequencyFilter": "Each wave uses continuous phase footprint projected from world-coordinate screen derivatives. Resolved waves preserved; compressed short waves fade before Nyquist.",
    "displayAdaptation": "Long-wave grazing reflection contrast is softened in the middle/far field; distance <=180m and steep abs(viewY)>=.4 preserve full macro optics. Smooth distance/angle transitions, separate from physical wave state.",
    "counterfactual": "Regression *-unfiltered images restore only old n=normalize(macro_normal+texture_slopes) after the owner updates. Production shader hash refers to the current source, not this diagnostic override.",
    "captures": captures,
    "headless": tests,
    "actualGlslScalarTests": {"passed": 11, "failed": 0, "skipped": 0, "scope": "Actual GLSL scalar bodies read/transpiled, not GPU derivative execution."},
    "sameCameraNearPreservation": preservation,
    "farHorizontalBandMeasure": {"roi": [1050, 215, 1530, 300], "before": before, "after": after, "ratio": after / before, "scope": "Single reproduced, unobstructed far-water view; not a general aesthetic score."},
    "productionShaderHashes": hashes,
    "islandGeneratorSha256": island,
    "retained": "Five-wave physical/vertex displacement, current optical texture bands, authored surf and .36 primary/.38 residue shoreline settings.",
    "review": "Independent code and seven current key-image review found no concrete blocking issue; first frequency-only visual result was rejected because broad repeated bands still dominated.",
    "limitations": "Sampled times12/12.1/12.2/18/24 and several angles/zoom levels; not proof of every subframe, all camera states, all graphics hardware or unrelated full-suite completion.",
}
output.write_text(json.dumps(proof, indent=2), encoding="utf-8")
print(json.dumps({"captures": sum(r["captures"] for r in captures.values()), "captureFailures": 0, "headlessSelected": sum(r["selected"] for r in tests.values()), "mathTests": 11, "farBandRatio": after / before, "nearRoiMaxDiff": 0, "lowNearRoiMaxDiff": 0, "evidence": output.relative_to(root).as_posix()}))
