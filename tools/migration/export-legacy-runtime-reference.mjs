// Frozen runtime oracle: TypeScript transpiled in memory, source never written.
import fs from 'node:fs';
import path from 'node:path';
import vm from 'node:vm';
import {createRequire} from 'node:module';
import {createHash} from 'node:crypto';
import {execFileSync} from 'node:child_process';
import {fileURLToPath} from 'node:url';
const source=path.resolve(process.argv[2]??'C:/Users/dains/.codex/worktrees/zheng-sailing-adventure/MingArmada');
const target=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const head=execFileSync('rtk',['git','-C',source,'rev-parse','HEAD'],{encoding:'utf8'}).trim();
if(head!=='9ad6a44daecd4ec36a8172d83ff27493feffe5dd')throw Error('wrong source HEAD');
const watched=['apps/game-client/src/simulation/AdventureRuntime.ts','apps/game-client/src/simulation/SailingSimulation.ts','packages/adventure-core/src','packages/naval-core/src','packages/physics-core/src'];
execFileSync('rtk',['git','-C',source,'diff','--exit-code','HEAD','--',...watched],{encoding:'utf8'});
const requireSource=createRequire(path.join(source,'package.json'));const ts=requireSource('typescript');
const hashes={},modules=new Map();
let identity=0;
const context=vm.createContext({console,Math,Number,Array,Object,Map,Set,Symbol,Error,RangeError,TypeError,JSON,Uint8Array,TextEncoder,structuredClone,crypto:{randomUUID:()=>`oracle-battle-${++identity}`}});
function load(file){
 file=path.resolve(file);if(file.endsWith('.js')&&fs.existsSync(file.replace(/\.js$/,'.ts')))file=file.replace(/\.js$/,'.ts');
 if(modules.has(file))return modules.get(file);
 const text=fs.readFileSync(file,'utf8');hashes[path.relative(source,file).replaceAll('\\','/')]=createHash('sha256').update(text).digest('hex');
 const m=new vm.SourceTextModule(ts.transpileModule(text,{compilerOptions:{target:ts.ScriptTarget.ES2022,module:ts.ModuleKind.ES2022}}).outputText,{context,identifier:file});modules.set(file,m);return m;
}
function resolve(spec,parent){
 if(spec.startsWith('@ming-armada/'))return path.join(source,'packages',spec.slice('@ming-armada/'.length),'src/index.ts');
 return path.resolve(path.dirname(parent),spec);
}
const entry=load(path.join(source,'apps/game-client/src/simulation/AdventureRuntime.ts'));
await entry.link((spec,parent)=>{
 if(spec==='three'){
  if(modules.has('three'))return modules.get('three');
  const real=requireSource('three'),names=Object.keys(real);const m=new vm.SyntheticModule(names,function(){for(const name of names)this.setExport(name,real[name]);},{context,identifier:'three'});modules.set('three',m);return m;
 }
 return load(resolve(spec,parent.identifier));
});await entry.evaluate();
const {AdventureRuntime}=entry.namespace;
const sessionEntry=modules.get(path.join(source,'packages/adventure-core/src/session.ts'));
const {AdventureSession}=sessionEntry.namespace;
function project(runtime){
 const s=runtime.snapshot(),n=runtime.nativeSnapshot();
 const domain={};for(const key of ['seed','elapsedSeconds','day','player','flagshipId','currentPortId','cargo','quests','relations','mainChapter','career','markets','battleActive','officers','ammoStocks','supplyPerDay','wagesPerDay'])domain[key]=s[key];
 domain.fleet=s.fleet.map(f=>Object.fromEntries(Object.entries(f).filter(([k])=>!['position','heading','speed','navalState'].includes(k))));
 return {domain,native:{tick:n.tick,status:n.status,playerId:n.playerId,ships:n.ships.map(f=>{const ship={};for(const key of ['id','name','kind','team','hull','sail','crew','ammo','stats','sailDeployment'])ship[key]=f[key];return ship;})}};
}
const data={sourceHead:head,sourceHashes:hashes,sourceWrites:0,scenarios:[]};
const domainOracle=JSON.parse(fs.readFileSync(path.join(target,'tests/fixtures/legacy-reference.json'),'utf8'));
if(domainOracle.sourceHead!==head)throw Error('wrong domain oracle HEAD');
data.checkpointSourceHashes=domainOracle.sourceHashes;
data.careerCheckpoints={};
for(const index of [14,37,62,68,73]){
 const step=domainOracle.scenarios.find(s=>s.name==='chapters').steps[index];
 const owner=AdventureSession.restore(JSON.stringify(step.save));
 // A safe checkpoint before nearby enemies activate. Same source Native snapshot,
 // no events, source Session clears battleActive through its real sync operation.
 if(step.kind==='sync')owner.syncNaval({...step.args.snapshot,status:'sailing'},[]);
 data.careerCheckpoints[index]=owner.serialize();
}
const runtime=new AdventureRuntime(new AdventureSession({seed:1661,name:'沈沧海'}));
const scenario={name:'source-business-runtime',options:{seed:1661,name:'沈沧海',initialDock:false},initial:project(runtime),steps:[]};data.scenarios.push(scenario);
for(const command of [{type:'dock',portId:'xiamen'},{type:'buy',good:'iron',quantity:2},{type:'hire-officer',role:'gunner'},{type:'hire-officer',role:'gunner'},{type:'buy',good:'grain',quantity:-1},{type:'sell',good:'grain',quantity:1},{type:'rename',name:'  林船长  '},{type:'accept-quest',questId:'main-1'},{type:'depart'}]){
 const result=runtime.command(command);scenario.steps.push({command,result,projection:project(runtime)});
}
// Actual frozen runtime persistence/refusal, rather than fixture hand-authored guesses.
scenario.exportReceipt=runtime.exportSave();
execFileSync('rtk',['git','-C',source,'diff','--exit-code','HEAD','--',...Object.keys(hashes)],{encoding:'utf8'});
const output=path.join(target,'tests/fixtures/legacy-runtime-reference.json');fs.writeFileSync(output,JSON.stringify(data,null,2)+'\n');
console.log(`LEGACY_RUNTIME_ORACLE scenarios=${data.scenarios.length} steps=${scenario.steps.length} modules=${modules.size} sourceWrites=0`);
