"""Run the existing hero topic's formal-light GPU study with raw process proof."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--godot", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--aa-study", action="store_true")
    parser.add_argument("--upper-study", action="store_true")
    parser.add_argument("--palette-study", action="store_true")
    parser.add_argument("--world-study", action="store_true")
    parser.add_argument("--rig-study", action="store_true")
    parser.add_argument("--filter-study", action="store_true")
    parser.add_argument("--proxy-study", action="store_true")
    parser.add_argument("--model", choices=["art_r6", "art_r7a", "art_r7b", "art_r7c", "art_r8b", "art_r9", "art_r9b", "art_r11", "art_r11b", "art_r12", "art_r13", "art_r14b"], default="art_r6")
    args = parser.parse_args()
    if sum([args.aa_study, args.upper_study, args.palette_study, args.world_study, args.rig_study, args.filter_study, args.proxy_study]) > 1:
        parser.error("independent study mode required")
    root = Path(__file__).resolve().parents[2]
    output = args.output.resolve()
    output.relative_to(root)
    if output.exists():
        raise SystemExit("fresh output directory required")
    proof_path = output.with_name(output.name + "-process.json")
    log_path = output.with_name(output.name + "-process.log")
    if proof_path.exists() or log_path.exists():
        raise SystemExit("fresh process evidence required")
    output.parent.mkdir(parents=True, exist_ok=True)
    resource = "res://" + output.relative_to(root).as_posix()
    command = ["rtk", "proxy", str(args.godot), "--path", str(root), "--script",
               "res://tools/research/compare-hero-formal-light.gd", "--", "--output=" + resource]
    if args.aa_study:
        command.append("--aa-study")
    if args.upper_study:
        command.append("--upper-study")
    if args.palette_study:
        command.append("--palette-study")
    if args.world_study:
        command.append("--world-study")
    if args.rig_study:
        command.append("--rig-study")
    if args.filter_study:
        command.append("--filter-study")
    if args.proxy_study:
        command.append("--proxy-study")
    command.append("--model=" + args.model)
    started = time.time()
    timed_out = False
    with log_path.open("w", encoding="utf-8") as log:
        process = subprocess.Popen(command, cwd=root, stdout=log, stderr=subprocess.STDOUT)
        try:
            exit_code = process.wait(timeout=250)
        except subprocess.TimeoutExpired:
            timed_out = True
            subprocess.run(["rtk", "proxy", "taskkill", "/PID", str(process.pid), "/T", "/F"],
                           check=False, capture_output=True)
            exit_code = process.wait(timeout=15)
    raw = log_path.read_text(encoding="utf-8", errors="replace")
    errors = [line for line in raw.splitlines()
              if "ERROR:" in line or "SCRIPT ERROR:" in line or line.startswith("FAIL:")]
    markers = [line for line in raw.splitlines() if line.startswith("HERO_FORMAL_LIGHT_STUDY ")]
    report_path = output / "LIGHT_STUDY.json"
    report = json.loads(report_path.read_text(encoding="utf-8")) if report_path.exists() else {}
    valid = (exit_code == 0 and not timed_out and not errors and len(markers) == 1
             and report.get("valid") is True
             and len(report.get("captures", [])) == (79 if args.aa_study else 7 if args.upper_study else 3 if args.palette_study else 2 if args.world_study else 11 if args.rig_study else 59 if args.filter_study else 13 if args.proxy_study else 9))
    proof = {"recordType": "gpu-process", "valid": valid, "command": command,
             "exitCode": exit_code, "timedOut": timed_out, "elapsedSeconds": time.time() - started,
             "errors": errors, "completionMarkers": markers,
             "reportSHA256": hashlib.sha256(report_path.read_bytes()).hexdigest() if report_path.exists() else None,
             "log": str(log_path.relative_to(root))}
    proof_path.write_text(json.dumps(proof, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(proof, ensure_ascii=False))
    return 0 if valid else 1


if __name__ == "__main__":
    raise SystemExit(main())
