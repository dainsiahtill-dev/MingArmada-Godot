"""Extract new fore-strake components and nearby unchanged hull triangles."""
import argparse,collections,hashlib,json,subprocess,sys
from datetime import datetime,timezone
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r16-blockout-01.blend'
DIR=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r16-blockout-01'
BLENDER=Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def inspect():
    import bpy
    if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('candidate required')
    before=sha(SRC);r=bpy.data.objects['bulwark_rails'];m=r.data;m.calc_loop_triangles();parent=list(range(len(m.vertices)))
    def find(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for edge in m.edges:
        a,b=map(find,edge.vertices)
        if a!=b:parent[b]=a
    groups=collections.defaultdict(list)
    for i in range(len(m.vertices)):groups[find(i)].append(i)
    walls={}
    for key,ids in groups.items():
        co=[m.vertices[i].co for i in ids];zs=[-p.y for p in co]
        if len(ids)==256 and min(zs)>9.39 and max(zs)<15.61:
            side='port' if sum(p.x for p in co)>0 else 'starboard';walls[side]={'vertices':len(ids),'componentId':min(ids),'triangles':[]}
            walls[side]['_key']=key
    if set(walls)!={'port','starboard'}:raise ValueError('two fore wall components required')
    def point(obj,i):
        p=obj.matrix_world@obj.data.vertices[i].co;return [p.x,p.z,-p.y]
    for tri in m.loop_triangles:
        key=find(tri.vertices[0])
        for item in walls.values():
            if key==item['_key']:item['triangles'].append([point(r,i) for i in tri.vertices])
    for item in walls.values():del item['_key']
    hull=bpy.data.objects['hull'];hull.data.calc_loop_triangles();ht=[]
    for tri in hull.data.loop_triangles:
        points=[point(hull,i) for i in tri.vertices];zs=[p[2] for p in points];ys=[p[1] for p in points]
        if max(zs)>=9.3 and min(zs)<=15.7 and max(ys)>=2.5:ht.append(points)
    result={'candidateSha256':before,'sourceUnchanged':before==sha(SRC),'walls':walls,'hullTriangles':ht,
        'scope':'Only bow above 2.5m near z 9.3 to 15.7; no modifiers, other objects or motion.'}
    with (DIR/'FORE-CONTACT-TRIANGLES.json').open('x',encoding='utf8') as f:json.dump(result,f,separators=(',',':'))
    print('HERO_R16_FORE_EXTRACT wallTriangles=',sum(len(v['triangles']) for v in walls.values()),'hullTriangles=',len(ht),flush=True)
def launch():
    files=[DIR/'FORE-CONTACT-TRIANGLES.json',DIR/'fore-extract.log',DIR/'fore-extract-process.json']
    if any(p.exists() for p in files):raise FileExistsError('fresh output required')
    command=['rtk','proxy',str(BLENDER),'--background',str(SRC),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--','--inspect']
    start=datetime.now(timezone.utc).isoformat();r=subprocess.run(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False);files[1].write_bytes(r.stdout)
    ok=r.returncode==0 and r.stdout.count(b'HERO_R16_FORE_EXTRACT')==1 and files[0].exists()
    with files[2].open('x',encoding='utf8') as f:json.dump({'success':ok,'exitCode':r.returncode,'command':command,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),'logSha256':sha(files[1]),'scriptSha256':sha(Path(__file__)),'candidateSha256':sha(SRC)},f,indent=2)
    print(r.stdout.decode('utf8',errors='replace')[-2000:]);return 0 if ok else 1
def main():
    p=argparse.ArgumentParser();p.add_argument('--launch',action='store_true');p.add_argument('--inspect',action='store_true');a=p.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if a.launch:return launch()
    if a.inspect:inspect();return 0
    p.error('mode required')
if __name__=='__main__':raise SystemExit(main())
