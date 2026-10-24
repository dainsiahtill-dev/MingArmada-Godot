(() => {
  'use strict';
  const data=window.MODEL_PREPRODUCTION;
  const labels={ships:'船舰',weapons:'炮械与船具',characters:'人物与头部',garments:'衣装与帽具',buildings:'港口建筑模块',environment:'自然环境',props:'生活与贸易道具'};
  const el=(tag,text,cls)=>{const n=document.createElement(tag);if(text!==undefined)n.textContent=text;if(cls)n.className=cls;return n;};
  const file=p=>'../../../'+p;
  const link=(text,href)=>{const a=el('a',text);a.href=href;return a;};
  if(!data){document.querySelector('#progress').textContent='清单未能加载。请检查同目录data.js，或打开manifest.json。';return;}
  const s=data.summary;
  document.querySelector('#progress').textContent=`${s.production}项制作基线 + ${s.reserve}项预备 / ${s.characters}个人物身份（${s.directCharacters}人直接在场） / ${s.generatedImages}张已生成，共${s.artJobs}张计划。`;
  for(const [id,name] of Object.entries(labels)){const o=el('option',name);o.value=id;document.querySelector('#group').append(o);}
  function render(){
    const search=document.querySelector('#search').value.trim().toLowerCase(),group=document.querySelector('#group').value,status=document.querySelector('#status').value,scope=document.querySelector('#scope').value;
    const selected=data.artJobs.filter(j=>(group==='all'||j.group===group)&&(scope==='all'||j.scope===scope)&&(status==='all'||status==='pending'&&j.status==='not-generated'||status==='generated'&&j.status!=='not-generated'||status==='redraw'&&j.generation?.review?.status==='needs-redraw')&&(!search||[j.id,j.title,j.brief,...j.covers].join(' ').toLowerCase().includes(search)));
    document.querySelector('#result-count').textContent=`显示${selected.length}张草图任务，其中${selected.filter(j=>j.status!=='not-generated').length}张已有图片。`;
    const out=document.querySelector('#results');out.replaceChildren();
    if(!selected.length){out.append(el('p','没有符合条件的资源。可清除筛选后重新查找。'));return;}
    for(const j of selected){
      const a=el('article',undefined,'sheet');a.id=j.id;
      const head=el('div',undefined,'sheet-head'),title=el('div');title.append(el('h2',j.title),el('p',j.id+' · '+labels[j.group]));head.append(title,el('span',j.status==='not-generated'?'尚未生成':j.generation?.review?.status==='needs-redraw'?'需要修订':'候选草图','status'));a.append(head);
      const preferred=j.preferredImagePath||j.imagePath;
      if(j.status!=='not-generated') {const imageLink=link('',file(preferred));imageLink.className='image-link';const img=el('img');img.src=file(preferred);img.alt=j.title+'的多方向建模候选草图';img.loading='lazy';img.decoding='async';imageLink.append(img);a.append(imageLink);}else a.append(el('div','该任务已有资源简报，尚未生成多视图。','pending'));
      a.append(el('p',j.brief||'外形要求见资源简报与考据分册。','brief'),el('p',`覆盖制作项：${j.covers.join('、')} · ${j.scope==='reserve'?'预备项':'制作基线'}`,'meta'));
      const dir=j.imagePath.slice(0,j.imagePath.lastIndexOf('/'));
      const links=el('div',undefined,'links');links.append(link('资源简报',file(dir+'/art-brief.json')));
      if(j.status!=='not-generated'){links.append(link('查看原图',file(preferred)),link('生成与审查记录',file(dir+'/generation.json')));if(j.generation?.promptPath)links.append(link('提示词',file(j.generation.promptPath)));}
      const research=data.models.find(m=>j.covers.includes(m.id))?.research;if(research)links.append(link('考据分册',file(research)));a.append(links);
      if(j.generation?.review){const d=el('details');d.append(el('summary','查看本张目视审查与未决问题'),el('pre',JSON.stringify(j.generation.review,null,2)));a.append(d);}
      out.append(a);
    }
  }
  document.querySelector('#filters').addEventListener('input',render);document.querySelector('#filters').addEventListener('reset',()=>setTimeout(render));
  for(const scene of data.scenePackages){const row=el('div',undefined,'scene-row');row.append(el('strong',scene.name),el('p',scene.note));document.querySelector('#scene-packages').append(row);}
  for(const x of data.unresolvedComponents)document.querySelector('#unresolved').append(el('li',x.name+'：'+x.note));
  render();
})();
