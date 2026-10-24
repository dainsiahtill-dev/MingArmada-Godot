// 第七稿收尾修订：消除三处落像模具重复与跨场道具撞词。
// 只改正文末段与个别道具描述；不改段落数、标题、年份、地点、图片、史注。
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');
const storyPath = path.join(root, 'docs/narrative/zheng-zhilong-story.json');
const story = JSON.parse(fs.readFileSync(storyPath, 'utf8').replace(/^﻿/, ''));
const scene = id => story.acts.flatMap(act => act.scenes).find(s => s.id === id);

const patches = [];

// 一、a5_s1 末段与 a1_s3 末段撞在同一件道具上（都收在「纸角露在外头」）。
//    改为收在柜外那块松木牌：末行名字与牌底下的空行。空行留得更宽，是本场
//    「这一栏仍旧是空的」从柜子走到人身上的最后一落。
{
  const s = scene('yiguan_a5_s1');
  const before = s.paragraphs[s.paragraphs.length - 1];
  const after = before.replace(
    '柜外那块松木牌上，最后一行名字是森的，下面空着。森回屋，把那两张抄好的副纸夹进自己的书匣，匣盖落下时，纸角露在外头一线。',
    '柜外那块松木牌上，最后一行名字是森的。森回屋，把那两张抄好的副纸夹进自己的书匣。匣盖落下时，牌上「送件」两个字底下那一行空着，比上面的行距宽出一指。'
  );
  if (after === before) throw new Error('a5_s1 末段未匹配');
  s.paragraphs[s.paragraphs.length - 1] = after;
  patches.push('a5_s1 末段：纸角露头 → 送件木牌底下的空行');
}

// 二、a5_s3 末段「墨还没干」与 a1_s3 末段「墨还没有干透」是同一枚落像。
//    a5_s3 的落点本应是父子分向两路，把最后一句交给地形与背影，不再用新墨。
{
  const s = scene('yiguan_a5_s3');
  const before = s.paragraphs[s.paragraphs.length - 1];
  const after = before.replace(
    '芝龙把两本册子夹在腋下——名单，饷行——饷行簿上成功名下的那一栏里，多出一行儿子的字，墨还没干。',
    '芝龙把两本册子夹在腋下——名单，饷行。他下阶的时候没有回头，内院巷口那道墙比海那边矮半人。'
  );
  if (after === before) throw new Error('a5_s3 末段未匹配');
  s.paragraphs[s.paragraphs.length - 1] = after;
  patches.push('a5_s3 末段：儿子新墨未干 → 两本册子与矮半人的院墙');
}

// 三、a1_s3 末段仍用「墨还没有干透」，与全卷另外两处同属「写字—墨未干」母题。
//    本场落点本应是那张纸比人重，改为纸的重量与风，不再以墨收。
{
  const s = scene('yiguan_a1_s3');
  const before = s.paragraphs[s.paragraphs.length - 1];
  const after = before.replace(
    '风掀起一角，他把纸往怀里收了半寸，只留一角露在外头。那一角上，墨还没有干透。',
    '风掀起一角，他把纸往怀里收了半寸，只留一角露在外头。纸压在他胸口，那一角一下一下地拍，像自己会跳。'
  );
  if (after === before) throw new Error('a1_s3 末段未匹配');
  s.paragraphs[s.paragraphs.length - 1] = after;
  patches.push('a1_s3 末段：墨未干透 → 纸在胸口一下一下地拍');
}

fs.writeFileSync(storyPath, `${JSON.stringify(story, null, 2)}\n`, 'utf8');
for (const patch of patches) console.log(`已改：${patch}`);
