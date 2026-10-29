import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { auditTimeline } from './run_crew_role_gpu.mjs';

const file = process.argv[2];
if (!file) throw new Error('Provide a completed capture-result.json; this checker does not generate evidence.');
const actual = JSON.parse(readFileSync(file, 'utf8'));
assert.deepEqual(auditTimeline(actual), [], 'actual report must pass before negative mutation checks');
const mutations = [
  ['missing frame', r => r.captures.pop()],
  ['missing tick', r => r.sequence.splice(100, 1)],
  ['duplicate tick', r => r.sequence[1] = structuredClone(r.sequence[0])],
  ['free material', r => r.sequence[100].wood += 1],
  ['wrong capture time', r => r.captures[50].snapshot.time += 1],
  ['headless claim', r => r.displayServer = 'headless'],
  ['unmuted claim', r => r.audioMuted = false],
  ['missing assignment', r => r.actions = []],
  ['fake pause', r => r.checks = r.checks.filter(x => x.name !== 'pause')],
  ['bad image identity', r => r.captures[0].file = '../outside.png'],
];
for (const [name, mutate] of mutations) {
  const changed = structuredClone(actual);
  mutate(changed);
  assert.ok(auditTimeline(changed).length > 0, name);
}
console.log(`CREW_GPU_EVIDENCE_CHECK assertions=${mutations.length + 1} failures=0 source=${file}`);
