"""Capture Blender's real process status without PowerShell stderr conversion."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--blender', required=True)
    parser.add_argument('--source', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    source, output = args.source.resolve(), args.output.resolve()
    source.relative_to(root)
    relative = output.relative_to(root).as_posix()
    proof, log = output.with_name(output.name + '-process.json'), output.with_name(output.name + '-process.log')
    if output.exists() or proof.exists() or log.exists():
        raise SystemExit('fresh output and evidence paths required')
    output.parent.mkdir(parents=True, exist_ok=True)
    before = hashlib.sha256(source.read_bytes()).hexdigest()
    command = ['rtk', 'proxy', args.blender, '--background', str(source), '--python',
               str(root / 'tools/blender/render_hero_palette_review.py'), '--', '--review-output=' + relative]
    started = time.monotonic()
    with log.open('w', encoding='utf-8') as stream:
        process = subprocess.Popen(command, cwd=root, stdout=stream, stderr=subprocess.STDOUT)
        try:
            code = process.wait(timeout=180)
            timeout = False
        except subprocess.TimeoutExpired:
            subprocess.run(['rtk', 'proxy', 'taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
            code, timeout = process.wait(timeout=15), True
    raw = log.read_text(encoding='utf-8', errors='replace')
    markers = [line for line in raw.splitlines() if line.startswith('HERO_PALETTE_BLENDER_REVIEW_OK')]
    errors = [line for line in raw.splitlines() if 'Traceback (most recent call last)' in line or line.startswith(('Error:', 'ERROR:'))]
    report_path = output / 'BLENDER_REVIEW.json'
    report = json.loads(report_path.read_text(encoding='utf-8')) if report_path.exists() else {}
    valid = code == 0 and not timeout and not errors and len(markers) == 1 and len(report.get('images', [])) == 3 and before == hashlib.sha256(source.read_bytes()).hexdigest()
    receipt = {'valid': valid, 'exitCode': code, 'timedOut': timeout, 'elapsedSeconds': time.monotonic() - started,
               'command': command, 'errors': errors, 'completionMarkers': markers,
               'reportSHA256': hashlib.sha256(report_path.read_bytes()).hexdigest() if report_path.exists() else None}
    proof.write_text(json.dumps(receipt, indent=2) + '\n', encoding='utf-8')
    print(json.dumps(receipt))
    return 0 if valid else 1


if __name__ == '__main__':
    raise SystemExit(main())
