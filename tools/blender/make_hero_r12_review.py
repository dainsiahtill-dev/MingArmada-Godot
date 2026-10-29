"""Freeze existing palette review with explicit CPU device for R12."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def main():
    src=(ROOT/'tools/blender/render_hero_palette_review.py').read_text(encoding='utf-8')
    target="scene.render.engine = 'CYCLES'"
    if src.count(target)!=1:raise ValueError('unexpected review script')
    src=src.replace(target,target+"\nscene.cycles.device = 'CPU'",1)
    src=src.replace("'renderer': 'Cycles24samples'", "'renderer': 'Cycles24samples CPU'")
    with (ROOT/'tools/blender/render_hero_r12_review.py').open('x',encoding='utf-8',newline='\n') as f:f.write(src)
    wrapper=(ROOT/'tools/blender/run_palette_review.py').read_text(encoding='utf-8')
    old='tools/blender/render_hero_palette_review.py'
    if wrapper.count(old)!=1:raise ValueError('unexpected review wrapper')
    wrapper=wrapper.replace(old,'tools/blender/render_hero_r12_review.py')
    with (ROOT/'tools/blender/run_hero_r12_review.py').open('x',encoding='utf-8',newline='\n') as f:f.write(wrapper)
    print('HERO_R12_REVIEW_TOOLS_CREATED')

if __name__=='__main__':main()
