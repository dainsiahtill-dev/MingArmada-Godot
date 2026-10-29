"""Create the pre-registered R15 whole-ship Blender-only art blockout."""
import argparse,ast,hashlib,importlib.util,json,math,struct,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
V3=ROOT/'tools/blender/build_hero_fuchuan_v3.py'
BASE=ROOT/'tools/blender/build_hero_fuchuan.py'
R12=ROOT/'tools/blender/build_hero_fuchuan_r12.py'
FORMULA=ROOT/'tools/blender/hero_r15_sail_formula.py'
TEXTURE=ROOT/'assets/textures/hero_fuchuan_r13/weathered-cinnabar-hemp.png'
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R15-WHOLE-SHIP-BLOCKOUT-BRIEF.md'
BASELINE=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15-baseline-measure-01/BASELINE-MEASURE.json'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SRC_HASH='ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3'
TEXTURE_HASH='0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b'
SAILS=[(0,10.3,7.2,4.6),(1,17.,12.2,4.05),(2,9.,6.2,5.35)]

def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def guards():
    if sha(SRC)!=SRC_HASH or sha(TEXTURE)!=TEXTURE_HASH:raise ValueError('author source or R13 image differs')
    paths=[SRC,V3,BASE,R12,FORMULA,TEXTURE,BRIEF,BASELINE,Path(__file__).resolve()]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj
def source_geometry():
    tree=ast.parse(V3.read_text(encoding='utf-8'))
    names=['smooth_table','sheer','quarter_width','quarter_y','outer_x']
    nodes=[n for n in tree.body if isinstance(n,ast.FunctionDef) and n.name in names]
    if [n.name for n in nodes]!=names:raise ValueError('unexpected V3 hull helpers')
    env={'math':math};exec(compile(ast.fix_missing_locations(ast.Module(body=nodes,type_ignores=[])),str(V3),'exec'),env);return env
def mesh_digest(obj):
    if obj.type!='MESH':return None
    data=obj.data;h=hashlib.sha256()
    for v in data.vertices:h.update(struct.pack('<fff',*v.co))
    for p in data.polygons:
        h.update(struct.pack('<II',p.material_index,len(p.vertices)))
        for i in p.vertices:h.update(struct.pack('<I',i))
    for layer in data.uv_layers:
        h.update(layer.name.encode())
        for uv in layer.data:h.update(struct.pack('<ff',*uv.uv))
    for m in data.materials:h.update((m.name if m else '').encode()+b'\0')
    if data.shape_keys:
        for key in data.shape_keys.key_blocks:
            h.update(key.name.encode()+b'\0')
            for v in key.data:h.update(struct.pack('<fff',*v.co))
    return h.hexdigest()
def snapshot(obj):
    return {'type':obj.type,'parent':obj.parent.name if obj.parent else None,
            'matrix':[[round(v,9) for v in row] for row in obj.matrix_local],
            'hideRender':obj.hide_render,'hideViewport':obj.hide_viewport,'meshSha256':mesh_digest(obj)}

def build():
    import bpy
    before=guards()
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('R7c source required')
    if '--vintage' not in sys.argv:sys.argv.append('--vintage')
    B=module('hero_r15_base',BASE);B.LOD=0;B.OBJECTS=[]
    for name in ['canvas','bamboo','canvas_seam','hemp','teak']:
        material=bpy.data.materials.get(name)
        if material is None:raise ValueError('missing original material '+name)
        B.MATS[name]=material
    root=bpy.data.objects.get('HeroFuchuan')
    if root is None:raise ValueError('hero root missing')
    baseline={o.name:snapshot(o) for o in bpy.context.scene.objects if not o.name.startswith('sail_')}
    for name in ['hull','deck','shadow_hull','shadow_deck','rudder_pivot','crew_helm','mast_0','mast_1','mast_2']:
        if name not in baseline:raise ValueError('required baseline node missing '+name)
    sockets=[n for n in baseline if n.startswith('socket_smoke_')]
    if len(sockets)!=8:raise ValueError('expected eight authored cannon sockets')
    material=B.MATS['canvas'];nodes=[n for n in material.node_tree.nodes if n.type=='TEX_IMAGE']
    if len(nodes)!=1 or nodes[0].image is None:raise ValueError('canvas texture node missing')
    old_image=nodes[0].image.name;links=sorted((l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in material.node_tree.links)
    image=bpy.data.images.load(str(TEXTURE.resolve()),check_existing=False);image.name='r15-weathered-cinnabar';image.pack()
    if image.packed_file is None or hashlib.sha256(bytes(image.packed_file.data)).hexdigest()!=TEXTURE_HASH:raise ValueError('packed R13 sail source differs')
    nodes[0].image=image
    if links!=sorted((l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in material.node_tree.links):raise ValueError('canvas connections changed')
    formula=module('hero_r15_formula',FORMULA);author=module('hero_r12_author',R12)
    env={'math':math,'B':B,'r10_breadth':formula.breadth,'r12_rake':formula.rake,'sail_surface':formula.surface}
    sail=author.build_sail_function(env);sails=[]
    for index,height,width,base in SAILS:
        old=bpy.data.objects.get(f'sail_{index}');mast=bpy.data.objects.get(f'mast_{index}')
        if old is None or mast is None or old.parent!=mast:raise ValueError('missing original sail hierarchy')
        old.name='r15-old-sail-'+str(index);new=sail(mast,index,height,width,base)
        if new.name!=f'sail_{index}' or new.parent!=mast or [k.name for k in new.data.shape_keys.key_blocks]!=['Basis','furl','inflate']:raise ValueError('sail role/shape key contract differs')
        bpy.data.objects.remove(old,do_unlink=True)
        sails.append({'name':new.name,'parent':mast.name,'vertices':len(new.data.vertices),'materials':[m.name for m in new.data.materials],'shapeKeys':[k.name for k in new.data.shape_keys.key_blocks],'parameters':[height,width,base,*formula.coefficients(width)]})
    g=source_geometry();created=[]
    def wall_piece(side,zs,radial,bottom,top):
        verts=[];faces=[]
        for z in zs:
            for y,outer in [(bottom(z),0),(bottom(z),.10),(top(z),.10),(top(z),0)]:
                verts.append((side*(radial(z,y)+outer),y,z))
        for i in range(len(zs)-1):
            a=4*i;b=4*(i+1)
            faces.extend([(a,a+1,b+1,b),(a+1,a+2,b+2,b+1),(a+2,a+3,b+3,b+2),(a+3,a,b,b+3)])
        faces.extend([(3,2,1,0),tuple(4*(len(zs)-1)+i for i in range(4))])
        return B.mesh('r15_temp_piece',verts,faces,'teak',root)
    def zs(a,b,n=12):return [a+(b-a)*i/n for i in range(n+1)]
    for side,label in [(-1,'starboard'),(1,'port')]:
        fore=wall_piece(side,zs(10.8,15.5),lambda z,y:g['smooth_table'](z)-.06,
                        lambda z:g['sheer'](z)+.72,lambda z:g['sheer'](z)+1.65+.50*(z-10.8)/4.7)
        fore.name='r15_foreworks_'+label;fore['deck_obstacle']=True;created.append(fore)
        wale=wall_piece(side,zs(-14.7,14.7,48),lambda z,y:g['outer_x'](y,z)+.035,lambda z:1.34,lambda z:1.70)
        wale.name='r15_wale_'+label;created.append(wale)
        lower=lambda z:g['quarter_y'](z)-.08
        upper=lambda z:g['quarter_y'](z)+1.65
        radial=lambda z,y:g['quarter_width'](z)+.10
        pieces=[wall_piece(side,zs(-15.4,-10.3),radial,lower,lambda z:lower(z)+.55),
                wall_piece(side,zs(-15.4,-10.3),radial,lambda z:upper(z)-.20,upper)]
        for post_z in [-15.4,-13.7,-12.0,-10.3]:
            a=max(-15.4,post_z-.12);b=min(-10.3,post_z+.12)
            pieces.append(wall_piece(side,[a,b],radial,lower,upper))
        aft=B.join(pieces,'r15_sternworks_'+label,root);aft['deck_obstacle']=True;created.append(aft)
    after={o.name:snapshot(o) for o in bpy.context.scene.objects if not o.name.startswith(('sail_','r15_'))}
    if after!=baseline:raise ValueError('existing non-sail object data or transform changed')
    if before!=guards():raise ValueError('frozen input changed')
    return {'baselineSources':before,'existingNonSailObjectsExact':True,'existingNonSailCount':len(baseline),
            'sailChanges':sails,'canvas':{'previousImage':old_image,'packedSha256':TEXTURE_HASH,'nodeLinksUnchanged':True},
            'addedNodes':[{'name':o.name,'vertices':len(o.data.vertices),'materials':[m.name for m in o.data.materials],'deck_obstacle':bool(o.get('deck_obstacle',False))} for o in created],
            'scope':'Blender static art blockout; original hull/deck and waterline unchanged. No LOD, GPU, collision, animation, shadow integration or gameplay acceptance.'}

def author(destination,receipt):
    import bpy
    if destination.exists() or receipt.exists():raise FileExistsError('fresh candidate and receipt required')
    info=build();destination.parent.mkdir(parents=True,exist_ok=True);receipt.parent.mkdir(parents=True,exist_ok=True)
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(destination.resolve()),compress=True):raise RuntimeError('Blender save failed')
    if info['baselineSources']!=guards():raise ValueError('inputs changed during save')
    info.update({'candidateBlend':destination.relative_to(ROOT).as_posix(),'candidateBlendSha256':sha(destination),'blenderVersion':bpy.app.version_string,'finishedUTC':datetime.now(timezone.utc).isoformat()})
    with receipt.open('x',encoding='utf-8') as f:json.dump(info,f,indent=2,ensure_ascii=False)
    print('HERO_R15_BLOCKOUT_AUTHOR_OK',flush=True)
def launch():
    evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15-blockout-01';destination=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15-blockout-01.blend'
    if evidence.exists() or destination.exists():raise FileExistsError('fresh output required')
    guards();evidence.mkdir(parents=True)
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--author','--destination',str(destination),'--receipt',str(evidence/'author.json')]
    start=datetime.now(timezone.utc).isoformat();result=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    log=evidence/'blender-author.log';log.write_bytes(result.stdout);marker=b'HERO_R15_BLOCKOUT_AUTHOR_OK';ok=result.returncode==0 and result.stdout.count(marker)==1 and (evidence/'author.json').is_file()
    with (evidence/'blender-author-process.json').open('x',encoding='utf-8') as f:json.dump({'success':ok,'command':command,'exitCode':result.returncode,'markerCount':result.stdout.count(marker),'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'scriptSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(result.stdout.decode('utf-8',errors='replace')[-2500:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--author',action='store_true');p.add_argument('--destination',type=Path);p.add_argument('--receipt',type=Path)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.author and a.destination and a.receipt:author(a.destination,a.receipt);return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
