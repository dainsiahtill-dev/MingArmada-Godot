(() => {
  "use strict";

  const ROOT = "../../../";
  const PHASE_NAMES = { P0: "P0 · 优先制作", P1: "P1 · 内容补全", P2: "P2 · 后续候选" };
  const EVIDENCE_NAMES = {
    "dedicated-concept": "独立概念图",
    "dedicated-original": "专用原图",
    "context-reference": "情境参考",
    "technical-sketch": "技术草图"
  };
  const ROLE_NAMES = {
    portrait: "独立肖像", "portrait-atlas-crop": "图集独立肖像", "scene-context": "剧情上下文",
    "scene-character-reference": "场景人物参考", "style-reference": "造型参考", "ui-context": "UI上下文",
    "dedicated-concept": "独立概念图", "dedicated-original": "专用原图", "technical-sketch": "技术草图",
    concept: "概念图", original: "原图", reference: "参考图", sketch: "草图"
  };
  const CHINESE_NUMBERS = ["零", "一", "二", "三", "四", "五", "六"];
  const text = (value) => value == null ? "" : typeof value === "object" ? JSON.stringify(value) : String(value);
  const escape = (value) => text(value).replace(/[&<>"']/g, (char) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[char]));
  const list = (value) => Array.isArray(value) ? value : value == null || value === "" ? [] : [value];
  const normalize = (value) => text(value).normalize("NFKC").toLocaleLowerCase("zh-CN").replace(/\s+/g, " ").trim();

  function repoUrl(path) {
    const clean = text(path).trim().replace(/\\/g, "/");
    if (!clean || clean.startsWith("/") || /[\u0000-\u001f:?#]/.test(clean)) return "";
    const segments = clean.split("/");
    if (segments.some((segment) => segment === ".." || segment === ".")) return "";
    return ROOT + segments.map(encodeURIComponent).join("/");
  }
  function sceneInfo(ref) {
    const id = text(ref);
    const match = /^(?:zheng|yiguan)_a(\d+)_s(\d+)$/.exec(id);
    return match ? { id, act: Number(match[1]), scene: Number(match[2]), label: "第" + (CHINESE_NUMBERS[Number(match[1])] || match[1]) + "幕 · 第" + match[2] + "场" } : { id, label: id };
  }
  function sceneKeywords(ref) {
    const info = sceneInfo(ref);
    return info.act ? info.label + " 第" + info.act + "幕 " + info.act + "幕 a" + info.act + " s" + info.scene + " a" + info.act + "s" + info.scene + " " + info.act + "-" + info.scene : info.label;
  }
  function cropValues(image) {
    const crop = image && image.cropNormalized;
    if (!crop) return null;
    const values = Array.isArray(crop) ? crop : [crop.x, crop.y, crop.width ?? crop.w, crop.height ?? crop.h];
    const [x, y, width, height] = values.map(Number);
    return [x, y, width, height].every(Number.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.000001 && y + height <= 1.000001 ? { x, y, width, height } : null;
  }
  function imageMarkup(image, name, eager = false) {
    const url = image && repoUrl(image.path);
    if (!url) return '<div class="asset-media is-missing"><span class="media-fallback">图像待补</span></div>';
    const attributes = ' alt="' + escape(name) + '" loading="' + (eager ? "eager" : "lazy") + '" decoding="async"' + (eager ? ' fetchpriority="high"' : "");
    const crop = cropValues(image);
    const content = crop
      ? '<div class="crop-frame"><img src="' + escape(url) + '"' + attributes + ' style="width:' + 100 / crop.width + '%;height:' + 100 / crop.height + '%;left:' + -100 * crop.x / crop.width + '%;top:' + -100 * crop.y / crop.height + '%"></div>'
      : '<img src="' + escape(url) + '"' + attributes + '>';
    return '<div class="asset-media">' + content + '<span class="media-fallback">图片暂未显示，可在下方打开原图。</span></div>';
  }
  function evidenceName(item) { return EVIDENCE_NAMES[item.evidenceStatus] || "参考状态待核"; }
  function isDedicated(item) { return item.evidenceStatus === "dedicated-concept" || item.evidenceStatus === "dedicated-original"; }
  function imageRole(image) { return ROLE_NAMES[image && image.role] || text(image && image.role) || "参考图"; }
  function itemImage(item) { return item.primaryImage || list(item.images).find((image) => repoUrl(image.path)) || null; }

  const source = window.MING_RESOURCE_LIBRARY;
  const resultsNode = document.getElementById("resource-results");
  if (!source || !Array.isArray(source.items)) {
    document.getElementById("collection-summary").textContent = "资源目录暂未载入";
    resultsNode.className = "";
    resultsNode.innerHTML = '<div class="load-error"><h2>资源数据未载入</h2><p>请确认本目录中的data.js已生成，再重新打开图鉴。原始分类清单可在 <a href="parts/">parts目录</a> 查阅。</p><button class="button" type="button" id="reload-library">重新读取</button></div>';
    resultsNode.addEventListener("click", (event) => { if (event.target.closest("#reload-library")) window.location.reload(); });
    return;
  }

  const items = source.items.filter((item) => item && text(item.id) && text(item.name));
  const byId = new Map(items.map((item) => [text(item.id), item]));
  const categoryNames = new Map(list(source.summary && source.summary.categories).map((category) => [text(category.id), text(category.name)]));
  for (const item of items) if (!categoryNames.has(text(item.category))) categoryNames.set(text(item.category), text(item.categoryName || item.category));
  const categories = Array.from(categoryNames, ([id, name]) => ({ id, name }));
  const state = { query: "", category: "all", phase: "all", evidence: "all", view: "grid", selected: "" };
  const elements = Object.fromEntries(["resource-search", "phase-filter", "evidence-filter", "category-list", "category-total", "result-count", "results-heading", "detail-panel", "grid-view", "table-view", "reset-filters", "collection-summary", "generated-at", "filters"].map((id) => [id, document.getElementById(id)]));
  const searchIndex = new Map(items.map((item) => [text(item.id), normalize([
    item.id, item.name, item.categoryName, categoryNames.get(text(item.category)), item.description, item.visualBrief,
    item.modelStrategy, item.historicalStatus, item.phase, item.appearance, evidenceName(item),
    ...list(item.aliases), ...list(item.variants), ...list(item.uiPages), ...list(item.legacyModelIds),
    ...list(item.storyRefs).map(sceneKeywords), ...list(item.storyRefs), ...list(item.storyLinks).flatMap((link) => [link.id, link.title, link.legacyTitle])
  ].map(text).join(" "))]));

  function matches(item, excluding = "") {
    if (excluding !== "category" && state.category !== "all" && text(item.category) !== state.category) return false;
    if (excluding !== "phase" && state.phase !== "all" && text(item.phase) !== state.phase) return false;
    if (excluding !== "evidence" && state.evidence !== "all" && text(item.evidenceStatus) !== state.evidence) return false;
    const corpus = searchIndex.get(text(item.id)) || "";
    return normalize(state.query).split(" ").filter(Boolean).every((token) => corpus.includes(token));
  }
  function facetCounts(dimension) {
    const counts = new Map();
    let total = 0;
    for (const item of items) if (matches(item, dimension)) {
      const value = text(dimension === "evidence" ? item.evidenceStatus : item[dimension]);
      counts.set(value, (counts.get(value) || 0) + 1);
      total += 1;
    }
    return { counts, total };
  }
  function renderFacets() {
    const categoryFacet = facetCounts("category");
    elements["category-list"].innerHTML = [{ id: "all", name: "全部资源" }, ...categories].map((category) => {
      const count = category.id === "all" ? categoryFacet.total : categoryFacet.counts.get(category.id) || 0;
      return '<button type="button" class="category-button' + (count ? "" : " is-empty") + '" data-category="' + escape(category.id) + '" aria-pressed="' + (state.category === category.id) + '" aria-label="' + escape(category.name) + '，' + count + '项"><span>' + escape(category.name) + '</span><span class="count" aria-hidden="true">' + count + "</span></button>";
    }).join("");
    elements["category-total"].textContent = items.length + "项";
    const phaseFacet = facetCounts("phase");
    const phases = Array.from(new Set(["P0", "P1", "P2", ...items.map((item) => text(item.phase)).filter(Boolean)]));
    elements["phase-filter"].innerHTML = '<option value="all">全部优先级（' + phaseFacet.total + "）</option>" + phases.map((phase) => '<option value="' + escape(phase) + '">' + escape(PHASE_NAMES[phase] || phase) + "（" + (phaseFacet.counts.get(phase) || 0) + "）</option>").join("");
    elements["phase-filter"].value = state.phase;
    const evidenceFacet = facetCounts("evidence");
    const evidenceValues = Array.from(new Set([...Object.keys(EVIDENCE_NAMES), ...items.map((item) => text(item.evidenceStatus)).filter(Boolean)]));
    elements["evidence-filter"].innerHTML = '<option value="all">全部图像状态（' + evidenceFacet.total + "）</option>" + evidenceValues.map((evidence) => '<option value="' + escape(evidence) + '">' + escape(EVIDENCE_NAMES[evidence] || "待核图像") + "（" + (evidenceFacet.counts.get(evidence) || 0) + "）</option>").join("");
    elements["evidence-filter"].value = state.evidence;
    elements["reset-filters"].disabled = !state.query && state.category === "all" && state.phase === "all" && state.evidence === "all";
  }
  function resourceCard(item) {
    return '<article class="resource-card' + (state.selected === text(item.id) ? " is-selected" : "") + '"><a class="resource-open" data-select="' + escape(item.id) + '" href="#' + escape(encodeURIComponent(text(item.id))) + '"' + (state.selected === text(item.id) ? ' aria-current="true"' : "") + '>' + imageMarkup(itemImage(item), item.name) + '<div class="asset-caption"><span>' + escape(categoryNames.get(text(item.category)) || item.category) + '</span><span aria-hidden="true">·</span><span class="phase-label">' + escape(item.phase) + "</span></div><h3>" + escape(item.name) + "</h3><code>" + escape(item.id) + '</code><span class="evidence-label' + (isDedicated(item) ? " is-dedicated" : "") + '">' + escape(evidenceName(item)) + (item.appearance === "mentioned-only" ? " · 仅提及" : "") + "</span></a></article>";
  }
  function resourceTable(filtered) {
    return '<div class="results-table-wrap"><table class="resource-table"><caption class="sr-only">筛选后的制作资源。点资源名称查看详情。</caption><thead><tr><th scope="col">资源名称 / ID</th><th scope="col">类别</th><th scope="col">优先级</th><th scope="col">图像状态</th></tr></thead><tbody>' + filtered.map((item) => '<tr class="' + (state.selected === text(item.id) ? "is-selected" : "") + '"><td class="name-cell"><a href="#' + escape(encodeURIComponent(text(item.id))) + '" data-select="' + escape(item.id) + '"' + (state.selected === text(item.id) ? ' aria-current="true"' : "") + ">" + escape(item.name) + "</a><code>" + escape(item.id) + "</code></td><td>" + escape(categoryNames.get(text(item.category)) || item.category) + "</td><td>" + escape(item.phase) + '</td><td class="status-cell">' + escape(evidenceName(item)) + "</td></tr>").join("") + "</tbody></table></div>";
  }
  function section(title, value) {
    if (!value) return "";
    return '<section class="detail-section"><h3>' + escape(title) + "</h3><p>" + escape(value) + "</p></section>";
  }
  function renderDetail() {
    const item = byId.get(state.selected);
    const panel = elements["detail-panel"];
    if (!item) {
      panel.innerHTML = '<div class="detail-empty"><h2>选择一项资源</h2><p>从结果中选择资源，查看造型、原图和生产说明。</p></div>';
      return;
    }
    const image = itemImage(item);
    const primaryUrl = image && repoUrl(image.path);
    const directory = repoUrl(item.assetDirectory);
    const images = list(item.images).filter((candidate) => candidate && repoUrl(candidate.path));
    let modelBoundary = "";
    if (item.modelRequired === false) {
      if (item.category === "named-character" && item.appearance === "mentioned-only") {
        modelBoundary = "当前不要求身体模型，仅保留信息图像候选。";
      } else if (item.category !== "named-character" && item.category !== "npc-archetype") {
        const assetType = {
          "prefab-assembly": "场景装配",
          "background-landmark": "背景地标装配",
          "ui-map": "地图图层",
          "scene-mother": "场景母版装配",
          "scene-variant-pack": "场景变体装配",
          "procedural-terrain": "程序地形条件",
          "environment-profile": "环境条件",
          "material-set": "材质条件"
        }[item.assetKind];
        if (assetType) modelBoundary = assetType + "，不另增独立基模。";
      }
    }
    const variants = list(item.variants);
    const dependencies = list(item.dependencies);
    const legacy = list(item.legacyModelIds);
    const scenes = list(item.storyLinks).length ? list(item.storyLinks).map((link) => ({id:link.id,label:link.legacyId ? "旧稿“" + text(link.legacyTitle) + "” → 新稿结构承接“" + text(link.title) + "”" : text(link.title)})) : list(item.storyRefs).map(sceneInfo);
    const pages = list(item.uiPages);
    const resources = images.filter((candidate) => !image || candidate.path !== image.path || JSON.stringify(candidate.cropNormalized) !== JSON.stringify(image.cropNormalized));
    const history = text(item.historicalStatus);
    panel.innerHTML = '<header class="detail-heading"><p class="detail-meta"><span>' + escape(categoryNames.get(text(item.category)) || item.category) + "</span><span>" + escape(PHASE_NAMES[item.phase] || item.phase) + '</span></p><h2 id="detail-heading" tabindex="-1">' + escape(item.name) + "</h2><code>" + escape(item.id) + "</code>" + (!matches(item) ? '<p class="detail-outside">此条目不在当前筛选结果中，仍可继续查阅。</p>' : "") + "</header>" +
      (image ? '<figure class="detail-image">' + imageMarkup(image, item.name, true) + '<figcaption><strong>' + escape([...new Set([evidenceName(item), imageRole(image)])].join(" · ")) + "</strong>" + (image.note ? "<br>" + escape(image.note) : "") + (primaryUrl ? '<br><a href="' + escape(primaryUrl) + '" target="_blank" rel="noopener">打开完整原图 ↗</a>' : "") + "</figcaption></figure>" : "") +
      '<div class="detail-content"><p class="detail-description">' + escape(item.description || "此资源的说明待补。") + '</p><div class="detail-actions">' + (directory ? '<a class="button" href="' + escape(directory) + '" target="_blank" rel="noopener">打开资源目录 ↗</a>' : "") + '<button class="button" type="button" data-back-results>返回资源结果</button></div>' + (directory ? '<a class="path-link" href="' + escape(directory) + '" target="_blank" rel="noopener">' + escape(item.assetDirectory) + "</a>" : "") +
      section("造型与建模简报", item.visualBrief) + section("模型策略", [text(item.modelStrategy), modelBoundary].filter(Boolean).join(" ")) +
      (variants.length ? '<section class="detail-section"><h3>同一资源的变体</h3><ul>' + variants.map((variant) => "<li>" + escape(variant) + "</li>").join("") + "</ul></section>" : "") +
      section("历史与创作边界", history) +
      (scenes.length ? '<section class="detail-section"><h3>' + (item.narrativeStatus === "legacy-requirement-needs-mainline-audit" ? "旧稿需求出处与新稿承接" : "关联剧本") + '</h3>' + (item.narrativeScope ? '<p class="subtle">' + escape(item.narrativeScope) + '</p>' : '') + '<div class="link-list">' + scenes.map((scene) => '<a href="' + ROOT + 'docs/narrative/zheng-zhilong/#' + escape(encodeURIComponent(scene.id)) + '" title="' + escape(scene.id) + '" target="_blank" rel="noopener">' + escape(scene.label) + "</a>").join("") + "</div></section>" : "") +
      (pages.length ? '<section class="detail-section"><h3>关联游戏界面</h3><div class="link-list">' + pages.map((page) => '<a href="' + ROOT + 'docs/design/game-ui/prototype/#' + escape(encodeURIComponent(text(page))) + '" target="_blank" rel="noopener">' + escape(page) + "</a>").join("") + "</div></section>" : "") +
      (legacy.length ? '<section class="detail-section"><h3>旧生产预算对应</h3><div class="detail-tags">' + legacy.map((id) => "<span>" + escape(id) + "</span>").join("") + '</div><p class="subtle">这些是旧预算中的基模ID；引用不代表模型已完成或当前运行时已接入。</p></section>' : "") +
      (dependencies.length ? '<section class="detail-section"><h3>制作依赖</h3><ul>' + dependencies.map((dependency) => {
        const id = typeof dependency === "object" ? text(dependency.id || dependency.name) : text(dependency);
        return "<li>" + (byId.has(id) ? '<a data-select="' + escape(id) + '" href="#' + escape(encodeURIComponent(id)) + '">' + escape(byId.get(id).name) + "</a>" : escape(dependency)) + "</li>";
      }).join("") + "</ul></section>" : "") +
      (resources.length ? '<section class="detail-section"><h3>其他原图与参考</h3><ul class="reference-list">' + resources.map((candidate) => '<li><a href="' + escape(repoUrl(candidate.path)) + '" target="_blank" rel="noopener">' + escape(imageRole(candidate)) + " ↗<br><code>" + escape(candidate.path) + "</code></a>" + (candidate.note ? "<small>" + escape(candidate.note) + "</small>" : "") + "</li>").join("") + "</ul></section>" : "") + "</div>";
  }
  function render() {
    renderFacets();
    const filtered = items.filter((item) => matches(item));
    elements["results-heading"].textContent = state.category === "all" ? "全部资源" : categoryNames.get(state.category) || state.category;
    elements["result-count"].textContent = "显示 " + filtered.length + " / " + items.length + " 项" + (state.query ? " · 搜索「" + state.query + "」" : "") + (state.phase !== "all" ? " · " + state.phase : "") + (state.evidence !== "all" ? " · " + (EVIDENCE_NAMES[state.evidence] || state.evidence) : "");
    elements["grid-view"].setAttribute("aria-pressed", String(state.view === "grid"));
    elements["table-view"].setAttribute("aria-pressed", String(state.view === "table"));
    resultsNode.className = state.view === "grid" ? "resource-grid" : "";
    resultsNode.innerHTML = !filtered.length ? '<div class="no-results"><h3>没有符合条件的资源</h3><p>试试更短的名称、资源ID或章节；也可以重置全部筛选，重新浏览目录。</p><button class="button" type="button" data-reset>重置全部筛选</button></div>' : state.view === "table" ? resourceTable(filtered) : filtered.map(resourceCard).join("");
    renderDetail();
  }
  function resetFilters() {
    state.query = ""; state.category = "all"; state.phase = "all"; state.evidence = "all";
    elements["resource-search"].value = "";
    render();
  }
  function hashId() {
    try { return decodeURIComponent(window.location.hash.replace(/^#/, "")); } catch { return ""; }
  }
  function selectItem(id, focus = true) {
    if (!byId.has(id)) return;
    state.selected = id;
    const nextHash = "#" + encodeURIComponent(id);
    if (window.location.hash !== nextHash) window.history.pushState(null, "", nextHash);
    render();
    if (focus && window.matchMedia("(max-width: 1000px)").matches) {
      elements["detail-panel"].scrollIntoView({ block: "start" });
      const heading = document.getElementById("detail-heading");
      if (heading) heading.focus({ preventScroll: true });
    }
  }
  elements["filters"].addEventListener("submit", (event) => event.preventDefault());
  elements["filters"].addEventListener("reset", (event) => { event.preventDefault(); resetFilters(); elements["resource-search"].focus(); });
  elements["resource-search"].addEventListener("input", (event) => { state.query = event.target.value; render(); });
  elements["phase-filter"].addEventListener("change", (event) => { state.phase = event.target.value; render(); });
  elements["evidence-filter"].addEventListener("change", (event) => { state.evidence = event.target.value; render(); });
  elements["category-list"].addEventListener("click", (event) => {
    const button = event.target.closest("[data-category]");
    if (!button) return;
    state.category = button.dataset.category;
    render();
    const current = Array.from(elements["category-list"].querySelectorAll("[data-category]")).find((candidate) => candidate.dataset.category === state.category);
    if (current) current.focus({ preventScroll: true });
  });
  elements["grid-view"].addEventListener("click", () => { state.view = "grid"; render(); });
  elements["table-view"].addEventListener("click", () => { state.view = "table"; render(); });
  document.addEventListener("click", (event) => {
    const select = event.target.closest("[data-select]");
    if (select) { event.preventDefault(); selectItem(select.dataset.select); return; }
    if (event.target.closest("[data-reset]")) { resetFilters(); elements["resource-search"].focus(); return; }
    if (event.target.closest("[data-back-results]")) {
      elements["results-heading"].scrollIntoView({ block: "start" });
      const selected = Array.from(resultsNode.querySelectorAll("[data-select]")).find((candidate) => candidate.dataset.select === state.selected);
      (selected || elements["results-heading"]).focus({ preventScroll: true });
    }
  });
  document.addEventListener("error", (event) => {
    if (event.target.tagName === "IMG") {
      const media = event.target.closest(".asset-media");
      if (media) media.classList.add("is-missing");
    }
  }, true);
  const restoreHash = () => {
    const id = hashId();
    state.selected = byId.has(id) ? id : items.length ? text(items[0].id) : "";
    render();
    if (byId.has(id) && window.matchMedia("(max-width: 1000px)").matches) {
      elements["detail-panel"].scrollIntoView({ block: "start" });
      const heading = document.getElementById("detail-heading");
      if (heading) heading.focus({ preventScroll: true });
    }
  };
  window.addEventListener("hashchange", restoreHash);
  window.addEventListener("popstate", restoreHash);
  elements["collection-summary"].innerHTML = '<strong>' + items.length + "项资源</strong> · " + categories.length + "类 · UI / 场景 / 建模共用目录";
  const narrativeScope = document.getElementById("narrative-scope");
  if (narrativeScope) { narrativeScope.textContent = text(source.narrativeScope); narrativeScope.hidden = !source.narrativeScope; }
  if (source.generatedAt) {
    const date = new Date(source.generatedAt);
    elements["generated-at"].textContent = "目录生成于 " + (Number.isNaN(date.getTime()) ? text(source.generatedAt) : date.toLocaleDateString("zh-CN"));
  }
  restoreHash();
})();

