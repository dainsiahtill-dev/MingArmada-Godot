import test from 'node:test';
import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';

test('the real story verification CLI completes the adopted historical illustration checks',()=>{
 const result=spawnSync('rtk',['proxy',process.execPath,'tools/verify-zheng-story.mjs'],{
  cwd:fileURLToPath(new URL('..',import.meta.url)),encoding:'utf8',timeout:60000,windowsHide:true,
 });
 assert.ifError(result.error);
 assert.equal(result.status,0,`${result.stdout}\n${result.stderr}`);
 assert.match(result.stdout,/Story verification: passed;/);
 assert.doesNotMatch(result.stderr,/unsettled top-level await/);
});
