"""Independent R7c→R10a exact JSON/BIN and author-sail verifier.

This independently reconstructs allowed target storage from baseline and the
Blender intermediate. It does not call the candidate packer or trust its
manifest. Semantic numerical tolerance applies only to checking the declared
0.06 formula; all undeclared JSON, BIN, topology, UV and material data are exact.
"""
import argparse
import copy
import hashlib
import json
import math
import struct
from datetime import datetime, timezone
from pathlib import Path
from verify_hero_palette_delta import decode_accessor, read_glb

PARAMS=[(10.3,7.7,4.6),(17.,12.,4.05),(9.,6.8,5.35)]
MATERIALS=['canvas','bamboo','canvas_seam','hemp']
ROOT=Path(__file__).resolve().parents[2]


def verify_author_receipt(author,process,log,raw,blend,lod):
    sha=lambda b:hashlib.sha256(b).hexdigest()
    marker=('HERO_R10A_AUTHOR_LOD_OK lod='+str(lod)).encode()
    if not (process.get('success') is True and process.get('exitCode')==0
            and process.get('markerCount')==1 and log.count(marker)==1
            and process.get('logSha256')==sha(log) and author.get('lod')==lod
            and author.get('coefficient')==.06 and author.get('sourceUnchanged') is True
            and author.get('candidateRawSha256')==sha(raw.read_bytes())):return False
    if (ROOT/author.get('candidateRaw','')).resolve()!=raw.resolve():return False
    if lod==0 and (ROOT/author.get('candidateBlend','')).resolve()!=blend.resolve():return False
    sails=author.get('sails',[])
    if len(sails)!=3:return False
    for i,sail in enumerate(sails):
        if (sail.get('name')!='sail_'+str(i) or sail.get('parent')!='mast_'+str(i)
                or sail.get('materials')!=MATERIALS or sail.get('shapeKeys')!=['Basis','furl','inflate']):return False
    script=ROOT/'tools/blender/build_hero_fuchuan_r10a.py'
    if process.get('scriptSha256')!=sha(script.read_bytes()):return False
    if lod==0 and author.get('candidateBlendSha256')!=sha(blend.read_bytes()):return False
    required={'assets/production/hero-fuchuan-blender/hero-fuchuan-v3-r7c.blend':'ac057d349395a5e0547ec20e382188c34ed2c6481778b5142a99c4d920045fb3',
              'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod0.glb':'b87af112855cb6883faf97ec02a5eeb5fd61a5d504f204d3b3a573e73735d02d',
              'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod1.glb':'db9f01b8968f66f2a1c27c689e9a9e0cdd7f03ea27d86a9b6f2bb911872e461a',
              'assets/models/hero_fuchuan_v3_r7c/fuchuan-lod2.glb':'16aa79cb89074879354d82402540f478e9ad5279085d2c53d7f92d579aa2291d'}
    for p in ['tools/blender/build_hero_fuchuan_v3.py','tools/blender/build_hero_fuchuan.py',
              'tools/blender/hero_r10_sail_formula.py','tools/blender/build_hero_fuchuan_r10a.py']:required[p]=None
    recorded={path.replace('\\','/'):value for path,value in author.get('baselineSources',{}).items()}
    if set(recorded)!=set(required):return False
    for path,expected in recorded.items():
        file=(ROOT/path).resolve()
        if not file.is_relative_to(ROOT) or not file.is_file() or sha(file.read_bytes())!=expected:return False
        if required[path] is not None and expected!=required[path]:return False
    return True


def node(doc,name):
    matches=[x for x in doc['nodes'] if x.get('name')==name]
    if len(matches)!=1:raise ValueError('node is not unique: '+name)
    return matches[0]


def prims(doc,name):
    n=node(doc,name);m=doc['meshes'][n['mesh']]
    if sum(x.get('mesh')==n['mesh'] for x in doc['nodes'])!=1:raise ValueError('shared sail mesh')
    if m.get('extras',{}).get('targetNames')!=['furl','inflate']:raise ValueError('shape-key names differ')
    p=m['primitives']
    if [doc['materials'][x['material']]['name'] for x in p]!=MATERIALS:raise ValueError('material order differs')
    return p


def node_chain(doc,name):
    parents={}
    for index,item in enumerate(doc['nodes']):
        for child in item.get('children',[]):
            if child in parents:raise ValueError('node has multiple parents')
            parents[child]=index
    selected=next(i for i,n in enumerate(doc['nodes']) if n.get('name')==name)
    result=[];seen=set()
    while True:
        if selected in seen:raise ValueError('node parent cycle')
        seen.add(selected);n=doc['nodes'][selected]
        result.append({k:n[k] for k in ('name','translation','rotation','scale','matrix') if k in n})
        if selected not in parents:return result
        selected=parents[selected]


def accessor_uses(doc,index):
    count=0
    for mesh in doc.get('meshes',[]):
        for p in mesh['primitives']:
            count+=sum(value==index for value in p.get('attributes',{}).values())
            count+=int(p.get('indices')==index)
            for target in p.get('targets',[]):count+=sum(value==index for value in target.values())
    for skin in doc.get('skins',[]):count+=int(skin.get('inverseBindMatrices')==index)
    for anim in doc.get('animations',[]):
        for sampler in anim.get('samplers',[]):count+=int(sampler.get('input')==index)+int(sampler.get('output')==index)
    return count


def exact_vectors(doc, data, index):
    accessor=doc['accessors'][index];values=decode_accessor(doc,data,index)
    fmt={5120:'b',5121:'B',5122:'h',5123:'H',5125:'I',5126:'f'}[accessor['componentType']]
    size={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[accessor['type']]
    return b''.join(struct.pack('<'+fmt*size,*row) for row in values),values


def span(doc,index):
    a=doc['accessors'][index]
    if a.get('sparse') or 'bufferView' not in a or a['componentType']!=5126 or a['type']!='VEC3':
        raise ValueError('expected dense float VEC3')
    v=doc['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);length=a['count']*12
    if v.get('byteStride',12)!=12 or start+length>v.get('byteOffset',0)+v['byteLength']:
        raise ValueError('unsupported target storage')
    for i,other in enumerate(doc['bufferViews']):
        if i==a['bufferView']:continue
        o=other.get('byteOffset',0)
        if max(start,o)<min(start+length,o+other['byteLength']):raise ValueError('target aliases another buffer view')
    return start,start+length


def compare(base,base_bin,candidate,candidate_bin,authored,authored_bin):
    result={'pass':False,'errors':[],'sails':[],'scope':'Independent exact storage, authored sail payload and declared shoulder formula; no GPU/clearance/animation acceptance'}
    try:
        if node(base,'HeroFuchuan').get('extras',{}).get('authored_asset')!='hero-fuchuan-v3-r7c':raise ValueError('baseline identity')
        if node(authored,'HeroFuchuan').get('extras',{}).get('authored_asset')!='hero-fuchuan-v3-r7c':raise ValueError('Blender source identity')
        expected=copy.deepcopy(base);node(expected,'HeroFuchuan')['extras']['authored_asset']='hero-fuchuan-v3-r10a'
        binary=bytearray(base_bin);changed=[]
        for i,(height,width,base_y) in enumerate(PARAMS):
            name='sail_'+str(i);bs=prims(base,name);rs=prims(authored,name);cs=prims(candidate,name)
            if node_chain(base,name)!=node_chain(authored,name):raise ValueError('author sail frame chain differs')
            sail={'node':name,'materials':[],'maxCanvasFormulaErrorMeters':0.,'maxCanvasYChangeMeters':0.}
            for a,b,c in zip(bs,rs,cs,strict=True):
                material=base['materials'][a['material']]['name']
                if a.get('mode',4)!=4 or b.get('mode',4)!=4 or c.get('mode',4)!=4:raise ValueError('non-triangle target')
                for key in ('indices',):
                    ar,av=exact_vectors(base,base_bin,a[key]);br,bv=exact_vectors(authored,authored_bin,b[key])
                    if ar!=br or av!=bv:raise ValueError('authored indices changed: '+name+'/'+material)
                for key in ('TEXCOORD_0','COLOR_0'):
                    ar,av=exact_vectors(base,base_bin,a['attributes'][key]);br,bv=exact_vectors(authored,authored_bin,b['attributes'][key])
                    if ar!=br or av!=bv:raise ValueError('authored nongeometry attribute changed: '+name+'/'+material+'/'+key)
                oldp=decode_accessor(base,base_bin,a['attributes']['POSITION'])
                newp=decode_accessor(authored,authored_bin,b['attributes']['POSITION'])
                max_delta=max(abs(x-y) for v,w in zip(oldp,newp,strict=True) for x,y in zip(v,w,strict=True))
                if max_delta<=0:raise ValueError('authored material geometry did not change: '+name+'/'+material)
                max_residual=0.
                for old,new in zip(oldp,newp,strict=True):
                    # Back-project each original vertex with the author's
                    # original 12-step fixed-point inverse; the actual curve
                    # tube normals and fixed mast endpoints make this an
                    # approximation, not a surface clearance measurement.
                    v=max(0.,min(1.,(old[1]-base_y)/(height*1.12)))
                    for _ in range(12):
                        original_breadth=width*(1+.10*math.sin(math.pi*v)-.40*v*v)
                        u=max(0.,min(1.,(old[2]+width*.045*v*v)/original_breadth+.70))
                        v=max(0.,min(1.,(old[1]-base_y)/height-.15*(1-u)*v**2.2))
                    predicted=.06*width*math.sin(math.pi*v)**2*(1-2*v)*(u-.70)
                    max_residual=max(max_residual,abs(new[2]-old[2]-predicted))
                sail['materials'].append({'name':material,'vertices':len(oldp),'maxPositionDeltaMeters':max_delta,
                                          'maxApproximateReverseMapResidualMeters':max_residual,
                                          'residualScope':'12-step baseline inverse approximation, not physical clearance'})
                if material=='canvas':
                    uv=decode_accessor(base,base_bin,a['attributes']['TEXCOORD_0'])
                    for old,new,(u,v_uv) in zip(oldp,newp,uv,strict=True):
                        v=1-v_uv
                        delta=.06*width*math.sin(math.pi*v)**2*(1-2*v)*(u-.70)
                        sail['maxCanvasFormulaErrorMeters']=max(sail['maxCanvasFormulaErrorMeters'],abs((new[2]-old[2])-delta))
                        sail['maxCanvasYChangeMeters']=max(sail['maxCanvasYChangeMeters'],abs(new[1]-old[1]))
                    if sail['maxCanvasFormulaErrorMeters']>0.000005 or sail['maxCanvasYChangeMeters']>0.000005:
                        raise ValueError('canvas does not match declared 0.06 shoulder formula')
                pairs=[(a['attributes'],b['attributes'],c['attributes'])]+[(a['targets'][k],b['targets'][k],c['targets'][k]) for k in range(2)]
                for target,(original,new,packed) in enumerate(pairs):
                    for attr in ('POSITION','NORMAL'):
                        ia,ib,ic=original[attr],new[attr],packed[attr]
                        if ia!=ic:raise ValueError('output target accessor index changed')
                        if accessor_uses(base,ia)!=1:raise ValueError('target accessor is not unique')
                        spec=base['accessors'][ia];rawspec=authored['accessors'][ib]
                        for key in ('count','componentType','type'):
                            if spec[key]!=rawspec[key]:raise ValueError('authored target schema changed')
                        raw,values=exact_vectors(authored,authored_bin,ib)
                        if spec.get('sparse'):
                            if target!=2 or attr!='POSITION' or 'bufferView' in spec:raise ValueError('unsupported sparse target')
                            while len(binary)%4:binary.append(0)
                            start=len(binary);binary.extend(raw);end=len(binary)
                            new_view={'buffer':0,'byteOffset':start,'byteLength':len(raw)}
                            vindex=len(expected['bufferViews']);expected['bufferViews'].append(new_view)
                            e=expected['accessors'][ia];e.pop('sparse');e.pop('byteOffset',None);e['bufferView']=vindex
                        else:
                            start,end=span(base,ia)
                            if len(raw)!=end-start:raise ValueError('payload length changed')
                            binary[start:end]=raw
                        if attr=='POSITION':
                            for key,func in [('min',min),('max',max)]:
                                if key in spec:expected['accessors'][ia][key]=[func(v[k] for v in values) for k in range(3)]
                        observed,actual=exact_vectors(candidate,candidate_bin,ic)
                        if raw!=observed or values!=actual:raise ValueError('packed P/N differs from author: '+name+'/'+material)
                        changed.append([start,end])
            result['sails'].append(sail)
        expected['buffers'][0]['byteLength']=len(binary)
        if json.dumps(expected,sort_keys=True,allow_nan=False,separators=(',',':')) != json.dumps(candidate,sort_keys=True,allow_nan=False,separators=(',',':')):
            raise ValueError('undeclared JSON differs')
        if bytes(binary)!=candidate_bin:raise ValueError('undeclared BIN differs')
        if len(changed)!=72:raise ValueError('unexpected number of target attributes')
        result.update({'pass':True,'allowedTargetAttributes':len(changed),'allUndeclaredJsonExact':True,
                       'allUndeclaredBinExact':True,'triangleIndexUvColorExact':True,'allAuthoredPayloadExact':True})
    except (ValueError,KeyError,IndexError,TypeError,struct.error) as error:
        result['errors'].append(str(error))
    return result


def main():
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True)
    p.add_argument('--authored',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    p.add_argument('--author-evidence',type=Path,required=True);p.add_argument('--blend',type=Path,required=True);args=p.parse_args()
    if args.output.exists():p.error('fresh report required')
    report={'recordType':'independent-cpu-delta','startedUtc':datetime.now(timezone.utc).isoformat(),
            'toolSha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'lods':[]}
    for lod in range(3):
        author=json.loads((args.author_evidence/f'blender-lod{lod}.json').read_text(encoding='utf-8'))
        process=json.loads((args.author_evidence/f'blender-lod{lod}-process.json').read_text(encoding='utf-8'))
        log=(args.author_evidence/f'blender-lod{lod}.log').read_bytes()
        provenance=verify_author_receipt(author,process,log,args.authored/f'fuchuan-lod{lod}.glb',args.blend,lod)
        a,ab,ah=read_glb(args.baseline/f'fuchuan-lod{lod}.glb')
        b,bb,bh=read_glb(args.candidate/f'fuchuan-lod{lod}.glb')
        c,cb,ch=read_glb(args.authored/f'fuchuan-lod{lod}.glb')
        item=compare(a,ab,b,bb,c,cb);item.update({'lod':lod,'baselineSha256':ah,'candidateSha256':bh,'authoredSha256':ch,'authorReceiptAndProcessValid':provenance})
        if not provenance:item['pass']=False;item['errors'].append('author receipt, process, or input hash mismatch')
        report['lods'].append(item);print(f'HERO_R10A_DELTA lod={lod} pass={item["pass"]} errors={item["errors"]}',flush=True)
    report['pass']=all(x['pass'] for x in report['lods']);report['finishedUtc']=datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf-8') as stream:json.dump(report,stream,indent=2,ensure_ascii=False)
    print('HERO_R10A_DELTA_'+('PASS' if report['pass'] else 'FAIL'),flush=True)
    return 0 if report['pass'] else 1


if __name__=='__main__':raise SystemExit(main())
