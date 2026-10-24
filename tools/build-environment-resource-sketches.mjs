import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

// Editable technical sketches. These are diagrams, not generated historical art.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const sourcePath = 'docs/production/resource-library/parts/environment.json';
const sourceBytes = fs.readFileSync(path.join(root, sourcePath));
const source = JSON.parse(sourceBytes);
const digest = value => crypto.createHash('sha256').update(value).digest('hex');
const esc = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&apos;' }[c]));
const p = {
  ink: '#273d40', muted: '#637573', paper: '#f6f2e8', wood: '#d9c3a0',
  stone: '#c7c9bd', earth: '#ddcda9', water: '#d8e8e8', shallow: '#b9d5d0',
  green: '#cad3b4', accent: '#a86040', blue: '#557c88', white: '#fffdf7',
};
const rect = (x, y, w, h, fill = 'none', extra = '') => `<rect x="${x}" y="${y}" width="${w}" height="${h}" fill="${fill}" ${extra}/>`;
const line = (x1, y1, x2, y2, extra = '') => `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" ${extra}/>`;
const poly = (points, fill = 'none', extra = '') => `<polygon points="${points}" fill="${fill}" ${extra}/>`;
const drawPath = (d, fill = 'none', extra = '') => `<path d="${d}" fill="${fill}" ${extra}/>`;
const circle = (x, y, r, fill = 'none', extra = '') => `<circle cx="${x}" cy="${y}" r="${r}" fill="${fill}" ${extra}/>`;
const text = (x, y, label, extra = '') => `<text x="${x}" y="${y}" ${extra}>${esc(label)}</text>`;
const small = (x, y, label) => text(x, y, label, 'class="small"');
const tag = (x, y, label) => text(x, y, label, 'class="tag"');
const lead = (x1, y1, x2, y2, label, anchor = 'start') => line(x1, y1, x2, y2, 'class="leader"') + circle(x1, y1, 4, p.accent, 'stroke="none"') + text(x2 + (anchor === 'start' ? 8 : -8), y2 - 6, label, `text-anchor="${anchor}"`);
const arrow = (d, label, x, y, extra = '') => drawPath(d, 'none', `class="route" marker-end="url(#arrow)" ${extra}`) + (label ? text(x, y, label, 'class="route-label"') : '');
const camera = (x, y, label, angle = 0) => `<g transform="translate(${x} ${y}) rotate(${angle})">${circle(0, 0, 14, p.white)}${poly('12,-9 39,-22 39,22 12,9', 'none', 'class="leader"')}${circle(0, 0, 4, p.accent)}</g>` + small(x - 20, y + 40, label);
const boat = (x, y, angle = 0, fill = p.white, length = 90) => `<g transform="translate(${x} ${y}) rotate(${angle}) scale(${length / 90})">${drawPath('M-44 0Q-28-19 23-16L48 0 23 16Q-28 19-44 0Z', fill)}${line(-26, 0, 23, 0)}${line(0, -16, 0, 16)}${circle(0, 0, 4, p.wood)}</g>`;
const roof = (x, y, w, h, fill = p.wood) => poly(`${x},${y + h} ${x + w / 2},${y} ${x + w},${y + h}`, fill) + line(x + w / 2, y, x + w / 2, y + h);
const hatch = (x, y, w, h, gap = 22) => Array.from({ length: Math.floor(w / gap) }, (_, i) => line(x + gap * (i + 1), y, x + gap * (i + 1), y + h, 'class="fine"')).join('');
const box = (x, y, w, h, label, fill = p.white) => rect(x, y, w, h, fill) + text(x + w / 2, y + h / 2 + 7, label, 'text-anchor="middle"');
const room = (x, y, w, h, label, fill = p.white) => box(x, y, w, h, label, fill) + line(x + w - 55, y + h, x + w - 10, y + h, `stroke="${p.paper}" stroke-width="7"`);
const moor = (x, y) => circle(x, y, 8, p.wood) + circle(x, y, 16, 'none', 'class="fine"');
const shallow = d => drawPath(d, 'none', 'class="shallow"');
const coast = d => drawPath(d, p.earth);
const seaBase = () => rect(12, 20, 944, 596, p.water) + small(30, 643, '青绿虚线：浅区　红箭头：航路 / 任务线　圆锥：镜头锚点') + small(30, 669, '布局关系示意；无真实经纬坐标，岸线与水深均待制作验证');
const stoneSeams = (x, y, w, h) => {
  let out = '';
  for (let row = 1; row < Math.ceil(h / 35); row++) out += line(x, y + row * 35, x + w, y + row * 35, 'class="fine"');
  for (let row = 0; row < Math.ceil(h / 35); row++) for (let col = 0; col < Math.ceil(w / 70); col++) {
    const px = x + col * 70 + (row % 2 ? 32 : 0);
    if (px > x && px < x + w) out += line(px, y + row * 35, px, Math.min(y + (row + 1) * 35, y + h), 'class="fine"');
  }
  return out;
};
const treeCrown = (cx, cy, scale = 1) => `<g transform="translate(${cx} ${cy}) scale(${scale})">${drawPath('M-170 15C-205-25-181-88-126-94C-128-150-44-178-11-139C35-183 110-151 119-100C185-104 216-35 178 8C190 55 121 83 72 62C24 100-43 82-60 63C-112 87-173 61-170 15Z', p.green)}</g>`;
const trunk = d => drawPath(d, p.wood);
const rock = (x, y, s = 1, wet = false) => `<g transform="translate(${x} ${y}) scale(${s})">${poly('0,90 24,20 92,0 146,32 160,102 103,133 35,125', wet ? p.shallow : p.stone)}${drawPath('M24 20L61 77 146 32M61 77L103 133M61 77L0 90')}${line(92, 0, 61, 77)}</g>`;

const renderers = {
  'coastal-wood-pier': () =>
    poly('160,210 610,125 825,250 375,345', p.wood) +
    Array.from({ length: 14 }, (_, i) => line(185 + i * 30, 205 - i * 5.5, 400 + i * 30, 339 - i * 6, 'class="fine"')).join('') +
    [[190,220],[395,340],[790,254],[590,160]].map(([x,y]) => rect(x, y, 22, 210, p.wood) + line(x + 11,y + 210,x + 11,y + 235,'class="leader"')).join('') +
    poly('375,345 825,250 825,276 375,371', p.wood) + line(396,400,800,309) + line(396,469,800,377) +
    line(412,454,590,330) + line(590,407,787,290) + moor(670,205) + drawPath('M675 205Q770 150 860 270','none','class="rope"') +
    lead(350,241,90,145,'铺板：可重复直段') + lead(577,302,690,415,'纵梁 / 横梁') + lead(215,420,80,500,'入水木桩') + lead(674,204,739,109,'绳桩：道具引用') + tag(170,590,'端头与直段共用接口；桩、梁、板分层可编辑'),
  'coastal-stone-step': () =>
    poly('105,185 610,110 840,215 330,300', p.stone) + poly('105,185 330,300 330,470 105,350',p.stone) +
    poly('330,300 840,215 840,385 330,470',p.stone) +
    Array.from({length:5},(_,i)=>poly(`${420+i*32},${305+i*27} ${600+i*32},${276+i*27} ${600+i*32},${302+i*27} ${420+i*32},${333+i*27}`,p.stone)).join('') +
    line(330,390,840,305,'class="waterline"') + stoneSeams(115,220,190,105) + lead(700,235,795,120,'堤顶通行面','end') + lead(610,395,750,500,'入水踏步') +
    lead(240,320,72,425,'砌石接缝') + text(75,565,'高岸平台与下水台阶分开；干湿水线随场景变化'),
  'building-warehouse-front': () =>
    rect(180,225,580,285,p.earth) + roof(145,100,650,135) + rect(290,280,340,230,p.paper) +
    [190,274,638,738].map(x=>rect(x,230,18,280,p.wood)).join('') + rect(177,240,590,30,p.wood) + rect(160,510,620,34,p.stone) +
    drawPath('M300 280L300 490M620 280L620 490','none','class="leader"') + lead(207,261,65,145,'梁柱门面') + lead(447,335,720,345,'大货门洞：门扇另引') +
    lead(180,524,70,600,'低石基与踏步') + small(235,580,'门面不重复内含独立门窗；两侧预留墙体接口'),
  'building-warehouse-wall': () =>
    rect(140,160,470,360,p.earth) + [150,585].map(x=>rect(x,160,22,360,p.wood)).join('') + rect(140,505,470,30,p.stone) +
    stoneSeams(175,185,390,300) + line(175,360,565,360) + rect(690,185,60,330,p.earth) + rect(750,185,25,330,p.wood) +
    line(610,160,645,160,'class="interface"') + line(610,520,645,520,'class="interface"') +
    lead(600,205,770,110,'柱端拼接接口','end') + lead(380,347,90,590,'填墙表面：砖石 / 灰泥') + text(669,565,'墙厚与柱关系剖示') + tag(135,115,'可重复侧墙 / 背墙，无门窗开洞'),
  'building-pitched-roof': () =>
    poly('135,225 470,92 835,235 492,366',p.wood) + line(470,92,492,366) +
    Array.from({length:11},(_,i)=>line(155+i*29,218-i*11,509+i*28,360-i*11,'class="fine"')).join('') +
    roof(205,418,460,122,'none') + line(245,540,625,540) + [270,365,460,555,620].map(x=>line(435,435,x,535)).join('') +
    lead(485,106,695,75,'屋脊') + lead(720,282,790,389,'瓦面与檐口') + lead(455,486,735,540,'下层椽架') + tag(90,610,'上：屋面轮廓　下：分离木构；门墙不并入此件'),
  'building-timber-wall': () =>
    rect(135,150,600,380,p.wood) + hatch(135,150,600,380,32) +
    [145,420,710].map(x=>rect(x,145,20,390,p.wood)).join('') + rect(135,335,600,22,p.wood) + rect(485,200,150,125,p.paper) +
    line(500,200,500,325) + line(620,200,620,325) + lead(440,355,755,425,'横档 / 柱接口') + lead(245,245,65,95,'板壁方向') +
    lead(555,218,650,95,'留窗洞：窗扇另引') + small(135,600,'木板壁与柱网分开；不套用货栈砖石墙轮廓'),
  'building-plaster-wall': () =>
    rect(130,170,565,350,p.white) + rect(130,490,565,45,p.stone) + rect(355,285,160,235,p.paper) +
    drawPath('M170 240L220 270 205 310M570 205L535 235 555 270','none','class="fine"') +
    rect(750,200,65,300,p.earth) + rect(735,200,15,300,p.white) + line(750,200,815,245) +
    lead(480,345,670,95,'门洞边留木框接口','end') + lead(190,501,50,590,'石基与灰墙分层') + text(728,560,'表层 / 墙体剖示') + tag(120,115,'灰泥面、门洞、石基：福建居所墙体'),
  'building-residence-roof': () =>
    poly('120,260 440,135 790,248 466,380',p.stone) + line(440,135,466,380) +
    poly('120,260 466,380 466,402 120,282',p.wood) + poly('466,380 790,248 790,270 466,402',p.wood) +
    Array.from({length:8},(_,i)=>line(150+i*35,256-i*13,484+i*32,373-i*13,'class="fine"')).join('') +
    drawPath('M235 510L420 435 640 510 610 529 420 468 260 531',p.wood) +
    lead(260,312,90,420,'低矮檐口') + lead(453,170,650,90,'住宅屋脊') + lead(419,468,685,555,'檐木层次剖示') + small(100,610,'平户 / 福建构造差别待概念审查；不同拓扑须另审预算'),
  'building-door': () =>
    rect(150,120,300,425,p.wood) + hatch(150,120,300,425,38) + rect(170,215,260,24,p.wood) + rect(170,432,260,24,p.wood) +
    [190,440].map(y=>circle(165,y,8,p.ink)).join('') + circle(405,330,13,p.paper) +
    line(590,540,830,540) + line(590,540,590,300) + drawPath('M830 540A240 240 0 0 0 590 300','none','class="swing"') +
    lead(165,190,60,88,'门轴边') + lead(405,330,475,245,'把手 / 门闩区') + text(580,590,'俯视：开门扫掠区') + small(150,605,'独立门扇；门洞与门框归建筑接口'),
  'building-window': () =>
    rect(150,130,430,360,p.wood) + rect(175,155,380,310,p.paper) +
    [240,315,390,465].map(x=>line(x,155,x,465)).join('') + [225,305,385].map(y=>line(175,y,555,y)).join('') +
    rect(650,210,185,245,'none') + rect(665,225,155,215,p.white,'class="interface"') +
    lead(375,155,550,80,'外框与格栅分层') + lead(465,385,595,555,'格样只是概念') + text(630,500,'可换闭合面') + small(120,610,'木格 / 纸面只表达构件关系；地域样式须单独审查'),
  'coastal-market-stall': () =>
    poly('180,220 570,155 800,250 405,325',p.wood) +
    drawPath('M180 220Q390 260 570 155M405 325Q610 360 800 250','none','class="fine"') +
    [[190,220],[405,325],[775,255],[570,175]].map(([x,y])=>rect(x,y,15,250,p.wood)).join('') +
    poly('330,395 670,340 750,390 405,455',p.wood) + rect(405,455,18,70,p.wood) + rect(720,395,18,78,p.wood) +
    lead(465,245,745,105,'布棚：收放层') + lead(215,385,65,470,'轻木柱') + lead(546,410,720,550,'摊面；货物另配') + tag(155,610,'港市 / 夜锚交易共用；不内含货箱与灯'),
  'coastal-shipyard-cradle': () =>
    drawPath('M100 215Q455 45 865 210L790 285Q470 410 185 300Z','none','class="silhouette"') +
    [[260,290],[455,318],[665,300]].map(([x,y])=>poly(`${x-85},510 ${x},${y} ${x+85},510`,p.wood)+rect(x-110,510,220,24,p.wood)+line(x-58,448,x+58,448)).join('') +
    line(190,535,810,535) + lead(455,320,540,100,'船壳只示接触轮廓') + lead(676,424,805,470,'斜撑') + lead(334,521,82,592,'岸上木枕与支点') + small(455,602,'工作面与支撑面分清；船只由船舶分册引用'),
  'nature-broadleaf': () =>
    treeCrown(450,240,1.35) + trunk('M420 560L428 390 396 300 417 287 455 365 488 293 509 301 470 399 485 560Z') +
    drawPath('M430 390L354 344M472 390L560 328','none','stroke-width="12"') +
    lead(385,85,120,90,'疏密树冠层') + lead(490,406,710,470,'分叉与主干') + lead(452,554,140,600,'根基接地') + small(650,610,'树种暂不定名'),
  'nature-shore-tree': () =>
    drawPath('M318 180C300 125 362 95 397 118C423 58 503 88 527 121C600 82 710 118 715 163C794 159 832 218 776 249C718 295 632 266 584 277C536 312 430 279 405 243C353 259 297 229 318 180Z',p.green) +
    trunk('M285 558Q420 440 488 266L516 246Q500 405 345 565Z') + drawPath('M434 379L655 226M482 302L405 220','none','stroke-width="10"') +
    arrow('M135 115L330 115','迎风方向',125,80) + lead(715,198,790,340,'偏冠与疏枝','end') + lead(359,510,105,590,'弯曲低主干') + small(535,610,'风塑轮廓；不以乔木等比缩小代替'),
  'nature-palm': () =>
    trunk('M440 565Q489 354 457 193L480 189Q522 380 468 565Z') +
    Array.from({length:7},(_,i)=>line(454+i*1.6,270+i*38,487+i*0.4,264+i*38,'class="fine"')).join('') +
    ['M467 195Q340 60 195 142Q332 94 467 195','M467 195Q367 125 250 245Q365 184 467 195','M467 195Q420 80 460 50Q483 123 467 195','M467 195Q585 45 741 119Q596 107 467 195','M467 195Q640 145 786 263Q630 190 467 195','M467 195Q555 222 624 330Q539 261 467 195'].map(d=>drawPath(d,p.green)).join('') +
    lead(665,111,740,55,'叶簇展开','end') + lead(480,410,685,480,'环痕干') + tag(155,620,'区域可选；不据此把无风航段设成热带植被区'),
  'nature-shrub': () =>
    [[220,340,100],[380,270,135],[525,330,140],[680,280,105],[760,390,85]].map(([x,y,r])=>circle(x,y,r,p.green)).join('') +
    ['M455 570L390 327 335 275','M452 570L530 380 655 300','M452 570L247 410','M452 570L700 440'].map(d=>drawPath(d,'none','stroke-width="8"')).join('') +
    lead(381,164,125,95,'不规则叶团') + lead(530,430,725,550,'木质分枝') + line(170,570,820,570,'class="ground"') + small(145,620,'簇间保留空隙；没有整齐园艺球轮廓'),
  'nature-grass': () =>
    ['M410 565Q230 380 250 200Q330 350 410 565','M420 565Q325 260 380 125Q420 340 420 565','M432 565Q448 245 535 160Q490 370 432 565','M443 565Q588 340 680 300Q520 470 443 565','M421 565Q250 486 185 420Q350 445 421 565','M439 565Q585 470 722 463Q578 520 439 565'].map(d=>drawPath(d,p.green)).join('') +
    line(165,565,785,565,'class="ground"') + lead(380,270,90,150,'不同方向叶片') + lead(434,557,670,590,'根部聚合') + small(560,90,'侧向轮廓 / 单簇结构'),
  'nature-rock': () =>
    rock(140,180,2.3) + rock(555,295,1.55,true) + rock(660,210,0.65) +
    line(520,430,865,430,'class="waterline"') + lead(289,207,100,108,'棱面与风化圆边') + lead(655,430,770,530,'湿石水线') +
    tag(125,610,'干石 / 近水礁石共用形体族；湿润材质单列'),
  'building-macau-warehouse': () =>
    poly('135,280 420,175 770,245 485,355',p.stone) + poly('135,280 485,355 485,535 135,460',p.earth) +
    poly('485,355 770,245 770,430 485,535',p.wood) + rect(210,330,180,150,p.paper) + [160,415].map(x=>line(x,285,x,470,'stroke-width="10"')).join('') +
    poly('130,460 485,535 670,590 315,520',p.stone) + arrow('M670 570L495 465L365 420','装卸进路',615,635) +
    lead(419,202,695,105,'仓储坡顶与侧墙') + lead(238,366,65,210,'大货门') + lead(366,510,92,590,'低石基 / 门前工作区') + camera(838,488,'门前镜头',165),
  'building-warehouse-berth': () =>
    rect(145,120,650,430,p.earth) + room(165,140,355,390,'旧铺小间') + room(520,140,255,215,'工具暂存',p.wood) +
    rect(195,180,120,220,p.wood) + text(204,430,'床铺另引') + line(350,170,480,170,'class="window"') +
    arrow('M875 535L610 535L585 425L450 430','门口至旧铺',605,600) + camera(725,445,'门口镜头',180) +
    lead(225,268,70,70,'窄铺位') + lead(607,185,747,85,'工具不并入墙体') + small(150,640,'有限室内平面；养伤与失位用陈设变化，不增另一座旅馆'),
  'building-hirado-home': () =>
    poly('130,260 420,135 785,240 492,375',p.stone) + poly('145,275 492,375 492,535 145,430',p.wood) +
    poly('492,375 770,250 770,430 492,535',p.wood) + hatch(160,300,295,125,27) +
    rect(252,320,102,145,p.paper) + rect(570,355,100,76,p.paper) + line(620,355,620,431) +
    poly('145,430 492,535 550,558 198,450',p.wood) + lead(336,321,65,190,'低门槛与窄入口') +
    lead(512,360,755,120,'窄檐 / 板壁') + lead(600,390,810,505,'木格闭合面') + tag(150,625,'普通邻里木屋概念；完整平面未考证'),
  'building-fujian-residence': () =>
    rect(110,110,730,450,p.stone) + room(140,140,270,140,'家人屋室',p.white) + room(430,140,370,140,'读书与起居',p.white) +
    room(140,300,190,220,'侧屋',p.earth) + rect(350,300,450,220,p.paper) + text(490,415,'小型内院 / 过道') +
    line(620,560,750,560,'stroke-width="12" stroke="#f6f2e8"') + arrow('M680 630L680 525L650 380L600 300','家人与出入口',695,605) +
    camera(430,475,'门槛镜头',-20) + lead(285,558,90,620,'石基与墙体') + small(110,80,'有限围合概念；非已证郑氏故居平面'),
  'building-shore-sickroom': () =>
    room(140,140,430,380,'养伤屋',p.white) + room(590,140,235,380,'檐下灶区',p.earth) +
    rect(175,185,115,220,p.wood) + text(174,442,'卧具另引') + circle(695,280,50,p.stone) + text(645,365,'锅灶另配') +
    line(570,225,590,225,'stroke-width="10" stroke="#f6f2e8"') + arrow('M485 630L485 465L360 465L360 340','伤员可行通路',465,605) +
    camera(760,450,'告别镜头',180) + lead(185,185,90,75,'床位靠墙留通道') + small(145,640,'煎鱼与养伤共用小屋；生活物件由道具分册提供'),
  'building-settlement-shelter': () =>
    roof(135,95,650,170,p.stone) + rect(170,265,580,245,p.earth) + rect(260,330,150,180,p.paper) +
    [215,610].map(x=>rect(x,265,16,245,p.wood)).join('') + drawPath('M565 192L580 245 565 290 576 345','none','class="drip"') +
    circle(577,430,35,p.stone) + lead(564,192,795,100,'破损节点 / 漏雨') + lead(275,344,70,350,'宽门与遮雨边') +
    arrow('M872 550L660 550L470 480','背人离屋通路',680,615) + text(130,600,'安置屋剖示：留出伤员、补给与重新出海的关系'),
  'building-inspection-room': () =>
    rect(150,150,650,365,p.stone) + [175,745].map(x=>rect(x,150,24,365,p.wood)).join('') +
    rect(150,150,650,30,p.wood) + box(300,265,340,95,'交验桌：道具另引',p.wood) +
    rect(180,190,90,190,p.paper,'class="interface"') + small(180,417,'交械暂置区') +
    arrow('M450 630L450 465L450 390','交验入内',470,598) + arrow('M675 415L840 415','码头出口',700,390) +
    camera(725,465,'交涉镜头',180) + text(140,95,'岸边一间交验房 / 檐下热点；不扩成全套衙门'),
  'coastal-fishing-hamlet': () =>
    seaBase() + coast('M12 20H956V185Q805 210 720 300Q540 325 390 260Q200 190 12 310Z') +
    [[140,110,170,85],[420,130,200,90],[710,70,155,105]].map(([x,y,w,h])=>roof(x,y,w,h,p.wood)+rect(x+20,y+h,w-40,85,p.earth)).join('') +
    shallow('M20 350Q225 230 390 310Q560 390 750 350Q850 265 950 255') +
    arrow('M840 540Q640 450 520 340','小艇接人线',590,523) + boat(820,530,-25) +
    camera(185,480,'远岸镜头',-15) + lead(513,175,570,70,'低矮渔寮组') + text(85,600,'火损只切换局部节点；不是可进入的整座村落'),
  'coastal-luzon-battery': () =>
    poly('135,490 255,250 680,205 820,470',p.earth) + drawPath('M240 260Q465 100 700 225L700 290Q480 180 260 320Z',p.stone) +
    [320,450,580].map((x,i)=>rect(x,200+i*5,52,42,p.paper)+line(x+26,205+i*5,x+18,150+i*5,'stroke-width="8"')).join('') +
    poly('465,460 530,350 590,350 570,470',p.stone) + arrow('M565 535L535 390','后侧坡台',630,515) +
    line(95,555,850,555,'class="waterline"') + lead(330,221,65,110,'朝海炮口仅示方向') + lead(729,329,810,145,'土石岸垒','end') + tag(150,630,'只作未具名炮台远景；炮位不代表史实数量'),
  'map-world-nautical-chart': () =>
    seaBase() + coast('M12 20H285L320 110 292 195 345 255 290 330 310 405 235 470 190 616H12Z') +
    poly('455,320 495,350 480,440 450,475 431,427',p.earth) + poly('760,100 810,80 845,120 815,165 770,160',p.earth) +
    poly('670,505 715,490 740,535 725,590 680,565',p.earth) + shallow('M345 40Q400 180 350 330Q355 470 270 600') +
    arrow('M240 460Q400 270 790 140','航区连接示意',430,185) + arrow('M345 320Q470 350 470 400','大员方向',515,390) +
    [[240,460,'澳门'],[345,320,'福建'],[470,400,'大员'],[790,140,'平户'],[700,540,'吕宋方向：未核靠港']].map(([x,y,t])=>circle(x,y,9,p.accent)+text(x+17,y-12,t)).join('') +
    camera(550,560,'底图观察锚点',-85) + tag(420,270,'界面底图，非真实经纬投影'),
  'map-tactical-water-chart': () =>
    seaBase() + coast('M12 20H290L360 125 300 220 200 280 12 270Z') + coast('M700 20H956V290L825 255 775 155Z') +
    shallow('M30 320Q210 345 350 215L405 90M667 70Q700 240 920 330') +
    [[465,180,90],[580,190,90],[500,425,90],[665,470,0]].map(([x,y,a])=>boat(x,y,a)).join('') +
    arrow('M505 540L500 340','接应 / 撤回',350,525) + arrow('M665 470Q775 365 735 280','外侧回援',700,430) +
    drawPath('M465 255L580 255M465 274L580 274','none','class="rope"') + text(405,310,'双船过板 / 舱门目标分层') +
    camera(175,490,'俯视战术锚点',-20) + text(405,75,'狭口封锁与承诺船位'),
  'map-open-sea-mother': () =>
    seaBase() + coast('M12 20H225L180 55 125 60 95 100 12 135Z') + coast('M830 20H956V120L920 95 875 100Z') +
    shallow('M20 165Q150 130 235 65M800 60Q860 140 945 150') +
    drawPath('M120 260Q350 230 590 260T900 260M80 440Q330 410 590 440T900 440','none','class="waterline"') +
    arrow('M170 540Q395 490 540 360T825 200','连续主航行空间',360,540) + boat(520,375,-35) +
    camera(310,465,'追船镜头',-20) + camera(730,340,'海平线镜头',-120) + box(65,190,205,80,'远岸可显隐',p.paper) +
    text(620,585,'雾 / 无风 / 横浪 / 昼夜为条件包'),
  'map-shipboard-mother': () =>
    seaBase() + drawPath('M120 330Q170 150 360 140H775Q870 155 870 315V405Q850 475 775 480H355Q170 465 120 330Z',p.wood) +
    rect(365,240,175,150,p.paper) + text(385,320,'舱口 / 货舱') + line(310,165,310,450) + line(665,155,665,470) +
    circle(265,330,18,p.stone) + circle(640,330,18,p.stone) + box(690,240,135,110,'有限舱室',p.paper) +
    arrow('M200 355L335 420L600 420L720 360','甲板通路',350,535) + camera(735,190,'舱口镜头',120) + camera(205,205,'甲板镜头',25) +
    tag(200,95,'船型挂点装配：不另计一艘“场景船”'),
  'map-macau-harbor': () =>
    seaBase() + coast('M12 20H956V150L680 175 560 230 290 265 12 290Z') +
    box(100,65,245,110,'华商货栈',p.white) + box(370,70,155,95,'旧铺小间',p.white) +
    poly('380,235 430,225 470,380 420,390',p.wood) + moor(425,320) +
    shallow('M20 335Q380 320 580 265L930 210') + boat(465,430,15) + boat(805,370,15,p.white,125) +
    arrow('M450 410Q590 530 850 465','夜间接驳至外泊船',490,560) + camera(230,300,'栈门镜头',10) + camera(675,500,'离岸回望',-145),
  'map-hirado-kawachi-harbor': () =>
    seaBase() + coast('M12 20H510L530 115 465 190 485 265 390 345 325 440 235 475 12 485Z') +
    box(130,110,210,105,'木屋与港巷',p.wood) + drawPath('M310 245L450 245 375 370 310 400','none','stroke-width="20"') +
    shallow('M600 35Q645 180 515 320L390 500 255 550') + boat(565,410,55) +
    arrow('M190 230L310 305L420 330L550 410','搬桶 / 候船路径',135,570) + camera(360,410,'石堤候船',-30) + text(600,225,'商船泊向') + moor(420,320),
  'map-taiwan-southwest-anchorage': () =>
    seaBase() + coast('M12 20H956V110L810 160 620 140 460 215 255 180 12 235Z') +
    shallow('M20 285Q250 220 430 275Q620 205 835 225L950 175') +
    boat(350,365,20,p.white,120) + boat(610,395,20,p.white,95) + boat(750,290,-20,p.white,55) +
    circle(350,365,105,'none','class="anchor-zone"') + circle(610,395,105,'none','class="anchor-zone"') +
    arrow('M185 565Q320 465 465 440L750 480','雾中会合主航道',430,570) + camera(485,325,'两船关系镜头',120) +
    text(95,120,'低远岸 / 沙岸') + text(640,125,'临时锚地，不补整座城堡'),
  'map-fujian-hidden-anchorage': () =>
    seaBase() + coast('M12 20H956V470L830 440 795 280 690 210 475 190 345 265 260 390 12 470Z') +
    shallow('M40 520L280 440 370 325 490 260 665 270 735 335 770 490 920 530') +
    box(430,82,220,95,'货棚 / 夜市',p.wood) + [[385,185],[580,190],[700,215]].map(([x,y])=>rect(x,y,75,45,p.wood)).join('') +
    boat(500,385,0) + boat(655,460,-35,p.white,65) + arrow('M200 570L370 470L500 410','背风进出线',300,575) +
    camera(320,380,'交易岸滩',-20) + moor(415,305) + text(710,140,'棚下换粮药'),
  'map-fujian-working-harbor': () =>
    seaBase() + coast('M12 20H956V225L700 225 700 300 540 300 540 205 335 205 335 355 160 355 160 250 12 250Z') +
    box(60,70,225,95,'货栈 / 补给',p.white) + box(355,55,170,95,'交验热点',p.white) + box(580,65,205,95,'家宅入口',p.white) +
    poly('225,335 260,335 260,460 225,460',p.wood) + box(750,245,150,80,'修船支架',p.wood) +
    shallow('M30 300L130 315 130 390 365 390 365 255 505 255 505 345 730 345L940 285') +
    boat(410,435,0) + boat(655,445,90,p.white,60) + arrow('M900 550L580 550L390 460','港内主航道',590,590) +
    camera(270,270,'工作岸镜头',30) + camera(760,420,'港火救援镜头',180) + text(82,555,'普通泊位 / 火损泊位共享布局'),
  'map-hirado-home-scene': () =>
    rect(115,100,700,420,p.wood) + room(145,130,355,260,'起居 / 母子区',p.paper) + room(520,130,265,260,'收物与行李',p.paper) +
    rect(145,410,640,80,p.earth) + text(390,462,'窄檐与门槛') + line(410,490,515,490,'stroke-width="10" stroke="#f6f2e8"') +
    arrow('M460 620L460 470L450 320','港巷至屋内',480,600) + camera(235,440,'护灯镜头',0) + camera(740,350,'送子镜头',160) +
    drawPath('M105 565Q265 545 340 565M585 565Q715 540 835 565','none','class="waterline"') + text(90,75,'家居母场景：同屋跨年换陈设，不新增宅院'),
  'map-fujian-household-scene': () =>
    rect(115,100,725,420,p.stone) + room(145,130,240,180,'家人屋室',p.white) + room(405,130,215,180,'蒙学 / 起居',p.white) +
    room(640,130,170,180,'侧间',p.earth) + rect(145,330,665,160,p.paper) + text(380,415,'门内缓冲与行李区') +
    arrow('M530 620L530 485L515 330','门槛 / 登船方向',555,600) + camera(230,440,'团聚镜头',-30) + camera(745,450,'取箱镜头',180) +
    text(130,75,'福建家宅共享镜头平面；养伤与临居另换装配'),
  'map-nearshore-channel': () =>
    seaBase() + coast('M12 20H405L360 125 415 210 310 305 355 410 240 500 12 560Z') +
    coast('M720 20H956V615H760L805 500 710 390 765 270 695 170Z') +
    shallow('M390 60L465 190 385 310 435 410 300 555M670 70L650 200 710 280 655 390 725 540') +
    rock(355,320,.42,true) + rock(665,210,.35,true) + arrow('M550 575L540 430L565 300L525 170L570 75','狭口主航道',575,515) +
    boat(545,330,-90) + boat(585,120,0,p.white,60) + camera(305,215,'暗岸 / 岛岸锚点',30) + text(45,95,'四场差异包：夺船 / 护货 / 试伏 / 封口'),
  'map-unnamed-rescue-bay': () =>
    seaBase() + coast('M12 20H956V425L825 440 800 245 690 160 475 180 330 280 225 485 12 450Z') +
    shallow('M35 500L255 535 365 345 495 250 660 235 740 300 765 500 930 505') +
    box(565,65,240,90,'岸上渔寮 / 火势',p.wood) + boat(590,325,0) + boat(655,355,0,p.white,70) +
    boat(350,520,-10,p.white,130) + boat(785,520,10,p.white,130) +
    arrow('M475 565L525 430L650 365','救援艇进路',365,600) + arrow('M700 385Q795 445 650 570','接人撤回',740,430) +
    camera(440,370,'湾内救人镜头',-20) + text(100,125,'虚构无名湾口；湾外封口与湾内接舷分层'),
  'map-liaoluo-bay': () =>
    seaBase() + coast('M12 20H956V175L800 120 665 180 520 130 345 190 190 135 12 210Z') +
    shallow('M20 260Q180 190 345 255Q520 195 670 245Q805 185 945 245') +
    [[430,290],[600,280],[770,300]].map(([x,y])=>boat(x,y,90,p.white,115)).join('') + boat(365,485,-65,p.wood,75) + boat(720,500,-30,p.white,50) +
    arrow('M335 550Q380 425 445 345','火船驶近',220,550) + arrow('M750 505Q620 465 525 520L480 580','接应艇回线',595,580) +
    arrow('M120 355L245 285','风向关系',70,405) + camera(550,400,'协同火攻镜头',-90) + text(90,90,'料罗湾关系稿；不复原逐舰阵位 / 实测岸线'),
  'map-tianweiyang-search': () =>
    seaBase() + coast('M12 20H270L230 65 165 90 115 150 12 165Z') + shallow('M20 220Q125 205 190 150L280 105') +
    boat(295,350,10,p.white,135) + boat(590,330,-20,p.white,55) + boat(770,440,35,p.white,50) +
    drawPath('M495 200Q700 130 860 260Q945 400 850 535Q690 600 490 510','none','class="search"') +
    arrow('M590 330Q630 220 770 230Q900 330 775 440','轻艇续寻',650,175) + arrow('M285 365L115 535','伤员母船归航',60,575) +
    camera(430,450,'空海面镜头',-30) + text(90,95,'战后锚地 / 搜索关系，死亡方式不在此图拍定'),
  'nature-island-terrain': () =>
    seaBase() + coast('M170 330Q180 160 385 140Q600 75 790 255L840 380 680 470 435 505 240 455Z') +
    shallow('M115 340Q130 100 385 85Q650 20 850 230L900 400 705 530 420 565 180 490Z') +
    drawPath('M270 335Q295 230 420 225Q590 160 710 295L720 365 590 415 420 435 300 395Z','none','class="contour"') +
    drawPath('M365 340Q405 265 495 275Q605 250 640 335L540 365 445 375Z','none','class="contour"') +
    arrow('M180 470Q275 430 320 370','岸路接缝',80,570) + box(680,115,180,65,'岩岸高差',p.stone) + camera(600,490,'临岸镜头',-100) +
    text(260,620,'同心轮廓只示高差层次，不代表实测等高线'),
  'nature-ocean-sky-profile': () => {
    const panels = [[65,70,'晴昼'],[505,70,'雾航'],[65,350,'静风'],[505,350,'横浪 / 风雨']];
    return panels.map(([x,y,t],i)=>rect(x,y,390,220,p.water)+rect(x,y,390,90,i===1?p.stone:p.paper)+text(x+20,y+35,t)+line(x,y+90,x+390,y+90,'class="horizon"')+
      Array.from({length:i===2?2:4},(_,n)=>drawPath(`M${x+15} ${y+125+n*22}Q${x+105} ${y+110+n*22-(i===3?18:0)} ${x+185} ${y+125+n*22}T${x+370} ${y+125+n*22}`,'none','class="fine"')).join('')+
      (i===1?[130,160,190].map(d=>line(x+20,y+d,x+370,y+d,'class="fog"')).join(''):'')+
      (i===3?[50,110,170,230,290].map(d=>line(x+d,y+45,x+d-25,y+90,'class="rain"')).join(''):'')).join('')+
      small(65,630,'同一海平面与天空条件集；不是四张独立地图或历史气象记录');
  },
  'nature-shore-materials': () =>
    [[65,110,210,250,p.earth,'干砂'],[275,110,210,250,p.wood,'湿砂'],[485,110,210,250,p.stone,'干岩'],[695,110,210,250,p.shallow,'湿岩']].map(([x,y,w,h,c,t],i)=>rect(x,y,w,h,c)+text(x+30,y+310,t)+(i<2?Array.from({length:8},(_,n)=>circle(x+25+(n%4)*45,y+50+Math.floor(n/4)*100,2,p.ink)).join(''):drawPath(`M${x+20} 280L${x+70} 180 ${x+120} 220 ${x+175} 145`))).join('') +
    arrow('M110 485L865 485','从潮上干燥到近水湿润：按实际水线混合',250,545) + line(65,610,905,610,'class="waterline"'),
  'nature-ground-materials': () =>
    poly('75,125 400,125 345,375 75,415',p.green) + poly('400,125 660,125 610,415 345,375',p.earth) + poly('660,125 900,125 900,415 610,415',p.stone) +
    Array.from({length:10},(_,i)=>drawPath(`M${105+i*23} ${210+(i%3)*50}l-8-22m8 22 7-26`)).join('') +
    Array.from({length:9},(_,i)=>circle(455+(i%3)*50,200+Math.floor(i/3)*70,5,p.wood)).join('') +
    [[710,190],[810,240],[700,325],[835,365]].map(([x,y])=>poly(`${x},${y} ${x+22},${y-15} ${x+38},${y+8} ${x+12},${y+20}`,p.stone)).join('') +
    text(140,465,'草土边缘') + text(420,465,'林下暗土') + text(720,465,'碎石通路') + arrow('M135 550Q430 510 835 550','可通行地面保持可读',330,605),
};

function wrap(value, width = 17) {
  const tokens = String(value).match(/[A-Za-z0-9]+(?:[—._-][A-Za-z0-9]+)*|./gu) || [];
  const lines = []; let current = ''; let used = 0;
  for (const token of tokens) {
    const size = [...token].reduce((sum, char) => sum + (char.codePointAt(0) > 255 ? 1 : 0.56), 0);
    if (current && used + size > width) { lines.push(current); current = ''; used = 0; }
    current += token; used += size;
  }
  if (current) lines.push(current);
  return lines;
}

function noteLines(x, y, title, value, maxLines = 5) {
  const lines = wrap(value).slice(0, maxLines);
  return tag(x,y,title) + lines.map((label,index)=>small(x,y+34+index*29,label)).join('');
}

// Keep editable labels inside the drawing area, including long Chinese callouts.
// This only wraps/repositions text; diagrams retain their distinct geometry.
function fitDiagramLabels(diagram) {
  return diagram.replace(/<text x="([\d.-]+)" y="([\d.-]+)"([^>]*)>([^<]*)<\/text>/g, (_, x0, y0, attrs, value) => {
    const font = attrs.includes('small') ? 18 : attrs.includes('route-label') ? 20 : attrs.includes('tag') ? 21 : 22;
    const width = str => [...str].reduce((sum, char) => sum + font * (char.codePointAt(0) > 255 ? 1 : 0.56), 0);
    const rows = []; let row = '';
    for (const char of [...value]) {
      if (row && width(row + char) > 900) { rows.push(row); row = ''; }
      row += char;
    }
    if (row) rows.push(row);
    const widest = Math.max(...rows.map(width));
    const middle = attrs.includes('text-anchor="middle"');
    const end = attrs.includes('text-anchor="end"');
    const left = middle ? Number(x0) - widest / 2 : end ? Number(x0) - widest : Number(x0);
    const bounded = Math.max(18, Math.min(left, 940 - widest));
    const x = middle ? bounded + widest / 2 : end ? bounded + widest : bounded;
    const y = Math.min(Number(y0), 675 - (rows.length - 1) * 29);
    return `<text x="${x}" y="${y}"${attrs}>${rows.map((content,index)=>`<tspan x="${x}" dy="${index ? 29 : 0}">${content}</tspan>`).join('')}</text>`;
  });
}

function svgFor(item, diagram) {
  const sceneTitle = item.category === 'scene-map' ? '可玩空间与镜头关系' : item.category === 'nature' ? '轮廓、层次与材质关系' : '构件与装配关系';
  const detail = item.assetKind === 'base-mesh' ? '原预算构件；本图不代表模型成品' : '装配 / 条件资源；不新增独立基模';
  const brief = item.visualBrief.replace(/建议[^；。]*[；。]/g, '').replace(/[\d]+(?:[—×.-][\d]+)*(?:米|级)/g,'');
  const purpose = item.category === 'nature' && item.assetKind === 'base-mesh' ? '原预算自然基模；以轮廓、分枝与接地关系支持沿岸实例复用。' : item.description;
  const refs = item.storyRefs.slice(0, 10).map(ref=>ref.replace('zheng_','')).join(' / ') + (item.storyRefs.length > 10 ? ' / …' : '');
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1440" height="1000" viewBox="0 0 1440 1000" role="img" aria-labelledby="title desc">
<title id="title">${esc(item.name)}：可编辑技术草图</title>
<desc id="desc">概念结构示意，非实测比例，非历史实址或精确复原。${esc(item.description)}所有符号与部件均为设计关系表达。</desc>
<defs><marker id="arrow" viewBox="0 0 10 10" refX="8" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse"><path d="M0 0L10 5L0 10Z" fill="${p.accent}"/></marker></defs>
<style>
svg{background:${p.paper}}text{font-family:"Noto Sans SC","Microsoft YaHei","PingFang SC",sans-serif;font-size:22px;fill:${p.ink};stroke:none}path,rect,polygon,line,circle{stroke:${p.ink};stroke-width:2.8;stroke-linejoin:round;stroke-linecap:round}.title{font-size:34px;font-weight:700}.subtitle{font-size:18px;fill:${p.muted}}.tag{font-size:21px;font-weight:700}.small{font-size:18px}.fine{stroke-width:1.3;opacity:.7}.leader{stroke:${p.muted};stroke-width:1.6;fill:none}.route{stroke:${p.accent};stroke-width:4;fill:none}.route-label{font-size:20px;fill:${p.accent}}.interface{stroke-dasharray:8 7;stroke:${p.blue}}.shallow{stroke:${p.shallow};stroke-width:17;stroke-dasharray:15 8;fill:none}.waterline{stroke:${p.blue};stroke-width:2;stroke-dasharray:13 9}.rope{stroke:${p.accent};stroke-width:2;stroke-dasharray:6 5;fill:none}.swing{stroke:${p.accent};stroke-dasharray:8 8;fill:none}.silhouette{stroke-dasharray:13 9;stroke:${p.muted};stroke-width:2}.ground{stroke-width:3}.window{stroke:${p.blue};stroke-width:7}.drip{stroke:${p.blue};stroke-dasharray:7 9;stroke-width:4}.anchor-zone{stroke:${p.blue};stroke-dasharray:8 10;stroke-width:1.5}.search{stroke:${p.blue};stroke-dasharray:10 8;stroke-width:2}.contour{stroke:${p.muted};stroke-dasharray:7 6;stroke-width:2}.horizon{stroke:${p.muted};stroke-width:2}.fog{stroke:${p.white};stroke-width:9;opacity:.7}.rain{stroke:${p.blue};stroke-width:2}
</style>
${rect(0,0,1440,1000,p.paper,'stroke="none"')}
${text(48,61,item.name,'class="title"')}
${text(49,98,item.id+' · '+sceneTitle,'class="subtitle"')}
${line(48,122,1390,122,`stroke="${p.muted}" stroke-width="1"`)}
${rect(48,146,970,694,p.white,`stroke="${p.stone}" stroke-width="1.2"`)}
<g transform="translate(50 155)">${fitDiagramLabels(diagram)}</g>
${noteLines(1050,174,'资源用途',purpose,5)}
${noteLines(1050,395,'制作关注',brief,6)}
${noteLines(1050,654,'计数边界',detail,3)}
${tag(50,884,'概念结构示意 · 非实测比例 · 非历史实址 / 非精确历史复原')}
${small(50,925,'只表达部件、空间、通路与镜头关系；图面位置不代表真实尺寸、水深、经纬度或史实炮位。')}
${small(50,962,'关联剧情：'+refs)}
</svg>\n`;
}

const ids = source.items.map(item => item.id);
if (ids.length !== 46 || new Set(ids).size !== 46) throw new Error('Expected 46 unique environment resource IDs.');
const missing = ids.filter(id => !renderers[id]);
const extra = Object.keys(renderers).filter(id => !ids.includes(id));
if (missing.length || extra.length) throw new Error(`Renderer mismatch: missing=${missing}, extra=${extra}`);
const group = { building: 'buildings', 'coastal-building': 'coastal', 'scene-map': 'maps', nature: 'nature' };
const records = [];
const graphHashes = new Set();
for (const item of source.items) {
  const diagram = renderers[item.id]();
  const geometryHash = digest(diagram.replace(/<text\b[\s\S]*?<\/text>/g, ''));
  if (graphHashes.has(geometryHash)) throw new Error(`Repeated diagram: ${item.id}`);
  graphHashes.add(geometryHash);
  const svg = svgFor(item, diagram);
  if (/<script\b|<foreignObject\b|(?:xlink:)?href\s*=|\bon[a-z]+\s*=/i.test(svg)) throw new Error(`Unsafe SVG: ${item.id}`);
  const relative = `assets/production/${group[item.category]}/${item.id}/sketch/structure-v1.svg`;
  const absolute = path.join(root, relative);
  fs.mkdirSync(path.dirname(absolute), { recursive: true });
  fs.writeFileSync(absolute, svg, 'utf8');
  records.push({ id: item.id, path: relative, role: 'technical-sketch', note: '可编辑概念结构/空间关系草图；非实测比例、非历史实址、非精确复原，不替代写实原画、模型或史料。', geometrySha256: geometryHash, sha256: digest(svg) });
}
const metadata = {
  schemaVersion: 1,
  generatedBy: 'tools/build-environment-resource-sketches.mjs',
  source: sourcePath,
  sourceSha256: digest(sourceBytes),
  outputKind: 'editable-svg-technical-sketch',
  disclaimer: '概念结构示意；无真实经纬坐标与尺寸承诺；不是历史实址、实测比例或写实原画。',
  count: records.length,
  items: records,
};
const metaPath = path.join(root,'docs/production/resource-library/parts/environment-sketches.json');
fs.writeFileSync(metaPath, JSON.stringify(metadata,null,2)+'\n','utf8');
if (digest(fs.readFileSync(path.join(root,sourcePath))) !== digest(sourceBytes)) throw new Error('Frozen environment source changed while generating.');
console.log(`Generated ${records.length} unique environment technical sketches; source unchanged.`);
