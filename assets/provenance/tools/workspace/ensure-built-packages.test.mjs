import assert from 'node:assert/strict';
import { spawn, spawnSync } from 'node:child_process';
import { cp, mkdir, mkdtemp, readFile, rename, rm, stat, symlink, utimes, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';

const repository = fileURLToPath(new URL('../..', import.meta.url));
const cli = fileURLToPath(new URL('./ensure-built-packages.mjs', import.meta.url));
const ids = ['physics-core', 'naval-core', 'adventure-core', 'adventure-encounters'];
const names = ids.map(id => `@ming-armada/${id}`);

function runNode(root, args) {
  const result = spawnSync('rtk', ['proxy', process.execPath, ...args], {
    cwd: root, encoding: 'utf8', windowsHide: true, timeout: 60000,
  });
  assert.ifError(result.error);
  return { status: result.status, output: result.stdout + result.stderr };
}

async function fixture(t) {
  const root = await mkdtemp(path.join(os.tmpdir(), 'mingarmada-build-contract-'));
  t.after(async () => {
    assert.equal(path.dirname(root), path.resolve(os.tmpdir()));
    assert.ok(path.basename(root).startsWith('mingarmada-build-contract-'));
    await rm(root, { recursive: true, force: true });
  });
  await mkdir(path.join(root, 'node_modules', '@ming-armada'), { recursive: true });
  // Private compiler copy allows identity and no-invocation tests without touching repository dependencies.
  await cp(path.join(repository, 'node_modules/typescript'), path.join(root, 'node_modules/typescript'), { recursive: true });
  await writeFile(path.join(root, 'package.json'), JSON.stringify({ type: 'module' }));
  await writeFile(path.join(root, 'tsconfig.base.json'), JSON.stringify({
    compilerOptions: { target: 'ES2022', module: 'NodeNext', moduleResolution: 'NodeNext', strict: true, declaration: true, skipLibCheck: true },
  }));
  for (const [i, id] of ids.entries()) {
    const directory = path.join(root, 'packages', id);
    await mkdir(path.join(directory, 'src'), { recursive: true });
    await writeFile(path.join(directory, 'package.json'), JSON.stringify({
      name: names[i], version: '1.0.0', type: 'module',
      exports: { '.': { types: './dist/index.d.ts', default: './dist/index.js' } },
      dependencies: i ? { [names[i - 1]]: `file:../${ids[i - 1]}` } : {},
    }));
    await writeFile(path.join(directory, 'tsconfig.json'), JSON.stringify({
      extends: '../../tsconfig.base.json', compilerOptions: { outDir: 'dist', rootDir: 'src' }, include: ['src/**/*.ts'],
    }));
    await writeFile(path.join(directory, 'src/index.ts'), i
      ? `import { value as previous } from '${names[i - 1]}';\nexport const value = previous + 1;\n`
      : '// emitted comment\nexport const value: number = 1;\n');
    await symlink(directory, path.join(root, 'node_modules', '@ming-armada', id), process.platform === 'win32' ? 'junction' : 'dir');
  }
  return root;
}

function behavior(root) {
  const result = runNode(root, ['--input-type=module', '-e', `import { value } from '${names[3]}'; console.log('VALUE=' + value)`]);
  assert.equal(result.status, 0, result.output);
  return Number(result.output.match(/VALUE=(\d+)/)?.[1]);
}

async function snapshot(root) {
  return readFile(path.join(root, '.cache/workspace-builds.json'), 'utf8');
}

async function holdWindowsHandle(root, target, directory = true) {
  const script = path.join(root, 'hold-windows-handle.ps1');
  await writeFile(script, `param([string]$Target, [switch]$Directory)
Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
public static class FixtureHandle {
  [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
  private static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
  public static SafeFileHandle Open(string name, bool directory) {
    var handle = CreateFileW(name, directory ? 1u : 0x80000000u, directory ? 3u : 1u, IntPtr.Zero, 3u, directory ? 0x02000000u : 0u, IntPtr.Zero);
    if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
    return handle;
  }
}
'@
$handle = [FixtureHandle]::Open($Target, [bool]$Directory)
try {
  [Console]::WriteLine('LOCK_READY')
  [Console]::Out.Flush()
  [Console]::ReadLine() | Out-Null
} finally { $handle.Dispose() }
`);
  const child = spawn('rtk', ['proxy', 'powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', script, target, ...(directory ? ['-Directory'] : [])], {
    cwd: root, windowsHide: true, stdio: ['pipe', 'pipe', 'pipe'],
  });
  let output = '';
  let released = false;
  const exited = new Promise((resolve, reject) => {
    child.once('error', reject);
    child.once('exit', (code, signal) => resolve({ code, signal }));
  });
  const release = async () => {
    if (released) return;
    released = true;
    child.stdin.end('\n');
    const result = await exited;
    assert.equal(result.code, 0, output);
  };
  try {
    await new Promise((resolve, reject) => {
      const timeout = setTimeout(() => reject(new Error(`Windows fixture handle did not become ready: ${output}`)), 15000);
      child.stdout.on('data', bytes => {
        output += bytes;
        if (output.includes('LOCK_READY')) { clearTimeout(timeout); resolve(); }
      });
      child.stderr.on('data', bytes => { output += bytes; });
      child.once('error', error => { clearTimeout(timeout); reject(error); });
      child.once('exit', code => { clearTimeout(timeout); reject(new Error(`Windows fixture exited before holding a handle (${code}): ${output}`)); });
    });
  } catch (error) { await release(); throw error; }
  return release;
}

test('real TypeScript builds use content and artifact identities, preserve successful output on failure, and propagate dependencies', async t => {
  let ensureBuiltPackages;
  try {
    ({ ensureBuiltPackages } = await import('./ensure-built-packages.mjs'));
  } catch (error) {
    if (error.code !== 'ERR_MODULE_NOT_FOUND') throw error;
    assert.fail('ensureBuiltPackages must compile changed/missing packages before consumers run');
  }
  const root = await fixture(t);
  await t.test('first build compiles all packages in dependency order and produces executable exports', async () => {
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.equal(behavior(root), 4);
  });
  await t.test('unchanged input never invokes RTK or TypeScript and leaves output and success record untouched', async () => {
    const before = await snapshot(root);
    const output = path.join(root, 'packages/physics-core/dist/index.js');
    const beforeStat = await stat(output);
    const originalPath = process.env.PATH;
    process.env.PATH = path.join(root, 'no-executables');
    try {
      assert.deepEqual((await ensureBuiltPackages(root)).built, []);
    } finally {
      process.env.PATH = originalPath;
    }
    assert.equal(await snapshot(root), before);
    assert.equal((await stat(output)).mtimeMs, beforeStat.mtimeMs);
  });
  await t.test('source edits with identical timestamps change executable behavior and rebuild dependents', async () => {
    const source = path.join(root, 'packages/physics-core/src/index.ts');
    const before = await stat(source);
    await writeFile(source, '// emitted comment\nexport const value: number = 7;\n');
    await utimes(source, before.atime, before.mtime);
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.equal(behavior(root), 10);
  });
  await t.test('tampered JavaScript and missing declaration exports are rebuilt from source', async () => {
    await writeFile(path.join(root, 'packages/naval-core/dist/index.js'), 'export const value = 900;\n');
    await rm(path.join(root, 'packages/naval-core/dist/index.d.ts'));
    assert.ok((await ensureBuiltPackages(root)).built.includes(names[1]));
    assert.equal(behavior(root), 10);
    assert.match(await readFile(path.join(root, 'packages/naval-core/dist/index.d.ts'), 'utf8'), /export declare const value: number/);
  });
  await t.test('unknown manual files in existing output are preserved and stop replacement', async () => {
    const manual = path.join(root, 'packages/adventure-encounters/dist/player-notes.txt');
    const beforeRecord = await snapshot(root);
    await writeFile(manual, 'manual file must survive\n');
    await assert.rejects(ensureBuiltPackages(root), /Unrecognized output files.*player-notes\.txt/s);
    assert.equal(await readFile(manual, 'utf8'), 'manual file must survive\n');
    assert.equal(await snapshot(root), beforeRecord);
    await rm(manual);
  });
  await t.test('missing output directory is recreated, and obsolete compiled source artifacts are removed', async () => {
    const source = path.join(root, 'packages/adventure-encounters/src/obsolete.ts');
    await writeFile(source, 'export const obsolete = true;\n');
    await ensureBuiltPackages(root);
    await rm(source);
    await ensureBuiltPackages(root);
    await assert.rejects(stat(path.join(root, 'packages/adventure-encounters/dist/obsolete.js')), { code: 'ENOENT' });
    await rm(path.join(root, 'packages/adventure-encounters/dist'), { recursive: true });
    assert.deepEqual((await ensureBuiltPackages(root)).built, [names[3]]);
    assert.equal(behavior(root), 10);
  });
  await t.test('extended configuration and compiler bytes invalidate builds independently of source timestamps', async () => {
    const base = path.join(root, 'tsconfig.base.json');
    const config = JSON.parse(await readFile(base, 'utf8'));
    config.compilerOptions.removeComments = true;
    await writeFile(base, JSON.stringify(config));
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.doesNotMatch(await readFile(path.join(root, 'packages/physics-core/dist/index.js'), 'utf8'), /emitted comment/);
    const compiler = path.join(root, 'node_modules/typescript/lib/_tsc.js');
    await writeFile(compiler, (await readFile(compiler, 'utf8')) + '\n// identity changed\n');
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
  });
  await t.test('package export metadata and dependency metadata invalidate successful identities', async () => {
    const metadata = path.join(root, 'packages/physics-core/package.json');
    const pkg = JSON.parse(await readFile(metadata, 'utf8'));
    pkg.version = '1.0.1';
    await writeFile(metadata, JSON.stringify(pkg));
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    pkg.exports['./extra'] = { types: './dist/extra.d.ts', default: './dist/extra.js' };
    await writeFile(metadata, JSON.stringify(pkg));
    await writeFile(path.join(root, 'packages/physics-core/src/extra.ts'), 'export const extra = 42;\n');
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.match(await readFile(path.join(root, 'packages/physics-core/dist/extra.js'), 'utf8'), /extra = 42/);
  });
  await t.test('source-based encounter exports still require valid compiled artifacts', async () => {
    const metadata = path.join(root, 'packages/adventure-encounters/package.json');
    const pkg = JSON.parse(await readFile(metadata, 'utf8'));
    pkg.exports = { '.': './src/index.ts' };
    await writeFile(metadata, JSON.stringify(pkg));
    assert.deepEqual((await ensureBuiltPackages(root)).built, [names[3]]);
    await rm(path.join(root, 'packages/adventure-encounters/dist/index.js'));
    assert.deepEqual((await ensureBuiltPackages(root)).built, [names[3]]);
    pkg.exports = { '.': { types: './dist/index.d.ts', default: './dist/index.js' } };
    await writeFile(metadata, JSON.stringify(pkg));
    await ensureBuiltPackages(root);
  });
  await t.test('missing newly declared export fails validation without replacing old output or success record', async () => {
    const metadata = path.join(root, 'packages/adventure-encounters/package.json');
    const original = await readFile(metadata, 'utf8');
    const pkg = JSON.parse(original);
    pkg.exports['./missing'] = './dist/missing.js';
    const beforeRecord = await snapshot(root);
    const beforeOutput = await readFile(path.join(root, 'packages/adventure-encounters/dist/index.js'), 'utf8');
    await writeFile(metadata, JSON.stringify(pkg));
    await assert.rejects(ensureBuiltPackages(root), /compilation produced missing output or exports/);
    assert.equal(await snapshot(root), beforeRecord);
    assert.equal(await readFile(path.join(root, 'packages/adventure-encounters/dist/index.js'), 'utf8'), beforeOutput);
    await writeFile(metadata, original);
    assert.deepEqual((await ensureBuiltPackages(root)).built, []);
  });
  await t.test('compiler failure and CLI nonzero exit keep old success identity and complete old output', async () => {
    const source = path.join(root, 'packages/physics-core/src/index.ts');
    const output = path.join(root, 'packages/physics-core/dist/index.js');
    const beforeRecord = await snapshot(root);
    const beforeOutput = await readFile(output, 'utf8');
    await writeFile(source, 'export const value: number = "broken";\n');
    await assert.rejects(ensureBuiltPackages(root), /physics-core.*compilation failed/s);
    assert.equal(await snapshot(root), beforeRecord);
    assert.equal(await readFile(output, 'utf8'), beforeOutput);
    assert.equal(behavior(root), 10);
    const result = runNode(root, [cli, '--root', root]);
    assert.equal(result.status, 1, result.output);
    assert.match(result.output, /physics-core.*compilation failed/s);
    assert.equal(await snapshot(root), beforeRecord);
    await writeFile(source, 'export const value: number = 9;\n');
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.equal(behavior(root), 12);
  });
  await t.test('actual npm root and app lifecycle hooks block consumers on compiler failure', async () => {
    await mkdir(path.join(root, 'tools/workspace'), { recursive: true });
    await cp(cli, path.join(root, 'tools/workspace/ensure-built-packages.mjs'));
    await writeFile(path.join(root, 'consume.mjs'), "import { value } from '@ming-armada/adventure-encounters';\nimport { writeFileSync } from 'node:fs';\nwriteFileSync(new URL('./consumer-ran.txt', import.meta.url), String(value));\n");
    const rootScripts = JSON.parse(await readFile(path.join(repository, 'package.json'), 'utf8')).scripts;
    rootScripts.test = rootScripts['test:game'] = 'rtk proxy node consume.mjs';
    await writeFile(path.join(root, 'package.json'), JSON.stringify({ private: true, type: 'module', scripts: rootScripts }));
    const app = path.join(root, 'apps/game-client');
    await mkdir(app, { recursive: true });
    const appScripts = JSON.parse(await readFile(path.join(repository, 'apps/game-client/package.json'), 'utf8')).scripts;
    for (const command of ['dev', 'test', 'check', 'build', 'build:wechat']) appScripts[command] = 'rtk proxy node ../../consume.mjs';
    await writeFile(path.join(app, 'package.json'), JSON.stringify({ private: true, type: 'module', scripts: appScripts }));
    await writeFile(path.join(root, 'packages/physics-core/src/index.ts'), 'export const value: number = "broken";\n');
    const beforeRecord = await snapshot(root);
    for (const args of [
      ['run', 'test'], ['run', 'test:game'], ['run', 'dev:game-client'], ['run', 'check:game'], ['run', 'build:game-client'], ['run', 'build:wechat-game'], ['run', 'build'],
      ['--prefix', 'apps/game-client', 'run', 'test'],
    ]) {
      const result = spawnSync('rtk', ['proxy', 'npm', ...args], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 60000 });
      assert.ifError(result.error);
      assert.equal(result.status, 1, result.stdout + result.stderr);
      assert.match(result.stdout + result.stderr, /physics-core.*compilation failed/s);
      await assert.rejects(stat(path.join(root, 'consumer-ran.txt')), { code: 'ENOENT' });
      assert.equal(await snapshot(root), beforeRecord);
    }
    await writeFile(path.join(root, 'packages/physics-core/src/index.ts'), 'export const value: number = 11;\n');
    const result = spawnSync('rtk', ['proxy', 'npm', 'run', 'dev:game-client'], { cwd: root, encoding: 'utf8', windowsHide: true, timeout: 60000 });
    assert.ifError(result.error);
    assert.equal(result.status, 0, result.stdout + result.stderr);
    assert.equal(await readFile(path.join(root, 'consumer-ran.txt'), 'utf8'), '14');
  });
  await t.test('output junctions or symbolic links cannot redirect build replacement', async () => {
    const output = path.join(root, 'packages/physics-core/dist');
    const retained = path.join(root, 'retained-output');
    const before = await readFile(path.join(output, 'index.js'), 'utf8');
    await rename(output, retained);
    await symlink(retained, output, process.platform === 'win32' ? 'junction' : 'dir');
    await assert.rejects(ensureBuiltPackages(root), /Symbolic link\/reparse build path refused/);
    assert.equal(await readFile(path.join(retained, 'index.js'), 'utf8'), before);
  });
});

const windowsOnly = process.platform === 'win32' ? false : 'Win32 directory/file sharing is only available on Windows';

test('Windows directory read handle blocks directory rename but generated-file promotion still succeeds', { skip: windowsOnly }, async t => {
  const { ensureBuiltPackages } = await import('./ensure-built-packages.mjs');
  const root = await fixture(t);
  await writeFile(path.join(root, 'packages/physics-core/src/obsolete.ts'), 'export const obsolete = true;\n');
  await ensureBuiltPackages(root);
  const output = path.join(root, 'packages/physics-core/dist');
  const release = await holdWindowsHandle(root, output);
  try {
    await assert.rejects(rename(output, output + '.probe'), error => ['EPERM', 'EACCES', 'EBUSY'].includes(error.code));
    const probe = path.join(output, 'child-write-probe.txt');
    await writeFile(probe, 'child files remain writable\n');
    await rename(probe, probe + '.renamed');
    await rm(probe + '.renamed');
    await writeFile(path.join(root, 'packages/physics-core/src/index.ts'), 'export const value: number = 7;\n');
    await rm(path.join(root, 'packages/physics-core/src/obsolete.ts'));
    await mkdir(path.join(root, 'packages/physics-core/src/nested'), { recursive: true });
    await writeFile(path.join(root, 'packages/physics-core/src/nested/added.ts'), 'export const nested = 42;\n');
    assert.deepEqual((await ensureBuiltPackages(root)).built, names);
    assert.equal(behavior(root), 10);
    await assert.rejects(stat(path.join(output, 'obsolete.js')), { code: 'ENOENT' });
    await assert.rejects(stat(path.join(output, 'obsolete.d.ts')), { code: 'ENOENT' });
    assert.match(await readFile(path.join(output, 'nested/added.js'), 'utf8'), /nested = 42/);
    assert.deepEqual((await ensureBuiltPackages(root)).built, []);
  } finally { await release(); }
});

test('Windows blocked generated-file replacement rolls back earlier writes and creations without a fresh record', { skip: windowsOnly }, async t => {
  const { ensureBuiltPackages } = await import('./ensure-built-packages.mjs');
  const root = await fixture(t);
  const source = path.join(root, 'packages/physics-core/src');
  const output = path.join(root, 'packages/physics-core/dist');
  await writeFile(path.join(source, 'extra.ts'), 'export const extra = 1;\n');
  await ensureBuiltPackages(root);
  const beforeRecord = await snapshot(root);
  const beforeExtra = await readFile(path.join(output, 'extra.js'), 'utf8');
  const beforeIndex = await readFile(path.join(output, 'index.js'), 'utf8');
  const releaseDirectory = await holdWindowsHandle(root, output);
  let releaseFile;
  try {
    releaseFile = await holdWindowsHandle(root, path.join(output, 'index.js'), false);
    await writeFile(path.join(source, 'added.ts'), 'export const added = 99;\n');
    await mkdir(path.join(source, 'added-directory'), { recursive: true });
    await writeFile(path.join(source, 'added-directory/nested.ts'), 'export const nested = 99;\n');
    await writeFile(path.join(source, 'extra.ts'), 'export const extra = 2;\n');
    await writeFile(path.join(source, 'index.ts'), 'export const value: number = 7;\n');
    await assert.rejects(ensureBuiltPackages(root), /index\.js/s);
    assert.equal(await snapshot(root), beforeRecord);
    assert.equal(await readFile(path.join(output, 'extra.js'), 'utf8'), beforeExtra);
    assert.equal(await readFile(path.join(output, 'index.js'), 'utf8'), beforeIndex);
    await assert.rejects(stat(path.join(output, 'added.js')), { code: 'ENOENT' });
    await assert.rejects(stat(path.join(output, 'added.d.ts')), { code: 'ENOENT' });
    await assert.rejects(stat(path.join(output, 'added-directory')), { code: 'ENOENT' });
    assert.equal(behavior(root), 4);
  } finally {
    try { if (releaseFile) await releaseFile(); }
    finally { await releaseDirectory(); }
  }
  assert.deepEqual((await ensureBuiltPackages(root)).built, names);
  assert.equal(behavior(root), 10);
});
