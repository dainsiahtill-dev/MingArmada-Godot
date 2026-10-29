"""Preserve a fresh process receipt for strict R11b adversarial checks."""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

root=Path(__file__).resolve().parents[2]
evidence=root/'docs/research/evidence/hero-fuchuan/r9-cinnabar-20261027'
log=evidence/'r11b-negative-tests.log'
receipt=evidence/'r11b-negative-tests.json'
if log.exists() or receipt.exists():raise SystemExit('fresh evidence required')
paths=['tools/research/verify_hero_r11b_delta.py','tests/test_hero_r11b_delta.py',
       'assets/models/hero_fuchuan_v3_r9b/manifest.json','assets/models/hero_fuchuan_v3_r11b/manifest.json']
paths += [f'assets/models/hero_fuchuan_v3_{variant}/fuchuan-lod{lod}.glb' for variant in ('r9b','r11b') for lod in range(3)]
digest=lambda path:hashlib.sha256((root/path).read_bytes()).hexdigest()
before={path:digest(path) for path in paths}
result=subprocess.run([sys.executable,'-B',str(root/'tests/test_hero_r11b_delta.py')],cwd=root,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8',errors='replace')
with log.open('x',encoding='utf8') as stream:stream.write(result.stdout)
after={path:digest(path) for path in paths}
valid=result.returncode==0 and 'Ran 9 tests' in result.stdout and result.stdout.rstrip().endswith('OK') and before==after
with receipt.open('x',encoding='utf8') as stream:
    json.dump({'exitCode':result.returncode,'valid':valid,'before':before,'after':after,'logSha256':hashlib.sha256(log.read_bytes()).hexdigest(),'scope':'CPU negative tests; not GPU or gameplay acceptance'},stream,indent=2);stream.write('\n')
print(result.stdout)
print('HERO_R11B_NEGATIVE_PROCESS accepted='+str(valid))
raise SystemExit(0 if valid else 1)
