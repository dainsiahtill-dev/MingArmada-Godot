import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import {fileURLToPath} from 'node:url';
import {loadGameUiStory} from './game-ui-story-baseline.mjs';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const folder=path.join(root,'docs/design/game-ui/prototype');
const output=path.join(folder,'detail-contract-verification.json');
const businessOnly=process.argv.includes('--business-only');
const unknown=process.argv.slice(2).filter(arg=>arg!=='--business-only');
if(unknown.length)throw new Error('Unknown argument: '+unknown.join(','));
const files=['data.js','ui-core.js','render-world.js','render-ships.js','render-life.js','app.js'];
const sources=Object.fromEntries(files.map(name=>[name,fs.readFileSync(path.join(folder,name),'utf8')]));
const sha=text=>crypto.createHash('sha256').update(text).digest('hex');
const plain=value=>JSON.parse(JSON.stringify(value));
const tests=[],defaultChecks=[],stateChecks=[];
let assertions=0;
function expect(value,message){assertions++;assert.ok(value,message);}
function equal(actual,expected,message){assertions++;assert.deepStrictEqual(plain(actual),plain(expected),message);}
function test(id,fn){const start=assertions;try{const evidence=fn();tests.push({id,status:'passed',assertions:assertions-start,...(evidence?{evidence}:{})});}catch(error){tests.push({id,status:'failed',assertions:assertions-start,error:error.message,stack:error.stack});}}

function harness(initialFixture={}){
 const events={},windowEvents={},elements=new Map(),forms=new Map(),errors=[];let pageNodes=[];
 const decode=value=>String(value).replace(/&(?:amp|lt|gt|quot|#39);/g,x=>({'&amp;':'&','&lt;':'<','&gt;':'>','&quot;':'"','&#39;':"'"}[x]));
 function matchesSelector(node,selector){
  if(selector.includes(','))return selector.split(',').some(s=>matchesSelector(node,s.trim()));
  if(selector.startsWith('#'))return node.id===selector.slice(1);
  if(/^[a-z]+$/i.test(selector))return node.tagName===selector.toUpperCase();
  const m=selector.match(/^([a-z]+)?\[([\w-]+)(?:=["']?([^"'\]]+)["']?)?\]$/i);
  if(!m)return false;
  const attrs={...node.attributes,...Object.fromEntries(Object.entries(node.dataset||{}).map(([key,value])=>['data-'+key.replace(/[A-Z]/g,c=>'-'+c.toLowerCase()),value]))};
  return (!m[1]||node.tagName===m[1].toUpperCase())&&Object.hasOwn(attrs,m[2])&&(m[3]===undefined||attrs[m[2]]===m[3]);
 }
 function hydrate(html){
  forms.clear();pageNodes=[];
  for(const {tag,attrs}of tags(html)){
   if(!attrs.id&&!['button','input','select','textarea','output'].includes(tag))continue;
   const node=new Element(attrs.id||'');node.tagName=tag.toUpperCase();node.attributes=attrs;node.dataset=Object.fromEntries(Object.entries(attrs).filter(([key])=>key.startsWith('data-')).map(([key,value])=>[key.slice(5).replace(/-([a-z])/g,(_,c)=>c.toUpperCase()),decode(value)]));
   node.value=decode(attrs.value??'');node.type=attrs.type||'';node.max=attrs.max||'';node.disabled=Object.hasOwn(attrs,'disabled');node.checked=Object.hasOwn(attrs,'checked');
   if(tag==='textarea'&&attrs.id){const body=html.match(new RegExp('<textarea\\b[^>]*id=["\']'+attrs.id+'["\'][^>]*>([\\s\\S]*?)</textarea>','i'));node.value=decode(body?.[1]||'');}
   if(tag==='select'&&attrs.id){const body=html.match(new RegExp('<select\\b[^>]*id=["\']'+attrs.id+'["\'][^>]*>([\\s\\S]*?)</select>','i'));const options=[...(body?.[1]||'').matchAll(/<option\b([^>]*)>([\s\S]*?)<\/option>/gi)],option=options.find(x=>/\bselected\b/.test(x[1]))||options[0];if(option)node.value=decode(option[1].match(/\bvalue=["']([^"']*)["']/)?.[1]??option[2].replace(/<[^>]*>/g,''));}
   if(attrs.id)forms.set(attrs.id,node);pageNodes.push(node);
  }
 }
 class Element{
  constructor(id=''){this.id=id;this._innerHTML='';this.textContent='';this.value='';this.dataset={};this.attributes={};this.hidden=false;this.open=false;this.disabled=false;this.tagName='DIV';this.classNames=new Set();this.classList={add:(...x)=>x.forEach(v=>this.classNames.add(v)),remove:(...x)=>x.forEach(v=>this.classNames.delete(v)),contains:x=>this.classNames.has(x),toggle:(x,on)=>{if(on===undefined)on=!this.classNames.has(x);on?this.classNames.add(x):this.classNames.delete(x);return on;}};}
  get innerHTML(){return this._innerHTML;}
  set innerHTML(value){this._innerHTML=String(value);if(this.id==='main-content')hydrate(this._innerHTML);}
  addEventListener(type,fn){(events[this.id+':'+type]??=[]).push(fn);}
  setAttribute(key,value){this.attributes[key]=String(value);this[key]=key==='disabled'?true:value;}
  removeAttribute(key){delete this.attributes[key];if(key==='disabled')this.disabled=false;}
  getAttribute(key){return this.attributes[key]??null;}
  querySelector(selector){if(selector==='.immersive')return this.innerHTML.includes(' immersive')?new Element():null;return pageNodes.find(n=>matchesSelector(n,selector))||new Element();}
  querySelectorAll(selector){return pageNodes.filter(n=>matchesSelector(n,selector));}
  prepend(){}
  focus(){}
  showModal(){this.open=true;}
  close(){this.open=false;}
  closest(selector){return matchesSelector(this,selector)?this:null;}
  matches(selector){return matchesSelector(this,selector);}
 }
 for(const id of ['main-content','directory-dialog','page-count','screen-directory','directory-close','page-search','directory-results','toast'])elements.set(id,new Element(id));
 const document={
  body:new Element('body'),title:'',
  getElementById:id=>forms.get(id)||elements.get(id)||null,
  createElement:()=>new Element(),
  querySelector:selector=>pageNodes.find(n=>matchesSelector(n,selector))||null,
  querySelectorAll:selector=>pageNodes.filter(n=>matchesSelector(n,selector)),
  addEventListener:(type,fn)=>(events[type]??=[]).push(fn)
 };
 const location={search:''};let currentHash='#main-menu';
 Object.defineProperty(location,'hash',{get:()=>currentHash,set:value=>{const next=value.startsWith('#')?value:'#'+value;if(next!==currentHash){currentHash=next;for(const fn of windowEvents.hashchange||[])fn({type:'hashchange'});}}});
 let fixtureApplied=false;
 const clone=value=>{const copy=structuredClone(value);if(!fixtureApplied&&copy&&Object.hasOwn(copy,'silver')&&Object.hasOwn(copy,'marketStock')&&Object.hasOwn(copy,'saves')){Object.assign(copy,structuredClone(initialFixture));fixtureApplied=true;}return copy;};
 const sandbox={document,location,URLSearchParams,structuredClone:clone,console:{info(){},log(){},warn(){},error(...x){errors.push(x.map(String).join(' '));}},setTimeout:()=>1,clearTimeout(){},scrollTo(){},addEventListener:(type,fn)=>(windowEvents[type]??=[]).push(fn)};
 sandbox.window=sandbox;
 const context=vm.createContext(sandbox);
 for(const file of files)vm.runInContext(sources[file],context,{filename:file,timeout:5000});
 const api=sandbox.GameUI;
 expect(typeof api.getState==='function','Real app must expose getState()');
 const dispatch=(type,target)=>{for(const fn of events[type]||[])fn({type,target,preventDefault(){}});};
 return{
  api,context,errors,
  state:()=>plain(api.getState()),
  html:()=>elements.get('main-content').innerHTML,
  navigate:id=>api.navigate(id),
  form:(id,value,max='')=>{const input=new Element(id);input.value=String(value);input.max=String(max);input.tagName='INPUT';forms.set(id,input);return input;},
  input:(id,value)=>{const input=forms.get(id);assert.ok(input,'Actual rendered input must exist: '+id);input.value=String(value);dispatch('input',input);return input;},
  change:(id,value)=>{const input=forms.get(id);assert.ok(input,'Actual rendered control must exist: '+id);input.value=String(value);dispatch('change',input);return input;},
  node:selector=>selector.startsWith('#')?forms.get(selector.slice(1)):document.querySelector(selector),
  clickRendered:(action,match=()=>true)=>{const button=pageNodes.find(n=>n.dataset.action===action&&match(n.dataset));assert.ok(button,'Rendered action must exist: '+action);assert.ok(!button.disabled,'Rendered action must be enabled: '+action);dispatch('click',button);},
  action:(action,attrs={})=>{const button=new Element();button.tagName='BUTTON';button.dataset=Object.fromEntries(Object.entries({action,...attrs}).map(([k,v])=>[k,String(v)]));dispatch('click',button);},
  setting:(key,value)=>{const input=new Element();input.tagName='INPUT';input.type=typeof value==='boolean'?'checkbox':'range';input.checked=value;input.value=String(value);input.dataset={setting:key};dispatch('change',input);},
  scenario:label=>{const input=new Element('preview-state');input.value=label;dispatch('change',input);},
  render:(screen,state)=>{sandbox.__detailScreen=screen;sandbox.__detailState=structuredClone(state);const html=vm.runInContext('GameUI.renderers.get(__detailScreen.id)(__detailScreen,__detailState,GameUI.ui)',context,{timeout:5000});return{html,after:plain(sandbox.__detailState)};}
 };
}
const economics=s=>({silver:s.silver,stock:s.stock,marketStock:s.marketStock,transactions:s.transactions,crew:s.crew,recruitRecords:s.recruitRecords});

test('weighted-cargo-overflow-is-atomic',()=>{
 const h=harness(),before=h.state();h.form('trade-quantity',79,999);
 h.action('buy',{item:'iron',price:1,market:'hidden'});
 const after=h.state();equal(economics(after),economics(before),'Iron weight 2 must reject 194+158>350 without economic writes');
 expect(/货舱不足/.test(after.notice),'Cargo refusal must explain cargo capacity');
 return{initialWeightedCargo:h.api.ui.cargoUsed(before),requestedUnits:79,unitWeight:2,capacity:before.cargoCapacity};
});
test('light-cargo-same-quantity-fits',()=>{
 const h=harness();h.form('trade-quantity',79,999);h.action('buy',{item:'grain',price:1,market:'hidden'});
 equal(h.state().stock.grain,159,'Weight 1 cargo must fit where same-unit weight 2 cargo fails');
 equal(h.state().silver,2381,'Accepted light cargo pays exactly once');
});
test('port-market-buy-sell-updates-local-stock',()=>{
 const h=harness();h.form('trade-quantity',3,999);h.action('buy',{item:'silk',price:42,market:'port'});
 equal([h.state().stock.silk,h.state().marketStock.silk,h.state().silver],[15,29,2334],'Buy must update cargo, port stock and money');
 h.form('trade-quantity',2,999);h.action('sell',{item:'silk',price:36,market:'port'});
 equal([h.state().stock.silk,h.state().marketStock.silk,h.state().silver],[13,31,2406],'Sell must replenish port stock and pay actual quantity');
});
test('hidden-market-does-not-pollute-port-stock',()=>{
 const h=harness(),market=h.state().marketStock;h.form('trade-quantity',2,999);h.action('buy',{item:'porcelain',price:20,market:'hidden'});
 equal(h.state().marketStock,market,'Hidden purchase must not subtract port inventory');
 h.form('trade-quantity',1,999);h.action('sell',{item:'porcelain',price:16,market:'hidden'});
 equal(h.state().marketStock,market,'Hidden sale must not replenish port inventory');
 equal([h.state().stock.porcelain,h.state().silver],[9,2436],'Hidden transaction must still change personal cargo and silver');
});
test('recruit-records-are-visible-in-roster',()=>{
 const h=harness();h.action('recruit',{item:'gunner',price:60});const s=h.state();
 equal([s.crew,s.silver,s.recruitRecords.length],[39,2400,1],'Recruit must change headcount, payment and record together');
 equal([s.recruitRecords[0].item,s.recruitRecords[0].price],['gunner',60],'Record must preserve recruited role and cost');
 h.navigate('crew-roster');expect(h.html().includes('本次雇用记录')&&h.html().includes('60'),'Roster must render the actual recruit record');
});
test('full-crew-refuses-without-charge',()=>{
 const h=harness();h.action('set',{key:'crew',value:60});const before=h.state();h.action('recruit',{item:'carpenter',price:80});
 equal(economics(h.state()),economics(before),'Full crew must not charge or append recruitment');
 expect(/已满/.test(h.state().notice),'Full crew refusal is explained');
});
test('one-person-has-one-post',()=>{
 const h=harness();h.action('assign',{item:'awang',post:'领航'});h.action('assign',{item:'awang',post:'损管'});
 equal(h.state().assignment,{'损管':'awang'},'Moving one person removes their previous post');
 h.action('assign',{item:'chen',post:'领航'});h.action('assign',{item:'awang',post:'领航'});
 equal(h.state().assignment,{'领航':'awang'},'Replacing a post must not retain displaced occupant or duplicate the new person');
});
test('crew-pay-is-idempotent-per-period',()=>{
 const h=harness();h.action('choose',{item:'crew-pay',price:90});const once=h.state();
 equal([once.silver,once.morale,once.wagesPaid],[2370,90,true],'First wages pay and morale are applied');
 h.action('choose',{item:'crew-pay',price:90});equal(economics(h.state()),economics(once),'Second wages action cannot charge twice');
 equal(h.state().morale,once.morale,'Second wages action cannot repeatedly boost morale');
});
test('contract-delivery-needs-acceptance-and-never-auto-pays',()=>{
 const h=harness(),before=h.state();h.action('deliver-contract',{item:'escort'});
 equal(h.state().contractDeliveries,{},'Unaccepted contract cannot be submitted');equal(economics(h.state()),economics(before),'Unaccepted contract cannot pay');
 h.action('accept-contract',{item:'escort'});h.action('deliver-contract',{item:'escort'});
 equal(h.state().contractDeliveries.escort,'pending','Accepted delivery records pending verification');
 const once=h.state();h.action('deliver-contract',{item:'escort'});
 equal(h.state().contractDeliveries,once.contractDeliveries,'Duplicate submission preserves one pending receipt');
 equal(economics(h.state()),economics(before),'Submission and duplicate submission do not fabricate reward');
});
test('empty-save-slot-refuses-load',()=>{
 const h=harness(),before=h.state();h.action('load',{slot:2});
 equal(economics(h.state()),economics(before),'Empty slot cannot replace game state');
 expect(/还没有保存|未保存|空/.test(h.state().notice),'Empty slot does not report load success');
});
test('save-overwrite-needs-second-confirmation',()=>{
 const h=harness();h.navigate('save-game');h.input('save-name','第一次');h.clickRendered('save',d=>d.slot==='0');const original=h.state().saves[0];
 h.action('set',{key:'hull',value:23});h.input('save-name','覆盖后');h.clickRendered('save',d=>d.slot==='0');
 equal(h.state().saves[0],original,'First overwrite click preserves the existing snapshot');equal(h.state().confirmSaveSlot,0,'First click records the slot needing confirmation');
 equal(h.node('#save-name').value,'覆盖后','Overwrite confirmation preserves the name the player actually typed');
 h.clickRendered('save',d=>d.slot==='0');equal(h.state().saves[0].name,'覆盖后','Second click performs requested overwrite');equal(h.state().saves[0].snapshot.hull,'23','Confirmed overwrite captures new state');
});
test('save-load-restores-full-domain-state',()=>{
 const h=harness();
 h.form('trade-quantity',2,999);h.action('buy',{item:'silk',price:42,market:'port'});
 h.action('recruit',{item:'gunner',price:60});h.action('assign',{item:'awang',post:'损管'});
 h.action('accept-contract',{item:'escort'});h.action('deliver-contract',{item:'escort'});
 h.setting('music',14);h.setting('colorAssist',true);
 h.action('set',{key:'customVoyageNote',value:'本航保存验证'});h.action('set',{key:'letterDraft',value:'这一程尚未定归期'});
 h.form('save-name','完整状态');h.action('save',{slot:0});
 const saved=h.state().saves[0].snapshot;
 h.action('repair');h.action('recruit',{item:'waterman',price:45});h.action('set',{key:'customVoyageNote',value:'后来变更'});h.setting('music',80);
 h.action('load',{slot:0});const restored=h.state();
 const transient=new Set(['saves','feedback','notice','notifications','notificationCounter','previewScenario']);
 const project=s=>Object.fromEntries(Object.entries(s).filter(([key])=>!transient.has(key)));
 equal(project(restored),project(saved),'Every persisted domain field, including nested collections and extension fields, is restored');
 equal(restored.notifications.slice(1),saved.notifications,'Previously saved notification history is restored beneath the new load notice');
 equal(restored.saves[0].name,'完整状态','Save slot remains available after restoring its snapshot');
 return{comparedFields:Object.keys(project(saved)),excludedTransientFields:[...transient]};
});
test('notifications-retain-history-and-mark-read',()=>{
 const h=harness();h.navigate('market');h.action('notice',{message:'第一笔可查通知'});h.action('notice',{message:'第二笔可查通知'});
 const state=h.state();equal(state.notifications.length,2,'Actions append actual notification history');
 expect(new Set(state.notifications.map(x=>x.id)).size===2,'Notice IDs are distinct');
 expect(state.notifications.every(x=>x.read===false&&x.pageId==='market'),'New notices are unread and link to their originating page');
 const selected=state.notifications[1];h.action('mark-notification',{id:selected.id});
 equal(h.state().notifications.length,2,'Marking read retains history');expect(h.state().notifications.find(x=>x.id===selected.id).read===true,'Requested record becomes read');
 h.navigate('notification-log');expect(h.html().includes('第一笔可查通知')&&h.html().includes('第二笔可查通知'),'Notification page renders real retained messages');
});

const catalog=JSON.parse(fs.readFileSync(path.join(folder,'../systems.json'),'utf8'));
test('route-confirmation-is-bound-to-current-destination',()=>{
 const h=harness();h.action('set',{key:'destination',value:'平户'});h.action('route-confirm');
 equal([h.state().routeConfirmed,h.state().routeConfirmedDestination],['沿岸','平户'],'Confirmation records route and the actual selected port together');
 expect(h.state().routeConfirmedAt&&h.state().routeConfirmedAt.length>0,'Confirmation has an explicit voyage receipt');
 h.action('set',{key:'selectedGood',value:'wood'});equal(h.state().routeConfirmedDestination,'平户','Unrelated selection does not erase a valid route');
 for(const [action,key,value,target]of [['set','route','直航'],['set','destination','吕宋'],['open','route','沿岸','route-plan'],['open','destination','澳门','destination-detail']]){
  h.action('set',{key:'route',value:'沿岸'});h.action('set',{key:'destination',value:'平户'});h.action('route-confirm');
  h.action(action,{key,value,...(target?{target}:{})});
  expect(!h.state().routeConfirmed&&!h.state().routeConfirmedDestination,action+' '+key+' invalidates both the old route and old destination receipt');
 }
 return{invalidatedBy:['set route','set destination','open route','open destination']};
});

test('route-confirmation-refuses-insufficient-supplies-and-can-recover',()=>{
 const h=harness();h.action('set',{key:'route',value:'直航'});h.action('set',{key:'destination',value:'吕宋'});const before=economics(h.state());h.action('route-confirm');
 expect(!h.state().routeConfirmed,'Direct voyage cannot confirm with the default 80 grain');equal(economics(h.state()),before,'Refused route does not consume resources');
 h.form('trade-quantity',30,999);h.action('buy',{item:'grain',price:1,market:'hidden'});h.action('route-confirm');
 equal([h.state().stock.grain,h.state().routeConfirmed,h.state().routeConfirmedDestination],[110,'直航','吕宋'],'Exactly 110 grain allows the selected direct route and destination');
});

test('jettison-owned-goods-updates-weighted-cargo-without-income',()=>{
 const h=harness({cargoOwnership:{porcelain:'owned'}}),before=h.state(),weight=h.api.ui.cargoUsed(before);
 h.action('choose',{item:'jettison-porcelain',quantity:3});const after=h.state();
 equal(after.stock.porcelain,5,'Owned porcelain is jettisonable; item category cannot substitute for ownership');
 equal(h.api.ui.cargoUsed(after),weight-6,'Three weight-2 units free exactly six cargo units');
 equal([after.silver,after.transactions],[before.silver,before.transactions],'Jettisoning creates no sale proceeds or fabricated ledger entry');
 equal(after.jettisonReceipt,{item:'porcelain',quantity:3},'Receipt records the actual cargo and quantity');
});

test('jettison-disputed-marker-applies-to-any-good',()=>{
 const h=harness({cargoOwnership:{grain:'disputed',porcelain:'owned'}}),before=h.state();
 h.action('choose',{item:'jettison-grain',quantity:1});
 equal(economics(h.state()),economics(before),'Disputed grain cannot be discarded even though it is ordinary grain');
 expect(!h.state().jettisonReceipt,'Disputed refusal produces no success receipt');expect(/归属|争议|核实/.test(h.state().notice),'Ownership refusal explains the unresolved ownership');
});

test('jettison-invalid-quantity-and-unknown-good-are-atomic',()=>{
 const h=harness(),before=h.state();
 for(const [item,quantity]of [['grain',0],['grain',-1],['grain',1.5],['grain',81],['grain','NaN'],['unknown',1]]){
  h.action('choose',{item:'jettison-'+item,quantity});equal(economics(h.state()),economics(before),'Invalid discard preserves resources: '+item+'/'+quantity);expect(!h.state().jettisonReceipt,'Invalid discard does not leave a success receipt');
 }
 return{cases:6};
});

test('cargo-page-jettison-controls-follow-actual-ownership',()=>{
 for(const cargoOwnership of [{},{porcelain:'owned'}]){
  const h=harness({cargoOwnership});h.navigate('cargo-hold');h.clickRendered('set',d=>d.key==='selectedGood'&&d.value==='porcelain');h.scenario('抛货确认');
  const button=h.node('[data-item="jettison-porcelain"]');expect(button&&!button.disabled,'Unmarked or explicitly owned porcelain has an enabled actual cargo-page discard control');
  const quantity=Number(button.dataset.quantity),before=h.state().stock.porcelain;h.clickRendered('choose',d=>d.item==='jettison-porcelain');
  equal([h.state().stock.porcelain,h.state().jettisonReceipt.quantity],[before-quantity,quantity],'Clicking the rendered cargo control discards its displayed quantity');
 }
 for(const good of ['wood','porcelain']){
  const h=harness({cargoOwnership:{[good]:'disputed'}});h.navigate('cargo-hold');h.clickRendered('set',d=>d.key==='selectedGood'&&d.value===good);h.scenario('抛货确认');
  expect(h.node('[data-item="jettison-'+good+'"]').disabled===true,'A disputed '+good+' has its actual discard control disabled');
  expect(/争议货须封存辨认原主，不可抛弃/.test(h.html()),'Disabled disputed cargo gives an explicit ownership recovery reason');
 }
 return{ownedCases:2,disputedCases:2};
});

for(const {model,name,price}of [{model:'fisherman',name:'小渔船',price:420},{model:'merchant',name:'海贸福船',price:1280},{model:'barque',name:'西式商船',price:2300}]){
 test('shipyard-'+model+'-quote-order-ledger-and-save-agree',()=>{
  const h=harness();h.navigate('shipyard');h.clickRendered('set',d=>d.key==='shipyardChoice'&&d.value===model);
  const quote=tags(h.html()).find(x=>x.attrs['data-action']==='buy'&&x.attrs['data-item']==='merchant-ship')?.attrs;
  equal([quote?.['data-model'],quote?.['data-name'],Number(quote?.['data-price'])],[model,name,price],'Real selected ship quote matches model, name and expected price');
  const before=h.state();h.clickRendered('buy',d=>d.item==='merchant-ship');const after=h.state();
  equal([after.shipOrdered,after.orderedShipType,after.orderedShipName,after.silver],[true,model,name,before.silver-price],'Actual handler orders the displayed model and charges its quote exactly once');
  equal([after.transactions[0].delta,after.transactions[0].balance,after.transactions[0].category],[-price,after.silver,'舰船'],'Ledger amount, category and resulting balance agree');expect(after.transactions[0].title.includes(name),'Ledger identifies the ship that was actually selected');
  h.form('save-name',name+'订造记录');h.action('save',{slot:0});const snapshot=h.state().saves[0].snapshot;
  equal([snapshot.orderedShipType,snapshot.orderedShipName,snapshot.silver],[model,name,after.silver],'Save stores the selected order and exact remaining funds');
  h.action('set',{key:'orderedShipName',value:'后来错误的名字'});h.action('load',{slot:0});equal([h.state().orderedShipType,h.state().orderedShipName],[model,name],'Load restores the actual ship choice');
  h.navigate('accounts');expect(h.html().includes('船坞订造'+name)&&h.html().includes(price.toLocaleString()),'Account page renders the actual order and cost');
  return{model,name,price,remainingSilver:after.silver};
 });
}

test('letter-input-locally-refreshes-submit-reason-count-and-fees',()=>{
 const h=harness({letterDraft:'',remittanceDraft:0,letterCarrier:'trusted'});h.navigate('send-letter-remittance');
 const submit=()=>h.node('[data-action="send-letter"]'),reason=()=>{const n=h.node('#letter-submit-reason');return(n?.textContent||'')+(n?.innerHTML||'');};
 expect(submit()?.disabled===true,'An actual empty rendered draft starts with submit disabled');const initialSubmit=submit();
 const body='平户的灯，留着等回船。';h.input('letter-body',body);
 expect(submit().disabled===false,'Typing a valid body enables the same rendered submit button without navigation');expect(submit()===initialSubmit,'Input feedback updates the existing button instead of replacing the form or losing textarea focus');
 expect(h.node('#letter-character-count').textContent.includes(String(body.length)),'Character count updates from actual textarea input');expect(!/还没有要托|先写正文|正文空白/.test(reason()),'Resolved empty-body reason is cleared immediately');
 h.input('remittance',2460);expect(submit().disabled===true,'Unaffordable remittance disables submit immediately');expect(/不足|还差|银两|筹/.test(reason()),'Unaffordable amount displays a visible reason');
 equal([h.node('#letter-total').textContent,h.node('#letter-balance').textContent],['2480','-20'],'Fee and balance update from the actual remittance input');
 h.input('remittance',0);expect(submit().disabled===false,'Reducing remittance restores ability to send');equal([Number(h.node('#letter-total').textContent.replace(/,/g,'')),Number(h.node('#letter-balance').textContent.replace(/,/g,''))],[20,2440],'Zero remittance still retains the 20-silver carrier fee');
 h.input('letter-body','   ');expect(submit().disabled===true,'Deleting back to whitespace disables submit again');expect(/正文|写|空/.test(reason()),'Empty draft explains how to recover');
 h.input('letter-body',body);const before=h.state();h.clickRendered('send-letter');
 equal([h.state().silver,h.state().sentLetters,h.state().lastLetter.body,h.state().lastLetter.amount],[before.silver-20,1,body,0],'Recovered form sends the actual text once with only the stated fee');
});

test('letter-invalid-remittance-rejects-and-keeps-draft',()=>{
 const h=harness({letterDraft:'尚未定归期，也照实写下。',letterCarrier:'trusted'});h.navigate('send-letter-remittance');
 for(const amount of [-1,1.5]){const before=economics(h.state());h.input('remittance',amount);expect(h.node('[data-action="send-letter"]').disabled===true,'Invalid remittance cannot leave submit enabled');h.action('send-letter');equal(economics(h.state()),before,'Actual handler rejects invalid remittance without payment');expect(!h.state().lastLetter,'Invalid remittance creates no sent-letter record');}
 h.input('remittance',0);h.action('set',{key:'letterCarrier',value:'next'});expect(h.node('[data-action="send-letter"]').disabled===true,'Unconfirmed carrier keeps draft editable but cannot send');
});

test('letter-same-draft-is-idempotent-and-each-signature-field-can-change',()=>{
 const cases=[{field:'body',edit:h=>h.input('letter-body','归期未定，下一条回船再捎信。')},{field:'amount',edit:h=>h.input('remittance',1)},{field:'recipient',edit:h=>h.change('letter-recipient','平户家中')}];
 for(const item of cases){
  const h=harness({letterDraft:'归期仍未定。',remittanceDraft:0,letterCarrier:'trusted'});h.navigate('send-letter-remittance');h.clickRendered('send-letter');const once=h.state();
  expect(h.node('[data-action="send-letter"]').disabled===true,'Same '+item.field+' draft is disabled immediately after sending');
  h.action('send-letter');equal([h.state().silver,h.state().sentLetters,h.state().sentLetterRecords,h.state().transactions],[once.silver,once.sentLetters,once.sentLetterRecords,once.transactions],'Bypassing the disabled UI cannot pay twice for the same complete draft');
  item.edit(h);expect(h.node('[data-action="send-letter"]').disabled===false,'Changing '+item.field+' alone immediately permits a distinct draft');
  h.clickRendered('send-letter');equal(h.state().sentLetters,2,'Distinct '+item.field+' draft creates one additional actual sent record');
 }
 return{signatureFields:cases.map(x=>x.field)};
});

const story=loadGameUiStory(root);
const assetFile=path.join(folder,'../production-assets.json');
let assetCounts=null;
test('catalog-systems-pages-flows-and-built-data-agree',()=>{
 const h=harness(),built=plain(h.context.GAME_UI_DATA),screens=catalog.screenGroups.flatMap(g=>g.screens),builtScreens=built.screenGroups.flatMap(g=>g.screens),pageIds=new Set(screens.map(s=>s.id)),sceneIds=new Set(story.acts.flatMap(a=>a.scenes.map(s=>s.id)));
 equal([catalog.systems.length,catalog.underlyingSystems.length,screens.length,catalog.flows.length],[30,11,72,13],'Declared gameplay, underlying, page and flow counts');
 equal([pageIds.size,new Set(catalog.systems.map(x=>x.id)).size,new Set(catalog.underlyingSystems.map(x=>x.id)).size],[72,30,11],'All contract identifiers are unique');
 equal([...h.api.renderers.keys()].sort(),[...pageIds].sort(),'Exactly the 72 contracted pages have registered renderers');
 equal(builtScreens.map(s=>({id:s.id,states:s.states})),screens.map(s=>({id:s.id,states:s.states})),'Built data contains the current exact state contract, without stale removed aliases');
 const refsValid=items=>items.every(x=>(x.storyRefs||[]).every(id=>sceneIds.has(id)));
 expect(refsValid(catalog.systems)&&refsValid(screens)&&refsValid(catalog.flows),'All gameplay, page and flow story references exist');
 expect(catalog.systems.every(x=>x.pages.every(id=>pageIds.has(id))),'Gameplay pages exist');expect(catalog.underlyingSystems.every(x=>x.mappedPages.every(id=>pageIds.has(id))),'Underlying page mappings exist');expect(catalog.flows.every(x=>x.screenIds.every(id=>pageIds.has(id))),'All flow steps exist');
 expect(screens.every(x=>catalog.systems.some(s=>s.id===x.systemId)),'Every page belongs to a declared gameplay system');
 return{defaultPages:screens.length,declaredStates:screens.reduce((n,s)=>n+s.states.length,0),canonicalScenes:sceneIds.size};
});
test('production-assets-counts-and-references',()=>{
 const d=JSON.parse(fs.readFileSync(assetFile,'utf8')),m=d.models;
 const ids=new Set(m.map(x=>x.id)),pages=new Set(catalog.screenGroups.flatMap(g=>g.screens.map(s=>s.id))),refs=new Set(story.acts.flatMap(a=>a.scenes.map(s=>s.id)));
 const count=key=>Object.fromEntries([...new Set(m.map(x=>x[key]))].map(value=>[value,m.filter(x=>x[key]===value).length]));
 const clipKeys=new Set(m.flatMap(x=>x.animations.map(a=>(x.rigFamily||x.id)+':'+a)));
 assetCounts={baseMeshes:m.reduce((n,x)=>n+x.baseMeshCount,0),byPhase:count('phase'),byCategory:count('category'),variants:m.reduce((n,x)=>n+x.variants.length,0),lods:m.reduce((n,x)=>n+x.lodLevels,0),rigs:d.rigs.length,animations:clipKeys.size};
 equal([m.length,ids.size,assetCounts.baseMeshes],[83,83,83],'83 real base records');
 equal(assetCounts.byPhase,{P0:47,P1:34,P2:2},'Phase totals');equal([assetCounts.lods,assetCounts.rigs,assetCounts.animations],[227,2,29],'LOD, rig and unique clip totals');
 equal(assetCounts.variants,117,'Variant configuration count');
 equal(d.basis.counts.byCategory,assetCounts.byCategory,'Category ledger matches actual entries');
 equal([d.basis.counts.baseMeshes,d.basis.counts.variantConfigurationLabels,d.basis.counts.lodDeliveryRepresentations,d.basis.counts.rigFamilies,d.basis.counts.uniqueBakedAnimationClips],[assetCounts.baseMeshes,assetCounts.variants,assetCounts.lods,assetCounts.rigs,assetCounts.animations],'Published asset ledger matches recomputed totals');
 equal(d.basis.counts.byPhase,assetCounts.byPhase,'Published phase ledger matches actual records');
 expect(m.every(x=>x.baseMeshCount===1&&[1,3].includes(x.lodLevels)),'Base and LOD units are valid');
 expect(m.every(x=>x.pages.every(p=>pages.has(p))&&x.storyRefs.every(s=>refs.has(s))),'All model page and story references exist');
 expect([...d.twoDimensional,...d.effects].every(x=>x.pages.every(p=>pages.has(p))),'2D/effect page references exist');
 expect(m.every(x=>x.existing.every(e=>fs.statSync(path.join(root,e.path)).isFile())),'Every existing asset path is a real file');
 expect(d.rigs.every(r=>JSON.stringify([...r.sharedBy].sort())===JSON.stringify(m.filter(x=>x.rigFamily===r.id).map(x=>x.id).sort())),'Rig ownership matches both directions');
 expect(m.every(x=>x.rigFamily===null||d.rigs.some(r=>r.id===x.rigFamily)),'Every declared rig family exists');
 expect(m.filter(x=>x.rigFamily).every(x=>x.animations.every(a=>d.rigs.find(r=>r.id===x.rigFamily).animations.includes(a))),'Model clips belong to their declared shared rig library');
 return assetCounts;
});

function tags(html){
 const out=[];
 for(const m of html.matchAll(/<([a-z][\w:-]*)\b((?:"[^"]*"|'[^']*'|[^'">])*)>/gi)){
  const attrs={};for(const a of m[2].matchAll(/([:\w-]+)(?:\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>\x60]+)))?/g))attrs[a[1].toLowerCase()]=a[2]??a[3]??a[4]??'';
  out.push({tag:m[1].toLowerCase(),attrs});
 }return out;
}
function substantive(html){
 let body=html.replace(/<!--[\s\S]*?-->/g,'').replace(/<(script|style)\b[^>]*>[\s\S]*?<\/\1>/gi,'')
 .replace(/<(section|aside|div)\b[^>]*class=["'][^"']*(?:state-banner|lp-scenario-surface|scenario-explainer)[^"']*["'][^>]*>[\s\S]*?<\/\1>/gi,'')
 .replace(/<header\b[^>]*class=["'][^"']*page-head[^"']*["'][^>]*>[\s\S]*?<\/header>/gi,'');
 const text=body.replace(/<[^>]*>/g,' ').replace(/\s+/g,' ').trim();
 const controls=tags(body).filter(x=>['input','button','option','select','textarea','img','image','path','circle','line','rect','polygon','polyline'].includes(x.tag)).map(x=>[x.tag,Object.fromEntries(Object.entries(x.attrs).filter(([key])=>['disabled','checked','selected','value','type','min','max','maxlength','aria-disabled','aria-pressed','src','href','xlink:href','d','cx','cy','x','y','x1','x2','y1','y2','points','width','height','style','transform'].includes(key)))]);
 const backgrounds=[...body.matchAll(/url\(([^)]+)\)/g)].map(x=>x[1]);
 return sha(JSON.stringify({text,controls,backgrounds}));
}
const pageIds=new Set(catalog.screenGroups.flatMap(g=>g.screens.map(s=>s.id)));
function inspect(html){
 const issues=[],elements=tags(html),internal=new Set(elements.map(x=>x.attrs.id).filter(Boolean));
 if(/\b(?:undefined|NaN)\b|页面载入异常|UI_RENDER_ERROR/.test(html))issues.push('bad-text');
 function resource(url){
  url=url.replace(/&amp;/g,'&').replace(/^['"]|['"]$/g,'').trim();
  if(!url||url.startsWith('#')||/^(?:https?:|data:|\/\/|mailto:)/.test(url))return;
  const file=path.resolve(folder,decodeURIComponent(url.split(/[?#]/,1)[0]));
  if(!fs.existsSync(file))issues.push('missing-resource:'+url);
 }
 for(const {tag,attrs:a}of elements){
  if(a['data-go']&&!pageIds.has(a['data-go']))issues.push('bad-data-go:'+a['data-go']);
  if(a['data-target']&&!pageIds.has(a['data-target'])&&!['overview','systems','flows','states','assets'].includes(a['data-target']))issues.push('bad-open-target:'+a['data-target']);
  if(a.src)resource(a.src);
  if(a.href?.startsWith('#')&&!pageIds.has(a.href.slice(1))&&!internal.has(a.href.slice(1)))issues.push('bad-fragment:'+a.href);
  if(a.href&&!a.href.startsWith('#')&&tag==='a')resource(a.href);
 }
 for(const match of html.matchAll(/url\(\s*(?:"([^"]*)"|'([^']*)'|([^)]*?))\s*\)/g))resource(match[1]??match[2]??match[3]);
 return[...new Set(issues)];
}
if(!businessOnly){
 const h=harness(),base=h.state();
 for(const screen of h.api.pages){
  let normal;const defaultRow={screenId:screen.id};
  try{
   const input={...structuredClone(base),previewScenario:''},before=JSON.stringify(input),rendered=h.render(screen,input);normal=rendered.html;
   const issues=typeof normal==='string'&&normal.trim()?inspect(normal):['empty-html'];if(JSON.stringify(rendered.after)!==before)issues.push('default-mutated-input-state');
   defaultRow.issues=issues;defaultRow.status=issues.length?'failed':'passed';defaultRow.htmlBytes=Buffer.byteLength(normal||'');defaultRow.bodyHash=substantive(normal||'');
  }catch(error){defaultRow.status='failed';defaultRow.issues=['default-render:'+error.message];}
  defaultChecks.push(defaultRow);if(normal===undefined)continue;
  for(const label of screen.states){
   const row={screenId:screen.id,state:label};
   try{
    const input={...structuredClone(base),previewScenario:label},before=JSON.stringify(input),rendered=h.render(screen,input);
    if(typeof rendered.html!=='string'||!rendered.html.trim())throw new Error('empty-html');
    const issues=inspect(rendered.html);
    if(JSON.stringify(rendered.after)!==before)issues.push('preview-mutated-input-state');
    row.defaultHash=substantive(normal);row.stateHash=substantive(rendered.html);
    if(row.defaultHash===row.stateHash)issues.push(normal===rendered.html?'unchanged-default':'only-generic-note-or-heading-differs');
    row.issues=issues;row.status=issues.length?'failed':'passed';row.htmlBytes=Buffer.byteLength(rendered.html);
   }catch(error){row.status='failed';row.issues=[error.message];}
   stateChecks.push(row);
  }
 }
}
const failedTests=tests.filter(t=>t.status==='failed'),failedDefaults=defaultChecks.filter(t=>t.status==='failed'),failedStates=stateChecks.filter(t=>t.status==='failed');
const status=failedTests.length||failedDefaults.length||failedStates.length?'failed':businessOnly?'pending':'passed';
const report={schemaVersion:2,generatedAt:new Date().toISOString(),status,businessOnly,
 method:'Execute unchanged classic app.js in Node VM; hydrate input/button nodes from its actual rendered HTML, dispatch the real document click/change/input listeners and observe GameUI.getState(). Optional domain fixtures overlay only the initial defaults clone. Minimal DOM harness does not emulate layout.',
 sourceHashes:{...Object.fromEntries(files.map(file=>[file,sha(sources[file])])),...Object.fromEntries(['systems.json','production-assets.json'].map(file=>[file,sha(fs.readFileSync(path.join(folder,'..',file)))]))},
 counts:{businessTests:tests.length,businessPassed:tests.length-failedTests.length,businessFailed:failedTests.length,assertions,defaultPages:defaultChecks.length,defaultPassed:defaultChecks.length-failedDefaults.length,defaultFailed:failedDefaults.length,screenStates:stateChecks.length,statePassed:stateChecks.length-failedStates.length,stateFailed:failedStates.length},
 tests,assetCounts,defaultChecks,stateChecks,pending:businessOnly?['All 72 default pages and declared states await frozen catalog and renderer checks; run again without --business-only.']:[],
 limitations:['No browser layout, accessibility tree, GPU, native gameplay or persistence execution.','The minimal DOM handles rendered form controls and synchronous event feedback; it is not a general browser DOM.','Timers are queued as no-op handles; none of the requested business acceptance cases depends on elapsed time.','State comparison excludes generic scenario surfaces, the outer state banner and page heading; meaningful text/control/image changes are required.']};
fs.writeFileSync(output,JSON.stringify(report,null,2)+'\n');
console.log('GAME_UI_DETAIL '+status.toUpperCase()+' business='+report.counts.businessPassed+'/'+tests.length+' assertions='+assertions+' defaults='+report.counts.defaultPassed+'/'+defaultChecks.length+' states='+report.counts.statePassed+'/'+stateChecks.length);
for(const test of failedTests)console.error('FAIL '+test.id+': '+test.error);
if(failedDefaults.length)console.error('DEFAULT FAILURES '+JSON.stringify(failedDefaults));
if(failedStates.length)console.error('STATE FAILURES '+JSON.stringify(failedStates.map(x=>({id:x.screenId,state:x.state,issues:x.issues}))));
console.log('Report: '+path.relative(root,output).split(path.sep).join('/'));
process.exitCode=failedTests.length||failedDefaults.length||failedStates.length?1:0;

