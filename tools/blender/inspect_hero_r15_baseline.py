"""Read-only Blender baseline measurement for R15 art blockout planning."""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15-baseline-measure-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def measure():
    import bpy
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('unexpected author source')
    before=sha(SRC);rows=[]
    for obj in bpy.context.scene.objects:
        n=obj.name
        if not (n in ['HeroFuchuan','hull','deck','sterncastle','stern_transom','deck_fittings','bulwark_rails','rudder_pivot','rudder_blade','shadow_deck','shadow_hull'] or n.startswith(('mast_','sail_','cargo_hold_','crew_','cannon_','socket_smoke_'))):continue
        mat=obj.matrix_world;points=[mat@v.co for v in obj.data.vertices] if obj.type=='MESH' else []
        if points:
            points=[(v.x,v.z,-v.y) for v in points]
            box={'min':[min(p[i] for p in points) for i in range(3)],'max':[max(p[i] for p in points) for i in range(3)],'vertexCount':len(points)}
        else:box=None
        o=mat.translation
        rows.append({'name':n,'type':obj.type,'parent':obj.parent.name if obj.parent else None,'origin':[o.x,o.z,-o.y],
                     'boundsGodotXYZ':box,'materials':[m.name if m else None for m in obj.data.materials] if obj.type=='MESH' else [],
                     'custom':{str(k):obj[k] for k in obj.keys() if isinstance(obj[k],(str,bool,int,float))}})
    report={'source':'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend','sha256':before,'sourceUnchanged':before==sha(SRC),'axes':'Godot x transverse,y vertical,z bow-positive; meters','objects':rows,'scope':'Source Blender mesh vertices before modifiers; only static bounding boxes, no collision or rendered acceptance.'}
    with (DIR/'BASELINE-MEASURE.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print('HERO_R15_BASELINE_MEASURE_OK objects='+str(len(rows)),flush=True)
def launch():
    if DIR.exists():raise FileExistsError('fresh measurement path required')
    DIR.mkdir(parents=True);before=sha(SRC)
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--measure']
    started=datetime.now(timezone.utc).isoformat();p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    log=DIR/'blender.log';log.write_bytes(p.stdout);marker=b'HERO_R15_BASELINE_MEASURE_OK';success=p.returncode==0 and p.stdout.count(marker)==1 and before==sha(SRC) and (DIR/'BASELINE-MEASURE.json').is_file()
    with (DIR/'process.json').open('x',encoding='utf-8') as f:json.dump({'success':success,'exitCode':p.returncode,'command':command,'startedUTC':started,'endedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'sourceSha256':before,'scriptSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(p.stdout.decode('utf8',errors='replace')[-2000:]);return 0 if success else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--measure',action='store_true');p.add_argument('--launch',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.measure:measure()
    elif a.launch:return launch()
    else:p.error('mode required')
    return 0
if __name__=='__main__':raise SystemExit(main())
