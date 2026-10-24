import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {loadGameUiStory,uiStoryBaselinePath,uiStoryBaselineSha256} from './game-ui-story-baseline.mjs';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const folder=path.join(root,'docs/design/game-ui');
const data=JSON.parse(fs.readFileSync(path.join(folder,'systems.json'),'utf8'));
const story=loadGameUiStory(root);
data.narrativeReference={version:story.version,sourcePath:uiStoryBaselinePath,sha256:uiStoryBaselineSha256,integration:'legacy-ui-simulation-not-new-mainline',currentScreenplay:'docs/narrative/zheng-zhilong/index.html'};
data.scenes=story.acts.flatMap(act=>act.scenes.map(scene=>({id:scene.id,title:scene.title,year:scene.year,summary:scene.summary,paragraphs:scene.paragraphs.slice(0,2),dialogue:scene.dialogue,history:scene.history,act:act.title,task:scene.task,location:scene.location,dramaticBeat:scene.dramaticBeat,currentCanon:scene.currentCanon,choices:scene.choices})));
data.acts=story.acts.map(a=>({id:a.id,title:a.title,years:a.years,cover:a.cover,synopsis:a.synopsis,first:a.scenes[0].id}));
data.sceneImages=Object.fromEntries(story.acts.flatMap(a=>a.scenes.map(s=>[s.id,s.image])));
for(const [key,name] of [['productionAssets','production-assets.json'],['artCatalog','ui-art-adoptions.json']]){
  const filename=path.join(folder,name);if(fs.existsSync(filename))data[key]=JSON.parse(fs.readFileSync(filename,'utf8'));
}
data.previewIds=data.screenGroups.flatMap(g=>g.screens).filter(s=>fs.existsSync(path.join(folder,'prototype/previews',`${s.id}.jpg`))).map(s=>s.id);
data.statePreviews=Object.fromEntries(data.screenGroups.flatMap(g=>g.screens).map(s=>[s.id,s.states.map((state,index)=>({state,file:`${s.id}--${String(index+1).padStart(2,'0')}.jpg`})).filter(x=>fs.existsSync(path.join(folder,'prototype/previews/states',x.file)))]));
const out='window.GAME_UI_DATA = '+JSON.stringify(data).replace(/</g,'\\u003c').replace(/\u2028/g,'\\u2028')+';\n';
fs.writeFileSync(path.join(folder,'prototype/data.js'),out);
console.log(`GAME_UI_DATA systems=${data.systems.length} pages=${data.screenGroups.flatMap(g=>g.screens).length} previews=${data.previewIds.length}`);
