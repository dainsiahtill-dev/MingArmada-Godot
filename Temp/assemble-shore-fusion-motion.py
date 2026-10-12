"""Package actual Godot PNGs; preserve RGB pixels and their injected times."""
import hashlib
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
folder = root / "docs/migration/evidence/integrated-world/shore-fusion-motion-v3"
result = json.loads((folder / "capture-result.json").read_text(encoding="utf-8"))
assert result["failures"] == 0
samples = sorted(
    (capture for capture in result["captures"] if capture["label"].startswith("fusion-close-")),
    key=lambda capture: capture["snapshot"]["time"],
)
assert len(samples) == 42
frames = []
times = []
for capture in samples:
    path = folder / (capture["label"] + ".png")
    assert hashlib.sha256(path.read_bytes()).hexdigest() == capture["imageSha256"]
    assert capture["cameraFov"] == 25.0
    assert capture["productionShaderHashes"] == samples[0]["productionShaderHashes"]
    assert capture["snapshot"]["cameraPosition"] == samples[0]["snapshot"]["cameraPosition"]
    frame = Image.open(path).convert("RGB")
    assert frame.size == (1600, 900)
    frames.append(frame)
    times.append(capture["snapshot"]["time"])
assert all(abs(right - left - 0.1) < 0.000001 for left, right in zip(times, times[1:]))
output = folder / "shore-fusion-motion.webp"
assert not output.exists(), "Never overwrite earlier visual evidence"
frames[0].save(output, save_all=True, append_images=frames[1:], duration=100, loop=0, lossless=True, method=4)
with Image.open(output) as animation:
    assert animation.n_frames == len(frames)
    for index, original in enumerate(frames):
        animation.seek(index)
        assert animation.convert("RGB").tobytes() == original.tobytes(), "Lossless native-frame contract"
proof = {
    "frames": len(frames), "timeStart": times[0], "timeEnd": times[-1],
    "stepSeconds": 0.1, "size": [1600, 900], "cameraFov": 25.0,
    "sourceHashesVerified": True, "decodedPixelsEqualNativePng": True,
    "productionShaderHashes": samples[0]["productionShaderHashes"],
    "file": output.name, "bytes": output.stat().st_size,
    "sha256": hashlib.sha256(output.read_bytes()).hexdigest(),
    "scope": "Looping lossless excerpt of actual paused/manual-clock GPU PNGs; not a realtime frame-rate or full-scene visual acceptance test.",
}
(folder / "motion-proof.json").write_text(json.dumps(proof, indent=2), encoding="utf-8")
print(json.dumps(proof, ensure_ascii=False))
