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
      const formatted = marker.includes('%d');
      const prefix = formatted ? marker.slice(0, marker.indexOf('%d')) : marker;
      const pattern = formatted ? new RegExp('^' + marker.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replaceAll('%d', '\\d+') + '$') : null;
      const completions = output.split(/\r?\n/).filter(line => line.startsWith(prefix));
      if (completions.length !== 1) reasons.push(`expected one ${JSON.stringify(marker)} completion, saw ${completions.length}`);
      else {
        const line = completions[0];
        const failures = line.match(/\bfailures\s*=\s*(\d+)\b/);
        const success = failures ? Number(failures[1]) === 0 : /\bPASS\s*\(\s*0\s*\)\s*$/.test(line) || /_PASS\s+assertions=\d+(?:\s+cases=\d+)?\s*$/.test(line);
        if (pattern && !pattern.test(line)) reasons.push(`malformed completion: ${line}`);
        else if (!success) reasons.push(`unsuccessful completion: ${line}`);
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
  assert.equal(assess({ ...success, stdout: 'NAVAL_SIMULATION_PASS assertions=51559 cases=72\n' }, 'NAVAL_SIMULATION_PASS assertions=').passed, true);
  assert.equal(assess({ ...success, stdout: 'NAVAL_SIMULATION_FAIL count=1\n' }, 'NAVAL_SIMULATION_PASS assertions=').passed, false);
  assert.equal(assess({ ...success, stdout: 'NAVAL_INVARIANTS_PASS assertions=72\n', stderr: 'SCRIPT ERROR: broken\n' }, 'NAVAL_INVARIANTS_PASS assertions=').passed, false);
  assert.equal(completionMarker('print("NAVAL_SIMULATION_PASS assertions=", assertions)\nprint("NAVAL_SIMULATION_FAIL count=", failures.size())'), 'NAVAL_SIMULATION_PASS assertions=', 'completion discovery must not choose a later failure branch');
  assert.equal(completionMarker('print("NAVAL_INVARIANTS_PASS assertions=", assertions)\nfor failure in failures: print("NAVAL_INVARIANT_FAIL ", failure)'), 'NAVAL_INVARIANTS_PASS assertions=', 'failure-variable names must not turn diagnostic prints into success markers');
  const formattedMarker = completionMarker('print("EXAMPLE_TESTS assertions=%d failures=%d" % [assertions, failures])');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\n' }, formattedMarker).passed, true, 'formatted source markers must recognize actual numeric output');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=2\n' }, formattedMarker).passed, false, 'formatted completion still rejects assertion failures');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS_OTHER assertions=8 failures=0\n' }, formattedMarker).passed, false, 'formatted marker retains exact test identity');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\nEXAMPLE_TESTS assertions=8 failures=0\n' }, formattedMarker).passed, false, 'formatted completions must occur exactly once');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\nEXAMPLE_TESTS assertions=bad failures=0\n' }, formattedMarker).passed, false, 'malformed duplicate must not disappear from completion count');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=bad failures=0\n' }, formattedMarker).passed, false, 'formatted assertions field must be numeric');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0 ignored\n' }, formattedMarker).passed, false, 'formatted output must match the entire declared format');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\n', stderr: 'SCRIPT ERROR: Invalid call.\n' }, formattedMarker).passed, false, 'formatted completion cannot hide script errors');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\n', exitCode: 1 }, formattedMarker).passed, false, 'formatted completion cannot hide nonzero process exit');
  assert.equal(assess({ ...success, stdout: 'EXAMPLE_TESTS assertions=8 failures=0\n', timedOut: true }, formattedMarker).passed, false, 'formatted completion cannot hide timeouts');
  assert.equal(assess({ ...success, stdout: 'quoted.test (v2) assertions=8 failures=0\n' }, completionMarker("print('quoted.test (v2) assertions=%d failures=%d'%[assertions,failures])")).passed, true, 'single-quoted compact formats retain literal regex punctuation');
  assert.equal(assess({ ...success, stdout: 'quotedXtest v2 assertions=8 failures=0\n' }, completionMarker("print('quoted.test (v2) assertions=%d failures=%d'%[assertions,failures])")).passed, false, 'regex punctuation in test identity must remain literal');
  assert.equal(completionMarker('print("EXAMPLE_TESTS assertions=%d failures=%d")'), '', 'unformatted placeholders are not a supported numeric completion format');
  console.log('VERIFICATION_RUNNER_SELF_TEST assertions=29 failures=0');
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
  const prints = source.split(/\r?\n/).filter(line => /\bprint\s*\(/.test(line) && /failures|["']PASS["']|_PASS\b/.test(line));
  const literals = prints.map(line => {
    const print = line.match(/\bprint\s*\(\s*(["'])([^"']+)\1/);
    if (!print) return '';
    const literal = print[2];
    if (literal.includes('%d') && (!/^\s*%/.test(line.slice(print.index + print[0].length)) || /%(?!d)/.test(literal) || literal.startsWith('%d'))) return '';
    return literal;
  }).filter(Boolean);
  const explicitPass = [...new Set(literals.filter(literal => /_PASS\b/.test(literal)))];
  if (explicitPass.length > 1) return '';
  if (explicitPass.length === 1) return explicitPass[0];
  return literals.filter(literal => !/_FAIL\b/.test(literal)).at(-1) ?? '';
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
  const evidence = { schemaVersion: 1, startedAtUtc: new Date().toISOString(), projectRoot: root, godot, timeoutMs, mode: 'headless', filter: filter ?? null, discoveredTests: allTests.map(file => path.relative(root, file).replaceAll('\\', '/')), runnerSelfTest: '29 assertions, failures=0', runs: [] };
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
  // Focused visual repairs must not erase the retained full-suite report.
  const output = path.resolve(root, value('--output') ?? 'docs/migration/evidence/verification.json');
  await mkdir(path.dirname(output), { recursive: true });
  await writeFile(output, JSON.stringify(evidence, null, 2) + '\n');
  console.log(`GODOT_VERIFICATION selected=${tests.length} passed=${evidence.summary.passed} failures=${evidence.summary.failed} evidence=${output}`);
  process.exitCode = evidence.summary.passedAll ? 0 : 1;
}

if (process.argv.includes('--self-test')) selfTest();
else await main().catch(error => { console.error(error.stack); process.exitCode = 1; });
