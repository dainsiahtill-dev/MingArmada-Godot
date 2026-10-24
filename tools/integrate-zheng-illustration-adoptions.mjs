import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { projectRoot, storyPath } from './build-zheng-story.mjs';

const narrative = path.join(projectRoot, 'docs/narrative');
const reader = path.join(narrative, 'zheng-zhilong');
const groups = ['acts12', 'acts34', 'acts56', 'root'];
const records = groups.flatMap(group => JSON.parse(fs.readFileSync(path.join(narrative, `zheng-illustration-adoption-${group}-2026-10-22.json`), 'utf8')));
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const byId = new Map();
for (const record of records) {
  if (!record.adopted || !record.review || !record.prompt || byId.has(record.id)) throw new Error(`Unreviewed or duplicate adoption ${record.id}`);
  const bytes = fs.readFileSync(path.join(reader, record.path));
  if (digest(bytes) !== record.sha256 || bytes.readUInt32BE(16) !== record.width || bytes.readUInt32BE(20) !== record.height) throw new Error(`Asset metadata drift ${record.id}`);
  byId.set(record.id, record);
}
const story = JSON.parse(fs.readFileSync(storyPath, 'utf8'));
if (story.narrativeContract?.canonicalPrefix === 'yiguan') {
  throw new Error('The v4 illustration adoption pipeline must not overwrite the five-act rewrite. Re-index preserved sources with tools/sync-yiguan-illustration-manifest.mjs.');
}
const used = new Set();
const adopt = id => {
  const record = byId.get(id);
  if (!record) throw new Error(`Missing adopted illustration ${id}`);
  used.add(id); return record;
};
const positions = {
  zheng_a2_s7: [2, 4],
  zheng_a4_s3: [3, 4],
  zheng_a4_s7: [3, 5],
  zheng_a5_s4: [3, 4]
};
for (const act of story.acts) {
  const cover = adopt(act.id);
  Object.assign(act, { cover: cover.path, coverPrompt: cover.prompt, coverWidth: cover.width, coverHeight: cover.height, illustrationStatus: 'ready' });
  for (const scene of act.scenes) {
    const main = adopt(scene.id);
    Object.assign(scene, { image: main.path, imagePrompt: main.prompt, imageCaption: main.caption, imageWidth: main.width, imageHeight: main.height, illustrationStatus: 'ready' });
    if (positions[scene.id]) scene.illustrations = positions[scene.id].map((afterParagraph, index) => {
      const frame = adopt(`${scene.id}_process${index + 1}`);
      if (afterParagraph > scene.paragraphs.length) throw new Error(`Invalid frame paragraph ${frame.id}`);
      return { id: frame.id, image: frame.path, caption: frame.caption, afterParagraph,
        width: frame.width, height: frame.height, imagePrompt: frame.prompt, illustrationStatus: 'ready' };
    });
  }
}
if (used.size !== records.length) throw new Error(`Unused records ${records.filter(record => !used.has(record.id)).map(record => record.id)}`);
story.illustrationStatus = 'ready';
story.version = 'v4-maritime-illustrated-2026-10-22';
story.sourceNotes = story.sourceNotes.map(note => note.includes('既有插图冻结')
  ? '插图已按本稿逐场重新审读，情节吻合的旧图采用，失配场面独立重绘；关键战斗补充连续过程图。全部为当代生成的历史情境想象，不作为历史现场证据。' : note);
const manifest = {schemaVersion: 1, generator: 'built-in imagegen', updated: '2026-10-22',
  disclaimer: '当代生成的历史情境想象，不是历史照片或史料证据。逐场历史与虚构边界见正文。',
  illustrations: records};
fs.writeFileSync(storyPath, JSON.stringify(story, null, 2) + '\n');
fs.writeFileSync(path.join(reader, 'illustration-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({acts: story.acts.length, scenes: story.acts.flatMap(act => act.scenes).length,
  illustrations: records.length, processFrames: Object.keys(positions).length * 2,
  newlyGenerated: records.filter(record => !record.reused).length, reused: records.filter(record => record.reused).length}));
