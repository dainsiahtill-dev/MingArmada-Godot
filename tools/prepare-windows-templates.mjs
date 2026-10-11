import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { Readable } from 'node:stream';
import { pipeline } from 'node:stream/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Never install templates into the user's Godot profile. All output is ignored.
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = '4.7.2-stable';
const assetName = `Godot_v${version}_export_templates.tpz`;
const expectedDigest = 'f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011';
const expectedSize = 1281349702;
const directory = path.join(root, 'build', 'tools', 'godot-4.7.2');
const archive = path.join(directory, assetName);
const names = ['windows_debug_x86_64.exe', 'windows_release_x86_64.exe',
  'windows_debug_x86_64_console.exe', 'windows_release_x86_64_console.exe'];
function command(args) {
  const result = spawnSync('rtk', ['proxy', ...args], { cwd: directory, encoding: 'utf8', maxBuffer: 8 * 1024 * 1024 });
  if (result.error || result.status !== 0) throw new Error(`Command failed: ${args.join(' ')}\n${result.error ?? result.stderr}\n${result.stdout}`);
  return result.stdout;
}
async function digest(file) {
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  return hash.digest('hex');
}
await mkdir(directory, { recursive: true });
const response = await fetch(`https://api.github.com/repos/godotengine/godot-builds/releases/tags/${version}`, {
  headers: { 'User-Agent': 'MingArmada-windows-template-verification', Accept: 'application/vnd.github+json' },
});
if (!response.ok) throw new Error(`Official release API failed: HTTP ${response.status}`);
const release = await response.json();
const asset = release.assets.find(entry => entry.name === assetName);
if (release.tag_name !== version || release.draft || release.prerelease || !asset
    || asset.digest !== `sha256:${expectedDigest}` || asset.size !== expectedSize
    || asset.browser_download_url !== `https://github.com/godotengine/godot-builds/releases/download/${version}/${assetName}`) {
  throw new Error('Official stable asset metadata does not match the pinned release; refusing download/extraction.');
}
const exists = await stat(archive).then(() => true, error => { if (error.code === 'ENOENT') return false; throw error; });
if (!exists) {
  console.log(`Downloading official ${assetName} (${expectedSize} bytes)...`);
  const download = await fetch(asset.browser_download_url);
  if (!download.ok || !download.body) throw new Error(`Template download failed: HTTP ${download.status}`);
  await pipeline(Readable.fromWeb(download.body), createWriteStream(archive, { flags: 'wx' }));
}
if ((await stat(archive)).size !== expectedSize || await digest(archive) !== expectedDigest) {
  throw new Error(`Archive digest/size mismatch. Refusing extraction; inspect/remove only this worktree file: ${archive}`);
}
const listing = command(['tar', '-tf', archive]).split(/\r?\n/).filter(Boolean);
const selected = names.map(name => {
  const member = `templates/${name}`;
  if (!listing.includes(member)) throw new Error(`Missing archive member ${member}`);
  return member;
});
// Windows dependencies supplied by this exact archive (D3D12, ICU, etc.).
for (const member of listing) {
  if (/^templates\/(?:.*\.dll|.*\.dat|version\.txt)$/i.test(member)) selected.push(member);
}
if (selected.some(member => !/^templates\/[A-Za-z0-9_.-]+$/.test(member))) throw new Error('Unsafe archive member path');
command(['tar', '-xf', archive, '-C', directory, ...selected]);
const versionFile = path.join(directory, 'templates', 'version.txt');
const templateVersion = (await readFile(versionFile, 'utf8')).trim();
if (templateVersion !== '4.7.2.stable') throw new Error(`Unexpected template version ${templateVersion}`);
const files = [];
for (const member of selected) {
  const file = path.join(directory, member);
  files.push({ file: path.relative(root, file).replaceAll('\\', '/'), bytes: (await stat(file)).size, sha256: await digest(file) });
}
const receipt = { version: templateVersion, release: release.html_url, releaseId: release.id,
  asset: { name: assetName, url: asset.browser_download_url, bytes: expectedSize, sha256: expectedDigest }, files };
await writeFile(path.join(directory, 'verification.json'), `${JSON.stringify(receipt, null, 2)}\n`);
console.log(JSON.stringify(receipt, null, 2));
