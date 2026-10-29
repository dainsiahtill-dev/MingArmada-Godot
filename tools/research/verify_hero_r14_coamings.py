"""Independent R14 audit: reconstruct old document, check added author payloads."""
import argparse,copy,hashlib,json,math,sys
from pathlib import Path
from verify_hero_palette_delta import read_glb,decode_accessor

ROOT=Path(__file__).resolve().parents[2]
NAMES=['cargo_hold_coaming_-3.2','cargo_hold_coaming_5.8']
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def item(items,name):
    matches=[x for x in items if x.get('name')==name]
    if len(matches)!=1:raise ValueError('unique named item required: '+name)
    return matches[0]
def halfwidth(z):
    knots=[(-16,2.25),(-14,3.),(-10,3.88),(-5,4.38),(0,4.5),(5,4.3),(9,3.72),(12,2.85),(14,1.85),(16,.24)]
    if z<=-16:return knots[0][1]
    if z>=16:return knots[-1][1]
    for i,(a,b) in enumerate(zip(knots,knots[1:])):
        if a[0]<=z<=b[0]:
            t=(z-a[0])/(b[0]-a[0]);h=b[0]-a[0];before=knots[max(0,i-1)];after=knots[min(len(knots)-1,i+2)]
            ma=(b[1]-before[1])/(b[0]-before[0]);mb=(after[1]-a[1])/(after[0]-a[0])
            return max(.12,(2*t**3-3*t*t+1)*a[1]+(t**3-2*t*t+t)*h*ma+(-2*t**3+3*t*t)*b[1]+(t**3-t*t)*h*mb)
    raise ValueError('outside hull')
def deck(x,z):return 1.92+1.8*(max(0,z)/16)**3.2+.7*(max(0,-z)/16)**2.6+.10*(1-(x/max(.25,halfwidth(z)))**2)

def verify(base,bb,cand,cb,raw,rb):
    errors=[];rows=[]
    try:
        root=item(cand['nodes'],'HeroFuchuan');base_root=item(base['nodes'],'HeroFuchuan')
        if root.get('extras',{}).get('candidate_experiment')!='hero-fuchuan-v3-r14':raise ValueError('candidate metadata missing')
        if len(cand['nodes'])!=len(base['nodes'])+2 or len(cand['meshes'])!=len(base['meshes'])+2 or len(cand['accessors'])!=len(base['accessors'])+8 or len(cand['bufferViews'])!=len(base['bufferViews'])+8:raise ValueError('unexpected new object count')
        if root['children']!=base_root.get('children',[])+list(range(len(base['nodes']),len(base['nodes'])+2)):raise ValueError('unexpected root children')
        clean=copy.deepcopy(cand);cleanroot=item(clean['nodes'],'HeroFuchuan');cleanroot['children']=copy.deepcopy(base_root['children']);del cleanroot['extras']['candidate_experiment']
        for key in ['nodes','meshes','accessors','bufferViews']:clean[key]=clean[key][:len(base[key])]
        clean['buffers'][0]['byteLength']=base['buffers'][0]['byteLength']
        if clean!=base:raise ValueError('original JSON outside declared append differs')
        if cb[:len(bb)]!=bb:raise ValueError('original BIN prefix differs')
        teak_idx=next(i for i,m in enumerate(base['materials']) if m.get('name')=='teak')
        covered=bytearray(len(cb));covered[:len(bb)]=b'\x01'*len(bb)
        for i,name in enumerate(NAMES):
            n=cand['nodes'][len(base['nodes'])+i];r=item(raw['nodes'],name)
            if n.get('name')!=name or n.get('extras')!={'deck_obstacle':True} or n['mesh']!=len(base['meshes'])+i:raise ValueError('new node contract differs')
            cm=cand['meshes'][n['mesh']];rm=raw['meshes'][r['mesh']]
            if cm.get('name')!=rm.get('name') or len(cm['primitives'])!=1 or len(rm['primitives'])!=1:raise ValueError('new mesh differs')
            cp=cm['primitives'][0];rp=rm['primitives'][0]
            if cp['material']!=teak_idx or raw['materials'][rp['material']]['name']!='teak':raise ValueError('wrong material identity')
            attrs=[(k,cp['attributes'][k],rp['attributes'][k]) for k in ['POSITION','NORMAL','TEXCOORD_0']]+[('indices',cp['indices'],rp['indices'])]
            for j,(key,ci,ri) in enumerate(attrs):
                if ci!=len(base['accessors'])+4*i+j:raise ValueError('unexpected appended accessor index')
                ca=cand['accessors'][ci];ra=raw['accessors'][ri];cv=cand['bufferViews'][ca['bufferView']]
                if ca['bufferView']!=len(base['bufferViews'])+4*i+j or ca.get('sparse') or cv.get('byteStride'):raise ValueError('unsupported appended storage')
                start=cv.get('byteOffset',0);end=start+cv['byteLength']
                if start<len(bb) or end>len(cb) or any(covered[start:end]):raise ValueError('appended data overlaps')
                covered[start:end]=b'\x01'*(end-start)
                for prop in ['type','componentType','count','normalized','min','max']:
                    if ca.get(prop)!=ra.get(prop):raise ValueError('new accessor property differs')
                if decode_accessor(cand,cb,ci)!=decode_accessor(raw,rb,ri):raise ValueError('author payload differs '+name+'/'+key)
            pos=decode_accessor(cand,cb,cp['attributes']['POSITION']);zcenter=-3.2 if i==0 else 5.8
            if abs(max(p[0] for p in pos)-min(p[0] for p in pos)-2.2)>1e-5 or abs(max(p[2] for p in pos)-min(p[2] for p in pos)-2.7)>1e-5:raise ValueError('outer dimensions differ')
            max_error=0.
            for x,y,z in pos:
                height=y-deck(x,z);max_error=max(max_error,min(abs(height-.03),abs(height-.55)))
                if abs(x)<.919 and abs(z-zcenter)<1.169:raise ValueError('solid geometry intrudes through center')
            if max_error>.00001:raise ValueError('coaming not based on actual deck curve')
            rows.append({'name':name,'vertices':len(pos),'outer':[2.2,2.7],'maxDeckHeightErrorMeters':max_error,'material':'teak','deckObstacle':True})
        if any(cb[i] for i in range(len(bb),len(cb)) if not covered[i]):raise ValueError('undeclared nonzero appended bytes')
    except (ValueError,KeyError,IndexError,TypeError,StopIteration) as error:errors.append(str(error))
    return {'pass':not errors,'errors':errors,'coamings':rows,'oldJsonExactAfterDeclaredAppendRemoved':not errors,'oldBinPrefixExact':not errors,'sourcePayloadAndDeckCurveChecked':not errors}

def main():
    p=argparse.ArgumentParser();p.add_argument('--baseline',type=Path,required=True);p.add_argument('--candidate',type=Path,required=True);p.add_argument('--authored',type=Path,required=True);p.add_argument('--author-evidence',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
    if a.output.exists():p.error('fresh output required')
    report={'lods':[],'scope':'Independent exact original JSON/BIN and two new Blender payloads; no collision, GPU or art acceptance.','toolSha256':sha(Path(__file__))}
    for lod in range(3):
        bp=a.baseline/f'fuchuan-lod{lod}.glb';cp=a.candidate/f'fuchuan-lod{lod}.glb';rp=a.authored/f'fuchuan-lod{lod}.glb'
        base,bb,bh=read_glb(bp);cand,cb,ch=read_glb(cp);raw,rb,rh=read_glb(rp)
        row=verify(base,bb,cand,cb,raw,rb)
        author=json.loads((a.author_evidence/f'blender-lod{lod}.json').read_text(encoding='utf-8'));process=json.loads((a.author_evidence/f'blender-lod{lod}-process.json').read_text(encoding='utf-8'));log=a.author_evidence/f'blender-lod{lod}.log'
        blend=ROOT/author['candidateBlend'];source_ok=all((ROOT/path).is_file() and sha(ROOT/path)==expected for path,expected in author['baselineSources'].items())
        receipt_ok=(author['lod']==lod and author['sourceUnchanged'] and author['candidateRawSha256']==rh and author['candidateBlendSha256']==sha(blend) and process['success'] and process['exitCode']==0 and process['markerCount']==1 and process['logSha256']==sha(log) and process['scriptSha256']==sha(ROOT/'tools/blender/build_hero_fuchuan_r14.py') and source_ok)
        row.update({'lod':lod,'baselineSha256':bh,'candidateSha256':ch,'authoredSha256':rh,'processAndInputsValid':receipt_ok});row['pass']=row['pass'] and receipt_ok
        report['lods'].append(row);print('HERO_R14_DELTA lod=',lod,' pass=',row['pass'],' errors=',row['errors'])
    report['pass']=all(r['pass'] for r in report['lods']);a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x',encoding='utf-8') as f:json.dump(report,f,indent=2)
    return 0 if report['pass'] else 1
if __name__=='__main__':raise SystemExit(main())
