"""Independent exact R7c -> R8b proxy-only JSON/BIN contract.

Only shadow_hull/shadow_deck FLOAT VEC3 POSITION/NORMAL component bytes may
change. POSITION bounds and the explicit HeroFuchuan authored_asset identity
are the only JSON deltas. Closed-composite means even edge incidence >=2 and
balanced directed edges; the original hull contains incidence-4 junctions.
"""
import argparse
import collections
import copy
import hashlib
import json
import math
import struct
import sys
from datetime import datetime, timezone
from pathlib import Path

from verify_hero_palette_delta import read_glb, decode_accessor

ROOT = Path(__file__).resolve().parents[2]
TARGETS = ('shadow_hull', 'shadow_deck')


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def uses(value, wanted):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == wanted and isinstance(child, int):
                yield child
            yield from uses(child, wanted)
    elif isinstance(value, list):
        for child in value:
            yield from uses(child, wanted)


def attribute_uses(value):
    if isinstance(value, dict):
        for key, child in value.items():
            if key == 'attributes' and isinstance(child, dict):
                yield from child.values()
            elif key == 'targets' and isinstance(child, list):
                for target in child:
                    yield from target.values()
            elif key in ('indices','input','output','inverseBindMatrices') and isinstance(child,int):
                yield child
            yield from attribute_uses(child)
    elif isinstance(value, list):
        for child in value:
            yield from attribute_uses(child)


def checked_file(path):
    document, binary, digest = read_glb(path)
    raw = path.read_bytes()
    offset, kinds = 12, []
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        if size % 4:
            raise ValueError('Chunk alignment invalid')
        kinds.append(kind)
        offset += size + 8
    if kinds != [0x4e4f534a,0x004e4942] or offset != len(raw):
        raise ValueError('Exactly one JSON and internal BIN required')
    length = document['buffers'][0]['byteLength']
    if not isinstance(length,int) or length < 0 or not 0 <= len(binary)-length <= 3:
        raise ValueError('Internal buffer length invalid')
    for v in document['bufferViews']:
        start,size=v.get('byteOffset',0),v['byteLength']
        if v.get('buffer',0)!=0 or not isinstance(start,int) or not isinstance(size,int) or start<0 or size<0 or start+size>length:
            raise ValueError('bufferView bounds invalid')
    return document,binary,digest


def proxy(document, name):
    ns=[n for n in document['nodes'] if n.get('name')==name]
    if len(ns)!=1 or 'mesh' not in ns[0]:
        raise ValueError('Target node identity ambiguous: '+name)
    mi=ns[0]['mesh']
    if sum(n.get('mesh')==mi for n in document['nodes'])!=1:
        raise ValueError('Proxy mesh shared')
    ps=document['meshes'][mi]['primitives']
    if len(ps)!=1 or ps[0].get('mode',4)!=4 or 'indices' not in ps[0] or ps[0].get('targets') or ps[0].get('extensions'):
        raise ValueError('Single indexed TRIANGLES proxy required')
    return ps[0]


def span(document, binary, index):
    a=document['accessors'][index]
    if a.get('componentType')!=5126 or a.get('type')!='VEC3' or a.get('normalized',False) or 'sparse' in a or 'bufferView' not in a:
        raise ValueError('Target must be dense non-normalized FLOAT VEC3')
    v=document['bufferViews'][a['bufferView']]
    count,local=a['count'],a.get('byteOffset',0)
    if not isinstance(count,int) or count<=0 or not isinstance(local,int) or local<0 or local%4 or v.get('byteStride',12)!=12 or local+12*count>v['byteLength']:
        raise ValueError('Unsupported target layout')
    if list(attribute_uses(document)).count(index)!=1 or list(uses(document,'bufferView')).count(a['bufferView'])!=1:
        raise ValueError('Target accessor/storage is shared')
    lo,hi=v.get('byteOffset',0),v.get('byteOffset',0)+v['byteLength']
    for vi,other in enumerate(document['bufferViews']):
        ol=other.get('byteOffset',0)
        if vi!=a['bufferView'] and max(lo,ol)<min(hi,ol+other['byteLength']):
            raise ValueError('Target storage alias')
    start,end=lo+local,lo+local+12*count
    if start%4:
        raise ValueError('Target alignment invalid')
    values=decode_accessor(document,binary,index)
    if not all(math.isfinite(x) for row in values for x in row):
        raise ValueError('Non-finite proxy geometry')
    return (start,end),values


def closed_composite(document,binary,primitive):
    vertices=decode_accessor(document,binary,primitive['attributes']['POSITION'])
    index=document['accessors'][primitive['indices']]
    if index.get('type')!='SCALAR' or index.get('componentType') not in (5121,5123,5125) or index.get('normalized',False) or 'sparse' in index:
        raise ValueError('Dense integer proxy indices required')
    indices=[row[0] for row in decode_accessor(document,binary,primitive['indices'])]
    if not indices or len(indices)%3 or any(i<0 or i>=len(vertices) for i in indices):
        raise ValueError('Proxy index bounds/topology invalid')
    edges=collections.Counter();directed=collections.Counter();degenerate=0
    for i in range(0,len(indices),3):
        t=[vertices[k] for k in indices[i:i+3]]
        if len(set(t))!=3:
            degenerate+=1
            continue
        e=[t[1][k]-t[0][k] for k in range(3)];f=[t[2][k]-t[0][k] for k in range(3)]
        cross=(e[1]*f[2]-e[2]*f[1],e[2]*f[0]-e[0]*f[2],e[0]*f[1]-e[1]*f[0])
        if not any(x!=0 for x in cross):
            degenerate+=1
        for a,b in [(t[0],t[1]),(t[1],t[2]),(t[2],t[0])]:
            edges[tuple(sorted((a,b)))]+=1;directed[(a,b)]+=1
    bad=sum(c<2 or c%2!=0 for c in edges.values())
    unbalanced=sum(directed[(a,b)]!=directed[(b,a)] for a,b in edges)
    histogram=dict(sorted(collections.Counter(edges.values()).items()))
    return {'pass':bool(edges) and degenerate==0 and bad==0 and unbalanced==0,
            'contract':'exact-position-welded closed composite; even incidence >=2 and directed balance; not strict manifold',
            'edge_incidence_histogram':histogram,'strict_manifold':set(histogram)=={2},
            'degenerate_triangles':degenerate,'open_or_odd_edges':bad,'unbalanced_edges':unbalanced,'triangles':len(indices)//3}


def compare(reference: Path, candidate: Path) -> dict:
    result={'baseline':str(Path(reference).resolve()),'candidate':str(Path(candidate).resolve()),'pass':False}
    try:
        a,ab,ah=checked_file(Path(reference));b,bb,bh=checked_file(Path(candidate))
        result.update(baseline_sha256=ah,candidate_sha256=bh)
        expected=copy.deepcopy(a)
        roots=[i for i,n in enumerate(a['nodes']) if n.get('name')=='HeroFuchuan']
        if len(roots)!=1 or a['nodes'][roots[0]].get('extras',{}).get('authored_asset')!='hero-fuchuan-v3-r7c':
            raise ValueError('Baseline authored_asset identity invalid')
        expected['nodes'][roots[0]]['extras']['authored_asset']='hero-fuchuan-v3-r8b'
        intervals=[];results={}
        for name in TARGETS:
            ap,bp=proxy(a,name),proxy(b,name)
            if ap['attributes'].keys()!=bp['attributes'].keys():
                raise ValueError('Proxy attribute keys changed')
            entry={}
            for attr in ('POSITION','NORMAL'):
                ai,bi=ap['attributes'][attr],bp['attributes'][attr]
                av,old=span(a,ab,ai);bv,new=span(b,bb,bi)
                if ai!=bi or av!=bv or len(old)!=len(new):
                    raise ValueError('Target layout changed')
                intervals.append(av)
                if attr=='POSITION':
                    expected['accessors'][ai]['min']=[min(row[k] for row in new) for k in range(3)]
                    expected['accessors'][ai]['max']=[max(row[k] for row in new) for k in range(3)]
                entry[attr]={'accessor':ai,'allowed_bin_interval_half_open':list(av),
                             'changed_bytes':sum(x!=y for x,y in zip(ab[av[0]:av[1]],bb[av[0]:av[1]]))}
            entry['baseline_closed_composite']=closed_composite(a,ab,ap)
            entry['candidate_closed_composite']=closed_composite(b,bb,bp)
            entry['pass']=entry['baseline_closed_composite']['pass'] and entry['candidate_closed_composite']['pass']
            results[name]=entry
        result['targets']=results
        # JSON booleans and numbers must stay distinct (Python False == 0).
        result['only_declared_json_delta']=(
            json.dumps(expected,sort_keys=True,allow_nan=False,separators=(',',':'))
            == json.dumps(b,sort_keys=True,allow_nan=False,separators=(',',':')))
        result['bin_length_exact']=len(ab)==len(bb)
        intervals.sort()
        if any(x[1]>y[0] for x,y in zip(intervals,intervals[1:])):
            raise ValueError('Target intervals overlap')
        # Compare unchanged byte runs directly, including padding and every image.
        cursor=0;outside_exact=True
        for start,end in intervals:
            outside_exact &= ab[cursor:start]==bb[cursor:start];cursor=end
        outside_exact &= ab[cursor:]==bb[cursor:]
        result['all_other_bin_bytes_exact']=bool(outside_exact)
        result['materials_and_images_json_exact']=a.get('materials')==b.get('materials') and a.get('images')==b.get('images')
        result['pass']=(result['only_declared_json_delta'] and result['bin_length_exact'] and outside_exact
                        and result['materials_and_images_json_exact'] and all(e['pass'] for e in results.values()))
    except (ValueError,KeyError,IndexError,TypeError,struct.error,OSError) as error:
        result['comparison_refused']=str(error)
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline',type=Path,required=True)
    parser.add_argument('--candidate',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('Fresh output required')
    report={'record_type':'cpu-contract','started_utc':datetime.now(timezone.utc).isoformat(),
            'method':__doc__,'tool_sha256':sha(Path(__file__).read_bytes()),'command':sys.argv,
            'limitations':['No Blender/GPU/visual/gameplay/performance acceptance.'],'lods':[]}
    for lod in range(3):
        item=compare(args.baseline/f'fuchuan-lod{lod}.glb',args.candidate/f'fuchuan-lod{lod}.glb')
        item['lod']=lod;report['lods'].append(item)
        print(json.dumps({'lod':lod,'pass':item['pass'],'comparison_refused':item.get('comparison_refused')}),flush=True)
    report['pass']=all(item['pass'] for item in report['lods'])
    report['finished_utc']=datetime.now(timezone.utc).isoformat()
    args.output.parent.mkdir(parents=True,exist_ok=True)
    with args.output.open('x',encoding='utf8') as stream:
        json.dump(report,stream,ensure_ascii=False,indent=2);stream.write('\n')
    print('HERO_PROXY_DELTA_'+('PASS' if report['pass'] else 'FAIL'))
    return 0 if report['pass'] else 1


if __name__=='__main__':
    raise SystemExit(main())
