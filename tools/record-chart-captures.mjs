import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const evidence = path.join(root, 'docs/migration/evidence');
const directory = path.join(evidence, 'charts/v2');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
function pngDimensions(bytes) {
  assert.equal(bytes.subarray(0, 8).toString('hex'), '89504e470d0a1a0a');
  return [bytes.readUInt32BE(16), bytes.readUInt32BE(20)];
}
const labels = ['legacy-expanded', 'legacy-sailing-minimap', 'legacy-sailing-minimap-moved',
  'island-details-wide', 'harbor-details-close', 'mingqi-expanded', 'mingqi-sailing-minimap',
  'mingqi-selected-escort-expanded', 'mingqi-narrow-expanded', 'default-trial-minimap', 'default-trial-expanded'];
const verificationBytes = await readFile(path.join(evidence, 'verification.json'));
const verification = JSON.parse(verificationBytes.toString('utf8'));
assert.equal(verification.filter, null, 'Whole suite required');
assert.equal(verification.summary.passedAll, true);
assert.equal(verification.summary.selected, verification.discoveredTests.length);
const warnings = [verification.version, ...verification.runs].flatMap(run =>
  `${run.stdout}\n${run.stderr}`.split(/\r?\n/).filter(line => /^\s*WARNING:/.test(line)));
assert.deepEqual(warnings, [], 'Godot warnings need investigation');
const captures = [];
for (const label of labels) {
  const png = await readFile(path.join(directory, `${label}.png`));
  const metadataBytes = await readFile(path.join(directory, `${label}.json`));
  const metadata = JSON.parse(metadataBytes.toString('utf8'));
  const dimensions = pngDimensions(png);
  assert.deepEqual(dimensions, metadata.viewport);
  assert.deepEqual(dimensions, label === 'mingqi-narrow-expanded' ? [800, 900] : [1600, 900]);
  assert.match(metadata.adapter, /Intel.*Arc/i);
  assert.equal(metadata.minimap.seaMaterial, 'res://assets/art/maps/ming-nautical-chart-v2.png');
  assert.equal(metadata.minimap.landMaterial, 'res://assets/art/maps/ming-nautical-land-paper-v2.png');
  if (label === 'mingqi-selected-escort-expanded') assert.match(metadata.packet.runtime.selectedShipId, /-fast$/);
  if (label === 'mingqi-narrow-expanded') assert.equal(metadata.minimap.visible, false);
  captures.push({ label, viewport: dimensions, engine: metadata.engine.string, gpu: metadata.adapter,
    pngSha256: hash(png), metadataSha256: hash(metadataBytes) });
}
const assets = [];
for (const name of ['ming-nautical-chart-v2.png', 'ming-nautical-land-paper-v2.png']) {
  const assetPath = `assets/art/maps/${name}`;
  const bytes = await readFile(path.join(root, assetPath));
  assets.push({ path: assetPath, dimensions: pngDimensions(bytes), sha256: hash(bytes) });
}
const report = { recordedAtUtc: new Date().toISOString(), tool: 'tools/capture-nautical-charts.gd -- --chart-v2',
  scope: 'Actual native GPU capture integrity. Visual judgment recorded separately; excludes FPS performance and complete voyage acceptance.',
  captures, assets, verification: { summary: verification.summary, godotWarnings: warnings, sha256: hash(verificationBytes) } };
await writeFile(path.join(directory, 'integrity.json'), JSON.stringify(report, null, 2) + '\n');
await writeFile(path.join(evidence, `verification-full-${verification.summary.selected}.json`), verificationBytes);
console.log(`NATIVE_CHART_V2_INTEGRITY captures=${captures.length} tests=${verification.summary.passed} failures=0 godotWarnings=0`);
