import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import test from 'node:test';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const storyFile = 'docs/narrative/zheng-zhilong-story.json';
const bibleFile = 'docs/narrative/rewrites/V7-REWRITE-BIBLE.md';
const baselineFile = 'docs/narrative/rewrites/baseline-v6-2026-10-22/story.json';

function runFixture(mutate = () => {}) {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'zheng-literary-test-'));
  try {
    for (const file of ['tools/verify-zheng-literary.mjs', storyFile, bibleFile, baselineFile]) {
      const target = path.join(fixtureRoot, file);
      fs.mkdirSync(path.dirname(target), { recursive: true });
      const input=file===storyFile?'docs/narrative/rewrites/v8-engagement-2026-10-23/baseline/story.json':file;
      fs.copyFileSync(path.join(root, input), target);
    }
    const story = JSON.parse(fs.readFileSync(path.join(fixtureRoot, storyFile), 'utf8'));
    let bible = fs.readFileSync(path.join(fixtureRoot, bibleFile), 'utf8');
    const changedBible = mutate(story, bible);
    if (changedBible !== undefined) bible = changedBible;
    fs.writeFileSync(path.join(fixtureRoot, storyFile), JSON.stringify(story));
    fs.writeFileSync(path.join(fixtureRoot, bibleFile), bible);
    const result = spawnSync(process.execPath, [path.join(fixtureRoot, 'tools/verify-zheng-literary.mjs')], {
      cwd: fixtureRoot,
      encoding: 'utf8',
    });
    assert.ifError(result.error);
    return { status: result.status, output: result.stdout + result.stderr };
  } finally {
    assert.equal(path.dirname(fixtureRoot), path.resolve(os.tmpdir()));
    assert.ok(path.basename(fixtureRoot).startsWith('zheng-literary-test-'));
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
}

// Merge two interior paragraphs: preserve every character and all word-root hits,
// while reducing the paragraph count by one. Only the count contract should fail.
function mergeParagraphs(story, id) {
  const scene = story.acts.flatMap(act => act.scenes).find(scene => scene.id === id);
  scene.paragraphs.splice(1, 2, scene.paragraphs[1] + scene.paragraphs[2]);
}

test('archived V7 story passes without changing the source fixture', () => {
  const result = runFixture();
  assert.equal(result.status, 0, result.output);
});

// First, second, third and fourth pairs, plus the final row with empty leading cells.
for (const [id, expected, actual] of [
  ['yiguan_a1_s1', 15, 14],
  ['yiguan_a2_s2', 15, 14],
  ['yiguan_a3_s3', 15, 14],
  ['yiguan_a5_s1', 15, 14],
  ['yiguan_a4_s4', 16, 15],
]) {
  test(`rejects one fewer paragraph in ${id}`, () => {
    const result = runFixture(story => mergeParagraphs(story, id));
    assert.equal(result.status, 1, result.output);
    assert.ok(result.output.includes(`${id}: 段落数合圣经: 期望 ${expected}，实际 ${actual}`), result.output);
  });
}

test('rejects missing paragraph specifications instead of silently skipping a scene', () => {
  const result = runFixture((_story, bible) => bible.replace('| a1_s1 | 15 |', '| | |'));
  assert.equal(result.status, 1, result.output);
  assert.ok(result.output.includes('yiguan_a1_s1: 圣经段落规格存在'), result.output);
});

test('rejects duplicate paragraph specifications instead of overwriting a count', () => {
  const result = runFixture((_story, bible) => `${bible}\n| a1_s1 | 15 |\n`);
  assert.equal(result.status, 1, result.output);
  assert.ok(result.output.includes('yiguan_a1_s1: 圣经段落规格唯一'), result.output);
});

test('archived v6 baseline rejects a matching accidental change to bible and story', () => {
  const result = runFixture((story, bible) => {
    mergeParagraphs(story, 'yiguan_a1_s1');
    return bible.replace('| a1_s1 | 15 |', '| a1_s1 | 14 |');
  });
  assert.equal(result.status, 1, result.output);
  assert.ok(result.output.includes('yiguan_a1_s1: 圣经段落数合第六稿基线: 期望 15，实际 14'), result.output);
});
