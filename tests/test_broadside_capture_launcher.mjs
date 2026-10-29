import { test } from 'node:test';
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { validRunId, strictlyInside, fixtureHash, auditTimeline } from '../tools/research/run_broadside_lab_capture.mjs';

test('unique run identifier does not admit traversal or alternate separators',()=>{
  assert.equal(validRunId('gpu-20261027-01'),true);
  for (const value of ['','../escape','nested/run','a\\b','UPPER','-bad','bad-','a..b']) assert.equal(validRunId(value),false,value);
});
test('output must be strictly inside the evidence parent',()=>{
  const parent=resolve('docs/research/evidence/broadside-receipt-readability');
  assert.equal(strictlyInside(resolve(parent,'new-run'),parent),true);
  for (const value of [parent,resolve(parent,'..'),resolve(parent,'../broadside-receipt-readability-other/run')]) assert.equal(strictlyInside(value,parent),false,value);
});
function completeReport() {
  const rows=[[4,'e1','fire'],[8,'e2','fire'],[12,'e3','fire'],[14,'e4','fire'],[16,'e5','hit'],[20,'e6','splash']];
  const fixture=rows.map(([tick,id,type])=>({tick,event:{id,type}}));
  const captures=[];
  for (const [w,h] of [[1600,900],[1280,720]]) for(const variant of ['baseline','candidate']) for(let tick=0;tick<=112;tick++) {
    const text=tick>=16&&tick<112?'右舷命中 · 敌船倭船':'';
    const receipt={text};
    const snapshot={tick,time:tick/32,step_seconds:1/32,camera_mode:'fixed',paused:true,ready:true,parameters:{candidate_enabled:variant==='candidate',paused:true},fixture_events:fixture.filter(r=>r.tick<=tick).length,receipt,naive_text:tick>=20?'miss':'',visible_receipt:variant==='candidate'?text:''};
    const layout={viewport:[900,203],panel:[20,44,240,105],paintedBounds:[9,3,265,185],labels:[[44,60,192,20],[44,84,192,20],[44,107,192,26]]};
    captures.push({viewport:[w,h],variant,tick,time:tick/32,events:fixture.filter(r=>r.tick===tick).map(r=>r.event),snapshot,layout});
  }
  return {fixture,fixtureSha256:fixtureHash(fixture),captures,comparisons:226,fixedStep:1/32,lastTick:112,valid:true};
}
test('timeline audit refuses missing events, mutated paired state and incomplete sequences',()=>{
  const good=completeReport(); assert.deepEqual(auditTimeline(good),[]);
  const lost=structuredClone(good); lost.captures.find(f=>f.tick===16).events=[]; assert.ok(auditTimeline(lost).some(e=>e.includes('event trace')));
  const changed=structuredClone(good); changed.captures.find(f=>f.variant==='candidate'&&f.tick===16).snapshot.receipt.text='invented'; assert.ok(auditTimeline(changed).some(e=>e.includes('paired state')));
  const missing=structuredClone(good); missing.captures.pop(); assert.ok(auditTimeline(missing).some(e=>e.includes('missing pair')));
  const mismatch=structuredClone(good); mismatch.fixtureSha256='forged'; assert.ok(auditTimeline(mismatch).includes('fixture hash mismatch'));
  const clipped=structuredClone(good); clipped.captures[0].layout.paintedBounds[1]=-1; assert.ok(auditTimeline(clipped).some(e=>e.includes('clipped or missing layout')));
});
test('Node fixture digest agrees with Godot JSON canonicalization',()=>{
  const fixture=[
    {tick:4,event:{id:'e1',type:'fire',shipId:'flag',side:'starboard',projectileId:'p1'}},
    {tick:8,event:{id:'e2',type:'fire',shipId:'flag',side:'starboard',projectileId:'p2'}},
    {tick:12,event:{id:'e3',type:'fire',shipId:'flag',side:'starboard',projectileId:'p3'}},
    {tick:14,event:{id:'e4',type:'fire',shipId:'flag',side:'starboard',projectileId:'p4'}},
    {tick:16,event:{id:'e5',type:'hit',shipId:'flag',targetId:'enemy',projectileId:'p1'}},
    {tick:20,event:{id:'e6',type:'splash',shipId:'flag',projectileId:'p2'}}
  ];
  assert.equal(fixtureHash(fixture),'02312b287942dcf07a94e12e41b76ea13665cf2c3b6349ed2847313427745032');
});
test('a recorded run is rejected and its witness bytes remain unchanged',()=>{
  const file=resolve('docs/research/evidence/broadside-receipt-readability/capture-guard-witness-03/process-result.json');
  assert.equal(existsSync(file),true,'run guard witness first');
  const sha=()=>createHash('sha256').update(readFileSync(file)).digest('hex');
  const before=sha();
  const result=spawnSync(process.execPath,['tools/research/run_broadside_lab_capture.mjs','--guard','capture-guard-witness-03'],{encoding:'utf8'});
  assert.equal(result.status,1); assert.match(result.stderr,/EEXIST/); assert.equal(sha(),before);
});
