"""Independent R9b/R15b Blender reopen: originals exact except bow rail faces."""
import argparse,collections,hashlib,json,struct,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
CANDIDATE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15b-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
NAMES={'r15b_foreworks_port','r15b_foreworks_starboard','r15b_wale_port','r15b_wale_starboard','r15b_sternrail_port','r15b_sternrail_starboard'}
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def object_snapshot(obj):
    row={'type':obj.type,'parent':obj.parent.name if obj.parent else None,'matrix':[[float(v) for v in r] for r in obj.matrix_local],'hidden':[obj.hide_render,obj.hide_viewport]}
    if obj.type=='MESH':
        d=obj.data;h=hashlib.sha256()
        for v in d.vertices:h.update(struct.pack('<fff',*v.co))
        for p in d.polygons:
            h.update(struct.pack('<II',p.material_index,len(p.vertices)))
            for v in p.vertices:h.update(struct.pack('<I',v))
        for layer in d.uv_layers:
            h.update(layer.name.encode()+b'\0')
            for uv in layer.data:h.update(struct.pack('<ff',*uv.uv))
        for m in d.materials:h.update((m.name if m else '').encode()+b'\0')
        if d.shape_keys:
            for k in d.shape_keys.key_blocks:
                h.update(k.name.encode()+b'\0')
                for v in k.data:h.update(struct.pack('<fff',*v.co))
        row['meshSha256']=h.hexdigest()
    return row
def rail_faces(mesh):
    result=collections.Counter();locations={}
    for poly in mesh.polygons:
        corners=[];zs=[]
        for li in poly.loop_indices:
            co=mesh.vertices[mesh.loops[li].vertex_index].co;uv=mesh.uv_layers.active.data[li].uv if mesh.uv_layers.active else (0.,0.)
            corners.append(tuple(float(x).hex() for x in [*co,*uv]));zs.append(-co.y)
        rotations=[tuple(corners[i:]+corners[:i]) for i in range(len(corners))]
        key=(poly.material_index,min(rotations));result[key]+=1;locations[key]=(min(zs),max(zs))
    return result,locations
def canvas():
    import bpy
    mat=bpy.data.materials.get('canvas');nodes=[n for n in mat.node_tree.nodes if n.type=='TEX_IMAGE'] if mat else []
    if len(nodes)!=1 or nodes[0].image is None or nodes[0].image.packed_file is None:raise ValueError('missing packed canvas')
    return {'packedSha256':hashlib.sha256(bytes(nodes[0].image.packed_file.data)).hexdigest(),'node':nodes[0].name,
            'links':sorted((l.from_node.name,l.from_socket.name,l.to_node.name,l.to_socket.name) for l in mat.node_tree.links)}
def inspect():
    import bpy
    before={p.as_posix():sha(p) for p in [SOURCE,CANDIDATE]}
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('source must be open')
    old={o.name:object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails'}
    oldrail,locations=rail_faces(bpy.data.objects['bulwark_rails'].data);oldcanvas=canvas()
    bpy.ops.wm.open_mainfile(filepath=str(CANDIDATE))
    current={o.name:object_snapshot(o) for o in bpy.context.scene.objects if o.name!='bulwark_rails' and not o.name.startswith('r15b_')}
    newrail,_=rail_faces(bpy.data.objects['bulwark_rails'].data);newcanvas=canvas()
    added={o.name for o in bpy.context.scene.objects if o.name.startswith('r15b_')};errors=[]
    if old!=current:errors.append('existing non-rail objects differ')
    if oldcanvas!=newcanvas:errors.append('canvas image or material links differ')
    if oldcanvas['packedSha256']!='f89da712948d0b3f3f72506f1375fbe27c8fabee6d816c5ea055ced67b491970':errors.append('not the registered R9b canvas')
    if added!=NAMES:errors.append('unexpected added structural objects')
    unexpected=newrail-oldrail;removed=oldrail-newrail
    if sum(unexpected.values()):errors.append('old rail contains new/mutated faces')
    outside=[{'bounds':locations[key],'count':count} for key,count in removed.items() if locations[key][0]<10.3 or locations[key][1]>15.7]
    if outside:errors.append('removed rail faces extend outside allowed bow region')
    if not removed:errors.append('no overlapping bow rail faces removed')
    structures=[]
    for name in sorted(added):
        obj=bpy.data.objects[name];p=[obj.matrix_world@v.co for v in obj.data.vertices];minimum=min(v.z for v in p)
        if minimum<=.5:errors.append('new geometry crosses protected waterline band '+name)
        degenerate=sum(1 for f in obj.data.polygons if f.area<=1e-10)
        if degenerate:errors.append('new structure has zero-area faces '+name)
        structures.append({'name':name,'vertices':len(p),'faces':len(obj.data.polygons),'minY':minimum,'maxY':max(v.z for v in p),'degenerateFaces':degenerate})
    if before!={p.as_posix():sha(p) for p in [SOURCE,CANDIDATE]}:errors.append('input changed during audit')
    report={'pass':not errors,'errors':errors,'baselineSha256':before[SOURCE.as_posix()],'candidateSha256':before[CANDIDATE.as_posix()],'existingNonRailObjectsExact':old==current,'existingCount':len(old),'canvasIdentical':oldcanvas==newcanvas,'canvas':newcanvas,'removedRailFaceCount':sum(removed.values()),'unexpectedRailFaceCount':sum(unexpected.values()),'removedOutsideAllowedRegion':outside,'structures':structures,'scope':'Independent static reopened Blender geometry/UV/morph, packed image and permissible bow rail edits; no proof of visual joining, dynamic sweep, collision, Godot shadow or gameplay.'}
    with (DIR/'reopen-audit-01.json').open('x',encoding='utf8') as f:json.dump(report,f,indent=2)
    print('HERO_R15B_REOPEN_AUDIT removed=',sum(removed.values()),' failures=',len(errors),' details=',errors,flush=True)
    return 0 if not errors else 1
def launch():
    report=DIR/'reopen-audit-01.json';log=DIR/'reopen-audit-01.log';process=DIR/'reopen-audit-01-process.json'
    if any(p.exists() for p in [report,log,process]):raise FileExistsError('fresh audit required')
    command=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log.write_bytes(r.stdout)
    d=json.loads(report.read_text(encoding='utf8')) if report.exists() else {};ok=r.returncode==0 and d.get('pass') is True and r.stdout.count(b'HERO_R15B_REOPEN_AUDIT')==1
    with process.open('x',encoding='utf8') as f:json.dump({'success':ok,'command':command,'exitCode':r.returncode,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'toolSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2000:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:return inspect()
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
