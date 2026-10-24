import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../../..');
const read = file => fs.readFileSync(path.join(root, file));
const json = file => JSON.parse(read(file).toString('utf8'));
const hash = file => crypto.createHash('sha256').update(read(file)).digest('hex');
const sourcePath = 'docs/narrative/zheng-zhilong-story.json';
const mirrorPath = 'docs/narrative/zheng-zhilong/zheng-zhilong-story.json';
const reportPath = 'docs/narrative/zheng-zhilong/verification.json';
const evidencePath = 'docs/research/evidence/yiguan-v7-2026-10-23/browser-checks.json';
const receipt = json(evidencePath);

// Accept a browser receipt only for the exact files actually exercised.
for (const input of receipt.inputs) {
  if (hash(input.path) !== input.sha256) throw new Error(`Browser evidence is stale: ${input.path}`);
}
if (!read(sourcePath).equals(read(mirrorPath))) throw new Error('Reader mirror differs from source');
const receivedPath = 'docs/narrative/rewrites/v7-review-2026-10-23/received-v7-story.json';
const receivedHash = '085f5e8c73602391e4812c138bb50ad67b4324c8ce68bad5824063f93a366ba4';
if (hash(receivedPath) !== receivedHash) throw new Error('Received V7 baseline changed');
const scenes = json(sourcePath).acts.flatMap(act => act.scenes);
const paragraphs = scenes.reduce((n, scene) => n + scene.paragraphs.length, 0);
const characters = scenes.reduce((n, scene) => n + scene.paragraphs.join('').length, 0);
const dialogue = scenes.reduce((n, scene) => n + scene.dialogue.length, 0);
if (paragraphs !== 291 || characters !== 46391 || dialogue !== 101) throw new Error('Reviewed text changed');
const report = json(reportPath);
if (!report.valid || report.summary.failed || report.illustrationValidation.needsRedraw.length) {
  throw new Error('Strict structure and illustration verification must pass first');
}
report.browserValidation = {
  status: 'partial',
  performedAt: receipt.date,
  method: receipt.method,
  evidence: evidencePath,
  checklist: 'docs/research/evidence/yiguan-v7-2026-10-23/QA-NINE-CHECKS.md',
  summary: receipt.summary,
  inputs: receipt.inputs,
  note: 'Six of nine checklist items fully passed; three partially verified. Native print, file protocol and system preference checks remain unverified. Recheck these receipt hashes after any input change.'
};
report.editorialReview = {
  status: 'reviewed-with-reservations',
  report: 'docs/narrative/rewrites/v7-review-2026-10-23/EDITORIAL-ACCEPTANCE.md',
  sourceSha256: hash(sourcePath), receivedSha256: receivedHash,
  paragraphs, characters, dialogue,
  scope: 'Twenty scenes read; fourteen paragraph continuity repairs; not a publication or film-readiness certification.'
};
fs.writeFileSync(path.join(root, reportPath), `${JSON.stringify(report, null, 2)}\n`);
console.log(JSON.stringify({ browser: report.browserValidation.status, editorial: report.editorialReview.status,
  paragraphs, characters, dialogue, browserInputsMatched: receipt.inputs.length }));
