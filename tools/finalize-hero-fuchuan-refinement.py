"""Freeze r6 evidence; preserve earlier rounds and leave Git untouched."""
from pathlib import Path
import datetime, hashlib, json, shutil

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/production/hero-fuchuan-2026-10-26-art'
REPORTS=['r6-final-model.json','r6-final-shadow.json','r6-final-ship-book.json',
         'r6-final-laboratory.json','r6-final-ordinary.json']
def read(path):return json.loads(path.read_text(encoding='utf-8'))
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def main():
    target=OUT/'final-state-manifest-r6.json';evidence=OUT/'verification-final-r6'
    assert not target.exists() and not evidence.exists(),'fresh final evidence required'
    tests=[]
    for name in REPORTS:
        report=read(ROOT/'Temp/hero-fuchuan'/name);assert report['summary']['passedAll'],name
        tests.extend({'test':run['test'],'report':name,'passed':run['passed'],
                      'completion':[line for line in run['stdout'].splitlines() if 'assertions=' in line]}
                     for run in report['runs'])
    gpu=read(OUT/'gpu-r6-c/manifest.json')
    assert gpu['sourcesUnchanged'] and gpu['pauseUnchanged'] and gpu['resetInitialSnapshotEqual']
    assert len(gpu['continuousFrames'])==257
    for frame in gpu['continuousFrames']:
        path=ROOT/frame['path'].removeprefix('res://');assert sha(path)==frame['sha256']
    shadows=read(OUT/'shadow-gpu-r6-c/manifest.json');assert shadows['failures']==0
    audit=read(OUT/'r6-c-contract-audit.json')
    assert audit['all_frames_preserved'] and audit['all_undeclared_geometry_preserved']
    assert all(v['same_parent'] and v['same_local_frame'] for lod in audit['lods'] for v in lod['proxy_full_frame_pairs'].values())
    performance=read(OUT/'perf-r6-c/live-observation.json');assert performance['valid']
    observations=read(OUT/'native-play-r6/observations.json')
    assert len(observations)>=5,'native input evidence required'
    evidence.mkdir()
    for name in REPORTS:shutil.copy2(ROOT/'Temp/hero-fuchuan'/name,evidence/name)
    paths=[
        'tools/blender/build_hero_fuchuan.py','tools/blender/build_hero_fuchuan_v3.py',
        'tools/verify-hero-fuchuan-gpu.gd','tools/verify-hero-shadow-gpu.gd',
        'tools/diagnose-hero-deck-joints.gd','tools/research/audit_hero_fuchuan_glb.py',
        'tools/finalize-hero-fuchuan-refinement.py',
        'modules/scene_engine/assets/hero_ship_provider.gd',
        'game/research/demos/hero_fuchuan_experiment.gd',
        'tests/test_hero_fuchuan_art.gd','tests/test_hero_shadow_geometry.gd','tests/test_ship_book.gd',
        'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r6.blend',
        'assets/production/hero-fuchuan-blender/README.md',
        'assets/research/papers/hero-fuchuan.md',
        'docs/superpowers/plans/2026-10-26-hero-fuchuan-art.md',
    ]
    paths += [p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models/hero_fuchuan_v3_r6').glob('*') if p.suffix in ['.glb','.json']]
    patterns=['R6-DELIVERY.md','r6-*.md','r6-*.json','verification-final-r6/*.json',
              'v3-r6-c/*.png','gpu-r6-c/*.json','gpu-r6-c/*.png','shadow-gpu-r6-c/*',
              'perf-r6-c/*.json','perf-r6-c/*.png','native-play-r6/*','hero-rig-v3-r6-c.mp4',
              'deck-joints-r6-b/*']
    for pattern in patterns:paths += [p.relative_to(ROOT).as_posix() for p in OUT.glob(pattern) if p.is_file()]
    files=[{'path':p,'bytes':(ROOT/p).stat().st_size,'sha256':sha(ROOT/p)} for p in sorted(set(paths))]
    result={'schemaVersion':1,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'candidate':'hero-fuchuan-v3-r6-c','status':'Integrated model refinement; full-game goal/performance incomplete',
            'tests':tests,'gpu':{'controlledFrames':257,'rawFrameHashesVerified':True,'shadowFailures':0},
            'contractScope':'All original frames and undeclared geometry unchanged; deck joints deliberately narrower.',
            'performance':performance['metrics'],'files':files,
            'limitations':['Controlled video is not native gameplay recording','No full-suite rerun',
                           'Aft windows are closed dark panes','Blade projected area reduced about6.05%; simulation unchanged',
                           'Full game performance, sea/island atmosphere and broader gameplay remain unfinished']}
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'HERO_R6_FINALIZED files={len(files)} test_files={len(tests)} raw_frames=257 output={target}')
if __name__=='__main__':main()
