"""R10a2 independent authoring: regenerate only three sails inside the R7c blend.

Each candidate GLB is a Blender authoring intermediate. Its non-sail LOD0
content is deliberately not a shippable lower LOD. An independent strict packer
must preserve the corresponding original R7c GLB for every non-sail byte.
Run through --launch so the actual Blender process is captured and checked.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
import math
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend'
BLENDER = Path('C:/Tools/blender-5.4.0-alpha+main.fbe82a461016-windows.amd64-release/blender.exe')
ORIGINAL = ROOT / 'tools/blender/build_hero_fuchuan_v3.py'
BASE = ROOT / 'tools/blender/build_hero_fuchuan.py'
FORMULA = ROOT / 'tools/blender/hero_r12_sail_formula.py'
R7C = ROOT / 'assets/models/hero_fuchuan_v3_r7c'
EXPECTED = ['ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3',
            'b87af112855cb6883faf97ec02a5eeb5fd61a5d504f204d3b3a573e73735d02d',
            'db9f01b8968f66f2a1c27c689e9a9e0cdd7f03ea27d86a9b6f2bb911872e461a',
            '16aa79cb89074879354d82402540f478e9ad5279085d2c53d7f92d579aa2291d']
PARAMS = [(0, 10.3, 7.4, 4.6), (1, 17., 11.8, 4.05), (2, 9., 6.8, 5.35)]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def guarded_sources():
    paths = [SOURCE] + [R7C / f'fuchuan-lod{i}.glb' for i in range(3)]
    if [sha(p) for p in paths] != EXPECTED:
        raise RuntimeError('R7c input differs from pre-registered baseline')
    paths += [ORIGINAL, BASE, FORMULA, Path(__file__).resolve()]
    return {str(p.relative_to(ROOT)): sha(p) for p in paths}


def build_sail_function(namespace):
    """Keep the original artist script, replacing its two width expressions only."""
    tree = ast.parse(ORIGINAL.read_text(encoding='utf-8'))
    function = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == 'sail')
    expected = ast.dump(ast.parse('width*(1+.10*math.sin(math.pi*v)-.40*v*v)', mode='eval').body,
                        include_attributes=False)

    class Width(ast.NodeTransformer):
        def __init__(self): self.count = 0
        def visit_Assign(self, node):
            node = self.generic_visit(node)
            if len(node.targets) == 1 and isinstance(node.targets[0], ast.Name) and node.targets[0].id == 'breadth':
                if ast.dump(node.value, include_attributes=False) != expected:
                    raise RuntimeError('original sail width expression changed')
                node.value = ast.Call(func=ast.Name(id='r10_breadth', ctx=ast.Load()),
                                      args=[ast.Name(id='v',ctx=ast.Load()), ast.Name(id='width',ctx=ast.Load())], keywords=[])
                self.count += 1
            return node
    transform = Width()
    function = transform.visit(function)
    class Rake(ast.NodeTransformer):
        def __init__(self): self.count = 0
        def visit_Constant(self, node):
            if node.value == .15:
                self.count += 1
                return ast.Call(func=ast.Name(id='r12_rake',ctx=ast.Load()),args=[ast.Name(id='width',ctx=ast.Load())],keywords=[])
            return node
    rake=Rake(); function=rake.visit(function)
    if rake.count != 1: raise RuntimeError('expected one sail inverse rake constant')
    if transform.count != 2: raise RuntimeError('expected precisely lashing and inverse width expressions')
    module = ast.fix_missing_locations(ast.Module(body=[function], type_ignores=[]))
    exec(compile(module, str(ORIGINAL), 'exec'), namespace)
    return namespace['sail']


def author(lod, raw, blend, receipt):
    import bpy
    if raw.exists() or receipt.exists() or (blend and blend.exists()):
        raise RuntimeError('fresh raw GLB, Blend and receipt required')
    before = guarded_sources()
    if Path(bpy.data.filepath).resolve() != SOURCE.resolve():
        raise RuntimeError('expected the real pre-registered R7c authoring blend')
    # The original helper's module initialization only confirms existing asset
    # directories. We never call its setup, build, main or preview functions.
    if '--vintage' not in sys.argv: sys.argv.append('--vintage')
    spec = importlib.util.spec_from_file_location('r10_original_base', BASE)
    original = importlib.util.module_from_spec(spec); spec.loader.exec_module(original)
    original.LOD = lod
    original.OBJECTS = []
    for name in ('canvas','bamboo','canvas_seam','hemp'):
        material = bpy.data.materials.get(name)
        if material is None: raise RuntimeError('R7c material missing: ' + name)
        original.MATS[name] = material
    spec = importlib.util.spec_from_file_location('r10_formula', FORMULA)
    formula = importlib.util.module_from_spec(spec); spec.loader.exec_module(formula)
    env = {'math':math,'B':original,
           'r10_breadth':formula.breadth, 'r12_rake':formula.rake,
           'sail_surface':formula.surface}
    sail = build_sail_function(env)
    root = bpy.data.objects.get('HeroFuchuan')
    if root is None: raise RuntimeError('R7c root absent')
    previous = {obj.name:(obj.type,obj.parent.name if obj.parent else None,
                          tuple(round(v,9) for row in obj.matrix_local for v in row))
                for obj in bpy.context.scene.objects if not obj.name.startswith('sail_')}
    changes = []
    for index, height, width, base in PARAMS:
        name = f'sail_{index}'
        old = bpy.data.objects.get(name); mast = bpy.data.objects.get(f'mast_{index}')
        if old is None or mast is None or old.parent != mast or old.type != 'MESH':
            raise RuntimeError('original sail/mast hierarchy missing: ' + name)
        old_vertices = len(old.data.vertices)
        old.name = 'r10-old-' + name
        new = sail(mast,index,height,width,base)
        if new.name != name or new.parent != mast:
            raise RuntimeError('candidate sail name or parent differs: ' + name)
        if [key.name for key in new.data.shape_keys.key_blocks] != ['Basis','furl','inflate']:
            raise RuntimeError('shape key contract differs: ' + name)
        bpy.data.objects.remove(old, do_unlink=True)
        changes.append({'name':name,'parent':mast.name,'oldLOD0Vertices':old_vertices,
                        'newVertices':len(new.data.vertices),
                        'materials':[x.name for x in new.data.materials],
                        'shapeKeys':[k.name for k in new.data.shape_keys.key_blocks]})
    after_nodes = {obj.name:(obj.type,obj.parent.name if obj.parent else None,
                             tuple(round(v,9) for row in obj.matrix_local for v in row))
                   for obj in bpy.context.scene.objects if not obj.name.startswith('sail_')}
    if previous != after_nodes: raise RuntimeError('non-sail author node, parent or local matrix changed')
    raw.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='DESELECT')
    for obj in [root] + list(root.children_recursive):
        if obj.type in {'MESH','CURVE','EMPTY'}: obj.select_set(True)
    status = bpy.ops.export_scene.gltf(filepath=str(raw.resolve()),export_format='GLB',use_selection=True,
                                       export_apply=True,export_extras=True,export_yup=True,
                                       export_animations=False,export_morph=True)
    if 'FINISHED' not in status or not raw.is_file(): raise RuntimeError('candidate raw export failed')
    if blend is not None:
        blend.parent.mkdir(parents=True, exist_ok=True)
        if 'FINISHED' not in bpy.ops.wm.save_as_mainfile(filepath=str(blend.resolve()),compress=True):
            raise RuntimeError('candidate source Blend save failed')
    if before != guarded_sources(): raise RuntimeError('pre-registered inputs changed during authoring')
    data={'scope':'Blender-authored sail-only candidate; raw GLB non-sail components are LOD0, not shippable',
          'lod':lod,'silhouetteParameters':{'width':[7.4,11.8,6.8],'k':[.25,.40,.54],'c':[.12,.17,.09]},'sourceBlend':str(SOURCE.relative_to(ROOT)),
          'baselineSources':before,'sourceUnchanged':True,'candidateRaw':str(raw.relative_to(ROOT)),
          'candidateRawSha256':sha(raw),'candidateBlend':str(blend.relative_to(ROOT)) if blend else None,
          'candidateBlendSha256':sha(blend) if blend else None,'sails':changes,
          'blenderVersion':bpy.app.version_string,'authoringUtc':datetime.now(timezone.utc).isoformat(),
          'limitations':['No production integration','No GPU, continuity, visual or performance acceptance']}
    receipt.parent.mkdir(parents=True, exist_ok=True)
    with receipt.open('x',encoding='utf-8') as stream: json.dump(data,stream,indent=2,ensure_ascii=False)
    print('HERO_R12_AUTHOR_LOD_OK lod='+str(lod), flush=True)


def launch(run):
    if not run.startswith('r12-') or not all(c in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in run):
        raise ValueError('safe fresh r12-* run id required')
    evidence=ROOT/'docs/production/hero-fuchuan-2026-10-26-art'/run
    work=ROOT/'Temp/hero-fuchuan-r12'/run
    blend=ROOT/'assets/production/hero-fuchuan-blender'/f'hero-fuchuan-v3-{run}.blend'
    if evidence.exists() or work.exists() or blend.exists(): raise RuntimeError('fresh run paths required')
    guarded_sources(); evidence.mkdir(parents=True); work.mkdir(parents=True)
    for lod in (0,1,2):
        raw=work/f'fuchuan-lod{lod}.glb'; receipt=evidence/f'blender-lod{lod}.json'
        args=[str(BLENDER),'--background',str(SOURCE),'--python-exit-code','1','--python',str(Path(__file__).resolve()),'--',
              '--author','--lod',str(lod),'--raw',str(raw),'--receipt',str(receipt)]
        if lod==0: args += ['--blend',str(blend)]
        start=datetime.now(timezone.utc).isoformat()
        result=subprocess.run(args,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,check=False)
        log=evidence/f'blender-lod{lod}.log';log.write_bytes(result.stdout)
        marker=f'HERO_R12_AUTHOR_LOD_OK lod={lod}'.encode()
        success=(result.returncode==0 and result.stdout.count(marker)==1 and receipt.is_file())
        process={'command':args,'startedUTC':start,'finishedUTC':datetime.now(timezone.utc).isoformat(),
                 'exitCode':result.returncode,'markerCount':result.stdout.count(marker),'success':success,
                 'logSha256':sha(log),'blenderSha256':sha(BLENDER),'scriptSha256':sha(Path(__file__).resolve())}
        with (evidence/f'blender-lod{lod}-process.json').open('x',encoding='utf-8') as s:json.dump(process,s,indent=2)
        print(result.stdout.decode('utf-8',errors='replace')[-2500:],flush=True)
        if not success: raise RuntimeError('Blender candidate authoring failed for LOD '+str(lod))
    print('HERO_R12_AUTHOR_COMPLETE all_lods=3',flush=True)


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--launch',action='store_true');parser.add_argument('--run')
    parser.add_argument('--author',action='store_true');parser.add_argument('--lod',type=int)
    parser.add_argument('--raw',type=Path);parser.add_argument('--blend',type=Path);parser.add_argument('--receipt',type=Path)
    args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else sys.argv[1:])
    if args.launch: launch(args.run)
    elif args.author and args.lod in (0,1,2) and args.raw and args.receipt: author(args.lod,args.raw,args.blend,args.receipt)
    else: parser.error('launch or explicit author arguments required')


if __name__=='__main__': main()
