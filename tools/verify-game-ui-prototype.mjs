import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {loadGameUiStory,uiStoryBaselinePath,uiStoryBaselineSha256} from './game-ui-story-baseline.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const folder = path.join(root, 'docs/design/game-ui/prototype');
const output = path.join(folder, 'verification.json');
const args = new Set(process.argv.slice(2));
const unknown = [...args].filter(arg => arg !== '--require-previews');
if (unknown.length) {
  console.error('Unknown arguments: ' + unknown.join(' '));
  console.error('Usage: node tools/verify-game-ui-prototype.mjs [--require-previews]');
  process.exit(2);
}
const requirePreviews = args.has('--require-previews');
const checks = [], failures = [], pending = [], navigation = [], pages = [], syntax = [];
const resourceRecords = new Map(), rendererOwners = new Map();
const registrationAttempts = [];
const expectedScripts = ['data.js', 'ui-core.js', 'render-world.js', 'render-ships.js', 'render-life.js', 'app.js'];
const relative = value => path.relative(root, value).split(path.sep).join('/');
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const unique = values => [...new Set(values)];

function check(id, description, passed, details = [], count = 1) {
  const record = { id, description, status: passed ? 'passed' : 'failed', count };
  const snapshot = structuredClone(details);
  if (snapshot.length) record.details = snapshot;
  checks.push(record);
  if (!passed) failures.push({ id, description, details: snapshot });
  return passed;
}

function readJSON(filename, label) {
  try {
    const parsed = JSON.parse(fs.readFileSync(filename, 'utf8'));
    check(label, relative(filename) + ' parses as JSON', true);
    return parsed;
  } catch (error) {
    check(label, relative(filename) + ' parses as JSON', false, [error.message]);
    return null;
  }
}

function decode(value) {
  return String(value).replace(/&(?:amp|lt|gt|quot|apos|nbsp|#\d+|#x[\da-f]+);/gi, entity => {
    const named = { '&amp;': '&', '&lt;': '<', '&gt;': '>', '&quot;': '"', '&apos;': "'", '&nbsp;': ' ' };
    const lowered = entity.toLowerCase();
    if (Object.hasOwn(named, lowered)) return named[lowered];
    const number = lowered.startsWith('&#x') ? Number.parseInt(lowered.slice(3, -1), 16) : Number.parseInt(lowered.slice(2, -1), 10);
    return Number.isFinite(number) && number >= 0 && number <= 0x10ffff ? String.fromCodePoint(number) : entity;
  });
}

function tags(html) {
  const result = [];
  const pattern = /<([a-z][\w:-]*)\b((?:"[^"]*"|'[^']*'|[^'">])*)>/gi;
  for (const match of html.matchAll(pattern)) {
    const attrs = {};
    const attributes = /([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>\x60]+)))?/g;
    for (const attribute of match[2].matchAll(attributes)) {
      attrs[attribute[1].toLowerCase()] = decode(attribute[2] ?? attribute[3] ?? attribute[4] ?? '');
    }
    result.push({ name: match[1].toLowerCase(), attrs });
  }
  return result;
}

function localResource(url, fromFile, location, kind) {
  const original = String(url ?? '').trim();
  if (!original || original.startsWith('#')) return;
  if (/^(?:data:|https?:|\/\/|blob:|mailto:|tel:|javascript:)/i.test(original)) {
    const key = 'external:' + original;
    const old = resourceRecords.get(key);
    if (old) old.references++;
    else resourceRecords.set(key, { url: original, kind, status: 'external-not-fetched', from: [location], references: 1 });
    return;
  }
  let decoded;
  try {
    decoded = decodeURIComponent(original.split(/[?#]/, 1)[0]);
  } catch (error) {
    resourceRecords.set('invalid:' + original, { url: original, kind, status: 'invalid-url', from: [location], references: 1, error: error.message });
    return;
  }
  const resolved = decoded.startsWith('/') ? path.resolve(root, '.' + decoded) : path.resolve(path.dirname(fromFile), decoded);
  const old = resourceRecords.get(resolved);
  if (old) {
    old.references++;
    if (old.from.length < 5 && !old.from.includes(location)) old.from.push(location);
    return;
  }
  let exists = false;
  try { exists = fs.statSync(resolved).isFile(); } catch { /* Report the absent file below. */ }
  resourceRecords.set(resolved, { url: original, path: relative(resolved), kind, status: exists ? 'exists' : 'missing', from: [location], references: 1 });
}

function cssResources(source, fromFile, location) {
  for (const match of source.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*?))\s*\)/gi)) {
    localResource(match[1] ?? match[2] ?? match[3], fromFile, location, 'css-url');
  }
  for (const match of source.matchAll(/@import\s+(?:"([^"]+)"|'([^']+)')/gi)) {
    localResource(match[1] ?? match[2], fromFile, location, 'css-import');
  }
}

function inspectHTML(source, fromFile, location, screenIds) {
  const elements = tags(source);
  const documentIds = new Set(elements.filter(element => Object.hasOwn(element.attrs, 'id')).map(element => element.attrs.id));
  for (const { attrs, name } of elements) {
    if (Object.hasOwn(attrs, 'data-go')) {
      navigation.push({ from: location, type: 'data-go', target: attrs['data-go'], valid: screenIds.has(attrs['data-go']) });
    }
    for (const attribute of ['src', 'poster']) {
      if (Object.hasOwn(attrs, attribute)) localResource(attrs[attribute], fromFile, location, name + '/' + attribute);
    }
    if (attrs.srcset && !attrs.srcset.trim().startsWith('data:')) {
      for (const candidate of attrs.srcset.split(',')) localResource(candidate.trim().split(/\s+/, 1)[0], fromFile, location, name + '/srcset');
    }
    if (attrs.style) cssResources(attrs.style, fromFile, location);
    for (const attribute of ['href', 'xlink:href']) {
      if (!Object.hasOwn(attrs, attribute)) continue;
      const value = attrs[attribute];
      if (value.startsWith('#')) {
        let target;
        try { target = decodeURIComponent(value.slice(1)); } catch { target = value.slice(1); }
        const internal = documentIds.has(target);
        navigation.push({ from: location, type: name === 'use' ? 'svg-fragment' : 'hash', target, valid: Boolean(target) && (internal || screenIds.has(target)), ...(internal ? { internalDefinition: true } : {}) });
      } else {
        localResource(value, fromFile, location, name + '/' + attribute);
      }
    }
  }
  for (const match of source.matchAll(/<style\b[^>]*>([\s\S]*?)<\/style>/gi)) cssResources(match[1], fromFile, location);
}

function bodyContent(html, screen) {
  let body = html.replace(/<!--[\s\S]*?-->/g, '')
    .replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi, '')
    .replace(/<header\b[^>]*class\s*=\s*["'][^"']*\bpage-head\b[^"']*["'][^>]*>[\s\S]*?<\/header>/gi, '')
    .replace(/<nav\b[^>]*>[\s\S]*?<\/nav>/gi, '')
    .replace(/<h1\b[^>]*>[\s\S]*?<\/h1>/gi, '');
  let text = decode(body.replace(/<[^>]*>/g, ' ')).replace(/\s+/g, ' ').trim();
  for (const metadata of [screen.title, screen.description]) if (metadata) text = text.split(metadata).join('');
  text = text.replace(/\s+/g, ' ').trim();
  body = body.replace(/\s+/g, ' ').trim();
  return { bodyHash: hash(body), textHash: hash(text), textLength: text.length };
}

function jpegInfo(filename) {
  if (!fs.existsSync(filename)) return { status: 'missing', path: relative(filename) };
  const buffer = fs.readFileSync(filename);
  const validHeader = buffer.length > 10 && buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff;
  const validEnd = buffer.length > 2 && buffer[buffer.length - 2] === 0xff && buffer[buffer.length - 1] === 0xd9;
  let width = 0, height = 0, offset = 2;
  const startOfFrame = new Set([0xc0, 0xc1, 0xc2, 0xc3, 0xc5, 0xc6, 0xc7, 0xc9, 0xca, 0xcb, 0xcd, 0xce, 0xcf]);
  while (validHeader && offset + 3 < buffer.length) {
    if (buffer[offset] !== 0xff) break;
    while (offset < buffer.length && buffer[offset] === 0xff) offset++;
    const marker = buffer[offset++];
    if (marker === 0xda || marker === 0xd9) break;
    if (marker === 0xd8 || marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;
    if (offset + 2 > buffer.length) break;
    const length = buffer.readUInt16BE(offset);
    if (length < 2 || offset + length > buffer.length) break;
    if (startOfFrame.has(marker) && length >= 8) {
      height = buffer.readUInt16BE(offset + 3);
      width = buffer.readUInt16BE(offset + 5);
      break;
    }
    offset += length;
  }
  return { status: validHeader && validEnd && width > 0 && height > 0 ? 'valid-jpeg' : 'invalid-jpeg', path: relative(filename), bytes: buffer.length, width, height, sha256: hash(buffer) };
}

function decodeImages(files) {
  if (!files.length) return { status: 'passed', images: [] };
  const source = String.raw`import sys,json,pathlib,hashlib
from PIL import Image,ImageStat
result=[]
for filename in json.load(sys.stdin):
 record={'absolutePath':filename}
 try:
  file=pathlib.Path(filename)
  with Image.open(file) as im:
   im.load()
   rgb=im.convert('RGB')
   extrema=rgb.getextrema()
   record.update(status='decoded',format=im.format,width=im.width,height=im.height,mode=im.mode,sha256=hashlib.sha256(file.read_bytes()).hexdigest(),decodedPixelSha256=hashlib.sha256(rgb.tobytes()).hexdigest(),completelyUniform=all(low==high for low,high in extrema),lumaStddev=round(ImageStat.Stat(rgb.convert('L')).stddev[0],4))
 except Exception as error:
  record.update(status='failed',error=str(error))
 result.append(record)
print(json.dumps(result,ensure_ascii=True))`;
  const child = spawnSync(process.platform === 'win32' ? 'rtk.exe' : 'rtk', ['proxy', 'python', '-c', source], {
    input: JSON.stringify(files), encoding: 'utf8', windowsHide: true, timeout: 60000, maxBuffer: 8 * 1024 * 1024,
  });
  if (child.error || child.status !== 0) return { status: 'failed', error: child.error?.message ?? child.stderr?.trim() ?? 'Image decoder exited ' + child.status, images: [] };
  try {
    const lines = child.stdout.trim().split(/\r?\n/);
    const images = JSON.parse(lines.at(-1));
    if (!Array.isArray(images) || images.length !== files.length) throw new Error('Decoder returned a different number of image records');
    return { status: 'passed', method: 'Pillow Image.open().load(), decoded RGB pixel hash and extrema through RTK', images };
  } catch (error) { return { status: 'failed', error: error.message, images: [] }; }
}

const catalog = readJSON(path.join(folder, '../systems.json'), 'catalog-json');
const story = loadGameUiStory(root);
check('ui-story-baseline-source', 'The UI simulation reads its preserved, hash-locked v4 screenplay and validates every successor in the current reader', story.version === 'v4-maritime-illustrated-2026-10-22' && story.acts.length === 6 && hash(fs.readFileSync(path.join(root, uiStoryBaselinePath))) === uiStoryBaselineSha256, [{sourcePath:uiStoryBaselinePath,sha256:uiStoryBaselineSha256,currentReader:'five-act rewrite; linked successors only'}], 1);
const screens = catalog?.screenGroups?.flatMap(group => group.screens) ?? [];
const screenIds = new Set(screens.map(screen => screen.id));
const systems = catalog?.systems ?? [], underlyingSystems = catalog?.underlyingSystems ?? [], flows = catalog?.flows ?? [];
const scenes = story?.acts?.flatMap(act => act.scenes) ?? [];
const sceneIds = new Set(scenes.map(scene => scene.id));
check('catalog-counts', '30 gameplay systems, 11 underlying systems, 72 screens, 12 groups and 13 flows', systems.length === 30 && underlyingSystems.length === 11 && screens.length === 72 && catalog?.screenGroups?.length === 12 && flows.length === 13, [{ systems: systems.length, underlyingSystems: underlyingSystems.length, screens: screens.length, groups: catalog?.screenGroups?.length ?? 0, flows: flows.length }], 5);
check('catalog-unique-ids', 'System, underlying system, screen, group and flow IDs are unique within each collection', [systems, underlyingSystems, screens, catalog?.screenGroups ?? [], flows].every(items => items.every(item => typeof item.id === 'string' && item.id) && new Set(items.map(item => item.id)).size === items.length), [], systems.length + underlyingSystems.length + screens.length + (catalog?.screenGroups?.length ?? 0) + flows.length);
const owners = new Map(systems.map(system => [system.id, new Set(system.pages ?? [])]));
const ownershipErrors = screens.filter(screen => !owners.get(screen.systemId)?.has(screen.id)).map(screen => screen.id);
for (const system of systems) {
  const actual = screens.filter(screen => screen.systemId === system.id).map(screen => screen.id).sort();
  if (JSON.stringify(actual) !== JSON.stringify([...(system.pages ?? [])].sort())) ownershipErrors.push(system.id);
}
const declaredPages = systems.flatMap(system => system.pages ?? []);
check('system-ownership', 'Each screen belongs to exactly one declared gameplay system', ownershipErrors.length === 0 && declaredPages.length === 72 && new Set(declaredPages).size === 72, ownershipErrors, screens.length);
const invalidReferences = [];
for (const entry of [...systems, ...screens, ...flows]) {
  if (!Array.isArray(entry.storyRefs)) invalidReferences.push(entry.id + ': storyRefs is not an array');
  for (const ref of entry.storyRefs ?? []) if (!sceneIds.has(ref)) invalidReferences.push(entry.id + ': ' + ref);
}
check('story-references', 'All storyRefs identify real scenes in the explicitly frozen v4 UI screenplay; current reader successors are separately validated', sceneIds.size === 43 && invalidReferences.length === 0, invalidReferences, [...systems, ...screens, ...flows].reduce((sum, item) => sum + (item.storyRefs?.length ?? 0), 0));
check('story-coverage', 'UI screen references cover all 43 scenes of their frozen v4 screenplay', new Set(screens.flatMap(screen => screen.storyRefs ?? [])).size === sceneIds.size && sceneIds.size === 43, [], sceneIds.size);
const flowErrors = flows.flatMap(flow => (flow.screenIds ?? []).filter(id => !screenIds.has(id)).map(id => flow.id + ': ' + id));
check('flow-pages', 'Every flow references existing screens', flowErrors.length === 0, flowErrors, flows.length);
const underlyingErrors = [];
for (const system of underlyingSystems) {
  for (const id of system.mappedPages ?? []) if (!screenIds.has(id)) underlyingErrors.push(system.id + ': page ' + id);
  for (const evidence of system.evidenceDocs ?? []) if (!fs.existsSync(path.resolve(root, evidence.path))) underlyingErrors.push(system.id + ': document ' + evidence.path);
  if (!system.existingImplementation?.status || !system.existingImplementation?.summary || !system.designTargets?.length || !system.verificationBoundary) underlyingErrors.push(system.id + ': missing implementation/design boundary');
}
check('underlying-mapping', 'Underlying systems map to real pages and evidence documents and distinguish existing evidence from targets', underlyingErrors.length === 0, underlyingErrors, underlyingSystems.length);

let indexSource = '';
const indexFile = path.join(folder, 'index.html');
try {
  indexSource = fs.readFileSync(indexFile, 'utf8');
  check('html-entry', 'Prototype index.html exists and contains an HTML entry point', /<!doctype\s+html/i.test(indexSource) && /<html\b/i.test(indexSource));
  inspectHTML(indexSource, indexFile, 'index.html', screenIds);
} catch (error) {
  check('html-entry', 'Prototype index.html exists', false, [error.message]);
}
const htmlElements = tags(indexSource);
const scriptURLs = htmlElements.filter(element => element.name === 'script' && element.attrs.src).map(element => element.attrs.src.split(/[?#]/, 1)[0]);
check('script-load-order', 'HTML loads data, core, all three renderer modules and app in contract order', expectedScripts.every((file, index) => scriptURLs.indexOf(file) >= 0 && (index === 0 || scriptURLs.indexOf(expectedScripts[index - 1]) < scriptURLs.indexOf(file))), [scriptURLs], expectedScripts.length);
const scriptSources = new Map();
for (const filename of unique([...expectedScripts, ...scriptURLs])) {
  if (/^(?:https?:|\/\/|data:)/i.test(filename)) continue;
  const absolute = path.resolve(folder, filename);
  try {
    const source = fs.readFileSync(absolute, 'utf8');
    new vm.Script(source, { filename: relative(absolute) });
    scriptSources.set(filename, source);
    syntax.push({ path: relative(absolute), status: 'passed', sha256: hash(source) });
  } catch (error) {
    syntax.push({ path: relative(absolute), status: 'failed', error: error.message });
  }
}
for (const [index, match] of [...indexSource.matchAll(/<script\b(?![^>]*\bsrc\s*=)[^>]*>([\s\S]*?)<\/script>/gi)].entries()) {
  try {
    new vm.Script(match[1], { filename: 'index.html:inline-' + index });
    syntax.push({ path: 'index.html:inline-' + index, status: 'passed' });
  } catch (error) {
    syntax.push({ path: 'index.html:inline-' + index, status: 'failed', error: error.message });
  }
}
check('javascript-syntax', 'Every classic HTML script parses as JavaScript', syntax.length >= expectedScripts.length && syntax.every(item => item.status === 'passed'), syntax.filter(item => item.status !== 'passed'), syntax.length);
const cssFiles = unique(htmlElements.filter(element => element.name === 'link' && element.attrs.rel?.split(/\s+/).includes('stylesheet')).map(element => element.attrs.href?.split(/[?#]/, 1)[0]).filter(Boolean));
for (const filename of cssFiles) {
  if (/^(?:https?:|\/\/|data:)/i.test(filename)) continue;
  const absolute = path.resolve(folder, filename);
  if (fs.existsSync(absolute)) cssResources(fs.readFileSync(absolute, 'utf8'), absolute, filename);
}

const sandbox = { console: { log() {}, warn() {}, error() {} }, URL, URLSearchParams, TextEncoder, TextDecoder, structuredClone: value => structuredClone(value) };
sandbox.window = sandbox;
const context = vm.createContext(sandbox, { name: 'game-ui-static-verification' });
const executionErrors = [];
for (const filename of ['data.js', 'ui-core.js']) {
  if (!scriptSources.has(filename)) continue;
  try { vm.runInContext(scriptSources.get(filename), context, { filename, timeout: 5000 }); }
  catch (error) { executionErrors.push({ file: filename, error: error.message }); }
}
const api = sandbox.GameUI;
check('core-api', 'Classic data.js and ui-core.js provide GAME_UI_DATA and the renderer registry', Boolean(sandbox.GAME_UI_DATA && api?.renderers && typeof api?.registerRenderer === 'function' && api?.ui), [...executionErrors, { dataLoaded: Boolean(sandbox.GAME_UI_DATA), registryLoaded: Boolean(api?.renderers), helperLoaded: Boolean(api?.ui) }]);
if (sandbox.GAME_UI_DATA && catalog) {
  const stale = ['systems', 'underlyingSystems', 'screenGroups', 'flows'].filter(key => JSON.stringify(sandbox.GAME_UI_DATA[key]) !== JSON.stringify(catalog[key]));
  check('generated-data-current', 'data.js matches current systems.json', stale.length === 0, stale, 4);
  const generatedScenes = sandbox.GAME_UI_DATA.scenes ?? [];
  check('generated-story-current', 'data.js matches its explicit frozen v4 UI story source, image mappings and source hash', generatedScenes.length === scenes.length && generatedScenes.every(scene => sceneIds.has(scene.id)) && scenes.every(scene => sandbox.GAME_UI_DATA.sceneImages?.[scene.id] === scene.image) && sandbox.GAME_UI_DATA.narrativeReference?.sha256 === uiStoryBaselineSha256 && sandbox.GAME_UI_DATA.narrativeReference?.sourcePath === uiStoryBaselinePath, [], scenes.length);
}
if (api?.registerRenderer) {
  const originalRegister = api.registerRenderer;
  let loadingFile = '';
  api.registerRenderer = function(ids, renderer) {
    for (const id of ids) {
      registrationAttempts.push({ id, file: loadingFile });
      if (!rendererOwners.has(id)) rendererOwners.set(id, loadingFile);
    }
    return originalRegister.call(this, ids, renderer);
  };
  for (const filename of ['render-world.js', 'render-ships.js', 'render-life.js']) {
    if (!scriptSources.has(filename)) {
      executionErrors.push({ file: filename, error: 'Renderer module is missing or has a syntax error' });
      continue;
    }
    loadingFile = filename;
    try { vm.runInContext(scriptSources.get(filename), context, { filename, timeout: 5000 }); }
    catch (error) { executionErrors.push({ file: filename, error: error.message }); }
  }
}
check('renderer-module-execution', 'All renderer modules execute in the classic-script VM', executionErrors.length === 0 && ['render-world.js', 'render-ships.js', 'render-life.js'].every(file => scriptSources.has(file)), executionErrors, 3);
const registeredIds = api?.renderers ? [...api.renderers.keys()] : [];
const missingRenderers = [...screenIds].filter(id => !registeredIds.includes(id));
const extraRenderers = registeredIds.filter(id => !screenIds.has(id));
const duplicateRegistrations = unique(registrationAttempts.filter((entry, index, entries) => entries.findIndex(other => other.id === entry.id) !== index).map(entry => entry.id));
check('renderer-registration', 'Exactly 72 canonical screens are registered with no duplicate or extra registrations', missingRenderers.length === 0 && extraRenderers.length === 0 && duplicateRegistrations.length === 0 && registeredIds.length === 72, [{ missing: missingRenderers, extra: extraRenderers, duplicate: duplicateRegistrations }], registeredIds.length);

const contractState = {
  silver: 2460, hull: 72, sails: 88, crew: 38, maxCrew: 60, morale: 78, ammo: 'solid',
  stock: { grain: 80, wood: 24, iron: 16, silk: 12, porcelain: 8, spices: 6 },
  selectedGood: 'silk', selectedCrew: 'awang', selectedItem: 'compass', equipped: '短刀', refit: '基础索具',
  post: '领航', contractAccepted: false, questAccepted: false, letterSent: false, sentLetters: 0,
  share: 35, paused: false, weather: '晴', speed: 8.6, zoom: 1, formation: '并列',
  leftShots: 12, rightShots: 12, reloading: false, saves: [],
  settings: { music: 60, effects: 75, text: 100, reducedMotion: false, colorAssist: false }, notice: '',
};
let stateSource = 'renderer-contract.md fixture';
function initialState() {
  if (typeof api?.initialState === 'function') { stateSource = 'GameUI.initialState()'; return api.initialState(); }
  if (api?.initialState && typeof api.initialState === 'object') { stateSource = 'GameUI.initialState object'; return structuredClone(api.initialState); }
  if (typeof api?.createInitialState === 'function') { stateSource = 'GameUI.createInitialState()'; return api.createInitialState(); }
  return structuredClone(contractState);
}
for (const screen of screens) {
  const result = { id: screen.id, title: screen.title, rendererFile: rendererOwners.get(screen.id) ?? null };
  if (!api?.renderers?.has(screen.id)) result.render = { status: 'missing-renderer' };
  else {
    try {
      sandbox.__verifyScreen = screen;
      sandbox.__verifyState = initialState();
      const html = vm.runInContext('window.GameUI.renderers.get(__verifyScreen.id)(__verifyScreen, __verifyState, window.GameUI.ui)', context, { filename: 'render:' + screen.id, timeout: 5000 });
      if (typeof html !== 'string' || !html.trim()) throw new Error('Renderer returned no HTML string');
      const content = bodyContent(html, screen);
      if (!content.textLength) throw new Error('Renderer has no substantive content after removing page heading, navigation and catalog description');
      result.render = { status: 'rendered', htmlBytes: Buffer.byteLength(html), ...content };
      inspectHTML(html, indexFile, screen.id, screenIds);
    } catch (error) { result.render = { status: 'failed', error: error.message }; }
  }
  result.preview = jpegInfo(path.join(folder, 'previews', screen.id + '.jpg'));
  pages.push(result);
}
delete sandbox.__verifyScreen;
delete sandbox.__verifyState;
const renderErrors = pages.filter(page => page.render.status !== 'rendered').map(page => ({ id: page.id, ...page.render }));
check('all-pages-render', 'Every registered page actually renders nonempty substantive HTML from an isolated state fixture', pages.length === 72 && renderErrors.length === 0, renderErrors, pages.filter(page => page.render.status === 'rendered').length);
function duplicates(field) {
  const groups = new Map();
  for (const page of pages.filter(page => page.render.status === 'rendered')) {
    const key = page.render[field];
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(page.id);
  }
  return [...groups.values()].filter(ids => ids.length > 1);
}
const duplicateBodies = duplicates('bodyHash'), duplicateText = duplicates('textHash');
check('dedicated-page-content', 'Rendered pages have distinct body HTML and visible-text hashes after ignoring shared heading/navigation', renderErrors.length === 0 && duplicateBodies.length === 0 && duplicateText.length === 0 && pages.length === 72, [{ duplicateBodyHashes: duplicateBodies, duplicateVisibleTextHashes: duplicateText }], pages.filter(page => page.render.status === 'rendered').length);
const invalidNavigation = navigation.filter(link => !link.valid);
check('navigation-targets', 'data-go and same-document hash links identify canonical pages or real internal definitions', invalidNavigation.length === 0, invalidNavigation, navigation.length);
const resources = [...resourceRecords.values()];
const missingResources = resources.filter(resource => resource.status === 'missing' || resource.status === 'invalid-url');
check('local-resources', 'All local HTML, rendered image/src and CSS url resources exist', missingResources.length === 0, missingResources, resources.filter(resource => resource.status === 'exists').length);
const validPreviews = pages.filter(page => page.preview.status === 'valid-jpeg');
const missingPreviews = pages.filter(page => page.preview.status === 'missing').map(page => page.id);
const invalidPreviews = pages.filter(page => page.preview.status === 'invalid-jpeg').map(page => page.id);
check('preview-file-headers', 'Present preview files have JPEG SOI/EOI and positive image dimensions', invalidPreviews.length === 0, invalidPreviews, validPreviews.length + invalidPreviews.length);
if (requirePreviews || missingPreviews.length === 0) {
  check('complete-previews', 'All 72 canonical pages have valid previews/<id>.jpg files', validPreviews.length === 72, [{ missing: missingPreviews, invalid: invalidPreviews }], validPreviews.length);
} else {
  const record = { id: 'complete-previews', description: 'All 72 canonical pages have valid previews/<id>.jpg files', status: 'pending', count: validPreviews.length, details: [{ missing: missingPreviews }] };
  checks.push(record); pending.push(record);
}
if (sandbox.GAME_UI_DATA) {
  const declared = [...(sandbox.GAME_UI_DATA.previewIds ?? [])].sort(), actual = validPreviews.map(page => page.id).sort();
  check('preview-index-current', 'data.js previewIds matches the available valid JPEG previews', JSON.stringify(declared) === JSON.stringify(actual), [{ declared: declared.length, actual: actual.length }], actual.length);
}
const declaredStatePreviews = sandbox.GAME_UI_DATA?.statePreviews ?? {};
const statePreviews = [], stateIndexErrors = [];
for (const id of Object.keys(declaredStatePreviews)) if (!screenIds.has(id)) stateIndexErrors.push(id + ': unknown screen');
for (const screen of screens) {
  const entries = declaredStatePreviews[screen.id];
  if (!Array.isArray(entries)) { stateIndexErrors.push(screen.id + ': missing state preview list'); continue; }
  const expected = (screen.states ?? []).map((state, index) => ({ state, file: screen.id + '--' + String(index + 1).padStart(2, '0') + '.jpg' }));
  if (JSON.stringify(entries) !== JSON.stringify(expected)) stateIndexErrors.push(screen.id + ': state names/order/files differ from catalog');
  for (const entry of entries) {
    const safe = typeof entry.file === 'string' && /^[a-z0-9-]+--\d{2}\.jpg$/.test(entry.file);
    statePreviews.push({ id: screen.id, title: screen.title, state: entry.state, file: entry.file, preview: safe ? jpegInfo(path.join(folder, 'previews/states', entry.file)) : { status: 'invalid-path' } });
    if (!safe) stateIndexErrors.push(screen.id + ': invalid preview path');
  }
}
const expectedStateCount = screens.reduce((sum, screen) => sum + (screen.states?.length ?? 0), 0);
const stateFiles = statePreviews.map(entry => entry.file);
check('state-preview-index-current', 'data.js statePreviews exactly matches all catalog states, order and safe per-state filenames', stateIndexErrors.length === 0 && statePreviews.length === expectedStateCount && new Set(stateFiles).size === stateFiles.length, stateIndexErrors, expectedStateCount);
const validStatePreviews = statePreviews.filter(entry => entry.preview.status === 'valid-jpeg');
const missingStatePreviews = statePreviews.filter(entry => entry.preview.status === 'missing').map(entry => entry.file);
const invalidStatePreviews = statePreviews.filter(entry => !['valid-jpeg', 'missing'].includes(entry.preview.status)).map(entry => entry.file);
check('state-preview-file-headers', 'Present declared state files have JPEG SOI/EOI and positive dimensions', invalidStatePreviews.length === 0, invalidStatePreviews, validStatePreviews.length + invalidStatePreviews.length);
if (requirePreviews || missingStatePreviews.length === 0) {
  check('complete-state-previews', 'Every declared catalog state has its own valid previews/states JPEG file', validStatePreviews.length === expectedStateCount && expectedStateCount > 0, [{ expected: expectedStateCount, missing: missingStatePreviews, invalid: invalidStatePreviews }], validStatePreviews.length);
} else {
  const record = { id: 'complete-state-previews', description: 'Every declared catalog state has its own valid previews/states JPEG file', status: 'pending', count: validStatePreviews.length, details: [{ expected: expectedStateCount, missing: missingStatePreviews }] };
  checks.push(record); pending.push(record);
}
const newArt = (sandbox.GAME_UI_DATA?.artCatalog?.assets ?? []).map(asset => ({ id: asset.id, name: asset.name, file: asset.path, absolutePath: path.resolve(folder, asset.path) }));
check('new-art-files', 'All six declared new 2D art assets exist inside the prototype folder', newArt.length === 6 && newArt.every(asset => asset.absolutePath.startsWith(folder + path.sep) && fs.existsSync(asset.absolutePath)), newArt.filter(asset => !asset.absolutePath.startsWith(folder + path.sep) || !fs.existsSync(asset.absolutePath)).map(asset => asset.file), newArt.length);
const imageInputs = [...validPreviews.map(page => ({ kind: 'default', id: page.id, filename: path.join(root, page.preview.path) })), ...validStatePreviews.map(entry => ({ kind: 'state', id: entry.id, state: entry.state, filename: path.join(root, entry.preview.path) })), ...newArt.filter(asset => asset.absolutePath.startsWith(folder + path.sep) && fs.existsSync(asset.absolutePath)).map(asset => ({ kind: 'art', id: asset.id, filename: asset.absolutePath }))];
const decoded = decodeImages(imageInputs.map(entry => entry.filename));
const decodedImages = decoded.images.map((entry, index) => {
  const { absolutePath, ...details } = entry;
  const { filename, ...input } = imageInputs[index];
  return { ...input, path: relative(absolutePath), ...details };
});
const decodeErrors = decodedImages.filter(entry => entry.status !== 'decoded' || entry.width <= 0 || entry.height <= 0 || entry.completelyUniform || entry.format !== (entry.kind === 'art' ? 'PNG' : 'JPEG'));
check('image-pixel-decode', 'Every present default/state screenshot and new art file fully decodes, has positive dimensions, expected format and nonuniform pixels', decoded.status === 'passed' && decodedImages.length === imageInputs.length && decodeErrors.length === 0, decoded.status === 'passed' ? decodeErrors : [{ error: decoded.error }], decodedImages.length);
function duplicateImageHashes(kind, field) {
  const groups = new Map();
  for (const entry of decodedImages.filter(image => image.kind === kind && image.status === 'decoded')) {
    if (!groups.has(entry[field])) groups.set(entry[field], []);
    groups.get(entry[field]).push(entry.path);
  }
  return [...groups.values()].filter(files => files.length > 1);
}
const duplicateImages = ['default', 'state'].flatMap(kind => ['sha256', 'decodedPixelSha256'].flatMap(field => duplicateImageHashes(kind, field).map(files => ({ kind, field, files }))));
check('screenshot-unique-pixels', 'Default screenshots and state screenshots are each unique in both file bytes and decoded RGB pixels', decoded.status === 'passed' && duplicateImages.length === 0, duplicateImages, validPreviews.length + validStatePreviews.length);
const manifest = readJSON(path.join(folder, 'preview-manifest.json'), 'preview-manifest-json');
const manifestEntries = [...(manifest?.pages ?? []), ...(manifest?.states ?? []), ...(manifest?.newArt ?? [])];
const manifestMap = new Map(manifestEntries.map(entry => [relative(path.resolve(folder, entry.filename)), entry]));
const manifestErrors = decodedImages.flatMap(entry => {
  const recorded = manifestMap.get(entry.path);
  return !recorded || recorded.sha256 !== entry.sha256 || recorded.decodedPixelSha256 !== entry.decodedPixelSha256 || recorded.width !== entry.width || recorded.height !== entry.height ? [entry.path] : [];
});
check('image-manifest-current', 'Manifest lists every current primary image with matching file hash, decoded pixel hash and dimensions', manifest !== null && manifestEntries.length === imageInputs.length && manifestMap.size === manifestEntries.length && manifestErrors.length === 0, manifestErrors, decodedImages.length);
const status = failures.length ? 'failed' : pending.length ? 'pending' : 'passed';
const report = {
  schemaVersion: 2, generatedAt: new Date().toISOString(), status,
  scope: 'Static contract, classic-script VM rendering, local resources and real default/state/art image decoding', requirePreviews, stateFixtureSource: stateSource,
  inputHashes: Object.fromEntries(['docs/design/game-ui/systems.json', 'docs/narrative/zheng-zhilong-story.json', uiStoryBaselinePath, 'tools/game-ui-story-baseline.mjs', 'tools/zheng-story-contract.mjs', 'docs/design/game-ui/renderer-contract.md', 'tools/verify-game-ui-prototype.mjs'].map(filename => [filename, fs.existsSync(path.join(root, filename)) ? hash(fs.readFileSync(path.join(root, filename))) : null])),
  counts: {
    gameplaySystems: systems.length, underlyingSystems: underlyingSystems.length, groups: catalog?.screenGroups?.length ?? 0,
    screens: screens.length, flows: flows.length, storyScenes: scenes.length, registeredRenderers: registeredIds.length,
    registrationAttempts: registrationAttempts.length, renderedPages: pages.filter(page => page.render.status === 'rendered').length,
    distinctBodyHashes: new Set(pages.filter(page => page.render.status === 'rendered').map(page => page.render.bodyHash)).size,
    distinctVisibleTextHashes: new Set(pages.filter(page => page.render.status === 'rendered').map(page => page.render.textHash)).size,
    localResources: resources.filter(resource => resource.status === 'exists').length, navigationReferences: navigation.length,
    validPreviews: validPreviews.length, declaredStates: expectedStateCount, validStatePreviews: validStatePreviews.length,
    newArt: newArt.length, decodedImages: decodedImages.filter(entry => entry.status === 'decoded').length,
    checksPassed: checks.filter(item => item.status === 'passed').length,
    checksFailed: failures.length, checksPending: pending.length,
  },
  checks, failures, pending, scriptSyntax: syntax, resources, navigation, pages, statePreviews,
  imageDecode: { status: decoded.status, method: decoded.method ?? null, images: decodedImages },
  notCovered: [
    'No browser, DOM layout, real user input, action handler or accessibility execution was performed.',
    'Pillow fully decodes current image bytes; hashes, nonblank pixels and dimensions do not establish visual quality or screenshot/page identity. Browser facts and contact-sheet visual review are recorded separately in preview-manifest.json.',
    'No Godot runtime, GPU, gameplay, performance or native persistence verification was performed.',
  ],
};
fs.mkdirSync(folder, { recursive: true });
fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
console.log('GAME_UI_STATIC ' + status.toUpperCase() + ' pages=' + report.counts.renderedPages + '/72 renderers=' + registeredIds.length + '/72 previews=' + validPreviews.length + '/72 states=' + validStatePreviews.length + '/' + expectedStateCount + ' decoded=' + report.counts.decodedImages + ' checks=' + report.counts.checksPassed + ' passed,' + failures.length + ' failed,' + pending.length + ' pending');
for (const failure of failures) console.error('FAIL ' + failure.id + ': ' + failure.description);
if (pending.length) console.log('PENDING previews: ' + missingPreviews.join(', '));
console.log('Report: ' + relative(output));
process.exitCode = failures.length ? 1 : 0;

