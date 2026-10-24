import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { projectRoot, storyPath } from './build-zheng-story.mjs';

export const screenplayPath = path.join(projectRoot, 'docs/narrative/zheng-zhilong-campaign-script-2026-10-21.md');
const list = value => Array.isArray(value) ? value : [];
const present = value => typeof value === 'string' && value.trim().length > 0;
const labels = {
  name: '名称', role: '身份', desire: '欲望', arc: '人物变化',
  plant: '埋入', payoff: '回收', fixed: '固定历史结局', personal: '人物结局',
  lastImage: '最后画面', want: '欲求', obstacle: '阻碍', decision: '既定行动',
  result: '直接结果', next: '如何迫出下一步', title: '标题', description: '说明',
  setup: '起点', development: '发展', resolution: '收束',
};

// Keep all structured editorial material rather than shortening it into a table.
function fullValue(value, headingLevel = 3) {
  if (value === undefined || value === null) return '';
  if (typeof value === 'string') return value;
  if (typeof value !== 'object') return String(value);
  if (Array.isArray(value)) return value.map(item => fullValue(item, headingLevel)).filter(Boolean).join('\n\n');
  return Object.entries(value).map(([key, item]) => {
    if (item === undefined || item === null) return '';
    const label = labels[key] ?? key;
    if (typeof item === 'object') return `${'#'.repeat(Math.min(6, headingLevel))} ${label}\n\n${fullValue(item, headingLevel + 1)}`;
    return `**${label}：**${String(item)}`;
  }).filter(Boolean).join('\n\n');
}

const sourceLine = source => `[${source.title}](${source.url})`;
const fold = (title, body) => `<details>\n<summary>${title}</summary>\n\n${body}\n\n</details>`;

export function renderScreenplay(story,{imageBase='zheng-zhilong/'}={}) {
  if (!story || typeof story !== 'object' || !Array.isArray(story.acts)) {
    throw new TypeError('Screenplay source must be the story JSON with acts.');
  }
  const partLabel = story.narrativeContract?.edition === 'historical-reboot' ? '部' : '幕';
  const out = [
    `# ${story.title ?? '海上明旗 · 郑芝龙主线'}`,
    story.narrativeContract?.edition === 'historical-reboot' ? (story.version==='historical-reboot-illustrated-2026-10-24'?'> 根据历史记录重新创作的小说与场景剧本。私人对白、具体现场与衔接为文学重建；依据和争议逐章列明。本版采用新生成的当代插图，用于场景想象，不代表历史现场或人物真容。':'> 根据历史记录重新创作的小说与场景剧本。私人对白、具体现场与衔接为文学重建；依据和争议逐章列明。本版为文字新作，没有采用旧版插图。') : '> 历史小说剧本与当代生成插图。本文由唯一剧本 JSON 完整生成，编辑应修改 JSON 后重新生成。结构校验不能代替文学或史实验收；具体虚构战事依各场说明区分。',
  ];
  if (present(story.subtitle)) out.push(story.subtitle);
  if (story.version !== undefined && story.version !== null) out.push(`版本：${story.version}`);
  if (present(story.logline)) out.push(story.logline);
  if (story.prologue) out.push(fullValue(story.prologue));

  out.push(`按${partLabel}阅读；章首只交代眼前困境。梗概、对白摘记和编辑解析含情节结果，默认折叠。`);

  const sources = new Map();
  for (const [actIndex, act] of story.acts.entries()) {
    out.push(`## 第${['一', '二', '三', '四', '五', '六'][actIndex] ?? actIndex + 1}${partLabel} · ${act.title}`);
    out.push(`幕 ID：${act.id}　｜　年代：${act.years}`);
    if (present(act.readerHook)) out.push(`> ${act.readerHook}`);
    if ((act.illustrationStatus ?? story.illustrationStatus) !== 'needs-redraw' && present(act.cover)) out.push(`![${act.title}](${imageBase}${act.cover})`);
    if (present(act.synopsis)) out.push(fold('本幕梗概（含情节结果）',act.synopsis));
    if (act.prologue) out.push(fullValue(act.prologue));
    for (const scene of list(act.scenes)) {
      out.push(`<a id="${scene.id}"></a>\n\n### ${scene.title}`);
      out.push(`年代：${scene.year}　｜　地点：${scene.location}`);
      if (present(scene.readerTeaser)) out.push(`> ${scene.readerTeaser}`);
      if (present(scene.summary)) out.push(fold('本场梗概（含情节结果）',scene.summary));
      // The prose and spoken lines are rendered without limits or summarization.
      const status = scene.illustrationStatus ?? act.illustrationStatus ?? story.illustrationStatus;
      if (status !== 'needs-redraw' && present(scene.image)) out.push(`![${scene.imageCaption || scene.title}](${imageBase}${scene.image})`);
      for (const [paragraphIndex, paragraph] of list(scene.paragraphs).entries()) {
        out.push(paragraph);
        for (const frame of list(scene.illustrations).filter(frame => frame.afterParagraph === paragraphIndex + 1)) {
          if ((frame.illustrationStatus ?? status) !== 'needs-redraw') out.push(`![${frame.alt||frame.caption}](${imageBase}${frame.image})${frame.alt?'\n\n*'+frame.caption+'*':''}`);
        }
      }
      if (list(scene.dialogue).length) {
        out.push(fold('对白摘记（辅助稿；含情节）',scene.dialogue.map(line=>`**${line.speaker}：**${line.text}`).join('\n\n')));
      }
      if (list(scene.choices).length) {
        out.push('#### 玩法备选（不替代正文既定行动）');
        for (const choice of scene.choices) {
          out.push(`**${choice.label}**${present(choice.id) ? `（${choice.id}）` : ''}`);
          if (present(choice.consequence)) out.push(choice.consequence);
          const { id, label, consequence, ...rest } = choice;
          if (Object.keys(rest).length) out.push(fullValue(rest, 5));
        }
      }
      out.push('#### 史实与创作边界');
      out.push(`层级：${scene.history?.level ?? '未标注'}`);
      if (present(scene.history?.note)) out.push(scene.history.note);
      for (const source of list(scene.history?.sources)) {
        out.push(`- ${sourceLine(source)}`);
        sources.set(`${source.title}\u0000${source.url}`, source);
      }
      if (status === 'needs-redraw') out.push('插图状态：旧图冻结保留；本场已改写，须重画后另行验收。');
    }
    if (present(act.nextHook)) {
      out.push(`> ${act.nextHook}`);
      const nextAct=story.acts[actIndex+1];
      if (nextAct?.scenes?.[0]) out.push(`[继续阅读 · ${nextAct.title}](#${nextAct.scenes[0].id})`);
    }
  }

  out.push('<details>\n<summary>人物、伏笔与结局解析（含全剧结果）</summary>');
  out.push('## 人物');
  for (const character of list(story.characters)) {
    out.push(`### ${character.name ?? '未命名人物'}`);
    const { name, ...details } = character;
    out.push(fullValue(details, 4));
  }
  out.push('## 贯穿线与伏笔回收');
  for (const [index, thread] of list(story.plotThreads).entries()) {
    if (thread && typeof thread === 'object' && !Array.isArray(thread)) {
      out.push(`### ${thread.name ?? thread.title ?? `线索 ${index + 1}`}`);
      const { name, title, ...details } = thread;
      out.push(fullValue(details, 4));
    } else out.push(fullValue(thread));
  }
  if (story.plotThreads && !Array.isArray(story.plotThreads)) out.push(fullValue(story.plotThreads));
  out.push('## 结局');
  out.push(fullValue(story.ending));
  out.push('</details>');

  out.push('## 来源汇编');
  for (const source of list(story.sources)) sources.set(`${source.title}\u0000${source.url}`, source);
  for (const source of sources.values()) out.push(`- ${sourceLine(source)}`);
  if (story.sourceNotes) out.push(fullValue(story.sourceNotes));

  out.push('## 编辑因果附录');
  out.push('<details>\n<summary>逐场因果与悬念兑现索引（含全剧结果）</summary>');
  out.push('以下逐场列出作者填写的欲求、阻碍、决定、结果和下一步。字段齐全仅表示编辑信息完整，不能证明事件成立、情绪有效或文学验收通过。');
  for (const act of story.acts) {
    for (const scene of list(act.scenes)) {
      out.push(`### ${scene.id} · ${scene.title}`);
      out.push(fullValue(scene.dramaticBeat, 4) || '尚未填写 dramaticBeat。');
      if (scene.suspense) out.push(fullValue(scene.suspense, 4));
    }
  }
  out.push('</details>');
  return `${out.filter(part => part !== undefined && part !== null && part !== '').join('\n\n')}\n`;
}

export async function writeScreenplay() {
  const story = JSON.parse((await readFile(storyPath, 'utf8')).replace(/^\uFEFF/, ''));
  const output = renderScreenplay(story);
  await writeFile(screenplayPath, output, 'utf8');
  return { screenplayPath, bytes: Buffer.byteLength(output), acts: story.acts.length,
    scenes: story.acts.reduce((count, act) => count + list(act.scenes).length, 0) };
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    if (process.argv.length > 2) throw new Error('Usage: node tools/render-zheng-screenplay.mjs');
    const result = await writeScreenplay();
    console.log(`Rendered ${path.relative(projectRoot, result.screenplayPath)} (${result.bytes} bytes; ${result.acts} acts; ${result.scenes} scenes).`);
  } catch (error) {
    console.error(`Screenplay render failed: ${error.message}`);
    process.exitCode = 1;
  }
}
