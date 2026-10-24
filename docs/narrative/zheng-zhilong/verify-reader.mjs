import assert from 'node:assert/strict';
import { storyStructure, aliasIssues } from '../../../tools/zheng-story-contract.mjs';
import { readFile, stat } from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const directory = path.dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
if (args.some(argument => argument !== '--text-only') || args.length > 1) {
  throw new Error('Usage: node verify-reader.mjs [--text-only]');
}
const textOnly = args.includes('--text-only');
const failures = [];
let assertions = 0;
function check(value, message) { assertions++; if (!value) failures.push(message); }
const read = (name) => readFile(path.join(directory, name), 'utf8');
const exists = async (name) => { try { return (await stat(path.join(directory, name))).isFile(); } catch { return false; } };
const html = await read('index.html'), css = await read('styles.css'), script = await read('app.js');
try { new vm.Script(script, { filename: 'app.js' }); check(true, 'app syntax'); } catch (error) { check(false, `app syntax: ${error.message}`); }
check(!/\bfetch\s*\(/.test(script), 'reader must not fetch data under file://');
check(!/<(?:script|link)\b[^>]*(?:src|href)=["']https?:/i.test(html), 'runtime dependencies must be local');
for (const name of ['styles.css', 'app.js', 'story-data.js']) check(await exists(name), `${name} exists`);
check(css.includes('@media print'), 'print stylesheet exists');
check(css.includes('prefers-reduced-motion'), 'reduced motion supported');
check(css.includes('max-width:767px'), 'mobile layout exists');
check(/color-scheme:\s*light/.test(css) && /name="color-scheme" content="light"/.test(html), 'reader keeps light paper under OS dark preference');
const scriptAt = html.search(/src="story-data\.js(?:\?[^\"]*)?"/), appAt = html.search(/src="app\.js(?:\?[^\"]*)?"/);
check(scriptAt >= 0 && appAt > scriptAt, 'classic data script precedes reader');
try {
  const dataSource = await read('story-data.js');
  const context = { window: {} }; vm.runInNewContext(dataSource, context, { timeout: 1500, filename: 'story-data.js' });
  const story = context.window.ZHENG_STORY;
  if(story?.narrativeContract?.edition==='historical-reboot'){
    const {verifyReboot}=await import('../../../tools/verify-zheng-reboot.mjs');
    const report=verifyReboot({writeReport:false});
    console.log(`ZHENG_REBOOT_READER_STATIC checks=${assertions+report.summary.checks} failures=${failures.length+report.failures.length} chapters=${report.summary.scenes}`);
    for(const failure of [...failures,...report.failures.map(x=>x.name)])console.error(failure);
    process.exit(failures.length||!report.valid?1:0);
  }
  check(!!story && Array.isArray(story.acts), 'window.ZHENG_STORY.acts exists');
  const acts = story?.acts || [], structure = storyStructure(story);
  check(acts.length === structure.acts, `exactly ${structure.acts} contracted acts`);
  const aliasErrors = aliasIssues(story); check(!aliasErrors.length, `published aliases valid: ${aliasErrors.join('; ')}`);
   const ids = new Set(); let sceneCount = 0, activeImages = 0, deferredImages = 0, choiceCount = 0, processCount = 0;
  for (const [actIndex, act] of acts.entries()) {
    const actStatus = act.illustrationStatus || story.illustrationStatus;
    check(typeof act.id === 'string' && !ids.has(act.id), `unique act id ${act.id}`); ids.add(act.id);
    check(act.id === `act-${actIndex + 1}`, `${act.id} stable act id`);
    check(!!act.title && !!act.synopsis, `${act.id} title and synopsis`);
    check(/^images\/(?:[\w-]+\/)*[\w.-]+\.png$/.test(act.cover || ''), `${act.id} local cover path`);
    if (actStatus === 'needs-redraw') deferredImages++;
    else { activeImages++; if (!textOnly) check(await exists(act.cover || '__missing__'), `${act.id} active cover image exists`); }
    check(Array.isArray(act.scenes) && act.scenes.length > 0, `${act.id} has scenes`);
    if (structure.scenesPerAct) check(act.scenes.length === structure.scenesPerAct, `${act.id} has exactly four rewritten scenes`);
    for (const scene of act.scenes || []) {
      const sceneStatus = scene.illustrationStatus || actStatus;
      sceneCount++;
      check(typeof scene.id === 'string' && !ids.has(scene.id), `unique scene id ${scene.id}`); ids.add(scene.id);
      const sceneId = typeof scene.id === 'string' && scene.id.match(new RegExp(`^${structure.prefix}_a([1-${structure.acts}])_s([1-9]\\d*)$`));
      check(sceneId && Number(sceneId[1]) === actIndex + 1, `${scene.id} belongs to ${act.id}`);
      if (structure.scenesPerAct) check(sceneId && Number(sceneId[2]) === act.scenes.indexOf(scene) + 1, `${scene.id} has sequential scene number`);
      check(!!scene.title && !!scene.location && !!scene.year, `${scene.id} scene metadata`);
      check(Array.isArray(scene.paragraphs) && scene.paragraphs.every((value) => typeof value === 'string' && value.trim()), `${scene.id} prose`);
      check(scene.paragraphs?.length >= 2, `${scene.id} at least two prose paragraphs`);
      check(Array.isArray(scene.dialogue) && scene.dialogue.length >= 2 && scene.dialogue.every(line => !!line.speaker && !!line.text), `${scene.id} complete dialogue`);
      check(Array.isArray(scene.choices), `${scene.id} optional gameplay choices array`);
      check(scene.choices?.every((choice) => !!choice.id && !!choice.label && !!choice.consequence), `${scene.id} choices have consequences`);
      choiceCount += scene.choices?.length || 0;
      check(!!scene.history?.level && !!scene.history?.note && Array.isArray(scene.history?.sources), `${scene.id} history layer`);
      check(/^images\/(?:[\w-]+\/)*[\w.-]+\.png$/.test(scene.image || ''), `${scene.id} local scene image path`);
      if (sceneStatus === 'needs-redraw') deferredImages++;
      else { activeImages++; if (!textOnly) check(await exists(scene.image || '__missing__'), `${scene.id} active scene image exists`); }
       for (const frame of scene.illustrations || []) {
         processCount++;
         check(typeof frame.id === 'string' && !ids.has(frame.id), `${scene.id} unique process frame ${frame.id}`); ids.add(frame.id);
         check(!!frame.caption && Number.isInteger(frame.afterParagraph) && frame.afterParagraph > 0 && frame.afterParagraph <= scene.paragraphs.length, `${frame.id} caption and paragraph position`);
         check(/^images\/(?:[\w-]+\/)*[\w.-]+\.png$/.test(frame.image || ''), `${frame.id} local image path`);
         if ((frame.illustrationStatus || sceneStatus) === 'needs-redraw') deferredImages++;
         else { activeImages++; if (!textOnly) check(await exists(frame.image || '__missing__'), `${frame.id} process image exists`); }
       }
    }
    for (let legacyScene = 1; !structure.scenesPerAct && legacyScene <= 5; legacyScene++) {
      const requiredId = `zheng_a${actIndex + 1}_s${legacyScene}`;
      check(act.scenes?.some(scene => scene?.id === requiredId), `${act.id} retains ${requiredId}`);
    }
  }
  if (structure.sceneCount) check(sceneCount === structure.sceneCount, 'exactly twenty rewritten scenes');
   const expectedIllustrations = acts.length + sceneCount + processCount;
   check(activeImages + deferredImages === expectedIllustrations, 'illustration references include act, scene and process frames');
  check(/id="revision-notice"[^>]*hidden/.test(html) && html.includes('剧情修订稿 · 插图暂缓'), 'single revision notice available');
  console.log(`ZHENG_READER_CONTENT mode=${textOnly ? 'text-only' : deferredImages ? 'text-with-deferred-art' : 'illustrated'} acts=${acts.length} scenes=${sceneCount} gameplayAlternatives=${choiceCount} expectedIllustrations=${expectedIllustrations} activeImageReferences=${activeImages} deferredImageReferences=${deferredImages}`);
  console.log('ZHENG_READER_SCOPE static data/resource checks only; browser self-check verifies deferred images are omitted.');
} catch (error) { check(false, `story data: ${error.message}`); }
assert.ok(assertions > 10);
console.log(`ZHENG_READER_STATIC_CHECK assertions=${assertions} failures=${failures.length}`);
for (const failure of failures) console.error(`FAIL ${failure}`);
process.exitCode = failures.length ? 1 : 0;
