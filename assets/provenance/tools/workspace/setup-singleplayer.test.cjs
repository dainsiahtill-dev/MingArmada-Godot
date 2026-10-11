const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const { createHash } = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const scriptSource = path.resolve(__dirname, '../../scripts/setup-singleplayer.ps1');
const windowsOnly = process.platform === 'win32' ? false : 'Requires Windows PowerShell CLI';
const sentinel = 'existing player source must survive\n';

function fixture(t) {
  const temporaryRoot = fs.mkdtempSync(path.join(os.tmpdir(), 'mingarmada-setup-cli-test-'));
  t.after(() => {
    // This test owns only its freshly allocated temporary directory.
    assert.equal(path.dirname(path.resolve(temporaryRoot)), path.resolve(os.tmpdir()));
    assert.match(path.basename(temporaryRoot), /^mingarmada-setup-cli-test-/);
    fs.rmSync(temporaryRoot, { recursive: true, force: true });
  });
  const repository = path.join(temporaryRoot, 'script repository');
  const caller = path.join(temporaryRoot, 'unrelated caller');
  const explicitWorkspace = path.join(temporaryRoot, 'explicit workspace');
  for (const directory of [repository, caller, explicitWorkspace]) fs.mkdirSync(directory);
  fs.mkdirSync(path.join(repository, 'scripts'));
  fs.mkdirSync(path.join(repository, 'tools', 'workspace'), { recursive: true });
  const script = path.join(repository, 'scripts', 'setup-singleplayer.ps1');
  fs.copyFileSync(scriptSource, script);

  const lock = '{}\n';
  for (const workspace of [repository, explicitWorkspace]) {
    fs.writeFileSync(path.join(workspace, 'package-lock.json'), lock);
    fs.mkdirSync(path.join(workspace, 'existing-source'));
    fs.writeFileSync(path.join(workspace, 'existing-source', 'player-source.txt'), sentinel);
  }
  fs.writeFileSync(path.join(repository, 'tools', 'workspace', 'empty.patch'), '');
  fs.writeFileSync(path.join(repository, 'tools', 'workspace', 'source-lock.json'), JSON.stringify({
    version: 1,
    npmRegistry: 'https://registry.npmjs.org/',
    rootLockFile: 'package-lock.json',
    rootLockSha256: createHash('sha256').update(lock).digest('hex'),
    packages: [{
      id: 'preflight-preservation-fixture',
      path: 'existing-source',
      baseSha: '0'.repeat(40),
      sourceTree: '0'.repeat(40),
      patch: 'tools/workspace/empty.patch',
      patchSha256: createHash('sha256').update('').digest('hex'),
      patchBytes: 0,
    }],
  }));
  // An actual existing directory without .git stops preflight before cloning,
  // npm installation or building. No path-resolution logic is stubbed or copied.
  return { temporaryRoot, repository, caller, explicitWorkspace, script };
}

function runCli(script, cwd, arguments = []) {
  const result = spawnSync('rtk', [
    'proxy', 'powershell', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
    '-File', script, ...arguments,
  ], { cwd, encoding: 'utf8', timeout: 15000, windowsHide: true });
  assert.ifError(result.error);
  return { status: result.status, output: result.stdout + result.stderr };
}

function assertPreservedPreflight(result, workspace) {
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Existing directory is not an independent Git package; preserved:/);
  // Error formatting can wrap a long Windows path across lines.
  assert.ok(result.output.replace(/[\r\n]/g, '').includes(path.join(workspace, 'existing-source')), result.output);
  assert.equal(fs.readFileSync(path.join(workspace, 'existing-source', 'player-source.txt'), 'utf8'), sentinel);
  assert.equal(fs.existsSync(path.join(workspace, 'existing-source', '.git')), false);
  assert.equal(fs.existsSync(path.join(workspace, 'node_modules')), false);
}

test('CLI omitted WorkspaceRoot reaches preservation preflight in the script repository', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const result = runCli(f.script, f.repository, ['-Install', '-Build']);
  assertPreservedPreflight(result, f.repository);
});

test('CLI omitted WorkspaceRoot uses the script repository when launched from another directory', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const result = runCli(f.script, f.caller, ['-Install', '-Build']);
  assertPreservedPreflight(result, f.repository);
  assert.deepEqual(fs.readdirSync(f.caller), []);
});

test('CLI explicit WorkspaceRoot preserves the chosen workspace rather than the script repository', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const result = runCli(f.script, f.caller, ['-WorkspaceRoot', f.explicitWorkspace, '-Install', '-Build']);
  assertPreservedPreflight(result, f.explicitWorkspace);
  assert.equal(fs.readFileSync(path.join(f.repository, 'existing-source', 'player-source.txt'), 'utf8'), sentinel);
});

test('CLI explicit drive root is rejected before workspace writes', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const result = runCli(f.script, f.caller, ['-WorkspaceRoot', path.parse(f.temporaryRoot).root]);
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Choose a workspace directory, not a drive root/);
  assert.equal(fs.readFileSync(path.join(f.repository, 'existing-source', 'player-source.txt'), 'utf8'), sentinel);
});

test('CLI explicit nonexistent workspace is rejected without creating it', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const missingWorkspace = path.join(f.temporaryRoot, 'missing workspace');
  const result = runCli(f.script, f.caller, ['-WorkspaceRoot', missingWorkspace]);
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Workspace directory does not exist:/);
  assert.equal(fs.existsSync(missingWorkspace), false);
});

test('CLI refuses a junction workspace while preserving its source', { skip: windowsOnly }, (t) => {
  const f = fixture(t);
  const junction = path.join(f.temporaryRoot, 'junction workspace');
  fs.symlinkSync(f.explicitWorkspace, junction, 'junction');
  const result = runCli(f.script, f.caller, ['-WorkspaceRoot', junction, '-Install', '-Build']);
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Reparse-point path is not supported; directory preserved:/);
  assert.equal(fs.readFileSync(path.join(f.explicitWorkspace, 'existing-source', 'player-source.txt'), 'utf8'), sentinel);
});

function runGit(directory, arguments) {
  const result = spawnSync('rtk', ['proxy', 'git', '-C', directory, ...arguments], {
    encoding: 'utf8', timeout: 15000, windowsHide: true,
  });
  assert.ifError(result.error);
  assert.equal(result.status, 0, result.stdout + result.stderr);
  return result.stdout.trimEnd();
}

function lockedGitFixture(t, { trackedOutput = false, marked = false } = {}) {
  const f = fixture(t);
  const target = path.join(f.repository, 'existing-source');
  fs.mkdirSync(path.join(target, 'src'));
  fs.writeFileSync(path.join(target, 'src', 'known.ts'), 'export const known = true;\n');
  if (trackedOutput) {
    fs.mkdirSync(path.join(target, 'node_modules'));
    fs.writeFileSync(path.join(target, 'node_modules', 'tracked-output.txt'), 'locked tracked output\n');
  }
  runGit(target, ['init', '--quiet']);
  runGit(target, ['config', 'core.autocrlf', 'false']);
  const emptyExcludes = path.join(f.temporaryRoot, 'empty-git-excludes');
  fs.writeFileSync(emptyExcludes, '');
  runGit(target, ['config', 'core.excludesFile', emptyExcludes]);
  const remote = 'https://example.invalid/locked-cli-fixture.git';
  runGit(target, ['config', 'remote.origin.url', remote]);
  runGit(target, ['add', '--all']);
  const sourceTree = runGit(target, ['write-tree']);
  // Synthetic Git objects exist only inside this test's temporary package.
  // Plumbing creates a clean HEAD without hooks, a remote fetch or root commits.
  const baseSha = runGit(target, [
    '-c', 'user.name=Setup CLI Fixture', '-c', 'user.email=setup-cli@example.invalid',
    'commit-tree', sourceTree, '-m', 'Synthetic locked source fixture',
  ]);
  runGit(target, ['update-ref', 'HEAD', baseSha]);
  const sourceFiles = runGit(target, ['ls-files', '--stage']).split('\n').map((line) => {
    const match = /^(\d+) ([0-9a-f]{40}) 0\t(.+)$/.exec(line);
    assert.ok(match, line);
    return { mode: match[1], blob: match[2], path: match[3] };
  });
  const sourceSha256 = createHash('sha256').update(sourceFiles.map((file) =>
    `${file.mode} ${file.blob}\t${file.path}\n`).join('')).digest('hex');
  const manifestPath = path.join(f.repository, 'tools', 'workspace', 'source-lock.json');
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const packageLock = { ...manifest.packages[0], remote, baseSha, sourceTree, sourceFiles, sourceSha256 };
  manifest.packages = [packageLock];
  fs.writeFileSync(manifestPath, JSON.stringify(manifest));
  if (marked) {
    fs.writeFileSync(path.join(target, '.git', 'mingarmada-source-lock.json'), JSON.stringify({
      version: 1, id: packageLock.id, baseSha, patchSha256: packageLock.patchSha256,
      sourceTree, sourceSha256,
    }));
  }
  assert.equal(runGit(target, ['status', '--porcelain', '--untracked-files=all']), '');
  return { ...f, target, sourceTree, baseSha, packageLock };
}

function writePackageFile(target, relative, content) {
  const file = path.join(target, ...relative.split('/'));
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, content);
  return file;
}

const generatedPaths = [
  'node_modules/.vite/vitest/da39a3ee5e6b4b0d3255bfef95601890afd80709/results.json',
  'dist/game.js',
  'dist-ssr/server.js',
  'coverage/coverage-final.json',
  'node_modules/cache with spaces/asset.js',
];

for (const relative of generatedPaths) {
  test(`CLI reuses locked source with untracked generated output ${relative}`, { skip: windowsOnly }, (t) => {
    const f = lockedGitFixture(t);
    const outputContent = 'generated output must survive\n';
    const generatedFile = writePackageFile(f.target, relative, outputContent);
    const beforeStatus = runGit(f.target, ['status', '--porcelain', '--untracked-files=all']);
    assert.match(beforeStatus, /^\?\? /);
    const result = runCli(f.script, f.caller);
    assert.equal(result.status, 0, result.output);
    assert.match(result.output, /Verified and reused preflight-preservation-fixture:/);
    assert.equal(fs.readFileSync(generatedFile, 'utf8'), outputContent);
    assert.equal(fs.readFileSync(path.join(f.target, 'player-source.txt'), 'utf8'), sentinel);
    assert.equal(runGit(f.target, ['status', '--porcelain', '--untracked-files=all']), beforeStatus);
    assert.equal(runGit(f.target, ['write-tree']), f.sourceTree);
    assert.equal(runGit(f.target, ['rev-parse', 'HEAD']), f.baseSha);
    assert.equal(fs.existsSync(path.join(f.target, '.git', 'mingarmada-source-lock.json')), false);
  });
}

const refusedChanges = [
  { name: 'tracked source edit', relative: 'src/known.ts', staged: false, trackedOutput: false },
  { name: 'staged source edit', relative: 'src/known.ts', staged: true, trackedOutput: false },
  { name: 'untracked source file', relative: 'src/new.ts', staged: false, trackedOutput: false },
  { name: 'nested source node_modules file', relative: 'src/node_modules/new.ts', staged: false, trackedOutput: false },
  { name: 'similar output prefix source', relative: 'dist-source/new.ts', staged: false, trackedOutput: false },
  { name: 'tracked output edit', relative: 'node_modules/tracked-output.txt', staged: false, trackedOutput: true },
];

for (const change of refusedChanges) {
  test(`CLI refuses ${change.name} even alongside untracked generated cache`, { skip: windowsOnly }, (t) => {
    const f = lockedGitFixture(t, { trackedOutput: change.trackedOutput });
    const changedContent = 'unapproved change must survive\n';
    const changedFile = writePackageFile(f.target, change.relative, changedContent);
    const generatedFile = writePackageFile(f.target, generatedPaths[0], 'cache stays\n');
    if (change.staged) runGit(f.target, ['add', '--', change.relative]);
    const beforeStatus = runGit(f.target, ['status', '--porcelain', '--untracked-files=all']);
    const beforeTree = runGit(f.target, ['write-tree']);
    const result = runCli(f.script, f.caller);
    assert.equal(result.status, 1, result.output);
    assert.match(result.output, /Unmarked dirty package refused; existing changes preserved:/);
    assert.equal(fs.readFileSync(changedFile, 'utf8'), changedContent);
    assert.equal(fs.readFileSync(generatedFile, 'utf8'), 'cache stays\n');
    assert.equal(runGit(f.target, ['status', '--porcelain', '--untracked-files=all']), beforeStatus);
    assert.equal(runGit(f.target, ['write-tree']), beforeTree);
  });
}

test('CLI still checks actual locked file hashes in a marked package with generated cache', { skip: windowsOnly }, (t) => {
  const f = lockedGitFixture(t, { marked: true });
  const changedFile = writePackageFile(f.target, 'src/known.ts', 'changed locked source\n');
  const generatedFile = writePackageFile(f.target, generatedPaths[0], 'cache stays\n');
  const result = runCli(f.script, f.caller);
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Source differs from lock; file preserved:/);
  assert.equal(fs.readFileSync(changedFile, 'utf8'), 'changed locked source\n');
  assert.equal(fs.readFileSync(generatedFile, 'utf8'), 'cache stays\n');
  assert.equal(runGit(f.target, ['write-tree']), f.sourceTree);
});

test('CLI still rejects untracked source in a marked package with generated cache', { skip: windowsOnly }, (t) => {
  const f = lockedGitFixture(t, { marked: true });
  const changedFile = writePackageFile(f.target, 'src/new.ts', 'unapproved new source\n');
  const generatedFile = writePackageFile(f.target, generatedPaths[0], 'cache stays\n');
  const result = runCli(f.script, f.caller);
  assert.equal(result.status, 1, result.output);
  assert.match(result.output, /Untracked source is present; preserved:/);
  assert.equal(fs.readFileSync(changedFile, 'utf8'), 'unapproved new source\n');
  assert.equal(fs.readFileSync(generatedFile, 'utf8'), 'cache stays\n');
  assert.equal(runGit(f.target, ['write-tree']), f.sourceTree);
});
