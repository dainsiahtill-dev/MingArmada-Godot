"""Blender-only visual asset experiment. External appearance, not a working weapon."""

import bpy
import json
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'assets/production/cannons/gun-light-muzzle/prototypes/blender-v1'
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'textures').mkdir(exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.render.engine = 'CYCLES'
scene.cycles.device = 'CPU'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.resolution_x = 1280
scene.render.resolution_y = 960
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new('Studio_world')
scene.world.use_nodes = True
scene.world.node_tree.nodes['Background'].inputs['Color'].default_value = (0.32, 0.36, 0.39, 1)
scene.world.node_tree.nodes['Background'].inputs['Strength'].default_value = 0.45
scene.view_settings.view_transform = 'AgX'


def texture(name, metal=False):
    size = 512
    image = bpy.data.images.new(name, width=size, height=size)
    rng = random.Random(51 if metal else 24)
    pixels = []
    for y in range(size):
        for x in range(size):
            u, v = x / size, y / size
            noise = rng.random() - 0.5
            if metal:
                value = 0.5 + 0.13 * noise + 0.08 * math.sin(u * 110 + math.sin(v * 29))
                color = (0.085 + value * 0.07, 0.097 + value * 0.075, 0.107 + value * 0.08)
            else:
                grain = math.sin(u * 270 + math.sin(v * 16) * 3 + math.sin(v * 47) * 0.6)
                grain2 = math.sin(u * 73 + math.sin(v * 8) * 2)
                value = 0.075 * grain + 0.055 * grain2 + noise * 0.09
                color = (0.40 + value, 0.245 + value * 0.7, 0.12 + value * 0.45)
            pixels.extend((*color, 1))
    image.pixels.foreach_set(pixels)
    image.filepath_raw = str(OUT / 'textures' / f'{name}.png')
    image.file_format = 'PNG'
    image.save()
    image.pack()
    return image


def material(name, color, roughness, metallic=0, image=None):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    mat.diffuse_color = (*color, 1)
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (*color, 1)
    bsdf.inputs['Roughness'].default_value = roughness
    bsdf.inputs['Metallic'].default_value = metallic
    if image:
        node = mat.node_tree.nodes.new('ShaderNodeTexImage')
        node.image = image
        mat.node_tree.links.new(node.outputs['Color'], bsdf.inputs['Base Color'])
    return mat


oak = material('Oak_game_PBR', (0.40, 0.245, 0.12), 0.75, image=texture('oak_albedo'))
iron = material('Iron_game_PBR', (0.13, 0.15, 0.17), 0.42, 0.85, texture('iron_albedo', True))
edge_iron = material('Iron_edges', (0.085, 0.10, 0.12), 0.38, 0.8)
recess = material('Muzzle_visual_recess', (0.012, 0.015, 0.018), 0.95, 0.1)
floor_mat = material('Studio_floor', (0.19, 0.215, 0.23), 0.9)


def move_to(obj, collection, parent=None):
    for old in list(obj.users_collection):
        old.objects.unlink(obj)
    collection.objects.link(obj)
    if parent:
        obj.parent = parent
    return obj


def empty(name, loc, collection, parent=None):
    obj = bpy.data.objects.new(name, None)
    collection.objects.link(obj)
    obj.location = loc
    obj.empty_display_type = 'PLAIN_AXES'
    obj.empty_display_size = 0.12
    obj.parent = parent
    return obj


def finish(obj, name, mat, collection, parent, bevel=0, smooth=False):
    obj.name = name
    move_to(obj, collection, parent)
    obj.data.materials.append(mat)
    if smooth:
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    if bevel:
        modifier = obj.modifiers.new('Edge_softening', 'BEVEL')
        modifier.width = bevel
        modifier.segments = 2
    return obj


def cube(name, loc, scale, mat, collection, parent, bevel=0.012):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    obj = bpy.context.object
    obj.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(obj, name, mat, collection, parent, bevel)


def cylinder(name, loc, radius, depth, mat, collection, parent, vertices=32, axis='Y'):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc)
    obj = bpy.context.object
    if axis == 'Y':
        obj.rotation_euler.x = math.pi / 2
    elif axis == 'X':
        obj.rotation_euler.y = math.pi / 2
    return finish(obj, name, mat, collection, parent, 0.008 if vertices >= 24 else 0, True)


def lathe(name, profile, segments, collection, parent):
    vertices, faces = [], []
    for x, radius in profile:
        for j in range(segments):
            angle = math.tau * j / segments
            vertices.append((x, radius * math.cos(angle), radius * math.sin(angle)))
    for i in range(len(profile) - 1):
        for j in range(segments):
            a = i * segments + j
            b = i * segments + (j + 1) % segments
            faces.append((a, b, b + segments, a + segments))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(iron)
    mesh.materials.append(recess)
    uv = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        polygon.use_smooth = True
        section = polygon.index // segments
        if section >= len(profile) - 3:
            polygon.material_index = 1
        for k, loop in enumerate(polygon.loop_indices):
            ring = section + (1 if k >= 2 else 0)
            circle = (polygon.index % segments + (1 if k in (1, 2) else 0)) / segments
            uv.data[loop].uv = (circle, ring / (len(profile) - 1))
    return obj


def cheek(name, y, collection, parent, quality):
    outline = [(-0.95, .32), (.79, .32), (.79, .62), (.39, .87), (-.38, .87), (-.65, .68), (-.95, .68)]
    vertices = [(x, y + dy, z) for dy in (-.09, .09) for x, z in outline]
    n = len(outline)
    faces = [tuple(reversed(range(n))), tuple(range(n, n * 2))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    collection.objects.link(obj)
    obj.parent = parent
    mesh.materials.append(oak)
    uv = mesh.uv_layers.new(name='UVMap')
    for polygon in mesh.polygons:
        for li in polygon.loop_indices:
            vertex = mesh.vertices[mesh.loops[li].vertex_index].co
            uv.data[li].uv = ((vertex.z - .3) * 1.5, (vertex.x + 1) / 2)
    if quality < 2:
        bevel = obj.modifiers.new('Worn_wood_edges', 'BEVEL')
        bevel.width = .012
        bevel.segments = 2 if quality == 0 else 1
    return obj


def make_asset(lod):
    collection = bpy.data.collections.new(f'LightCannon_LOD{lod}')
    scene.collection.children.link(collection)
    root_obj = empty(f'light_cannon_lod{lod}', (0, 0, 0), collection)
    root_obj['asset_id'] = 'gun-light-muzzle'
    root_obj['carriage_asset_id'] = 'gun-deck-carriage'
    root_obj['status'] = 'prototype-not-historical-final'
    root_obj['lod'] = lod
    frame = empty('Carriage', (0, 0, 0), collection, root_obj)
    pivot = empty('BarrelPivot', (0, 0, .96), collection, root_obj)
    pivot.rotation_euler.y = math.radians(-3)
    radial = (64, 32, 16)[lod]
    profile = [(-1.05,.025),(-1.04,.09),(-.97,.13),(-.90,.13),(-.87,.10),(-.83,.11),(-.79,.21),(-.70,.26),(-.64,.27),(-.60,.285),(-.54,.285),(-.50,.263),(-.22,.247),(-.19,.265),(-.14,.265),(-.11,.24),(.31,.206),(.35,.223),(.40,.223),(.43,.200),(.92,.166),(.95,.185),(1.00,.185),(1.03,.162),(1.27,.159),(1.31,.195),(1.38,.20),(1.40,.18),(1.40,.103),(1.29,.101),(1.29,.002)]
    if lod == 2:
        profile = [profile[i] for i in (0,2,5,7,11,15,19,23,24,26,27,28,29,30)]
    lathe('Barrel', profile, radial, collection, pivot)
    cylinder('Trunnions', (0,0,0), .075, .96, iron, collection, pivot, radial)
    empty('Muzzle', (1.40,0,0), collection, pivot)
    empty('DeckAttachment', (0,0,0), collection, root_obj)
    cheek('Cheek_port', -.30, collection, frame, lod)
    cheek('Cheek_starboard', .30, collection, frame, lod)
    for x in (-.71, .49):
        cube(f'Crossbeam_{x}', (x,0,.39), (.19,.80,.19), oak, collection, frame, .012 if lod < 2 else 0)
        cylinder(f'Axle_{x}', (x,0,.235), .05, 1.24, edge_iron, collection, frame, radial // 2)
        for side in (-1,1):
            y = side * .51
            cylinder(f'Wheel_{x}_{side}', (x,y,.235), .235, .14, oak, collection, frame, radial)
            cylinder(f'Rim_{x}_{side}', (x,y,.235), .241, .052, edge_iron, collection, frame, radial)
            cylinder(f'Hub_{x}_{side}', (x,y + side*.085,.235), .075, .06, edge_iron, collection, frame, radial//2)
            if lod < 2:
                for i in range(4):
                    a = i * math.pi/2 + math.pi/4
                    cylinder(f'Wheel_pin_{x}_{side}_{i}', (x + .15*math.cos(a), y + side*.073, .235 + .15*math.sin(a)), .012, .012, edge_iron, collection, frame, 8)
    if lod < 2:
        for y in (-.402,.402):
            for x in (-.68,.48):
                cube(f'Cheek_strap_{x}_{y}', (x,y,.505), (.075,.018,.29), edge_iron, collection, frame, .006)
                for z in (.42,.59):
                    cylinder(f'Fastener_{x}_{y}_{z}', (x,y + math.copysign(.015,y),z), .025,.016,edge_iron,collection,frame,12)
            cube(f'Trunnion_seat_{y}', (0,y*.80,.88), (.22,.16,.075), edge_iron, collection, frame, .008)
    return collection, root_obj


def stats(collection):
    triangles = vertices = 0
    deps = bpy.context.evaluated_depsgraph_get()
    for obj in collection.objects:
        if obj.type != 'MESH':
            continue
        evaluated = obj.evaluated_get(deps)
        mesh = evaluated.to_mesh()
        mesh.calc_loop_triangles()
        triangles += len(mesh.loop_triangles)
        vertices += len(mesh.vertices)
        evaluated.to_mesh_clear()
    return {'triangles': triangles, 'vertices': vertices, 'meshObjects': sum(o.type == 'MESH' for o in collection.objects)}


lods = []
for level in range(3):
    collection, root_obj = make_asset(level)
    bpy.context.view_layer.update()
    metrics = stats(collection)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in collection.objects:
        obj.select_set(True)
    path = OUT / f'light-cannon-lod{level}.glb'
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', use_selection=True, export_apply=True, export_extras=True, export_yup=True, export_animations=False)
    lods.append({'lod': level, 'file': path.name, **metrics})
    collection.hide_render = level != 0
    collection.hide_viewport = level != 0

studio = bpy.data.collections.new('Preview_studio_not_exported')
scene.collection.children.link(studio)
cube('Ground', (0,0,-.065), (200,200,.08), floor_mat, studio, None, 0)


def light(name, loc, power, size, color):
    data = bpy.data.lights.new(name, 'AREA')
    data.energy, data.shape, data.size, data.color = power, 'DISK', size, color
    obj = bpy.data.objects.new(name, data)
    studio.objects.link(obj)
    obj.location = loc
    obj.rotation_euler = (Vector((0,0,.7))-obj.location).to_track_quat('-Z','Y').to_euler()


light('Key', (1,-3,5), 650, 4.0, (1,.88,.74))
light('Fill', (-2,2,3), 450, 3.0, (.73,.85,1))
light('Rim', (3,3,4), 750, 2.5, (1,.95,.85))
camera_data = bpy.data.cameras.new('Camera')
camera = bpy.data.objects.new('Camera', camera_data)
studio.objects.link(camera)
scene.camera = camera
camera_data.type = 'ORTHO'
camera_data.ortho_scale = 3.9
camera.location = (3.7,-5.8,3.0)
camera.rotation_euler = (Vector((.1,0,.65))-camera.location).to_track_quat('-Z','Y').to_euler()
scene.render.filepath = str(OUT / 'preview-hero.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT / 'light-cannon-prototype.blend'))
bpy.ops.render.render(write_still=True)
camera.location = (0,-6,1.0)
camera.rotation_euler = (Vector((.1,0,.6))-camera.location).to_track_quat('-Z','Y').to_euler()
camera_data.ortho_scale = 3.4
scene.render.filepath = str(OUT / 'preview-side.png')
bpy.ops.render.render(write_still=True)
report = {
    'status': 'prototype', 'date': '2026-10-24', 'blender': bpy.app.version_string,
    'source': str(Path(__file__).relative_to(ROOT)), 'assetIds': ['gun-light-muzzle','gun-deck-carriage'],
    'reference': 'assets/production/cannons/gun-light-muzzle/concept/original-v1.png',
    'lods': lods, 'materials': ['Oak_game_PBR','Iron_game_PBR','Iron_edges','Muzzle_visual_recess'],
    'textures': ['textures/oak_albedo.png','textures/iron_albedo.png'],
    'boundsPolicy': 'Fictional game proportions; historical scale and engine socket alignment not yet approved.',
    'limitations': ['External visual model only.', 'No internal mechanism or manufacturing specification.', 'Not yet imported or accepted in Godot.', 'No final historical or commercial-art acceptance.'],
}
(OUT / 'prototype.json').write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8')
print('CANNON_PROTOTYPE_COMPLETE '+json.dumps(report))
