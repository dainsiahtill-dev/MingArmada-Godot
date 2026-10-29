"""Extract actual Blender candidate triangle surfaces, no transforms or writes to source."""
import hashlib,json
from pathlib import Path
import bpy
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r15b-blockout-01.blend'
OUT=ROOT/'docs/production/hero-fuchuan-2026-10-26-art/r15b-blockout-01/join-triangles-01.json'
if OUT.exists():raise FileExistsError('fresh output required')
if Path(bpy.data.filepath).resolve()!=SRC.resolve():raise ValueError('candidate source not open')
before=hashlib.sha256(SRC.read_bytes()).hexdigest();records={}
for name in ['bulwark_rails','r15b_foreworks_port','r15b_foreworks_starboard','r15b_sternrail_port','r15b_sternrail_starboard']:
    ob=bpy.data.objects.get(name)
    if ob is None or ob.type!='MESH':raise ValueError('missing '+name)
    mesh=ob.data;mesh.calc_loop_triangles();points=[ob.matrix_world@v.co for v in mesh.vertices]
    records[name]=[[[points[i].x,points[i].z,-points[i].y] for i in tri.vertices] for tri in mesh.loop_triangles]
if before!=hashlib.sha256(SRC.read_bytes()).hexdigest():raise ValueError('candidate source changed')
with OUT.open('x',encoding='utf8') as f:json.dump({'sourceSha256':before,'triangles':records,'scope':'Unmodified actual Blender candidate triangles in Godot coordinate units; no animation or GPU.'},f,separators=(',',':'))
print('HERO_R15B_JOIN_EXTRACTION_OK',flush=True)
