import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import {fileURLToPath} from 'node:url';

const dir=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(dir,'../../../..');
const reader=path.join(root,'docs/narrative/zheng-zhilong');
const target=path.join(root,'docs/narrative/zheng-zhilong-story.json');
const story=JSON.parse(fs.readFileSync(target,'utf8'));
if(story.version!=='v7-reviewed-illustrated-2026-10-23')throw new Error('Expected reviewed v7.');
const manifestPath=path.join(reader,'illustration-manifest.json');
const oldBytes=fs.readFileSync(manifestPath),manifest=JSON.parse(oldBytes);
const archive=path.join(dir,'received-illustration-manifest.json');
if(!fs.existsSync(archive))fs.writeFileSync(archive,oldBytes);
const descriptions={
 yiguan_a3_s3:'雾中可辨援旗，一官按住锣沿，陈添放下锣槌。',
 yiguan_a5_s1:'杜七拿着旧旗与封套交涉，空左袖收在腰侧。',
 yiguan_a5_s2:'旧衣在下，新衣在上；郑森的手停在磨薄的领口。',
 yiguan_a5_s4_after2:'受控北上途中，一官由内河短渡上岸，前方押送者已定去路。',
 yiguan_a4_s2_process2:'半沉破船旁，阿旺托扶杜七入救艇；左臂伤处藏在包裹中，只露右手。'
};
const expectedIds=Object.keys(descriptions),adopted=[];
for(const reportFile of ['image-worker-scholar-north.json','image-worker-fog-flag.json']){
 const report=JSON.parse(fs.readFileSync(path.join(dir,reportFile),'utf8'));
 for(const asset of report.assets||report.images){
  if(!expectedIds.includes(asset.id)||adopted.includes(asset.id))throw new Error('Unrequested or duplicate asset');
  const bytes=fs.readFileSync(asset.targetPath),hash=crypto.createHash('sha256').update(bytes).digest('hex');
  if(hash!==asset.sha256||!bytes.equals(fs.readFileSync(asset.sourcePath)))throw new Error('Source/copy mismatch');
  const width=bytes.readUInt32BE(16),height=bytes.readUInt32BE(20);
  if(width<=800||height<=800)throw new Error('Image dimensions too small');
  const relative=path.relative(reader,asset.targetPath).replaceAll('\\','/');
  if(!relative.startsWith('images/film-v7/'))throw new Error('Expected project-bound v7 file');
  const scene=story.acts.flatMap(a=>a.scenes).find(s=>s.id===asset.id);
  const frame=story.acts.flatMap(a=>a.scenes).flatMap(s=>s.illustrations||[]).find(f=>f.id===asset.id);
  const content=scene||frame;
  if(!content)throw new Error(`Missing content ${asset.id}`);
  const prompt=asset.revisionPrompt?`${asset.prompt}\n\nFinal revision request:\n${asset.revisionPrompt}`:asset.prompt;
  content.image=relative;content.imagePrompt=prompt;content.illustrationStatus='ready';content.illustrationScope='v7-scene-reviewed';
  if(scene){content.imageCaption=descriptions[asset.id];content.imageWidth=width;content.imageHeight=height;}
  else {content.caption=descriptions[asset.id];content.width=width;content.height=height;}
  const index=manifest.illustrations.findIndex(i=>i.id===asset.id);
  if(index<0)throw new Error(`Missing manifest id ${asset.id}`);
  const prior=manifest.illustrations[index];
  manifest.illustrations[index]={id:asset.id,path:relative,sourcePath:asset.sourcePath,prompt,caption:descriptions[asset.id],width,height,sha256:hash,reused:false,adopted:true,narrativeStatus:'reviewed-v7-scene',generatedAt:'2026-10-23',review:'协调者逐图目视核对人物年龄、发式、主要动作、伤残阶段及画面空间；'+descriptions[asset.id]+'。新图为小说情境重建，不作为历史原件。',reviewEvidence:path.relative(root,path.join(dir,reportFile)).replaceAll('\\','/'),supersedes:{id:prior.id,path:prior.path,sha256:prior.sha256,reason:'Old image does not match revised scene; original file and full old manifest preserved.'}};
  adopted.push(asset.id);
 }
}
if(adopted.length!==5)throw new Error('Five new accepted images required');
manifest.storyVersion=story.version;manifest.updated='2026-10-23';manifest.disclaimer='五幅按第七稿新绘并目视核对的概念插图，另二十八项保留旧稿情境参考；逐项以reused/review区分。并非历史现场影像或全部最终美术。';
story.sourceNotes.push('2026-10-23：接手审读后保291段修连续性，重绘原四项延期图，并追加修正厦门救援过程图的断手穿帮。五张新图逐一保存prompt、原件与哈希；其余28项仍是旧稿情境参考。');
fs.writeFileSync(target,JSON.stringify(story,null,2)+'\n');
fs.writeFileSync(manifestPath,JSON.stringify(manifest,null,2)+'\n');
fs.writeFileSync(path.join(dir,'adopted-illustrations.json'),JSON.stringify({date:'2026-10-23',adopted,newlyGenerated:5,retainedReferences:28,expectedReferences:33},null,2)+'\n');
console.log(JSON.stringify({adopted:adopted.length,references:manifest.illustrations.length}));
