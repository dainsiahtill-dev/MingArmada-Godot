"""Derive R12 author/packer from frozen R10a2 tools without altering them."""
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]

def replace_once(source, before, after):
    if source.count(before)!=1:
        raise ValueError('expected unique source pattern: '+before[:90])
    return source.replace(before,after,1)

def write_new(path, text):
    with (ROOT/path).open('x',encoding='utf-8',newline='\n') as stream: stream.write(text)

def main():
    author=(ROOT/'tools/blender/build_hero_fuchuan_r10a2.py').read_text(encoding='utf-8')
    author=author.replace('r10a2','r12').replace('R10A2','R12')
    author=author.replace('hero_r10_sail_formula.py','hero_r12_sail_formula.py')
    author=replace_once(author,'PARAMS = [(0, 10.3, 7.7, 4.6), (1, 17., 12., 4.05), (2, 9., 6.8, 5.35)]',
        'PARAMS = [(0, 10.3, 7.4, 4.6), (1, 17., 11.8, 4.05), (2, 9., 6.8, 5.35)]')
    author=replace_once(author,
        "'r10_breadth':lambda v,w:formula.breadth(v,w,.20),\n           'sail_surface':lambda u,v,h,w,b:formula.surface(u,v,h,w,b,.20)",
        "'r10_breadth':formula.breadth, 'r12_rake':formula.rake,\n           'sail_surface':formula.surface")
    author=replace_once(author,"    function = transform.visit(function)\n    if transform.count != 2:",
        "    function = transform.visit(function)\n    class Rake(ast.NodeTransformer):\n        def __init__(self): self.count = 0\n        def visit_Constant(self, node):\n            if node.value == .15:\n                self.count += 1\n                return ast.Call(func=ast.Name(id='r12_rake',ctx=ast.Load()),args=[ast.Name(id='width',ctx=ast.Load())],keywords=[])\n            return node\n    rake=Rake(); function=rake.visit(function)\n    if rake.count != 1: raise RuntimeError('expected one sail inverse rake constant')\n    if transform.count != 2:")
    author=replace_once(author,"'coefficient':.20", "'silhouetteParameters':{'width':[7.4,11.8,6.8],'k':[.25,.40,.54],'c':[.12,.17,.09]}")
    write_new('tools/blender/build_hero_fuchuan_r12.py',author)
    pack=(ROOT/'tools/blender/pack_hero_r10a2_sail.py').read_text(encoding='utf-8')
    pack=pack.replace('r10a2','r12').replace('R10A2','R12')
    pack=replace_once(pack,"'coefficient':.20", "'silhouetteParameters':{'width':[7.4,11.8,6.8],'k':[.25,.40,.54],'c':[.12,.17,.09]}")
    write_new('tools/blender/pack_hero_r12_sail.py',pack)
    print('HERO_R12_TOOLS_CREATED')

if __name__=='__main__': main()
