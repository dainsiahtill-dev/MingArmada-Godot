(() => {
  'use strict';

  const data = window.MING_ARMADA;
  if (!data || !Array.isArray(data.features)) {
    const warning = document.createElement('p');
    warning.className = 'notice';
    warning.setAttribute('role', 'alert');
    warning.textContent = '玩法资料暂未载入。请重新构建网页，并从 dist/index.html 打开完整版本。';
    document.querySelector('#ways').append(warning);
    return;
  }

  const statusNames = { playable: '已可玩', experiment: '实验中', planned: '规划中' };
  const kindNames = { game: '游戏实机', experiment: '独立实验', render: '模型渲染', art: '生成原画' };
  const byId = new Map(data.features.map(feature => [feature.id, feature]));
  const state = { status: 'all', query: '', selected: data.features[0].id, ship: data.ships[0].id };
  let shipCategory = 'all';
  const directory = document.querySelector('#feature-directory');
  const detail = document.querySelector('#feature-detail');
  const search = document.querySelector('#feature-search');
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');

  function element(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function badge(status) {
    return element('span', `status status-${status}`, statusNames[status]);
  }

  function normalized(value) {
    return value.normalize('NFKC').toLocaleLowerCase('zh-CN').trim();
  }

  function matchingFeatures() {
    const words = normalized(state.query).split(/\s+/).filter(Boolean);
    return data.features.filter(feature => {
      if (state.status !== 'all' && feature.status !== state.status) return false;
      const haystack = normalized([feature.title, feature.category, feature.summary,
        feature.description, feature.tradeoff, ...feature.playerChoices].join(' '));
      return words.every(word => haystack.includes(word));
    });
  }

  function imageButton(key) {
    const media = data.media[key];
    const button = element('button', 'image-button');
    button.type = 'button';
    button.dataset.openImage = key;
    button.setAttribute('aria-label', `放大图片：${media.caption}`);
    const img = element('img');
    img.src = media.src;
    img.alt = media.alt;
    img.width = media.width;
    img.height = media.height;
    img.loading = 'lazy';
    img.decoding = 'async';
    const hint = element('span', 'image-expand', '查看大图 ↗');
    hint.setAttribute('aria-hidden', 'true');
    button.append(img, hint);
    return button;
  }

  function renderDetail(feature) {
    detail.replaceChildren();
    if (!feature) {
      const empty = element('div', 'empty-state');
      empty.append(element('h3', '', '还没有找到这条航路'),
        element('p', '', '试试“火攻”“贸易”或“英雄”，也可以展开全部玩法。'));
      const reset = element('button', 'reset-search', '清空筛选，展开全部');
      reset.type = 'button';
      reset.dataset.resetSearch = 'true';
      empty.append(reset);
      detail.append(empty);
      return;
    }
    const media = data.media[feature.imageKey];
    const figure = element('figure', 'detail-visual');
    figure.append(imageButton(feature.imageKey), element('figcaption', '', media.caption));
    const titleLine = element('div', 'detail-title-line');
    titleLine.append(element('h3', 'feature-title', feature.title), badge(feature.status));
    detail.append(figure, titleLine,
      element('p', 'detail-summary', feature.summary),
      element('p', 'detail-description', feature.description));
    const choices = element('ul', 'detail-choices');
    feature.playerChoices.forEach(choice => choices.append(element('li', '', choice)));
    const cost = element('p', 'detail-tradeoff');
    cost.append(element('strong', '', '取舍'), document.createTextNode(feature.tradeoff));
    detail.append(choices, cost);
    if (feature.status === 'planned') {
      detail.append(element('p', 'planned-visual-note', '配图展示现有素材；本项完整玩法尚未开放。'));
    }
    const related = element('div', 'detail-related');
    related.append(element('span', '', '沿着这条航路：'));
    feature.related.forEach(id => {
      const button = element('button', 'related-link', byId.get(id).title);
      button.type = 'button';
      button.dataset.relatedFeature = id;
      related.append(button);
    });
    detail.append(related);
  }

  function renderFeatures() {
    const visible = matchingFeatures();
    if (!visible.some(feature => feature.id === state.selected)) state.selected = visible[0]?.id ?? null;
    directory.replaceChildren();
    visible.forEach(feature => {
      const button = element('button', 'feature-entry');
      button.type = 'button';
      button.dataset.featureId = feature.id;
      button.setAttribute('aria-pressed', String(feature.id === state.selected));
      button.setAttribute('aria-controls', 'feature-detail');
      const top = element('span', 'feature-entry-top');
      top.append(element('span', 'feature-entry-title', feature.title), badge(feature.status));
      button.append(top, element('small', '', feature.summary));
      directory.append(button);
    });
    if (!visible.length) directory.append(element('p', 'inline-note', '没有匹配的玩法。'));
    document.querySelector('#result-count').textContent = `收录 ${data.features.length} 种玩法 · 当前展示 ${visible.length} 项`;
    document.querySelectorAll('[data-status]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.status === state.status));
    });
    renderDetail(byId.get(state.selected));
  }

  function selectFeature(id, fromRelated = false) {
    if (fromRelated) {
      state.status = 'all';
      state.query = '';
      search.value = '';
    }
    state.selected = id;
    renderFeatures();
    const selected = directory.querySelector(`[data-feature-id="${id}"]`);
    selected?.focus({ preventScroll: true });
    if (fromRelated) detail.scrollIntoView({ block: 'start', behavior: reducedMotion.matches ? 'instant' : 'smooth' });
  }

  search.addEventListener('input', () => { state.query = search.value; renderFeatures(); });
  document.querySelector('.filters').addEventListener('click', event => {
    const button = event.target.closest('[data-status]');
    if (!button) return;
    state.status = button.dataset.status;
    renderFeatures();
  });
  directory.addEventListener('click', event => {
    const button = event.target.closest('[data-feature-id]');
    if (button) selectFeature(button.dataset.featureId);
  });
  detail.addEventListener('click', event => {
    const related = event.target.closest('[data-related-feature]');
    if (related) selectFeature(related.dataset.relatedFeature, true);
    if (event.target.closest('[data-reset-search]')) {
      state.status = 'all'; state.query = ''; state.selected = data.features[0].id;
      search.value = ''; renderFeatures(); search.focus();
    }
  });

  function renderShip() {
    const ship = data.ships.find(item => item.id === state.ship);
    document.querySelectorAll('[data-ship-id]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.shipId === ship.id));
    });
    const target = document.querySelector('#ship-detail');
    const title = element('div', 'ship-name-row');
    title.append(element('h3', 'ship-name', ship.name), badge(ship.status));
    const specs = element('dl', 'ship-spec');
    [['长处', ship.strength], ['制约', ship.weakness], ['打法', ship.tactic]].forEach(([name, value]) => {
      specs.append(element('dt', '', name), element('dd', '', value));
    });
    target.replaceChildren(title, element('p', 'ship-role', ship.role), specs);
    if (ship.crew || ship.counterplay) {
      const more = element('details', 'ship-more');
      more.append(element('summary', '', '人员配置与反制'));
      const roles = element('dl', 'ship-spec');
      if (ship.crew) roles.append(element('dt', '', '配员'), element('dd', '', ship.crew));
      if (ship.counterplay) roles.append(element('dt', '', '反制'), element('dd', '', ship.counterplay));
      more.append(roles); target.append(more);
    }
    if (ship.status === 'planned') {
      target.append(element('p', 'ship-planning-note', '本船型处于设计阶段。旁图为现有福船模型，用于展示当前制作质量；不是本船型外观。'));
    }
  }

  const shipTabs = document.querySelector('#ship-tabs');
  const shipCategorySelect = document.querySelector('#ship-category');
  const categories = ['all', ...new Set(data.ships.map(ship => ship.category || '其他'))];
  categories.forEach(category => {
    const count = category === 'all' ? data.ships.length : data.ships.filter(ship => (ship.category || '其他') === category).length;
    const option = element('option', '', `${category === 'all' ? '全部船型' : category}（${count}）`);
    option.value = category; shipCategorySelect.append(option);
  });
  function renderShipTabs() {
    const ships = data.ships.filter(ship => shipCategory === 'all' || (ship.category || '其他') === shipCategory);
    if (!ships.some(ship => ship.id === state.ship)) state.ship = ships[0].id;
    shipTabs.replaceChildren();
    ships.forEach(ship => {
      const button = element('button', '', ship.name);
      button.type = 'button'; button.dataset.shipId = ship.id;
      button.setAttribute('aria-controls', 'ship-detail');
      shipTabs.append(button);
    });
    document.querySelector('#ship-count').textContent = `收录 ${data.ships.length} 种职责原型 · 当前分类 ${ships.length} 种`;
    renderShip();
  }
  shipCategorySelect.addEventListener('change', () => { shipCategory = shipCategorySelect.value; renderShipTabs(); });
  shipTabs.addEventListener('click', event => {
    const button = event.target.closest('[data-ship-id]');
    if (!button) return;
    state.ship = button.dataset.shipId; renderShip();
  });

  data.chapters.forEach(chapter => {
    const item = element('li');
    item.append(element('p', 'chapter-year', chapter.year),
      element('h3', 'chapter-title', chapter.title),
      element('p', 'chapter-person', chapter.protagonist),
      element('p', 'chapter-description', chapter.description));
    const disclosure = element('details');
    disclosure.append(element('summary', '', '这一程的玩法'), element('p', '', chapter.mechanic));
    item.append(disclosure);
    document.querySelector('#chapter-list').append(item);
  });

  const allImageIds = Object.keys(data.media);
  const galleryIds = allImageIds.filter(key => data.media[key].gallery !== false)
    .sort((left, right) => (data.media[left].galleryOrder ?? 1000) - (data.media[right].galleryOrder ?? 1000));
  galleryIds.forEach(key => {
    const media = data.media[key];
    const figure = element('figure', 'gallery-item');
    const caption = element('figcaption', 'gallery-caption');
    const text = element('div');
    text.append(element('p', '', media.galleryTitle || media.caption.split('·')[0].trim()), element('small', '', media.caption));
    caption.append(text, element('span', '', kindNames[media.kind]));
    figure.append(imageButton(key), caption);
    document.querySelector('#gallery-grid').append(figure);
  });

  data.updates.forEach(update => {
    const entry = element('article', 'update-entry');
    const date = element('time', '', update.date.replaceAll('-', '.'));
    date.dateTime = update.date;
    const text = element('div');
    const title = element('div', 'update-title-row');
    title.append(element('h3', '', update.title), badge(update.status));
    text.append(title, element('p', '', update.description));
    entry.append(date, text);
    document.querySelector('#update-list').append(entry);
  });
  const date = document.querySelector('#updated-at');
  date.dateTime = data.updatedAt; date.textContent = data.updatedAt.replaceAll('-', '.');
  document.querySelector('#ways-title').textContent = data.intro.title;
  document.querySelector('#ways-description').textContent = data.intro.description;
  document.querySelector('#latest-update').textContent = data.updates[0].title + ' · ' + data.updates[0].description;

  const viewer = document.querySelector('#image-viewer');
  let viewerIds = galleryIds;
  let viewerKey = galleryIds[0] || allImageIds[0];
  let returnFocus = null;

  function showViewerImage(key) {
    viewerKey = key;
    const media = data.media[key];
    const image = document.querySelector('#viewer-image');
    image.src = media.src; image.alt = media.alt;
    image.width = media.width; image.height = media.height;
    document.querySelector('#viewer-caption').textContent = media.caption;
    document.querySelector('#viewer-kind').textContent = kindNames[media.kind];
    const index = viewerIds.indexOf(key);
    document.querySelector('#viewer-position').textContent = `${index + 1} / ${viewerIds.length}`;
  }

  function changeViewer(delta) {
    const index = viewerIds.indexOf(viewerKey);
    showViewerImage(viewerIds[(index + delta + viewerIds.length) % viewerIds.length]);
  }

  document.addEventListener('click', event => {
    const button = event.target.closest('[data-open-image]');
    if (!button) return;
    returnFocus = button;
    viewerIds = galleryIds.includes(button.dataset.openImage) ? galleryIds : allImageIds;
    showViewerImage(button.dataset.openImage);
    if (!viewer.open) viewer.showModal();
    document.body.classList.add('viewer-open');
    document.querySelector('#viewer-close').focus();
  });
  document.querySelector('#viewer-close').addEventListener('click', () => viewer.close());
  document.querySelector('#viewer-prev').addEventListener('click', () => changeViewer(-1));
  document.querySelector('#viewer-next').addEventListener('click', () => changeViewer(1));
  viewer.addEventListener('keydown', event => {
    if (event.key === 'ArrowLeft') { event.preventDefault(); changeViewer(-1); }
    if (event.key === 'ArrowRight') { event.preventDefault(); changeViewer(1); }
  });
  viewer.addEventListener('click', event => {
    const bounds = viewer.getBoundingClientRect();
    if (event.target === viewer && (event.clientX < bounds.left || event.clientX > bounds.right ||
      event.clientY < bounds.top || event.clientY > bounds.bottom)) viewer.close();
  });
  viewer.addEventListener('close', () => {
    document.body.classList.remove('viewer-open');
    if (returnFocus?.isConnected) returnFocus.focus({ preventScroll: true });
  });

  const menuButton = document.querySelector('.menu-toggle');
  const nav = document.querySelector('#main-nav');
  function closeMenu(restoreFocus = false) {
    menuButton.setAttribute('aria-expanded', 'false');
    menuButton.firstChild.nodeValue = '展开目录 ';
    menuButton.querySelector('span').textContent = '＋';
    nav.classList.remove('is-open');
    if (restoreFocus) menuButton.focus();
  }
  menuButton.addEventListener('click', () => {
    if (menuButton.getAttribute('aria-expanded') === 'true') return closeMenu();
    menuButton.setAttribute('aria-expanded', 'true');
    menuButton.firstChild.nodeValue = '收起目录 ';
    menuButton.querySelector('span').textContent = '−';
    nav.classList.add('is-open');
  });
  nav.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
  document.addEventListener('click', event => {
    if (!event.target.closest('.site-header')) closeMenu();
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && !viewer.open && menuButton.getAttribute('aria-expanded') === 'true') closeMenu(true);
  });
  window.addEventListener('resize', () => { if (window.innerWidth > 800) closeMenu(); });

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(entries => {
      const active = entries.find(entry => entry.isIntersecting);
      if (!active) return;
      const targetId = active.target.id === 'story' ? 'prologue' : active.target.id;
      nav.querySelectorAll('a').forEach(link => {
        if (link.hash === '#' + targetId) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
    }, { rootMargin: '-15% 0px -65% 0px', threshold: 0 });
    document.querySelectorAll('#prologue, #ways, #ships, #story, #gallery, #journal').forEach(section => observer.observe(section));
  }

  renderFeatures();
  renderShipTabs();
})();
