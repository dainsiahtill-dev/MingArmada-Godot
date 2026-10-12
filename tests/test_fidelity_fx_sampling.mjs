import { readFileSync } from 'node:fs';
import { test } from 'node:test';
import assert from 'node:assert/strict';
const shader = readFileSync(new URL('../modules/scene_engine/fidelity_fx/particle_sampling.gdshaderinc', import.meta.url), 'utf8');
const match = shader.match(/vec3\s+fidelity_particle_wrap_weights\s*\(float\s+uv,\s*float\s+extent\)\s*\{([^}]*)\}/);
assert.ok(match, 'actual production per-mip wrap addressing helper exists');
const body = match[1].replace(/\bfloat\s+(\w+)\s*=/g, 'let $1 =');
const address = new Function('uv', 'extent', 'fract', 'floor', 'mod', 'vec3', body);
const execute = (uv, size) => address(uv, size, value => value - Math.floor(value), Math.floor, (x, y) => x - y * Math.floor(x / y), (...values) => values);
test('actual shader wraps its two bilinear neighbours at every native mip', () => {
  for (const size of [128, 64, 32, 16, 8, 4, 2, 1]) {
    assert.deepEqual(execute(0, size), [size - 1, 0, .5]);
    assert.deepEqual(execute(1, size), [size - 1, 0, .5]);
    assert.deepEqual(execute(.5 / size, size), [0, size === 1 ? 0 : 1, 0]);
    for (const uv of [-31.75, -1.001, -.001, .001, .49, 1.001, 13.25]) {
      const [a, b, weight] = execute(uv, size);
      assert.ok(Number.isInteger(a) && a >= 0 && a < size && Number.isInteger(b) && b >= 0 && b < size);
      assert.ok(Number.isFinite(weight) && weight >= 0 && weight < 1);
      const periodic = execute(uv + 16, size);
      assert.ok(periodic.every((value, i) => Math.abs(value - [a, b, weight][i]) < 1e-10));
    }
  }
});
test('actual wrapped weights preserve seam continuity with unequal edge pixels', () => {
  const [first, second, blend] = execute(0, 4);
  const edgeFixture = [0, 0.2, 0.35, 1];
  assert.equal(edgeFixture[first] * (1 - blend) + edgeFixture[second] * blend, .5);
  const sample = uv => { const [a, b, weight] = execute(uv, 4); return edgeFixture[a] * (1 - weight) + edgeFixture[b] * weight; };
  assert.ok(Math.abs(sample(-1e-8) - sample(1e-8)) < 1e-6);
});
