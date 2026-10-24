import {renderScreenplay} from './render-zheng-screenplay.mjs';

export function editorialOutputDirectory(story) {
  const report=story.editorialRevision?.report||'reboot-2026-10-23/DELIVERY.md';
  if(!/^[a-z0-9-]+\/DELIVERY\.md$/.test(report)) throw new Error('Editorial report must stay in one named narrative workspace');
  return 'docs/narrative/'+report.slice(0,-'/DELIVERY.md'.length);
}

export function renderRebootExports(story) {
  if(story.narrativeContract?.edition!=='historical-reboot') throw new Error('Independent historical edition required');
  const nums=['一','二','三','四','五','六'],illustrated=story.version==='historical-reboot-illustrated-2026-10-24';
  const novel=[`# ${story.title}`,story.subtitle,'> 历史小说。事件依据与争议见同目录完整剧本的逐章史注；私人对白、感官与未留记录的衔接是文学重建。'];
  const game=[`# ${story.title} · 游戏叙事场景稿`,'> 这是新作的制作输入：场面目标、行动、后果与对白。尚未实现游戏任务、分支、过场或战斗。具体历史结果固定，玩家可操作的范围须另做设计和实测。'];
  const rows=['|章|当下目标|行动及直接后果|怎样迫出后事|','|---|---|---|---|'];
  const cell=value=>value.replaceAll('|','／').replaceAll('\n',' ');
  for(const [i,a] of story.acts.entries()) {
    novel.push(`## 第${nums[i]}部 · ${a.title}`);
    game.push(`## 第${nums[i]}部 · ${a.title}`);
    for(const s of a.scenes) {
      novel.push(`### ${s.title}`,`${s.year} · ${s.location}`);
      for(const [index,paragraph] of s.paragraphs.entries()){
        novel.push(paragraph);
        if(illustrated)for(const frame of (s.illustrations||[]).filter(frame=>frame.afterParagraph===index+1&&frame.illustrationStatus==='ready'))novel.push(`![${frame.alt||frame.caption}](${frame.image})\n\n*${frame.caption}*`);
      }
      game.push(`### ${s.id} · ${s.title}`,`${s.year} · ${s.location}`,`**场面目标：**${s.task}`,`**人物欲求：**${s.dramaticBeat.want}`,`**阻力：**${s.dramaticBeat.obstacle}`,`**既定行动：**${s.dramaticBeat.decision}`,`**结果：**${s.dramaticBeat.result}`,`**接续：**${s.dramaticBeat.next}`,s.dialogue.map(d=>`- ${d.speaker}：${d.text}`).join('\n'),`**历史与重建：**${s.history.note}`);
      rows.push(`|${s.id} ${s.title}|${cell(s.dramaticBeat.want)}|${cell(s.dramaticBeat.decision)} ${cell(s.dramaticBeat.result)}|${cell(s.dramaticBeat.next)}|`);
    }
  }
  novel.push('## 史后记','郑芝龙受控北上，1661年被清廷处死。郑成功没有随父整体归降，海上的抗清力量随后重新集结。','田川氏死于兵乱；《台湾外纪》卷六记1647年二月安平，平户纪念馆记1646年泉州，具体纪年、地点及死法未能统一。本作未据某一种晚出叙述重演其死亡现场。逐章证据与文学重建边界见完整剧本。');
  return {
    'novel.md':novel.join('\n\n')+'\n',
    'screenplay.md':renderScreenplay(story,{imageBase:illustrated?'':'zheng-zhilong/'}).replaceAll('](../research/','](../../research/'),
    'game-scenes.md':game.join('\n\n')+'\n',
    'CAUSE-CHAIN.md':`# ${story.title} · 因果衔接索引\n\n下表整理实际写成的各章，用于查找因果断点，不能证明读者必然喜欢，也不能代替正文。\n\n${rows.join('\n')}\n`
  };
}
