#!/usr/bin/env node
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { readdir, readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const defaultGodot = 'C:/Users/dains/Downloads/Godot_v4.7.2-stable_win64.exe/Godot_v4.7.2-stable_win64.exe';

function assess(result, marker) {
  const reasons = [];
  const output = `${result.stdout}\n${result.stderr}`.replace(/\u001b\[[0-9;]*m/g, '');
  if (result.timedOut) reasons.push('timed out');
  if (result.processError) reasons.push(`process error: ${result.processError}`);
  if (result.exitCode !== 0) reasons.push(`exit code ${result.exitCode}`);
  const diagnostic = output.split(/\r?\n/).find(line => /SCRIPT ERROR:|\bERROR:|\b(?:Parse|Compile) Error:|Failed to load (?:script|resource)|Error loading/i.test(line));
  if (diagnostic) reasons.push(diagnostic.trim());
  if (marker !== null) {
    if (!marker) reasons.push('test has no supported completion marker');
    else {
      const completions = output.split(/\r?\n/).filter(line => line.startsWith(marker));
      if (completions.length !== 1) reasons.push(`expected one ${JSON.stringify(marker)} completion, saw ${completions.length}`);
      else {
        const line = completions[0];
        const failures = line.match(/\bfailures\s*=\s*(\d+)\b/);
        if (failures ? Number(failures[1]) !== 0 : !/\bPASS\s*\(\s*0\s*\)\s*$/.test(line)) reasons.push(`unsuccessful completion: ${line}`);
      }
    }
  }
  return { passed: reasons.length === 0, reasons };
}

function selfTest() {
  const success = { exitCode: 0, stdout: 'EXAMPLE_TESTS assertions=5 failures=0\n', stderr: '', timedOut: false };
  assert.equal(assess(success, 'EXAMPLE_TESTS').passed, true);
  assert.equal(assess({ ...success, stderr: 'SCRIPT ERROR: Invalid call.\n' }, 'EXAMPLE_TESTS').passed, false, 'Godot can exit 0 after a script error');
  assert.equal(assess({ ...success, stderr: 'ERROR: Failed to load script.\n' }, 'EXAMPLE_TESTS').passed, false, 'Resource errors invalidate a printed pass');
  assert.equal(assess({ ...success, stdout: 'Godot Engine\n' }, 'EXAMPLE_TESTS').passed, false, 'Missing completion is not success');
  assert.equal(assess({ ...success, stdout: 'OTHER_TESTS failures=0\n' }, 'EXAMPLE_TESTS').passed, false, 'Another test marker cannot complete this test');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS failures=2\n' }, 'EXAMPLE_TESTS').passed, false, 'Nonzero assertions fail even with exit 0');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS failures=0\nEXAMPLE_TESTS failures=1\n' }, 'EXAMPLE_TESTS').passed, false, 'Duplicate completions are ambiguous');
  assert.equal(assess({ ...success, stdout: 'save compatibility v2: PASS (0)\n' }, 'save compatibility v2: ').passed, true);
  assert.equal(assess({ ...success, stdout: 'save compatibility v2: PASS (1)\n' }, 'save compatibility v2: ').passed, false);
  assert.equal(assess({ ...success, exitCode: 1 }, 'EXAMPLE_TESTS').passed, false);
  assert.equal(assess({ ...success, timedOut: true }, 'EXAMPLE_TESTS').passed, false);
  console.log('VERIFICATION_RUNNER_SELF_TEST assertions=11 failures=0');
}

async function discover(directory) {
  const tests = [];
  for (const entry of await readdir(directory, { withFileTypes: true })) {
    const full = path.join(directory, entry.name);
    if (entry.isDirectory()) tests.push(...await discover(full));
    else if (/^test_.*\.gd$/.test(entry.name)) tests.push(full);
  }
  return tests.sort();
}

// Source supplies only each test's identity; success still comes from actual output.
function completionMarker(source) {
  const prints = source.split(/\r?\n/).filter(line => /\bprint\s*\(/.test(line) && /failures|["']PASS["']/.test(line));
  return prints.at(-1)?.match(/\bprint\s*\(\s*["']([^"']+)["']/)?.[1] ?? '';
}

async function runGodot(godot, arguments_, timeoutMs) {
  const started = Date.now();
  return new Promise(resolve => {
    let stdout = '', stderr = '', timedOut = false, processError = '';
    const child = spawn('rtk', ['proxy', godot, ...arguments_], { cwd: root, windowsHide: true, shell: false, stdio: ['ignore', 'pipe', 'pipe'] });
    child.stdout.setEncoding('utf8');
    child.stderr.setEncoding('utf8');
    child.stdout.on('data', chunk => { stdout += chunk; });
    child.stderr.on('data', chunk => { stderr += chunk; });
    child.on('error', error => { processError = error.message; });
    const timer = setTimeout(() => {
      timedOut = true;
      if (process.platform === 'win32') {
        const killer = spawn('rtk', ['proxy', 'taskkill', '/PID', String(child.pid), '/T', '/F'], { windowsHide: true, shell: false, stdio: 'ignore' });
        killer.on('error', () => child.kill('SIGKILL'));
      } else child.kill('SIGKILL');
    }, timeoutMs);
    child.on('close', (exitCode, signal) => {
      clearTimeout(timer);
      resolve({ exitCode, signal, timedOut, processError, durationMs: Date.now() - started, stdout, stderr });
    });
  });
}

async function main() {
  selfTest();
  const args = process.argv.slice(2);
  const value = name => {
    const index = args.indexOf(name);
    if (index < 0) return undefined;
    if (!args[index + 1] || args[index + 1].startsWith('--')) throw new Error(`${name} needs a value`);
    return args[index + 1];
  };
  const godot = path.resolve(value('--godot') ?? process.env.GODOT_EXE ?? defaultGodot);
  const timeoutMs = Number(value('--timeout-ms') ?? 60000);
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 60000) throw new Error('--timeout-ms must be between 1000 and 60000');
  const filter = value('--filter');
  const allTests = await discover(path.join(root, 'tests'));
  const tests = allTests.filter(file => !filter || path.basename(file).includes(filter));
  if (!tests.length) throw new Error('No tests discovered or selected');
  const evidence = { schemaVersion: 1, startedAtUtc: new Date().toISOString(), projectRoot: root, godot, timeoutMs, mode: 'headless', filter: filter ?? null, discoveredTests: allTests.map(file => path.relative(root, file).replaceAll('\\', '/')), runnerSelfTest: '11 assertions, failures=0', runs: [] };
  const version = await runGodot(godot, ['--headless', '--version'], timeoutMs);
  evidence.version = { ...version, ...assess(version, null) };
  for (const file of tests) {
    const test = path.relative(root, file).replaceAll('\\', '/');
    const marker = completionMarker(await readFile(file, 'utf8'));
    const result = await runGodot(godot, ['--headless', '--path', root, '--script', `res://${test}`], timeoutMs);
    const verdict = assess(result, marker);
    evidence.runs.push({ test, completionMarker: marker, arguments: ['--headless', '--path', root, '--script', `res://${test}`], ...result, ...verdict });
    console.log(`${verdict.passed ? 'PASS' : 'FAIL'} ${test} (${result.durationMs}ms)${verdict.reasons.length ? ': ' + verdict.reasons.join('; ') : ''}`);
  }
  evidence.finishedAtUtc = new Date().toISOString();
  evidence.summary = { selected: tests.length, passed: evidence.runs.filter(run => run.passed).length, failed: evidence.runs.filter(run => !run.passed).length, passedAll: evidence.version.passed && evidence.runs.every(run => run.passed) };
  const output = path.join(root, 'docs/migration/evidence/verification.json');
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(evidence, null, 2) + '\n');
  console.log(`GODOT_VERIFICATION selected=${tests.length} passed=${evidence.summary.passed} failures=${evidence.summary.failed} evidence=${output}`);
  process.exitCode = evidence.summary.passedAll ? 0 : 1;
}

if (process.argv.includes('--self-test')) selfTest();
else await main().catch(error => { console.error(error.stack); process.exitCode = 1; });
