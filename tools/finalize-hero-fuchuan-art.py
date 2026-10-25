"""Freeze current art candidate evidence without committing or changing gameplay."""
from pathlib import Path
import ast, datetime, hashlib, json, re, shutil, subprocess

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/production/hero-fuchuan-2026-10-26-art'
REPORTS=[
    'art-v3-r5-model.json','shadow-geometry-matrix-r5.json','shadow-parity-r5.json',
    'sun-direction-green.json','weather-corrected-sun.json',
    'source-environment-corrected-sun.json','final-paused-laboratory-r5.json',
    'final-ordinary-r5.json',
]

def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def main():
    target=OUT/'final-state-manifest-r5.json'
    evidence=OUT/'verification-final-r5'
    if target.exists() or evidence.exists():raise RuntimeError('fresh final evidence required')
    rows=[]
    for name in REPORTS:
        path=ROOT/'Temp/hero-fuchuan'/name
        report=json.loads(path.read_text(encoding='utf-8'))
        assert report['summary']['passedAll'],name
        for run in report['runs']:
            assert run['passed'] and not run['timedOut'],name
            rows.append({'report':name,'test':run['test'],'passed':run['passed'],
                         'completion':[line for line in run['stdout'].splitlines()
                                       if re.search(r'assertions=|failures=',line)]})
    for source in ['tools/blender/build_hero_fuchuan.py','tools/blender/build_hero_fuchuan_v3.py']:
        ast.parse((ROOT/source).read_text(encoding='utf-8'))
    gpu=json.loads((OUT/'shadow-gpu-final-paused-ready/manifest.json').read_text(encoding='utf-8'))
    assert gpu['failures']==0
    performance=json.loads((OUT/'perf-r5-corrected-sun-a/live-observation.json').read_text(encoding='utf-8'))
    assert performance['valid'] and not performance['invalidReasons']
    evidence.mkdir()
    for name in REPORTS:shutil.copy2(ROOT/'Temp/hero-fuchuan'/name,evidence/name)
    paths=[
        'tools/blender/build_hero_fuchuan.py','tools/blender/build_hero_fuchuan_v3.py',
        'modules/scene_engine/assets/hero_ship_provider.gd',
        'game/presentation/world/target_rigid_shadow_caster.gd',
        'modules/environment_engine/weather_state.gd',
        'game/research/demos/hero_fuchuan_experiment.gd',
        'tools/verify-hero-shadow-gpu.gd','tools/measure-hero-rigid-shadow.gd',
        'tools/diagnose-hero-native-shadow.gd','tools/measure-architecture-live.gd',
        'tools/finalize-hero-fuchuan-art.py',
        'tests/test_hero_shadow_geometry.gd','tests/test_weather_sun_direction.gd',
        'tests/test_hero_fuchuan_art.gd','tests/test_target_rigid_shadow_edges.gd',
        'assets/production/hero-fuchuan-blender/hero-fuchuan-v3.blend',
        'assets/production/hero-fuchuan-blender/README.md',
        'assets/research/papers/hero-fuchuan.md','assets/research/papers/weather-shadow.md',
        'docs/superpowers/plans/2026-10-26-hero-fuchuan-art.md',
        'docs/superpowers/specs/2026-10-26-hero-fuchuan-art.md',
    ]
    paths += [p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/models/hero_fuchuan_v3').glob('*') if p.suffix in ['.glb','.json']]
    paths += [p.relative_to(ROOT).as_posix() for p in (ROOT/'assets/textures/hero_fuchuan_v2').glob('*') if p.suffix in ['.png','.json']]
    for pattern in ['verification-final-r5/*.json','*review.md','DELIVERY.md','native-play/*.png','native-play/observations.json','v3-r4/*.png','gpu-r4/manifest.json','shadow-gpu-final-paused-ready/*','perf-*/live-observation.json','cpu-proxy-pairs-*/measurement.json']:
        paths += [p.relative_to(ROOT).as_posix() for p in OUT.glob(pattern) if p.is_file()]
    files=[{'path':p,'bytes':(ROOT/p).stat().st_size,'sha256':digest(ROOT/p)} for p in sorted(set(paths))]
    head=subprocess.check_output(['rtk','git','rev-parse','HEAD'],cwd=ROOT,text=True).strip()
    result={'schemaVersion':1,'utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'checkpoint':head,'candidate':'hero-fuchuan-v3-r5-corrected-sun',
            'status':'model candidate available for art review; whole-game performance acceptance NOT passed',
            'gitScope':'Working files after checkpoint; this script does not commit or push.',
            'verification':rows,'gpuFailures':gpu['failures'],
            'formalPerformance':{'valid':performance['valid'],'metrics':performance['metrics'],
                                 'acceptedTime':[performance['nativeStart'],performance['nativeEnd']]},
            'limitations':['Not a full-suite rerun','Final manual firing image precedes sun-sign correction; geometry unchanged',
                           'Native E injection not certified','13.80 FPS remains below smooth-play acceptance',
                           'Sea/island art direction, export package and helm hand IK remain outstanding'],
            'files':files}
    target.write_text(json.dumps(result,ensure_ascii=False,indent=2),encoding='utf-8')
    print(f'HERO_ART_FINALIZED files={len(files)} test_files={len(rows)} gpu_failures=0 output={target}')

if __name__=='__main__':main()
