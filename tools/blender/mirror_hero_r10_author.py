"""Preserve or restore exact Blender author intermediates without overwrites.

The raw files are NOT shippable lower-LOD models: non-sail geometry comes from
the R7c LOD0 author Blend. They exist solely to replay the independent verifier.
The assets/production directory is excluded from Godot import by .gdignore.
"""
import argparse
import hashlib
import json
import shutil
from datetime import datetime,timezone
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
EVIDENCE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r10a-author-02'
TEMP=ROOT/'Temp/hero-fuchuan-r10a/r10a-author-02'
ARCHIVE=ROOT/'assets/production/hero-fuchuan-blender/r10a-author-02-intermediates'


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--restore-temp',action='store_true');args=parser.parse_args()
    records=[]
    for lod in range(3):
        receipt=json.loads((EVIDENCE/f'blender-lod{lod}.json').read_text(encoding='utf-8'))
        original=TEMP/f'fuchuan-lod{lod}.glb';archive=ARCHIVE/original.name
        source,target=(archive,original) if args.restore_temp else (original,archive)
        if not source.is_file() or digest(source)!=receipt['candidateRawSha256']:
            raise ValueError('original author receipt hash differs: '+str(source))
        if target.exists():raise FileExistsError('fresh destination required: '+str(target))
        records.append((lod,source,target,receipt['candidateRawSha256']))
    for lod,source,target,expected in records:
        target.parent.mkdir(parents=True,exist_ok=True)
        with source.open('rb') as src,target.open('xb') as dst:shutil.copyfileobj(src,dst,1024*1024)
        if digest(source)!=expected or digest(target)!=expected:raise ValueError('source/destination changed during copy')
    if not args.restore_temp:
        report={'createdUtc':datetime.now(timezone.utc).isoformat(),'scope':'Exact mirror of Blender-generated intermediate GLBs; not shippable',
                'files':[{'lod':lod,'original':str(source.relative_to(ROOT)),'archive':str(target.relative_to(ROOT)),
                          'sha256':expected} for lod,source,target,expected in records]}
        with (EVIDENCE/'r10a-author-mirror-01.json').open('x',encoding='utf-8') as stream:json.dump(report,stream,indent=2)
    print('HERO_R10A_AUTHOR_'+('RESTORED' if args.restore_temp else 'MIRRORED')+' files=3',flush=True)


if __name__=='__main__':main()
