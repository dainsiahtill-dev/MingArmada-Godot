import { spawn } from 'node:child_process';
import { copyFile, mkdir, readdir, readFile, stat, writeFile } from 'node:fs/promises';
import { createReadStream } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const editor = process.env.GODOT_PATH || 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';
const output = path.join(root, 'build', 'windows');
const profile = path.join(root, 'build', 'export-profile');
async function sourceFiles(directory) {
  const result=[];
  for(const entry of await readdir(path.join(root,directory),{withFileTypes:true})) {
    const name=`${directory}/${entry.name}`;
    if(entry.isDirectory())result.push(...await sourceFiles(name));
    else if(entry.isFile())result.push(name);
  }
  return result;
}
async function currentSourceHashes() {
  const names=['project.godot','export_presets.cfg',...(await sourceFiles('game')),...(await sourceFiles('modules')),...(await sourceFiles('assets'))];
  return Promise.all([...new Set(names)].sort().map(async name=>({path:name,sha256:createHash('sha256').update(await readFile(path.join(root,name))).digest('hex')})));
}
const sourceSha256=await currentSourceHashes();
if(process.argv.includes('--prepare-only')) {
  await mkdir(path.join(root,'build'),{recursive:true});
  const prepared={stage:'prepared-only-not-exported',preparedAt:new Date().toISOString(),gameModes:['mingqi','career','sail','duel','fleet'],sourceSha256,scope:'Source coverage includes all game, modules and assets, including import settings and UID files. No Windows export or runtime launch has occurred.'};
  await writeFile(path.join(root,'build/windows-export-prepared.json'),JSON.stringify(prepared,null,2)+'\n');
  console.log(JSON.stringify({stage:prepared.stage,sourceFiles:sourceSha256.length,receipt:'build/windows-export-prepared.json'}));
  process.exit(0);
}
await Promise.all([output, profile].map(p => mkdir(p, { recursive: true })));
const env = { ...process.env, APPDATA: path.join(profile, 'roaming'), LOCALAPPDATA: path.join(profile, 'local') };
await Promise.all([env.APPDATA, env.LOCALAPPDATA].map(p => mkdir(p, { recursive: true })));
const logs = [];
const command = ['proxy', editor, '--headless', '--path', root, '--export-release', 'Windows Desktop', path.join(output, 'MingArmada.exe')];
const code = await new Promise((resolve, reject) => {
  const child = spawn('rtk', command, { cwd: root, env, windowsHide: true });
  child.on('error', reject);
  child.stdout.on('data', chunk => logs.push(chunk.toString()));
  child.stderr.on('data', chunk => logs.push(chunk.toString()));
  child.on('close', resolve);
});
const log = logs.join('');
await writeFile(path.join(root, 'build', 'export-release.log'), log);
if (code !== 0 || /(?:^|\n)\s*(?:SCRIPT ERROR|ERROR):/m.test(log)) {
  throw new Error(`Windows release export failed (${code}); see build/export-release.log\n${log.slice(-4000)}`);
}
const afterExportHashes=await currentSourceHashes();
if(JSON.stringify(afterExportHashes)!==JSON.stringify(sourceSha256))throw new Error('Game/module/asset sources changed during export; current package is not accepted. Freeze sources and repeat export.');
// Ship the normal user-argument preview entry only after a successful export.
// Official release templates disallow main-pack and external script overrides.
await copyFile(path.join(root, 'tools', 'launch-island-water.ps1'), path.join(output, 'Launch-IslandWater.ps1'));
await writeFile(path.join(output, 'Launch-IslandWater.cmd'), '@echo off\r\nrtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-IslandWater.ps1"\r\nif errorlevel 1 pause\r\n');
await copyFile(path.join(root,'tools/launch-mingqi.ps1'),path.join(output,'Launch-Game.ps1'));
await writeFile(path.join(output,'Launch-Mingqi.cmd'),'@echo off\r\nrtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Game.ps1" -Mode mingqi\r\nif errorlevel 1 pause\r\n');
await writeFile(path.join(output,'Launch-Menu.cmd'),'@echo off\r\nrtk proxy powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Game.ps1" -Mode menu\r\nif errorlevel 1 pause\r\n');
const files = [];
for (const name of (await readdir(output)).sort()) {
  const file = path.join(output, name);
  if(name==='windows-export.json')continue; // A portable copy cannot hash itself.
  if (!(await stat(file)).isFile()) continue;
  const hash = createHash('sha256');
  for await (const chunk of createReadStream(file)) hash.update(chunk);
  files.push({ name, bytes: (await stat(file)).size, sha256: hash.digest('hex') });
}
const referenceSources = [
  'assets/data/reference_cat_island_h.json',
  'game/scenes/reference_island_water/reference_island_water.gd',
  'game/scenes/reference_island_water/reference_island_water.tscn',
  'game/scenes/main/main_scene.gd', 'game/ui/menu/main_menu.gd', 'game/runtime/game_router.gd',
  ...(await readdir(path.join(root, 'modules/scene_engine/reference_island_water')))
    .filter(name => /\.(?:gd|gdshader|gdshaderinc)$/.test(name))
    .map(name => `modules/scene_engine/reference_island_water/${name}`),
];
const referenceSourceSha256 = await Promise.all(referenceSources.sort().map(async name => ({
  path: name, sha256: createHash('sha256').update(await readFile(path.join(root, name))).digest('hex'),
})));
if (!files.some(f => f.name === 'MingArmada.exe') || !files.some(f => f.name === 'MingArmada.pck')) {
  throw new Error('Expected EXE and PCK were not emitted.');
}
const receipt = { schemaVersion:2, stage: 'exported-not-yet-runtime-accepted', exportedAt: new Date().toISOString(), editor,
  engineCommand: command, exportLog: 'build/export-release.log', files,
  presetSha256: createHash('sha256').update(await readFile(path.join(root, 'export_presets.cfg'))).digest('hex'),
  previewEntrypoint: 'build/windows/Launch-IslandWater.cmd', previewScene: 'res://game/scenes/reference_island_water/reference_island_water.tscn',
  referenceSourceSha256,
  sourceSha256,
  gameEntrypoints:{menu:'Launch-Menu.cmd',mingqi:'Launch-Mingqi.cmd',launcher:'Launch-Game.ps1',modes:['mingqi','career','sail','duel','fleet'],arguments:'-- --start-game=<mode> [--game-capture=<absolute PNG>]',capture:'Actual current bundled scene/window; menu generation/nonce/operation and scene identity checked before/after each await.'},
  scope: 'Official verified release template, isolated editor profile, export exit/log checks and actual output hashes. Does not assert standalone UI/GPU/resource correctness.' };
await writeFile(path.join(root, 'build', 'windows-export.json'), `${JSON.stringify(receipt, null, 2)}\n`);
await writeFile(path.join(output,'windows-export.json'),`${JSON.stringify(receipt,null,2)}\n`);
console.log(JSON.stringify({stage:receipt.stage,exportedAt:receipt.exportedAt,files:receipt.files,sourceFiles:sourceSha256.length,previewSourceFiles:referenceSourceSha256.length,receipt:'build/windows-export.json'},null,2));
