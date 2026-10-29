"""Render the actual saved palette Blend; does not save/alter its source."""
import bpy
import hashlib
import json
import sys
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
OUTPUT = ROOT / next(a.split('=', 1)[1] for a in sys.argv if a.startswith('--review-output='))
OUTPUT.resolve().relative_to(ROOT)
if OUTPUT.exists():
    raise RuntimeError('fresh review output required')
OUTPUT.mkdir(parents=True)
SOURCE = Path(bpy.data.filepath)
source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 24
scene.render.resolution_x = 1600
scene.render.resolution_y = 1000
scene.render.resolution_percentage = 100
scene.view_settings.view_transform = 'AgX'
world = bpy.data.worlds.new('Palette review world')
world.use_nodes = True
world.node_tree.nodes.get('Background').inputs['Color'].default_value = (.28, .34, .42, 1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value = .5
scene.world = world
bpy.ops.mesh.primitive_plane_add(size=200, location=(0, 0, -2.4))
floor = bpy.context.object
floor.name = 'Review ground only'
mat = bpy.data.materials.new('Review neutral ground')
mat.diffuse_color = (.07, .09, .10, 1)
floor.data.materials.append(mat)


def point(p):
    return Vector((p[0], -p[2], p[1]))


for name, pos, power in [('Warm key', (15, 32, 15), 6500), ('Sky fill', (-16, 24, 4), 4500), ('Rim', (6, 26, -23), 7000)]:
    data = bpy.data.lights.new(name, 'AREA')
    data.energy = power
    data.shape = 'DISK'
    data.size = 18
    light = bpy.data.objects.new(name, data)
    scene.collection.objects.link(light)
    light.location = point(pos)
    light.rotation_euler = (point((0, 8, 0)) - light.location).to_track_quat('-Z', 'Y').to_euler()
data = bpy.data.cameras.new('Palette review camera')
camera = bpy.data.objects.new('Palette review camera', data)
scene.collection.objects.link(camera)
data.type = 'ORTHO'
scene.camera = camera
images = []
for name, eye, target, scale in [('hero', (34, 22, 39), (0, 10, 0), 60), ('stern', (-31, 19, -36), (0, 10, 0), 58), ('hull-detail', (27, 7, 1), (0, 2, 1), 24)]:
    camera.location = point(eye)
    camera.rotation_euler = (point(target) - camera.location).to_track_quat('-Z', 'Y').to_euler()
    data.ortho_scale = scale
    path = OUTPUT / (name + '.png')
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)
    images.append({'path': path.relative_to(ROOT).as_posix(), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(), 'eye': eye, 'target': target, 'orthoScale': scale})
assert source_hash == hashlib.sha256(SOURCE.read_bytes()).hexdigest()
(OUTPUT / 'BLENDER_REVIEW.json').write_text(json.dumps({'source': SOURCE.relative_to(ROOT).as_posix(), 'sourceSHA256': source_hash, 'sourceUnchanged': True, 'blender': bpy.app.version_string, 'renderer': 'Cycles24samples', 'scope': 'Actual saved Blender asset; fixed authoring review lights, not formal game lighting or gameplay', 'images': images}, indent=2) + '\n', encoding='utf-8')
print('HERO_PALETTE_BLENDER_REVIEW_OK images=3 sourceUnchanged=true')
