import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Integrity and native metadata only. Human visual judgment belongs in the report.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const evidence = path.join(root, 'docs/migration/evidence');
const directory = path.join(evidence, 'entries');
const labels = ['menu-wide', 'menu-settings', 'recovery-invalid', 'recovered-1650-menu',
  'mingqi-native', 'career-native', 'duel-native', 'duel-narrow', 'fleet-native', 'sail-native',
  ...['fuchuan', 'fisherman', 'merchant', 'voc', 'patrol', 'heavy'].map(kind => `shipbook-${kind}`),
  ...['duel', 'landBattle', 'treasure', 'banquet'].map(kind => `practice-${kind}`)];
const verification = JSON.parse(await readFile(path.join(evidence, 'verification.json'), 'utf8'));
assert.equal(verification.filter, null, 'Evidence must come from the whole test suite');
assert.equal(verification.summary.passedAll, true);
assert.equal(verification.summary.selected, verification.discoveredTests.length);
const warnings = [verification.version, ...verification.runs].flatMap(run =>
  `${run.stdout}\n${run.stderr}`.split(/\r?\n/).filter(line => /^\s*WARNING:/.test(line)));
assert.deepEqual(warnings, [], 'Godot warnings require investigation');
const captures = [];
for (const label of labels) {
  const pixels = await readFile(path.join(directory, `${label}.png`));
  assert.equal(pixels.subarray(0, 8).toString('hex'), '89504e470d0a1a0a', `${label}: native PNG`);
  const metadataBytes = await readFile(path.join(directory, `${label}.json`));
  const metadata = JSON.parse(metadataBytes.toString('utf8'));
  const dimensions = [pixels.readUInt32BE(16), pixels.readUInt32BE(20)];
  assert.deepEqual(dimensions, metadata.viewport, `${label}: viewport and pixels agree`);
  assert.deepEqual(dimensions, label === 'duel-narrow' ? [320, 480] : [1600, 900]);
  assert.match(metadata.gpu, /Intel.*Arc/i, `${label}: actual native GPU metadata`);
  captures.push({ label, viewport: dimensions, engine: metadata.engine.string, gpu: metadata.gpu,
    scene: metadata.scene ?? 'res://game/scenes/main/main_scene.tscn', generation: metadata.generation,
    pngSha256: createHash('sha256').update(pixels).digest('hex'),
    metadataSha256: createHash('sha256').update(metadataBytes).digest('hex') });
}
const report = { recordedAtUtc: new Date().toISOString(), scope: 'Native capture integrity; excludes visual judgment and performance',
  sourceTool: 'tools/capture-native-entries.gd', captures,
  verification: { summary: verification.summary, godotWarnings: warnings,
    jsonSha256: createHash('sha256').update(await readFile(path.join(evidence, 'verification.json'))).digest('hex') } };
await writeFile(path.join(directory, 'integrity.json'), JSON.stringify(report, null, 2) + '\n');
await writeFile(path.join(evidence, `verification-full-${verification.summary.selected}.json`),
  await readFile(path.join(evidence, 'verification.json')));
console.log(`NATIVE_ENTRY_INTEGRITY captures=${captures.length} tests=${verification.summary.passed} failures=0 godotWarnings=0`);
