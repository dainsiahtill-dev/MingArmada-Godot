#!/usr/bin/env node
// Offline evidence audit. This script never launches Godot or changes game sources.
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import vm from 'node:vm';

const root = fs.realpathSync(path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
const base = 'docs/research/evidence/world-cloud-lifecycle-2026-10-15';
const failures = [], checks = [], images = [], sources = {};
const sha = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const hash = file => sha(fs.readFileSync(file));
const check = (ok, description) => {
  checks.push({ ok: Boolean(ok), description });
  if (!ok) failures.push(description);
};
function contained(parent, relative) {
  assert.equal(typeof relative, 'string', 'file path must be a string');
  assert(/^[A-Za-z0-9_./-]+$/.test(relative), 'unsupported path characters');
  assert(!path.isAbsolute(relative) && !relative.split('/').includes('..'), 'path must stay inside its owner');
  const target = path.resolve(parent, relative);
  const delta = path.relative(parent, target);
  assert(delta && delta !== '..' && !delta.startsWith(`..${path.sep}`) && !path.isAbsolute(delta), 'path escapes its owner');
  if (fs.existsSync(target)) {
    const realDelta = path.relative(fs.realpathSync(parent), fs.realpathSync(target));
    assert(realDelta && realDelta !== '..' && !realDelta.startsWith(`..${path.sep}`) && !path.isAbsolute(realDelta), 'symlink escapes its owner');
  }
  return target;
}
const repoFile = relative => contained(root, relative);
const evidenceRoot = repoFile(base);
const read = relative => JSON.parse(fs.readFileSync(repoFile(relative), 'utf8'));
const near = (a, b, epsilon = 1e-9) => Number.isFinite(a) && Number.isFinite(b) && Math.abs(a - b) <= epsilon;
const distance = (a, b) => Math.hypot(...a.map((value, i) => value - b[i]));
const vector = value => Array.isArray(value) && value.length === 3 && value.every(Number.isFinite);
const html = value => String(value).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
const jsonForHtml = value => JSON.stringify(value).replace(/[<>&\u2028\u2029]/g, c => `\\u${c.charCodeAt(0).toString(16).padStart(4, '0')}`);
const url = relative => relative.split('/').map(encodeURIComponent).join('/');
const linkTo = relative => url(path.relative(evidenceRoot, repoFile(relative)).replaceAll('\\', '/'));

function pngDimensions(bytes) {
  assert(bytes.length > 45 && bytes.subarray(0, 8).equals(Buffer.from([137,80,78,71,13,10,26,10])), 'nonempty PNG signature');
  assert.equal(bytes.toString('ascii', 12, 16), 'IHDR', 'PNG must start with IHDR');
  assert.equal(bytes.readUInt32BE(8), 13, 'valid IHDR size');
  const width = bytes.readUInt32BE(16), height = bytes.readUInt32BE(20);
  assert(width > 0 && height > 0, 'nonempty PNG dimensions');
  let offset = 8, dataBytes = 0, ended = false;
  while (offset + 12 <= bytes.length) {
    const size = bytes.readUInt32BE(offset), type = bytes.toString('ascii', offset + 4, offset + 8);
    assert(offset + 12 + size <= bytes.length, 'complete PNG chunk');
    if (type === 'IDAT') dataBytes += size;
    offset += 12 + size;
    if (type === 'IEND') { assert.equal(size, 0); ended = true; break; }
  }
  assert(ended && dataBytes > 0 && offset === bytes.length, 'PNG has image payload and complete end');
  return { width, height, bytes: bytes.length, compressedImageBytes: dataBytes };
}

function assessRun(run, marker, countField, expectedCount) {
  const output = `${run.stdout ?? ''}\n${run.stderr ?? ''}`.replace(/\u001b\[[0-9;]*m/g, '');
  const completions = output.split(/\r?\n/).filter(line => line.startsWith(`${marker} `));
  const expected = `${marker} ${countField}=${expectedCount} failures=0`;
  const reasons = [];
  if (run.valid !== true || run.exitCode !== 0 || run.timedOut !== false || run.processError) reasons.push('process did not finish successfully');
  if (!Array.isArray(run.diagnostics) || run.diagnostics.length) reasons.push('raw run diagnostics are not empty');
  if (/SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)|Error loading/i.test(output)) reasons.push('Godot error in raw output');
  if (completions.length !== 1 || completions[0] !== expected) reasons.push(`expected exactly one ${expected}`);
  const start = Date.parse(run.startedAtUtc), finish = Date.parse(run.finishedAtUtc);
  if (!Number.isFinite(start) || !Number.isFinite(finish) || finish < start) reasons.push('invalid run interval');
  return { valid: reasons.length === 0, completion: completions, reasons };
}

function archiveRun(input, output, marker, countField, expectedCount, script, gpu) {
  const run = read(input), assessed = assessRun(run, marker, countField, expectedCount);
  check(assessed.valid, `${input}: unique successful ${marker} completion; ${assessed.reasons.join('; ')}`);
  check(Array.isArray(run.args) && run.args.includes(`res://${script}`), `${input}: expected executable script`);
  check(path.resolve(run.cwd) === root, `${input}: expected repository working directory`);
  if (gpu) {
    check(!run.args.includes('--headless') && /Vulkan .*Using Device/.test(run.stdout), `${input}: actual Vulkan GPU execution`);
    check(run.args.includes(`--output=res://${base}/${gpu}`), `${input}: output matches accepted proof folder`);
  }
  fs.writeFileSync(repoFile(`${base}/${output}`), fs.readFileSync(repoFile(input)));
  return { source: input, archive: output, sha256: hash(repoFile(input)), ...assessed };
}

function verifySources(proof, label) {
  const entries = Object.entries(proof.sources ?? {});
  check(entries.length > 0, `${label}: frozen source manifest exists`);
  for (const [relative, expected] of entries) {
    const actual = hash(repoFile(relative));
    check(/^[a-f0-9]{64}$/.test(expected) && actual === expected, `${label}: current source SHA256 ${relative}`);
    if (sources[relative]) check(sources[relative] === expected, `consistent shared source hash ${relative}`);
    sources[relative] = actual;
  }
}

function verifyPng(folder, image, expected) {
  assert(/^[A-Za-z0-9_-]+\.png$/.test(image), 'capture filename must be a local PNG basename');
  const filename = contained(repoFile(`${base}/${folder}`), image), bytes = fs.readFileSync(filename);
  const dimensions = pngDimensions(bytes), actual = sha(bytes);
  check(/^[a-f0-9]{64}$/.test(expected) && actual === expected, `${folder}/${image}: original PNG SHA256`);
  check(dimensions.width > 0 && dimensions.height > 0, `${folder}/${image}: nonempty PNG and dimensions`);
  images.push({ path: `${folder}/${image}`, sha256: actual, ...dimensions });
}

function verifyCaptures(proof, folder, expectedCount) {
  check(Array.isArray(proof.captures) && proof.captures.length === expectedCount, `${folder}: ${expectedCount} accepted capture records`);
  const names = [];
  for (const capture of proof.captures) {
    check(Number.isFinite(capture.time ?? capture.accepted_time), `${folder}/${capture.image}: actual accepted time recorded`);
    verifyPng(folder, capture.image, capture.sha256); names.push(capture.image);
    if (folder === 'production-2') { verifyPng(folder, capture.mirror, capture.mirror_sha256); names.push(capture.mirror); }
  }
  check(new Set(names).size === names.length, `${folder}: no duplicate image records`);
  const diskNames = fs.readdirSync(repoFile(`${base}/${folder}`)).filter(name => name.endsWith('.png')).sort();
  check(JSON.stringify([...names].sort()) === JSON.stringify(diskNames), `${folder}: every PNG belongs to accepted manifest`);
}

function verifyTrajectory(proof, label, chosen, count, hz, stepLimit) {
  const baseline = proof.trajectories.baseline, candidate = proof.trajectories[chosen];
  for (const [name, rows] of [['baseline', baseline], [chosen, candidate]]) {
    check(Array.isArray(rows) && rows.length === count, `${label}/${name}: ${count} accepted trajectory samples`);
    check(rows.every((row, i) => near(row.time, i / hz) && vector(row.position) && Number.isInteger(row.generation) && Number.isInteger(row.recycles)), `${label}/${name}: finite trajectory on exact ${hz} Hz accepted timeline`);
  }
  check(baseline.every((row, i) => row.generation === candidate[i].generation && near(row.time, candidate[i].time)), `${label}: A/B source generations and accepted times identical`);
  check(distance(baseline[0].position, [-1598,30,0]) < 1e-5 && distance(candidate[0].position, baseline[0].position) < 1e-5, `${label}: near-reset fixture present in both cached t=0 packets`);
  const reset = baseline.findIndex((row, i) => i > 0 && row.generation > baseline[i - 1].generation);
  check(reset === (label === 'lab-3' ? 1 : 2), `${label}: expected first source reset index`);
  assert(reset > 0, 'first reset required');
  const oldJump = distance(baseline[reset].position, baseline[reset - 1].position);
  const newStep = distance(candidate[reset].position, candidate[reset - 1].position);
  check(oldJump > 1000 && newStep > 0 && newStep < stepLimit && candidate[reset].retiring && candidate[reset].recycles === 0, `${label}: first reset retains moving old actor without kilometer pop`);
  // Godot Vector3 distance is float32; JavaScript Math.hypot is float64.
  check(near(oldJump, proof.metrics.baseline_first_jump_m, 1e-4) && near(newStep, proof.metrics[label === 'lab-3' ? 'candidate_first_step_m' : 'production_first_step_m'], 1e-4), `${label}: independently recomputed reset distances match metrics within 0.1 mm float32 rounding`);
  const recycle = candidate.findIndex((row, i) => i > 0 && row.recycles > candidate[i - 1].recycles);
  if (label === 'lab-3') {
    check(baseline.every((row, i) => JSON.stringify(row.native) === JSON.stringify(candidate[i].native)), `${label}: all 129 native source positions identical`);
    check(recycle > reset && candidate[recycle].recycles === 1 && !candidate[recycle].retiring, `${label}: later bounded recycle observed`);
  } else check(candidate.every(row => row.recycles === 0), `${label}: visible 0..2s trajectory has no recycle`);
  return { samplesPerArm: count, hz, acceptedTimeStart: 0, acceptedTimeEnd: (count - 1) / hz, firstResetTime: baseline[reset].time, baselineJumpMetres: oldJump, chosenStepMetres: newStep, recycleTimeInTrajectory: recycle > 0 ? candidate[recycle].time : null };
}

function pairedFrames(proof, folder, chosen) {
  const first = proof.captures.filter(row => /^baseline-\d+\.png$/.test(row.image));
  const second = proof.captures.filter(row => new RegExp(`^${chosen}-\\d+\\.png$`).test(row.image));
  check(first.length === second.length && first.length === (folder === 'lab-3' ? 25 : 8), `${folder}: complete paired framebuffer timeline`);
  return first.map((before, i) => {
    const after = second[i], time = before.time ?? before.accepted_time;
    check(near(time, after.time ?? after.accepted_time), `${folder}: A/B framebuffer accepted times match at sample ${i}`);
    if (folder === 'production-2') {
      check(JSON.stringify(before.native_clouds) === JSON.stringify(after.native_clouds), `${folder}: paired native cloud authority identical at ${time}s`);
      check(before.camera === after.camera && before.display.enabled === false && after.display.enabled === true, `${folder}: same camera and declared A/B policy at ${time}s`);
    }
    return { time, baseline: `${folder}/${before.image}`, chosen: `${folder}/${after.image}`, baselineMirror: before.mirror ? `${folder}/${before.mirror}` : null, chosenMirror: after.mirror ? `${folder}/${after.mirror}` : null };
  });
}

function regressionSummary() {
  for (const file of [`${base}/full-headless.json`, `${base}/contracts/full-headless.json`, 'Temp/full-headless.json']) {
    if (!fs.existsSync(repoFile(file))) continue;
    try {
      const data = read(file);
      assert(Array.isArray(data.runs), 'regression report requires runs array');
      const failed = data.runs.filter(run => run.passed !== true).map(run => ({ test: run.test, exitCode: run.exitCode, timedOut: run.timedOut, reasons: run.reasons ?? [] }));
      return { present: true, source: file, sha256: hash(repoFile(file)), declaredSummary: data.summary ?? null, runs: data.runs.length, passed: data.runs.length - failed.length, failed, allPassed: failed.length === 0 && data.runs.length > 0, affectsCloudEvidenceVerdict: false };
    } catch (error) { return { present: true, source: file, readError: error.message, affectsCloudEvidenceVerdict: false }; }
  }
  return { present: false, affectsCloudEvidenceVerdict: false, note: 'Full headless report absent when this offline audit ran.' };
}

function renderReview(report, labFrames, productionFrames, production, pixel) {
  const figure = (src, caption) => `<figure><a href="${html(url(src))}"><img src="${html(url(src))}" alt="${html(caption)}" loading="lazy"></a><figcaption>${html(caption)}</figcaption></figure>`;
  const panel = (id, title, subtitle, frames, mirrors) => `<section id="${id}"><h2>${html(title)}</h2><p>${html(subtitle)}</p><div class="controls"><button type="button" data-play="${id}">播放原始帧</button><label>已捕获样本 <input type="range" min="0" max="${frames.length - 1}" value="0" step="1" data-slider="${id}"></label><output data-time="${id}">接受时间 t=${html(String(frames[0].time))} 秒 · 1/${frames.length}</output></div><div class="pair"><div><h3>A：基线（直接采用源位置）</h3><a data-link="${id}-baseline" href="${html(url(frames[0].baseline))}"><img data-image="${id}-baseline" src="${html(url(frames[0].baseline))}" alt="${html(title)}：基线主相机原始画面"></a></div><div><h3>B：采用的生命周期策略</h3><a data-link="${id}-chosen" href="${html(url(frames[0].chosen))}"><img data-image="${id}-chosen" src="${html(url(frames[0].chosen))}" alt="${html(title)}：生命周期策略主相机原始画面"></a></div>${mirrors ? `<div><h3>A：基线 · 平面反射原始画面</h3><a data-link="${id}-baselineMirror" href="${html(url(frames[0].baselineMirror))}"><img data-image="${id}-baselineMirror" src="${html(url(frames[0].baselineMirror))}" alt="基线平面反射视口原始画面"></a></div><div><h3>B：生命周期策略 · 平面反射原始画面</h3><a data-link="${id}-chosenMirror" href="${html(url(frames[0].chosenMirror))}"><img data-image="${id}-chosenMirror" src="${html(url(frames[0].chosenMirror))}" alt="生命周期策略平面反射视口原始画面"></a></div>` : ''}</div><details><summary>展开实际捕获的接受时间</summary><p>${html(frames.map(frame => String(frame.time)).join(', '))} 秒</p></details></section>`;
  const extras = production.captures.filter(row => !/^(baseline|production)-\d+\.png$/.test(row.image));
  const full = report.fullSuiteRegression;
  const suite = !full.present ? '<p>本次离线核验时，完整 headless 回归报告尚未归档；本页不据此宣称全套回归通过。</p>' : `<p><a href="${html(linkTo(full.source))}">完整 headless 回归原始报告</a> · 共 ${html(full.runs ?? '未知')} 项，通过 ${html(full.passed ?? '未知')} 项，失败 ${html(full.failed?.length ?? '未知')} 项。该回归结果单独列示；云证据通过不表示完整回归全部通过。</p>${full.readError ? `<p>报告读取失败：${html(full.readError)}</p>` : `<ul>${full.failed.map(run => `<li><code>${html(run.test)}</code>：${html(run.reasons.join('; ') || `退出码=${run.exitCode}；超时=${run.timedOut}`)}</li>`).join('')}</ul>`}`;
  const extraTitles = { 'normal-entry.png':'真实标准自由航行入口 · 常规初态', 'quality-high-paused.png':'暂停时切换高画质', 'low-angle-paused.png':'暂停时切换低角度相机', 'after-offscreen-recycle.png':'完整出镜后，接受下一时刻并回收' };
  const limitations = ['近重置初态属于明确声明的控制夹具；常规自由航行入口另有原始截图与标签。','画面只覆盖实际捕获的接受时刻，不插帧，也不代表所有可能的相机状态。','镜像图片来自实际平面反射视口的原始帧缓冲，未用主画面的海面区域裁剪替代。','逻辑天气位置与 RNG 仍为权威数据；显示层等待出镜时，旧云位置允许暂时偏离逻辑中心。','生产证据内的 CPU 耗时仅测暂停时同一数据包的显示处理成本，不能作为整场游戏 FPS。','不宣称原版像素一致、原版实测速率，或完整游戏性能已验收。','完整 headless 回归失败独立保留；云证据通过不表示全套测试通过。'];
  const followup = fs.existsSync(repoFile(`${base}/contracts/extended-headless-assessment.json`)) ? `<p><a href="contracts/extended-headless-assessment.json">两个超时项的独立复验审查</a>：扩大保护窗口后串行复跑均通过；原全套的两个超时失败继续保留。其余失败及直接依赖核对见研究报告的完整回归表。</p>` : "";
  const data = { lab: labFrames, production: productionFrames };
  return `<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self' file:; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"><title>世界云生命周期 · 原始证据审阅</title><style>
:root{color-scheme:light;--ink:#152b36;--muted:#53636a;--line:#cbd2d1;--paper:#f5f4ee;--accent:#145e53}*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.55 system-ui,sans-serif}main{max-width:1440px;padding:36px 24px 64px;margin:auto}h1{font-size:clamp(28px,4vw,46px);line-height:1.12;max-width:980px;margin:12px 0 24px}h2{font-size:25px;margin:0 0 12px}h3{font-size:16px;font-weight:650;margin:12px 0 8px}p{max-width:1060px}a{color:var(--accent);text-underline-offset:3px}section{border-top:1px solid var(--line);padding-top:28px;margin-top:34px}.eyebrow{letter-spacing:.1em;text-transform:uppercase;font-size:13px;color:var(--muted)}.verdict{font-weight:700;color:var(--accent)}.controls{display:flex;gap:18px;align-items:center;flex-wrap:wrap;margin:20px 0}.controls label{display:flex;align-items:center;gap:10px}input[type=range]{width:220px;accent-color:var(--accent)}button{background:var(--accent);color:white;border:0;border-radius:4px;padding:10px 14px;font:inherit;cursor:pointer}button:focus-visible,a:focus-visible,input:focus-visible{outline:3px solid #b86a19;outline-offset:3px}output,code{font-family:ui-monospace,monospace}output{font-size:14px}.pair{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.pair img,.extras img{display:block;width:100%;height:auto;background:#dbe1df;border:1px solid var(--line)}figure{margin:0}figcaption{font-size:14px;color:var(--muted);margin-top:6px}details{margin-top:16px}summary{cursor:pointer}li{margin:6px 0}.extras{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:18px}.record{border-top:1px dashed var(--line);padding-top:20px;margin-top:24px}@media(max-width:740px){main{padding:24px 14px}.pair,.extras{grid-template-columns:1fr}.controls{align-items:flex-start;flex-direction:column}.controls label{flex-wrap:wrap}output{overflow-wrap:anywhere}}
</style></head><body><main><div class="eyebrow">可复现工程证据 · 2026-10-15</div><h1>世界云生命周期：并排审阅基线与采用方案的原始画面</h1><p class="verdict">云证据核验：${report.valid ? '通过' : '失败'} · 已核验 ${report.imageCount} 张原始 PNG · ${report.sourceCount} 个当前源文件哈希一致</p><p>本页离线展示真实捕获的帧缓冲与仿真接受时间。拖动滑块只切换已有 PNG；播放按相邻捕获的实际接受时间间隔推进，不插帧、不补造画面，也不重新运行游戏。点击图片可查看原始 PNG。</p><p><a href="VERIFY.json">离线核验 JSON</a> · <a href="lab-3/LAB_VERIFY.json">实验室证据</a> · <a href="production-2/LIFECYCLE_VERIFY.json">生产入口证据</a> · <a href="lab-3/RUN.json">实验室原始运行日志</a> · <a href="production-2/RUN.json">生产入口原始运行日志</a> · <a href="${html(linkTo('assets/research/papers/weather-shadow.md'))}">现有 weather-shadow 研究论文</a> · <a href="${html(linkTo('docs/research/world-cloud-lifecycle-2026-10-15.md'))}">生命周期研究报告</a></p>
${panel('lab', '现有 weather-shadow 实验室', '明确声明的近重置夹具，随机种子 1，modelScale 1，相机与诊断网格固定。A/B 每组按 32 Hz 采样 129 个接受时刻，覆盖 0～4 秒；GPU 原帧覆盖 0～2 秒的 8 Hz 采样，以及实际屏外回收前后的 2.5/3/3.5/3.53125/3.5625/3.59375/3.625/4 秒。首次源重置发生在 t=0.03125 秒，重置后首张原帧为 t=0.125 秒。基线直接跳到源位置，采用方案保留旧云并沿连续轨迹移动。', labFrames, false)}
<p><a href="lab-2/LAB_VERIFY.json">此前成功的 lab-2 证据</a> 保留为历史记录，当时 GPU 工具尚未加入回收前后的密集捕获。最终源文件与哈希核验采用 lab-3。</p>
${panel('production', '真实自由航行运行链路 · 明确声明的近重置夹具', '采用真实游戏入口、生产运行时、物理、海面、船员与实际平面反射，正常 modelScale 为 10。该 A/B 明确修改 Weather 初态以触发重置；常规入口初态另列于下方。每组按 60 Hz 采样 121 个接受时刻，覆盖 0～2 秒。截图间隔并不均匀，以下保留每帧实际的接受时间。', productionFrames, true)}
<section><h2>真实标准入口与额外生产链路检查</h2><p>下方 normal-entry 原帧拍摄于设置近重置夹具之前，记录常规自由航行入口在接受时间 t=0 的初态。其余检查使用已声明的夹具。暂停时切换画质或相机，接受时间仍为 t=2 秒；屏外回收发生在 t=${html(String(extras.at(-1).accepted_time))} 秒。</p>${extras.map(row => `<article class="record"><h3>${html(extraTitles[row.image] ?? row.image.replace('.png',''))}</h3><p>接受时间 t=${html(String(row.accepted_time))} 秒</p><div class="extras">${figure(`production-2/${row.image}`, '主相机原始画面')}${figure(`production-2/${row.mirror}`, '实际平面反射视口原始画面')}</div></article>`).join('')}</section>
<section><h2>连续性实测与验收边界</h2><p>首次源重置时，实验室基线位置跳变 ${report.trajectories.lab.baselineJumpMetres.toFixed(3)} 米，生产入口基线跳变 ${report.trajectories.production.baselineJumpMetres.toFixed(3)} 米。采用方案的显示位移分别为每 1/32 秒 ${report.trajectories.lab.chosenStepMetres.toFixed(3)} 米、每 1/60 秒 ${report.trajectories.production.chosenStepMetres.toFixed(3)} 米。以上测量用于验收重置连续性，不作为原版游戏速度的标定。</p>${pixel ? `<p><a href="PIXEL_VERIFY.json">相对基线的变暗区域与质心像素证据</a> · <a href="PIXEL_RUN.json">像素核验原始日志</a>。七个配对接受时刻，主画面与实际反射原帧共 14 组比较。主画面质心 x 从 ${pixel.rows[0].main.centroid[0].toFixed(3)} 移至 ${pixel.rows.at(-1).main.centroid[0].toFixed(3)} 像素；反射原帧质心 x 从 ${pixel.rows[0].mirror.centroid[0].toFixed(3)} 移至 ${pixel.rows.at(-1).mirror.centroid[0].toFixed(3)} 像素。反射相机使两者的屏幕坐标运动方向相反。</p>` : ''}<ul>${limitations.map(item => `<li>${html(item)}</li>`).join('')}</ul></section>
<section><h2>保留的失败夹具与回归结果</h2><p><a href="production-1/LIFECYCLE_VERIFY.json">production-1 失败证据完整保留</a>：缓存的 t=0 数据包仍使用云位置 x=800 米，而预期近重置夹具应为 x=-1598 米。该报告明确记录 valid=false，采用方案重置步长为 ${report.rejectedProof.productionFirstStepMetres.toFixed(3)} 米，未纳入通过验收的 A/B。修正后的 production-2 在 A/B 前明确刷新并检查运行时快照。</p>${suite}${followup}</section><p class="eyebrow">由 tools/verify-cloud-lifecycle-evidence.mjs 根据本地原始证据生成</p></main>
<script id="recorded-data" type="application/json">${jsonForHtml(data)}</script><script>
'use strict';
const timelines=JSON.parse(document.getElementById('recorded-data').textContent);
for(const [id,frames] of Object.entries(timelines)){
 const slider=document.querySelector('[data-slider="'+id+'"]');
 const button=document.querySelector('[data-play="'+id+'"]');
 const output=document.querySelector('[data-time="'+id+'"]');
 let timer=null,playing=false;
 function show(){const index=Number(slider.value),frame=frames[index];for(const key of ['baseline','chosen','baselineMirror','chosenMirror']){if(!frame[key])continue;const image=document.querySelector('[data-image="'+id+'-'+key+'"]'),link=document.querySelector('[data-link="'+id+'-'+key+'"]');const source=frame[key].split('/').map(encodeURIComponent).join('/');image.src=source;link.href=source;}output.textContent='接受时间 t='+String(frame.time)+' 秒 · '+(index+1)+'/'+frames.length;}
 function stop(){playing=false;clearTimeout(timer);button.textContent='播放原始帧';}
 function schedule(){const i=Number(slider.value);if(i>=frames.length-1){stop();return;}timer=setTimeout(()=>{slider.value=String(i+1);show();schedule();},Math.max(1,(frames[i+1].time-frames[i].time)*1000));}
 slider.addEventListener('input',()=>{stop();show();});
 button.addEventListener('click',()=>{if(playing){stop();return;}if(Number(slider.value)>=frames.length-1)slider.value='0';playing=true;button.textContent='暂停';show();schedule();});
 document.addEventListener('visibilitychange',()=>{if(document.hidden)stop();});
 show();
}
</script></body></html>\n`;
}

function selfTest() {
  const run = { valid:true, exitCode:0, timedOut:false, diagnostics:[], stdout:'EXAMPLE captures=2 failures=0\n', stderr:'', startedAtUtc:'2026-10-15T00:00:00Z', finishedAtUtc:'2026-10-15T00:00:01Z' };
  assert(assessRun(run, 'EXAMPLE', 'captures', 2).valid);
  assert(!assessRun({...run,stdout:run.stdout+run.stdout},'EXAMPLE','captures',2).valid);
  assert(!assessRun({...run,stdout:'OTHER captures=2 failures=0'},'EXAMPLE','captures',2).valid);
  assert(!assessRun({...run,stderr:'SCRIPT ERROR: invalid call'},'EXAMPLE','captures',2).valid);
  assert(!assessRun({...run,stdout:'EXAMPLE captures=2 failures=1'},'EXAMPLE','captures',2).valid);
  assert(!assessRun({...run,exitCode:1},'EXAMPLE','captures',2).valid);
  assert(!assessRun({...run,timedOut:true},'EXAMPLE','captures',2).valid);
  assert.throws(()=>contained(root,'../outside.png'));
  assert.throws(()=>contained(root,'C:/outside.png'));
  assert.throws(()=>contained(root,'https://example.com/image.png'));
  assert(!jsonForHtml('</script><script>bad()</script>').includes('<'));
  assert.equal(html('<&"'), '&lt;&amp;&quot;');
  const png = fs.readFileSync(repoFile(`${base}/lab-3/baseline-000.png`));
  assert(pngDimensions(png).width > 0);
  const zero = Buffer.from(png);zero.writeUInt32BE(0,16);assert.throws(()=>pngDimensions(zero));
  assert.throws(()=>pngDimensions(png.subarray(0,png.length-12)));
  console.log('CLOUD_LIFECYCLE_EVIDENCE_SELF_TEST assertions=15 failures=0');
}

function verifyReview(page) {
  for (const match of page.matchAll(/(?:src|href)="([^"]+)"/g)) {
    const relative = decodeURIComponent(match[1]);
    assert(!relative.includes(':') && !relative.startsWith('//'), 'review asset/link must be local');
    const file = path.resolve(evidenceRoot, relative), delta = path.relative(root, file);
    assert(!delta.startsWith('..') && !path.isAbsolute(delta) && (fs.existsSync(file) || file===repoFile(`${base}/VERIFY.json`)), `existing repository review asset/link: ${relative}`);
  }
  const scripts = [...page.matchAll(/<script\b([^>]*)>([\s\S]*?)<\/script>/g)];
  assert.equal(scripts.length, 2, 'one embedded data block and one inline player');
  const data = JSON.parse(scripts[0][2]), nodes = new Map(), timers = new Map();
  let timerId = 0;
  const querySelector = selector => {
    if (!nodes.has(selector)) nodes.set(selector, { value:'0', listeners:{}, addEventListener(type, listener) { this.listeners[type] = listener; } });
    return nodes.get(selector);
  };
  const document = { hidden:false, listeners:{}, getElementById:()=>({textContent:scripts[0][2]}), querySelector, addEventListener(type,listener) { this.listeners[type] = listener; } };
  const context = vm.createContext({ document, setTimeout:(callback,delay)=>{const id=++timerId;timers.set(id,{callback,delay});return id;}, clearTimeout:id=>timers.delete(id) });
  new vm.Script(scripts[1][2], { filename:'review.html inline recorded-frame player' }).runInContext(context, { timeout:1000 });
  for (const [id, frames] of Object.entries(data)) {
    const slider=querySelector(`[data-slider="${id}"]`), button=querySelector(`[data-play="${id}"]`), output=querySelector(`[data-time="${id}"]`);
    assert.equal(querySelector(`[data-image="${id}-chosen"]`).src, frames[0].chosen);
    slider.value=String(id==='lab'?20:1);slider.listeners.input();
    const index=Number(slider.value);
    assert(output.textContent.includes(`接受时间 t=${frames[index].time} 秒`));
    assert.equal(querySelector(`[data-link="${id}-baseline"]`).href, frames[index].baseline);
    if (id==='production') assert.equal(querySelector(`[data-image="${id}-chosenMirror"]`).src, frames[index].chosenMirror);
    button.listeners.click();
    const scheduled=[...timers.values()].at(-1);
    assert(near(scheduled.delay,(frames[index+1].time-frames[index].time)*1000));
    scheduled.callback();
    assert.equal(Number(slider.value),index+1);
    assert.equal(querySelector(`[data-image="${id}-chosen"]`).src,frames[index+1].chosen);
    document.hidden=true;document.listeners.visibilitychange();document.hidden=false;
    slider.value=String(frames.length-1);slider.listeners.input();button.listeners.click();
    assert.equal(Number(slider.value),0,'play at end restarts captured sequence');
    button.listeners.click();assert.equal(button.textContent,'播放原始帧');
  }
  check(true,'offline review: local links, embedded data/script, sliders, captured-time playback, main/mirror frame changes and pause controls verified without browser or GPU');
}

function main() {
  const lab = read(`${base}/lab-3/LAB_VERIFY.json`), production = read(`${base}/production-2/LIFECYCLE_VERIFY.json`);
  for (const [label,proof] of [['lab-3',lab],['production-2',production]]) {
    check(proof.valid === true && Array.isArray(proof.failures) && proof.failures.length === 0, `${label}: valid proof with zero failures`);
    verifySources(proof,label);
    verifyCaptures(proof,label,label === 'lab-3' ? 50 : 20);
  }
  const labFrames = pairedFrames(lab,'lab-3','candidate'), productionFrames = pairedFrames(production,'production-2','production');
  check([3.5,3.53125,3.5625,3.59375,3.625].every(time=>labFrames.some(frame=>near(frame.time,time))), 'lab-3: original GPU frames immediately before, at, and after offscreen recycle');
  const trajectories = { lab:verifyTrajectory(lab,'lab-3','candidate',129,32,4), production:verifyTrajectory(production,'production-2','production',121,60,2) };
  const runs = [archiveRun('Temp/cloud-lifecycle-lab-gpu-run3.json','lab-3/RUN.json','CLOUD_LIFECYCLE_LAB_GPU','captures',50,'tools/verify-cloud-lifecycle-lab-gpu.gd','lab-3'),archiveRun('Temp/cloud-lifecycle-production-gpu-run3.json','production-2/RUN.json','CLOUD_LIFECYCLE_PRODUCTION_GPU','captures',20,'tools/verify-cloud-lifecycle-production-gpu.gd','production-2')];
  const normal = production.captures.find(row=>row.image==='normal-entry.png');
  check(normal && normal.accepted_time===0 && normal.native_clouds[0].worldPosition[0]===800, 'actual ordinary free-sail entry separately captured before declared near-reset fixture');
  const recycled = production.captures.find(row=>row.image==='after-offscreen-recycle.png');
  check(recycled.accepted_time>2 && recycled.display.states['0'].recycles===1 && !recycled.display.states['0'].retiring, 'production post-look-away accepted frame records one completed recycle');
  let pixel = null;
  if (fs.existsSync(repoFile(`${base}/PIXEL_VERIFY.json`))) {
    pixel=read(`${base}/PIXEL_VERIFY.json`);
    check(pixel.valid===true && pixel.failures.length===0 && pixel.rows.length===7, 'pixel proof: seven paired main/mirror accepted samples and zero failures');
    check(pixel.rows.every((row,i)=>near(row.accepted_time,productionFrames[i+1].time) && row.main.pixels>0 && row.mirror.pixels>0 && row.main.centroid.every(Number.isFinite) && row.mirror.centroid.every(Number.isFinite)), 'pixel proof: matches accepted PNG times with nonempty measured clouds');
    check(pixel.rows[0].main.centroid[0]-pixel.rows.at(-1).main.centroid[0]>100 && pixel.rows.at(-1).mirror.centroid[0]-pixel.rows[0].mirror.centroid[0]>100 && pixel.rows.every((row,i)=>i===0||(row.main.centroid[0]<pixel.rows[i-1].main.centroid[0]&&row.mirror.centroid[0]>pixel.rows[i-1].mirror.centroid[0])), 'pixel proof: sampled retained cloud moves monotonically over 100 px in main/reflected image coordinates');
    runs.push(archiveRun('Temp/cloud-lifecycle-pixels-run1.json','PIXEL_RUN.json','CLOUD_LIFECYCLE_PIXEL_TESTS','frames',14,'tools/verify-cloud-lifecycle-pixels.gd'));
  }
  const rejected = read(`${base}/production-1/LIFECYCLE_VERIFY.json`);
  check(rejected.valid===false && rejected.failures.length>0 && rejected.trajectories.production[0].position[0]===800, 'retained production-1 proof documents failed cached-t0 fixture and stays excluded');
  const report = { schemaVersion:1, valid:failures.length===0, verdictScope:'cloud lifecycle evidence only; independent of full-suite regression outcome', createdUtc:new Date().toISOString(), failures, checks, imageCount:images.length, sourceCount:Object.keys(sources).length, sources, images, trajectories, runs, proofs:[{path:'lab-3/LAB_VERIFY.json',sha256:hash(repoFile(`${base}/lab-3/LAB_VERIFY.json`)),scope:lab.scope},{path:'production-2/LIFECYCLE_VERIFY.json',sha256:hash(repoFile(`${base}/production-2/LIFECYCLE_VERIFY.json`)),scope:production.scope}], pixelProof:pixel?{path:'PIXEL_VERIFY.json',sha256:hash(repoFile(`${base}/PIXEL_VERIFY.json`)),rows:pixel.rows}:null, rejectedProof:{path:'production-1/LIFECYCLE_VERIFY.json',sha256:hash(repoFile(`${base}/production-1/LIFECYCLE_VERIFY.json`)),valid:rejected.valid,failures:rejected.failures,exclusion:'cached t=0 packet predates declared near-reset fixture; not accepted A/B evidence',productionFirstStepMetres:rejected.metrics.production_first_step_m}, fullSuiteRegression:regressionSummary(), limitations:['Declared near-reset initial state is a controlled fixture; ordinary free-sail entry is captured and labelled separately.','Framebuffer samples cover recorded accepted times only; no interpolation and no claim about every possible camera.','Raw planar-reflection images are actual reflection viewport framebuffers, not screen-space ocean crops.','Logical weather source positions and RNG remain authoritative; presentation may retain a retiring cloud at a different position.','CPU timing in production proof measures paused same-packet presentation work only; this is not full-game FPS.','No claim of original-game pixel parity, original measured drift speed, or whole-game performance.','Full headless regression failures remain separate and visible; cloud evidence PASS does not imply full-suite PASS.'], verifier:{path:'tools/verify-cloud-lifecycle-evidence.mjs',sha256:hash(repoFile('tools/verify-cloud-lifecycle-evidence.mjs'))}, review:'review.html' };
  const review=renderReview(report,labFrames,productionFrames,production,pixel);
  if (pixel) report.supportingAuditSources = { 'tools/verify-cloud-lifecycle-pixels.gd': { sha256:hash(repoFile('tools/verify-cloud-lifecycle-pixels.gd')), hashStage:'post-capture offline evidence audit; pixel proof has no execution-time source manifest' } };
  verifyReview(review);
  fs.writeFileSync(repoFile(`${base}/review.html`),review);
  fs.writeFileSync(repoFile(`${base}/VERIFY.json`),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({valid:report.valid,verdictScope:report.verdictScope,checks:checks.length,images:images.length,sources:report.sourceCount,fullSuite:report.fullSuiteRegression,failures}));
  process.exitCode=report.valid?0:1;
}

if (process.argv.includes('--self-test')) selfTest();
else {
  try { main(); }
  catch (error) {
    console.error(`CLOUD_LIFECYCLE_EVIDENCE_ERROR ${error.message}`);
    fs.writeFileSync(repoFile(`${base}/VERIFY.json`),JSON.stringify({schemaVersion:1,valid:false,verdictScope:'cloud lifecycle evidence only',createdUtc:new Date().toISOString(),failures:[...failures,error.message],checks},null,2)+'\n');
    process.exitCode=1;
  }
}
