// Read frozen TypeScript in memory. Never builds/writes the source checkout.
// Run: rtk proxy node --experimental-vm-modules tools/migration/export-naval-reference.mjs
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
const sourceRoot = path.resolve(process.argv[2] ?? 'C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada');
const targetRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const head = execFileSync('rtk', ['git','-C',sourceRoot,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
if(head !== '9ad6a44daecd4ec36a8172d83ff27493feffe5dd') throw new Error('Wrong source HEAD');
execFileSync('rtk',['git','-C',sourceRoot,'diff','--exit-code','HEAD','--','packages/naval-core/src','packages/physics-core/src'],{encoding:'utf8'});
const ts = createRequire(path.join(sourceRoot,'package.json'))('typescript');
const context = vm.createContext({console,Math,Number,Array,Object,Map,Set,Error,RangeError,TypeError,Symbol,structuredClone});
const modules = new Map(), hashes = {};
function load(filename){
 filename=path.resolve(filename).replace(/\.js$/,'.ts');
 if(modules.has(filename))return modules.get(filename);
 const source=fs.readFileSync(filename,'utf8');
 hashes[path.relative(sourceRoot,filename).replaceAll('\\','/')]=createHash('sha256').update(source).digest('hex');
 const code=ts.transpileModule(source,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText;
 const mod=new vm.SourceTextModule(code,{context,identifier:filename});modules.set(filename,mod);return mod;
}
const entry=load(path.join(sourceRoot,'packages/naval-core/src/index.ts'));
await entry.link((s,r)=>load(s==='@ming-armada/physics-core'?path.join(sourceRoot,'packages/physics-core/src/index.ts'):path.resolve(path.dirname(r.identifier),s)));
await entry.evaluate();
const {NavalEncounter}=entry.namespace;
const cases=[];
const calm={wind:{direction:{x:1,y:0},speed:0},oceanWaves:[],seed:42,battleId:'oracle'};
const setup=(id,kind,team,x,z,extra={})=>({id,kind,team,position:{x,z},sailDeployment:0,...extra});
// Source localeCompare delegates to ICU and the exporting host locale. Capture
// deterministic primary/secondary/case weights for product/audited characters.
const hostCollator=new Intl.Collator();
const baseCollator=new Intl.Collator(undefined,{sensitivity:'base'});
const accentCollator=new Intl.Collator(undefined,{sensitivity:'accent'});
const alphabet=Array.from({length:0x250-0x20},(_,i)=>String.fromCodePoint(i+0x20)).concat(Array.from({length:0x100},(_,i)=>String.fromCodePoint(i+0x370)),Array.from('船港中海文福中文海盗逐浪号😀⚓'));
const characters=[...new Set(alphabet)];
characters.sort(baseCollator.compare);
const groups=[];
for(const char of characters){if(!groups.length||baseCollator.compare(groups.at(-1)[0],char)!==0)groups.push([]);groups.at(-1).push(char)}
const weights={};
for(const [primary,group] of groups.entries()){
 group.sort(accentCollator.compare);let secondary=0,previous;
 for(const char of group){
  if(previous!==undefined&&accentCollator.compare(previous,char)!==0)secondary++;
  const tertiary=char.toLowerCase()!==char?1:0;
  weights[char]={primary:[primary+1],secondary:[secondary],tertiary:[tertiary]};
  previous=char;
 }
}
const expansions={'æ':'ae','Æ':'AE','œ':'oe','Œ':'OE','ß':'ss','ẞ':'SS'};
for(const [char,expansion]of Object.entries(expansions))if(weights[char]&&baseCollator.compare(char,expansion)===0){
 const primary=Array.from(expansion).flatMap(c=>weights[c].primary),secondary=Array.from(expansion).flatMap(c=>weights[c].secondary),tertiary=Array.from(expansion).flatMap(c=>weights[c].tertiary);
 secondary[secondary.length-1]+=accentCollator.compare(char,expansion)>0?1000:-1000;
 weights[char]={primary,secondary,tertiary};
}
for(const char of characters){const nfd=char.normalize('NFD');if(nfd!==char)weights[nfd]=weights[char]}
for(const char of ['\u0001','\u0002','\u007f'])if(hostCollator.compare(char,'')===0)weights[char]={primary:[],secondary:[],tertiary:[]};
const collation={locale:hostCollator.resolvedOptions(),icuVersion:process.versions.icu,weights};
fs.writeFileSync(path.join(targetRoot,'modules/naval_simulation/id-collation.json'),JSON.stringify(collation)+'\n');
const localePairs=[];
const ids=['a','A','a-a','a_a','aZ','Ab','abc','ABC','aBc','áb','ab','é','e\u0301','e','å','ä','æ','ae','af','Æ','ss','ß','SS','船','港','中','中文','文','海-1','海_1','😀','⚓','α','Α','β','Е','ё','Ё'];
for(const a of ids)for(const b of ids)localePairs.push({a,b,expected:Math.sign(a.localeCompare(b))});
const terrainFor=kind=>(x,z)=>kind==='deep'?-100:kind==='wall'?(Math.abs(x-100)<20?10:-100):kind==='island'?(Math.hypot(x-100,z)<45?10:-100):kind==='dry'?10:NaN;
function run(name,config,actions){
 const actualConfig={...config};if(config._terrain)actualConfig.sampleTerrainHeight=terrainFor(config._terrain);
 const game=new NavalEncounter(actualConfig),records=[];
 for(const action of actions){
  let result=null;
  if(action.method==='step')for(let i=0;i<(action.count??1);i++)game.step(action.seconds??1/60);
  else result=game[action.method](...action.args);
  records.push({action,result:result===undefined?null:structuredClone(result),snapshot:game.snapshot(),events:game.drainEvents(),orders:game.orderStatus(),navigation:Object.fromEntries(game.snapshot().ships.map(s=>[s.id,game.navigationStatus(s.id)??null]))});
 }
 cases.push({name,config,records});
}
for(const ammo of ['solid','chain','grape'])for(const side of ['port','starboard']){
 run(`${ammo}-${side}`,{...calm,ships:[setup('player','fuchuan','player',0,0),setup('victim','voc','neutral',0,side==='port'?-70:70)]},[
 {method:'command',args:[{type:'select-ammo',ammo}]},{method:'command',args:[{type:'fire',side}]},{method:'command',args:[{type:'fire',side}]},
 {method:'step',count:5},{method:'step',count:10},{method:'step',count:240}]);
}
run('permission-controls-rejections',{...calm,mode:'continuous',controllableShipIds:['player'],ships:[setup('player','fuchuan','player',0,0),setup('other','patrol','neutral',100,0)]},[
 ...[{type:'controls',rudder:2,sailDeployment:0},{type:'controls',shipId:'other',rudder:0,sailDeployment:0},{type:'select-ammo',ammo:'bad'},{type:'fire',side:'bad'},{type:'controls',rudder:.4,sailDeployment:.6,sailAngle:.2,autoTrim:false}].map(c=>({method:'command',args:[c]})),{method:'step',count:10}]);
run('ai-live-fire',{...calm,ships:[setup('player','fuchuan','player',0,0),setup('enemy','voc','hostile',0,110)]},[{method:'step',count:1},{method:'step',count:14},{method:'step',count:180}]);
run('unarmed-ai',{...calm,mode:'continuous',controllableShipIds:['player'],hostileTargets:{enemy:['player'],player:['enemy']},ships:[setup('player','fuchuan','player',0,0),setup('enemy','merchant','hostile',0,110)]},[{method:'step',count:120}]);
const fleet=[setup('player','fuchuan','player',0,0),setup('escort','patrol','player',100,0),setup('enemy','voc','hostile',0,200)];
const policy={controllableShipIds:['player','escort'],hostileTargets:{player:['enemy'],escort:['enemy'],enemy:['player','escort']}};
for(const kind of ['protect','intercept','keep-distance','focus','prepare-boarding','rally']){
 const intent=kind==='rally'?{kind,point:{x:350,z:30}}:kind==='keep-distance'?{kind,targetId:'enemy',range:150}:{kind,targetId:kind==='protect'?'escort':'enemy'};
 const order={id:`order-${kind}`,shipIds:['player'],intent};
 run(`order-${kind}`,{...calm,mode:'continuous',...policy,ships:fleet},[{method:'issueOrder',args:[order]},{method:'issueOrder',args:[order]},{method:'step',count:1},{method:'step',count:30},{method:'command',args:[{type:'controls',rudder:0,sailDeployment:0}]}]);
}
run('navigation-deep',{...calm,routePlanning:true,ships:[setup('player','fuchuan','player',0,0)]},[{method:'navigate',args:['player',{x:300,z:120}]},{method:'step',count:60},{method:'navigate',args:['player',null]}]);
run('reconcile-inertia',{...calm,mode:'continuous',controllableShipIds:['player'],ships:[setup('player','fuchuan','player',0,0,{speed:5})]},[
 {method:'step',count:30},{method:'reconcileShips',args:[[setup('player','fuchuan','player',999,999,{stats:{speedMultiplier:1.3}})],{controllableShipIds:['player'],hostileTargets:{},disabledMotionShipIds:['player']}]},{method:'step',count:60},
 {method:'command',args:[{type:'controls',rudder:0,sailDeployment:1}]},{method:'reconcileShips',args:[[setup('player','fuchuan','player',0,0),setup('player','voc','player',0,0)],{controllableShipIds:['player'],hostileTargets:{}}]}]);
run('surrender',{...calm,ships:[setup('player','fuchuan','player',0,0),setup('enemy','voc','hostile',0,110)]},[
 {method:'command',args:[{type:'fire',side:'starboard'}]},{method:'previewSurrender',args:[]},{method:'command',args:[{type:'surrender',request:{battleId:'oracle',tick:0,captorId:'enemy'}}]},{method:'step',count:60},{method:'command',args:[{type:'fire',side:'port'}]}]);
const waveFile=path.join(sourceRoot,'packages/scene-engine/src/engine/water/oceanWaves.js');
const waveText=fs.readFileSync(waveFile,'utf8');
hashes['packages/scene-engine/src/engine/water/oceanWaves.js']=createHash('sha256').update(waveText).digest('hex');
const waveSnippet=waveText.slice(waveText.indexOf('const originalWave'),waveText.indexOf('export function sampleOriginalProjectedOcean')).replace('export const ORIGINAL_PROJECTED_WAVES','const ORIGINAL_PROJECTED_WAVES');
const originalWaves=structuredClone(vm.runInContext(waveSnippet+'; ORIGINAL_PROJECTED_WAVES',context));
for(const kind of ['fuchuan','fisherman','merchant','voc','patrol','heavy']){
 const ship=setup('player',kind,'player',13,-27,{heading:.4,speed:3,sailDeployment:.8,stats:{steeringMultiplier:1.2}});
 run(`original-waves-${kind}`,{seed:42,battleId:'oracle',oceanWaves:originalWaves,wind:{direction:{x:-1,y:.3},speed:9},ships:[ship]},[
 {method:'command',args:[{type:'controls',rudder:.4,sailDeployment:.8}]},{method:'step',count:1},{method:'step',count:59},{method:'step',count:240},
 {method:'updateShipStats',args:['player',{stats:{speedMultiplier:1.3,cargoMass:1000,draftMeters:2.5}}]},{method:'step',count:120}]);
}
run('generic-waves-live-wind',{battleId:'generic',ships:[setup('player','patrol','player',100,30,{speed:3,sailDeployment:1})]},[
 {method:'step',count:300},{method:'setWind',args:[{direction:{x:.3,y:-.9},speed:11}]},{method:'step',count:300},{method:'updateShipStats',args:['player',{stats:{draftMeters:3}}]},{method:'step',count:120}]);
for(const hz of [30,60,120])run(`clock-${hz}hz`,{...calm,ships:[setup('player','patrol','player',0,0,{speed:3})]},[
 {method:'command',args:[{type:'fire',side:'port'}]},{method:'step',count:12*hz,seconds:1/hz},{method:'hasPendingAttacks',args:[]},{method:'hasPendingCombat',args:[]}]);
run('reload-crew-equipment',{...calm,ships:[setup('player','heavy','player',0,0,{crew:80,stats:{reloadMultiplier:1.3,cannonMultiplier:1.8}})]},[
 {method:'command',args:[{type:'fire',side:'port'}]},{method:'updateShipStats',args:['player',{stats:{reloadMultiplier:1,speedMultiplier:1.3}}]},
 {method:'step',count:35},{method:'step',count:520},{method:'command',args:[{type:'fire',side:'port'}]},{method:'step',count:240}]);
run('atomic-batch-service',{...calm,mode:'continuous',controllableShipIds:['player','escort'],ships:fleet.slice(0,2)},[
 {method:'navigate',args:['player',{x:300,z:40}]},{method:'step',count:10},
 {method:'reconcileShips',args:[[fleet[0],{...fleet[1],stats:{maxCrew:0}}],{controllableShipIds:['player','escort'],hostileTargets:{}}]},
 {method:'reconcileShips',args:[fleet.slice(0,2),{controllableShipIds:['player','escort'],hostileTargets:{},anchorShipIds:['player'],lockedShipIds:['player']}]},
 {method:'isAnchored',args:['player']},{method:'command',args:[{type:'controls',rudder:.3,sailDeployment:.8}]},{method:'step',count:10},
 {method:'setPlayerId',args:['escort']},{method:'anchorFleet',args:[['player','missing']]},{method:'anchorFleet',args:[['escort']]},{method:'isAnchored',args:['escort']}]);
run('atomic-staged-orders',{...calm,mode:'continuous',...policy,ships:fleet},[
 {method:'reconcileShips',args:[fleet,{...policy,orders:[{id:'staged',shipIds:['escort'],intent:{kind:'focus',targetId:'enemy'}}],navigation:{player:{x:300,z:-300}}}]},
 {method:'step',count:15},
 {method:'reconcileShips',args:[fleet,{...policy,disabledMotionShipIds:['escort'],orders:[{id:'invalid-stage',shipIds:['escort'],intent:{kind:'rally',point:{x:300,z:0}}}]}]},
 {method:'reconcileShips',args:[fleet,{...policy,capturedShipIds:['enemy']}]},{method:'step',count:240}]);
run('sink-victory',{...calm,ships:[setup('player','heavy','player',0,0,{stats:{cannonMultiplier:10}}),setup('enemy','fuchuan','neutral',0,45,{hull:8})]},[
 {method:'command',args:[{type:'fire',side:'starboard'}]},{method:'step',count:120},{method:'updateShipStats',args:['enemy',{hull:100}]},{method:'command',args:[{type:'controls',rudder:0,sailDeployment:1}]}]);
run('sink-defeat',{...calm,ships:[setup('player','patrol','player',0,0)]},[{method:'updateShipStats',args:['player',{hull:0}]},{method:'step',count:60}]);
run('contact-overlap',{...calm,ships:[setup('player','fuchuan','player',0,0,{speed:6,heading:.3}),setup('other','patrol','neutral',10,2,{speed:-4,heading:.9})]},[{method:'step',count:1},{method:'step',count:59},{method:'step',count:120}]);
run('wet-route-island',{...calm,_terrain:'island',routePlanning:true,ships:[setup('player','fuchuan','player',0,0,{speed:4})]},[{method:'navigate',args:['player',{x:250,z:0}]},{method:'step',count:1},{method:'step',count:119},{method:'navigationStatus',args:['player']}]);
run('route-rejected-endpoint',{...calm,_terrain:'dry',routePlanning:true,ships:[setup('player','fuchuan','player',0,0)]},[{method:'navigate',args:['player',{x:250,z:0}]},{method:'step',count:1},{method:'step',count:119},{method:'navigationStatus',args:['player']}]);
run('shore-swept-contact',{...calm,_terrain:'wall',ships:[setup('player','patrol','player',35,0,{speed:12,heading:.3})]},[{method:'step',count:120},{method:'command',args:[{type:'controls',rudder:1,sailDeployment:.6}]},{method:'step',count:240}]);
run('manual-assisted-recovery',{seed:42,battleId:'manual',_terrain:'deep',oceanWaves:[],wind:{direction:{x:1,y:0},speed:9},ships:[setup('player','fuchuan','player',0,0)]},[
 {method:'findManualRecoveryHeading',args:['player']},{method:'setManualHandling',args:['player',{mode:'assisted',turnIntent:.8,sailIntent:0,braking:true,recovery:false}]},{method:'step',count:120},
 {method:'navigate',args:['player',{x:250,z:0}]},{method:'setManualHandling',args:['player',{mode:'assisted',turnIntent:1,sailIntent:1,braking:false,recovery:true}]},{method:'step',count:120}]);
for(const heading of [0,Math.PI/2,Math.PI,-Math.PI/2])for(const side of ['port','starboard']){
 const sign=side==='starboard'?1:-1;
 run(`heading-${heading}-${side}`,{...calm,ships:[setup('player','fuchuan','player',0,0,{heading}),setup('victim','voc','neutral',-Math.sin(heading)*sign*70,Math.cos(heading)*sign*70,{heading})]},[
 {method:'command',args:[{type:'fire',side}]},{method:'step',count:180}]);
}
run('reconcile-validation',{...calm,mode:'continuous',controllableShipIds:['player'],ships:[setup('player','fuchuan','player',0,0)]},[
 ...[{stats:{draftMeters:.001}},{stats:{steeringMultiplier:3}},{stats:{cargoMass:1000000}},{ammo:{solid:-1}},{ammoType:'invalid'},{rudder:2},{sailDeployment:2},{sailAngle:Math.PI},{autoTrim:0},{kind:'voc'},{id:'replacement'}].map(update=>({method:'updateShipStats',args:['player',update]})),
 {method:'reconcileShips',args:[[setup('player','fuchuan','player',999,999,{stats:{speedMultiplier:1.3}})],{controllableShipIds:['missing'],hostileTargets:{}}]}]);
run('pending-attacks-policy',{...calm,mode:'continuous',...policy,ships:fleet},[
 {method:'hasPendingCombat',args:[]},{method:'hasPendingAttacks',args:[]},{method:'command',args:[{type:'fire',side:'starboard'}]},
 {method:'reconcileShips',args:[fleet,{...policy,anchorShipIds:['player']}]},{method:'hasPendingAttacks',args:[]},
 {method:'reconcileShips',args:[fleet.slice(0,2),{controllableShipIds:['player','escort'],hostileTargets:{}}]},
 {method:'step',count:600},{method:'hasPendingAttacks',args:[]},{method:'anchorFleet',args:[['player','escort']]}]);
run('six-ships-battle-original',{seed:77,battleId:'six-ships',oceanWaves:originalWaves,wind:{direction:{x:-1,y:.25},speed:10},ships:[
 setup('player','fuchuan','player',0,0,{sailDeployment:.65}),setup('escort','patrol','player',90,-80,{sailDeployment:.65}),setup('grain','merchant','player',-95,20,{sailDeployment:.6}),
 setup('voc','voc','hostile',0,130,{sailDeployment:.65}),setup('heavy','heavy','hostile',100,180,{sailDeployment:.65}),setup('fisherman','fisherman','neutral',-150,-100,{sailDeployment:.6})]},[
 {method:'command',args:[{type:'fire',side:'starboard'}]},{method:'step',count:1200},{method:'step',count:3600}]);
for(const seed of [42.5,-42.5,1e100,1e308])run(`fractional-large-seed-${seed}`,{...calm,seed,enemyCount:2},[{method:'hasPendingCombat',args:[]},{method:'step',count:2}]);
for(const pair of [['A','a'],['a-a','a_a'],['ab','áb'],['中','文'],['α','Α'],['é','e\u0301']]){
 const [left,right]=pair;
 const tieShips=[setup('player','fuchuan','player',0,0),setup(left,'patrol','hostile',-10,100),setup(right,'patrol','hostile',10,100)];
 const tiePolicy={controllableShipIds:['player'],hostileTargets:{player:[left,right],[left]:['player'],[right]:['player']}};
 run(`locale-target-${left}-${right}`,{...calm,mode:'continuous',...tiePolicy,ships:tieShips},[
 {method:'command',args:[{type:'fire',side:'starboard'}]},{method:'step',count:1},{method:'step',count:15}]);
 const protectShips=[setup('player','fuchuan','player',0,-100),setup('ally','merchant','player',0,0),setup(left,'patrol','hostile',-100,0),setup(right,'patrol','hostile',100,0)];
 run(`locale-protect-${left}-${right}`,{...calm,mode:'continuous',...tiePolicy,ships:protectShips},[
 {method:'issueOrder',args:[{id:'protect-tie',shipIds:['player'],intent:{kind:'protect',targetId:'ally'}}]},{method:'step',count:1}]);
 run(`locale-ai-avoidance-${left}-${right}`,{...calm,mode:'continuous',...tiePolicy,ships:[setup('player','fuchuan','player',0,100),setup(left,'patrol','hostile',0,0),setup(right,'patrol','hostile',20,5)]},[{method:'step',count:1},{method:'step',count:15}]);
}
const overflowWave={direction:{x:1,y:0},amplitude:8.8e307,wavelength:100,speed:0};
const overflowShip=setup('player','fuchuan','player',0,0,{stats:{draftMeters:1e307}});
run('overflow-live-update',{...calm,oceanWaves:[overflowWave],ships:[setup('player','fuchuan','player',0,0)]},[
 {method:'updateShipStats',args:['player',{stats:{draftMeters:1e307}}]},{method:'reconcileShips',args:[[overflowShip]]}]);
const resetProbe=new NavalEncounter(calm),resetBefore=resetProbe.snapshot();let resetRejection;
try{resetProbe.reset({...calm,ships:[overflowShip],oceanWaves:[overflowWave]});throw new Error('Source unexpectedly accepts overflow')}catch(error){resetRejection={reason:error.message,unchanged:JSON.stringify(resetProbe.snapshot())===JSON.stringify(resetBefore)}}
if(resetRejection.reason!=='Ship heave travel limit must be finite'||!resetRejection.unchanged)throw new Error('Unexpected source reset rejection');
const sweeps=[];
const collision=load(path.join(sourceRoot,'packages/naval-core/src/collision.ts')).namespace.sweepMovingBox;
for(const [name,from,to,previous,current,box] of [
 ['high-speed',{x:-100,y:1,z:0},{x:100,y:1,z:0},{position:{x:0,y:0,z:0},heading:0},{position:{x:0,y:0,z:0},heading:0},{length:20,width:8,bottom:-2,top:5}],
 ['relative-translation',{x:0,y:2,z:-12},{x:0,y:2,z:12},{position:{x:-8,y:0,z:0},heading:0},{position:{x:8,y:0,z:0},heading:0},{length:10,width:5,bottom:-2,top:5}],
 ['rotating-hull',{x:7,y:1,z:-8},{x:7,y:1,z:8},{position:{x:0,y:0,z:0},heading:-.3},{position:{x:0,y:0,z:0},heading:.4},{length:20,width:4,bottom:-2,top:4}],
 ['mast-hit',{x:-20,y:10,z:0},{x:20,y:10,z:0},{position:{x:0,y:2,z:0},heading:1},{position:{x:0,y:3,z:0},heading:1},{length:18,width:5,bottom:4,top:20}],
 ['miss',{x:-100,y:10,z:100},{x:100,y:10,z:100},{position:{x:0,y:0,z:0},heading:0},{position:{x:0,y:0,z:0},heading:0},{length:20,width:8,bottom:-2,top:5}],
 ])sweeps.push({name,from,to,previous,current,box,expected:collision(from,to,previous,current,box)});
const routes=[];
const planner=load(path.join(sourceRoot,'packages/naval-core/src/route-planner.ts'));
const plan=planner.namespace.planWetRoute;
for(const terrain of ['deep','wall','island','dry','nan']){
 const sampler=terrainFor(terrain);
 routes.push({terrain,start:{x:0,z:0},target:{x:250,z:0},hull:{length:32,width:9,draft:2},expected:plan({x:0,z:0},{x:250,z:0},{length:32,width:9,draft:2},sampler)});
}
routes.push({terrain:'deep',start:{x:0,z:0},target:{x:3000,z:0},hull:{length:32,width:9,draft:2},expected:plan({x:0,z:0},{x:3000,z:0},{length:32,width:9,draft:2},()=>-100)});
const filename=path.join(targetRoot,'tests/fixtures/naval-reference.json');
fs.mkdirSync(path.dirname(filename),{recursive:true});
fs.writeFileSync(filename,JSON.stringify({sourceRoot,sourceHead:head,hashes,cases,routes,sweeps,localePairs,resetRejection},null,2)+'\n');
console.log(`NAVAL_REFERENCE_OK ${cases.length} cases ${routes.length} routes ${filename}`);
