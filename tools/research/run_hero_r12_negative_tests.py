"""Record an independently replayable process receipt for R12 tamper tests."""
import hashlib,json,subprocess
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r12-author-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    log=DIR/'r12-negative-tests-01.log';receipt=DIR/'r12-negative-tests-01.json'
    if log.exists() or receipt.exists():raise FileExistsError('fresh evidence required')
    command=['rtk','proxy','python','-m','unittest','tests.test_hero_r12_pipeline','-v']
    start=datetime.now(timezone.utc).isoformat()
    result=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    with log.open('xb') as f:f.write(result.stdout)
    raw=result.stdout.decode('utf-8',errors='replace');passed=result.returncode==0 and 'Ran 5 tests' in raw and '\nOK' in raw
    report={'startedUtc':start,'finishedUtc':datetime.now(timezone.utc).isoformat(),'command':command,'exitCode':result.returncode,'pass':passed,'logSha256':sha(log),'testSha256':sha(ROOT/'tests/test_hero_r12_pipeline.py'),'packerSha256':sha(ROOT/'tools/blender/pack_hero_r12_sail.py'),'verifierSha256':sha(ROOT/'tools/research/verify_hero_r12_sail_delta.py')}
    with receipt.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print(raw);return 0 if passed else 1
if __name__=='__main__':raise SystemExit(main())
