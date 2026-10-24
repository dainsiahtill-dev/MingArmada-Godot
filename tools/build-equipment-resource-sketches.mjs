import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'docs/production/resource-library/parts/equipment.json');
const destination = path.join(root, 'docs/production/resource-library/parts/equipment-sketches.json');
const { items } = JSON.parse(fs.readFileSync(source, 'utf8'));
const directory = { cannon:'cannons', firearm:'firearms', 'melee-weapon':'melee-weapons', ammunition:'ammunition', prop:'props' };
const color = { ink:'#243844', paper:'#f7f1df', muted:'#69746e', wood:'#b38a59', woodDark:'#795b3e', metal:'#819495', dark:'#455b61', brass:'#ba9c5f', cloth:'#c4b596', rope:'#bba77a', red:'#9d4d3f', white:'#e6dfc9', blue:'#526f82' };
const esc = value => String(value).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
const attrs = values => Object.entries(values).map(([k,v])=>`${k}="${esc(v)}"`).join(' ');
const element = (tag,a,body='') => `<${tag} ${attrs(a)}>${body}</${tag}>`;
const p = (d,fill=color.wood,extra={})=>element('path',{d,fill,stroke:color.ink,'stroke-width':3,'stroke-linejoin':'round',...extra});
const r = (x,y,width,height,fill=color.wood,extra={})=>element('rect',{x,y,width,height,fill,stroke:color.ink,'stroke-width':3,...extra});
const c = (cx,cy,radius,fill=color.metal,extra={})=>element('circle',{cx,cy,r:radius,fill,stroke:color.ink,'stroke-width':3,...extra});
const ell = (cx,cy,rx,ry,fill=color.cloth,extra={})=>element('ellipse',{cx,cy,rx,ry,fill,stroke:color.ink,'stroke-width':3,...extra});
const l = (x1,y1,x2,y2,stroke=color.ink,width=3,extra={})=>element('line',{x1,y1,x2,y2,stroke,'stroke-width':width,...extra});
const t = (x,y,text,size=19,fill=color.ink,extra={})=>element('text',{x,y,fill,'font-size':size,'font-family':"'Noto Sans SC','Microsoft YaHei',sans-serif",...extra},esc(text));
const g = (transform,body)=>element('g',{transform},body);
const rings = (x,y,count,step,radius=14)=>Array.from({length:count},(_,i)=>c(x+i*step,y,radius,'none',{'stroke-width':5})).join('');
const grain = (x,y,w,h)=>[.2,.45,.7].map((f,i)=>p(`M${x+10} ${y+h*f} q${w*.22} ${i%2?12:-9} ${w*.45} 0 t${w*.4} 0`,'none',{stroke:color.woodDark,'stroke-width':1.6})).join('');
const callout = (x,y,tx,ty,label)=>l(x,y,tx-12,ty-7,color.muted,1.6)+c(x,y,3,color.ink,{'stroke-width':0})+t(tx,ty,label,17,color.ink);
const badge = (x,y,text,fill=color.white)=>r(x,y,Math.max(100,text.length*17+24),32,fill,{rx:4,'stroke-width':1})+t(x+12,y+23,text,16);
const rope = (d,width=10)=>p(d,'none',{stroke:color.woodDark,'stroke-width':width+3,'stroke-linecap':'round'})+p(d,'none',{stroke:color.rope,'stroke-width':width,'stroke-linecap':'round','stroke-dasharray':'5 2'});
const sheetNotes = (left,right)=>t(88,570,left,18,color.muted)+t(88,603,right,18,color.muted);
const woodBox = (x=180,y=250,w=350,h=170,lid=true)=>p(`M${x} ${y} l70 -35 h${w} l-70 35 Z`,color.wood)+r(x,y,w,h,color.wood)+p(`M${x+w} ${y} l70 -35 v${h} l-70 35 Z`,color.woodDark)+[1,2,3].map(i=>l(x+i*w/4,y,x+i*w/4,y+h,color.woodDark,2)).join('')+grain(x,y,w,h)+(lid?l(x,y+28,x+w,y+28,color.woodDark,2):'');
const smallBag = (variant='plain')=>{
 let body=p('M325 225 Q305 270 267 307 Q225 368 268 440 Q338 473 443 437 Q480 367 431 309 Q399 274 401 226 Z',variant==='red'?color.red:color.cloth);
 body+=p('M325 226 Q353 245 401 226 L410 246 Q360 262 316 246 Z',color.rope)+rope('M317 247 Q352 266 409 245',5)+p('M288 333 Q333 353 309 430 M405 324 Q373 367 417 428','none',{stroke:color.woodDark,'stroke-width':2});
 if(variant==='red')body+=p('M284 353 l24 0 l0 29 l-24 0 Z',color.white)+l(284,353,308,382,color.red,1.5)+l(308,353,284,382,color.red,1.5);
 return body;
};
function cannon(type){
 if(type==='swivel')return p('M150 302 L640 273 L680 286 L680 330 L640 342 L150 329 Z',color.metal)+r(682,280,105,65,color.dark,{rx:10})+p('M691 287 H775 V337 H691 Z',color.paper)+l(788,312,875,328,color.dark,19)+c(550,311,14,color.dark)+callout(260,300,130,200,'细长炮管外轮廓')+callout(735,281,650,190,'后框：只示整体外形')+callout(550,311,500,426,'炮耳挂点')+callout(845,323,780,426,'尾柄外轮廓')+sheetNotes('外观方案；母铳单列，子铳与叉架另交。','铁／铜仅材质变体；具体中国型号、比例与铭款待证。');
 const heavy=type==='heavy', y=heavy?298:313;
 let b=p(heavy?'M150 283 L180 290 L565 256 L730 247 Q779 258 785 294 Q782 334 735 343 L565 339 L180 316 L150 324 Z':'M175 301 L201 307 L568 280 L689 280 Q738 286 740 318 Q738 346 690 349 L568 343 L202 328 L175 335 Z',color.metal);
 b+=ell(heavy?154:179,heavy?304:318,11,heavy?21:17,color.dark);
 b+=[heavy?585:585,heavy?700:670].map(x=>r(x,heavy?254:282,16,heavy?86:65,color.dark)).join('');
 b+=p(heavy?'M782 286 Q829 271 835 295 Q833 320 783 309 Z':'M737 310 Q773 296 782 319 Q775 338 738 328 Z',color.dark)+c(heavy?565:530,y,16,color.dark);
 return b+callout(300,294,130,205,heavy?'前段收窄的长管':'轻炮：紧凑外形')+callout(715,250,650,194,heavy?'后部厚重／简节箍':'炮尾与节箍')+callout(heavy?565:530,y,440,447,'炮耳：与独立炮架对位')+sheetNotes(heavy?'红夷式重炮外观创作方案，非料罗湾单炮复原。':'轮式轻炮方案；保留a2_s8坏轮轴剧情，型号未证。','只画外观，不示内部、尺寸、装药或制作工序。');
}
function carriage(){
 return p('M220 310 L303 260 H630 L701 309 L690 409 H212 Z',color.wood)+p('M240 294 L305 267 H621 L676 294 Z',color.paper)+r(255,326,416,26,color.woodDark)+[275,629].map(x=>c(x,409,49,color.woodDark)+c(x,409,20,color.wood)+l(x,364,x,454,color.wood,3)+l(x-45,409,x+45,409,color.wood,3)).join('')+p('M355 303 Q370 277 387 303 M548 303 Q563 277 580 303','none',{'stroke-width':8})+callout(371,292,120,188,'炮耳座：仅外部挂点')+callout(445,341,630,212,'厚木侧板与横梁')+callout(629,410,720,448,'木轮／轮轴节点')+sheetNotes('炮架与炮身分交；断轴用可切换节点表达。','轻重炮适配范围须美术／动画审查；不输出工程尺寸。');
}
function mount(){
 return p('M330 260 Q300 365 380 384 L520 384 Q602 363 570 260 L542 260 Q570 345 512 353 H389 Q337 343 357 260 Z',color.dark)+c(345,268,20,color.metal)+c(556,268,20,color.metal)+r(435,383,30,93,color.dark)+p('M320 474 l70 -28 h171 l58 29 v49 H320 Z',color.wood)+grain(325,480,285,35)+callout(344,268,130,186,'叉端：外侧承接位置')+callout(575,321,665,246,'U形叉架轮廓')+callout(449,431,640,432,'竖直支轴／木座挂点')+sheetNotes('佛朗机候选安装模块；船舷与炮身另列。','参照同代旋回炮类比；福建具体安装式样待证。');
}
function chamber(){
 return p('M310 273 Q388 246 460 273 L474 408 Q389 435 305 410 Z',color.metal)+ell(385,271,76,22,color.dark)+p('M459 305 Q565 284 553 355 Q539 403 473 381 L470 359 Q517 377 525 343 Q530 318 463 329 Z',color.dark)+p('M323 315 Q380 335 456 313','none',{stroke:color.dark,'stroke-width':2})+callout(343,350,120,199,'短筒外形／金属区')+callout(538,333,630,231,'外露把手：抓握点')+callout(416,409,620,442,'与母铳分开的外部件')+sheetNotes('佛朗机子铳，非炮弹、现代弹壳或个人火器。','只绘整体外觀；不畫內腔、裝填、配合尺寸或操作步驟。');
}
function firearm(short=false){
 let b=short?p('M220 317 L602 299 L713 310 L713 338 L408 349 L383 406 L283 410 L309 348 L220 343 Z',color.wood):p('M155 339 L300 339 L327 299 L443 294 L451 309 L883 309 L883 337 L432 343 L376 409 L283 407 L304 349 L155 355 Z',color.wood);
 b+=short?p('M250 298 L708 289 L708 315 L250 325 Z',color.metal):p('M184 287 H884 V311 H184 Z',color.metal);
 b+=short?r(510,292,14,54,color.dark):[450,650,810].map(x=>r(x,283,11,35,color.dark)).join('');
 b+=p(short?'M384 304 Q376 267 400 264 Q419 266 424 291':'M382 302 Q374 258 402 260 Q422 262 425 290','none',{stroke:color.dark,'stroke-width':8});
 b+=callout(short?325:290,303,130,194,short?'短铳外轮廓：待证':'长火绳枪管外轮廓')+callout(short?325:336,382,130,466,short?'近直短木柄：暂定':'朴素木托与手位')+callout(402,274,625,200,'火绳夹只作外轮廓')+sheetNotes(short?'剧情确有短铳；1631福建具体形制未证，先审后定稿。':'鸟铳／长火绳枪：区域同代类比，非郑氏实物复原。','无内部机构、尺寸、装药或制作／操作步骤；禁现代枪械元素。');
 return b;
}
function blade(long=false){
 const end=long?897:758, start=long?365:375;
 let b=p(`M${start} 290 Q${end-140} 315 ${end} 256 Q${end-25} 313 ${end-134} 338 L${start} 325 Z`,color.metal)+r(long?155:235,296,long?195:120,28,color.woodDark,{rx:8})+r(350,277,19,68,color.brass);
 b+=Array.from({length:long?9:5},(_,i)=>l((long?172:249)+i*18,298,(long?160:237)+i*18,322,color.rope,4)).join('');
 b+=p(`M${long?365:381} 405 Q${end-130} 429 ${end-8} 379 L${end+4} 407 Q${end-133} 464 ${long?365:381} 438 Z`,color.woodDark)+rope(`M${long?410:430} 414 q-20 50 -38 43`,5);
 return b+callout(long?530:500,318,570,201,long?'长单刃弧线：刀型待审':'短单刃：紧凑刀身')+callout(long?230:288,309,120,204,long?'双手柄与简护手':'单手柄与窄护手')+callout(470,437,650,490,'木鞘独立节点／腰带挂点')+sheetNotes(long?'原创雇佣刀手用；不以刀型替代人物国籍判断。':'主角防身、缴刀、桌上刀鞘与装备页共用。','仅美术外形；不提供刃口、锻造或使用技术。');
}
function spear(){
 return p('M180 326 L703 296 L703 314 L180 345 Z',color.wood)+p('M704 296 L826 237 L870 278 L714 317 Z',color.metal)+r(688,291,34,31,color.dark)+callout(810,273,650,172,'窄金属枪头：形制待审')+callout(447,320,300,457,'直木杆／双手持位')+sheetNotes('守船长枪；与篙、长钩和个人火器区分。','不加奇幻巨刃；本图只示外观、材料分区与角色比例关系。');
}
function ammo(type){
 if(type==='solid')return c(420,340,112,color.dark)+ell(380,303,34,20,color.metal,{'stroke-width':0,opacity:.5})+r(255,452,330,30,color.wood)+callout(488,277,645,223,'单枚球形弹：深铁色')+callout(456,460,645,440,'可选储放木托')+sheetNotes('实心弹：UI图、甲板弹架和库存共用。','球体重复实例；不标口径、重量或火器性能。');
 if(type==='chain')return c(220,340,75,color.dark)+c(780,340,75,color.dark)+Array.from({length:18},(_,i)=>{const x=290+i*25,y=348+54*Math.sin(i/17*Math.PI*1.45);return ell(x,y,i%2?12:18,i%2?18:10,'none',{stroke:color.dark,'stroke-width':5,transform:'rotate('+(i%2?20:-15)+' '+x+' '+y+')'});}).join('')+callout(220,302,105,207,'端部外轮廓')+callout(482,383,620,471,'相连铁链／收拢配置')+sheetNotes('链弹：既有游戏弹种，不声称各场史实均曾使用。','仅外观与连接关系，不画制作、装填或性能细节。');
 if(type==='grape'){
  let b=p('M300 245 Q425 207 548 251 L577 430 Q425 486 276 429 Z',color.cloth);
  for(let row=0;row<3;row++)for(let col=0;col<4;col++)b+=c(330+col*63+(row%2?14:0),285+row*59,25,color.dark);
  b+=rope('M294 362 Q435 395 565 361',8)+rope('M417 243 L421 457',7);
  return b+callout(336,286,110,195,'小圆丸的组合轮廓')+callout(557,361,660,233,'外布／绳束分区')+sheetNotes('葡萄弹包：现有游戏弹种的外观说明。','不绘内部层次、数量标准、配方或装药参数。');
 }
 let b=smallBag('plain')+[0,1,2,3].map((v)=>c(530+v*44,430+(v%2)*20,16,color.dark)).join('');
 return b+callout(354,247,120,190,'扎口小袋／腰带系点')+callout(596,439,665,330,'少量小丸：非现代定装弹')+sheetNotes('个人火器携带物；软袋复用红线袋基础拓扑。','小丸只作美术比例示意，不标尺寸、材质配比或性能。');
}
function crate(){
 return woodBox()+r(298,250,44,171,color.red,{'stroke-width':1})+r(300,318,39,48,color.white,{'stroke-width':1})+t(307,348,'封',23,color.red)+rope('M180 278 L530 278 L600 243',5)+callout(300,337,680,210,'红封为贴图变体')+callout(529,312,680,403,'拼板／盖板独立节点')+sheetNotes('托运、争议货与抛货共用木货箱。','封记为原创，不抄真实商号；货物内容另列。');
}
function barrel(bucket=false){
 const x=bucket?330:300,w=bucket?250:300,top=bucket?287:247,bottom=465;
 let b=p(`M${x} ${top} Q${x-25} ${(top+bottom)/2} ${x+18} ${bottom} Q${x+w/2} ${bottom+28} ${x+w-18} ${bottom} Q${x+w+25} ${(top+bottom)/2} ${x+w} ${top} Z`,color.wood)+ell(x+w/2,top,w/2,29,bucket?color.dark:color.wood);
 b+=[1,2,3,4].map(i=>p(`M${x+i*w/5} ${top+15} Q${x+i*w/5-5} 360 ${x+18+i*(w-36)/5} ${bottom}`,'none',{stroke:color.woodDark,'stroke-width':2})).join('');
 b+=[top+55,bottom-35].map(y=>p(`M${x-8} ${y} Q${x+w/2} ${y+35} ${x+w+8} ${y}`,'none',{stroke:color.dark,'stroke-width':11})).join('');
 if(bucket)b+=p(`M${x+7} ${top+12} Q${x+w/2} ${top-200} ${x+w-7} ${top+12}`,'none',{stroke:color.woodDark,'stroke-width':13});
 else b+=p('M415 335 l-12 28 l13 21 l-4 32','none',{stroke:color.ink,'stroke-width':3})+r(389,363,52,10,color.woodDark);
 return b+callout(x+w/2,top,650,196,bucket?'开放桶口／提梁':'储水大桶／闭顶')+callout(x+44,bottom-35,650,445,bucket?'木桶板／箍与提手挂点':'裂缝／补缝局部状态')+sheetNotes(bucket?'小桶单手提携；救火、堵漏和生活取水共用。':'储水体量与提水小桶不同；水量不增加基模。','木材与箍材质待审，不作特定地方器具的精确复原。');
}
function bale(){
 return p('M250 295 L316 248 H633 L567 295 Z',color.white)+r(250,295,317,151,color.cloth,{rx:14})+p('M567 295 l66 -47 v151 l-66 47 Z',color.rope)+rope('M330 286 V445',9)+rope('M483 286 V445',9)+p('M267 334 Q310 351 355 336 M412 407 Q468 422 545 406','none',{stroke:color.woodDark,'stroke-width':2})+r(389,295,42,60,color.red)+g('translate(690 337)',ell(0,0,45,27,color.white)+r(-45,0,90,104,color.cloth)+ell(0,104,45,27,color.white))+callout(400,324,650,192,'包布封记／货包绑索')+callout(687,420,685,494,'家用小布卷配置')+sheetNotes('布／丝绸货包、家用布与货舱展示共用形体家族。','布色与纹理不增基模；花纹、包法为待审概念。');
}
function sack(spice=false){
 let b=smallBag(spice?'plain':'plain');
 b+=r(335,315,60,64,spice?color.red:color.white,{'stroke-width':1})+t(347,357,spice?'香':'米',28,spice?color.white:color.ink);
 if(spice)for(let i=0;i<14;i++)b+=p(`M${560+(i%5)*24} ${382+Math.floor(i/5)*25} q12 -8 17 2 q-3 12 -17 8 Z`,i%2?color.woodDark:color.brass);
 else for(let i=0;i<18;i++)b+=ell(560+(i%6)*23,385+Math.floor(i/6)*18,7,3,color.white,{'stroke-width':1});
 return b+callout(361,244,120,180,'扎口与提抓点')+callout(366,338,650,225,spice?'香料货标：材质变体':'粮袋货标／粗布纹理')+sheetNotes(spice?'香料袋直接复用粮袋主体，商品名称不增加袋体基模。':'米粮袋：饱满／半空用同拓扑形变。','少量内容只作识别，品种、包法与货标均非史实认证。');
}
function jar(){
 return p('M370 223 H500 L493 274 Q598 315 560 440 Q537 473 435 478 Q332 471 310 440 Q271 316 377 274 Z',color.white)+ell(435,223,66,18,color.blue)+ell(435,263,59,15,color.white)+p('M324 359 Q435 388 547 359','none',{stroke:color.blue,'stroke-width':13})+p('M350 381 q28 -26 55 0 t55 0 t55 0','none',{stroke:color.blue,'stroke-width':3})+callout(494,230,655,184,'短颈／包口或盖节点')+callout(551,367,660,420,'圆腹与朴素釉色分区')+sheetNotes('瓷货罐：市场、货舱、家居复用。','不标具体官窑、窑口或复原年代；装饰仅概念。');
}
function basket(){
 let b=p('M250 298 Q435 259 620 298 L584 446 Q435 486 286 446 Z',color.rope)+ell(435,298,185,39,color.dark);
 for(let i=0;i<9;i++)b+=p(`M${277+i*39} 310 Q${300+i*33} 370 ${294+i*34} 445`,'none',{stroke:color.wood,'stroke-width':5});
 for(let i=0;i<5;i++)b+=p(`M${263+i*5} ${333+i*24} Q435 ${365+i*25} ${606-i*5} ${333+i*24}`,'none',{stroke:color.woodDark,'stroke-width':3});
 b+=p('M280 308 Q435 99 590 308','none',{stroke:color.wood,'stroke-width':15});
 return b+callout(434,199,660,187,'可选弧形提手')+callout(537,406,670,439,'粗竹编／底圈')+sheetNotes('空篮与装果配置共用，内容物独立。','货栈果筐有剧情；编法和提手样式待审。');
}
function coil(){
 let b='';
 for(let i=0;i<7;i++)b+=ell(430,350,190-i*18,110-i*10,'none',{stroke:color.woodDark,'stroke-width':12})+ell(430,350,190-i*18,110-i*10,'none',{stroke:color.rope,'stroke-width':8,'stroke-dasharray':'8 4'});
 return b+rope('M608 372 Q731 473 810 408',10)+callout(413,271,120,190,'麻绳绞股／盘卷')+callout(765,432,700,497,'自由端／连接挂点')+sheetNotes('盘卷、拉直、断索用同材料与曲线家族。','只示外观；不输出绳结操作和施工步骤。');
}
function net(){
 let b=p('M251 246 L633 246 L686 442 Q440 486 197 442 Z',color.cloth,{opacity:.18});
 for(let i=0;i<9;i++)b+=rope(`M${251+i*47} 247 L${197+i*61} 442`,4);
 for(let i=0;i<6;i++)b+=rope(`M${240-i*8} ${265+i*33} Q440 ${283+i*34} ${645+i*8} ${265+i*33}`,4);
 b+=rope('M251 246 Q440 213 633 246 L686 442 Q440 486 197 442 Z',8)+[251,633].map(x=>c(x,246,13,'none'));
 return b+callout(252,248,110,182,'边绳／吊点')+callout(492,360,710,363,'大网眼与结点')+sheetNotes('货网只围合既有箱、袋、包，内容物不烘死。','空网与包货配置共用；不新增每种装货模型。');
}
function bollard(){
 return p('M263 384 l105 -32 h240 l67 38 v62 H263 Z',color.woodDark)+r(337,251,80,166,color.wood)+r(520,251,80,166,color.wood)+r(314,248,309,34,color.woodDark)+rope('M323 356 Q442 408 610 345',13)+callout(357,279,110,193,'粗木柱／上横头')+callout(525,375,690,435,'绳绕位／固定底部')+sheetNotes('船甲板与港口缆桩共享；环境装配引用本条。','待证概念，避免现代铸钢港机轮廓。');
}
function lantern(paper=false){
 let b='';
 if(paper){
  b=p('M350 236 Q450 192 550 236 Q612 337 550 443 Q450 485 350 443 Q289 337 350 236 Z',color.white);
  for(let i=0;i<7;i++)b+=p(`M${353+i*31} 234 Q${330+i*40} 335 ${353+i*31} 445`,'none',{stroke:color.wood,'stroke-width':2});
  b+=r(329,322,62,67,color.cloth,{'stroke-dasharray':'5 4','stroke-width':2})+p('M398 221 Q450 147 500 221','none',{stroke:color.wood,'stroke-width':6});
 }else{
  b=p('M335 258 L393 222 H519 L574 258 L551 447 H358 Z',color.woodDark)+r(366,271,174,156,color.white,{opacity:.75})+l(394,260,390,438,color.wood,8)+l(511,260,516,438,color.wood,8)+ell(454,447,101,17,color.woodDark)+p('M408 220 Q454 145 500 220','none',{stroke:color.dark,'stroke-width':8});
 }
 b+=ell(450,389,22,42,color.brass,{'stroke-width':0,opacity:.55})+callout(450,194,660,181,'提拿／悬挂点')+callout(paper?349:390,350,100,403,paper?'补纸一角／竹架':'灯框／护罩材质分区');
 return b+sheetNotes(paper?'平户手糊纸灯：两人共同修补的叙事物件。':'船灯／提灯：灭灯保留形体，火光为独立效果。','器形、材料与地方细节待证；不当作精确文物复原。');
}
function furniture(type){
 if(type==='bench')return p('M225 294 L300 265 H667 L592 294 Z',color.wood)+r(225,294,367,39,color.wood)+[248,531].map(x=>p(`M${x} 331 h33 l26 131 h-43 Z`,color.woodDark)).join('')+r(277,409,299,18,color.wood)+grain(230,299,350,25)+callout(418,294,120,190,'窄木座面／坐点')+callout(550,425,680,436,'横撑／落地接触点')+sheetNotes('长凳可同结构调长；刀鞘和角色另列。','朴素家具概念，非明代地域家具鉴定图。');
 if(type==='table')return [321,649].map(x=>r(x,x===649?239:245,25,186,color.woodDark)).join('')+p('M190 275 L291 219 H695 L594 275 Z',color.wood)+r(190,275,404,41,color.woodDark)+[225,548].map(x=>r(x,316,30,180,color.wood)).join('')+r(239,427,315,18,color.woodDark)+grain(205,276,380,35)+callout(420,258,105,179,'桌面：独立摆放道具')+callout(551,435,680,456,'桌腿／横撑')+sheetNotes('货栈谈判、账务和家庭饭桌共用。','不烘焙碗、纸、刀；避免宫廷家具装饰。');
 return p('M214 322 L320 258 H693 L587 322 Z',color.woodDark)+r(214,322,373,95,color.wood)+p('M243 309 L335 272 H650 L562 309 Z',color.cloth)+r(243,309,319,80,color.white,{rx:16})+p('M340 292 Q431 280 541 297 L519 393 H323 Z',color.blue)+p('M265 303 l55 -19 l67 10 l-48 20 Z',color.cloth)+p('M358 312 Q413 329 507 319 M351 350 Q435 368 525 352','none',{stroke:color.white,'stroke-width':3})+callout(339,300,100,190,'枕位／铺位接触区')+callout(494,362,690,429,'被褥与铺架分节点')+sheetNotes('床铺与被褥模块：两岸摆放需分别审查。','不将同一日式地铺默认铺到福建全部家居场景。');
}
function chest(tool=false){
 let b=woodBox(tool?260:210,tool?310:286,tool?300:390,tool?127:164);
 b+=r(tool?396:385,tool?321:298,36,55,color.dark,{rx:3})+r(tool?407:396,tool?340:317,13,22,color.brass);
 b+=p(tool?'M337 294 V257 H486 V294':'M611 330 Q679 333 669 368 H620','none',{stroke:color.dark,'stroke-width':10});
 if(tool)b+=p('M290 311 L320 267 L600 267 L570 311 Z',color.woodDark)+l(353,274,377,309,color.wood,8)+p('M451 274 l0 36 M434 284 h34','none',{stroke:color.metal,'stroke-width':10});
 return b+callout(tool?411:400,345,125,195,tool?'工具箱扣件／基本装载':'衣箱扣件／平盖')+callout(tool?410:647,tool?260:346,690,226,tool?'提把／携行抓点':'侧把手／双人搬抬点')+sheetNotes(tool?'阿旺本人所有；工具从已列道具共享，不暗含工具全集。':'母亲送子与1646取回行李箱的同一形体家族。','盖体保留独立节点；具体箱式为待证概念。');
}
function pot(){
 return p('M290 300 Q270 461 443 470 Q615 463 596 300 Z',color.dark)+ell(443,299,151,34,color.metal)+p('M294 325 Q190 274 214 367 Q228 398 294 378 M596 325 Q700 274 676 367 Q663 398 596 378','none',{stroke:color.dark,'stroke-width':16})+p('M346 276 Q443 221 540 276 Z',color.metal)+r(421,237,44,19,color.woodDark,{rx:6})+callout(445,252,660,180,'可选锅盖／抓点')+callout(226,349,100,440,'双耳／烟熏锅底')+sheetNotes('船岸热饭与家居道具共用。','锅具型制待审；不随饭菜种类重复建模。');
}
function bowl(){
 return p('M280 315 Q300 443 444 456 Q588 443 608 315 Z',color.white)+ell(444,315,164,42,color.cloth)+ell(444,465,70,14,color.woodDark)+p('M318 344 Q444 373 571 344','none',{stroke:color.blue,'stroke-width':5})+callout(444,314,650,202,'开放碗口／盛饭节点')+callout(511,439,650,458,'低足与捧碗接触区')+sheetNotes('阿禾冷饭、小儿留碗、母子饭桌与翻碗共用。','陶釉颜色为变体，不标特定窑口或器物复原。');
}
function document(type){
 const colors={letter:color.white,chart:color.white,receipt:color.cloth,contract:color.white,official:color.white};
 let b=p('M250 230 L620 217 L651 465 L270 483 Z',colors[type])+p('M425 225 L440 473 M263 348 L637 337','none',{stroke:color.rope,'stroke-width':2,'stroke-dasharray':'7 5'});
 if(type==='chart'){
  b+=p('M318 371 Q406 344 561 361 L527 407 H350 Z',color.wood)+p('M431 352 V267 L505 344 Z',color.white)+p('M455 345 L457 286 L503 342','none',{stroke:color.red,'stroke-width':2})+t(295,264,'歪船图／水程笺',18);
 }else{
  const titles={letter:'家书',receipt:'损货回单',contract:'合货／托运凭据',official:'任职／通行文书'};
  b+=t(291,267,titles[type],23);
  for(let col=0;col<6;col++)for(let row=0;row<5;row++)b+=l(303+col*46,293+row*22,318+col*46,293+row*22,color.muted,2);
  if(type!=='letter')b+=r(526,390,59,51,color.red,{'stroke-width':1})+t(534,423,type==='receipt'?'收':'记',24,color.white);
  if(type==='official')b+=r(245,220,19,254,color.blue)+r(614,220,17,245,color.blue);
 }
 b+=p('M732 299 l93 -6 l22 140 l-98 6 Z',color.cloth)+p('M736 352 l100 -4','none',{stroke:color.woodDark,'stroke-width':2});
 return b+callout(425,346,110,183,'折痕／薄纸：共享基模')+callout(785,367,714,493,'折叠携行配置')+sheetNotes(type==='chart'?'船图为家族创作；水程与针路文字另行史料校核。':'正文、封记与格式为可编辑内容，不作为真实历史原件。','纸张文种共享几何；UI正文须独立排字，不用本图伪字当史料。');
}
function tally(){
 return p('M310 253 L537 245 L567 281 L543 312 L568 348 L545 455 L320 465 L298 418 L318 393 L294 361 Z',color.wood)+grain(315,270,220,170)+p('M380 285 l-11 131 M411 280 l-11 131 M448 299 l-10 114','none',{stroke:color.woodDark,'stroke-width':5})+callout(302,360,110,190,'可辨缺口：几何轮廓')+callout(406,357,665,230,'旧刻痕／磨圆边')+sheetNotes('阮老六原创索路凭据，持有不等于所有海域免检。','识记仅供剧情，不冒充明代通行制度实物。');
}
function rack(){
 let b=[245,648].map(x=>p(`M${x} 470 L${x+55} 233 L${x+117} 470 Z`,'none',{stroke:color.woodDark,'stroke-width':15})).join('')+l(299,234,704,234,color.wood,17);
 b+=g('translate(10 30) scale(.75 .8)',net().split('<text')[0]);
 return b+callout(490,234,100,177,'横杆／挂网点')+callout(720,408,760,445,'粗木双架')+sheetNotes('P2可省陈设；挂网独立引用绳网模块。','海边生活概念，不作特定渔具复原。');
}
function timber(wreck=false){
 let b='';
 for(let i=0;i<3;i++){
  let x=220+i*64,y=305-i*22;
  b+=p(wreck?`M${x} ${y} l43 -28 l18 18 l23 -23 l405 -25 l-29 39 l24 16 l-464 58 Z`:`M${x} ${y} l51 -26 l415 -17 l-48 32 Z`,wreck?(i%2?color.dark:color.woodDark):color.wood);
  b+=p(`M${x} ${y} l0 40 l466 -42 v-35`,wreck?color.woodDark:color.woodDark)+grain(x+20,y+2,430,29);
 }
 if(!wreck)b+=rope('M363 258 L374 365 M571 242 L585 344',9);
 return b+callout(382,290,120,182,wreck?'断裂毛边／湿木或焦黑':'成束备料／端纹')+callout(646,293,710,428,wreck?'有限木段重复实例':'捆绳挂点／板梁分区')+sheetNotes(wreck?'破船木段共用；不暗示找回郑芝虎遗体。':'六货种与修船共用；不按库存数量重复建模。','木材种类与规格待审；没有工程尺寸或制作工序。');
}
function toolbelt(){
 let b=p('M200 285 Q446 331 719 283 L734 336 Q464 389 193 335 Z',color.cloth)+r(221,291,56,54,color.dark)+r(233,302,33,30,color.brass);
 b+=p('M377 332 V430 H418 V338 M500 340 V438 H541 V336','none',{stroke:color.woodDark,'stroke-width':8})+r(385,295,24,115,color.wood)+p('M357 304 h78 l-14 -40 h-48 Z',color.metal)+r(508,287,23,128,color.woodDark)+r(502,392,35,40,color.metal)+r(613,309,59,42,color.white,{'stroke-dasharray':'4 4','stroke-width':1})+callout(644,330,714,201,'女儿缝补的识别细节')+callout(401,364,120,195,'工具挂环／腰部绑点')+sheetNotes('阿旺工具带：挂件和工具箱共享小件。','本人所有；道具可复用，不代替人物自主去留。');
 return b;
}
function axe(){
 return p('M278 458 L310 472 L590 234 L571 211 Z',color.wood)+p('M528 205 Q602 168 689 213 L651 303 L565 279 L550 256 Z',color.metal)+r(557,223,35,35,color.woodDark)+grain(350,383,135,30)+callout(614,235,700,179,'朴素铁斧头')+callout(407,370,120,193,'直木柄／双手抓点')+sheetNotes('砍桅、断索与船务工具共用；禁奇幻战斧比例。','只示外观，不给刃口、锻造或操作技术。');
}
function polehook(){
 return p('M172 363 L188 381 L736 262 L730 245 Z',color.wood)+p('M722 250 L745 243 Q807 168 843 222 Q864 263 808 292 L792 278 Q828 254 820 233 Q811 212 763 268 L737 277 Z',color.metal)+callout(812,242,660,177,'窄铁钩头／钩索接触点')+callout(416,319,135,451,'长直木杆／双手持位')+sheetNotes('长柄篙钩：区别枪头、无叶船篙与短索挠钩。','只示美术轮廓，具体地方钩式待证。');
}
function grapnel(){
 return p('M433 277 V390 M433 374 Q333 438 302 340 M433 374 Q536 439 566 340 M433 374 Q449 475 505 455','none',{stroke:color.dark,'stroke-width':17})+c(433,258,24,'none',{'stroke-width':11})+rope('M431 232 Q365 190 285 250 Q211 317 233 409 Q269 467 337 450',12)+callout(431,259,665,190,'绳环：独立连接挂点')+callout(532,408,665,445,'短索多爪钩：爪数待审')+sheetNotes('钩头与绳体分资源；漂索／挂舷由配置表达。','不使用现代登山扣，不提供结绳或攀登操作。');
}
function plank(){
 let b=p('M190 377 L613 239 L718 279 L293 431 Z',color.wood)+p('M293 431 L718 279 V304 L294 457 L190 403 V377 Z',color.woodDark);
 for(let i=0;i<5;i++)b+=p(`M${257+i*73} ${355-i*25} l83 27 l0 13 l-83 -27 Z`,color.woodDark);
 b+=callout(238,388,100,203,'端部搭接区')+callout(521,328,690,434,'可选横条／木板面');
 return b+sheetNotes('接舷过板与码头跳板共用；人物与船体另列。','按角色画面比例审查，不给施工、尺寸或搭建步骤。');
}
function oar(pole=false){
 if(pole)return p('M175 382 L183 397 L853 225 L847 210 Z',color.wood)+[0,1,2,3,4,5].map(i=>l(234+i*100,365-i*25,245+i*100,375-i*25,color.woodDark,3)).join('')+callout(491,306,120,183,'竹／木长直杆，无枪刃、桨叶')+callout(822,225,710,455,'磨损端／折断端节点')+sheetNotes('撑船篙：救援、近岸撑船与离泊共用。','材质与具体地方形式待证；不含尺寸或操作教学。');
 return p('M179 376 L188 395 L696 263 L688 243 Z',color.wood)+p('M686 244 Q768 199 855 209 L881 251 Q801 295 699 264 Z',color.woodDark)+grain(705,235,140,25)+callout(465,310,100,184,'长柄／手位')+callout(810,246,650,169,'长橹／手桨叶片节点')+sheetNotes('长橹与应急桨共用材料，叶形和动作差异须审查。','不可把无叶篙、枪杆与桨混名；只作外观概念。');
}
function compass(){
 let b=ell(440,348,170,113,color.woodDark)+ell(440,329,170,113,color.brass)+ell(440,329,143,93,color.white);
 for(let i=0;i<24;i++){let a=i*Math.PI/12;b+=l(440+Math.cos(a)*130,329+Math.sin(a)*84,440+Math.cos(a)*(i%3?121:113),329+Math.sin(a)*(i%3?78:72),color.ink,2);}
 b+=p('M416 349 L461 273 L452 331 L419 384 Z',color.red)+c(440,329,7,color.dark)+t(431,249,'子',18)+t(430,418,'午',18)+t(309,335,'卯',18)+t(555,335,'酉',18);
 return b+callout(475,289,680,193,'磁针／盘面刻度：待证')+callout(316,371,110,203,'木／铜分区与持握边')+sheetNotes('现有UI铜制罗盘的审查草案，非明末器形定稿。','刻度只示视觉层次，真实盘面、罩盖与方位文字须史料核校。');
}
function medicine(){
 return smallBag()+g('translate(230 140) scale(.65)',p('M440 210 l158 -12 l29 115 l-160 20 Z',color.white)+l(465,265,611,257,color.red,6))+p('M573 421 q55 -25 100 -9 l11 33 q-52 -12 -100 11 Z',color.white)+callout(367,247,120,181,'布袋封口／递物点')+callout(597,319,690,228,'纸药包／独立裹伤布')+sheetNotes('医护补给外观；余量以UI文字表示，不画现代医疗十字。','不提供药方、制作方法或疗效承诺，器形仍需年代审查。');
}
function pouch(red){
 return smallBag(red?'red':'plain')+(red?p('M510 328 l151 -8 l16 107 l-157 6 Z',color.white)+p('M535 380 l102 -5 l-15 30 h-78 Z',color.wood)+p('M574 368 l0 -27 l25 25','none',{stroke:color.red,'stroke-width':2}):g('translate(230 65) scale(.65)',money(false)))+callout(358,246,120,177,'抽口／抓握点')+callout(red?297:350,red?366:365,690,193,red?'红线与旧补丁识别':'家用／交银仅内容变体')+sheetNotes(red?'亲情红线袋，歪船图另交纸面模块。':'钱袋与红线袋共享软袋拓扑，账目归属不能混同。','早晚旧化为状态，不为每次航程新增基模。');
}
function money(withNotes=true){
 let b='';
 for(let i=0;i<7;i++)b+=ell(300+i*41,350+(i%2)*8,29,36,color.brass)+r(291+i*41,340+(i%2)*8,18,18,color.dark,{'stroke-width':1});
 b+=rope('M282 365 Q405 395 565 369',7)+p('M637 327 l72 -26 l57 28 l-9 71 l-88 15 l-39 -34 Z',color.metal)+p('M639 326 l45 33 l80 -31 M684 359 l-14 56','none',{stroke:color.dark,'stroke-width':2});
 return b+(withNotes?callout(422,356,110,186,'方孔钱串／非现代金币')+callout(711,363,700,478,'朴素小银块：形态待审')+sheetNotes('金额以账目为准，不按银两数量堆叠等量3D。','具体币种与银形未定；不使用夸张统一元宝。'):'');
}
function flag(){
 return r(296,210,15,292,color.woodDark)+p('M312 221 Q426 187 533 224 Q646 261 745 210 L724 377 Q619 410 521 372 Q409 340 312 378 Z',color.white)+p('M335 242 Q425 215 522 248 Q620 284 712 237 L697 351 Q610 382 525 347 Q425 314 335 350 Z',color.blue)+t(469,317,'记',54,color.white)+rope('M308 221 Q275 240 309 266 M307 354 Q276 370 308 387',5)+callout(307,248,110,181,'旗绳／旗杆挂点')+callout(570,303,700,471,'旗纹为待证原创占位')+sheetNotes('白旗、保护旗、盟旗、官旗复用同一旗布，纹理另列。','不称郑氏实旗复原；禁现代国旗与后世制式军旗。');
}
function gong(){
 return c(420,343,125,color.brass)+c(420,343,99,color.brass,{'stroke-width':1})+c(420,343,32,color.wood)+rope('M367 232 Q419 150 473 232',8)+p('M618 390 L651 413 L740 274 L708 254 Z',color.wood)+ell(723,262,35,26,color.dark)+callout(423,194,665,176,'挂绳／提握点')+callout(421,344,120,202,'浅鼓锣面与木槌分区')+sheetNotes('湾口停火铜锣；只为剧情号令物件，不扩建乐器系统。','尺寸、铸纹与具体锣式待证。');
}
function torch(){
 return p('M363 462 L392 472 L523 289 L494 273 Z',color.woodDark)+p('M483 294 l-28 -69 l53 -35 l58 56 l-38 65 Z',color.cloth)+[0,1,2,3].map(i=>rope(`M${467+i*7} ${235+i*16} l64 -16`,5)).join('')+p('M490 222 Q464 153 512 123 Q503 169 539 180 Q571 151 560 114 Q628 195 548 245 Z',color.brass,{opacity:.7,'stroke-width':0})+callout(435,384,110,190,'木柄／抓握区')+callout(524,240,690,202,'布束外观；火焰独立效果')+sheetNotes('点亮／熄灭共享实体；禁止绘配制或点火工序。','形制为待证概念，不附制作、装药与使用参数。');
}
function iron(){
 let b='';
 for(let i=0;i<4;i++)b+=p(`M${220+i*90} ${341-i*17} l74 -44 l116 20 l-77 48 Z`,color.metal)+p(`M${220+i*90} ${341-i*17} v56 l113 23 v-55 Z`,color.dark)+p(`M${333+i*90} ${364-i*17} l77 -47 v54 l-77 48 Z`,color.metal);
 return b+rope('M352 310 L361 423 M565 270 L575 388',8)+callout(455,323,120,190,'朴素铁块／条坯：待审')+callout(571,377,710,447,'捆绳／搬抬接触区')+sheetNotes('六商品系统中的铁料，不新增矿冶工艺玩法。','具体流通形态待证；禁现代钢卷、螺纹钢与标准锭标。');
}
function scissors(){
 return ell(310,385,58,43,'none',{'stroke-width':16})+ell(462,399,58,43,'none',{'stroke-width':16})+p('M343 364 L438 281 L616 218 L464 339 L395 396 Z',color.metal)+p('M430 366 L441 294 L564 222 L477 355 Z',color.metal)+c(444,324,13,color.dark)+callout(332,390,110,204,'朴素环柄／单手抓点')+callout(529,269,675,190,'外露双刃与铰点轮廓')+sheetNotes('修纸灯与拆红封共用；只示外观开合节点。','具体明末剪式待审；不提供制作与刃口技术。');
}
function matchcord(){
 return g('translate(70 10) scale(.75)',coil().split('<text')[0])+rope('M581 349 Q660 421 779 340 Q834 290 835 256',10)+c(836,255,9,color.red,{'stroke-width':0})+callout(421,298,130,185,'备用纤维绳束／可抓自由端')+callout(837,255,720,463,'干湿状态以材质／UI标明')+sheetNotes('明确为剧情火绳外观，非现代导火索或引爆装置。','不绘原料、配方、制作方法或使用步骤。');
}
const draw = {
 'gun-light-muzzle':()=>cannon('light'), 'gun-folangji':()=>cannon('swivel'), 'gun-hongyipao':()=>cannon('heavy'),
 'gun-deck-carriage':carriage, 'gun-swivel-mount':mount, 'gun-folangji-chamber':chamber,
 'firearm-matchlock':()=>firearm(false), 'firearm-short-matchlock':()=>firearm(true),
 'weapon-sabre':()=>blade(false), 'weapon-spear':spear, 'weapon-longblade':()=>blade(true),
 'ammo-solid':()=>ammo('solid'), 'ammo-chain':()=>ammo('chain'), 'ammo-grape':()=>ammo('grape'), 'ammo-firearm-shot':()=>ammo('personal'),
 'prop-crate':crate, 'prop-barrel':()=>barrel(false), 'prop-cloth-bale':bale, 'prop-grain-sack':()=>sack(false),
 'prop-porcelain-jar':jar, 'prop-basket':basket, 'prop-rope-coil':coil, 'prop-cargo-net':net, 'prop-bollard':bollard,
 'prop-lantern':()=>lantern(false), 'prop-bench':()=>furniture('bench'), 'prop-table':()=>furniture('table'), 'prop-bedding':()=>furniture('bedding'),
 'prop-chest':()=>chest(false), 'prop-bucket':()=>barrel(true), 'prop-pot':pot, 'prop-bowl':bowl,
 'prop-letter':()=>document('letter'), 'prop-chart':()=>document('chart'), 'prop-tally':tally, 'prop-toolbox':()=>chest(true),
 'prop-drying-rack':rack, 'prop-wreck-timber':()=>timber(true), 'prop-toolbelt':toolbelt, 'prop-shipwright-axe':axe,
 'prop-polehook':polehook, 'prop-grapnel':grapnel, 'prop-boarding-plank':plank, 'prop-oar':()=>oar(false), 'prop-punt-pole':()=>oar(true),
 'prop-compass':compass, 'prop-medicine':medicine, 'prop-receipt':()=>document('receipt'), 'prop-contract-document':()=>document('contract'),
 'prop-official-document':()=>document('official'), 'prop-red-thread-pouch':()=>pouch(true), 'prop-money-pouch':()=>pouch(false),
 'prop-money-set':()=>money(true), 'prop-command-flag':flag, 'prop-gong':gong, 'prop-torch':torch, 'prop-paper-lantern':()=>lantern(true),
 'prop-timber-stock':()=>timber(false), 'prop-iron-stock':iron, 'prop-spices':()=>sack(true), 'prop-scissors':scissors, 'prop-matchcord':matchcord
};
if(items.length!==62) throw new Error('Expected reviewed 62-item inventory; re-audit before extending sketches.');
if(Object.keys(draw).length!==items.length) throw new Error('Drawing inventory mismatch.');
const notes = '可编辑外观说明草图；形制待证，不是写实概念图、史实复原或正式3D验收；仅整体轮廓、材质分区、挂点与节点关系。火炮火器无内部机构、尺寸、装药、制造或操作步骤。';
const manifest=[];
for(const item of items){
 if(!draw[item.id]) throw new Error('Missing item-specific drawing: '+item.id);
 const folder=directory[item.category];
 if(!folder) throw new Error('Unknown category: '+item.category);
 const relative=`assets/production/${folder}/${item.id}/sketch/structure-v1.svg`;
 const absolute=path.join(root,relative);
 const specific=draw[item.id]();
 if(typeof specific!=='string'||!/<(path|rect|circle|ellipse)[ >]/.test(specific)) throw new Error('Empty item-specific geometry: '+item.id);
 const svg=`<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="800" viewBox="0 0 1200 800" role="img" aria-labelledby="title desc">
<title id="title">${esc(item.name)}：可编辑外观说明草图</title>
<desc id="desc">${esc(item.visualBrief)} ${esc(notes)}</desc>
<metadata>${esc(JSON.stringify({id:item.id,role:'technical-sketch',generator:'tools/build-equipment-resource-sketches.mjs',version:1,historicalStatus:'unverified-concept',storyRefs:item.storyRefs}))}</metadata>
<rect width="1200" height="800" fill="${color.paper}"/>
<path d="M60 130 H1140 M60 647 H1140" stroke="${color.ink}" stroke-width="2"/>
${t(60,58,item.name,31)}
${t(60,94,item.id+'  /  '+item.category+'  /  '+item.phase,17,color.muted)}
${badge(943,44,'待证概念',color.white)}
<g id="item-specific-outline" transform="translate(30 7)">${specific}</g>
<g id="material-legend">
${r(61,681,18,18,color.wood,{'stroke-width':1})}${t(90,697,'木／竹',16)}
${r(199,681,18,18,color.metal,{'stroke-width':1})}${t(228,697,'金属',16)}
${r(327,681,18,18,color.cloth,{'stroke-width':1})}${t(356,697,'布／绳／纸',16)}
${t(61,736,'外观草图；可编辑路径与中文标注。比例为美术示意，材料与形制须复核。',17,color.muted)}
${t(61,768,'同一物件跨UI与场景共享；状态、材质、实例数量不自动增加基模。',17,color.muted)}
</g>
</svg>
`;
 fs.mkdirSync(path.dirname(absolute),{recursive:true});
 fs.writeFileSync(absolute,svg,'utf8');
 manifest.push({id:item.id,path:relative,role:'technical-sketch',note:notes});
}
fs.mkdirSync(path.dirname(destination),{recursive:true});
fs.writeFileSync(destination,JSON.stringify(manifest,null,2)+'\n','utf8');
console.log(JSON.stringify({items:manifest.length,svgFiles:manifest.length,manifest:path.relative(root,destination).split(path.sep).join('/'),missingDrawings:items.filter(x=>!draw[x.id]).map(x=>x.id)}));

