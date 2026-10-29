"""Measure R9b rail mesh components and extract actual triangles, read-only."""
import argparse,collections,hashlib,json,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r9b.blend'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15c-baseline-rails-01'
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inspect():
    import bpy
    if Path(bpy.data.filepath).resolve()!=SOURCE.resolve():raise ValueError('R9b source required')
    before=sha(SOURCE);obj=bpy.data.objects.get('bulwark_rails')
    if obj is None or obj.type!='MESH':raise ValueError('rail mesh missing')
    mesh=obj.data;mesh.calc_loop_triangles();parent=list(range(len(mesh.vertices)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    def union(a,b):
        a=find(a);b=find(b)
        if a!=b:parent[b]=a
    for edge in mesh.edges:union(edge.vertices[0],edge.vertices[1])
    groups=collections.defaultdict(list)
    for i in range(len(mesh.vertices)):groups[find(i)].append(i)
    tris=collections.defaultdict(list)
    points=[obj.matrix_world@v.co for v in mesh.vertices]
    godot=[(p.x,p.z,-p.y) for p in points]
    for tri in mesh.loop_triangles:
        component=find(tri.vertices[0]);
        if any(find(i)!=component for i in tri.vertices):raise ValueError('triangle spans components')
        tris[component].append([godot[i] for i in tri.vertices])
    items=[]
    for component,indices in sorted(groups.items(),key=lambda x:min(x[1])):
        vs=[godot[i] for i in indices];items.append({'id':min(indices),'vertexCount':len(indices),'triangleCount':len(tris[component]),
            'min':[min(p[i] for p in vs) for i in range(3)],'max':[max(p[i] for p in vs) for i in range(3)],'triangles':tris[component]})
    result={'sourceSha256':before,'sourceUnchanged':before==sha(SOURCE),'rail':obj.name,'vertices':len(mesh.vertices),'edges':len(mesh.edges),'faces':len(mesh.polygons),'triangles':len(mesh.loop_triangles),'components':items,
            'scope':'Blender mesh topology components and static triangles, not contact, animation or collision acceptance.'}
    with (DIR/'RAIL-COMPONENTS.json').open('x',encoding='utf8') as f:json.dump(result,f,separators=(',',':'))
    print('HERO_R15C_RAIL_MEASURE components=',len(items),' vertices=',len(mesh.vertices),' faces=',len(mesh.polygons),flush=True)
def launch():
    if DIR.exists():raise FileExistsError('fresh evidence required')
    DIR.mkdir(parents=True);before=sha(SOURCE)
    command=['rtk','proxy',str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    started=datetime.now(timezone.utc).isoformat();p=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
    log=DIR/'blender.log';log.write_bytes(p.stdout);marker=b'HERO_R15C_RAIL_MEASURE';success=p.returncode==0 and p.stdout.count(marker)==1 and before==sha(SOURCE) and (DIR/'RAIL-COMPONENTS.json').is_file()
    with (DIR/'process.json').open('x',encoding='utf8') as f:json.dump({'success':success,'exitCode':p.returncode,'command':command,'startedUTC':started,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(log),'sourceSha256':before,'scriptSha256':sha(Path(__file__)),'blenderSha256':sha(BLENDER)},f,indent=2)
    print(p.stdout.decode('utf8',errors='replace')[-1500:]);return 0 if success else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:inspect();return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
