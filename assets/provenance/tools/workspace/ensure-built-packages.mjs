import { spawnSync } from 'node:child_process';
import { createHash, randomUUID } from 'node:crypto';
import { existsSync } from 'node:fs';
import { createRequire } from 'node:module';
import { lstat, mkdir, readFile, readdir, rename, rm, rmdir, stat, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { setTimeout as delay } from 'node:timers/promises';
import { fileURLToPath } from 'node:url';

const packageIds = ['physics-core', 'naval-core', 'adventure-core', 'adventure-encounters'];
const cacheRelative = '.cache/workspace-builds.json';
const ownFile = fileURLToPath(import.meta.url);
const defaultRoot = path.resolve(path.dirname(ownFile), '../..');
const digest = value => createHash('sha256').update(value).digest('hex');
const portable = value => value.split(path.sep).join('/');

async function optionalRead(file) {
  try { return await readFile(file); }
  catch (error) { if (error.code === 'ENOENT') return null; throw error; }
}

async function filesIn(directory) {
  const files = [];
  try {
    for (const entry of (await readdir(directory, { withFileTypes: true })).sort((a, b) => a.name.localeCompare(b.name))) {
      const file = path.join(directory, entry.name);
      if (entry.isDirectory()) files.push(...await filesIn(file));
      else if (entry.isFile()) files.push(file);
      else throw new Error(`Build identity requires regular files: ${file}`);
    }
  } catch (error) { if (error.code !== 'ENOENT') throw error; }
  return files;
}

async function fileIdentity(files, root) {
  const rows = [];
  for (const file of [...new Set(files)].sort()) {
    const bytes = await optionalRead(file);
    rows.push([portable(path.relative(root, file)), bytes === null ? null : digest(bytes)]);
  }
  return digest(JSON.stringify(rows));
}

function exportTargets(pkg) {
  const values = [];
  function visit(value) {
    if (typeof value === 'string') values.push(value);
    else if (Array.isArray(value)) value.forEach(visit);
    else if (value && typeof value === 'object') Object.values(value).forEach(visit);
  }
  visit(pkg.exports);
  visit(pkg.main);
  visit(pkg.types);
  return [...new Set(values)];
}

function inside(directory, file) {
  const relative = path.relative(directory, file);
  return relative !== '' && !relative.startsWith(`..${path.sep}`) && relative !== '..' && !path.isAbsolute(relative);
}

async function assertOwnedPath(root, file) {
  file = path.resolve(file);
  if (!inside(root, file)) throw new Error(`Build path escapes workspace: ${file}`);
  for (let current = file; ; current = path.dirname(current)) {
    try {
      if ((await lstat(current)).isSymbolicLink()) throw new Error(`Symbolic link/reparse build path refused; files preserved: ${current}`);
    } catch (error) { if (error.code !== 'ENOENT') throw error; }
    if (current === root) break;
  }
}

async function renameWithRetry(from, to) {
  // Windows scanners may briefly hold generated files. Keep atomic rename; never unlink the destination.
  for (let attempt = 0; ; attempt++) {
    try { await rename(from, to); return; }
    catch (error) {
      if (attempt === 5 || !['EPERM', 'EACCES', 'EBUSY'].includes(error.code)) throw error;
      await delay(25 * 2 ** attempt);
    }
  }
}

async function replaceGeneratedFile(root, file, bytes, mode) {
  await assertOwnedPath(root, file);
  await mkdir(path.dirname(file), { recursive: true });
  const temporary = `${file}.replace-${randomUUID()}.tmp`;
  await assertOwnedPath(root, temporary);
  try {
    await writeFile(temporary, bytes, { mode });
    await renameWithRetry(temporary, file);
  } finally { await rm(temporary, { force: true }); }
}

async function assertOutputOwnership(outputRoot, knownOutputs, packageName) {
  const files = await filesIn(outputRoot);
  const unknown = files.map(file => portable(path.relative(outputRoot, file))).filter(file => !knownOutputs.has(file));
  if (unknown.length) throw new Error(`Unrecognized output files in ${packageName}; files preserved: ${unknown.join(', ')}`);
  return files;
}

// A directory may have a long-lived Windows handle without DELETE sharing while its children remain writable.
// This fallback is a per-file transaction, not a directory-atomic swap. Keep the old tree until all writes validate.
async function promoteGeneratedFiles(root, packageRoot, outputRoot, staged, backup, knownOutputs, targets, expectedFiles, compiledHash, packageName) {
  await assertOwnedPath(root, outputRoot);
  const previousFiles = await assertOutputOwnership(outputRoot, knownOutputs, packageName);
  const previousHash = await fileIdentity(previousFiles, outputRoot);
  const previous = new Map();
  const emitted = new Map();
  const touched = [];
  const createdDirectories = new Set();
  let retainBackup = false;
  await mkdir(backup);
  try {
    for (const file of previousFiles) {
      const relative = portable(path.relative(outputRoot, file));
      const bytes = await readFile(file);
      const mode = (await stat(file)).mode & 0o7777;
      previous.set(relative, { bytes, mode });
      const saved = path.join(backup, relative);
      await mkdir(path.dirname(saved), { recursive: true });
      await writeFile(saved, bytes, { mode });
    }
    if (await fileIdentity(await filesIn(backup), backup) !== previousHash || await fileIdentity(await filesIn(outputRoot), outputRoot) !== previousHash) {
      throw new Error(`${packageName} output changed during backup; files preserved`);
    }
    for (const file of await filesIn(staged)) {
      const relative = portable(path.relative(staged, file));
      emitted.set(relative, { bytes: await readFile(file), mode: (await stat(file)).mode & 0o7777 });
    }
    try {
      for (const [relative, next] of emitted) {
        const old = previous.get(relative);
        if (old?.bytes.equals(next.bytes)) continue;
        const destination = path.join(outputRoot, relative);
        await assertOwnedPath(root, destination);
        for (let directory = path.dirname(destination); directory !== outputRoot; directory = path.dirname(directory)) {
          if (!existsSync(directory)) createdDirectories.add(directory);
        }
        touched.push(relative);
        await replaceGeneratedFile(root, destination, next.bytes, old?.mode ?? next.mode);
      }
      for (const relative of previous.keys()) {
        if (emitted.has(relative)) continue;
        const destination = path.join(outputRoot, relative);
        await assertOwnedPath(root, destination);
        touched.push(relative);
        await rm(destination);
      }
      if (await outputIdentity(packageRoot, outputRoot, targets, expectedFiles) !== compiledHash) {
        throw new Error(`${packageName} generated output failed validation after file promotion`);
      }
    } catch (error) {
      // Any unexpected rollback failure must leave the durable old-byte backup available.
      retainBackup = true;
      const rollbackErrors = [];
      for (const relative of touched.reverse()) {
        try {
          const destination = path.join(outputRoot, relative);
          const old = previous.get(relative);
          if (old) {
            const current = await optionalRead(destination);
            if (!current?.equals(old.bytes)) await replaceGeneratedFile(root, destination, old.bytes, old.mode);
          }
          else { await assertOwnedPath(root, destination); await rm(destination, { force: true }); }
        } catch (rollbackError) { rollbackErrors.push(rollbackError); }
      }
      for (const directory of [...createdDirectories].sort((a, b) => b.length - a.length)) {
        try {
          await assertOwnedPath(root, directory);
          // Remove only directories allocated by this transaction and only while empty.
          if ((await readdir(directory)).length === 0) await rmdir(directory);
        } catch (rollbackError) { if (rollbackError.code !== 'ENOENT') rollbackErrors.push(rollbackError); }
      }
      try {
        if (await fileIdentity(await filesIn(outputRoot), outputRoot) !== previousHash) rollbackErrors.push(new Error('Restored generated tree differs from its old byte identity'));
      } catch (rollbackError) { rollbackErrors.push(rollbackError); }
      if (rollbackErrors.length) {
        retainBackup = true;
        throw new AggregateError([error, ...rollbackErrors], `${packageName} file promotion failed: ${error.message}; rollback failed, old byte backup retained: ${backup}`);
      }
      retainBackup = false;
      throw new Error(`${packageName} file promotion failed: ${error.message}; rollback restored old output`, { cause: error });
    }
  } finally {
    if (!retainBackup) await rm(backup, { recursive: true, force: true });
  }
}

async function outputIdentity(packageRoot, outputRoot, targets, expectedFiles, stagedRoot = outputRoot) {
  const emitted = await filesIn(stagedRoot);
  if (!emitted.length) return null;
  const available = new Set(emitted.map(file => portable(path.relative(stagedRoot, file))));
  for (const expected of expectedFiles) {
    if (!inside(outputRoot, expected)) throw new Error(`Compiler output must stay inside ${outputRoot}: ${expected}`);
    if (!available.has(portable(path.relative(outputRoot, expected)))) return null;
  }
  const exported = [];
  for (const target of targets) {
    if (!target.startsWith('./') || target.includes('*')) throw new Error(`Unsupported package export target: ${target}`);
    const resolved = path.resolve(packageRoot, target);
    if (!inside(packageRoot, resolved)) throw new Error(`Package export escapes its package: ${target}`);
    const file = inside(outputRoot, resolved) ? path.join(stagedRoot, path.relative(outputRoot, resolved)) : resolved;
    const bytes = await optionalRead(file);
    if (bytes === null || !(await stat(file)).isFile()) return null;
    exported.push([target, digest(bytes)]);
  }
  return digest(JSON.stringify({ tree: await fileIdentity(emitted, stagedRoot), exported }));
}

function findDependency(packageRoot, name) {
  let directory = packageRoot;
  for (;;) {
    const candidate = path.join(directory, 'node_modules', name, 'package.json');
    if (existsSync(candidate)) return candidate;
    const parent = path.dirname(directory);
    if (parent === directory) throw new Error(`Installed dependency is missing: ${name}`);
    directory = parent;
  }
}

async function dependencyIdentity(packageRoot, pkg, records, root) {
  const identities = [];
  const dependencies = { ...pkg.dependencies, ...pkg.peerDependencies, ...pkg.optionalDependencies };
  for (const name of Object.keys(dependencies).sort()) {
    if (records[name]) {
      identities.push([name, dependencies[name], records[name]]);
      continue;
    }
    const metadata = findDependency(packageRoot, name);
    const installed = JSON.parse(await readFile(metadata, 'utf8'));
    const files = [metadata];
    for (const target of exportTargets(installed)) {
      if (target.startsWith('./') && !target.includes('*')) files.push(path.resolve(path.dirname(metadata), target));
    }
    identities.push([name, dependencies[name], await fileIdentity(files, root)]);
  }
  return identities;
}

function configuration(ts, configFile) {
  const configurationFiles = new Set();
  const host = {
    ...ts.sys,
    readFile(file) {
      configurationFiles.add(path.resolve(file));
      return ts.sys.readFile(file);
    },
    onUnRecoverableConfigFileDiagnostic(diagnostic) { throw new Error(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n')); },
  };
  const parsed = ts.getParsedCommandLineOfConfigFile(configFile, { noEmitOnError: true }, host);
  if (!parsed || parsed.errors.length) {
    throw new Error(`Invalid build configuration ${configFile}: ${parsed?.errors.map(error => ts.flattenDiagnosticMessageText(error.messageText, '\n')).join('\n')}`);
  }
  if (parsed.projectReferences?.length || parsed.options.incremental || parsed.options.composite) {
    throw new Error(`Build configuration requires a separate project-reference/incremental contract: ${configFile}`);
  }
  return { parsed, configurationFiles: [...configurationFiles] };
}

async function writeCache(cacheFile, records) {
  await mkdir(path.dirname(cacheFile), { recursive: true });
  const temporary = `${cacheFile}.${randomUUID()}.tmp`;
  try {
    await writeFile(temporary, JSON.stringify({ version: 1, packages: records }, null, 2) + '\n');
    await renameWithRetry(temporary, cacheFile);
  } finally { await rm(temporary, { force: true }); }
}

/** Ensure active package exports match their source/config/compiler/dependency content.
 * Returns built/reused package names and their last successful content identities.
 * Compilation is always the installed root TypeScript CLI, through RTK; no install or server startup.
 */
export async function ensureBuiltPackages(root = defaultRoot) {
  root = path.resolve(root);
  const require = createRequire(path.join(root, 'package.json'));
  const compiler = require.resolve('typescript/lib/tsc.js');
  const ts = require('typescript');
  const compilerRoot = path.resolve(path.dirname(compiler), '..');
  const compilerIdentity = await fileIdentity([
    path.join(compilerRoot, 'package.json'), ...await filesIn(path.join(compilerRoot, 'lib')), ...await filesIn(path.join(compilerRoot, 'bin')),
  ], root);
  const cacheFile = path.join(root, cacheRelative);
  await assertOwnedPath(root, cacheFile);
  let records = {};
  try {
    const cached = JSON.parse((await optionalRead(cacheFile))?.toString() || '{}');
    if (cached.version === 1 && cached.packages && typeof cached.packages === 'object') records = cached.packages;
  } catch (error) { if (!(error instanceof SyntaxError)) throw error; }
  const built = [], reused = [], verified = {};
  const utilityIdentity = digest(await readFile(ownFile));
  const lockIdentity = await fileIdentity([path.join(root, 'package-lock.json')], root);
  for (const id of packageIds) {
    const packageRoot = path.join(root, 'packages', id);
    const metadata = path.join(packageRoot, 'package.json');
    const pkg = JSON.parse(await readFile(metadata, 'utf8'));
    const { parsed, configurationFiles } = configuration(ts, path.join(packageRoot, 'tsconfig.json'));
    const outputRoot = parsed.options.outDir && path.resolve(parsed.options.outDir);
    if (!outputRoot || !inside(packageRoot, outputRoot) || parsed.options.noEmit) {
      throw new Error(`Package ${pkg.name} needs an emitted output directory inside its package`);
    }
    await assertOwnedPath(root, outputRoot);
    const program = ts.createProgram(parsed.fileNames, parsed.options);
    const sourceFiles = program.getSourceFiles().map(source => source.fileName);
    if (sourceFiles.some(file => file === outputRoot || inside(outputRoot, file))) {
      throw new Error(`Package ${pkg.name} cannot use its output as source input`);
    }
    const expectedFiles = parsed.fileNames.flatMap(file => ts.getOutputFileNames(parsed, file, !ts.sys.useCaseSensitiveFileNames));
    const targets = exportTargets(pkg);
    const dependencies = await dependencyIdentity(packageRoot, pkg, verified, root);
    const inputFiles = [metadata, ...configurationFiles, ...sourceFiles];
    const inputIdentity = async () => digest(JSON.stringify({
      utilityIdentity, compilerIdentity, lockIdentity, sources: await fileIdentity([...inputFiles, ...await filesIn(path.join(packageRoot, 'src'))], root), dependencies,
      options: parsed.options, expectedFiles: expectedFiles.map(file => portable(path.relative(root, file))), targets,
      command: ['tsc', '-p', 'tsconfig.json', '--noEmitOnError', '--outDir', '<staged-output>'],
    }));
    const inputHash = await inputIdentity();
    const artifactHash = await outputIdentity(packageRoot, outputRoot, targets, expectedFiles);
    if (records[pkg.name]?.inputHash === inputHash && artifactHash && records[pkg.name]?.artifactHash === artifactHash) {
      reused.push(pkg.name);
      verified[pkg.name] = records[pkg.name];
      continue;
    }
    const knownOutputs = new Set([
      ...expectedFiles.map(file => portable(path.relative(outputRoot, file))),
      ...(Array.isArray(records[pkg.name]?.outputs) ? records[pkg.name].outputs : []),
    ]);
    await assertOutputOwnership(outputRoot, knownOutputs, pkg.name);
    // A sibling output directory preserves relative source-map paths. Failed compilations never touch live dist.
    const staged = `${outputRoot}.build-${randomUUID()}`;
    const backup = `${outputRoot}.previous-${randomUUID()}`;
    await assertOwnedPath(root, staged);
    await assertOwnedPath(root, backup);
    let backedUp = false;
    let promoted = false;
    try {
      const result = spawnSync('rtk', ['proxy', process.execPath, compiler, '-p', path.join(packageRoot, 'tsconfig.json'), '--noEmitOnError', '--outDir', staged], {
        cwd: root, encoding: 'utf8', windowsHide: true, maxBuffer: 16 * 1024 * 1024,
      });
      if (result.error || result.status !== 0) {
        throw new Error(`${pkg.name} compilation failed (${result.status ?? result.error?.code}):\n${result.stdout || ''}${result.stderr || ''}${result.error?.message || ''}`);
      }
      const compiledHash = await outputIdentity(packageRoot, outputRoot, targets, expectedFiles, staged);
      if (!compiledHash) throw new Error(`${pkg.name} compilation produced missing output or exports`);
      if (await inputIdentity() !== inputHash) throw new Error(`${pkg.name} source changed during compilation; retry before starting consumers`);
      const outputs = (await filesIn(staged)).map(file => portable(path.relative(staged, file)));
      await assertOwnedPath(root, outputRoot);
      await assertOutputOwnership(outputRoot, knownOutputs, pkg.name);
      let fallback = false;
      try { await renameWithRetry(outputRoot, backup); backedUp = true; }
      catch (error) {
        if (['EPERM', 'EACCES', 'EBUSY'].includes(error.code)) fallback = true;
        else if (error.code !== 'ENOENT') throw error;
      }
      if (fallback) {
        await promoteGeneratedFiles(root, packageRoot, outputRoot, staged, backup, knownOutputs, targets, expectedFiles, compiledHash, pkg.name);
        promoted = true;
      } else {
        try { await renameWithRetry(staged, outputRoot); promoted = true; }
        catch (error) {
          if (backedUp) { await renameWithRetry(backup, outputRoot); backedUp = false; }
          throw error;
        }
      }
      const record = { inputHash, artifactHash: compiledHash, outputs };
      records[pkg.name] = record;
      await writeCache(cacheFile, records);
      verified[pkg.name] = record;
      built.push(pkg.name);
    } finally {
      // Only UUID-scoped generated directories created/moved by this invocation are removed.
      await rm(staged, { recursive: true, force: true });
      if (backedUp && promoted) await rm(backup, { recursive: true, force: true });
    }
  }
  return { built, reused, packages: verified };
}

if (process.argv[1] && path.resolve(process.argv[1]) === ownFile) {
  const args = process.argv.slice(2);
  try {
    if (args.length && (args.length !== 2 || args[0] !== '--root')) throw new Error('Usage: ensure-built-packages.mjs [--root WORKSPACE]');
    const result = await ensureBuiltPackages(args[1] || defaultRoot);
    console.log(JSON.stringify(result, null, 2));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
