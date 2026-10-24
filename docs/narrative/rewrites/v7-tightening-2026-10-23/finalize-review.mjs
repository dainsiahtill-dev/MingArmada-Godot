import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const read = rel => fs.readFileSync(path.join(root, rel));
const hash = rel => crypto.createHash('sha256').update(read(rel)).digest('hex');
const sourcePath = 'docs/narrative/zheng-zhilong-story.json';
const evidencePath = 'docs/research/evidence/yiguan-subtractive-2026-10-23/browser-checks.json';
const receipt = JSON.parse(read(evidencePath));
for (const input of receipt.inputs) if (hash(input.path) !== input.sha256) throw new Error(`Stale browser receipt: ${input.path}`);
const story = JSON.parse(read(sourcePath));
const scenes = story.acts.flatMap(a => a.scenes);
const metrics = { paragraphs: scenes.reduce((n,s) => n+s.paragraphs.length,0), characters: scenes.reduce((n,s) => n+s.paragraphs.join('').length,0), dialogue: scenes.reduce((n,s) => n+s.dialogue.length,0) };
if (metrics.paragraphs !== 291 || metrics.characters !== 42747 || metrics.dialogue !== 100) throw new Error('Final text changed');
if (!read(sourcePath).equals(read('docs/narrative/zheng-zhilong/zheng-zhilong-story.json'))) throw new Error('Reader mirror is stale');
const reportPath = 'docs/narrative/zheng-zhilong/verification.json';
const report = JSON.parse(read(reportPath));
if (!report.valid || report.summary.failed || report.illustrationValidation.needsRedraw.length) throw new Error('Strict checks must pass first');
report.browserValidation = {
  status: 'partial', performedAt: receipt.date, scope: receipt.scope,
  focusedNarrativeChecks: 'passed', evidence: evidencePath,
  report: 'docs/research/evidence/yiguan-subtractive-2026-10-23/REVIEW.md',
  inputs: receipt.inputs, notRetested: receipt.notRetested,
  note: 'Current narrative synchronization checked in a real browser; native platform checks remain partial. Recheck these hashes after any input change.'
};
report.editorialReview = {
  status: 'reviewed-after-subtractive-edit', sourceSha256: hash(sourcePath),
  report: 'docs/narrative/rewrites/v7-tightening-2026-10-23/EDITING-REPORT.md',
  independentReview: 'docs/narrative/rewrites/v7-tightening-2026-10-23/COLD-READ.md',
  metrics,
  note: 'Three scenes tightened and all public hooks checked; two required findings fixed, then two short clarity recommendations adopted. Not a publication certification.'
};
fs.writeFileSync(path.join(root, reportPath), JSON.stringify(report, null, 2) + '\n');
console.log(JSON.stringify({strict: report.status, browser: report.browserValidation.status, narrativeBrowserChecks: 'passed', ...metrics}));
