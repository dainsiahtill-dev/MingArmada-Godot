"""R15b-only Blender blockout: R9b sails, locally joined bow and stern work."""
import argparse,ast,hashlib,importlib.util,json,math,struct,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
V3=ROOT/'tools/blender/build_hero_fuchuan_v3.py';BASE=ROOT/'tools/blender/build_hero_fuchuan.py'
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R15B-HULL-INTEGRATION-BRIEF.md'
IMAGE=ROOT/'assets/textures/hero_fuchuan_r9/sunfaded-cinnabar-hemp-sail.png'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SRC_HASH='2961f7f28d31cfc71a16638fbd634b4245912adb1fcf79bc55bfc5d00722d2e8'
IMAGE_HASH='f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def guards():
    if sha(SRC)!=SRC_HASH or sha(IMAGE)!=IMAGE_HASH:raise ValueError('R9b source or image differs')
    paths=[SRC,V3,BASE,BRIEF,IMAGE,Path(__file__).resolve()]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);o=importlib.util.module_from_spec(spec);spec.loader.exec_module(o);return o
def source_geometry():
    names=['smooth_table','sheer','quarter_width','quarter_y','outer_x']
    tree=ast.parse(V3.read_text(encoding='utf8'));nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names]
    if [n.name for n in nodes]!=names:raise ValueError('original geometry helpers changed')
    env={'math':math};exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),str(V3),'exec'),env);return env
def mesh_digest(obj):
    if obj.type!='MESH':return None
    d=obj.data;h=hashlib.sha256()
    for v in d.vertices:h.update(struct.pack('<fff',*v.co))
    for p in d.polygons:
        h.update(struct.pack('<II',p.material_index,len(p.vertices)))
        for i in p.vertices:h.update(struct.pack('<I',i))
    for layer in d.uv_layers:
        h.update(layer.name.encode())
        for uv in layer.data:h.update(struct.pack('<ff',*uv.uv))
    for m in d.materials:h.update((m.name if m else '').encode()+b'\0')
    if d.shape_keys:
        for key in d.shape_keys.key_blocks:
            h.update(key.name.encode()+b'\0')
            for v in key.data:h.update(struct.pack('<fff',*v.co))
    return h.hexdigest()
def snapshot(obj):
    return {'type':obj.type,'parent':obj.parent.name if obj.parent else None,'matrix':[[round(v,9) for v in row] for row in obj.matrix_local],
            'hidden':[obj.hide_render,obj.hide_viewport],'meshSha256':mesh_digest(obj)}
def outside_rail_hash(mesh):
    """Canonical face geometry/UV/material outside the only allowed bow region."""
    rows=[]
    for poly in mesh.polygons:
        coords=[mesh.vertices[i].co for i in poly.vertices]
        if any(10.3<=-v.y<=15.7 for v in coords):continue
        loops=[]
        for li in poly.loop_indices:
            p=mesh.vertices[mesh.loops[li].vertex_index].co
            uv=mesh.uv_layers.active.data[li].uv if mesh.uv_layers.active else (0.,0.)
            loops.append(tuple(float(x).hex() for x in [*p,*uv]))
        rows.append((poly.material_index,tuple(loops)))
    return hashlib.sha256(repr(sorted(rows)).encode()).hexdigest(),len(rows)
def ease(x):
    x=max(0.,min(1.,x));return x*x*(3.-2.*x)
def build():
    import bpy,bmesh
    before=guards()
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('R9b source required')
    if '--vintage' not in sys.argv:sys.argv.append('--vintage')
    B=module('hero_r15b_base',BASE);B.LOD=0;B.OBJECTS=[]
    teak=bpy.data.materials.get('teak')
    if teak is None:raise ValueError('teak material missing')
    B.MATS['teak']=teak;root=bpy.data.objects.get('HeroFuchuan');rail=bpy.data.objects.get('bulwark_rails')
    if root is None or rail is None or rail.type!='MESH' or rail.parent!=root:raise ValueError('missing root or original rail')
    baseline={o.name:snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    if len([x for x in baseline if x.startswith('socket_smoke_')])!=8:raise ValueError('original eight sockets required')
    if any(x not in baseline for x in ['hull','deck','shadow_hull','shadow_deck','rudder_pivot','mast_0','mast_1','mast_2','sail_0','sail_1','sail_2']):raise ValueError('baseline contract missing')
    tex=bpy.data.materials.get('canvas');images=[n.image for n in tex.node_tree.nodes if n.type=='TEX_IMAGE'] if tex else []
    if len(images)!=1 or images[0] is None or images[0].packed_file is None or hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest()!=IMAGE_HASH:raise ValueError('R9b canvas packed texture mismatch')
    g=source_geometry();old_rail_digest=mesh_digest(rail);outside_before,outside_count=outside_rail_hash(rail.data)
    # Remove only original rail faces whose bounds overlap the declared bow
    # panel envelope. Other rail faces (including aft handrail) are retained.
    def intersects_bow(face):
        zvals=[-v.co.y for v in face.verts];mid=sum(zvals)/len(zvals)
        if not 10.3<=mid<=15.7 or any(z<10.3 or z>15.7 for z in zvals):return False
        t=(mid-10.3)/5.4;e=math.sin(math.pi*t)**2
        if e<.015:return False
        lower=g['sheer'](mid)+1.34-.40*e;upper=g['sheer'](mid)+1.34+.55*e
        ys=[v.co.z for v in face.verts];xs=[abs(v.co.x) for v in face.verts]
        return max(ys)>=lower-.025 and min(ys)<=upper+.025 and max(xs)>=g['smooth_table'](mid)-.16 and min(xs)<=g['smooth_table'](mid)+.16
    bm=bmesh.new();bm.from_mesh(rail.data);removed=[f for f in bm.faces if intersects_bow(f)]
    if not removed:raise ValueError('expected original bow rails to overlap candidate')
    removed_count=len(removed);bmesh.ops.delete(bm,geom=removed,context='FACES');bm.to_mesh(rail.data);bm.free();rail.data.update()
    outside_after,_=outside_rail_hash(rail.data)
    if outside_after!=outside_before:raise ValueError('original rail geometry outside declared bow range changed')
    created=[];post_results=[]
    def fan_piece(name,side,a,b,ring,steps=32):
        verts=[];faces=[]
        verts.append(ring(a,True))
        for i in range(1,steps):verts.extend(ring(a+(b-a)*i/steps,False))
        end=len(verts);verts.append(ring(b,True))
        for j in range(4):faces.append((0,1+j,1+(j+1)%4))
        for i in range(steps-2):
            lo=1+4*i;hi=lo+4
            for j in range(4):faces.append((lo+j,hi+j,hi+(j+1)%4,lo+(j+1)%4))
        last=1+4*(steps-2)
        for j in range(4):faces.append((end,last+(j+1)%4,last+j))
        if side<0:faces=[tuple(reversed(f)) for f in faces]
        obj=B.mesh(name,verts,faces,'teak',root)
        if any(p.area<=1e-10 for p in obj.data.polygons):raise ValueError('candidate has degenerate face '+name)
        return obj
    for side,label in [(-1,'starboard'),(1,'port')]:
        def bow_ring(z,end,side=side):
            t=(z-10.3)/5.4;e=math.sin(math.pi*t)**2;mid=g['sheer'](z)+1.34;x=g['smooth_table'](z)-.06
            if end:return (side*x,mid,z)
            lo=mid-.40*e;hi=mid+.55*e
            return [(side*x,lo,z),(side*(x+.09),lo,z),(side*(x+.09),hi,z),(side*x,hi,z)]
        fore=fan_piece('r15b_foreworks_'+label,side,10.3,15.7,bow_ring);fore['deck_obstacle']=True;created.append(fore)
        def wale_ring(z,end,side=side):
            t=min((z+14.5)/1.75,(14.5-z)/1.75);w=ease(t);middle=min(1.70,g['sheer'](z)-.88);x=g['outer_x'](middle,z)
            if end:return (side*x,middle,z)
            lo=middle-.09*w;hi=middle+.09*w
            return [(side*(g['outer_x'](lo,z)-.005),lo,z),(side*(g['outer_x'](lo,z)+.05*w),lo,z),
                    (side*(g['outer_x'](hi,z)+.05*w),hi,z),(side*(g['outer_x'](hi,z)-.005),hi,z)]
        wale=fan_piece('r15b_wale_'+label,side,-14.5,14.5,wale_ring,64);created.append(wale)
        def position(z):
            strength=min(ease((z+15.6)/1.0),ease((-9.8-z)/1.0))
            return (side*(g['quarter_width'](z)-.04),g['quarter_y'](z)+.76+.30*strength,z)
        pieces=[];postchecks=[]
        for z in [-14.6333333333,-13.6666666667,-12.7,-11.7333333333,-10.7666666667]:
            x=side*(g['quarter_width'](z)-.04);y=g['quarter_y'](z)+.76
            # Source mesh's actual post cap ring should surround the intended join.
            nearest=min(math.dist((v.co.x,v.co.z,-v.co.y),(x,y,z)) for v in rail.data.vertices)
            if nearest>.08:raise ValueError('existing stern post not found '+str(z))
            postchecks.append({'z':z,'nearestOriginalRailVertexMeters':nearest})
            pieces.append(B.tube('r15b_post',(x,y,z),position(z),.055,'teak',root,8))
        coords=[position(-15.6+5.8*i/24) for i in range(25)]
        for a,b in zip(coords,coords[1:]):pieces.append(B.tube('r15b_upper_rail',a,b,.04,'teak',root,8))
        aft=B.join(pieces,'r15b_sternrail_'+label,root);aft['deck_obstacle']=True;created.append(aft)
        post_results.append({'side':label,'sourcePostJoins':postchecks})
    after={o.name:snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails' and not o.name.startswith('r15b_')}
    if baseline!=after:raise ValueError('existing non-rail object changed')
    if before!=guards():raise ValueError('inputs changed while building')
    return {'baselineSources':before,'existingNonRailObjectsExact':True,'existingObjectCount':len(baseline),'railChange':{'object':'bulwark_rails','allowedZ':[10.3,15.7],'deletedFaceCount':removed_count,'oldMeshSha256':old_rail_digest,'newMeshSha256':mesh_digest(rail),'outsideBowOriginalFaceHash':outside_before,'outsideBowCandidateFaceHash':outside_after,'outsideFaces':outside_count,'scope':'Only faces selected by envelope-overlap criterion; overlap/visual continuity still require checking'},'sternPostJoins':post_results,'canvasPackedSha256':IMAGE_HASH,'addedNodes':[{'name':o.name,'vertices':len(o.data.vertices),'faces':len(o.data.polygons),'deck_obstacle':bool(o.get('deck_obstacle',False))} for o in created],
            'scope':'R9b Blender art blockout with local bow rail crop, not GPU, runtime, shadow, collision, LOD or gameplay acceptance.'}
def author(destination,receipt):
    import bpy
    if destination.exists() or receipt.exists():raise FileExistsError('fresh outputs required')
    info=build();destination.parent.mkdir(parents=True,exist_ok=True);receipt.parent.mkdir(parents=True,exist_ok=True)
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(destination.resolve()),compress=True):raise RuntimeError('save failed')
    if info['baselineSources']!=guards():raise ValueError('input changed during save')
    info.update({'candidateBlend':destination.relative_to(ROOT).as_posix(),'candidateBlendSha256':sha(destination),'blenderVersion':bpy.app.version_string,'finishedUTC':datetime.now(timezone.utc).isoformat()})
    with receipt.open('x',encoding='utf8') as f:json.dump(info,f,indent=2)
    print('HERO_R15B_AUTHOR_OK',flush=True)
def launch():
    evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01';dest=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15b-blockout-01.blend'
    if evidence.exists() or dest.exists():raise FileExistsError('fresh output required')
    guards();evidence.mkdir(parents=True)
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--author','--destination',str(dest),'--receipt',str(evidence/'author.json')]
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log=evidence/'blender-author.log';log.write_bytes(r.stdout)
    marker=b'HERO_R15B_AUTHOR_OK';ok=r.returncode==0 and r.stdout.count(marker)==1 and (evidence/'author.json').is_file()
    with (evidence/'blender-author-process.json').open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'markerCount':r.stdout.count(marker),'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'scriptSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2500:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--author',action='store_true');p.add_argument('--destination',type=Path);p.add_argument('--receipt',type=Path)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.author and a.destination and a.receipt:author(a.destination,a.receipt);return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
