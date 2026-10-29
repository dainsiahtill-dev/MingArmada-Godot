"""Independently reopen R9b and R15c and audit the registered rail field."""
import argparse, hashlib, importlib.util, json, math, subprocess, sys
from datetime import datetime, timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
CANDIDATE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15c-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
def smooth(v):
    v=max(0.,min(1.,v));return v*v*(3-2*v)
def expected(y,z):
    sheer=1.92+1.8*(max(0.,z)/16)**3.2+.7*(max(0.,-z)/16)**2.6
    quarter=4.38+.25*max(0.,min(1.,(-z-7)/8))**2
    b=.85*math.sin(math.pi*(z-10.3)/5.4)**2 if 10.3<z<15.7 else 0.
    a=.55*smooth(z+15.6)*smooth(-9.8-z)
    return b*smooth((y-sheer-.85)/.49)+a*smooth((y-quarter-.30)/.46)
def helper():
    spec=importlib.util.spec_from_file_location('audit_r15b',ROOT/'tools/blender/verify_hero_r15b_reopen.py')
    mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod);return mod
def rail_snapshot(o):
    m=o.data;m.calc_loop_triangles()
    return {'matrix':[[float(v) for v in r] for r in o.matrix_local], 'parent':o.parent.name if o.parent else None,
        'coords':[tuple(v.co) for v in m.vertices], 'edges':[tuple(e.vertices) for e in m.edges],
        'faces':[(p.material_index,tuple(p.vertices)) for p in m.polygons],
        'uv':[(l.name,[(float(v.uv.x),float(v.uv.y)) for v in l.data]) for l in m.uv_layers],
        'materials':[mat.name if mat else None for mat in m.materials],
        'triangles':[tuple(t.vertices) for t in m.loop_triangles]}
def inspect():
    import bpy
    from mathutils import Vector
    h=helper();before={str(p):sha(p) for p in (SOURCE,CANDIDATE)}
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('source not open')
    objects={o.name:h.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    oldrail=rail_snapshot(bpy.data.objects['bulwark_rails']);canvas=h.canvas()
    bpy.ops.wm.open_mainfile(filepath=str(CANDIDATE))
    newobjects={o.name:h.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    newrail=rail_snapshot(bpy.data.objects['bulwark_rails']);newcanvas=h.canvas();errors=[]
    if objects!=newobjects:errors.append('non-rail objects differ')
    if canvas!=newcanvas:errors.append('canvas or links differ')
    for k in ('matrix','parent','edges','faces','uv','materials','triangles'):
        if oldrail[k]!=newrail[k]:errors.append('rail '+k+' differs')
    if len(oldrail['coords'])!=len(newrail['coords']):errors.append('vertex count differs')
    maxerr=0.;moved=0;identity=0
    for old,new in zip(oldrail['coords'],newrail['coords']):
        x,nz,y=old;delta=expected(y,-nz);err=abs(new[2]-(y+delta));maxerr=max(err,maxerr)
        if old[0]!=new[0] or old[1]!=new[1]:errors.append('x/z changed');break
        if delta==0 and old!=new:identity+=1
        if old!=new:moved+=1
    if maxerr>1e-5 or identity:errors.append('field mismatch or identity violation')
    degenerate=flipped=0
    for tri in oldrail['triangles']:
        a,b,c=(Vector(oldrail['coords'][i]) for i in tri);d,e,f=(Vector(newrail['coords'][i]) for i in tri)
        old=(b-a).cross(c-a);new=(e-d).cross(f-d)
        if old.length>1e-10 and new.length<=1e-10:degenerate+=1
        if old.length>1e-10 and new.length>1e-10 and old.dot(new)<=0:flipped+=1
    if degenerate or flipped:errors.append('new degenerate or flipped triangle')
    if before!={str(p):sha(p) for p in (SOURCE,CANDIDATE)}:errors.append('input file changed')
    report={'pass':not errors,'errors':errors,'baselineSha256':before[str(SOURCE)],'candidateSha256':before[str(CANDIDATE)],
        'existingNonRailObjectsExact':objects==newobjects,'existingCount':len(objects),'canvasIdentical':canvas==newcanvas,'canvas':newcanvas,
        'railTopologyUvMaterialIdentical':all(oldrail[k]==newrail[k] for k in ('matrix','parent','edges','faces','uv','materials','triangles')),
        'movedVertices':moved,'identityChangedVertices':identity,'maximumFieldErrorMeters':maxerr,'newDegenerateTriangles':degenerate,'flippedTriangles':flipped,
        'scope':'Reopened static object/mesh/UV/shape keys/canvas audit and formula; no surface joining, Godot, GPU, animation, collision or gameplay acceptance.'}
    with (DIR/'reopen-audit-01.json').open('x',encoding='utf8') as f:json.dump(report,f,indent=2)
    print('HERO_R15C_REOPEN_AUDIT failures=',len(errors),'details=',errors,flush=True)
    return 0 if not errors else 1
def launch():
    report=DIR/'reopen-audit-01.json';log=DIR/'reopen-audit-01.log';process=DIR/'reopen-audit-01-process.json'
    if any(p.exists() for p in (report,log,process)):raise FileExistsError('fresh audit required')
    command=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log.write_bytes(r.stdout)
    d=json.loads(report.read_text(encoding='utf8')) if report.exists() else {};ok=r.returncode==0 and d.get('pass') is True and r.stdout.count(b'HERO_R15C_REOPEN_AUDIT')==1
    with process.open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'toolSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2000:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:return inspect()
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
