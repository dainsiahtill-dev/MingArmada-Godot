// 文学规则校验：机器合同管结构，本脚本管"第七稿改写圣经"里的文学约束。
// 两者分开记录；通过本脚本不等于文学验收通过。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const storyPath = path.join(root, 'docs/narrative/zheng-zhilong-story.json');
const biblePath = path.join(root, 'docs/narrative/rewrites/V7-REWRITE-BIBLE.md');
const baselinePath = path.join(root, 'docs/narrative/rewrites/baseline-v6-2026-10-22/story.json');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));

const story = readJson(storyPath);
if(story.narrativeContract?.edition==='historical-reboot'){
  console.error('此脚本专用于V7文学模板。新作请运行 tools/verify-zheng-reboot.mjs；文学质量须独立连读。');
  process.exit(2);
}
const bible = fs.readFileSync(biblePath, 'utf8');
const baseline = readJson(baselinePath);

const failures = [];
const warnings = [];
let checks = 0;
const check = (value, name, detail = '') => {
  checks++;
  if (!value) failures.push(detail ? `${name}: ${detail}` : name);
};

// 表格每行有多组“场次／段数”，空单元格必须保留，否则末行会错位。
const specCounts = new Map();
{
  const rows = bible.split('\n').filter(line => /^\s*\|/.test(line));
  for (const row of rows) {
    const cells = row.trim().split('|').slice(1, -1).map(cell => cell.trim());
    for (let index = 0; index + 1 < cells.length; index += 2) {
      if (!/^(?:yiguan_)?a\d+_s\d+$/.test(cells[index])) continue;
      const id = cells[index].startsWith('yiguan_') ? cells[index] : `yiguan_${cells[index]}`;
      const count = /^\d+$/.test(cells[index + 1]) ? Number(cells[index + 1]) : NaN;
      check(!specCounts.has(id), `${id}: 圣经段落规格唯一`);
      check(Number.isSafeInteger(count) && count > 0, `${id}: 圣经段落规格为正整数`);
      if (!specCounts.has(id)) specCounts.set(id, count);
    }
  }
}

// 已归档第六稿独立保护段数，防止正文和圣经同步误改后互相“通过”。
const baselineScenes = baseline.acts.flatMap(act => act.scenes);
const baselineMap = new Map(baselineScenes.map(scene => [scene.id, scene]));
check(baseline.version === 'v6-suspense-integrated-2026-10-22', '第六稿段落基线版本正确');
check(baselineScenes.length === 20 && baselineMap.size === 20, '第六稿段落基线恰有二十场');
check(specCounts.size === 20, '圣经段落规格恰有二十场', `实际 ${specCounts.size}`);
for (let act = 1; act <= 5; act++) {
  for (let scene = 1; scene <= 4; scene++) {
    const id = `yiguan_a${act}_s${scene}`;
    const original = baselineMap.get(id);
    check(Array.isArray(original?.paragraphs) && original.paragraphs.length >= 2, `${id}: 第六稿段落基线存在`);
    check(specCounts.get(id) === original?.paragraphs?.length,
      `${id}: 圣经段落数合第六稿基线`, `期望 ${original?.paragraphs?.length}，实际 ${specCounts.get(id)}`);
  }
}

const BANNED = ['机制', '状态', '流程', '系统', '创伤', '心理', '性格', '成长', '情绪', '效率', '逻辑', '博弈', '资源', '配置', '沟通', '决策', '复盘'];
// 直接总结主题或直接忏悔的句式。
const THEME_MARKERS = [
  '从此他', '他终于明白', '他终于懂', '他不再是', '他明白了这个', '他懂得了',
  '他感到愧疚', '他很痛苦', '他心里很', '他意识到', '他第一次意识到',
  '他对自己说', '他暗暗发誓', '他发誓', '他决定要改',
];
// 第一段应当是"正在发生的动作"，不能是交代背景或天气开场。
const BACKDROP_OPENERS = ['天刚亮', '天色', '黄昏，', '傍晚，', '清晨，', '那年', '这一年', '多年以后', '当时', '那一日，'];

const seenOpeners = new Map();
const seenMetaphorImages = new Map();

for (const act of story.acts) {
  for (const scene of act.scenes) {
    const tag = scene.id;
    const paragraphs = scene.paragraphs || [];

    // 1. 段落数：圣经规格与机器合同必须一致
    check(specCounts.has(tag), `${tag}: 圣经段落规格存在`);
    check(paragraphs.length === specCounts.get(tag), `${tag}: 段落数合圣经`, `期望 ${specCounts.get(tag)}，实际 ${paragraphs.length}`);
    check(paragraphs.length >= 2, `${tag}: 至少两段`);

    // 2. 禁语
    const body = paragraphs.join('\n');
    for (const word of BANNED) {
      check(!body.includes(word), `${tag}: 禁语「${word}」`, `第${paragraphs.findIndex(p => p.includes(word)) + 1}段`);
    }

    // 3. 主题直陈
    for (const marker of THEME_MARKERS) {
      const hit = paragraphs.findIndex(p => p.includes(marker));
      check(hit === -1, `${tag}: 主题直陈「${marker}」`, hit >= 0 ? `第${hit + 1}段` : '');
    }

    // 4. 末段不得是总结句：以句号／问号／叹号收尾且含主题词，或以"从此/他明白"开头
    const last = paragraphs[paragraphs.length - 1] || '';
    check(!THEME_MARKERS.some(m => last.includes(m)), `${tag}: 末段含主题直陈`, last.slice(0, 40));
    check(!/^(从此|他终于|他明白|他感到|他意识到)/.test(last), `${tag}: 末段以总结句开头`, last.slice(0, 30));

    // 5. 首段是动作，不是背景铺陈
    const first = paragraphs[0] || '';
    check(!BACKDROP_OPENERS.some(op => first.startsWith(op)), `${tag}: 首段为背景式开场`, first.slice(0, 30));
    check(!first.includes('那年') && !first.includes('多年以后'), `${tag}: 首段含回忆跳转`, first.slice(0, 30));

    // 6. 感官具体项 ≥ 6：统计感官词根出现次数（去重计）
    const sensoryRoots = ['冷', '热', '凉', '温', '烫', '痛', '疼', '酸', '麻', '咸', '苦', '甜', '香', '臭', '腥', '霉', '烟', '味', '声', '响', '响', '响', '静', '哑', '滑', '粗', '糙', '涩', '软', '硬', '沉', '轻', '潮', '湿', '干', '暗', '光', '影', '月', '日', '风', '雨', '浪', '绳', '缆', '帆', '墨', '油', '灰'];
    const distinct = new Set(sensoryRoots.filter(root2 => body.includes(root2)));
    check(distinct.size >= 6, `${tag}: 感官具体项偏少`, `命中 ${distinct.size} 类`);

    // 7. 对白：3—5 行，每行有 speaker/text，长度不过长
    const dialogue = scene.dialogue || [];
    check(dialogue.length >= 2, `${tag}: 对白至少两行`);
    check(dialogue.length >= 3, `${tag}: 对白宜三行以上`, `实际 ${dialogue.length}`);
    check(dialogue.length <= 6, `${tag}: 对白不过多`, `实际 ${dialogue.length}`);
    for (const [index, line] of dialogue.entries()) {
      check(!!line.speaker && !!line.text, `${tag}: 对白${index + 1}完整`);
      check((line.text || '').length <= 34, `${tag}: 对白${index + 1}过长`, `${(line.text || '').length} 字`);
    }
    // 对白里不得出现禁语
    for (const line of dialogue) {
      for (const word of BANNED) check(!(line.text || '').includes(word), `${tag}: 对白含禁语「${word}」`);
    }

    // 8. 跨场撞词：各场首句前半不得重复
    const openerKey = (first.slice(0, 8) || '').trim();
    if (openerKey) {
      if (seenOpeners.has(openerKey)) {
        warnings.push(`${tag}: 首句与 ${seenOpeners.get(openerKey)} 相似「${openerKey}」`);
      } else seenOpeners.set(openerKey, tag);
    }

    // 9. 明喻计数：全书每场至多两处
    const metaphorCount = (body.match(/像[^，。；！？]{1,12}(?=[，。；！？])/g) || []).length
      + (body.match(/仿佛|好像|似乎/g) || []).length;
    check(metaphorCount <= 6, `${tag}: 明喻偏多`, `${metaphorCount} 处`);

    // 10. 场次顺序与年份
    check(!!scene.year, `${tag}: 有年份`);
    check(!!scene.readerTeaser, `${tag}: 有公开引子`);
    check(!!scene.summary, `${tag}: 有梗概`);
    for (const key of ['want', 'obstacle', 'decision', 'result', 'next']) {
      check(!!scene.dramaticBeat?.[key], `${tag}: dramaticBeat.${key}`);
    }
  }
}

// 11. 全书级：种收分配表与正文对账
const THREADS = [
  { seed: '木筹', pattern: /木筹|旧筹|新筹|缺角/, plant: ['yiguan_a1_s4'], pay: ['yiguan_a4_s1', 'yiguan_a5_s1'] },
  { seed: '歪船图', pattern: /歪船图|船图|画.*船|那条船.*画/, plant: ['yiguan_a2_s1'], pay: ['yiguan_a4_s3', 'yiguan_a5_s3', 'yiguan_a5_s4'] },
  { seed: '工具箱', pattern: /工具箱/, plant: ['yiguan_a1_s2'], pay: ['yiguan_a3_s3', 'yiguan_a5_s4'] },
  { seed: '援旗', pattern: /援旗|赭黄|三角旗|起旗/, plant: ['yiguan_a3_s2'], pay: ['yiguan_a3_s3', 'yiguan_a4_s2'] },
  { seed: '账／航记', pattern: /航记|账本|账册|册子|那本账|账页/, plant: ['yiguan_a1_s3'], pay: ['yiguan_a3_s3', 'yiguan_a3_s4', 'yiguan_a5_s1'] },
  { seed: '银袋', pattern: /银袋|家用袋|那一袋|装钱/, plant: ['yiguan_a2_s4'], pay: ['yiguan_a3_s1', 'yiguan_a5_s4'] },
  { seed: '姓名木牌', pattern: /姓名木|木牌|写了姓名|写好姓名|那截木/, plant: ['yiguan_a2_s3'], pay: ['yiguan_a4_s3', 'yiguan_a5_s1'] },
  { seed: '铜扣', pattern: /铜扣/, plant: ['yiguan_a4_s3'], pay: ['yiguan_a4_s4', 'yiguan_a5_s2'] },
  { seed: '出入单', pattern: /出入单|家人.*单|名单|照这张单/, plant: ['yiguan_a4_s4'], pay: ['yiguan_a5_s1', 'yiguan_a5_s4'] },
];
const allScenes = story.acts.flatMap(act => act.scenes);
const sceneMap = new Map(allScenes.map(scene => [scene.id, scene]));
for (const thread of THREADS) {
  for (const id of thread.plant) {
    const scene = sceneMap.get(id);
    check(!!scene && thread.pattern.test(scene.paragraphs.join('')),
      `种收:「${thread.seed}」应在 ${id} 种下`, scene ? '正文未出现该物' : '场次缺失');
  }
  for (const id of thread.pay) {
    const scene = sceneMap.get(id);
    check(!!scene && thread.pattern.test(scene.paragraphs.join('')),
      `种收:「${thread.seed}」应在 ${id} 回收`, scene ? '正文未出现该物' : '场次缺失');
  }
}

// 12. 知情链：一官在第四幕之前不得承认看见援旗
for (const scene of allScenes) {
  const actNumber = Number(scene.id.match(/a(\d)_/)[1]);
  if (actNumber >= 4) continue;
  const body = scene.paragraphs.join('');
  const confessed = /看见[了]?旗|看见了那面旗|看见援旗/.test(body) && /承认|承认看|我说我看见/.test(body);
  check(!confessed, `${scene.id}: 第四幕前不得承认看旗`);
}

// 13. a3_s3 与 a4_s2 必须显见旗
for (const id of ['yiguan_a3_s3', 'yiguan_a4_s2']) {
  const scene = sceneMap.get(id);
  check(scene.paragraphs.join('').includes('旗'), `${id}: 须显见援旗`);
}
// a4_s2 须有"没有雾"的枢轴
check(sceneMap.get('yiguan_a4_s2').paragraphs.join('').includes('没有雾'), 'yiguan_a4_s2: 须有"这天没有雾"的枢轴');
// a3_s3 须有雾
check(sceneMap.get('yiguan_a3_s3').paragraphs.join('').includes('雾'), 'yiguan_a3_s3: 须有雾');

// 14. 一官的指示动作：手伸向账／单／册／册子，全书至少五次
let gestureCount = 0;
for (const scene of allScenes) {
  if (/按住[^。]{0,8}(单|册|账|簿|图|纸)|摊开[^。]{0,8}(单|册|账|簿|纸)|(账|册|簿|单)[^。]{0,10}(摊开|翻|合上|推过去|抽回|按)/.test(scene.paragraphs.join(''))) gestureCount++;
}
check(gestureCount >= 5, '全书: 一官"手伸向账册"的指示动作至少五次', `实际 ${gestureCount} 场`);

console.log(`文学规则校验：${checks - failures.length}/${checks} 通过；警告 ${warnings.length} 条。`);
for (const failure of failures) console.error(`  ✗ ${failure}`);
for (const warning of warnings) console.log(`  ! ${warning}`);
process.exitCode = failures.length ? 1 : 0;
