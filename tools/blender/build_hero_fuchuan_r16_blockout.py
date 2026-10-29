"""R16 preregistered independent R9b upper-works replacement, not production."""
import argparse,hashlib,importlib.util,json,math,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
DEST=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r16-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R16-UPPER-WORKS-BRIEF.md'
V3=ROOT/'tools/blender/build_hero_fuchuan_v3.py'
BASE=ROOT/'tools/blender/build_hero_fuchuan.py'
HELP=ROOT/'tools/blender/build_hero_fuchuan_r15b_blockout.py'
AUDIT=ROOT/'tools/blender/verify_hero_r15b_reopen.py'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SRC_HASH='2961f7f28d31cfc71a16638fbd634b4245912adb1fcf79bc55bfc5d00722d2e8'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
def guards():
    if sha(SRC)!=SRC_HASH:raise ValueError('source hash changed')
    return {p.relative_to(ROOT).as_posix():sha(p) for p in (SRC,BRIEF,V3,BASE,HELP,AUDIT,Path(__file__).resolve())}
def build():
    import bpy,bmesh
    before=guards()
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('source not open')
    if '--vintage' not in sys.argv:sys.argv.append('--vintage')
    B=module('r16_base',BASE);B.LOD=0;B.OBJECTS=[];B.MATS['teak']=bpy.data.materials['teak']
    h=module('r16_original_functions',HELP);audit=module('r16_original_audit',AUDIT);g=h.source_geometry()
    root=bpy.data.objects['HeroFuchuan'];old=bpy.data.objects['bulwark_rails']
    if old.type!='MESH' or old.parent!=root or len(old.data.vertices)!=4008 or len(old.data.polygons)!=3000:raise ValueError('unexpected original rail')
    baseline={o.name:audit.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    if sum(n.startswith('socket_smoke_') for n in baseline)!=8:raise ValueError('eight sockets required')
    if any(n not in baseline for n in ('hull','deck','sterncastle','stern_transom','rudder_pivot','sail_0','sail_1','sail_2')):raise ValueError('contract missing')
    original=audit.object_snapshot(old);original.update({'vertices':len(old.data.vertices),'faces':len(old.data.polygons),'components':168})
    canvas=audit.canvas();bpy.data.objects.remove(old,do_unlink=True)
    parts=[]
    def e(z):return math.sin(math.pi*(z-9.4)/6.2)**2 if 9.4<z<15.6 else 0.
    def mainp(side,z,h):return (side*(g['smooth_table'](z)-.06),g['sheer'](z)+h+.75*e(z),z)
    def quarterp(side,z,h):return (side*(g['quarter_width'](z)-.04),g['quarter_y'](z)+h,z)
    for side,label in ((-1,'starboard'),(1,'port')):
        for j in range(33):
            z=-15.7+31.4*j/32;x=side*(g['smooth_table'](z)-.06);y=g['sheer'](z)
            parts.append(B.tube('Main stanchion '+label,(x,y+.86,z),mainp(side,z,1.34),.055,'teak',root,8))
        for level,rad in ((1.10,.035),(1.34,.055)):
            parts.append(B.curve('Main sheer '+label,[mainp(side,-15.7+31.4*j/128,level) for j in range(129)],rad,'teak',root))
        # The contact strip is flush with the original upper wall; the original
        # round wale can still intersect it and needs actual geometry review.
        za,zb=9.4,15.6;steps=64;verts=[];faces=[]
        def ring(z):
            x=g['smooth_table'](z);y=g['sheer'](z)+.94;top=y+.6*e(z)
            return [(side*x,y,z),(side*(x-.12),y,z),(side*(x-.12),top,z),(side*x,top,z)]
        for z in (za,):verts.extend(ring(z)[:2])
        for j in range(1,steps):verts.extend(ring(za+(zb-za)*j/steps))
        end=len(verts);verts.extend(ring(zb)[:2])
        faces.extend([(0,2,5),(1,4,3),(0,1,3,2),(0,5,4,1)])
        for j in range(steps-2):
            a=2+4*j;b=a+4
            faces.extend((a+k,b+k,b+(k+1)%4,a+(k+1)%4) for k in range(4))
        last=2+4*(steps-2)
        faces.extend([(end,last+3,last),(end+1,last+1,last+2),(end,last,last+1,end+1),(end,last+3,last+2,end+1)])
        if side<0:faces=[tuple(reversed(f)) for f in faces]
        wall=B.mesh('Fore upper strake '+label,verts,faces,'teak',root)
        if any(p.area<1e-10 for p in wall.data.polygons):raise ValueError('degenerate fore strake')
        bm=bmesh.new();bm.from_mesh(wall.data);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(wall.data);bm.free();wall.data.update();parts.append(wall)
        for j in range(10):
            z=-15.6+8.7*j/9;low=quarterp(side,z,0);top=quarterp(side,z,.90)
            parts.append(B.tube('Quarterdeck stanchion '+label,low,top,.055,'teak',root,8))
        for level,rad in ((.35,.035),(.90,.055)):
            parts.append(B.curve('Quarterdeck rail '+label,[quarterp(side,-15.6+8.7*j/64,level) for j in range(65)],rad,'teak',root))
        z=-15.6;y=g['quarter_y'](z);width=g['quarter_width'](z)-.04
        parts.append(B.tube('Stern inner post '+label,(side*.36,y,z),(side*.36,y+.90,z),.06,'teak',root,8))
        for level,rad in ((.35,.035),(.90,.055)):
            parts.append(B.curve('Stern open guard '+label,[(side*(.36+(width-.36)*j/32),y+level,z) for j in range(33)],rad,'teak',root))
    new=B.join(parts,'bulwark_rails',root)
    if new.name!='bulwark_rails' or new.parent!=root:raise ValueError('replacement did not take original name')
    after={o.name:audit.object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    if baseline!=after or canvas!=audit.canvas():raise ValueError('protected object or canvas changed')
    if before!=guards():raise ValueError('input changed during build')
    return {'baselineSources':before,'oldRail':original,'newRail':audit.object_snapshot(new),'oldGeometryRemoved':'entire object removed before creating replacement',
        'newRailCounts':{'vertices':len(new.data.vertices),'faces':len(new.data.polygons)},'existingNonRailObjectsExact':True,'existingObjectCount':len(baseline),
        'canvas':canvas,'nominalSternGapMeters':.60,'bowWallZ':[9.4,15.6],'bowPanelThicknessMeters':.12,
        'scope':'Static independent blockout; contact, visual acceptance, shadows, Godot, GPU, collision and motion not proven.'}
def author():
    import bpy
    if DEST.exists() or (DIR/'author.json').exists():raise FileExistsError('fresh output required')
    data=build()
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(DEST),compress=True):raise ValueError('save failed')
    if data['baselineSources']!=guards():raise ValueError('source changed during save')
    data.update({'candidateBlend':DEST.relative_to(ROOT).as_posix(),'candidateBlendSha256':sha(DEST),'blenderVersion':bpy.app.version_string})
    with (DIR/'author.json').open('x',encoding='utf8') as f:json.dump(data,f,indent=2)
    print('HERO_R16_AUTHOR_OK',flush=True)
def launch():
    if DIR.exists() or DEST.exists():raise FileExistsError('fresh candidate required')
    sources=guards();DIR.mkdir(parents=True);(DIR/'preregistration.md').write_bytes(BRIEF.read_bytes())
    if sha(DIR/'preregistration.md')!=sources[BRIEF.relative_to(ROOT).as_posix()]:raise ValueError('preregistration changed')
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--author']
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log=DIR/'author.log';log.write_bytes(r.stdout)
    ok=r.returncode==0 and r.stdout.count(b'HERO_R16_AUTHOR_OK')==1 and (DIR/'author.json').exists()
    with (DIR/'author-process.json').open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'sourceHashes':sources,'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-3000:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--author',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.author:author();return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
