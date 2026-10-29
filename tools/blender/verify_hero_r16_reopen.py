"""Reopen source and R16; audit all protected objects and old/new rail regions."""
import argparse,collections,hashlib,importlib.util,json,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
DEST=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r16-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def helper():
    spec=importlib.util.spec_from_file_location('r16_reopen_helpers',ROOT/'tools/blender/verify_hero_r15b_reopen.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def facekeys(mesh):
    result=collections.Counter()
    for p in mesh.polygons:
        coords=[tuple(float(q).hex() for q in mesh.vertices[i].co) for i in p.vertices]
        variations=[tuple(coords[i:]+coords[:i]) for i in range(len(coords))]
        rev=list(reversed(coords));variations += [tuple(rev[i:]+rev[:i]) for i in range(len(rev))]
        result[min(variations)]+=1
    return result
def inspect():
    import bpy
    h=helper();before={str(p):sha(p) for p in (SRC,DEST)}
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('source required')
    old={o.name:h.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    oldmesh=bpy.data.objects['bulwark_rails'].data;original=facekeys(oldmesh);oldcanvas=h.canvas()
    oldinfo={'vertices':len(oldmesh.vertices),'faces':len(oldmesh.polygons),'uniqueFaceGeometries':len(original)}
    bpy.ops.wm.open_mainfile(filepath=str(DEST))
    new={o.name:h.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    rail=bpy.data.objects['bulwark_rails'];newmesh=rail.data;replacement=facekeys(newmesh);newcanvas=h.canvas()
    # Coordinates are Blender (x,-z,y); in stern cross-section test only upper rail.
    local=[(float(v.co.x),float(v.co.z),float(-v.co.y)) for v in newmesh.vertices]
    slot=[p for p in local if abs(p[2]+15.6)<.07 and p[1]>4.8]
    gap=min(abs(p[0]) for p in slot) if slot else 0.
    intrusive=[p for p in slot if abs(p[0])<.299]
    degenerate=sum(p.area<=1e-10 for p in newmesh.polygons)
    errors=[]
    if old!=new:errors.append('protected objects changed or added')
    if oldcanvas!=newcanvas:errors.append('canvas differs')
    if rail.parent is None or rail.parent.name!='HeroFuchuan':errors.append('rail parent differs')
    if intrusive or gap<.299:errors.append('stern slot intrusive geometry or incomplete')
    if degenerate:errors.append('degenerate new polygons')
    if original==replacement:errors.append('original rail not replaced')
    if before!={str(p):sha(p) for p in (SRC,DEST)}:errors.append('source modified')
    overlap=original&replacement
    data={'pass':not errors,'errors':errors,'baselineSha256':before[str(SRC)],'candidateSha256':before[str(DEST)],
        'protectedObjectsExact':old==new,'protectedObjectCount':len(old),'canvasExact':oldcanvas==newcanvas,'oldRail':oldinfo,
        'newRail':{'vertices':len(newmesh.vertices),'faces':len(newmesh.polygons),'uniqueFaceGeometries':len(replacement)},
        'identicalOldFaceGeometriesInReplacement':sum(overlap.values()),'sternSlot':{'sampledVertices':len(slot),'minAbsoluteXMeters':gap,'intrusiveVertexCount':len(intrusive),'nominalNetWidthMeters':2*gap},
        'degeneratePolygons':degenerate,'scope':'Static saved mesh/object/shape/canvas comparison; sampled slot vertices do not prove swept volume or collision-free intersections.'}
    with (DIR/'reopen-audit-01.json').open('x',encoding='utf8') as f:json.dump(data,f,indent=2)
    print('HERO_R16_REOPEN_AUDIT failures=',len(errors),'slot=',gap,'sharedFaces=',sum(overlap.values()),'errors=',errors,flush=True)
    return 0 if not errors else 1
def launch():
    report=DIR/'reopen-audit-01.json';log=DIR/'reopen-audit-01.log';process=DIR/'reopen-audit-01-process.json'
    if any(p.exists() for p in (report,log,process)):raise FileExistsError('fresh audit required')
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log.write_bytes(r.stdout)
    d=json.loads(report.read_text(encoding='utf8')) if report.exists() else {};ok=r.returncode==0 and d.get('pass') is True and r.stdout.count(b'HERO_R16_REOPEN_AUDIT')==1
    with process.open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'toolSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2000:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:return inspect()
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
