"""Exploratory, baseline-derived shoreline pixel metric; never image editing."""
import json
import sys
from pathlib import Path
import numpy as np
from PIL import Image

folder = Path(sys.argv[1])
width = int(sys.argv[2]) if len(sys.argv) > 2 else 60
rows, roi = [], []
for tick in (0, 16, 64, 256):
    a = np.asarray(Image.open(folder / f"edge-t{tick:03d}-w00.png")).astype(float)
    b = np.asarray(Image.open(folder / f"edge-t{tick:03d}-w{width:02d}.png")).astype(float)
    assert a.shape == b.shape
    h, w, _ = a.shape
    ga = np.linalg.norm(np.diff(a, axis=0), axis=2)
    gb = np.linalg.norm(np.diff(b, axis=0), axis=2)
    peaks = []
    for x in range(40, w - 40, 40):
        lo, hi = int(h * .08), int(h * .36)
        y = lo + int(np.argmax(ga[lo:hi, x]))
        peaks.append((float(ga[y, x]), float(gb[max(0, y-4):y+5, x].max())))
        roi.append(dict(tick=tick, x=x, y_baseline=y, radius=4))
    baseline, candidate = np.median(peaks, axis=0)
    rows.append(dict(tick=tick, baseline_rgb_jump=float(baseline),
                     candidate_local_max_rgb_jump=float(candidate),
                     ratio=float(candidate/baseline),
                     below_0_70=bool(candidate/baseline <= .70),
                     lower_half_exactly_equal=bool((a[h//2:] == b[h//2:]).all())))
proof = json.loads((folder / "GPU_VERIFY.json").read_text(encoding="utf-8"))
timings = {}
for value in (0, width/100):
    samples = sorted(t["wall_ms"] for t in proof["timings"] if abs(t["width"]-value) < 1e-6)
    timings[str(value)] = dict(n=len(samples), p50=samples[int(np.ceil(len(samples)*.5))-1],
                              p95=samples[int(np.ceil(len(samples)*.95))-1],
                              minimum=min(samples), maximum=max(samples))
result = dict(method="Exploratory baseline-only peak detection in fixed upper8%-36% image band; columns40..width-40 stride40; candidate local max same center+-4px. Not preregistered frozen ROI confirmation.",
              samples=rows, roi=roi, wall_frame_intervals=timings,
              timing_scope="32 interleaved pairs after40 warm-up frames, nearest rank; vsync and desktop load included. Not GPU timestamps/full-game performance.")
(folder / "PIXEL_ANALYSIS.json").write_text(json.dumps(result, indent=2)+"\n", encoding="utf-8")
print(json.dumps(dict(samples=rows, timings=timings)))
