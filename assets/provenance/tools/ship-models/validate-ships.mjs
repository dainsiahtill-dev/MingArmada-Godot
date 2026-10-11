import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {pathToFileURL} from 'node:url';
import validator from 'gltf-validator';

const directory=new URL('../../apps/game-client/public/models/ships/',import.meta.url);
const kinds=['fuchuan','fisherman','merchant','voc','patrol','heavy'];

/** Read the delivered files only; never regenerate or rewrite model artifacts. */
export async function validateShips(root=directory,log=console.log) {
  const failures=[];
  let checked=0,errors=0,warnings=0;
  try {
    const manifest=JSON.parse(await readFile(new URL('ships-manifest.json',root),'utf8'));
    if(manifest.version!==1||!Array.isArray(manifest.assets)||manifest.assets.length!==18)throw new Error('manifest must contain version 1 and exactly 18 assets');
    const expected=new Set(kinds.flatMap(kind=>[0,1,2].map(lod=>`${kind}-lod${lod}.glb`)));
    for(const asset of manifest.assets) {
      if(!asset||!expected.delete(asset.file)||!kinds.includes(asset.kind)||!Number.isInteger(asset.lod)||asset.lod<0||asset.lod>2||asset.file!==`${asset.kind}-lod${asset.lod}.glb`||!Number.isSafeInteger(asset.bytes)||asset.bytes<=0||typeof asset.sha256!=='string'||!/^[\da-f]{64}$/i.test(asset.sha256))throw new Error('manifest has duplicate, missing or invalid kind/LOD/hash/byte metadata');
    }
    if(expected.size)throw new Error('manifest does not cover all six kinds and three LODs');
    for(const asset of manifest.assets) {
      try {
        const bytes=await readFile(new URL(asset.file,root));
        const hash=createHash('sha256').update(bytes).digest('hex');
        if(bytes.length!==asset.bytes)failures.push(`${asset.file}: bytes ${bytes.length}, expected ${asset.bytes}`);
        if(hash!==asset.sha256.toLowerCase())failures.push(`${asset.file}: SHA256 mismatch`);
        const report=await validator.validateBytes(new Uint8Array(bytes),{uri:asset.file});
        checked++;errors+=report.issues.numErrors;warnings+=report.issues.numWarnings;
        if(report.issues.numErrors||report.issues.numWarnings) {
          const first=report.issues.messages.find(issue=>issue.severity<=1);
          failures.push(`${asset.file}: ${report.issues.numErrors} errors/${report.issues.numWarnings} warnings${first?`; ${first.code}: ${first.message}`:''}`);
        }
      }catch(error){failures.push(`${asset.file}: ${error instanceof Error?error.message:String(error)}`);}
    }
  }catch(error){failures.push(error instanceof Error?error.message:String(error));}
  failures.forEach(failure=>log(`FAIL ${failure}`));
  log(`${failures.length?'FAIL':'OK'} ${checked}/18 current GLBs; ${failures.length?`${failures.length} failed checks`:'SHA256/bytes match'}; validator ${errors} errors/${warnings} warnings`);
  return failures.length?1:0;
}

if(process.argv[1]&&import.meta.url===pathToFileURL(process.argv[1]).href)process.exitCode=await validateShips();
