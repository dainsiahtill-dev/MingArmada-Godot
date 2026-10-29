"""Record independent Blender reopen and adversarial GLB checks."""
import hashlib
import json
import subprocess
import sys
from datetime import datetime,timezone
from pathlib import Path
import build_hero_fuchuan_r13 as b

ROOT=Path(__file__).resolve().parents[2]
E=b.EVIDENCE
BLEND_CHECK=ROOT/'tools/blender/verify_hero_r13_blend.py'
RESULT=E/'r13-blender-independent.json'

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def run(label,cmd,marker):
    log=E/(label+'.log'); receipt=E/(label+'.process.json')
    if log.exists() or receipt.exists():raise RuntimeError('fresh evidence required')
    start=datetime.now(timezone.utc).isoformat()
    proc=subprocess.run(cmd,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    with log.open('xb') as stream:stream.write(proc.stdout)
    count=proc.stdout.replace(b'\r\n',b'\n').count(marker)
    accepted=proc.returncode==0 and count==1
    data={'command':cmd,'startedUtc':start,'finishedUtc':datetime.now(timezone.utc).isoformat(),
          'exitCode':proc.returncode,'markerCount':count,'accepted':accepted,'logSha256':sha(log)}
    with receipt.open('x',encoding='utf8') as stream:json.dump(data,stream,indent=2)
    print(proc.stdout.decode('utf8',errors='replace'),flush=True)
    if not accepted:raise RuntimeError(label+' failed; evidence retained')

def main():
    if '--adversarial-only' in sys.argv:
        run('r13-adversarial-retry',[sys.executable,'-m','unittest','tests.test_hero_r13_texture_delta','-v'],b'\nOK\n')
        return
    if RESULT.exists():raise RuntimeError('fresh Blender report required')
    cmd=[str(b.BLENDER),'--background','--python-exit-code','1','--python',str(BLEND_CHECK),
         '--',str(b.SOURCE),str(b.DEST),str(b.PNG),str(RESULT)]
    run('r13-blender-independent',cmd,b'HERO_R9_BLEND_VERIFY ')
    run('r13-adversarial', [sys.executable,'-m','unittest','tests.test_hero_r13_texture_delta','-v'],b'\nOK\n')
    print('HERO_R13_INDEPENDENT_CHECKS_COMPLETE',flush=True)

if __name__=='__main__':main()
