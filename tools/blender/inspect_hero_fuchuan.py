import bpy,json
from pathlib import Path
p=Path(__file__).resolve().parents[2]/'assets/production/hero-fuchuan-blender/hero-fuchuan.blend'
bpy.ops.wm.open_mainfile(filepath=str(p))
for o in bpy.data.objects:
    if o.type=='MESH' and o.name.startswith('sail_'):
        print(json.dumps({'name':o.name,'meshYheight':max(v.co.z for v in o.data.vertices)-min(v.co.z for v in o.data.vertices),'only':o.show_only_shape_key,'active':o.active_shape_key_index,'keys':[(k.name,k.value,min(v.co.z for v in k.data),max(v.co.z for v in k.data)) for k in o.data.shape_keys.key_blocks]}))
