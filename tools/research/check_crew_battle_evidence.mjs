import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { auditTimeline } from './run_crew_battle_gpu.mjs';
const file=process.argv[2];
if (!file) throw new Error('Provide an existing capture-result.json');
const actual=JSON.parse(readFileSync(file,'utf8'));
assert.deepEqual(auditTimeline(actual),[]);
const mutations=[
 ['missing image',r=>r.captures.pop()],
 ['duplicate tick',r=>r.sequence[1].tick=0],
 ['wrong native time',r=>r.captures[0].snapshot.native.time=10],
 ['fake repair',r=>r.captures[0].snapshot.crew.hull+=1],
 ['battle pays wages',r=>r.captures[0].snapshot.contract.day=1],
 ['unpaid worker',r=>r.captures[0].snapshot.contract.hired_ids.pop()],
 ['headless',r=>r.displayServer='headless'],
 ['no visible projectile',r=>{r.visibleProjectileSamples=0;r.sequence.forEach(s=>s.visible_projectiles=[]);}],
 ['forged command effect',r=>r.actions[0].after.native.time+=1],
 ['image traversal',r=>r.captures[0].file='../elsewhere.png'],
];
for(const [name,mutate] of mutations){const broken=structuredClone(actual);mutate(broken);assert.ok(auditTimeline(broken).length>0,name);}
console.log(`CREW_BATTLE_EVIDENCE_CHECK assertions=${mutations.length+1} failures=0 source=${file}`);
