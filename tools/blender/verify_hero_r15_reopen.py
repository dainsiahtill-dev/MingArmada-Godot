"""Independently reopen R7c and R15 Blender files and check static contracts."""
import argparse,hashlib,json,math,struct,subprocess,sys
from pathlib import Path
from datetime import datetime,timezone
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
CANDIDATE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
PARAMS=[(10.3,7.2,4.6,.18,.10),(17.,12.2,4.05,.30,.17),(9.,6.2,5.35,.50,.08)]
EXPECTED_NODES={'r15_foreworks_port','r15_foreworks_starboard','r15_wale_port','r15_wale_starboard','r15_sternworks_port','r15_sternworks_starboard'}
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def uv_topology(obj):
    d=obj.data;h=hashlib.sha256()
    for p in d.polygons:
        h.update(struct.pack('<II',p.material_index,len(p.vertices)))
        for i in p.vertices:h.update(struct.pack('<I',i))
    for layer in d.uv_layers:
        for uv in layer.data:h.update(struct.pack('<ff',*uv.uv))
    return h.hexdigest()
def original_state(obj):
    out={'type':obj.type,'parent':obj.parent.name if obj.parent else None,'matrix':[[round(v,9) for v in r] for r in obj.matrix_local],'hidden':[obj.hide_render,obj.hide_viewport]}
    if obj.type=='MESH':
        d=obj.data;h=hashlib.sha256()
        for v in d.vertices:h.update(struct.pack('<fff',*v.co))
        h.update(uv_topology(obj).encode())
        for m in d.materials:h.update((m.name if m else '').encode()+b'\0')
        if d.shape_keys:
            for key in d.shape_keys.key_blocks:
                h.update(key.name.encode())
                for v in key.data:h.update(struct.pack('<fff',*v.co))
        out['meshSha256']=h.hexdigest()
    return out
def inspect():
    import bpy
    before={p.as_posix():sha(p) for p in [SOURCE,CANDIDATE]}
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('baseline source not open')
    base={o.name:original_state(o) for o in bpy.context.scene.objects if not o.name.startswith('sail_')}
    uv={o.name:uv_topology(o) for o in bpy.context.scene.objects if o.name in ['sail_0','sail_1','sail_2']}
    bpy.ops.wm.open_mainfile(filepath=str(CANDIDATE))
    cand={o.name:original_state(o) for o in bpy.context.scene.objects if not o.name.startswith(('sail_','r15_'))}
    errors=[]
    if cand!=base:errors.append('existing non-sail object data or transforms differ')
    new={o.name for o in bpy.context.scene.objects if o.name.startswith('r15_')}
    if new!=EXPECTED_NODES:errors.append('unexpected new structural nodes')
    texture=bpy.data.materials.get('canvas');images=[n.image for n in texture.node_tree.nodes if n.type=='TEX_IMAGE'] if texture else []
    if len(images)!=1 or images[0] is None or images[0].packed_file is None or hashlib.sha256(bytes(images[0].packed_file.data)).hexdigest()!='0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b':errors.append('canvas image differs from registered R13 asset')
    sails=[]
    for index,(height,width,base_y,k,rake) in enumerate(PARAMS):
        obj=bpy.data.objects.get('sail_'+str(index));name='sail_'+str(index)
        if not obj or obj.parent.name!='mast_'+str(index) or not obj.data.shape_keys:errors.append('missing sail or mast '+name);continue
        names=[q.name for q in obj.data.shape_keys.key_blocks]
        if names!=['Basis','furl','inflate'] or uv_topology(obj)!=uv.get(name):errors.append('shape key/UV/topology mismatch '+name)
        d=obj.data;coords={}
        for poly in d.polygons:
            mat=d.materials[poly.material_index]
            if mat and mat.name=='canvas':
                for loop in poly.loop_indices:coords[d.loops[loop].vertex_index]=d.uv_layers.active.data[loop].uv[:]
        max_surface=0.;max_morph=0.
        for i,(u,v) in coords.items():
            x,nz,y=d.vertices[i].co;z=-nz
            b=width*(1+.10*math.sin(math.pi*v)-k*v*v)
            expected_z=b*(u-.70)-.045*width*v*v
            expected_y=base_y+height*v+height*rake*(1-u)*v**2.2
            expected_x=.32+(.30*math.sin(math.pi*v)+.025*math.sin(math.pi*((8*v)%1))**2)*math.sin(math.pi*u)
            max_surface=max(max_surface,abs(z-expected_z),abs(y-expected_y),min(abs(x-expected_x),abs(x-expected_x-.026)))
        for i,vertex in enumerate(d.vertices):
            x,nz,y=vertex.co;z=-nz;v=max(0,min(1,(y-base_y)/(height*1.12)))
            for _ in range(12):
                b=width*(1+.10*math.sin(math.pi*v)-k*v*v);u=max(0,min(1,(z+width*.045*v*v)/b+.70))
                v=max(0,min(1,(y-base_y)/height-rake*(1-u)*v**2.2))
            furl=d.shape_keys.key_blocks['furl'].data[i].co;inflate=d.shape_keys.key_blocks['inflate'].data[i].co
            expected_furl_x=.32+(x-.32)*.2;expected_furl_y=base_y+(y-base_y)*.038
            expected_inflate_x=x+(width*.019*math.sin(math.pi*v)*math.sin(math.pi*u) if x>.25 else 0)
            max_morph=max(max_morph,abs(furl.x-expected_furl_x),abs(furl.z-expected_furl_y),abs(inflate.x-expected_inflate_x))
        if max_surface>1e-5 or max_morph>1e-5:errors.append('sail formula/morph mismatch '+name)
        sails.append({'name':name,'canvasVerticesChecked':len(coords),'allVerticesChecked':len(d.vertices),'maxCanvasSurfaceErrorMeters':max_surface,'maxFurlInflateErrorMeters':max_morph,'uvTopologyExact':uv_topology(obj)==uv.get(name),'shapeKeys':names})
    structures=[]
    for name in sorted(new):
        obj=bpy.data.objects[name];coords=[obj.matrix_world@v.co for v in obj.data.vertices]
        ys=[v.z for v in coords];minimum=min(ys);maximum=max(ys)
        if minimum<=.5:errors.append('new geometry enters protected waterline slice: '+name)
        structures.append({'name':name,'minY':minimum,'maxY':maximum,'vertices':len(coords),'deckObstacleAuthorProperty':bool(obj.get('deck_obstacle',False))})
    if before!={p.as_posix():sha(p) for p in [SOURCE,CANDIDATE]}:errors.append('source changed while reopened')
    report={'pass':not errors,'errors':errors,'sourceSha256':before[SOURCE.as_posix()],'candidateSha256':before[CANDIDATE.as_posix()],'existingObjectsExact':cand==base,'existingObjectCount':len(base),'sails':sails,'structures':structures,'scope':'Independent reopened Blender files, static data and surface formulas only; no LOD, runtime damage, shadow, animation, collision, GPU or gameplay acceptance.'}
    with (DIR/'reopen-audit-01.json').open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    print('HERO_R15_REOPEN_AUDIT checks=',len(sails),'failures=',len(errors),' details=',errors,flush=True)
    return 0 if not errors else 1
def launch():
    report=DIR/'reopen-audit-01.json';log=DIR/'reopen-audit-01.log';process=DIR/'reopen-audit-01-process.json'
    if any(p.exists() for p in [report,log,process]):raise FileExistsError('fresh audit evidence required')
    command=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    start=datetime.now(timezone.utc).isoformat();p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);log.write_bytes(p.stdout)
    data=json.loads(report.read_text(encoding='utf-8')) if report.exists() else {};ok=p.returncode==0 and data.get('pass') is True and p.stdout.count(b'HERO_R15_REOPEN_AUDIT')==1
    with process.open('x',encoding='utf-8') as f:json.dump({'success':ok,'command':command,'exitCode':p.returncode,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'toolSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(p.stdout.decode('utf8',errors='replace')[-2500:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:return inspect()
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
