import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const detailPath = fileURLToPath(new URL('../modules/scene_engine/ocean/surface_detail_lod.gdshaderinc', import.meta.url));
const smoothstep = (a, b, x) => {
  const t = Math.max(0, Math.min(1, (x - a) / (b - a)));
  return t * t * (3 - 2 * t);
};
// Execute the production scalar GLSL bodies. No mirrored LOD implementation:
// replacing its return/branch/threshold changes these measured results.
function shaderScalar(name) {
  assert.ok(existsSync(detailPath), 'surface detail needs a texture-footprint LOD contract');
  const source = readFileSync(detailPath, 'utf8');
  const match = source.match(new RegExp(`float ${name}\\(([^)]*)\\) \\{([^}]+)\\}`));
  assert.ok(match, `production shader exposes ${name}`);
  const parameters = match[1].split(',').map(value => value.trim().replace(/^float\s+/, ''));
  const body = match[2].replace(/\bfloat\s+/g, 'let ');
  const run = new Function(...parameters, 'smoothstep', 'max', 'clamp', body);
  return (...args) => run(...args, smoothstep, Math.max, (x, a, b) => Math.max(a, Math.min(b, x)));
}

test('resolved near water retains small ripples; subpixel bands fade independently', () => {
  const visible = shaderScalar('reference_surface_band_visibility');
  assert.equal(visible(0.25, 8), 1, 'resolved original normal features retain their amplitude');
  assert.equal(visible(32, 8), 0, 'an unresolved fine feature cannot become white grain');
  assert.equal(visible(32, 64), 1, 'same pixel footprint keeps the broad water flow');
  assert.ok(visible(10, 8) > 0.45 && visible(10, 8) < 0.55, 'partially resolved band blends, rather than pops');
  assert.equal(visible(10, 8), visible(20, 16), 'LOD follows pixel span, independent of texture resolution');
});

test('LOD remains monotone and continuous through near/far transitions', () => {
  const visible = shaderScalar('reference_surface_band_visibility');
  let previous = visible(0, 8);
  for (let footprint = 0.05; footprint <= 24; footprint += 0.05) {
    const next = visible(footprint, 8);
    assert.ok(next >= 0 && next <= previous, 'moving outward cannot reintroduce a fine band');
    assert.ok(previous - next < 0.007, 'camera movement cannot jump between band strengths');
    previous = next;
  }
  for (const boundary of [4, 16]) {
    assert.ok(Math.abs(visible(boundary - 1e-5, 8) - visible(boundary + 1e-5, 8)) < 1e-5);
  }
});

test('off-specular normals still produce bounded water-body ripple contrast', () => {
  const light = shaderScalar('reference_surface_ripple_light');
  assert.equal(light(0.8, 0.8, 0.4), 1, 'flat water keeps the approved palette');
  assert.ok(Math.abs(light(0.95, 0.8, 0.4) - 1.06) < 1e-12);
  assert.ok(Math.abs(light(0.65, 0.8, 0.4) - 0.94) < 1e-12);
  assert.equal(light(1, -1, 1), 1.16, 'normal detail cannot whiten the water body');
  assert.equal(light(-1, 1, 1), 0.84, 'normal detail cannot carve black creases');
});

test('filtered specular widens continuously without increasing highlight energy', () => {
  const power = shaderScalar('reference_surface_specular_power');
  assert.equal(power(0, 250), 250, 'resolved normals preserve the original fine lobe');
  assert.ok(Math.abs(power(0.008, 250) - 250 / 3) < 1e-10);
  assert.ok(power(0.08, 250) < power(0.008, 250));
  assert.equal(power(-1, 250), 250, 'numerical noise cannot sharpen the lobe');
});

