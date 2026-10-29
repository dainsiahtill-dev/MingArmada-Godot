"""Compare two mathematically equivalent gain evaluation orders on raw R9b UVs."""
import json
import struct
from pathlib import Path
import verify_hero_r11_delta as contract

output=contract.ROOT/'docs/research/evidence/hero-fuchuan/r9-cinnabar-20261027/r11-rounding-order-diagnostic.json'
if output.exists():raise SystemExit('fresh output required')
f32=lambda value:struct.unpack('<f',struct.pack('<f',value))[0]
rows=[]
for lod in range(3):
    document,binary,_=contract.read_glb(contract.BASE/f'fuchuan-lod{lod}.glb')
    mismatches=[]
    for surface in contract.selections(document,binary):
        k=contract.COEFFICIENTS[surface['sail']]
        for vertex,(color,uv) in enumerate(zip(surface['colors'],surface['uvs'])):
            position=(1.0-uv[1])*8.0
            low=min(int(position),7);x=position-low;ease=x*x*(3.0-2.0*x)
            blend=(1.0-ease)*k[low]+ease*k[low+1]
            for channel,original in enumerate(color):
                first=f32(max(0,min(1,original*blend)))
                second=contract.expected_channel(original,uv[1],surface['sail'])
                if first!=second:
                    mismatches.append({'sail':surface['sail'],'vertex':vertex,'channel':channel,'uv':list(uv),'blend':first,'increment':second,'absoluteDifference':abs(first-second)})
    rows.append({'lod':lod,'mismatchCount':len(mismatches),'maximumDifference':max((x['absoluteDifference'] for x in mismatches),default=0.0),'examples':mismatches[:8]})
with output.open('x',encoding='utf8') as stream:json.dump({'scope':'read-only arithmetic ordering diagnosis; does not change acceptance tolerance','rows':rows},stream,indent=2);stream.write('\n')
print('R11_ROUNDING_DIAGNOSTIC '+json.dumps([{'lod':x['lod'],'count':x['mismatchCount'],'max':x['maximumDifference']} for x in rows]))
