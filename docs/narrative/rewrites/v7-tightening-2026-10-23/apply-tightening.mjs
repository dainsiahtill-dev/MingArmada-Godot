import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../../..');
const sourcePath = path.join(root, 'docs/narrative/zheng-zhilong-story.json');
const baselineBytes = fs.readFileSync(path.join(here, 'before-story.json'));
if (!fs.readFileSync(sourcePath).equals(baselineBytes)) throw new Error('Source changed since this round began; review before applying');
const before = JSON.parse(baselineBytes);
const next = structuredClone(before);
const read = name => JSON.parse(fs.readFileSync(path.join(here, name), 'utf8'));
const scenes = story => story.acts.flatMap(act => act.scenes);
const byId = new Map(scenes(next).map(scene => [scene.id, scene]));
const editable = new Set(['paragraphs', 'summary', 'dialogue', 'dramaticBeat', 'readerTeaser', 'task', 'dramaticMode', 'currentCanon', 'suspense']);
for (const file of ['fog-proposal.json', 'xiamen-proposal.json', 'flag-proposal.json']) {
  const proposal = read(file);
  const scene = byId.get(proposal.id);
  if (!scene) throw new Error(`Unknown scene: ${file}`);
  for (const key of new Set([...Object.keys(scene), ...Object.keys(proposal)])) {
    if (!editable.has(key) && JSON.stringify(scene[key]) !== JSON.stringify(proposal[key])) throw new Error(`Protected field changed: ${proposal.id}.${key}`);
  }
  if (proposal.paragraphs.length !== scene.paragraphs.length || proposal.paragraphs.some(p => !p.trim())) throw new Error(`Paragraph contract: ${file}`);
  for (const key of editable) if (Object.hasOwn(proposal, key)) scene[key] = proposal[key];
}

// Coordinator's read-through: a small boat blocks hooks, not the mass of a pursuing hull.
const fog = byId.get('yiguan_a3_s3');
fog.paragraphs[9] = fog.paragraphs[9].replace('篙头顶开追船', '船工用篙挡住探来的挠钩');
fog.paragraphs[11] = fog.paragraphs[11].replace('叫小艇顺潮绕出', '叫小艇绕礁回救');
fog.summary = '潮口只剩半个时辰，阿旺的小艇既要接人又要挡住追船。一官看清顺生三起援旗，按住小锣，等陈添放下槌子才让他改口护货。货船过口，顺生沉没，四十人只救回两个；阿禾断腿，杜七掌伤。陈添在航记里写下援旗被雾挡住，阿禾就在近旁。';
const xiamen = byId.get('yiguan_a4_s2');
xiamen.paragraphs[5] = xiamen.paragraphs[5].replace('传令的人还等着。', '给接应艇传令的人还等着。');
const flagCase = byId.get('yiguan_a5_s1');
flagCase.paragraphs[4] = flagCase.paragraphs[4].replace('都是为失货来申的', '都是为先前失货来申的');

const hooks = read('hooks-and-endings.json');
for (const act of next.acts) Object.assign(act, hooks.acts[act.id]);
for (const [id, teaser] of Object.entries(hooks.scenes)) byId.get(id).readerTeaser = teaser;
for (const [id, paragraph] of Object.entries(hooks.lastParagraphs)) {
  const scene = byId.get(id);
  scene.paragraphs[scene.paragraphs.length - 1] = paragraph;
}

next.version = 'v7-subtractive-2026-10-23';
next.subtitle = '五幕二十场 · 文学剧本第七稿·节奏修订 · 1621—1646';
next.sourceNotes.push('2026-10-23减法修订：按用户明确采用的文学判断，压缩雾中辨旗、厦门对质及第五幕令旗案；简化五幕与二十场公开引子、幕末落像。保留291段、旧锚点、历史护栏、人物知情链和当前全部图像合同；没有新增事件或图片。');
next.editorialRevision = {
  ...next.editorialRevision,
  previousReport: next.editorialRevision.report,
  report: 'rewrites/v7-tightening-2026-10-23/EDITING-REPORT.md',
  beforeSourceSha256: crypto.createHash('sha256').update(baselineBytes).digest('hex'),
  scope: 'Subtractive edit of three confrontations, public hooks and act endings; human read-through required beyond lexical checks.'
};

const oldScenes = new Map(scenes(before).map(scene => [scene.id, scene]));
const edits = scenes(next).map(scene => {
  const old = oldScenes.get(scene.id);
  if (old.paragraphs.length !== scene.paragraphs.length) throw new Error(`Paragraph count changed: ${scene.id}`);
  return {
    id: scene.id, title: scene.title, before: old.paragraphs.join('').length, after: scene.paragraphs.join('').length,
    paragraphChanges: scene.paragraphs.flatMap((text, i) => text === old.paragraphs[i] ? [] : [{ paragraph: i + 1, before: old.paragraphs[i], after: text }]),
    readerTeaser: { before: old.readerTeaser, after: scene.readerTeaser }
  };
});
const metrics = story => ({ paragraphs: scenes(story).reduce((n,s) => n+s.paragraphs.length,0), characters: scenes(story).reduce((n,s) => n+s.paragraphs.join('').length,0), dialogue: scenes(story).reduce((n,s) => n+s.dialogue.length,0) });
const changes = { beforeVersion: before.version, afterVersion: next.version, before: metrics(before), after: metrics(next), edits };
fs.writeFileSync(path.join(here, 'changes.json'), JSON.stringify(changes, null, 2) + '\n');
const reportPath = path.join(root, 'docs/narrative/zheng-zhilong/verification.json');
const reportBytes = fs.readFileSync(reportPath);
const report = JSON.parse(reportBytes);
fs.writeFileSync(path.join(here, 'before-verification.json'), reportBytes);
report.browserValidation = { ...report.browserValidation, status: 'stale', previousStatus: report.browserValidation.status, note: 'Story and public hooks changed in the subtractive edit; earlier browser evidence does not validate this source.' };
if (report.editorialReview) report.editorialReview = { ...report.editorialReview, status: 'stale', note: 'Previous literary review describes the pre-tightening source.' };
fs.writeFileSync(reportPath, JSON.stringify(report, null, 2) + '\n');
fs.writeFileSync(sourcePath, JSON.stringify(next, null, 2) + '\n');
console.log(JSON.stringify({before: changes.before, after: changes.after, focusedScenes: edits.filter(x => ['yiguan_a3_s3','yiguan_a4_s2','yiguan_a5_s1'].includes(x.id)).map(({id,before,after})=>({id,before,after}))}));
