"""Encode actual Godot viewport PNGs as an animation, with capture provenance.

This tool does not create artwork. Original full-resolution PNG/JSON captures
remain the evidence; the GIF is only a resized, palette-encoded preview.
"""

import argparse
import hashlib
import json
from pathlib import Path

from PIL import Image


def build(directory: Path, count: int, preview_only: bool = False) -> None:
    frames = []
    records = []
    previous_time = None
    previous_tick = None
    size = None
    for index in range(count):
        stem = f"shore-wave-{index:02d}"
        png = directory / f"{stem}.png"
        metadata = json.loads((directory / f"{stem}.json").read_text(encoding="utf-8"))
        seconds = metadata["campaign"]["simulationSeconds"]
        tick = metadata["naval"]["tick"]
        if metadata["uiVisible"] is not False:
            raise ValueError(f"{stem}: capture unexpectedly includes the UI")
        if previous_time is not None:
            if abs(seconds - previous_time - 1 / 12) > 1e-9 or tick - previous_tick != 5:
                raise ValueError(f"{stem}: capture simulation sequence is discontinuous")
        with Image.open(png) as original:
            if size is None:
                size = original.size
            if original.size != size or list(size) != metadata["viewport"]:
                raise ValueError(f"{stem}: viewport size mismatch")
            frames.append(original.convert("RGB"))
        records.append({
            "png": png.name,
            "sha256": hashlib.sha256(png.read_bytes()).hexdigest(),
            "simulationSeconds": seconds,
            "tick": tick,
        })
        previous_time, previous_tick = seconds, tick

    small = [frame.resize((960, 540), Image.Resampling.LANCZOS) for frame in frames]
    small[0].save(directory / "shore-waves-preview.webp", save_all=True,
                  append_images=small[1:], duration=83, loop=0, lossless=False, quality=90, method=1)
    preview_metadata = {"file": "shore-waves-preview.webp", "pixels": [960, 540], "lossless": False, "quality": 90, "resizedFromNativeViewport": True}
    if preview_only:
        # Only reuse existing full-size evidence when its source frames match.
        manifest_path = directory / "shore-waves-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest["frames"] != records:
            raise ValueError("full-size animation provenance differs; run the complete build")
        manifest["previewWebp"] = preview_metadata
        manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"NATIVE_WAVE_SMALL_PREVIEW frames={count} webp=960x540 quality=90 original-PNGs-unchanged")
        return

    # Preserve native pixels in the WebP. GIF uses a single palette sampled
    # across the whole recording to avoid per-frame color flashing.
    frames[0].save(directory / "shore-waves.webp", save_all=True,
                   append_images=frames[1:], duration=83, loop=0, lossless=True, method=4)
    atlas = Image.new("RGB", (320 * 4, 180 * 3))
    for tile in range(12):
        sample = small[tile * (count - 1) // 11].resize((320, 180))
        atlas.paste(sample, ((tile % 4) * 320, (tile // 4) * 180))
    palette = atlas.quantize(colors=224, method=Image.Quantize.MEDIANCUT)
    gif_frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in small]
    gif_frames[0].save(directory / "shore-waves.gif", save_all=True,
                       append_images=gif_frames[1:], duration=80, loop=0, optimize=False)
    manifest = {
        "source": "Godot get_viewport().get_texture().get_image() native PNG captures",
        "engine": metadata["engine"], "gpu": metadata["gpu"],
        "camera": metadata["camera"], "originalViewport": list(size),
        "frameCount": count, "simulationStepSeconds": 1 / 12,
        "simulationRangeSeconds": [records[0]["simulationSeconds"], records[-1]["simulationSeconds"]],
        "nativeTickRange": [records[0]["tick"], records[-1]["tick"]],
        "webp": {"file": "shore-waves.webp", "pixels": list(size), "lossless": True},
        "previewWebp": preview_metadata,
        "gif": {"file": "shore-waves.gif", "pixels": [960, 540], "colors": 224},
        "performanceNote": "Encoding/capture wall time and frameTimeMs include synchronous PNG/JSON writes; this is not a GPU FPS benchmark.",
        "loopNote": "The recording repeats; its end-to-start seam is not part of the native simulation.",
        "frames": records,
    }
    (directory / "shore-waves-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"NATIVE_WAVE_PREVIEW frames={count} ticks={manifest['nativeTickRange']} "
          f"simulation={manifest['simulationRangeSeconds']} webp=lossless gif=960x540")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", type=Path)
    parser.add_argument("--frames", type=int, default=72)
    parser.add_argument("--preview-only", action="store_true")
    arguments = parser.parse_args()
    if arguments.frames < 12:
        parser.error("at least 12 native frames are required")
    build(arguments.directory.resolve(), arguments.frames, arguments.preview_only)
