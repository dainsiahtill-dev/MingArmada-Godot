import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const helperPath = fileURLToPath(new URL('../modules/scene_engine/ocean/macro_wave_optics.gdshaderinc', import.meta.url));
const descriptorPath = fileURLToPath(new URL('../modules/contracts/wave_descriptor.gd', import.meta.url));
const tau = 2 * Math.PI;

// These are GLSL scalar intrinsics, not an implementation of visibility.
// The return expression, thresholds and branches execute from production text.
function smoothstep(edge0, edge1, value) {
  const fraction = Math.max(0, Math.min(1, (value - edge0) / (edge1 - edge0)));
  return fraction * fraction * (3 - 2 * fraction);
}

function shaderScalar(name, expectedParameters = ['phase_footprint']) {
  assert.ok(existsSync(helperPath), 'production macro-wave optical footprint helper exists');
  const original = readFileSync(helperPath, 'utf8');
  const source = original.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const declaration = source.match(new RegExp(`\\bfloat\\s+${name}\\s*\\(([^)]*)\\)\\s*\\{`));
  assert.ok(declaration, `production shader exposes ${name}`);
  const start = declaration.index + declaration[0].length;
  let end = start;
  let nesting = 1;
  while (end < source.length && nesting > 0) {
    if (source[end] === '{') nesting += 1;
    if (source[end] === '}') nesting -= 1;
    end += 1;
  }
  assert.equal(nesting, 0, 'actual GLSL function has a complete body');
  const parameters = declaration[1].split(',').map(value => value.trim().replace(/^float\s+/, ''));
  assert.deepEqual(parameters, expectedParameters, `${name} consumes the requested scalar inputs`);
  const globals = [...source.slice(0, declaration.index).matchAll(/\bconst\s+float\s+(\w+)\s*=\s*([^;]+);/g)]
    .map(([, key, expression]) => `const ${key} = ${expression};`).join('\n');
  const body = source.slice(start, end - 1)
    .replace(/\bconst\s+float\s+/g, 'const ')
    .replace(/\bfloat\s+(\w+)/g, 'let $1')
    .replace(/\bfloat\s*\(/g, 'Number(');
  const run = new Function(...parameters, 'smoothstep', 'max', 'min', 'clamp', 'abs', 'PI', 'TAU', `${globals}\n${body}`);
  const visible = (...values) => run(...values, smoothstep, Math.max, Math.min,
    (x, a, b) => Math.max(a, Math.min(b, x)), Math.abs, Math.PI, tau);
  return { visible, hash: createHash('sha256').update(original).digest('hex') };
}

function sourceComponents() {
  const source = readFileSync(descriptorPath, 'utf8');
  const data = source.match(/\bconst\s+ORIGINAL_COMPONENTS\s*:=\s*(\[[\s\S]*?\n\])/);
  assert.ok(data, 'long/short wave fixtures come from the retained production descriptor');
  const components = JSON.parse(data[1].replace(/,\s*]/g, ']'));
  assert.equal(components.length, 5);
  for (const component of components) assert.ok(component.length === 4 && component.every(Number.isFinite));
  return components;
}

// Independent Fourier units: a world-pixel displacement projected onto the
// source wave vector gives phase radians. Never differentiate sampled cosines.
function phaseFootprint(component, dx, dy) {
  const dot = derivative => derivative[0] * component[1] + derivative[1] * component[2];
  return Math.max(Math.abs(dot(dx)), Math.abs(dot(dy)));
}

const { visible, hash } = shaderScalar('reference_macro_wave_visibility');
const { visible: grazing } = shaderScalar('reference_macro_grazing_visibility', ['view_elevation', 'view_distance']);
const components = sourceComponents();

test('resolved near macro normals retain full optical amplitude', () => {
  for (const phase of [0, 1e-9, tau / 96, tau / 48, tau / 24]) {
    assert.ok(Math.abs(visible(phase) - 1) < 1e-12, `near footprint ${phase} remains full`);
  }
});

test('unresolved phase footprints cannot reappear at or above the cutoff', () => {
  for (const phase of [tau / 4, tau / 2, Math.PI, tau, 10, 20]) {
    assert.equal(visible(phase), 0, `unresolved footprint ${phase} is fully filtered`);
  }
});

test('one full phase cycle across a pixel filters even when endpoint cosines agree', () => {
  const component = components[2];
  const displacement = [tau / component[1], 0];
  const delta = phaseFootprint(component, displacement, [0, 0]);
  const initialPhase = 0.27;
  assert.ok(Math.abs(Math.cos(initialPhase + delta) - Math.cos(initialPhase)) < 1e-12,
    'endpoint cosine variance really is zero in this regression fixture');
  assert.ok(Math.abs(delta - tau) < 1e-12, 'unwrapped phase still covers a whole cycle');
  assert.equal(visible(delta), 0, 'a cosine endpoint coincidence never revives the unresolved wave');
});

test('visibility stays finite, bounded, monotone and continuous over zero to twenty radians', () => {
  let previous = visible(0);
  for (let index = 1; index <= 20000; index += 1) {
    const phase = index / 1000;
    const next = visible(phase);
    assert.ok(Number.isFinite(next) && next >= 0 && next <= 1, `finite coverage at ${phase}`);
    assert.ok(next <= previous + 1e-12, `coverage cannot rise at ${phase}`);
    assert.ok(previous - next < 0.0015, `no hard transition across a 0.001-radian step at ${phase}`);
    previous = next;
  }
  for (const boundary of [tau / 24, tau / 4]) {
    assert.ok(Math.abs(visible(boundary - 1e-6) - visible(boundary + 1e-6)) < 1e-5,
      'each resolution boundary is continuous from both sides');
  }
});

test('the same world footprint keeps the retained 251m wave and hides the 42m wave', () => {
  const long = components[0];
  const short = components[3];
  const wavelength = component => tau / Math.hypot(component[1], component[2]);
  assert.ok(wavelength(long) > 250 && wavelength(long) < 252);
  assert.ok(wavelength(short) > 42 && wavelength(short) < 43);
  const dx = [10, 10];
  const dy = [0, 0.5];
  const longPhase = phaseFootprint(long, dx, dy);
  const shortPhase = phaseFootprint(short, dx, dy);
  assert.ok(visible(longPhase) > 0.9, 'broad flow remains visible under that camera footprint');
  assert.equal(visible(shortPhase), 0, 'fine carrier cannot produce far-water stripe normals');
  console.log('MACRO_WAVE_OPTICS_EVIDENCE', JSON.stringify({ sourceSha256: hash,
    long: { wavelength: wavelength(long), phase: longPhase, visibility: visible(longPhase) },
    short: { wavelength: wavelength(short), phase: shortPhase, visibility: visible(shortPhase) } }));
});

test('anisotropic projection respects wave direction rather than isotropic pixel distance', () => {
  const component = components[0];
  const magnitude = Math.hypot(component[1], component[2]);
  const parallel = [100 * component[1] / magnitude, 100 * component[2] / magnitude];
  const perpendicular = [100 * component[2] / magnitude, -100 * component[1] / magnitude];
  assert.ok(Math.abs(Math.hypot(...parallel) - Math.hypot(...perpendicular)) < 1e-12);
  assert.equal(visible(phaseFootprint(component, parallel, [0, 0])), 0,
    'parallel displacement crosses unresolved periods');
  assert.equal(visible(phaseFootprint(component, perpendicular, [0, 0])), 1,
    'same length perpendicular displacement does not smear that wave');
  assert.equal(visible(phaseFootprint(component, parallel, perpendicular)),
    visible(phaseFootprint(component, perpendicular, parallel)), 'either screen derivative can own the footprint');
});

test('grazing adaptation leaves every near view through 180m intact', () => {
  for (const distance of [-10, 0, 1, 60, 179.999, 180]) {
    for (const elevation of [-1, -0.4, -0.05, 0, 0.001, 0.04, 0.05, 0.2, 0.4, 1]) {
      assert.equal(grazing(elevation, distance), 1, `near low view ${elevation}/${distance} keeps optical normals`);
    }
  }
});

test('steep views retain macro optics at every distance', () => {
  for (const elevation of [0.4, 0.401, 0.6, 1, -0.4, -0.401, -0.6, -1]) {
    for (const distance of [-10, 0, 180, 300, 799, 800, 3000, 1e6]) {
      assert.equal(grazing(elevation, distance), 1, `steep ${elevation}/${distance} remains unchanged`);
    }
  }
});

test('distant horizon views reject the unresolved grazing macro reflection', () => {
  for (const elevation of [-0.05, -0.01, 0, 0.01, 0.05]) {
    for (const distance of [800, 900, 3000, 1e6]) {
      assert.equal(grazing(elevation, distance), 0, `far grazing ${elevation}/${distance} has no long optical stripe`);
    }
  }
});

test('grazing visibility is bounded and decreases continuously with distance', () => {
  for (const elevation of [0, 0.01, 0.05, 0.1, 0.2, 0.3, 0.4, 0.6]) {
    let previous = grazing(elevation, 0);
    for (let distance = 1; distance <= 2000; distance += 1) {
      const next = grazing(elevation, distance);
      assert.ok(Number.isFinite(next) && next >= 0 && next <= 1);
      assert.ok(next <= previous + 1e-12, 'moving farther cannot restore grazing stripes');
      assert.ok(previous - next < 0.003, 'distance gate cannot pop across a one-metre camera step');
      previous = next;
    }
  }
  for (const boundary of [180, 800]) {
    assert.ok(Math.abs(grazing(0, boundary - 1e-4) - grazing(0, boundary + 1e-4)) < 1e-5);
  }
});

test('grazing visibility rises continuously with angle and is sign symmetric', () => {
  for (const distance of [0, 100, 180, 200, 300, 500, 799, 800, 1500]) {
    let previous = grazing(0, distance);
    for (let index = 1; index <= 1000; index += 1) {
      const elevation = index / 1000;
      const next = grazing(elevation, distance);
      assert.ok(Number.isFinite(next) && next >= 0 && next <= 1);
      assert.ok(next + 1e-12 >= previous, 'a steeper view cannot erase visible macro flow');
      assert.ok(next - previous < 0.005, 'angle adaptation cannot pop across a .001 elevation step');
      assert.equal(grazing(-elevation, distance), next, 'above/below views use elevation magnitude consistently');
      previous = next;
    }
  }
  for (const boundary of [0.05, 0.4]) {
    assert.ok(Math.abs(grazing(boundary - 1e-6, 1000) - grazing(boundary + 1e-6, 1000)) < 1e-5);
  }
  console.log('MACRO_GRAZING_EVIDENCE', JSON.stringify({ sourceSha256: hash,
    nearHorizon: grazing(0, 180), farHorizon: grazing(0, 800),
    farSteep: grazing(0.4, 800), middleDistance: grazing(0, 490),
    middleAngle: grazing(0.225, 800), combinedMiddle: grazing(0.225, 490) }));
});
