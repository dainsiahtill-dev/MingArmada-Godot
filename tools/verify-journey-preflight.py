"""Cheap headless QA guard checks. Never runs a voyage or a GPU scene."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_GODOT = "C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe"
OLD = "res://docs/migration/evidence/opening-story/journey-formal-manual-fire-return.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--godot", default=DEFAULT_GODOT)
    parser.add_argument("--report", default="build/port-approach-work/qa-tooling-preflight.json")
    args = parser.parse_args()
    historical = ROOT / OLD.removeprefix("res://")
    historical_sha = hashlib.sha256(historical.read_bytes()).hexdigest()
    token = str(time.time_ns())
    first_output = f"res://docs/migration/evidence/opening-story/qa-preflight-unused-first-{token}.json"
    second_output = f"res://docs/migration/evidence/opening-story/qa-preflight-unused-second-{token}.json"
    rows = []

    def run(script, user_args, code, marker):
        command = ["rtk", "proxy", args.godot, "--headless", "--path", str(ROOT), "--script", f"res://tools/{script}", "--", *user_args]
        finished = subprocess.run(command, cwd=ROOT, text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=30)
        output = finished.stdout + finished.stderr
        passed = finished.returncode == code and marker in output and not any(value in output for value in ("SCRIPT ERROR:", "ERROR:", "STORY_JOURNEY ", "CONTINUED_VOYAGE actual-", "JOURNEY_COMPLETE"))
        rows.append({"command":command,"exitCode":finished.returncode,"expectedExitCode":code,"marker":marker,"passed":passed,"output":output})

    run("test-journey-output-guard.gd", [], 0, "JOURNEY_OUTPUT_GUARD_TESTS assertions=18 failures=0")
    run("test-journey-checkpoint.gd", [], 0, "JOURNEY_CHECKPOINT_TESTS assertions=10 failures=0")
    run("play-opening-story-journey.gd", [f"--output={first_output}", "--preflight"], 0, "OPENING_JOURNEY_PREFLIGHT_PASS acceptedSeconds=0")
    run("play-continued-voyage.gd", [f"--journey={OLD}", f"--output={second_output}", "--preflight"], 0, "CONTINUED_VOYAGE_PREFLIGHT_PASS acceptedSeconds=0")
    # No --preflight on rejections: prove normal execution stops at guard.
    run("play-opening-story-journey.gd", [f"--output={OLD}"], 2, "JOURNEY_OUTPUT_REJECTED evidence-already-exists")
    run("play-opening-story-journey.gd", ["--output=C:/outside.json"], 2, "JOURNEY_OUTPUT_REJECTED workspace-evidence-json-required")
    run("play-opening-story-journey.gd", [], 2, "JOURNEY_OUTPUT_REJECTED one-explicit---output-required")
    run("play-continued-voyage.gd", [f"--journey={OLD}", f"--output={OLD}"], 2, "CONTINUED_VOYAGE_PREFLIGHT_REJECTED evidence-already-exists")
    run("play-continued-voyage.gd", [f"--journey={OLD}", "--output=C:/outside.json"], 2, "CONTINUED_VOYAGE_PREFLIGHT_REJECTED workspace-evidence-json-required")
    run("play-continued-voyage.gd", [f"--output={second_output}"], 2, "CONTINUED_VOYAGE_PREFLIGHT_REJECTED one-explicit---journey-required")
    historical_unchanged = hashlib.sha256(historical.read_bytes()).hexdigest() == historical_sha
    no_outputs_created = all(not (ROOT / path.removeprefix("res://")).exists() for path in (first_output, second_output))
    report = {"mode":"headless path guards and preflight only; no runtime advancement, voyage, user Storage, GPU or performance claim","cases":rows,"historicalJourneySha256":historical_sha,"historicalUnchanged":historical_unchanged,"preflightCreatedNoOutputs":no_outputs_created,"assertions":len(rows)+2,"failures":sum(not row["passed"] for row in rows)+int(not historical_unchanged)+int(not no_outputs_created)}
    report_path = ROOT / args.report
    if not report_path.resolve().is_relative_to(ROOT / "build" / "port-approach-work"):
        raise ValueError("selftest report must remain in build/port-approach-work")
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"JOURNEY_PREFLIGHT_VERIFIER assertions={report['assertions']} failures={report['failures']} report={report_path}")
    return 1 if report["failures"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
