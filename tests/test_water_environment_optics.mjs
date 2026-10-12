import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';

const helperPath = fileURLToPath(new URL('../modules/scene_engine/ocean/water_environment_optics.gdshaderinc', import.meta.url));
const waterPath = fileURLToPath(new URL('../modules/scene_engine/ocean/reference_game_water.gdshader', import.meta.url));
const receiptPath = fileURLToPath(new URL('../Temp/water-environment-optics-math.json', import.meta.url));
const clamp = (value, low, high) => Math.max(low, Math.min(high, value));

// Evaluate the actual scalar GLSL body. This contains intrinsics only, never
// a second implementation of the production Fresnel or its thresholds.
function shaderScalar(name) {
  assert.ok(existsSync(helperPath), 'formal ocean requires independent rough environment optics');
  const original = readFileSync(helperPath, 'utf8');
  const source = original.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
  const declaration = source.match(new RegExp(`float\\s+${name}\\s*\\(([^)]*)\\)\\s*\\{([^}]+)\\}`));
  assert.ok(declaration, `actual helper implements ${name}`);
  const parameters = declaration[1].split(',').map(value => value.trim().replace(/^float\s+/, ''));
  const body = declaration[2].replace(/\bconst\s+float\s+/g, 'const ').replace(/\bfloat\s+/g, 'let ');
  const run = new Function(...parameters, 'pow', 'clamp', body);
  return { run: (...values) => run(...values, Math.pow, clamp), hash: createHash('sha256').update(original).digest('hex') };
}

test('rough environment preserves normal-incidence reflection and bounds back-facing white bands', () => {
  const { run: fresnel, hash } = shaderScalar('reference_water_environment_fresnel');
  assert.equal(fresnel(1, 0.52), 0.02, 'real reflection remains present even looking down');
  assert.equal(fresnel(0, 0.52), 0.52, 'a grazing ripple never becomes 100% white sky');
  assert.equal(fresnel(-0.2, 0.52), 0.52, 'a local ripple facing away cannot exceed the grazing budget');
  assert.equal(fresnel(2, 0.52), 0.02, 'roundoff above one has a finite physical minimum');
  assert.equal(fresnel(0, 100), 1, 'external material tuning is bounded');
  assert.equal(fresnel(0, -100), 0.02, 'external tuning cannot silently disable reflection');
  writeFileSync(receiptPath, JSON.stringify({ gpuRendered: false, sourceSha256: hash,
    normalIncidence: fresnel(1, 0.52), horizon: fresnel(0, 0.52),
    backFacing: fresnel(-0.2, 0.52), intermediate: fresnel(0.2, 0.52) }, null, 2) + '\n');
});

test('environment envelope varies continuously with incidence and material tuning', () => {
  const { run: fresnel } = shaderScalar('reference_water_environment_fresnel');
  for (const peak of [0.02, 0.3, 0.52, 0.8, 1]) {
    let previous = fresnel(-0.2, peak);
    for (let index = -199; index <= 1200; index += 1) {
      const next = fresnel(index / 1000, peak);
      assert.ok(Number.isFinite(next) && next >= 0.02 && next <= peak + 1e-12);
      assert.ok(next <= previous + 1e-12, 'steeper views never increase reflected white coverage');
      assert.ok(previous - next < 0.005, 'incidence transitions cannot pop at a .001 step');
      previous = next;
    }
  }
  for (const cosine of [-0.2, 0, 0.15, 0.5, 1]) {
    let previous = fresnel(cosine, -0.1);
    for (let index = -99; index <= 1100; index += 1) {
      const next = fresnel(cosine, index / 1000);
      assert.ok(next >= previous - 1e-12 && next - previous < 0.00101);
      previous = next;
    }
  }
});

test('full mirror tuning retains the independent physical Schlick limiting cases', () => {
  const { run: fresnel } = shaderScalar('reference_water_environment_fresnel');
  // Independent reference law, deliberately used only as an oracle at full
  // mirror tuning. The production shader body supplies every actual result.
  for (const cosine of [0, 0.01, 0.05, 0.1, 0.2, 0.4, 0.8, 1]) {
    assert.ok(Math.abs(fresnel(cosine, 1) - (0.02 + 0.98 * (1 - cosine) ** 5)) < 1e-12);
  }
});

test('a real grazing ripple keeps blue water instead of replacing it with sky', () => {
  const { run: fresnel } = shaderScalar('reference_water_environment_fresnel');
  const source = readFileSync(helperPath, 'utf8');
  const gain = Number(source.match(/uniform\s+float\s+water_environment_ripple_gain[^;]*=\s*([\d.]+)\s*;/)?.[1]);
  const peak = Number(source.match(/uniform\s+float\s+water_environment_horizon_weight[^;]*=\s*([\d.]+)\s*;/)?.[1]);
  assert.ok(gain > 0 && gain <= 0.25, 'environment still contains softer advected ripple detail');
  assert.ok(peak >= 0.35 && peak <= 0.6, 'environment remains visible with blue-water space');
  // An independent unit-vector construction: ray elevation .2, a -.3 slope
  // toward the horizon. Full texture slopes flip NoV negative in this case.
  const view = [Math.sqrt(0.96), 0.2];
  const noV = slope => (slope * view[0] + view[1]) / Math.hypot(slope, 1);
  const oldWeight = 0.02 + 0.98 * (1 - Math.max(noV(-0.3), 0)) ** 5;
  const newWeight = fresnel(noV(-0.3 * gain), peak);
  assert.equal(oldWeight, 1, 'regression really exercises the former complete sky replacement');
  assert.ok(newWeight > 0.05 && newWeight < 0.3, 'same wave now preserves the blue body and real reflection');
  const body = [0.12, 0.48, 0.66], sky = [0.88, 0.94, 0.96];
  const color = body.map((channel, index) => channel * (1 - newWeight) + sky[index] * newWeight);
  assert.ok(color[0] < 0.35 && color[2] - color[0] > 0.35, 'target remains blue rather than neutral cloud white');
});

test('formal shader separates environment from full body, refraction and point-glint normals', () => {
  const shader = readFileSync(waterPath, 'utf8');
  assert.match(shader, /#include\s+"res:\/\/modules\/scene_engine\/ocean\/water_environment_optics\.gdshaderinc"/);
  assert.match(shader, /vec3\s+reflection_normal\s*=\s*n\s*;/);
  assert.match(shader, /if\s*\(!water_legacy_optics\)/);
  assert.match(shader, /reference_water_environment_normal\(optical_macro_normal,world_slopes,water_environment_ripple_gain\)/);
  assert.match(shader, /reference_water_environment_fresnel\(dot\(reflection_normal,view_dir\),water_environment_horizon_weight\)/);
  assert.ok(shader.includes('reference_surface_ripple_light(dot(n,light_direction)'));
  assert.ok(shader.includes('vec2(n.x,-n.z)*.012'));
  assert.ok(shader.includes('reflection_lobe=max(dot(n,half_vector)'));
  assert.ok(shader.includes('coastal_breaker_foam(reference_coast_distance'));
});
