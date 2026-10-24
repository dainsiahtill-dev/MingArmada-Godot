(() => {
  'use strict';
  const renderers = new Map();
  const e = value => String(value ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const paths = {ship:'M3 16l3 5h12l3-5H3zm9-14v13M11 3L4 13h7m3-8v8h6z',map:'M3 5l6-2 6 2 6-2v16l-6 2-6-2-6 2V5zm6-2v16m6-14v16',bag:'M4 7h16v14H4zM8 7V5a4 4 0 018 0v2',book:'M3 4h7l2 2 2-2h7v16h-7l-2 2-2-2H3V4zm9 2v16',people:'M16 21v-3a4 4 0 00-4-4H6a4 4 0 00-4 4v3m10-13a4 4 0 11-8 0 4 4 0 018 0zm4-4a4 4 0 010 8m2 3a4 4 0 014 4v2',trade:'M3 7h17l-4-4m5 14H4l4 4',letter:'M3 5h18v14H3V5zm0 0l9 8 9-8',flag:'M4 22V3m0 0c5-5 11 5 16 0v11c-5 5-11-5-16 0',settings:'M12 8a4 4 0 100 8 4 4 0 000-8zm0-6v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10l2 2M5 19l2-2M17 7l2-2',arrow:'M4 12h16m-6-6l6 6-6 6',compass:'M12 2a10 10 0 100 20 10 10 0 000-20zm4 6l-3 5-5 3 3-5 5-3z',cannon:'M3 10l17-4 2 5-17 5-2-6zm3 6l-2 5m12-8l4 8M8 20h10',anchor:'M12 2v19M8 6h8M3 13c0 11 18 11 18 0M1 15l2-2 3 1m12 0l3-1 2 2',coin:'M12 2a10 10 0 100 20 10 10 0 000-20zm-3 7h6v6H9V9z',check:'M4 12l5 5L21 5',close:'M5 5l14 14M19 5L5 19'};
  const icon = name => `<svg class="icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.35" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="${paths[name] || paths.compass}"/></svg>`;
  const attrs = data => Object.entries(data || {}).map(([key,value]) => key === 'disabled' ? (value ? ' disabled' : '') : ` data-${key.replace(/[^a-z0-9-]/gi,'')}="${e(value)}"`).join('');
  const ui = {
    cargoWeights:{grain:1,wood:2,iron:2,silk:1,porcelain:2,spices:1},
    cargoUsed:state=>Object.entries(state.stock||{}).reduce((sum,[id,count])=>sum+Number(count||0)*({grain:1,wood:2,iron:2,silk:1,porcelain:2,spices:1}[id]||1),0),
    e,icon,asset: name => `../../../../assets/art/${name}`,shipImage:'assets/fuchuan-inspection.png',sailingImage:'assets/sailing-background.png',portImage:'assets/port-hub-v2.png',
    sceneURL: id => `../../../narrative/zheng-zhilong/${window.GAME_UI_DATA?.sceneImages?.[id] || 'images/film-v4/zheng_a5_s4.png'}`,
    go:(id,label,cls='button')=>`<button type="button" class="${e(cls)}" data-go="${e(id)}">${label}</button>`,
    action:(action,label,cls='button',data={})=>`<button type="button" class="${e(cls)}" data-action="${e(action)}"${attrs(data)}>${label}</button>`,
    pageHead:(kicker,title,description,actions='')=>`<header class="page-head"><div><p class="context-label">${e(kicker)}</p><h1>${e(title)}</h1>${description?`<p class="page-description">${e(description)}</p>`:''}</div><div class="toolbar">${actions}</div></header>`,
    metric:(label,value,unit='',note='')=>`<div class="metric"><span>${e(label)}</span><strong>${e(value)}<small>${e(unit)}</small></strong>${note?`<p>${e(note)}</p>`:''}</div>`,
    pill:(text,tone='')=>`<span class="pill ${e(tone)}">${e(text)}</span>`,
    tabs:(items,active)=>`<nav class="tabs" aria-label="同类页面">${items.map(item=>ui.go(item.id,e(item.label),`tab ${item.id===active?'active':''}`)).join('')}</nav>`
  };
  window.GameUI = {renderers,ui,registerRenderer(ids,renderer){ for(const id of ids){if(renderers.has(id))throw new Error(`Duplicate screen renderer: ${id}`);renderers.set(id,renderer);} }};
})();
