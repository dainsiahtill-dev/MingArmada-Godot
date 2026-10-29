"""Strictly transfer Blender-authored R10 sail P/N and shape keys onto R7c GLBs.

The Blender intermediate uses R7c LOD0 for non-sail meshes at all three
resolutions. Never ship that intermediate: clone each corresponding original
LOD's BIN and permit only the three sail meshes' matching dense P/N payloads.
"""
import argparse
import copy
import hashlib
import json
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

from transfer_hero_shadow_geometry import accessor_references, dense, encode, frame_chain, identity, read_checked, schema
from verify_hero_palette_delta import decode_accessor

ROOT = Path(__file__).resolve().parents[2]
EXPECTED_MATERIALS = ['canvas','bamboo','canvas_seam','hemp']
EXPECTED_ATTRIBUTES = {'POSITION','NORMAL','TEXCOORD_0','COLOR_0'}


def sha(data): return hashlib.sha256(data).hexdigest()


def sail_primitives(document, name):
    nodes=[n for n in document['nodes'] if n.get('name')==name]
    if len(nodes)!=1 or 'mesh' not in nodes[0]: raise ValueError('unique target sail node required: '+name)
    index=nodes[0]['mesh']
    if sum(node.get('mesh')==index for node in document['nodes'])!=1: raise ValueError('unique target mesh required: '+name)
    mesh=document['meshes'][index]
    if mesh.get('extras',{}).get('targetNames') != ['furl','inflate']:
        raise ValueError('target shape-key order differs: '+name)
    primitives=mesh['primitives']
    names=[document['materials'][p['material']]['name'] for p in primitives]
    if names!=EXPECTED_MATERIALS: raise ValueError('target material order differs: '+name)
    return primitives


def pack_documents(base, base_bin, raw, raw_bin):
    identity(base,'hero-fuchuan-v3-r7c');identity(raw,'hero-fuchuan-v3-r7c')
    output=copy.deepcopy(base);identity(output,'hero-fuchuan-v3-r7c')['extras']['authored_asset']='hero-fuchuan-v3-r12'
    binary=bytearray(base_bin); changes=[]
    for name in ('sail_0','sail_1','sail_2'):
        original=next(n for n in base['nodes'] if n.get('name')==name)
        authored=next(n for n in raw['nodes'] if n.get('name')==name)
        if frame_chain(base,original)!=frame_chain(raw,authored):raise ValueError('target frame chain differs: '+name)
        if {k:v for k,v in original.items() if k!='mesh'} != {k:v for k,v in authored.items() if k!='mesh'}:
            raise ValueError('target node metadata differs: '+name)
        for p,q in zip(sail_primitives(base,name),sail_primitives(raw,name),strict=True):
            material=base['materials'][p['material']]['name']
            if p.get('mode',4)!=4 or q.get('mode',4)!=4 or p.get('extensions') or q.get('extensions'):
                raise ValueError('only indexed triangle sail primitives supported')
            if set(p['attributes'])!=EXPECTED_ATTRIBUTES or set(q['attributes'])!=EXPECTED_ATTRIBUTES:
                raise ValueError('unexpected target attribute schema: '+name+'/'+material)
            if len(p.get('targets',[]))!=2 or len(q.get('targets',[]))!=2:
                raise ValueError('two targets required: '+name+'/'+material)
            pa,_,pr,pv=dense(base,base_bin,p['indices']);qa,_,qr,qv=dense(raw,raw_bin,q['indices'])
            if schema(pa)!=schema(qa) or pr!=qr or pv!=qv or len(pv)%3:
                raise ValueError('triangle indices differ: '+name+'/'+material)
            vertex_count=base['accessors'][p['attributes']['POSITION']]['count']
            if any(index[0]>=vertex_count for index in pv):raise ValueError('triangle indices out of bounds')
            for attr in ('TEXCOORD_0','COLOR_0'):
                aa,_,ar,av=dense(base,base_bin,p['attributes'][attr]);ba,_,br,bv=dense(raw,raw_bin,q['attributes'][attr])
                if schema(aa)!=schema(ba) or ar!=br or av!=bv:
                    raise ValueError('unchanged target attribute differs: '+name+'/'+material+'/'+attr)
            lists=[(None,p['attributes'],q['attributes'])]+[(i,p['targets'][i],q['targets'][i]) for i in range(2)]
            for target,a,b in lists:
                if target is not None and (set(a)!={'POSITION','NORMAL'} or set(b)!={'POSITION','NORMAL'}):
                    raise ValueError('unsupported shape-key attributes')
                for attr in ('POSITION','NORMAL'):
                    ia,ib=a[attr],b[attr]
                    aa,ba=base['accessors'][ia],raw['accessors'][ib]
                    if schema(aa)!=schema(ba) or aa['type']!='VEC3' or aa['componentType']!=5126 or aa['count']!=vertex_count:
                        raise ValueError('target P/N schema or count differs')
                    if list(accessor_references(base)).count(ia)!=1:
                        raise ValueError('target accessor must have one unique reference')
                    old_values=decode_accessor(base,base_bin,ia)
                    new_values=decode_accessor(raw,raw_bin,ib)
                    if not all(math.isfinite(x) for v in new_values for x in v):raise ValueError('non-finite target P/N')
                    old=b''.join(struct.pack('<fff',*row) for row in old_values)
                    new=b''.join(struct.pack('<fff',*row) for row in new_values)
                    if 'sparse' in aa:
                        if target is None or attr!='POSITION' or 'bufferView' in aa:
                            raise ValueError('unsupported sparse target representation')
                        # Keep original sparse bytes untouched; a dedicated dense
                        # tail stores the same Blender-decoded target values.
                        # The accessor is exclusive and only this sail's target
                        # representation changes; triangle indices remain exact.
                        while len(binary)%4:binary.append(0)
                        start=len(binary);binary.extend(new);end=len(binary)
                        view=len(output['bufferViews'])
                        output['bufferViews'].append({'buffer':0,'byteOffset':start,'byteLength':len(new)})
                        output['accessors'][ia].pop('sparse')
                        output['accessors'][ia]['bufferView']=view
                        output['accessors'][ia].pop('byteOffset',None)
                        raw_interval=None
                    else:
                        _,interval,old_bytes,_=dense(base,base_bin,ia,True)
                        start,end=interval
                        if old_bytes!=old:raise ValueError('dense byte encoding differs')
                        binary[start:end]=new
                        raw_interval=None
                    if attr=='POSITION':
                        for key,fn in [('min',min),('max',max)]:
                            if key in aa:output['accessors'][ia][key]=[fn(v[k] for v in new_values) for k in range(3)]
                    changes.append({'node':name,'material':material,'target':target,'attribute':attr,
                                    'accessor':ia,'authoredAccessor':ib,'start':start,'end':end,
                                    'authoredRepresentation':'sparse' if 'sparse' in ba else 'dense',
                                    'outputRepresentation':'appended-dense' if 'sparse' in aa else 'original-dense',
                                    'changed_bytes':sum(x!=y for x,y in zip(old,new)),
                                    'baselineSha256':sha(old),'authoredSha256':sha(new)})
    output['buffers'][0]['byteLength']=len(binary)
    intervals=sorted((x['start'],x['end']) for x in changes)
    if any(a[1]>b[0] for a,b in zip(intervals,intervals[1:])):raise ValueError('target intervals alias')
    if len(changes)!=72:raise ValueError('unexpected target count')
    for name in ('sail_0','sail_1','sail_2'):
        if not any(p['changed_bytes'] for p in changes if p['node']==name and p['target'] is None and p['attribute']=='POSITION'):
            raise ValueError('candidate sail unchanged: '+name)
    return output,bytes(binary),changes


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--authored',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--blend',type=Path,required=True);parser.add_argument('--report',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists() or args.report.exists() or args.report.resolve().is_relative_to(args.output.resolve()):
        parser.error('fresh output directory and separate fresh report required')
    inputs=[args.blend]+[args.baseline/f'fuchuan-lod{i}.glb' for i in range(3)]+[args.authored/f'fuchuan-lod{i}.glb' for i in range(3)]
    before={str(p.resolve()):sha(p.read_bytes()) for p in inputs};prepared=[]
    for lod in range(3):
        a,ab,_=read_checked(args.baseline/f'fuchuan-lod{lod}.glb')
        b,bb,_=read_checked(args.authored/f'fuchuan-lod{lod}.glb')
        doc,binary,changes=pack_documents(a,ab,b,bb)
        packed=encode(doc,binary);prepared.append((lod,packed,changes))
        print(f'HERO_R12_PACK_PREPARED lod={lod} intervals={len(changes)}',flush=True)
    if before!={str(p.resolve()):sha(p.read_bytes()) for p in inputs}:raise ValueError('inputs changed before output')
    args.output.mkdir(parents=True,exist_ok=False)
    lods=[]
    for lod,packed,changes in prepared:
        path=args.output/f'fuchuan-lod{lod}.glb'
        with path.open('xb') as stream:stream.write(packed)
        lods.append({'lod':lod,'output':str(path.resolve()),'output_sha256':sha(packed),'allowedIntervals':changes})
    if before!={str(p.resolve()):sha(p.read_bytes()) for p in inputs}:raise ValueError('inputs changed during output')
    report={'recordType':'cpu-sail-compatibility-package','asset':'hero-fuchuan-v3-r12','silhouetteParameters':{'width':[7.4,11.8,6.8],'k':[.25,.40,.54],'c':[.12,.17,.09]},
            'scope':'R7c cloned with only three Blender-authored sail P/N and morph P/N payloads',
            'sourceBlend':str(args.blend.resolve()),'inputSha256':before,'inputsUnchanged':True,'lods':lods,
            'toolSha256':sha(Path(__file__).read_bytes()),'completedUtc':datetime.now(timezone.utc).isoformat(),
            'limitations':['Not a full Blender re-export','No GPU, gameplay, continuity, clearance, artistic or performance acceptance'],
            'pass':True}
    with (args.output/'manifest.json').open('x',encoding='utf-8') as stream:json.dump(report,stream,indent=2)
    args.report.parent.mkdir(parents=True,exist_ok=True)
    with args.report.open('x',encoding='utf-8') as stream:json.dump(report,stream,indent=2)
    print('HERO_R12_SAIL_PACK_PASS lods=3',flush=True)


if __name__=='__main__':
    try:main()
    except (ValueError,OSError,KeyError,IndexError) as error:
        print('HERO_R12_SAIL_PACK_REFUSED: '+str(error),file=sys.stderr);raise SystemExit(1)
