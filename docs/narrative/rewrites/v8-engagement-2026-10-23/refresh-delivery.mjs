import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../../..');
const absolute=p=>path.join(root,p);
const story=JSON.parse(fs.readFileSync(absolute('docs/narrative/zheng-zhilong-story.json'),'utf8'));
if(story.version!=='v8-engagement-historical-2026-10-23')throw new Error('V8 source required');
const save=(relative,text)=>fs.writeFileSync(absolute(relative),text);
const backup=(relative,name)=>{
 const target=path.join(dir,'baseline',name);
 if(!fs.existsSync(target))fs.copyFileSync(absolute(relative),target);
};
const reader='docs/narrative/zheng-zhilong/';
backup(reader+'index.html','reader-index.html');
let html=fs.readFileSync(absolute(reader+'index.html'),'utf8');
html=html.replaceAll('20261023-v7-readthrough','20261023-v8-engagement');
html=html.replace('<a href="../zheng-zhilong-campaign-script-2026-10-21.md" download>下载完整文学剧本</a>','<a href="novel-v8.md" download>下载小说正文</a><a href="screenplay-v8.md" download>下载完整文学剧本</a><a href="game-scenes-v8.md" download>下载游戏场景稿</a>');
save(reader+'index.html',html);
const manifest=JSON.parse(fs.readFileSync(absolute(reader+'illustration-manifest.json'),'utf8'));
manifest.storyVersion=story.version;
manifest.updated='2026-10-23';
const revisedFrame=story.acts.flatMap(a=>a.scenes).flatMap(s=>s.illustrations||[]).find(f=>f.id==='yiguan_a4_s3_process2');
if(revisedFrame)manifest.illustrations.find(f=>f.id===revisedFrame.id).caption=revisedFrame.caption;
manifest.disclaimer='本轮V8复用33项既有图像。5项的原始新绘与目视审读属于V7，其余为更早情境参考；原review及来源保留，不代表V8逐动作重新绘图或全量视觉验收。概念图不是历史现场证据。';
manifest.textRevisionScope={version:story.version,generatedImages:0,scope:'Text and anchors revised; prior image reviews retain their original version scope.'};
save(reader+'illustration-manifest.json',JSON.stringify(manifest,null,2)+'\n');
// Only advance the resource library's reference to the current text. Its 170
// legacy requirements, artwork, baselines and production audit remain untouched.
for(const relative of ['docs/production/resource-library/catalog.json','assets/production/catalog.json']){
 backup(relative,relative.replaceAll('/','--'));
 const catalog=JSON.parse(fs.readFileSync(absolute(relative),'utf8'));
 catalog.storyVersion=story.version;
 save(relative,JSON.stringify(catalog,null,2)+'\n');
}
const catalog=JSON.parse(fs.readFileSync(absolute('docs/production/resource-library/catalog.json'),'utf8'));
backup('docs/production/resource-library/data.js','resource-library-data.js');
save('docs/production/resource-library/data.js','window.MING_RESOURCE_LIBRARY='+JSON.stringify(catalog)+';\n');
console.log(JSON.stringify({version:story.version,readerDownloads:['novel-v8.md','screenplay-v8.md','game-scenes-v8.md'],existingImages:manifest.illustrations.length,newImages:0,resourceItems:catalog.items.length}));
