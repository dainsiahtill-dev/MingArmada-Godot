"""R15c independent Blender blockout: deform the one existing R9b rail mesh."""
import argparse,hashlib,importlib.util,json,math,struct,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
BRIEF=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/R15C-CONTINUOUS-RAIL-BRIEF.md'
FIELD=ROOT/'tools/research/hero_r15c_field.py'
TOPOLOGY=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-baseline-rails-01/RAIL-COMPONENTS.json'
JOINS=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-baseline-rails-01/JOIN-BASELINE.json'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
SRC_HASH='2961f7f28d31cfc71a16638fbd634b4245912adb1fcf79bc55bfc5d00722d2e8'
IMAGE_HASH='f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def guards():
    if sha(SOURCE)!=SRC_HASH:raise ValueError('R9b author baseline changed')
    paths=[SOURCE,BRIEF,FIELD,TOPOLOGY,JOINS,Path(__file__).resolve()]
    return {p.relative_to(ROOT).as_posix():sha(p) for p in paths}
def load_field():
    s=importlib.util.spec_from_file_location('r15c_field',FIELD);m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m
def mesh_hash(mesh,positions=True):
    h=hashlib.sha256()
    if positions:
        for v in mesh.vertices:h.update(struct.pack('<fff',*v.co))
    for e in mesh.edges:h.update(struct.pack('<II',*e.vertices))
    for p in mesh.polygons:
        h.update(struct.pack('<II',p.material_index,len(p.vertices)))
        for v in p.vertices:h.update(struct.pack('<I',v))
    for layer in mesh.uv_layers:
        h.update(layer.name.encode()+b'\0')
        for uv in layer.data:h.update(struct.pack('<ff',*uv.uv))
    for m in mesh.materials:h.update((m.name if m else '').encode()+b'\0')
    if mesh.shape_keys:
        for key in mesh.shape_keys.key_blocks:
            h.update(key.name.encode()+b'\0')
            for v in key.data:h.update(struct.pack('<fff',*v.co))
    return h.hexdigest()
def snapshot(o):
    return {'type':o.type,'parent':o.parent.name if o.parent else None,'matrix':[[float(v) for v in r] for r in o.matrix_local],
            'hidden':[o.hide_render,o.hide_viewport],'meshSha256':mesh_hash(o.data) if o.type=='MESH' else None}
def build():
    import bpy
    before=guards()
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('incorrect author source')
    rail=bpy.data.objects.get('bulwark_rails');root=bpy.data.objects.get('HeroFuchuan')
    if rail is None or rail.type!='MESH' or rail.parent!=root or not rail.matrix_local.is_identity:raise ValueError('unsupported rail frame')
    baseline={o.name:snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    if len([n for n in baseline if n.startswith('socket_smoke_')])!=8:raise ValueError('eight cannon sockets required')
    if any(n not in baseline for n in ['hull','deck','shadow_hull','shadow_deck','sail_0','sail_1','sail_2','rudder_pivot','crew_helm']):raise ValueError('required object missing')
    canvas=bpy.data.materials.get('canvas');images=[n.image for n in canvas.node_tree.nodes if n.type=='TEX_IMAGE'] if canvas else []
    if len(images)!=1 or images[0] is None or images[0].packed_file is None or hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest()!=IMAGE_HASH:raise ValueError('R9b canvas image differs')
    field=load_field();mesh=rail.data;old_topology=mesh_hash(mesh,False);old_positions=[v.co.copy() for v in mesh.vertices];mesh.calc_loop_triangles()
    old_cross=[(old_positions[t.vertices[1]]-old_positions[t.vertices[0]]).cross(old_positions[t.vertices[2]]-old_positions[t.vertices[0]]) for t in mesh.loop_triangles]
    moved=[];max_displacement=0.;out_of_range=0;max_formula_error=0.
    for i,v in enumerate(mesh.vertices):
        x,negative_z,y=old_positions[i];z=-negative_z;delta=field.displacement(y,z)
        if delta<0 or delta>.8500001:raise ValueError('displacement out of registered bound')
        if delta:
            v.co.z=y+delta;moved.append(i);max_displacement=max(max_displacement,delta)
        if not (-15.6<z<-9.8 or 10.3<z<15.7) and v.co!=old_positions[i]:out_of_range+=1
        max_formula_error=max(max_formula_error,abs(v.co.z-(y+delta)))
        if v.co.x!=x or v.co.y!=negative_z:raise ValueError('transverse/longitudinal coordinate changed')
    mesh.update();mesh.calc_loop_triangles();new_degenerate=0;flipped=0
    for old,t in zip(old_cross,mesh.loop_triangles,strict=True):
        a,b,c=(mesh.vertices[i].co for i in t.vertices);cross=(b-a).cross(c-a)
        if old.length>1e-10 and cross.length<=1e-10:new_degenerate+=1
        if old.length>1e-10 and cross.length>1e-10 and old.dot(cross)<=0:flipped+=1
    after={o.name:snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    if baseline!=after or old_topology!=mesh_hash(mesh,False) or out_of_range:raise ValueError('baseline object, topology, material, UV or non-target vertex changed')
    if new_degenerate or flipped:raise ValueError(f'new triangle degeneracy={new_degenerate} flip={flipped}')
    if before!=guards():raise ValueError('input changed')
    return {'baselineSources':before,'existingNonRailObjectsExact':True,'existingObjectCount':len(baseline),'railTopologyUvMaterialSha256':old_topology,
            'railVertices':len(mesh.vertices),'movedVertices':len(moved),'maxDisplacementMeters':max_displacement,'maxFloatRoundingErrorMeters':max_formula_error,
            'outsideRangeChangedVertices':out_of_range,'newDegenerateTriangles':new_degenerate,'flippedTriangles':flipped,'canvasPackedSha256':IMAGE_HASH,
            'scope':'Single original disconnected rail mesh deformed by one field; no weld, Godot, shadow, collision, animation, GPU or gameplay acceptance.'}
def author(destination,receipt):
    import bpy
    if destination.exists() or receipt.exists():raise FileExistsError('fresh outputs required')
    info=build();destination.parent.mkdir(parents=True,exist_ok=True);receipt.parent.mkdir(parents=True,exist_ok=True)
    if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(destination.resolve()),compress=True):raise RuntimeError('Blender save failed')
    if info['baselineSources']!=guards():raise ValueError('inputs changed during save')
    info.update({'candidateBlend':destination.relative_to(ROOT).as_posix(),'candidateBlendSha256':sha(destination),'blenderVersion':bpy.app.version_string,'finishedUTC':datetime.now(timezone.utc).isoformat()})
    with receipt.open('x',encoding='utf8') as f:json.dump(info,f,indent=2)
    print('HERO_R15C_AUTHOR_OK',flush=True)
def launch():
    evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-blockout-01';dest=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15c-blockout-01.blend'
    if evidence.exists() or dest.exists():raise FileExistsError('fresh candidate required')
    guards();evidence.mkdir(parents=True)
    command=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--author','--destination',str(dest),'--receipt',str(evidence/'author.json')]
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log=evidence/'blender-author.log';log.write_bytes(r.stdout)
    marker=b'HERO_R15C_AUTHOR_OK';ok=r.returncode==0 and r.stdout.count(marker)==1 and (evidence/'author.json').is_file()
    with (evidence/'blender-author-process.json').open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'markerCount':r.stdout.count(marker),'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'scriptSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2500:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--author',action='store_true');p.add_argument('--destination',type=Path);p.add_argument('--receipt',type=Path)
    a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.author and a.destination and a.receipt:author(a.destination,a.receipt);return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
