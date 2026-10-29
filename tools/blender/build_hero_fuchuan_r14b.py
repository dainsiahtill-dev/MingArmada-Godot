"""Add two R14B coamings to actual R7c Blend; raw exports aren't shippable LODs."""
import argparse,ast,hashlib,json,math,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
R7=ROOT/'assets/models/hero_fuchuan_v3_r7c'
V3=ROOT/'tools/blender/build_hero_fuchuan_v3.py'
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R14-DECK-HATCH-BRIEF.md'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
EXPECTED=['ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3','b87af112855cb6883faf97ec02a5eeb5fd61a5d504f204d3b3a573e73735d02d','db9f01b8968f66f2a1c27c689e9a9e0cdd7f03ea27d86a9b6f2bb911872e461a','16aa79cb89074879354d82402540f478e9ad5279085d2c53d7f92d579aa2291d']

def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()

def guarded():
    paths=[SOURCE]+[R7/f'fuchuan-lod{i}.glb' for i in range(3)]
    if [sha(p) for p in paths]!=EXPECTED:raise ValueError('R7c inputs differ from frozen baseline')
    paths += [V3,BRIEF,Path(__file__).resolve()]
    return {str(p.relative_to(ROOT)).replace('\\','/'):sha(p) for p in paths}

def deck_geometry():
    tree=ast.parse(V3.read_text(encoding='utf-8'))
    selected=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in ['smooth_table','sheer','deck_y']]
    if [n.name for n in selected]!=['smooth_table','sheer','deck_y']:raise ValueError('original deck functions changed')
    env={'math':math};exec(compile(ast.fix_missing_locations(ast.Module(body=selected,type_ignores=[])),str(V3),'exec'),env)
    return env['deck_y']

def author(lod,raw,blend,receipt):
    import bpy
    if raw.exists() or blend.exists() or receipt.exists():raise FileExistsError('fresh outputs required')
    before=guarded()
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('wrong Blender source')
    root=bpy.data.objects.get('HeroFuchuan');teak=bpy.data.materials.get('teak')
    if root is None or teak is None:raise ValueError('baseline root/material missing')
    snapshots={o.name:(o.type,o.parent.name if o.parent else None,tuple(round(v,9) for row in o.matrix_local for v in row)) for o in bpy.context.scene.objects}
    for center in [-3.2,5.8]:
        obj=bpy.data.objects.get('cargo_hold_%s'%center)
        if obj is None or obj.type!='MESH' or obj.parent!=root or not obj.get('deck_obstacle'):raise ValueError('baseline cargo node contract missing')
        xs=[v.co.x for v in obj.data.vertices];zs=[-v.co.y for v in obj.data.vertices];ys=[v.co.z for v in obj.data.vertices]
        if abs((max(xs)-min(xs))-1.45)>.001 or abs((max(zs)-min(zs))-1.85)>.001 or abs((max(ys)-min(ys))-.28)>.001:raise ValueError('baseline cargo dimensions changed')
    deck=deck_geometry();created=[]
    for center in [-3.2,5.8]:
        name='cargo_hold_coaming_%s'%center
        if bpy.data.objects.get(name):raise ValueError('candidate node already exists')
        rectangles=[(-.925,-.745,-1.125,1.125),(.745,.925,-1.125,1.125),(-.745,.745,-1.125,-.945),(-.745,.745,.945,1.125)]
        vertices=[];faces=[]
        for x0,x1,z0,z1 in rectangles:
            start=len(vertices)
            for x,z in [(x0,center+z0),(x1,center+z0),(x1,center+z1),(x0,center+z1)]:
                y=deck(x,z);vertices.append((x,-z,y+.03));vertices.append((x,-z,deck(0,center)+.34))
            faces += [tuple(start+i for i in face) for face in [(0,6,4,2),(1,3,5,7),(0,2,3,1),(2,4,5,3),(4,6,7,5),(6,0,1,7)]]
        mesh=bpy.data.meshes.new(name+'_mesh');mesh.from_pydata(vertices,[],faces);mesh.update()
        obj=bpy.data.objects.new(name,mesh);bpy.context.collection.objects.link(obj);obj.parent=root
        obj['deck_obstacle']=True;mesh.materials.append(teak);uv=mesh.uv_layers.new(name='UVMap')
        spans=[max(v.co[a] for v in mesh.vertices)-min(v.co[a] for v in mesh.vertices) for a in range(3)]
        for polygon in mesh.polygons:
            axis=max(range(3),key=lambda a:abs(polygon.normal[a]));axes=[a for a in range(3) if a!=axis];axes.sort(key=lambda a:spans[a],reverse=True)
            for loop in polygon.loop_indices:
                v=mesh.vertices[mesh.loops[loop].vertex_index].co;uv.data[loop].uv=(v[axes[0]]*.35,v[axes[1]]*.35)
        created.append({'name':name,'vertices':len(vertices),'faces':len(faces),'centerZ':center,'outer':[1.85,2.25],'heightAboveDeck':[.03,.34],'topHeightReference':'deck center','thickness':.18,'material':'teak','deck_obstacle':True})
    after={o.name:(o.type,o.parent.name if o.parent else None,tuple(round(v,9) for row in o.matrix_local for v in row)) for o in bpy.context.scene.objects if o.name not in [c['name'] for c in created]}
    if after!=snapshots:raise ValueError('original object identity/parent/pose changed')
    raw.parent.mkdir(parents=True,exist_ok=True);blend.parent.mkdir(parents=True,exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root]+list(root.children_recursive):
        if obj.type in {'MESH','CURVE','EMPTY'}:obj.select_set(True)
    if 'FINISHED' not in bpy.ops.export_scene.gltf(filepath=str(raw.resolve()),export_format='GLB',use_selection=True,export_apply=True,export_extras=True,export_yup=True,export_animations=False,export_morph=True):raise RuntimeError('raw author GLB failed')
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(blend.resolve()),compress=True):raise RuntimeError('editable Blend save failed')
    if before!=guarded():raise ValueError('baseline source changed during authoring')
    data={'lod':lod,'baselineSources':before,'sourceUnchanged':True,'candidateRaw':str(raw.relative_to(ROOT)).replace('\\','/'),'candidateRawSha256':sha(raw),'candidateBlend':str(blend.relative_to(ROOT)).replace('\\','/'),'candidateBlendSha256':sha(blend),'newNodes':created,'blenderVersion':bpy.app.version_string,'scope':'R7c author Blend plus two editable coamings; original geometry is LOD0 in this raw export; not shippable lower LOD', 'constraints':'Existing original cargo covers and deck_fittings untouched; no collision/GPU acceptance.'}
    receipt.parent.mkdir(parents=True,exist_ok=True)
    with receipt.open('x',encoding='utf-8') as f:json.dump(data,f,indent=2)
    print('HERO_R14B_AUTHOR_LOD_OK lod='+str(lod),flush=True)

def launch(run):
    if not run.startswith('r14b-') or not all(c in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in run):raise ValueError('safe fresh run required')
    evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art'/run;work=ROOT/'Temp/hero-fuchuan-r14b'/run
    blends=ROOT/'assets/production/hero-fuchuan-blender'/f'{run}-blends'
    if evidence.exists() or work.exists() or blends.exists():raise FileExistsError('fresh run required')
    guarded();evidence.mkdir(parents=True);work.mkdir(parents=True);blends.mkdir(parents=True)
    for lod in range(3):
        raw=work/f'fuchuan-lod{lod}.glb';blend=blends/f'hero-fuchuan-v3-r14b-lod{lod}.blend';receipt=evidence/f'blender-lod{lod}.json'
        args=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--author','--lod',str(lod),'--raw',str(raw),'--blend',str(blend),'--receipt',str(receipt)]
        start=datetime.now(timezone.utc).isoformat();result=subprocess.run(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
        log=evidence/f'blender-lod{lod}.log';log.write_bytes(result.stdout);marker=f'HERO_R14B_AUTHOR_LOD_OK lod={lod}'.encode();success=result.returncode==0 and result.stdout.count(marker)==1 and receipt.is_file()
        process={'command':args,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'exitCode':result.returncode,'markerCount':result.stdout.count(marker),'success':success,'logSha256':sha(log),'blenderSha256':sha(BLENDER),'scriptSha256':sha(Path(__file__).resolve())}
        with (evidence/f'blender-lod{lod}-process.json').open('x',encoding='utf-8') as f:json.dump(process,f,indent=2)
        print(result.stdout.decode('utf-8',errors='replace')[-1500:],flush=True)
        if not success:raise RuntimeError('Blender author failed LOD '+str(lod))
    print('HERO_R14B_AUTHOR_COMPLETE all_lods=3',flush=True)

def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--run');p.add_argument('--author',action='store_true');p.add_argument('--lod',type=int);p.add_argument('--raw',type=Path);p.add_argument('--blend',type=Path);p.add_argument('--receipt',type=Path)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:launch(a.run)
    elif a.author and a.lod in (0,1,2) and a.raw and a.blend and a.receipt:author(a.lod,a.raw,a.blend,a.receipt)
    else:p.error('launch or explicit author parameters required')
if __name__=='__main__':main()
