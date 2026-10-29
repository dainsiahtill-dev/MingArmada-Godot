"""Run candidate triangle extraction and record process evidence."""
import hashlib,json,subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    log=DIR/'join-extract-01.log';receipt=DIR/'join-extract-01-process.json';out=DIR/'join-triangles-01.json'
    if any(p.exists() for p in [log,receipt,out]):raise FileExistsError('fresh outputs required')
    source=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15b-blockout-01.blend';script=ROOT/'tools/blender/extract_hero_r15b_join_triangles.py'
    command=['rtk','proxy',str(BLENDER),'--background',str(source),'--python-exit-code','1','--python',str(script)]
    before=sha(source);p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log.write_bytes(p.stdout)
    ok=p.returncode==0 and p.stdout.count(b'HERO_R15B_JOIN_EXTRACTION_OK')==1 and out.is_file() and sha(source)==before
    with receipt.open('x',encoding='utf8') as f:json.dump({'success':ok,'exitCode':p.returncode,'command':command,'sourceSha256':before,'scriptSha256':sha(script),'outputSha256':sha(out) if out.exists() else None,'logSha256':sha(log)},f,indent=2)
    print(p.stdout.decode('utf8',errors='replace')[-1000:]);return 0 if ok else 1
if __name__=='__main__':raise SystemExit(main())
