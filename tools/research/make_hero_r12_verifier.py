"""Derive an independent exact-payload verifier from the R10a2 audit."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def once(text, before, after):
    if text.count(before)!=1: raise ValueError('missing unique source block: '+before[:80])
    return text.replace(before,after,1)

def main():
    text=(ROOT/'tools/research/verify_hero_r10a2_sail_delta.py').read_text(encoding='utf-8')
    text=text.replace('r10a2','r12').replace('R10A2','R12')
    text=text.replace('hero_r10_sail_formula.py','hero_r12_sail_formula.py')
    text=once(text,'PARAMS=[(10.3,7.7,4.6),(17.,12.,4.05),(9.,6.8,5.35)]',
        'PARAMS=[(10.3,7.4,4.6,.25,.12),(17.,11.8,4.05,.40,.17),(9.,6.8,5.35,.54,.09)]')
    text=once(text,"and author.get('coefficient')==.20 and author.get('sourceUnchanged') is True",
        "and author.get('silhouetteParameters')=={'width':[7.4,11.8,6.8],'k':[.25,.40,.54],'c':[.12,.17,.09]} and author.get('sourceUnchanged') is True")
    text=once(text,'for i,(height,width,base_y) in enumerate(PARAMS):',
        'for i,(height,width,base_y,k,rake) in enumerate(PARAMS):')
    start=text.index('                max_residual=0.')
    end=text.index('                pairs=[',start)
    replacement='''                sail['materials'].append({'name':material,'vertices':len(oldp),'maxPositionDeltaMeters':max_delta})
                if material=='canvas':
                    uv=decode_accessor(base,base_bin,a['attributes']['TEXCOORD_0'])
                    for old,new,(u,v_uv) in zip(oldp,newp,uv,strict=True):
                        v=1-v_uv
                        breadth=width*(1+.10*math.sin(math.pi*v)-k*v*v)
                        z=breadth*(u-.70)-.045*width*v*v
                        y=base_y+height*v+height*rake*(1-u)*v**2.2
                        sail['maxCanvasFormulaErrorMeters']=max(sail['maxCanvasFormulaErrorMeters'],abs(new[2]-z),abs(new[1]-y))
                        sail['maxCanvasYChangeMeters']=max(sail['maxCanvasYChangeMeters'],abs(new[1]-old[1]))
                    if sail['maxCanvasFormulaErrorMeters']>0.00001:
                        raise ValueError('canvas does not match R12 declared surface')
'''
    text=text[:start]+replacement+text[end:]
    text=text.replace('declared shoulder formula','declared R12 surface').replace('0.20 formula','R12 surface formula')
    with (ROOT/'tools/research/verify_hero_r12_sail_delta.py').open('x',encoding='utf-8',newline='\n') as stream:stream.write(text)
    print('HERO_R12_VERIFIER_CREATED')

if __name__=='__main__':main()
