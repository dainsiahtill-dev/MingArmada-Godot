"""Reuse the independent Blender structure audit for R9b -> R13."""
from pathlib import Path
source=Path(__file__).with_name('verify_hero_r9_blend.py')
text=source.read_text(encoding='utf8')
old="changed[0][0][2] != 'antique-hemp-sail.png' or changed[0][1][2] != 'cinnabar-hemp-sail.png'"
new="changed[0][0][2] != 'cinnabar-hemp-sail.png' or changed[0][1][2] != 'weathered-cinnabar-hemp.png'"
if text.count(old)!=1: raise RuntimeError('baseline verifier contract changed')
exec(compile(text.replace(old,new),str(source),'exec'),{'__name__':'__main__'})
