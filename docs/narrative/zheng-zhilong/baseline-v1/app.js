/* Buildless reader. Story data is loaded as a classic local script so file:// works. */
(() => {
  "use strict";
  const STORAGE_KEY = "mingarmada.zheng-reader.v1";
  const $ = (id) => document.getElementById(id);
  const text = (value, fallback = "") => typeof value === "string" ? value : typeof value === "number" ? String(value) : fallback;
  const array = (value) => Array.isArray(value) ? value : [];
  const object = (value) => value && typeof value === "object" && !Array.isArray(value) ? value : {};
  const chineseNumbers = ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"];
  const cleanId = (value, fallback) => text(value).trim().replace(/[^a-zA-Z0-9_\-\u3400-\u9fff]/g, "-") || fallback;
  const safeUrl = (value, image = false) => {
    const source = text(value).trim();
    if (!source || /[\u0000-\u001f]/.test(source)) return "";
    if (image) return /^(?:images\/)[a-zA-Z0-9_./-]+\.(?:png|jpe?g|webp|avif)$/i.test(source) && !source.includes("..") ? source : "";
    // Source JSON lives one folder above the reader. Permit only the project
    // research Markdown tree and normalize both source-relative and reader-relative URLs.
    const localResearch = source.match(/^(?:\.\.\/research\/|\.\.\/\.\.\/research\/)((?:[\p{L}\p{N}_-]+\/)*[\p{L}\p{N}_.-]+\.md)(#[\p{L}\p{N}_-]+)?$/u);
    if (localResearch) return `../../research/${localResearch[1]}${localResearch[2] || ""}`;
    try { const url = new URL(source); return /^https?:$/.test(url.protocol) ? url.href : ""; } catch { return ""; }
  };
  function normalize(raw) {
    const source = object(raw);
    const usedIds = new Set(["top", "story", "appendix"]);
    const uniqueId = (value, fallback) => {
      let id = cleanId(value, fallback), suffix = 2;
      while (usedIds.has(id)) id = `${cleanId(value, fallback)}-${suffix++}`;
      usedIds.add(id); return id;
    };
    const acts = array(source.acts).map((value, index) => {
      const act = object(value);
      const id = uniqueId(act.id, `act-${index + 1}`);
      return {
        id, title: text(act.title, `第${chineseNumbers[index] || index + 1}幕`), years: text(act.years),
        synopsis: text(act.synopsis), cover: safeUrl(act.cover, true), number: index + 1,
        scenes: array(act.scenes).map((value, sceneIndex) => {
          const scene = object(value), history = object(scene.history);
          return {
            id: uniqueId(scene.id, `${id}-scene-${sceneIndex + 1}`), title: text(scene.title, `第${chineseNumbers[sceneIndex] || sceneIndex + 1}场`),
            year: text(scene.year), location: text(scene.location), summary: text(scene.summary),
            paragraphs: array(scene.paragraphs).map((line) => text(line)).filter(Boolean),
            dialogue: array(scene.dialogue).map((line) => ({ speaker: text(object(line).speaker, "旁白"), text: text(object(line).text) })).filter((line) => line.text),
            choices: array(scene.choices).map((value, choiceIndex) => { const choice = object(value); return { id: cleanId(choice.id, `choice-${choiceIndex + 1}`), label: text(choice.label, `选择${choiceIndex + 1}`), consequence: text(choice.consequence, "此分支尚未提供后果说明。") }; }),
            history: { level: text(history.level), note: text(history.note), sources: array(history.sources).map((value) => { const source = object(value); return { title: text(source.title, "史料来源"), url: safeUrl(source.url) }; }) },
            image: safeUrl(scene.image, true), actId: id, actTitle: text(act.title), actNumber: index + 1, sceneNumber: sceneIndex + 1
          };
        })
      };
    });
    return { title: text(source.title, "郑芝龙：海上半生"), subtitle: text(source.subtitle, "一条船，一个家，人与时代之间的一片海。"), logline: text(source.logline), characters: source.characters, foreshadowing: source.foreshadowing || source.foreshadows || source.motifs, appendix: source.appendix, acts };
  }
  function element(tag, className, content) { const node = document.createElement(tag); if (className) node.className = className; if (content !== undefined) node.textContent = content; return node; }
  function add(parent, tag, className, content) { const node = element(tag, className, content); parent.append(node); return node; }
  function readStored() { try { return object(JSON.parse(localStorage.getItem(STORAGE_KEY) || "{}")); } catch { return {}; } }
  const stored = readStored();
  const model = normalize(window.ZHENG_STORY);
  const scenes = model.acts.flatMap((act) => act.scenes);
  const sceneMap = new Map(scenes.map((scene, index) => [scene.id, { scene, index }]));
  let currentIndex = -1, mode = stored.mode === "script" ? "script" : "story", storageUnavailable = false;
  let searchTimer, observer, beforePrint = [], lastDrawerTrigger;
  const searchEntries = scenes.map((scene) => ({ scene, body: [scene.title, scene.location, scene.summary, ...scene.paragraphs, ...scene.dialogue.map((line) => `${line.speaker} ${line.text}`), ...scene.choices.map((choice) => `${choice.label} ${choice.consequence}`), scene.history.note].join("\n") }));
  function savePosition() {
    try { localStorage.setItem(STORAGE_KEY, JSON.stringify({ sceneId: scenes[currentIndex]?.id || stored.sceneId || "", mode, savedAt: Date.now() })); }
    catch { storageUnavailable = true; }
  }
  function announce(message) { $("announcement").textContent = message; }
  function setMode(value, persist = true) {
    mode = value === "script" ? "script" : "story";
    document.body.dataset.readingMode = mode;
    document.querySelectorAll('input[name="reading-mode"]').forEach((input) => { input.checked = input.value === mode; });
    document.querySelectorAll(".script-details").forEach((details) => { details.open = mode === "script"; });
    $("mode-help").textContent = mode === "script" ? "剧本阅读完整展开对白与分支。点击每个分支，可查看相应后果。" : "故事阅读收起对白和分支，可逐段展开。剧本阅读完整展开。";
    if (persist) savePosition();
  }
  function createIllustration(path, caption, className, eager = false) {
    const figure = element("figure", className);
    if (!path) { figure.append(element("p", "art-unavailable", "本场插画尚未提供。")); return figure; }
    const button = add(figure, "button", "art-button"); button.type = "button"; button.setAttribute("aria-label", `放大${caption}插画`);
    const image = add(button, "img"); image.src = path; image.alt = `${caption}，叙事插画`; image.width = 1536; image.height = 1024;
    image.loading = eager ? "eager" : "lazy"; image.decoding = "async"; if (eager) image.fetchPriority = "high";
    image.addEventListener("error", () => {
      const note = element("p", "art-unavailable", "本幅插画暂时无法读取，请确认 images 文件夹与图卷一同保存。");
      button.replaceWith(note); figure.dataset.imageStatus = "unavailable";
    }, { once: true });
    button.addEventListener("click", () => openImage(path, caption));
    const label = add(figure, "figcaption", "art-caption"); add(label, "span", "", caption); add(label, "span", "", "生成插画");
    return figure;
  }
  function openImage(path, caption) {
    const dialog = $("image-dialog"); $("lightbox-image").src = path; $("lightbox-image").alt = `${caption}，叙事插画`;
    $("lightbox-caption").textContent = `${caption}。当代生成插画，用于场景想象。`;
    if (!dialog.open) dialog.showModal();
  }
  function historyLabel(level) {
    const labels = { fact: "史实骨架", documented: "史实骨架", historical: "史实背景", adaptation: "历史改编", legend: "地方传说", inference: "合理推演", inferred: "合理推演", reconstruction: "叙事重建", fiction: "虚构场景", fictional: "虚构场景", mixed: "史实与叙事重建" };
    return labels[level.toLowerCase()] || (/^[\u3400-\u9fff\s／、]+$/.test(level) ? level : "史料与叙事说明");
  }
  function renderScene(scene) {
    const article = element("article", "scene"); article.id = scene.id; article.dataset.scene = scene.id; article.setAttribute("aria-labelledby", `${scene.id}-title`);
    const header = add(article, "header", "scene-header"), meta = add(header, "p", "scene-meta");
    if (scene.year) add(meta, "span", "", scene.year);
    if (scene.location) add(meta, "span", "", scene.location);
    add(meta, "span", "", `第${chineseNumbers[scene.sceneNumber - 1] || scene.sceneNumber}场`);
    const title = add(header, "h3", "", scene.title); title.id = `${scene.id}-title`; title.tabIndex = -1;
    if (scene.summary) {
      const synopsis = add(header, "details", "script-details scene-synopsis");
      add(synopsis, "summary", "", "本场梗概"); add(synopsis, "p", "scene-summary", scene.summary);
    }
    article.append(createIllustration(scene.image, scene.title, "scene-illustration"));
    const prose = add(article, "div", "scene-prose prose");
    scene.paragraphs.forEach((paragraph) => add(prose, "p", "", paragraph));
    if (scene.dialogue.length) {
      const details = add(prose, "details", "script-details dialogue"); add(details, "summary", "", `对白 · ${scene.dialogue.length}段`);
      const lines = add(details, "dl", "dialogue-lines");
      scene.dialogue.forEach((line) => { const row = add(lines, "div", "dialogue-line"); add(row, "dt", "", line.speaker); add(row, "dd", "", line.text); });
    }
    if (scene.choices.length) {
      const details = add(prose, "details", "script-details choices"); add(details, "summary", "", `分支选择 · ${scene.choices.length}种可能`);
      add(details, "p", "choice-intro", "以下为剧本中的分支与后果，供阅读和比较。展开分支不会改变历史叙事。 ");
      scene.choices.forEach((choice) => { const branch = add(details, "details", "choice"); branch.dataset.choice = choice.id; add(branch, "summary", "", choice.label); add(branch, "p", "", choice.consequence); });
    }
    if (scene.history.note || scene.history.sources.length || scene.history.level) {
      const details = add(prose, "details", "history-note");
      const summary = add(details, "summary", "", "史实与叙事说明"); add(summary, "span", "history-level", historyLabel(scene.history.level));
      const content = add(details, "div", "history-content");
      if (scene.history.note) add(content, "p", "", scene.history.note);
      if (scene.history.sources.length) {
        const list = add(content, "ul"); scene.history.sources.forEach((source) => {
          const li = add(list, "li"); if (source.url) { const anchor = add(li, "a", "", source.title); anchor.href = source.url; anchor.target = "_blank"; anchor.rel = "noopener noreferrer"; } else li.textContent = source.title;
        });
      }
    }
    add(article, "div", "scene-end", "海").setAttribute("aria-hidden", "true"); return article;
  }
  function renderContents() {
    const contents = $("contents-list");
    model.acts.forEach((act) => {
      const group = add(contents, "div", "contents-act");
      const heading = add(group, "a", "contents-act-heading"); heading.href = `#${act.id}`; add(heading, "span", "", act.title); add(heading, "small", "", act.years);
      const list = add(group, "ol"); act.scenes.forEach((scene) => { const anchor = add(add(list, "li"), "a", "", scene.title); anchor.href = `#${scene.id}`; anchor.dataset.contentsScene = scene.id; });
    });
    if (!$("appendix").hidden) { const link = add(contents, "a", "contents-act-heading", "人物与伏笔"); link.href = "#appendix"; }
  }
  function displayValue(value, depth = 0) {
    if (depth > 3) return "";
    if (typeof value === "string" || typeof value === "number") return String(value);
    if (Array.isArray(value)) return value.map((entry) => displayValue(entry, depth + 1)).filter(Boolean).join("；");
    return Object.entries(object(value)).filter(([key]) => !/^(id|image|imagePrompt|url|sources)$/i.test(key)).map(([key, entry]) => {
      const labels = { role: "身份", description: "人物小传", note: "说明", arc: "人物走向", relationship: "关系", payoff: "回收", setup: "铺垫", historical: "史实身份", status: "身份性质", firstAppearance: "初次出现", resolution: "回应", scenes: "相关场次", historyLevel: "史实层级" };
      const content = displayValue(entry, depth + 1); return content ? `${labels[key] ? labels[key] + "：" : ""}${content}` : "";
    }).filter(Boolean).join("\n");
  }
  function renderAppendix() {
    const root = $("appendix"), groups = [];
    const characterEntries = Array.isArray(model.characters) ? model.characters : Object.entries(object(model.characters)).map(([name, value]) => typeof value === "string" ? { name, description: value } : { name, ...object(value) });
    if (characterEntries.length) groups.push(["同行与相逢的人", characterEntries]);
    const foreshadowEntries = Array.isArray(model.foreshadowing) ? model.foreshadowing : Object.entries(object(model.foreshadowing)).map(([title, value]) => ({ title, description: displayValue(value) }));
    if (foreshadowEntries.length) groups.push(["贯穿全卷的伏笔", foreshadowEntries]);
    const extra = object(model.appendix); Object.entries(extra).forEach(([key, value]) => { if (Array.isArray(value) && value.length) groups.push([{ characters: "人物小传", foreshadowing: "伏笔与回应", notes: "补记" }[key] || key, value]); });
    if (!groups.length) return;
    root.hidden = false; add(root, "p", "overline", "卷后"); add(root, "h2", "", "人物与伏笔");
    groups.forEach(([title, entries]) => {
      const group = add(root, "div", "appendix-group"); add(group, "h3", "", title);
      entries.forEach((value, index) => { const entry = typeof value === "string" ? { description: value } : object(value); const row = add(group, "div", "appendix-entry"); add(row, "h4", "", text(entry.name || entry.title || entry.label, `补记${index + 1}`)); const copy = { ...entry }; delete copy.name; delete copy.title; delete copy.label; add(row, "p", "", displayValue(copy)); });
    });
  }
  function render() {
    document.title = `${model.title} | 郑芝龙图卷`; $("book-title").textContent = model.title; $("book-subtitle").textContent = model.subtitle; $("book-logline").textContent = model.logline;
    if (!model.logline) $("book-logline").hidden = true;
    const count = scenes.reduce((total, scene) => total + scene.paragraphs.join("").length + scene.dialogue.reduce((sum, line) => sum + line.text.length, 0), 0);
    $("book-count").textContent = `${model.acts.length}幕　${scenes.length}场　约${count >= 10000 ? (count / 10000).toFixed(1) + "万" : count.toLocaleString("zh-CN")}字`;
    const heroArt = createIllustration(model.acts[0]?.cover || "", model.acts[0]?.title || model.title, "", true);
    $("cover-figure").replaceChildren(...heroArt.childNodes);
    if (!model.acts.length || !scenes.length) {
      $("data-status").textContent = "剧本数据尚未载入。请将 story-data.js 与 index.html 放在同一目录，确认文件中设置了 window.ZHENG_STORY 后重新打开。";
      $("start-reading").hidden = true; $("previous-scene").disabled = true; $("next-scene").disabled = true; return;
    }
    $("data-status").remove();
    const fragment = document.createDocumentFragment();
    model.acts.forEach((act) => {
      const section = element("section", "act"); section.id = act.id; section.setAttribute("aria-labelledby", `${act.id}-title`);
      const opening = add(section, "header", "act-opening"), heading = add(opening, "div", "act-heading"), aside = add(heading, "div");
      add(aside, "p", "act-number", `第${chineseNumbers[act.number - 1] || act.number}幕`); add(aside, "p", "act-years", act.years);
      const copy = add(heading, "div"), title = add(copy, "h2", "", act.title); title.id = `${act.id}-title`; title.tabIndex = -1;
      if (act.synopsis) add(copy, "p", "act-synopsis", act.synopsis);
      opening.append(createIllustration(act.cover, act.title, "act-image")); act.scenes.forEach((scene) => section.append(renderScene(scene))); fragment.append(section);
    });
    $("story").append(fragment); renderAppendix(); renderContents();
    $("start-reading").href = `#${model.acts[0].id}`;
    const savedScene = sceneMap.get(stored.sceneId);
    if (savedScene) { $("continue-reading").hidden = false; $("continue-reading").href = `#${savedScene.scene.id}`; $("continue-reading").textContent = `继续：${savedScene.scene.title}`; }
    setMode(mode, false); updateCurrent(-1, false);
  }
  function updateCurrent(index, persist = true) {
    if (index < -1 || index >= scenes.length) return;
    currentIndex = index; const scene = scenes[index]; const progress = index < 0 ? 0 : Math.round((index + 1) / scenes.length * 100);
    $("current-act").textContent = scene ? `第${chineseNumbers[scene.actNumber - 1] || scene.actNumber}幕 · ${scene.actTitle}` : "卷首";
    $("current-scene").textContent = scene?.title || "展开图卷"; $("progress-label").textContent = `${progress}%`; $("progress-fill").style.transform = `scaleX(${progress / 100})`;
    $("previous-scene").disabled = index <= 0; $("next-scene").disabled = !scenes.length || index >= scenes.length - 1;
    document.querySelectorAll("[data-contents-scene]").forEach((link) => { if (link.dataset.contentsScene === scene?.id) link.setAttribute("aria-current", "location"); else link.removeAttribute("aria-current"); });
    if (persist && scene) savePosition();
  }
  function navigate(id, focus = true) {
    const destination = document.getElementById(id); if (!destination) return false;
    if (sceneMap.has(id)) updateCurrent(sceneMap.get(id).index);
    else { const act = model.acts.find((item) => item.id === id); if (act?.scenes[0]) updateCurrent(sceneMap.get(act.scenes[0].id).index); }
    destination.scrollIntoView({ behavior: "auto", block: "start" });
    try { history.replaceState(null, "", `#${encodeURIComponent(id)}`); } catch { location.hash = id; }
    if (focus) { const heading = destination.matches("h1,h2,h3") ? destination : destination.querySelector("h2,h3"); (heading || destination).focus({ preventScroll: true }); }
    return true;
  }
  function step(direction) { const index = Math.max(0, Math.min(scenes.length - 1, currentIndex + direction)); if (scenes[index]) navigate(scenes[index].id); }
  function openContents(search = false, trigger) {
    const dialog = $("contents-dialog"); lastDrawerTrigger = trigger || document.activeElement;
    if (!dialog.open) dialog.showModal();
    if (search) $("story-search").focus(); else $("contents-close").focus();
  }
  function closeContents() { $("contents-dialog").close(); if (lastDrawerTrigger instanceof HTMLElement) lastDrawerTrigger.focus(); }
  function search(query) {
    const terms = query.trim().toLocaleLowerCase().split(/\s+/).filter(Boolean);
    return !terms.length ? [] : searchEntries.filter((entry) => terms.every((term) => entry.body.toLocaleLowerCase().includes(term)));
  }
  function highlighted(parent, value, query) {
    const lower = value.toLocaleLowerCase(), target = query.toLocaleLowerCase(), at = lower.indexOf(target);
    if (at < 0 || !target) { parent.textContent = value; return; }
    parent.append(document.createTextNode(value.slice(0, at)), element("mark", "", value.slice(at, at + query.length)), document.createTextNode(value.slice(at + query.length)));
  }
  function renderSearch() {
    const query = $("story-search").value.trim(), container = $("search-results"); container.replaceChildren();
    $("search-clear").hidden = !query; $("contents-list").hidden = !!query; container.hidden = !query;
    if (!query) { $("search-status").textContent = ""; return; }
    const results = search(query); $("search-status").textContent = results.length ? `找到${results.length}场相关剧情` : "未找到相关剧情。可试试人物姓名、地名或较短的词。";
    results.forEach(({ scene, body }) => {
      const link = add(container, "a", "search-result"); link.href = `#${scene.id}`;
      add(link, "small", "", `${scene.actTitle}　${scene.year}`); highlighted(add(link, "strong"), scene.title, query);
      const term = query.split(/\s+/)[0], at = body.toLocaleLowerCase().indexOf(term.toLocaleLowerCase()), begin = Math.max(0, at - 30), end = Math.min(body.length, begin + 110);
      highlighted(add(link, "p"), `${begin ? "…" : ""}${body.slice(begin, end).replace(/\n/g, " ")}${end < body.length ? "…" : ""}`, term);
    });
  }
  function watchPosition() {
    if (!scenes.length || !("IntersectionObserver" in window)) return;
    const visible = new Set();
    observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => { if (entry.isIntersecting) visible.add(entry.target.id); else visible.delete(entry.target.id); });
      const candidates = [...visible].map((id) => sceneMap.get(id)).filter(Boolean).sort((a, b) => a.index - b.index);
      if (candidates.length) updateCurrent(candidates[0].index);
    }, { rootMargin: "-18% 0px -64% 0px", threshold: 0 });
    scenes.forEach((scene) => observer.observe($(scene.id)));
    const topObserver = new IntersectionObserver((entries) => { if (entries[0].isIntersecting) updateCurrent(-1, false); }, { threshold: 0.25 });
    topObserver.observe(document.querySelector(".book-cover"));
  }
  function openForPrint() { beforePrint = [...document.querySelectorAll("details")].map((details) => [details, details.open]); beforePrint.forEach(([details]) => { details.open = true; }); }
  function restoreAfterPrint() { beforePrint.forEach(([details, open]) => { details.open = open; }); beforePrint = []; }
  function bind() {
    $("contents-open").addEventListener("click", (event) => openContents(false, event.currentTarget));
    $("search-open").addEventListener("click", (event) => openContents(true, event.currentTarget));
    $("contents-close").addEventListener("click", closeContents);
    $("contents-dialog").addEventListener("click", (event) => { if (event.target === event.currentTarget && event.clientX < event.currentTarget.getBoundingClientRect().left) closeContents(); });
    $("image-close").addEventListener("click", () => $("image-dialog").close());
    $("image-dialog").addEventListener("click", (event) => { if (event.target === event.currentTarget) event.currentTarget.close(); });
    $("image-dialog").addEventListener("close", () => { $("lightbox-image").removeAttribute("src"); });
    $("previous-scene").addEventListener("click", () => step(-1)); $("next-scene").addEventListener("click", () => step(1));
    $("search-form").addEventListener("submit", (event) => { event.preventDefault(); renderSearch(); });
    $("story-search").addEventListener("input", () => { clearTimeout(searchTimer); searchTimer = setTimeout(renderSearch, 100); });
    $("search-clear").addEventListener("click", () => { $("story-search").value = ""; renderSearch(); $("story-search").focus(); });
    document.querySelectorAll('input[name="reading-mode"]').forEach((input) => input.addEventListener("change", () => { setMode(input.value); announce(mode === "script" ? "已切换为剧本阅读" : "已切换为故事阅读"); }));
    $("print-book").addEventListener("click", async () => {
      const button = $("print-book"); button.disabled = true; button.textContent = "正在准备图卷";
      const images = [...document.querySelectorAll("main img")];
      images.forEach((image) => { image.loading = "eager"; });
      await Promise.allSettled(images.map((image) => image.decode()));
      openForPrint(); button.disabled = false; button.textContent = "打印图卷"; window.print();
    });
    window.addEventListener("beforeprint", () => { if (!beforePrint.length) openForPrint(); }); window.addEventListener("afterprint", restoreAfterPrint);
    document.addEventListener("click", (event) => {
      const anchor = event.target.closest('a[href^="#"]'); if (!anchor) return;
      let id; try { id = decodeURIComponent(anchor.hash.slice(1)); } catch { return; } if (!id) return;
      if (!$(id)) return; event.preventDefault(); if ($("contents-dialog").open) $("contents-dialog").close(); navigate(id);
    });
    document.addEventListener("keydown", (event) => {
      const editing = event.target.closest("input,textarea,select,[contenteditable='true']");
      if (event.key === "Escape") return;
      if (!editing && event.key === "/" && !$("image-dialog").open) { event.preventDefault(); openContents(true); return; }
      if (editing || $("contents-dialog").open || $("image-dialog").open || event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
      if (event.key === "ArrowRight") { event.preventDefault(); step(1); } else if (event.key === "ArrowLeft") { event.preventDefault(); step(-1); }
    });
    window.addEventListener("hashchange", () => { try { const id = decodeURIComponent(location.hash.slice(1)); if (sceneMap.has(id)) updateCurrent(sceneMap.get(id).index); } catch { /* Bad bookmarks do not prevent reading. */ } });
  }
  function runSelfCheck() {
    const tests = [], check = (name, passed) => tests.push({ name, passed: !!passed });
    check("story loaded", model.acts.length > 0 && scenes.length > 0);
    check("six acts", model.acts.length === 6);
    check("all scenes rendered", document.querySelectorAll("article[data-scene]").length === scenes.length);
    check("unique anchors", new Set([...document.querySelectorAll("[id]")].map((node) => node.id)).size === document.querySelectorAll("[id]").length);
    check("all scenes have prose", scenes.every((scene) => scene.paragraphs.length));
    check("all scenes have images", scenes.every((scene) => !!scene.image));
    check("all covers declared", model.acts.every((act) => !!act.cover));
    check("all scene directory links", document.querySelectorAll("[data-contents-scene]").length === scenes.length);
    check("search finds first scene", !scenes.length || search(scenes[0].title).some((entry) => entry.scene.id === scenes[0].id));
    check("empty data tolerated", normalize(null).acts.length === 0);
    check("hostile image rejected", safeUrl("javascript:alert(1)", true) === "");
    check("hostile source rejected", safeUrl("javascript:alert(1)") === "");
    check("local research source normalized", safeUrl("../research/example.md") === "../../research/example.md");
    check("local research traversal rejected", safeUrl("../research/../../secret.md") === "");
    check("internal history labels translated", historyLabel("adaptation") === "历史改编" && historyLabel("historical") === "史实背景" && historyLabel("legend") === "地方传说");
    check("no remote runtime dependencies", [...document.querySelectorAll("script[src],link[rel='stylesheet']")].every((node) => !/^https?:/.test(node.getAttribute("src") || node.getAttribute("href") || "")));
    check("no horizontal overflow", document.documentElement.scrollWidth <= innerWidth + 1);
    return { passed: tests.every((entry) => entry.passed), tests, acts: model.acts.length, scenes: scenes.length, imageElements: document.querySelectorAll("main img").length, storageUnavailable };
  }
  render(); bind(); watchPosition();
  if (location.hash) requestAnimationFrame(() => { try { navigate(decodeURIComponent(location.hash.slice(1)), false); } catch { /* Malformed hash falls back to the cover. */ } });
  window.ZhengReader = Object.freeze({ normalize, search, navigate, setMode, runSelfCheck, get currentScene() { return scenes[currentIndex]?.id || ""; }, get storageUnavailable() { return storageUnavailable; }, get counts() { return { acts: model.acts.length, scenes: scenes.length }; } });
  if (new URLSearchParams(location.search).has("selftest")) requestAnimationFrame(() => { window.__ZHENG_READER_TESTS__ = runSelfCheck(); console.info("ZHENG_READER_SELF_CHECK", JSON.stringify(window.__ZHENG_READER_TESTS__)); });
})();
