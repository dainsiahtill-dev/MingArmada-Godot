"""Measure the reproduced distant horizontal banding, not overall art quality."""
import argparse
import json
from pathlib import Path
import numpy as np
from PIL import Image

parser = argparse.ArgumentParser()
parser.add_argument("candidate", type=Path)
args = parser.parse_args()
baseline = Path("docs/migration/evidence/integrated-world/far-water-isolation-v1/far-water-baseline.png")

def band_measure(path):
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float64)
    assert rgb.shape == (900, 1600, 3)
    # An unobstructed far-water rectangle in the identical native camera.
    # Averaging across columns isolates broad coherent horizontal bands;
    # adjacent rows then remove the gentle sky/fog color gradient.
    row = rgb[215:300, 1050:1530].mean(axis=(1, 2))
    return float(np.sqrt(np.mean(np.diff(row) ** 2)))

before = band_measure(baseline)
after = band_measure(args.candidate)
ratio = after / before
print(json.dumps({"baselineRowRms": before, "candidateRowRms": after, "ratio": ratio, "roi": [1050, 215, 1530, 300], "scope": "Single reproduced view only; excludes islands and near water; not aesthetic acceptance."}))
assert ratio < 0.45, "Reproduced far horizontal stripe contrast remains above 45% of baseline"
