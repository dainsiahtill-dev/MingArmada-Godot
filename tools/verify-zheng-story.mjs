import { readFile, writeFile, mkdir, stat } from 'node:fs/promises';
import path from 'node:path';
import { createHash } from 'node:crypto';
import vm from 'node:vm';
import { inspectImage } from './inspect-story-image.mjs';
export { inspectImage } from './inspect-story-image.mjs';
import { pathToFileURL } from 'node:url';
import { projectRoot, storyPath, readerDirectory, outputPath, jsonMirrorPath, serializeStory } from './build-zheng-story.mjs';
import { storyStructure, aliasIssues } from './zheng-story-contract.mjs';

const manifestPath = path.join(readerDirectory, 'illustration-manifest.json');
const reportPath = path.join(readerDirectory, 'verification.json');
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const text = value => typeof value === 'string' && value.trim().length > 0;
const array = value => Array.isArray(value) ? value : [];
const object = value => value && typeof value === 'object' && !Array.isArray(value);
const exists = async filename => stat(filename).then(info => info.isFile(), () => false);
const json = async filename => JSON.parse((await readFile(filename, 'utf8')).replace(/^\uFEFF/, ''));
const relative = filename => path.relative(projectRoot, filename).replaceAll('\\', '/');

function localImagePath(value) {
  if (!text(value) || !/^images\/(?:[A-Za-z0-9_-]+\/)*[A-Za-z0-9_.-]+\.(?:png|jpe?g)$/i.test(value)) {
    throw new Error('Image must be a portable images/ subpath ending in PNG or JPEG.');
  }
  return path.join(readerDirectory, value);
}

// Extract resource declarations only. This is not a DOM or browser emulator;
// JavaScript is parsed by V8 below, and browser behavior is a separate QA step.
function htmlTags(html) {
  return [...html.matchAll(/<(script|link|img)\b((?:[^>"']|"[^"]*"|'[^']*')*)>/gi)].map(match => {
    const attributes = {};
    for (const attribute of match[2].matchAll(/([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))/g)) {
      attributes[attribute[1].toLowerCase()] = attribute[2] ?? attribute[3] ?? attribute[4];
    }
    return { tag: match[1].toLowerCase(), attributes };
  });
}

export async function verifyStory({ allowPendingImages = false, textOnly = false, writeReport = true } = {}) {
  const checks = [];
  const artifacts = [];
  const pendingImages = [];
  const imageReferences = [];
  const imageRecords = [];
  const warnings = [];
  let expectedIllustrations = 0;
  let checkScope = 'text';
  const check = (condition, name, detail = '') => {
    checks.push({ name, scope: checkScope, passed: Boolean(condition), ...(detail ? { detail } : {}) });
    return Boolean(condition);
  };
  const artifact = async filename => {
    const bytes = await readFile(filename);
    const record = { path: relative(filename), bytes: bytes.length, sha256: sha256(bytes) };
    artifacts.push(record);
    return bytes;
  };
  const pending = (name, detail) => {
    pendingImages.push({ name, detail });
  };
  let story;
  let sourceBytes;
  try {
    sourceBytes = await artifact(storyPath);
    story = JSON.parse(sourceBytes.toString('utf8').replace(/^\uFEFF/, ''));
  }
  catch (error) { check(false, 'story:read-json', error.message); }

  if(story?.narrativeContract?.edition==='historical-reboot'){
    const {verifyReboot}=await import('./verify-zheng-reboot.mjs');
    return verifyReboot({story,writeReport});
  }

  if (story !== undefined) check(object(story), 'story:object');
  if (object(story)) {
    for (const key of ['title', 'subtitle', 'logline']) check(text(story[key]), `story:${key}`);
    check(Array.isArray(story.characters) && story.characters.length > 0, 'story:characters');
    const acts = Array.isArray(story.acts) ? story.acts : [];
    let structure;
    try { structure = storyStructure(story); check(true, 'story:recognized-narrative-contract'); }
    catch (error) { check(false, 'story:recognized-narrative-contract', error.message); structure = { acts: 5, scenesPerAct: 4, sceneCount: 20, prefix: 'yiguan' }; }
    check(acts.length === structure.acts, 'story:contract-act-count', `expected=${structure.acts}; actual=${acts.length}`);
    try { const issues = aliasIssues(story); check(!issues.length, 'story:published-scene-aliases', issues.join('; ')); }
    catch (error) { check(false, 'story:published-scene-aliases', error.message); }
    const ids = new Set();
    let sceneCount = 0;
    let previousYear = 1621;
    const levels = new Set(['historical', 'adaptation', 'legend']);
    const choiceIds = new Set();
    for (const [actIndex, act] of acts.entries()) {
      if (!check(object(act), 'act:object')) continue;
      check(text(act.id) && !ids.has(act.id), `act:${act.id}:unique-id`);
      check(act.id === `act-${actIndex + 1}`, `act:${act.id}:stable-id`);
      ids.add(act.id);
      for (const key of ['title', 'years', 'synopsis']) check(text(act[key]), `act:${act.id}:${key}`);
      const actIllustrationStatus = act.illustrationStatus ?? story.illustrationStatus;
      imageReferences.push({ id: act.id, path: act.cover, prompt: act.coverPrompt, illustrationStatus: actIllustrationStatus });
      const scenes = Array.isArray(act.scenes) ? act.scenes : [];
      check(Array.isArray(act.scenes) && scenes.length > 0, `act:${act.id}:scenes-array`, `actual=${scenes.length}`);
      if (structure.scenesPerAct) check(scenes.length === structure.scenesPerAct, `act:${act.id}:contract-scene-count`, `expected=${structure.scenesPerAct}; actual=${scenes.length}`);
      for (const scene of scenes) {
        sceneCount++;
        if (!check(object(scene), 'scene:object')) continue;
        const prefix = `scene:${scene.id}`;
        check(text(scene.id) && !ids.has(scene.id), `${prefix}:unique-id`);
        const sceneId = typeof scene.id === 'string' && scene.id.match(new RegExp(`^${structure.prefix}_a([1-${structure.acts}])_s([1-9]\\d*)$`));
        check(sceneId && Number(sceneId[1]) === actIndex + 1, `${prefix}:id-belongs-to-act`);
        if (structure.scenesPerAct) check(sceneId && Number(sceneId[2]) === scenes.indexOf(scene) + 1, `${prefix}:sequential-scene-id`);
        ids.add(scene.id);
        for (const key of ['title', 'location', 'summary']) check(text(scene[key]), `${prefix}:${key}`);
        const years = String(scene.year ?? '').match(/16\d{2}/g)?.map(Number) ?? [];
        check(years.length > 0 && years.every(year => year >= 1621 && year <= 1646), `${prefix}:year-range`);
        check(years.length > 0 && years[0] >= previousYear, `${prefix}:chronological`, `previous=${previousYear}; actual=${scene.year}`);
        if (years.length) previousYear = years[0];
        check(Array.isArray(scene.paragraphs) && scene.paragraphs.length >= 2 && scene.paragraphs.every(text), `${prefix}:at-least-two-narrative-paragraphs`);
        check(Array.isArray(scene.dialogue) && scene.dialogue.length >= 2, `${prefix}:at-least-two-dialogue-lines`);
        for (const [index, line] of array(scene.dialogue).entries()) {
          check(text(line?.speaker) && text(line?.text), `${prefix}:dialogue:${index}:speaker-and-text`);
        }
        check(Array.isArray(scene.choices), `${prefix}:optional-gameplay-choices-array`);
        for (const [index, choice] of array(scene.choices).entries()) {
          check(text(choice?.label) && text(choice?.consequence), `${prefix}:choice:${index}:action-and-consequence`);
          check(text(choice?.id) && !choiceIds.has(choice.id) && !ids.has(choice.id), `${prefix}:choice:${index}:unique-id`);
          choiceIds.add(choice?.id);
          ids.add(choice?.id);
        }
        check(object(scene.dramaticBeat), `${prefix}:dramatic-beat-object`);
        for (const key of ['want', 'obstacle', 'decision', 'result', 'next']) {
          check(text(scene.dramaticBeat?.[key]), `${prefix}:dramatic-beat:${key}`);
        }
        check(scene.history && levels.has(scene.history.level), `${prefix}:history-level`, String(scene.history?.level));
        check(text(scene.history?.note), `${prefix}:history-note`);
        check(Array.isArray(scene.history?.sources) && scene.history.sources.length > 0, `${prefix}:history-sources`);
        for (const [index, source] of array(scene.history?.sources).entries()) {
          check(object(source) && text(source.title), `${prefix}:source:${index}:title`);
          let legal = false;
          try { legal = ['http:', 'https:'].includes(new URL(source?.url).protocol); }
          catch {
            if (text(source?.url) && !/^(?:[a-z][a-z\d+.-]*:|\/\/|\/)/i.test(source.url)) {
              const filename = path.resolve(path.dirname(storyPath), source.url);
              const withinProject = path.relative(projectRoot, filename);
              legal = !withinProject.startsWith(`..${path.sep}`) && withinProject !== '..' &&
                !path.isAbsolute(withinProject) && await exists(filename);
            }
          }
          check(legal, `${prefix}:source:${index}:legal-link`);
        }
        imageReferences.push({ id: scene.id, path: scene.image, prompt: scene.imagePrompt,
          illustrationStatus: scene.illustrationStatus ?? actIllustrationStatus });
        check(scene.illustrations === undefined || Array.isArray(scene.illustrations), `${prefix}:process-frames-array`);
        for (const frame of array(scene.illustrations)) {
          check(object(frame) && text(frame.id) && !ids.has(frame.id), `${prefix}:process-frame-unique-id`);
          ids.add(frame.id);
          check(text(frame.caption), `${prefix}:${frame.id}:caption`);
          check(Number.isInteger(frame.afterParagraph) && frame.afterParagraph > 0 && frame.afterParagraph <= scene.paragraphs.length,
            `${prefix}:${frame.id}:paragraph-position`);
          imageReferences.push({id: frame.id, path: frame.image, prompt: frame.imagePrompt,
            illustrationStatus: frame.illustrationStatus ?? scene.illustrationStatus ?? actIllustrationStatus});
        }
      }
      for (let legacyScene = 1; !structure.scenesPerAct && legacyScene <= 5; legacyScene++) {
        const requiredId = `zheng_a${actIndex + 1}_s${legacyScene}`;
        check(scenes.some(scene => scene?.id === requiredId), `act:${act.id}:retains-original-scene:${requiredId}`);
      }
    }
    if (structure.sceneCount) check(sceneCount === structure.sceneCount, 'story:contract-total-scenes', `expected=${structure.sceneCount}; actual=${sceneCount}`);
    expectedIllustrations = imageReferences.length;
    check(!choiceIds.has(undefined), 'story:gameplay-choice-ids-complete', `actual=${choiceIds.size}`);
    checkScope = 'illustration';
    for (const reference of imageReferences) {
      if (reference.illustrationStatus === 'needs-redraw') {
        pending(`image:${reference.id}:needs-redraw`, 'Retained old asset is not accepted for the revised scene.');
      }
    }
    if (textOnly) {
      if (pendingImages.length === 0) pending('images:not-inspected-in-text-only-mode', 'No illustration acceptance is claimed.');
    } else {
    check(imageReferences.length === expectedIllustrations, 'images:one-reference-per-act-and-scene', `expected=${expectedIllustrations}; actual=${imageReferences.length}`);
    check(new Set(imageReferences.map(reference => reference.path?.toLowerCase())).size === imageReferences.length, 'images:unique-paths');
    const validPaths = new Set();
    const hashes = new Set();
    // A retained v4 image keeps its generation prompt in the preserved image
    // provenance. The new screenplay need not pretend that it commissioned
    // that prompt for its rewritten action. File/hash/source checks still run.
    let retainedPromptRecords = new Map();
    if (structure.edition === 'five-act-rewrite') {
      try { retainedPromptRecords = new Map(array((await json(manifestPath)).illustrations)
        .filter(entry => entry.reused === true && entry.originalVersion === 'v4-maritime-illustrated-2026-10-22' && text(entry.originalId))
        .map(entry => [entry.id, entry])); }
      catch { /* The strict manifest checks below report malformed provenance. */ }
    }
    for (const reference of imageReferences) {
      const retained = retainedPromptRecords.get(reference.id);
      const retainedPrompt = retained?.path === reference.path ? retained.prompt : undefined;
      check(text(reference.prompt) || text(retainedPrompt), `image:${reference.id}:prompt`);
      let filename;
      try { filename = localImagePath(reference.path); validPaths.add(reference.path); }
      catch (error) { check(false, `image:${reference.id}:portable-path`, error.message); continue; }
      if (!(await exists(filename))) {
        imageRecords.push({ ...reference, exists: false });
        pending(`image:${reference.id}:exists`, reference.path);
        continue;
      }
      try {
        const bytes = await artifact(filename);
        const info = inspectImage(bytes);
        const digest = sha256(bytes);
        check(info.width > 800 && info.height > 800, `image:${reference.id}:dimensions-over-800`, `${info.width}x${info.height}`);
        check(!hashes.has(digest), `image:${reference.id}:unique-hash`, digest);
        hashes.add(digest);
        imageRecords.push({ ...reference, ...info, exists: true, bytes: bytes.length, sha256: digest });
        if (info.format === 'JPEG') warnings.push(`JPEG ${reference.path}: frame/scan checked; full decoding remains browser QA.`);
      } catch (error) { check(false, `image:${reference.id}:valid-binary`, error.message); }
    }
    if (hashes.size !== expectedIllustrations) pending('images:distinct-files-for-current-story', `expected=${expectedIllustrations}; actual=${hashes.size}`);

    if (!(await exists(manifestPath))) pending('manifest:exists', relative(manifestPath));
    else {
      try {
        const manifest = JSON.parse((await artifact(manifestPath)).toString('utf8').replace(/^\uFEFF/, ''));
        check(manifest.schemaVersion === 1, 'manifest:schema-version');
        check(manifest.generator === 'built-in imagegen', 'manifest:built-in-imagegen');
        const illustrations = Array.isArray(manifest.illustrations) ? manifest.illustrations : [];
        check(Array.isArray(manifest.illustrations), 'manifest:illustrations-array');
        if (illustrations.length < expectedIllustrations) pending('manifest:entries-for-current-story', `expected=${expectedIllustrations}; actual=${illustrations.length}`);
        else check(illustrations.length === expectedIllustrations, 'manifest:entries-for-current-story', `expected=${expectedIllustrations}; actual=${illustrations.length}`);
        const manifestIds = new Set();
        const manifestPaths = new Set();
        for (const illustration of illustrations) {
          if (!check(object(illustration), 'manifest:entry-object')) continue;
          const prefix = `manifest:${illustration.id}`;
          check(text(illustration.id) && !manifestIds.has(illustration.id), `${prefix}:unique-id`);
          manifestIds.add(illustration.id);
          check(text(illustration.path) && !manifestPaths.has(illustration.path?.toLowerCase()), `${prefix}:unique-path`);
          manifestPaths.add(illustration.path?.toLowerCase());
          const reference = imageReferences.find(item => item.id === illustration.id);
          check(reference && reference.path === illustration.path, `${prefix}:matches-content-reference`);
          check(validPaths.has(illustration.path), `${prefix}:registered-path`);
          check(text(illustration.prompt), `${prefix}:prompt`);
          check(text(illustration.sourcePath), `${prefix}:generation-source-path`);
          check(Number.isInteger(illustration.width) && Number.isInteger(illustration.height) &&
            illustration.width > 800 && illustration.height > 800, `${prefix}:declared-dimensions-over-800`);
          check(typeof illustration.sha256 === 'string' && /^[a-f\d]{64}$/i.test(illustration.sha256), `${prefix}:sha256-format`);
          const record = imageRecords.find(item => item.id === illustration.id && item.exists);
          if (record) {
            check(record.width === illustration.width && record.height === illustration.height, `${prefix}:dimensions-match-file`);
            check(record.sha256 === illustration.sha256, `${prefix}:sha256-matches-file`);
            if (text(illustration.sourcePath)) {
              const sourcePath = path.resolve(projectRoot, illustration.sourcePath);
              if (await exists(sourcePath)) {
                check(sha256(await readFile(sourcePath)) === record.sha256, `${prefix}:original-source-matches-copy`);
              } else warnings.push(`${prefix}: original generation source no longer available; local packaged image was verified.`);
            }
          } else if (!allowPendingImages) check(false, `${prefix}:file-available-for-verification`);
        }
        for (const reference of imageReferences) {
          if (!manifestIds.has(reference.id)) pending(`manifest:${reference.id}:entry`, reference.path);
        }
      } catch (error) { check(false, 'manifest:read-json', error.message); }
    }
    }

    checkScope = 'text';
    try {
      const script = (await artifact(outputPath)).toString('utf8');
      check(script === serializeStory(story), 'build:current-deterministic-output');
      const context = vm.createContext({ window: {} });
      new vm.Script(script, { filename: relative(outputPath) }).runInContext(context, { timeout: 1000 });
      check(JSON.stringify(context.window.ZHENG_STORY) === JSON.stringify(story), 'build:v8-parsed-data-equals-json');
      check(!script.includes('<') && !script.includes('\u2028') && !script.includes('\u2029'), 'build:script-embedding-escaping');
    } catch (error) { check(false, 'build:parse-and-data-equivalence', error.message); }
    try {
      const mirrorBytes = await artifact(jsonMirrorPath);
      const mirror = JSON.parse(mirrorBytes.toString('utf8').replace(/^\uFEFF/, ''));
      check(JSON.stringify(mirror) === JSON.stringify(story), 'build:download-json-equals-source');
      check(mirrorBytes.equals(sourceBytes), 'build:download-json-exact-copy');
    } catch (error) { check(false, 'build:download-json-read-and-equivalence', error.message); }
  }

  checkScope = 'page';
  if (!textOnly) try {
    const htmlPath = path.join(readerDirectory, 'index.html');
    const html = (await artifact(htmlPath)).toString('utf8');
    const resources = htmlTags(html).flatMap(({ tag, attributes }) => {
      const value = (tag === 'link' ? attributes.href : attributes.src)?.split(/[?#]/)[0];
      return value ? [{ tag, value }] : [];
    });
    check(resources.some(resource => resource.tag === 'script' && resource.value === 'story-data.js'), 'page:loads-story-data');
    check(resources.some(resource => resource.tag === 'script' && resource.value === 'app.js'), 'page:loads-app');
    check(resources.some(resource => resource.tag === 'link' && resource.value === 'styles.css'), 'page:loads-styles');
    check(resources.findIndex(resource => resource.value === 'story-data.js') < resources.findIndex(resource => resource.value === 'app.js'), 'page:data-before-app');
    for (const resource of resources) {
      const name = `page:resource:${resource.value}`;
      const local = !/^(?:[a-z][a-z\d+.-]*:|\/\/|\/|#)/i.test(resource.value);
      check(local, `${name}:local`);
      if (!local) continue;
      const filename = path.resolve(readerDirectory, resource.value.split(/[?#]/)[0]);
      const contained = path.relative(readerDirectory, filename);
      check(contained !== '..' && !contained.startsWith(`..${path.sep}`) && !path.isAbsolute(contained), `${name}:within-reader`);
      if (contained.startsWith('..')) continue;
      try {
        const bytes = await artifact(filename);
        check(true, `${name}:exists`);
        if (resource.tag === 'script') {
          new vm.Script(bytes.toString('utf8'), { filename: relative(filename) });
          check(true, `${name}:v8-syntax`);
        }
      } catch (error) { check(false, `${name}:read-or-parse`, error.message); }
    }
  } catch (error) { check(false, 'page:resource-check', error.message); }

  const failures = checks.filter(result => !result.passed);
  const scopedResult = scope => {
    const scopedChecks = checks.filter(result => result.scope === scope);
    const failed = scopedChecks.filter(result => !result.passed);
    return { status: failed.length ? 'failed' : 'passed', valid: failed.length === 0,
      checks: scopedChecks.length, passed: scopedChecks.length - failed.length, failed: failed.length };
  };
  const textValidation = { ...scopedResult('text'),
    scope: 'Structure, required prose/dialogue, stable IDs, chronology fields, source links and source/build/mirror equivalence.',
    literaryAcceptance: 'not-assessed',
    note: 'Dramatic-beat fields are editorial completeness checks, not proof of literary quality or historical truth.' };
  const illustrationValidation = { ...scopedResult('illustration'),
    status: textOnly ? 'pending' : checks.some(result => result.scope === 'illustration' && !result.passed) ? 'failed' :
      pendingImages.length ? 'pending' : 'passed',
    valid: !textOnly && pendingImages.length === 0 && !checks.some(result => result.scope === 'illustration' && !result.passed),
    inspected: !textOnly,
    needsRedraw: imageReferences.filter(reference => reference.illustrationStatus === 'needs-redraw').map(reference => reference.id),
    note: 'Binary/manifest integrity does not establish visual or narrative acceptance. Frozen assets marked needs-redraw remain pending.' };
  const pageValidation = textOnly ? { status: 'not-run', valid: false, checks: 0, passed: 0, failed: 0 } : scopedResult('page');
  const fullDeliveryValid = textValidation.valid && illustrationValidation.valid && pageValidation.valid;
  let previous = {};
  try { previous = await json(reportPath); } catch { /* First report. */ }
  const priorSource = array(previous.artifacts).find(item => item.path === relative(storyPath));
  const browserValidation = previous.browserValidation ?? { status: 'not-run', note: 'Must be performed in a real browser; static verification is not browser evidence.' };
  const browserInputs=[storyPath,outputPath,path.join(readerDirectory,'index.html'),path.join(readerDirectory,'app.js'),path.join(readerDirectory,'styles.css')];
  let browserInputsChanged=false;
  for(const filename of browserInputs){
    const prior=array(previous.artifacts).find(item=>item.path===relative(filename));
    if(!prior||!await exists(filename)||sha256(await readFile(filename))!==prior.sha256)browserInputsChanged=true;
  }
  const browserEvidenceStale = browserValidation.status === 'passed' &&
    (!sourceBytes || priorSource?.sha256 !== sha256(sourceBytes)||browserInputsChanged);
  const report = {
    ...previous,
    schemaVersion: 1,
    generatedBy: 'tools/verify-zheng-story.mjs',
    generatedAt: new Date().toISOString(),
    scope: 'Text delivery, illustration integrity and static page checks are separate. Literary/historical judgment and browser behavior require independent review.',
    mode: textOnly ? 'text-only' : allowPendingImages ? 'allow-pending-images' : 'strict',
    status: textOnly ? (textValidation.valid ? 'passed' : 'failed') : failures.length ? 'failed' : pendingImages.length ? 'incomplete' : 'passed',
    valid: textOnly ? textValidation.valid : fullDeliveryValid,
    fullDeliveryValid,
    textValidation,
    illustrationValidation,
    pageValidation,
    summary: { checks: checks.length, passed: checks.length - failures.length, failed: failures.length,
      acts: array(story?.acts).length, scenes: array(story?.acts).reduce((count, act) => count + array(act?.scenes).length, 0),
      expectedIllustrations, expectedImages: expectedIllustrations, presentImages: textOnly ? null : imageRecords.filter(record => record.exists).length,
      uniqueImageHashes: textOnly ? null : new Set(imageRecords.map(record => record.sha256).filter(Boolean)).size,
      pendingImages: imageRecords.filter(record => !record.exists).length, pendingChecks: pendingImages.length },
    failures,
    pendingImages,
    warnings,
    checks,
    images: imageRecords,
    artifacts: [...new Map(artifacts.map(record => [record.path, record])).values()],
    browserValidation: browserEvidenceStale ? { ...browserValidation, status: 'stale', previousStatus: 'passed',
      note: 'Story source changed since browser QA; previous browser evidence does not validate this revision.' } : browserValidation,
  };
  if (writeReport) {
    await mkdir(readerDirectory, { recursive: true });
    await writeFile(reportPath, `${JSON.stringify(report, null, 2)}\n`, 'utf8');
  }
  return report;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  if (args.some(argument => !['--allow-pending-images', '--text-only'].includes(argument)) ||
      new Set(args).size !== args.length || args.length > 1) {
    console.error('Usage: node tools/verify-zheng-story.mjs [--allow-pending-images | --text-only]');
    process.exitCode = 1;
  } else {
    try {
      const report = await verifyStory({ allowPendingImages: args.includes('--allow-pending-images'), textOnly: args.includes('--text-only') });
      console.log(`Story verification: ${report.status}; ${report.summary.passed}/${report.summary.checks} checks; ${args.includes('--text-only') ? 'images not inspected' : `${report.summary.presentImages}/${report.summary.expectedIllustrations} images; ${report.summary.uniqueImageHashes} distinct image hashes`}.`);
      for (const failure of report.failures) console.error(`${failure.name}${failure.detail ? `: ${failure.detail}` : ''}`);
      console.log(`Report: ${relative(reportPath)}. Browser QA: ${report.browserValidation.status}.`);
      console.log(`Text: ${report.textValidation.status}; illustrations: ${report.illustrationValidation.status}; literary acceptance: not-assessed.`);
      process.exitCode = args.includes('--text-only') ? (report.textValidation.valid ? 0 : 1) :
        report.summary.failed > 0 || (!args.includes('--allow-pending-images') && !report.valid) ? 1 : 0;
    } catch (error) {
      console.error(`Story verification failed: ${error.stack ?? error.message}`);
      process.exitCode = 1;
    }
  }
}
