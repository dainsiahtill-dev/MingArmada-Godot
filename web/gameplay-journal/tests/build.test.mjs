import assert from 'node:assert/strict';
import test from 'node:test';
import * as builder from '../scripts/build.mjs';

const { compareArtifacts, validateContent, validateRelativePath, revisionForSources } = builder;

function content() {
  return {
    updatedAt: '2026-10-29',
    intro: { title: '海上', description: '玩法记录' },
    features: [{
      id: 'fire', title: '火攻', category: '海战', status: 'playable',
      summary: '如何交锋', description: '独立对局', playerChoices: ['接近', '投送', '扑救'],
      tradeoff: '需要人手', related: [], imageKey: 'battle', source: 'docs/fire.md',
    }],
    ships: [{ id: 'fuchuan', name: '福船', role: '综合', status: 'playable', strength: '承载', weakness: '转向', tactic: '守位' }],
    chapters: [{ year: '1646', title: '分途', protagonist: '父子', description: '交棒', mechanic: '交接', status: 'planned' }],
    updates: [{ date: '2026-10-29', title: '火攻', description: '独立入口', status: 'playable', source: 'docs/fire.md' }],
  };
}

function images() {
  return [{ id: 'battle', sourcePath: 'docs/images/battle.png', fileName: 'battle.png', kind: 'game', caption: '独立海战', alt: '两船交锋', sourceDocument: 'docs/fire.md', width: 1600, height: 900 }];
}

test('valid content returns the exact referenced repository files', () => {
  assert.deepEqual([...validateContent(content(), images())].sort(), ['docs/fire.md', 'docs/images/battle.png']);
});

test('duplicate feature and media identities are rejected before output can overwrite records', () => {
  const gameplay = content();
  gameplay.features.push(structuredClone(gameplay.features[0]));
  assert.throws(() => validateContent(gameplay, images()), /duplicate.*fire/i);
  assert.throws(() => validateContent(content(), [...images(), ...images()]), /duplicate.*battle/i);
});

test('repository references cannot escape through traversal, absolute paths, URLs, or Windows separators', () => {
  for (const value of ['../secret.png', 'docs/../../secret.png', '/tmp/secret.png', 'C:/secret.png', 'https://site/image.png', 'docs\\..\\secret.png', 'docs/./image.png', 'docs//image.png']) {
    assert.throws(() => validateRelativePath(value, 'reference'), /repository-relative/i, value);
  }
  assert.equal(validateRelativePath('docs/images/battle.png', 'reference'), 'docs/images/battle.png');
});

test('unknown related feature IDs and image IDs fail instead of silently disappearing', () => {
  const gameplay = content();
  gameplay.features[0].related = ['missing'];
  assert.throws(() => validateContent(gameplay, images()), /unknown.*missing/i);
  gameplay.features[0].related = [];
  gameplay.features[0].imageKey = 'missing';
  assert.throws(() => validateContent(gameplay, images()), /unknown.*missing/i);
});

test('invalid calendar dates, status values, player choices, and output names fail validation', () => {
  const badDate = content();
  badDate.updatedAt = '2026-02-30';
  assert.throws(() => validateContent(badDate, images()), /date/i);
  const badStatus = content();
  badStatus.features[0].status = 'finished';
  assert.throws(() => validateContent(badStatus, images()), /status/i);
  const choices = content();
  choices.features[0].playerChoices.pop();
  assert.throws(() => validateContent(choices, images()), /three|3/i);
  const media = images();
  media[0].fileName = '../battle.png';
  assert.throws(() => validateContent(content(), media), /fileName/i);
});

test('source revision is independent of collection order and detects changed source documents', () => {
  const original = [
    { path: 'src/app.js', sha256: 'a'.repeat(64), bytes: 15 },
    { path: 'docs/fire.md', sha256: 'b'.repeat(64), bytes: 30 },
  ];
  assert.equal(revisionForSources(original), revisionForSources([...original].reverse()));
  const changed = structuredClone(original);
  changed[1].sha256 = 'c'.repeat(64);
  assert.notEqual(revisionForSources(original), revisionForSources(changed));
});

test('artifact comparison catches missing files, tampered bytes, and unallowlisted leftovers', () => {
  const expected = new Map([
    ['index.html', Buffer.from('<html></html>')],
    ['data.js', Buffer.from('window.MING_ARMADA = {};')],
    ['assets/battle.png', Buffer.from('original image bytes')],
  ]);
  const actual = new Map([
    ['index.html', Buffer.from('<html></html>')],
    ['assets/battle.png', Buffer.from('tampered image bytes')],
    ['assets/old.png', Buffer.from('obsolete image')],
  ]);
  assert.deepEqual(compareArtifacts(expected, actual), [
    'changed: assets/battle.png',
    'missing: data.js',
    'unexpected: assets/old.png',
  ]);
  assert.deepEqual(compareArtifacts(expected, new Map(expected)), []);
});

test('optional gallery metadata accepts curated ordering and rejects values that break presentation', () => {
  const media = images();
  Object.assign(media[0], { gallery: false, galleryTitle: '海战画面', galleryOrder: 10 });
  assert.doesNotThrow(() => validateContent(content(), media));
  for (const invalid of [{ gallery: 'false' }, { galleryTitle: '  ' }, { galleryOrder: -1 }, { galleryOrder: 1001 }, { galleryOrder: 1.5 }]) {
    const invalidMedia = images();
    Object.assign(invalidMedia[0], invalid);
    assert.throws(() => validateContent(content(), invalidMedia), /gallery/);
  }
});

test('presentation validates real local resource names and static gallery entry IDs', () => {
  assert.equal(typeof builder.validatePresentation, 'function', 'presentation validator must be exported');
  const html = `<link rel="icon" href="data:image/svg+xml,%3Csvg/%3E">
    <link rel="stylesheet" href="./styles.css"><script src='./data.js' defer></script>
    <script src=./app.js defer></script><a href="#gallery">图集</a>
    <button data-open-image="battle"><img src="./assets/battle.png" alt="海战"></button>`;
  const outputs = new Set(['index.html', 'styles.css', 'data.js', 'app.js', 'assets/battle.png']);
  assert.doesNotThrow(() => builder.validatePresentation(html, images(), outputs));
  assert.throws(() => builder.validatePresentation(html, images(), new Set([...outputs].filter((name) => name !== 'assets/battle.png'))), /assets\/battle\.png/);
  assert.throws(() => builder.validatePresentation(html.replace('assets/battle.png', 'assets/renamed.png'), images(), outputs), /assets\/renamed\.png/);
  assert.throws(() => builder.validatePresentation(html.replace('data-open-image="battle"', 'data-open-image="missing"'), images(), outputs), /unknown.*missing/i);
});

test('presentation rejects remote dependencies while allowing ordinary external article links', () => {
  assert.equal(typeof builder.validatePresentation, 'function', 'presentation validator must be exported');
  const outputs = new Set(['styles.css', 'app.js']);
  for (const html of [
    '<img src="https://example.com/image.png">',
    '<script src="//example.com/app.js"></script>',
    '<link rel="stylesheet" href="https://fonts.googleapis.com/css?family=Font">',
    '<img src="../outside.png">',
    '<base href="./">',
  ]) assert.throws(() => builder.validatePresentation(html, images(), outputs), /resource|dependency|reference|base/i);
  assert.doesNotThrow(() => builder.validatePresentation('<a href="https://example.com/article">出处</a>', images(), outputs));
  assert.doesNotThrow(() => builder.validatePresentation('<!-- <img src="missing.png"> --><script src="./app.js"></script>', images(), outputs));
});

function storyOverview() {
  return { title: '一片海，两代人的航程', lead: '从生计到海疆', heroLead: '郑芝龙与郑成功的两代航程',
    paragraphs: ['郑芝龙从劫掠与贸易中聚起舰队。', '父子分途，视角交给郑成功。', '故事最终驶向台湾战役。'],
    status: 'planned', note: '主线规划，尚未接入试玩。', source: 'docs/campaign.md' };
}

test('homepage story is built before gameplay, with both protagonists visible without client JavaScript', () => {
  assert.equal(typeof builder.compileHomeStory, 'function');
  const overview = storyOverview();
  const template = '<main><p><!-- HERO_STORY_LEAD --></p><!-- HOME_STORY_OVERVIEW --><section id="ways"></section></main>';
  const html = builder.compileHomeStory(template, overview);
  assert.ok(html.includes(overview.heroLead));
  assert.ok(html.indexOf('id="prologue"') < html.indexOf('id="ways"'));
  for (const paragraph of overview.paragraphs) assert.ok(html.includes(paragraph));
  assert.ok(html.includes('主线规划'));
  assert.ok(html.includes(overview.note));
  const gameplay = content(); gameplay.storyOverview = overview;
  assert.ok(validateContent(gameplay, images()).has('docs/campaign.md'));
});

test('homepage story rejects lost placement and invalid content, and renders markup as prose', () => {
  assert.equal(typeof builder.compileHomeStory, 'function');
  const template = '<p><!-- HERO_STORY_LEAD --></p><!-- HOME_STORY_OVERVIEW -->';
  const overview = storyOverview();
  overview.paragraphs[0] = '<script>not executable</script> & a promise';
  const html = builder.compileHomeStory(template, overview);
  assert.ok(html.includes('&lt;script&gt;not executable&lt;/script&gt; &amp; a promise'));
  assert.ok(!html.includes('<script>'));
  assert.throws(() => builder.compileHomeStory('<main></main>', overview), /marker|placeholder/i);
  assert.throws(() => builder.compileHomeStory(template + '<!-- HOME_STORY_OVERVIEW -->', overview), /marker|placeholder/i);
  const gameplay = content(); gameplay.storyOverview = { ...overview, paragraphs: ['incomplete'] };
  assert.throws(() => validateContent(gameplay, images()), /paragraph/i);
});

test('homepage story keeps literal replacement tokens in editorial copy', () => {
  const overview = storyOverview();
  overview.heroLead = "literal $& $` $' $$";
  overview.paragraphs[0] = overview.heroLead;
  const template = '<p><!-- HERO_STORY_LEAD --></p><!-- HOME_STORY_OVERVIEW -->';
  const html = builder.compileHomeStory(template, overview);
  assert.ok(html.includes('literal $&amp; $` $&#39; $$'));
  assert.ok(!html.includes('HERO_STORY_LEAD'));
  assert.ok(!html.includes('HOME_STORY_OVERVIEW'));
});
