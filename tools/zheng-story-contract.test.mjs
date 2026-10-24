import test from 'node:test';
import assert from 'node:assert/strict';
import {storyStructure,aliasIssues,legacySceneIds} from './zheng-story-contract.mjs';
const counts=[4,4,4,4,3,3];
const recent=Array.from({length:5},(_,a)=>Array.from({length:4},(_,s)=>`yiguan_a${a+1}_s${s+1}`)).flat();
function fixture(){return {narrativeContract:{edition:'historical-reboot',revision:9,acts:6,sceneCounts:counts,canonicalPrefix:'zzl'},acts:counts.map((n,a)=>({id:`act-${a+1}`,scenes:Array.from({length:n},(_,s)=>({id:`zzl_a${a+1}_s${s+1}`}))})),legacySceneAliases:Object.fromEntries([...legacySceneIds,...recent].map(id=>[id,'zzl_a1_s1']))};}
test('new historical edition has explicit variable-length six-part contract',()=>{const c=storyStructure(fixture());assert.equal(c.edition,'historical-reboot');assert.equal(c.sceneCount,22);assert.deepEqual(c.sceneCounts,counts);assert.equal(c.prefix,'zzl');});
test('edition cannot reduce its promised chapters by declaring new counts',()=>{const s=fixture();s.narrativeContract.sceneCounts=[1,1,1,1,1,1];assert.throws(()=>storyStructure(s));});
test('unknown edition cannot fall back to historical reboot',()=>{const s=fixture();s.narrativeContract.edition='unknown';assert.throws(()=>storyStructure(s));});
test('all sixty-three published bookmarks remain valid navigation aliases',()=>assert.deepEqual(aliasIssues(fixture()),[]));
test('dropping a previous five-act bookmark is rejected',()=>{const s=fixture();delete s.legacySceneAliases.yiguan_a5_s4;assert.ok(aliasIssues(s).some(x=>x.includes('yiguan_a5_s4')));});
test('alias to an absent or chained chapter is rejected',()=>{const s=fixture();s.legacySceneAliases.zheng_a1_s1='yiguan_a1_s1';assert.ok(aliasIssues(s).length>0);});
test('legacy five-act contract still enforced',()=>{assert.equal(storyStructure({narrativeContract:{acts:5,scenesPerAct:4,canonicalPrefix:'yiguan'}}).sceneCount,20);assert.throws(()=>storyStructure({narrativeContract:{acts:5,scenesPerAct:3,canonicalPrefix:'yiguan'}}));});
test('original six-act data remains recognized',()=>assert.equal(storyStructure({}).edition,'legacy-six-act'));
