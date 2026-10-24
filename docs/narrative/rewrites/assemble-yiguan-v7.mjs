// 第七稿装配器：把二十场修订稿合回唯一内容源 docs/narrative/zheng-zhilong-story.json。
// 只替换文学正文与编辑字段；史注、图片、场次 ID、旧场映射一律沿用第六稿。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const finalDir = path.join(root, 'docs/narrative/rewrites/v7-scenes/final');
const storyPath = path.join(root, 'docs/narrative/zheng-zhilong-story.json');
const readJson = file => JSON.parse(fs.readFileSync(file, 'utf8').replace(/^﻿/, ''));

const story = readJson(storyPath);
const applied = [];
const missing = [];

for (const act of story.acts) {
  for (const scene of act.scenes) {
    const file = path.join(finalDir, `${scene.id}.json`);
    if (!fs.existsSync(file)) { missing.push(scene.id); continue; }
    const fresh = readJson(file);

    // 硬约束自检：段落数必须与第六稿一致，否则八张过程图的锚点会错位。
    if (fresh.paragraphs.length !== scene.paragraphs.length) {
      throw new Error(`${scene.id}: 段落数 ${fresh.paragraphs.length} ≠ 第六稿 ${scene.paragraphs.length}`);
    }
    // 标题、年份、地点是机器校验项与读者定位项，不许改。
    if (fresh.year && fresh.year !== scene.year) throw new Error(`${scene.id}: year 不得改动`);
    if (fresh.title && fresh.title !== scene.title) throw new Error(`${scene.id}: title 不得改动`);
    if (fresh.location && fresh.location !== scene.location) throw new Error(`${scene.id}: location 不得改动`);
    if (!Array.isArray(fresh.dialogue) || fresh.dialogue.length < 2) throw new Error(`${scene.id}: 对白不足两行`);
    for (const line of fresh.dialogue) {
      if (!line || !line.speaker || !line.text) throw new Error(`${scene.id}: 对白缺 speaker 或 text`);
    }
    for (const key of ['want', 'obstacle', 'decision', 'result', 'next']) {
      if (!fresh.dramaticBeat?.[key]) throw new Error(`${scene.id}: dramaticBeat.${key} 缺失`);
    }
    const banned = ['机制', '状态', '流程', '系统', '创伤', '心理', '性格', '成长', '情绪', '效率', '逻辑', '博弈', '资源', '配置', '沟通', '决策', '复盘'];
    const body = [...fresh.paragraphs, ...fresh.dialogue.map(l => l.text)].join('\n');
    const hits = banned.filter(word => body.includes(word));
    if (hits.length) throw new Error(`${scene.id}: 正文含禁用词 ${hits.join('、')}`);

    scene.paragraphs = fresh.paragraphs;
    scene.dialogue = fresh.dialogue;
    if (fresh.summary) scene.summary = fresh.summary;
    if (fresh.readerTeaser) scene.readerTeaser = fresh.readerTeaser;
    if (fresh.dramaticBeat) scene.dramaticBeat = fresh.dramaticBeat;
    if (fresh.currentCanon) scene.currentCanon = fresh.currentCanon;
    if (fresh.task) scene.task = fresh.task;
    applied.push(scene.id);
  }
}

if (missing.length) throw new Error(`缺少修订稿：${missing.join(', ')}`);

// 版本与说明
story.version = 'v7-literary-rewrite-2026-10-22';
story.illustrationStatusNote = '第七稿完成全篇正文重写：五幕二十场按《一官入海》第七稿改写圣经重新执笔，逐场经文学与连续性双路评审后修订，再经全卷连续性审校补修。配图仍沿用经来源归档的旧稿图片作情境参考，非新稿逐场新绘；不符的三场主图和一幅结尾舟影暂缓，不让旧画改变新剧情。';
if (!Array.isArray(story.sourceNotes)) story.sourceNotes = [];
story.sourceNotes.push('2026-10-22 第七稿全篇改写：依《一官入海》第七稿改写圣经（docs/narrative/rewrites/V7-REWRITE-BIBLE.md）重写五幕二十场正文。体例为每场按入场—器物—转折—代价—落像组织，段落数与第六稿完全一致以保持八张过程图的段落锚点。史实边界、人物连续性、知情链与图片引用状态均未改动。');

fs.writeFileSync(storyPath, `${JSON.stringify(story, null, 2)}\n`, 'utf8');
console.log(`装配完成：${applied.length} 场已更新 → ${path.relative(root, storyPath)}`);
