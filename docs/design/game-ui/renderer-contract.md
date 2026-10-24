# UI 原型实现合同

目录 `docs/design/game-ui/prototype/`。所有脚本经典defer加载，可从本地HTTP运行；不写Godot。全局 `window.GameUI.registerRenderer(ids, (screen,state,ui)=>htmlString)`；页面ID来自上级systems.json。每页有专用内容和适当布局，不允许通用列表换标题。状态只在内存中。

## Root拥有

index.html、styles.css、ui-core.js、app.js、data.js（构建生成）、render-world.js、原型验证工具。游戏场景已有页头与底部导航；renderer只返回页面内部主体，不再写全局壳。

## 公共帮助函数

- `ui.asset('goods/grain-v1.png')` 返回原项目art路径；`ui.sceneURL('zheng_a5_s4')` 返回已采用剧情图片路径。
- `ui.shipImage` 为新福船透明PNG的URL；`ui.e(text)` HTML转义；`ui.icon(name)`返回小SVG图标（ship,map,bag,book,people,trade,letter,flag,settings,arrow,compass,cannon,anchor,coin,check,close）。
- `ui.go(id,label,cls='button')` 返回跳转按钮；`ui.action(action,label,cls='button',attrs={})` 返回动作按钮，attrs自动写成data-属性。
- `ui.pageHead(kicker,title,description,actions='')`；`ui.metric(label,value,unit='',note='')`；`ui.pill(text,tone='')`；`ui.tabs([{id,label}],activeId)`。
- 其余直接semanticHTML：section/h2/table/label/input，统一class：columns-2,columns-3,wide-split,section-title,panel,paper,muted,gold,small,button,primary,danger,stat-row,list-row,toolbar,divider,progress,empty-state,portrait,goods-icon,ship-portrait,form-grid,field,inline-note,tag-list。可加语义自定义class，CSS交由root合并。

## 动作合同

`data-action`支持 set(key,value)、toggle(key)、buy(item,price)、sell(item,price)、repair、refit(item,price)、recruit(item,price)、assign(item,post)、ammo(item)、fire(side)、send-letter、accept-contract(item)、accept-quest(item)、save(slot)、load(slot)、choose(item)、notice(message)、reset。

ui.action attrs示例 `{item:'silk',price:42}`。set写state[key]=value；需要数字时renderer用Number。表单元素ID：trade-quantity、remittance、letter-body、letter-recipient、save-name。主要交易、修船、招募、寄信等改变资源并在重绘后可见；低影响提示使用notice。data-go直接跳转。临时UI选择一律set或toggle，不创建额外事件处理器。

## 状态字段

默认state：silver:2460,hull:72,sails:88,crew:38,maxCrew:60,morale:78,ammo:'solid',stock:{grain:80,wood:24,iron:16,silk:12,porcelain:8,spices:6},selectedGood:'silk',selectedCrew:'awang',selectedItem:'compass',equipped:'短刀',refit:'基础索具',post:'领航',contractAccepted:false,questAccepted:false,letterSent:false,sentLetters:0,share:35,paused:false,weather:'晴',speed:8.6,zoom:1,formation:'并列',leftShots:12,rightShots:12,reloading:false,saves:[],settings:{music:60,effects:75,text:100,reducedMotion:false,colorAssist:false},notice:''。可用set新增其他局部状态。

## 图像与内容

船图 `assets/fuchuan-inspection.png` 是本次生成的方案插图，不冒充活动Godot船模。人物art用zheng-captain、merchant-woman、voc-captain、pirate-captain；商品grain,wood,iron,silk,porcelain,spices；弹药solid-shot,chain-shot,grape-shot。剧情使用真实场ID，不能给原创人物/战事补造史实。
