"""Launch the R11 Blender build and retain its true exit and output."""
import hashlib
import json
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SCRIPT=ROOT/'tools/blender/build_hero_fuchuan_r11.py'
BLEND=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
EVIDENCE=ROOT/'docs/research/evidence/hero-fuchuan/r9-cinnabar-20261027'
parser=argparse.ArgumentParser();parser.add_argument('--suffix',default='');args=parser.parse_args()
if args.suffix and not re.fullmatch(r'-[a-z0-9-]+',args.suffix):raise SystemExit('invalid evidence suffix')
LOG=EVIDENCE/('r11-blender-build'+args.suffix+'.log')
RECEIPT=EVIDENCE/('r11-blender-build'+args.suffix+'.json')
if LOG.exists() or RECEIPT.exists():raise SystemExit('fresh R11 build evidence required')
inputs=[SCRIPT,BLEND,ROOT/'tools/research/verify_hero_r11_delta.py']
digest=lambda path:hashlib.sha256(path.read_bytes()).hexdigest()
before={str(path.relative_to(ROOT)):digest(path) for path in inputs}
result=subprocess.run([str(BLENDER),'--background',str(BLEND),'--python-exit-code','2','--python',str(SCRIPT)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf8',errors='replace')
EVIDENCE.mkdir(parents=True,exist_ok=True)
with LOG.open('x',encoding='utf8') as stream:stream.write(result.stdout)
after={str(path.relative_to(ROOT)):digest(path) for path in inputs}
accepted=result.returncode==0 and result.stdout.count('HERO_R11_BUILD_COMPLETE ')==1 and before==after
with RECEIPT.open('x',encoding='utf8') as stream:
    json.dump({'exitCode':result.returncode,'accepted':accepted,'before':before,'after':after,'logSha256':digest(LOG),'scope':'CPU Blender authoring and GLB build, no GPU or gameplay claim'},stream,indent=2);stream.write('\n')
print(result.stdout)
print('HERO_R11_PROCESS accepted='+str(accepted))
sys.exit(0 if accepted else 1)
