"""Run inside Blender: save an R7c-derived authoring blend with only canvas art changed."""
import hashlib
import json
import sys
from pathlib import Path
import bpy

args = sys.argv[sys.argv.index('--') + 1:]
if len(args) not in (3, 4):
    raise SystemExit('expected canvas PNG, fresh destination blend, fresh receipt, optional expected SHA')
png, destination, receipt = map(Path, args[:3])
expected = args[3] if len(args) == 4 else 'b4bf04b8f2cd5f5558bf63a2c533e95864d7d1b5c16368db5841540dd6695ce8'
raw = png.read_bytes()
if hashlib.sha256(raw).hexdigest() != expected:
    raise RuntimeError('generated canvas PNG hash mismatch')
if destination.exists() or receipt.exists():
    raise RuntimeError('fresh blend and receipt required')
material = bpy.data.materials.get('canvas')
if material is None or not material.use_nodes:
    raise RuntimeError('unique node-based canvas material required')
images = [node for node in material.node_tree.nodes if node.type == 'TEX_IMAGE']
if len(images) != 1 or images[0].image is None or images[0].image.name != 'antique-hemp-sail.png':
    raise RuntimeError('unexpected original canvas image node')
node = images[0]
links_before = sorted((link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                      for link in material.node_tree.links)
old_name = node.image.name
image = bpy.data.images.load(str(png.resolve()), check_existing=False)
image.name = 'cinnabar-hemp-sail.png'
image.pack()
if image.packed_file is None or hashlib.sha256(bytes(image.packed_file.data)).hexdigest() != expected:
    raise RuntimeError('packed image differs from source PNG')
node.image = image
links_after = sorted((link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                     for link in material.node_tree.links)
if material.name != 'canvas' or links_before != links_after:
    raise RuntimeError('canvas material name or node links changed')
destination.parent.mkdir(parents=True, exist_ok=True)
if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(destination.resolve()), compress=True):
    raise RuntimeError('Blender did not save candidate blend')
document = {'sourceBlend': sys.argv[sys.argv.index('--background') + 1],
            'candidateBlend': str(destination), 'blender': bpy.app.version_string,
            'material': material.name, 'node': node.name, 'sourceImage': old_name,
            'candidateImage': image.name, 'packedImageSha256': expected,
            'nodeLinksUnchanged': True, 'textureColorSpace': image.colorspace_settings.name,
            'scope': 'authored Blender blend image replacement; no GPU or gameplay claim'}
receipt.parent.mkdir(parents=True, exist_ok=True)
with receipt.open('x', encoding='utf8') as stream:
    json.dump(document, stream, ensure_ascii=False, indent=2)
    stream.write('\n')
print('HERO_R9_BLEND_SAVED material=canvas packed_sha256=' + expected)
