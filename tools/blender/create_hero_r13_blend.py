"""Replace only R9b's packed canvas image in a fresh R13 Blender source."""
import hashlib
import json
import sys
from pathlib import Path
import bpy

png, destination, receipt = map(Path, sys.argv[sys.argv.index('--') + 1:])
expected = '0a25b0a8833eb81e8b03708f113e6e10238fec03c3adeb4b72143333917c8c3b'
if hashlib.sha256(png.read_bytes()).hexdigest() != expected:
    raise RuntimeError('pre-registered PNG differs')
if destination.exists() or receipt.exists():
    raise RuntimeError('fresh destination and receipt required')
material = bpy.data.materials.get('canvas')
if material is None or not material.use_nodes:
    raise RuntimeError('canvas node material missing')
nodes = [node for node in material.node_tree.nodes if node.type == 'TEX_IMAGE']
if len(nodes) != 1 or nodes[0].image is None or nodes[0].image.name != 'cinnabar-hemp-sail.png':
    raise RuntimeError('unexpected R9b canvas image')
node = nodes[0]
links = sorted((link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
               for link in material.node_tree.links)
old = node.image.name
image = bpy.data.images.load(str(png.resolve()), check_existing=False)
image.name = 'weathered-cinnabar-hemp.png'
image.pack()
if image.packed_file is None or hashlib.sha256(bytes(image.packed_file.data)).hexdigest() != expected:
    raise RuntimeError('packed PNG differs')
node.image = image
if links != sorted((link.from_node.name, link.from_socket.name, link.to_node.name, link.to_socket.name)
                   for link in material.node_tree.links):
    raise RuntimeError('canvas node links changed')
destination.parent.mkdir(parents=True, exist_ok=True)
if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(destination.resolve()), compress=True):
    raise RuntimeError('Blender save failed')
data = {'sourceBlend':sys.argv[sys.argv.index('--background')+1], 'candidateBlend':str(destination),
        'blender':bpy.app.version_string, 'material':'canvas', 'node':node.name,
        'sourceImage':old, 'candidateImage':image.name, 'packedImageSha256':expected,
        'nodeLinksUnchanged':True, 'textureColorSpace':image.colorspace_settings.name,
        'scope':'R9b Blender canvas replacement only; no GPU or gameplay claim'}
receipt.parent.mkdir(parents=True, exist_ok=True)
with receipt.open('x', encoding='utf8') as stream: json.dump(data, stream, ensure_ascii=False, indent=2)
print('HERO_R13_BLEND_SAVED material=canvas packed_sha256='+expected, flush=True)
