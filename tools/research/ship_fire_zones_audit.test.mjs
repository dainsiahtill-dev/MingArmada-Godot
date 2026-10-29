import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { auditState, auditTimeline } from './run_ship_fire_zones_gpu.mjs';

// Retained real GPU fixture, before the cumulative-budget audit was hardened.
const report = JSON.parse(readFileSync(new URL('../../docs/research/evidence/ship-fire-control/zones-gpu-01/frames/capture-result.json', import.meta.url), 'utf8'));
const state = report.captures.find(x => x.file === 'stern-005.png').snapshot;
test('real four-case report remains acceptable', () => {
  assert.deepEqual(auditState(state), []);
  assert.deepEqual(auditTimeline(report), []);
});
for (const [name, mutate] of [
  ['unbounded cumulative emission', s => { s.fire_view.ships.baseline.emitted_smoke = 999999; s.fire_view.ships.baseline.emitted_flames = 999999; }],
  ['missing hot ship record', s => { delete s.fire_view.ships.baseline; }],
  ['different slot in last-slot record', s => { s.fire_view.ships.baseline.last_slot.slot--; }],
]) test(`reject ${name}`, () => {
  const copy = structuredClone(state); mutate(copy);
  assert.ok(auditState(copy).some(x => /emission budget/.test(x)));
});
test('reject cumulative count regression even below absolute slot limit', () => {
  const copy = structuredClone(report), row = copy.sequences.find(x => x.case === 'stern' && x.sample === 5);
  const image = copy.captures.find(x => x.file === row.file);
  for (const view of [row.fire_view, image.snapshot.fire_view]) {
    view.ships.baseline.emitted_smoke = 3;
    view.ships.baseline.emitted_flames = 4;
  }
  assert.ok(auditTimeline(copy).some(x => /cumulative emission budget/.test(x)));
});
test('camera-only snapshots cannot introduce new fire emissions', () => {
  const copy = structuredClone(report), image = copy.captures.find(x => x.file === 'stern-active-near.png');
  image.snapshot.fire_view.ships.baseline.emitted_smoke--;
  assert.ok(auditTimeline(copy).some(x => /camera emission/.test(x)));
});
