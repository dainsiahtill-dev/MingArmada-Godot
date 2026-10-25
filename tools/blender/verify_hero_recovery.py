"""Rerun prior full-suite failures with the existing strict test runner."""
from pathlib import Path
import subprocess, json, datetime

root = Path(__file__).resolve().parents[2]
out = root / 'Temp/hero-fuchuan/recovery-final'
out.mkdir(parents=True, exist_ok=True)
previous = json.loads((root / 'Temp/hero-fuchuan/full-suite.json').read_text(encoding='utf-8'))
filters = [Path(run['test']).stem for run in previous['runs'] if not run['passed']]
filters += ['test_hero_fuchuan', 'test_reference_ship_game_contract', 'test_ship_book', 'test_ordinary_natural']
report = {'startedAtUtc': datetime.datetime.now(datetime.timezone.utc).isoformat(), 'scope': 'Prior full-suite failures plus hero and ordinary-entry integration; not a new frozen full-suite run.', 'receipts': []}
for name in filters:
    receipt = out / (name + '.json')
    command = ['rtk', 'proxy', 'node', 'tools/verify-godot.mjs', '--godot', 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe', '--filter', name, '--output', str(receipt)]
    result = subprocess.run(command, cwd=root, capture_output=True, text=True, encoding='utf-8', errors='replace')
    (out / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
    data = json.loads(receipt.read_text(encoding='utf-8')) if receipt.exists() else {}
    report['receipts'].append({'filter': name, 'exitCode': result.returncode, 'summary': data.get('summary', {}), 'file': str(receipt.relative_to(root))})
    (out / 'summary.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(name, result.returncode, data.get('summary', {}), flush=True)
report['finishedAtUtc'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
report['passedAll'] = all(item['summary'].get('passedAll', False) for item in report['receipts'])
(out / 'summary.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
raise SystemExit(0 if report['passedAll'] else 1)
