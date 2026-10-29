"""Read-only Blender comparison of R9b and R11 authoring data."""
import array
import hashlib
import json
import struct
import sys
from pathlib import Path
import bpy

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools/research'))
import verify_hero_r11b_delta as gate


def digest(raw):return hashlib.sha256(raw).hexdigest()
def packed(collection,field,width,code):
    values=array.array(code,[0])*(len(collection)*width)
    collection.foreach_get(field,values)
    return digest(values.tobytes())
def f32(value):return struct.unpack('<f',struct.pack('<f',value))[0]


def scalar_or_vector(value):
    if isinstance(value,(bool,int,float,str)) or value is None:return value
    try:return tuple(value)
    except TypeError:return getattr(value,'name',str(value))


def node_signature(node):
    inputs=[]
    for socket in node.inputs:
        if hasattr(socket,'default_value'):
            inputs.append((socket.identifier,scalar_or_vector(socket.default_value)))
    image=node.image if node.type=='TEX_IMAGE' else None
    image_hash=digest(bytes(image.packed_file.data)) if image and image.packed_file else None
    extras=tuple((key,getattr(node,key)) for key in ['blend_type','data_type','operation','extension','interpolation','projection'] if hasattr(node,key))
    return (node.name,node.bl_idname,image.name if image else None,image_hash,
            image.colorspace_settings.name if image else None,extras,tuple(inputs))


def snapshot():
    objects=[]
    for obj in sorted(bpy.data.objects,key=lambda value:value.name):
        row={'name':obj.name,'type':obj.type,'parent':obj.parent.name if obj.parent else None,
             'matrix':[float(value) for matrix_row in obj.matrix_local for value in matrix_row],
             'data':obj.data.name if obj.data else None}
        if obj.type=='MESH':
            mesh=obj.data
            row['geometry']={'vertices':packed(mesh.vertices,'co',3,'f'),
                             'loops':packed(mesh.loops,'vertex_index',1,'i'),
                             'polygonStarts':packed(mesh.polygons,'loop_start',1,'i'),
                             'polygonSizes':packed(mesh.polygons,'loop_total',1,'i'),
                             'polygonMaterialIndices':packed(mesh.polygons,'material_index',1,'i'),
                             'uv':[(layer.name,packed(layer.data,'uv',2,'f')) for layer in mesh.uv_layers],
                             'shapeKeys':[(key.name,packed(key.data,'co',3,'f')) for key in (mesh.shape_keys.key_blocks if mesh.shape_keys else [])],
                             'materials':[material.name if material else None for material in mesh.materials]}
            row['colors']={attr.name:{'domain':attr.domain,'type':attr.data_type,
                                     'values':[tuple(float(v) for v in item.color) for item in attr.data]}
                           for attr in mesh.color_attributes}
            if obj.name in ['sail_0','sail_1','sail_2']:
                canvas,other,coordinates=set(),set(),{}
                uv=mesh.uv_layers.active
                if uv is None:raise ValueError('sail UV missing')
                for polygon in mesh.polygons:
                    material=mesh.materials[polygon.material_index]
                    for loop_id in polygon.loop_indices:
                        vertex=mesh.loops[loop_id].vertex_index
                        if material and material.name=='canvas':
                            canvas.add(vertex);pair=tuple(float(v) for v in uv.data[loop_id].uv)
                            if vertex in coordinates and coordinates[vertex]!=pair:raise ValueError('canvas point has multiple UVs')
                            coordinates[vertex]=pair
                        else:other.add(vertex)
                if canvas&other:raise ValueError('canvas and another material share a vertex')
                row['canvasVertices']=sorted(canvas)
                row['canvasUV']={vertex:coordinates[vertex] for vertex in canvas}
        objects.append(row)
    materials=[]
    for material in sorted(bpy.data.materials,key=lambda value:value.name):
        if not material.node_tree:
            materials.append({'name':material.name,'nodes':None,'links':None});continue
        materials.append({'name':material.name,'diffuse':tuple(material.diffuse_color),
                          'metallic':material.metallic,'roughness':material.roughness,
                          'nodes':sorted(node_signature(node) for node in material.node_tree.nodes),
                          'links':sorted((link.from_node.name,link.from_socket.name,link.to_node.name,link.to_socket.name) for link in material.node_tree.links)})
    return {'objects':objects,'materials':materials}


def main():
    source,candidate,output=map(Path,sys.argv[sys.argv.index('--')+1:])
    if output.exists():raise ValueError('fresh output required')
    before=[digest(path.read_bytes()) for path in (source,candidate)]
    bpy.ops.wm.open_mainfile(filepath=str(source.resolve()));baseline=snapshot()
    bpy.ops.wm.open_mainfile(filepath=str(candidate.resolve()));current=snapshot()
    errors=[];canvas_counts=[]
    if len(baseline['objects'])!=len(current['objects']):errors.append('object count changed')
    for old,new in zip(baseline['objects'],current['objects']):
        if old['name']!=new['name'] or {k:v for k,v in old.items() if k!='colors'}!={k:v for k,v in new.items() if k!='colors'}:
            errors.append('object transform/geometry/UV/shape key changed: '+old['name']);continue
        if old.get('type')!='MESH':continue
        old_colors,new_colors=old['colors'],new['colors']
        if set(old_colors)!=set(new_colors):errors.append('color attribute names changed: '+old['name']);continue
        for attribute in old_colors:
            a,b=old_colors[attribute],new_colors[attribute]
            if a['domain']!=b['domain'] or a['type']!=b['type'] or len(a['values'])!=len(b['values']):
                errors.append('color attribute schema changed: '+old['name']);continue
            if old['name'] not in ['sail_0','sail_1','sail_2'] or attribute!='SailAge':
                if a['values']!=b['values']:errors.append('non-target color attribute changed: '+old['name']+'/'+attribute)
                continue
            sail=int(old['name'][-1]);canvas=set(old['canvasVertices']);changed=0
            for index,(previous,result) in enumerate(zip(a['values'],b['values'])):
                if index not in canvas:
                    if previous!=result:errors.append('noncanvas point color changed: '+old['name']);break
                    continue
                gltf_u=f32(old['canvasUV'][index][0])
                gltf_v=f32(1.0-old['canvasUV'][index][1])
                expected=tuple(gate.expected_channel(v,gltf_u,gltf_v,sail) for v in previous[:3])+(previous[3],)
                if expected!=result:errors.append('canvas point differs from declared gain: '+old['name']);break
                changed+=previous!=result
            canvas_counts.append({'sail':sail,'vertices':len(canvas),'changedVertices':changed})
    if baseline['materials']!=current['materials']:errors.append('material nodes, links or packed images changed')
    if len(canvas_counts)!=3 or any(row['changedVertices']==0 for row in canvas_counts):errors.append('three changed canvas sets required')
    if [digest(path.read_bytes()) for path in (source,candidate)]!=before:errors.append('source changed during inspection')
    report={'scope':'Blender authoring structure/UV/shape and all point colors; no GPU claim',
            'blender':bpy.app.version_string,'objectsCompared':len(baseline['objects']),
            'materialsCompared':len(baseline['materials']),'baselineSha256':before[0],
            'candidateSha256':before[1],'canvas':canvas_counts,'failures':errors}
    output.parent.mkdir(parents=True,exist_ok=True)
    with output.open('x',encoding='utf8') as stream:json.dump(report,stream,indent=2);stream.write('\n')
    print('R11_BLENDER_AUTHORING_COMPARE objects=%d sails=%d failures=%d'%(len(baseline['objects']),len(canvas_counts),len(errors)))
    if errors:
        for error in errors:print('FAIL:',error)
        raise ValueError('authoring comparison failed')


if __name__=='__main__':main()
