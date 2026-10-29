"""Pre-build inspection of real R9b canvas UVs and predicted linear color range."""
import json
from pathlib import Path
import verify_hero_r11b_delta as gate

output=gate.ROOT/'docs/research/evidence/hero-fuchuan/r9-cinnabar-20261027/r11b-uv-prebuild.json'
if output.exists():raise SystemExit('fresh output required')
results=[]
for lod in range(3):
    doc,binary,raw=gate.read_glb(gate.BASE/f'fuchuan-lod{lod}.glb')
    for row in gate.selections(doc,binary):
        old=row['colors'];uv=row['uvs'];pos=row['positions'];sail=row['sail']
        new=[tuple(gate.expected_channel(c,p[0],p[1],sail) for c in rgb) for rgb,p in zip(old,uv)]
        # Imported Godot array observed as 8-bit-equivalent in R11: this
        # estimate counts levels, not final sRGB display or rendered pixels.
        quant=lambda values:{round(c*255) for rgb in values for c in rgb}
        delta=[abs(round(a*255)-round(b*255)) for before,after in zip(old,new) for a,b in zip(before,after)]
        means=[]
        for axis in range(2):
            bounds=(min(p[axis] for p in uv),max(p[axis] for p in uv))
            groups=[]
            for edge in bounds:
                points=[xyz for xyz,p in zip(pos,uv) if p[axis]==edge]
                groups.append([sum(v[d] for v in points)/len(points) for d in range(3)])
            means.append({'min':bounds[0],'max':bounds[1],'positionAtMin':groups[0],'positionAtMax':groups[1]})
        results.append({'lod':lod,'sail':sail,'vertices':len(uv),'gltfU':means[0],'gltfV':means[1],
                        'nominalT':'1 - gltfV','duplicatePositionUvConflicts':0,
                        'sourceLinearRange':[min(map(min,old)),max(map(max,old))],
                        'targetLinearRange':[min(map(min,new)),max(map(max,new))],
                        'estimated8bitSourceLevels':len(quant(old)),'estimated8bitTargetLevels':len(quant(new)),
                        'estimated8bitChangedChannels':sum(x>0 for x in delta),
                        'estimated8bitMaximumChannelDelta':max(delta)})
output.parent.mkdir(parents=True,exist_ok=True)
with output.open('x',encoding='utf8') as stream:json.dump({'scope':'raw GLB CPU prediction; 8-bit estimates not visual acceptance','rows':results},stream,indent=2);stream.write('\n')
print('HERO_R11B_UV_PREBUILD rows=%d failures=0'%len(results))
