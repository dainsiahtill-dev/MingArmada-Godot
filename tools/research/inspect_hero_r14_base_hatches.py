"""Record actual R7c hatch bounds and hatch-region fitting geometry by material."""
import argparse,hashlib,json
from pathlib import Path
from verify_hero_palette_delta import read_glb,decode_accessor
from verify_hero_r14_coamings import deck

def bounds(values):
    return {'count':len(values),'min':[min(p[i] for p in values) for i in range(3)],'max':[max(p[i] for p in values) for i in range(3)]} if values else {'count':0}
def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():p.error('fresh output required')
    result=[]
    for lod in range(3):
        path=Path(f'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod{lod}.glb');doc,data,digest=read_glb(path)
        node=next(n for n in doc['nodes'] if n.get('name')=='deck_fittings');mesh=doc['meshes'][node['mesh']]
        for center in [-3.2,5.8]:
            name='cargo_hold_'+str(center);hatch=next(n for n in doc['nodes'] if n.get('name')==name);deck_y=deck(0,center)
            vertices=[]
            for primitive in doc['meshes'][hatch['mesh']]['primitives']:vertices.extend(decode_accessor(doc,data,primitive['attributes']['POSITION']))
            fits={}
            for primitive in mesh['primitives']:
                material=doc['materials'][primitive['material']]['name']
                if material not in ('teak','bamboo'):continue
                ps=decode_accessor(doc,data,primitive['attributes']['POSITION'])
                selected=[q for q in ps if abs(q[0])<=.76 and abs(q[2]-center)<=.96 and deck_y+.24<=q[1]<=deck_y+.35]
                fits[material]=bounds(selected)
            result.append({'lod':lod,'centerZ':center,'modelSha256':digest,'baseDeckY':deck_y,'cargoHold':bounds(vertices),'hatchRegionFittings':fits,'regionFilter':'abs(x)<=.76; abs(z-center)<=.96; deckY+.24<=y<=deckY+.35; may contain other merged geometry'})
    report={'rows':result,'toolSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'scope':'Imported GLB vertex bounds and filtered merged fitting vertices; this does not assign names to merged pieces or measure dynamic clearance.'}
    a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    for row in result:print('R7C_HATCH',row['lod'],row['centerZ'],'deck=',row['baseDeckY'],'hatch=',row['cargoHold'],'fittings=',row['hatchRegionFittings'])
if __name__=='__main__':main()
