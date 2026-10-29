"""Exercise real Godot refusal paths without a GPU or player profile writes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
GODOT = Path(os.environ.get(
    "GODOT_EXE",
    "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe",
))
temp_root = ROOT / "Temp"
temp_root.mkdir(exist_ok=True)
run = Path(tempfile.mkdtemp(prefix="hero-gpu-guards-", dir=temp_root))
profile = run / "profile"
profile.mkdir()
environment = dict(os.environ, APPDATA=str(profile), LOCALAPPDATA=str(profile))
failures = []
checks = []


def check(condition, description):
    checks.append({"description": description, "ok": bool(condition)})
    if not condition:
        failures.append(description)


def invoke(name, arguments, expected):
    output = run / name
    relative = "res://" + output.relative_to(ROOT).as_posix()
    command = [str(GODOT), "--headless", "--path", str(ROOT), "--script",
               "res://tools/verify-hero-fuchuan-gpu.gd", "--", *arguments,
               "--output=" + relative]
    if name == "occupied":
        output.mkdir()
        (output / "keep.txt").write_text("untouched", encoding="utf8")
    try:
        child = subprocess.run(command, cwd=ROOT, env=environment,
                               capture_output=True, text=True, timeout=8)
        combined = child.stdout + "\n" + child.stderr
        actual_exit = child.returncode
        timed_out = False
    except subprocess.TimeoutExpired as exc:
        chunks = [exc.stdout or b"", exc.stderr or b""]
        combined = "\n".join(x.decode("utf8", errors="replace") if isinstance(x, bytes) else x for x in chunks)
        actual_exit = None
        timed_out = True
    (run / (name + ".log")).write_text(combined, encoding="utf8")
    check(not timed_out and actual_exit != 0, name + " refuses promptly with nonzero exit")
    check(expected in combined, name + " reports the real refusal reason")
    check("SCRIPT ERROR:" not in combined and "ERROR: Failed to load script" not in combined,
          name + " is an intentional refusal rather than a script error")
    if name == "occupied":
        check((output / "keep.txt").read_text(encoding="utf8") == "untouched"
              and len(list(output.iterdir())) == 1, "occupied output was not modified")
    else:
        check(not output.exists(), name + " does not create output before validation")


invoke("invalid", ["--model=not-a-real-model", "--shadows=authored"], "invalid-model-options")
invoke("headless", ["--model=art_r8b", "--shadows=authored"], "GPU display unavailable")
invoke("headless-r9", ["--model=art_r9", "--shadows=authored", "--daylight=source_corrected"], "GPU display unavailable")
invoke("headless-r9b", ["--model=art_r9b", "--shadows=authored", "--daylight=source_corrected"], "GPU display unavailable")
invoke("occupied", ["--model=art_r8b", "--shadows=authored"], "fresh output directories required")
receipt = {"scope": "real headless Godot refusal paths only; no GPU claim",
           "run": str(run), "checks": checks, "failures": failures}
(run / "receipt.json").write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf8")
print("HERO_GPU_GUARDS assertions=%d failures=%d receipt=%s" % (len(checks), len(failures), run / "receipt.json"))
for failure in failures:
    print("FAIL: " + failure)
raise SystemExit(1 if failures else 0)
