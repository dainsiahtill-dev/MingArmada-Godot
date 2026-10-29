import { createHash } from 'node:crypto';
import { lstat, mkdir, readFile, readdir, realpath, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SCRIPT_PATH = fileURLToPath(import.meta.url);
const REPO_ROOT = path.resolve(path.dirname(SCRIPT_PATH), '../../..');
const SITE_PATH = 'web/gameplay-journal';
const STATUSES = new Set(['playable', 'experiment', 'planned']);
const MEDIA_KINDS = new Set(['art', 'render', 'game', 'experiment']);
const PNG_SIGNATURE = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);

function requireValue(condition, message) {
  if (!condition) throw new Error(message);
}

function object(value, label) {
  requireValue(value && typeof value === 'object' && !Array.isArray(value), `${label} must be an object`);
}

function text(value, label) {
  requireValue(typeof value === 'string' && value.trim().length > 0, `${label} must be a nonempty string`);
}

function fields(row, names, label) {
  object(row, label);
  for (const name of names) text(row[name], `${label}.${name}`);
}

function date(value, label) {
  requireValue(typeof value === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(value), `${label} must be an ISO date (YYYY-MM-DD)`);
  const parsed = new Date(`${value}T00:00:00.000Z`);
  requireValue(!Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value, `${label} is not a valid calendar date`);
}

function status(value, label) {
  requireValue(STATUSES.has(value), `${label} must be a valid status: playable, experiment, planned`);
}

function validateStoryOverview(overview) {
  fields(overview, ['title', 'lead', 'heroLead', 'note'], 'storyOverview');
  requireValue(overview.status === 'planned', 'storyOverview.status must reflect the planned main campaign');
  requireValue(Array.isArray(overview.paragraphs) && overview.paragraphs.length === 3,
    'storyOverview.paragraphs must contain the three narrative stages');
  overview.paragraphs.forEach((paragraph, index) => text(paragraph, `storyOverview.paragraphs[${index}]`));
  validateRelativePath(overview.source, 'storyOverview.source');
}

function escapeHtml(value) {
  return value.replace(/[&<>"']/g, character => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[character]);
}

/** Build the opening synopsis as real HTML, before the JavaScript-driven game directory. */
export function compileHomeStory(html, overview) {
  const heroMarker = '<!-- HERO_STORY_LEAD -->';
  const storyMarker = '<!-- HOME_STORY_OVERVIEW -->';
  if (overview === undefined && !html.includes(heroMarker) && !html.includes(storyMarker)) return html;
  validateStoryOverview(overview);
  requireValue(html.split(heroMarker).length === 2 && html.split(storyMarker).length === 2,
    'Homepage story requires exactly one hero marker and one story placeholder');
  const story = `<section class="section prologue-section" id="prologue" aria-labelledby="prologue-title">
      <div class="prologue-heading"><span class="status status-planned">主线规划</span>
        <h2 id="prologue-title">${escapeHtml(overview.title)}</h2>
        <p class="prologue-lead">${escapeHtml(overview.lead)}</p>
        <a class="quiet-link" href="#story">沿着章节展开 <span aria-hidden="true">↓</span></a>
      </div>
      <div class="prologue-copy">${overview.paragraphs.map(paragraph => `<p>${escapeHtml(paragraph)}</p>`).join('\n')}
        <p class="prologue-note">${escapeHtml(overview.note)}</p>
      </div>
    </section>`;
  return html.replace(heroMarker, () => escapeHtml(overview.heroLead)).replace(storyMarker, () => story);
}

function uniqueRows(rows, label) {
  requireValue(Array.isArray(rows) && rows.length > 0, `${label} must be a nonempty array`);
  const ids = new Set();
  for (const [index, row] of rows.entries()) {
    object(row, `${label}[${index}]`);
    requireValue(typeof row.id === 'string' && /^[a-z][a-z0-9-]*$/.test(row.id), `${label}[${index}].id must be a lowercase slug`);
    requireValue(!ids.has(row.id), `${label} has duplicate ID: ${row.id}`);
    ids.add(row.id);
  }
  return ids;
}

/** Enforce portable, canonical paths before resolving anything on disk. */
export function validateRelativePath(value, label = 'path') {
  requireValue(typeof value === 'string' && value.length > 0
    && !/[\\\u0000-\u001f:?*<>|#%]/.test(value)
    && !path.posix.isAbsolute(value)
    && value.split('/').every((part) => part.length > 0 && part !== '.' && part !== '..' && !/[. ]$/.test(part)),
  `${label} must be a canonical repository-relative path`);
  return value;
}

/** Validate editorial contracts and return every explicit source reference. */
export function validateContent(gameplay, media) {
  object(gameplay, 'gameplay');
  date(gameplay.updatedAt, 'updatedAt');
  fields(gameplay.intro, ['title', 'description'], 'intro');
  const featureIds = uniqueRows(gameplay.features, 'features');
  uniqueRows(gameplay.ships, 'ships');
  const mediaIds = uniqueRows(media, 'media');
  const references = new Set();
  if (gameplay.storyOverview !== undefined) {
    validateStoryOverview(gameplay.storyOverview);
    references.add(gameplay.storyOverview.source);
  }
  const fileNames = new Set();

  for (const row of media) {
    const label = `media.${row.id}`;
    fields(row, ['fileName', 'caption', 'alt'], label);
    requireValue(MEDIA_KINDS.has(row.kind), `${label}.kind must be art, render, game, or experiment`);
    requireValue(/^[a-zA-Z0-9][a-zA-Z0-9._-]*\.png$/i.test(row.fileName), `${label}.fileName must be a plain PNG filename`);
    const portableName = row.fileName.toLowerCase();
    requireValue(!fileNames.has(portableName), `media has duplicate fileName: ${row.fileName}`);
    fileNames.add(portableName);
    references.add(validateRelativePath(row.sourcePath, `${label}.sourcePath`));
    requireValue(/\.png$/i.test(row.sourcePath), `${label}.sourcePath must reference a PNG image`);
    references.add(validateRelativePath(row.sourceDocument, `${label}.sourceDocument`));
    requireValue(Number.isInteger(row.width) && row.width > 0 && Number.isInteger(row.height) && row.height > 0,
      `${label} width and height must be positive integers`);
    if ('gallery' in row) requireValue(typeof row.gallery === 'boolean', `${label}.gallery must be a boolean`);
    if ('galleryTitle' in row) text(row.galleryTitle, `${label}.galleryTitle`);
    if ('galleryOrder' in row) requireValue(Number.isInteger(row.galleryOrder) && row.galleryOrder >= 0 && row.galleryOrder <= 1000,
      `${label}.galleryOrder must be an integer from 0 to 1000`);
  }

  for (const row of gameplay.features) {
    const label = `features.${row.id}`;
    fields(row, ['title', 'category', 'summary', 'description', 'tradeoff'], label);
    status(row.status, `${label}.status`);
    requireValue(Array.isArray(row.playerChoices) && row.playerChoices.length === 3, `${label}.playerChoices must contain exactly three choices`);
    row.playerChoices.forEach((choice, index) => text(choice, `${label}.playerChoices[${index}]`));
    requireValue(Array.isArray(row.related), `${label}.related must be an array`);
    requireValue(new Set(row.related).size === row.related.length, `${label}.related contains duplicate IDs`);
    for (const id of row.related) requireValue(featureIds.has(id), `${label}.related has unknown feature ID: ${id}`);
    requireValue(mediaIds.has(row.imageKey), `${label}.imageKey has unknown media ID: ${row.imageKey}`);
    references.add(validateRelativePath(row.source, `${label}.source`));
  }

  for (const row of gameplay.ships) {
    const label = `ships.${row.id}`;
    fields(row, ['name', 'role', 'strength', 'weakness', 'tactic'], label);
    status(row.status, `${label}.status`);
    for (const name of ['category', 'crew', 'counterplay']) {
      if (row[name] !== undefined) text(row[name], `${label}.${name}`);
    }
    if (row.source !== undefined) references.add(validateRelativePath(row.source, `${label}.source`));
  }

  requireValue(Array.isArray(gameplay.chapters) && gameplay.chapters.length > 0, 'chapters must be a nonempty array');
  for (const [index, row] of gameplay.chapters.entries()) {
    const label = `chapters[${index}]`;
    fields(row, ['year', 'title', 'protagonist', 'description', 'mechanic'], label);
    requireValue(row.status === 'planned', `${label}.status must be planned`);
  }

  requireValue(Array.isArray(gameplay.updates) && gameplay.updates.length > 0, 'updates must be a nonempty array');
  for (const [index, row] of gameplay.updates.entries()) {
    const label = `updates[${index}]`;
    fields(row, ['title', 'description'], label);
    date(row.date, `${label}.date`);
    status(row.status, `${label}.status`);
    references.add(validateRelativePath(row.source, `${label}.source`));
  }
  return references;
}

function sha256(bytes) {
  return createHash('sha256').update(bytes).digest('hex');
}

function sortedSources(sources) {
  return [...sources].sort((left, right) => left.path < right.path ? -1 : left.path > right.path ? 1 : 0);
}

export function revisionForSources(sources) {
  return sha256(JSON.stringify(sortedSources(sources)));
}

function inside(root, candidate) {
  const relative = path.relative(root, candidate);
  return relative === '' || (!relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative));
}

async function readSource(repoRoot, relativePath) {
  validateRelativePath(relativePath);
  const absolutePath = path.resolve(repoRoot, ...relativePath.split('/'));
  let actualPath;
  try {
    actualPath = await realpath(absolutePath);
  } catch (error) {
    throw new Error(`Missing source file: ${relativePath} (${error.code})`);
  }
  requireValue(inside(repoRoot, actualPath), `Source resolves outside repository: ${relativePath}`);
  requireValue((await lstat(actualPath)).isFile(), `Source is not a regular file: ${relativePath}`);
  return readFile(actualPath);
}

function parseJson(bytes, name) {
  try {
    return JSON.parse(bytes.toString('utf8').replace(/^\uFEFF/, ''));
  } catch (error) {
    throw new Error(`Invalid JSON in ${name}: ${error.message}`);
  }
}

function verifyPng(bytes, media) {
  requireValue(bytes.length >= 24 && bytes.subarray(0, 8).equals(PNG_SIGNATURE)
    && bytes.readUInt32BE(8) === 13 && bytes.toString('ascii', 12, 16) === 'IHDR',
  `${media.sourcePath} is not a PNG image`);
  requireValue(bytes.readUInt32BE(16) === media.width && bytes.readUInt32BE(20) === media.height,
    `${media.sourcePath} dimensions differ from media.json (${media.width}x${media.height})`);
}

async function existingArtifacts(directory, prefix = '') {
  const files = new Map();
  let entries;
  try {
    const info = await lstat(directory);
    requireValue(!info.isSymbolicLink() && info.isDirectory(), `Output path must be a real directory: ${directory}`);
    entries = await readdir(directory, { withFileTypes: true });
  } catch (error) {
    if (error.code === 'ENOENT') return files;
    throw error;
  }
  for (const entry of entries) {
    const key = `${prefix}${entry.name}`;
    requireValue(!entry.isSymbolicLink(), `Output contains a symbolic link: ${key}`);
    if (entry.isDirectory()) {
      for (const [nestedKey, bytes] of await existingArtifacts(path.join(directory, entry.name), `${key}/`)) files.set(nestedKey, bytes);
    } else {
      requireValue(entry.isFile(), `Output contains an unsupported entry: ${key}`);
      files.set(key, await readFile(path.join(directory, entry.name)));
    }
  }
  return files;
}

export function compareArtifacts(expected, actual) {
  const problems = [];
  for (const [name, bytes] of expected) {
    if (!actual.has(name)) problems.push(`missing: ${name}`);
    else if (!bytes.equals(actual.get(name))) problems.push(`changed: ${name}`);
  }
  for (const name of actual.keys()) if (!expected.has(name)) problems.push(`unexpected: ${name}`);
  return problems.sort();
}

function decodeAttribute(value) {
  const entities = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", colon: ':', tab: '\t', newline: '\n' };
  return value.replace(/&(?:#(\d+)|#x([a-f\d]+)|(amp|lt|gt|quot|apos|colon|tab|newline));/gi, (match, decimal, hex, named) => {
    if (named) return entities[named.toLowerCase()];
    const codepoint = Number.parseInt(decimal ?? hex, decimal ? 10 : 16);
    return codepoint > 0 && codepoint <= 0x10ffff ? String.fromCodePoint(codepoint) : '\ufffd';
  });
}

/** Validate the static HTML against the files and image records actually shipped. */
export function validatePresentation(html, media, outputNames) {
  const outputs = new Set(outputNames);
  const mediaIds = new Set(media.map((row) => row.id));
  const markup = html.replace(/<!--[\s\S]*?-->/g, '');
  // This small tokenizer accepts quoted or unquoted attributes, including > in quotes.
  // Raw script/style/text contents are skipped so strings are never treated as markup.
  const tags = /<(\/?)([a-z][a-z\d:-]*)\b((?:[^"'<>]|"[^"]*"|'[^']*')*)>/gi;
  let rawTextTag;
  for (const [, closing, originalTag, attributeText] of markup.matchAll(tags)) {
    const tag = originalTag.toLowerCase();
    if (rawTextTag) {
      if (closing && tag === rawTextTag) rawTextTag = undefined;
      continue;
    }
    if (closing) continue;
    const attributes = new Map();
    const attributePattern = /(?:^|\s)([^\s"'<>/=]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+)))?/g;
    for (const [, name, doubleQuoted, singleQuoted, unquoted] of attributeText.matchAll(attributePattern)) {
      const key = name.toLowerCase();
      if (['src', 'href', 'data-open-image'].includes(key)) requireValue(!attributes.has(key), `Duplicate presentation reference attribute: ${key}`);
      attributes.set(key, decodeAttribute(doubleQuoted ?? singleQuoted ?? unquoted ?? '').trim());
    }
    if (attributes.has('data-open-image')) {
      const id = attributes.get('data-open-image');
      requireValue(mediaIds.has(id), `Presentation has unknown data-open-image ID: ${id}`);
    }
    for (const key of ['src', 'href']) {
      if (!attributes.has(key)) continue;
      const reference = attributes.get(key);
      requireValue(tag !== 'base', 'Presentation cannot use a base reference that changes local resource resolution');
      requireValue(reference.length > 0, `Presentation has an empty ${key} resource reference`);
      if (reference.startsWith('#')) continue;
      if (key === 'href' && tag === 'link' && attributes.get('rel')?.toLowerCase().split(/\s+/).includes('icon') && /^data:/i.test(reference)) continue;
      // Ordinary article links can leave the site; executable, image, and font dependencies cannot.
      if (key === 'href' && tag === 'a' && /^https?:\/\//i.test(reference)) continue;
      requireValue(!/^(?:[a-z][a-z\d+.-]*:|\/\/)/i.test(reference), `Presentation contains an external resource dependency: ${reference}`);
      const resource = reference.split(/[?#]/, 1)[0].replace(/^\.\//, '');
      validateRelativePath(resource, 'Presentation resource reference');
      requireValue(outputs.has(resource), `Presentation resource is missing from output: ${resource}`);
    }
    if (['script', 'style', 'textarea', 'title'].includes(tag)) rawTextTag = tag;
  }
}

/** All outputs are computed before --check reads or build writes dist. */
export async function buildSite({ repoRoot = REPO_ROOT, check = false } = {}) {
  repoRoot = await realpath(repoRoot);
  const siteRoot = path.join(repoRoot, SITE_PATH);
  const actualSiteRoot = await realpath(siteRoot);
  requireValue(inside(repoRoot, actualSiteRoot) && actualSiteRoot === siteRoot, 'Site directory must be a real directory inside the repository');
  const inputs = new Map();
  const readInput = async (name) => {
    if (!inputs.has(name)) inputs.set(name, await readSource(repoRoot, name));
    return inputs.get(name);
  };
  const gameplayPath = `${SITE_PATH}/content/gameplay.json`;
  const mediaPath = `${SITE_PATH}/content/media.json`;
  const gameplay = parseJson(await readInput(gameplayPath), gameplayPath);
  const media = parseJson(await readInput(mediaPath), mediaPath);
  const references = validateContent(gameplay, media);
  const expected = new Map();
  for (const name of ['index.html', 'styles.css', 'app.js']) expected.set(name, await readInput(`${SITE_PATH}/src/${name}`));
  expected.set('index.html', Buffer.from(compileHomeStory(expected.get('index.html').toString('utf8'), gameplay.storyOverview)));
  await readInput(`${SITE_PATH}/scripts/build.mjs`);
  for (const name of [...references].sort()) await readInput(name);
  const publicMedia = {};
  for (const row of media) {
    const bytes = inputs.get(row.sourcePath);
    verifyPng(bytes, row);
    expected.set(`assets/${row.fileName}`, bytes);
    publicMedia[row.id] = { ...row, src: `assets/${row.fileName}`, sha256: sha256(bytes), bytes: bytes.length };
  }
  const sources = sortedSources([...inputs].map(([name, bytes]) => ({ path: name, sha256: sha256(bytes), bytes: bytes.length })));
  const revisionHash = revisionForSources(sources);
  const data = { ...gameplay, media: publicMedia, build: { revisionHash } };
  const safeJson = JSON.stringify(data, null, 2).replace(/</g, '\\u003c').replace(/\u2028/g, '\\u2028').replace(/\u2029/g, '\\u2029');
  expected.set('data.js', Buffer.from(`// Generated by scripts/build.mjs. Edit content sources, then rebuild.\nwindow.MING_ARMADA = ${safeJson};\n`));
  validatePresentation(expected.get('index.html').toString('utf8'), media, [...expected.keys(), 'manifest.json']);
  const outputs = [...expected].map(([name, bytes]) => ({ path: name, sha256: sha256(bytes), bytes: bytes.length }));
  expected.set('manifest.json', Buffer.from(`${JSON.stringify({ version: 1, revisionHash, sources, outputs: sortedSources(outputs) }, null, 2)}\n`));

  const dist = path.join(siteRoot, 'dist');
  const actual = await existingArtifacts(dist);
  const problems = compareArtifacts(expected, actual);
  if (check) {
    requireValue(problems.length === 0, `Website output is stale; rebuild with node ${SITE_PATH}/scripts/build.mjs:\n${problems.join('\n')}`);
  } else {
    const unexpected = problems.filter((problem) => problem.startsWith('unexpected:'));
    requireValue(unexpected.length === 0, `Unexpected output files require explicit review; build never deletes files:\n${unexpected.join('\n')}`);
    await mkdir(path.join(dist, 'assets'), { recursive: true });
    for (const [name, bytes] of expected) {
      if (!actual.get(name)?.equals(bytes)) await writeFile(path.join(dist, ...name.split('/')), bytes);
    }
  }
  return { revisionHash, outputCount: expected.size, mediaCount: media.length, sourceCount: sources.length, check };
}

if (process.argv[1] && path.resolve(process.argv[1]) === SCRIPT_PATH) {
  const args = process.argv.slice(2);
  if (args.some((argument) => argument !== '--check') || args.length > 1) {
    console.error('Usage: node web/gameplay-journal/scripts/build.mjs [--check]');
    process.exitCode = 1;
  } else {
    try {
      const result = await buildSite({ check: args.includes('--check') });
      console.log(`${result.check ? 'Checked' : 'Built'} gameplay journal: ${result.outputCount} files, ${result.mediaCount} images, ${result.sourceCount} source files; revision ${result.revisionHash.slice(0, 12)}.`);
    } catch (error) {
      console.error(error.message);
      process.exitCode = 1;
    }
  }
}
