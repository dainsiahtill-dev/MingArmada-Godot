import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const destination = path.join(root, 'docs/narrative/zheng-zhilong');
const jobsPath = path.join(root, 'docs/narrative/zheng-illustration-jobs.json');
const jobs = JSON.parse(fs.readFileSync(jobsPath, 'utf8'));
for (const filename of ['zheng-illustration-film-a1-a2.json', 'zheng-illustration-film-a3-a4.json']) {
  const recordFile = path.join(root, 'docs/narrative', filename);
  if (fs.existsSync(recordFile)) {
    const records = JSON.parse(fs.readFileSync(recordFile, 'utf8'));
    jobs.push(...records.filter(record => record.adopted === true));
  }
}
const illustrations = [];
const ids = new Set();
for (const job of jobs) {
  if (ids.has(job.id)) throw new Error(`Duplicate illustration ${job.id}`);
  ids.add(job.id);
  const match = job.output_hint?.match(/as (C:\\[^\r\n]+\.png)/);
  const sourcePath = job.sourcePath || match?.[1];
  if (!sourcePath || !fs.existsSync(sourcePath)) throw new Error(`Missing generated original: ${job.id}`);
  const target = path.resolve(destination, job.path);
  if (!target.startsWith(destination + path.sep)) throw new Error(`Unsafe target ${job.path}`);
  const bytes = fs.readFileSync(sourcePath);
  if (bytes.subarray(0, 8).toString('hex') !== '89504e470d0a1a0a') throw new Error(`Not a PNG: ${job.id}`);
  const sha256 = crypto.createHash('sha256').update(bytes).digest('hex');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  if (fs.existsSync(target)) {
    const existing = crypto.createHash('sha256').update(fs.readFileSync(target)).digest('hex');
    if (existing !== sha256) throw new Error(`Existing image differs; choose a versioned filename: ${job.path}`);
  } else fs.copyFileSync(sourcePath, target);
  illustrations.push({ id: job.id, path: job.path, prompt: job.prompt, sourcePath,
    width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20), sha256,
    generator: 'built-in imagegen', kind: 'fictional historical narrative illustration',
    review: job.review || 'Root visual review: adopted film-v3 composition and scene.' });
}
const manifest = { schemaVersion: 1, generator: 'built-in imagegen',
  disclaimer: 'AI生成的历史剧情概念插画，不是历史现场记录或游戏实机截图。', illustrations };
fs.mkdirSync(destination, { recursive: true });
fs.writeFileSync(path.join(destination, 'illustration-manifest.json'), JSON.stringify(manifest, null, 2) + '\n');
console.log(JSON.stringify({ copiedAndVerified: illustrations.length, dimensions: illustrations.map(x => `${x.id}:${x.width}x${x.height}`) }));
