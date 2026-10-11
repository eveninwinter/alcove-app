const assert = require("node:assert/strict");
const G = require("../../ios/App/App/Embroidery/geometry.js");
assert.deepEqual(
  G.stitches(
    [
      [
        [0, 0],
        [100, 20],
        [200, 0],
      ],
    ],
    "seed",
  ),
  G.stitches(
    [
      [
        [0, 0],
        [100, 20],
        [200, 0],
      ],
    ],
    "seed",
  ),
);
assert.deepEqual(
  G.resample(
    [
      [0, 0],
      [5, 0],
      [10, 0],
      [15, 0],
    ],
    10,
  ),
  [
    [0, 0],
    [10, 0],
    [15, 0],
  ],
);
let h = new G.History({ layers: [] });
h.change((d) => d.layers.push({ id: "fake" }));
h.undo();
assert.equal(h.doc.layers.length, 0);
h.redo();
assert.equal(h.doc.layers.length, 1);
h.undo();
h.change((d) => d.layers.push({ id: "other" }));
assert.equal(h.redoStack.length, 0);
for (const flipX of [false, true])
  for (const flipY of [false, true]) {
    let l = { x: 13, y: 25, rot: 1.2, scale: 2.3, flipX, flipY },
      p = [14, 18],
      q = G.inverse(G.transform(p, l), l);
    assert.ok(Math.hypot(p[0] - q[0], p[1] - q[1]) < 1e-10);
  }
let shape = { kind: "circle", w: 800, h: 460 };
for (const p of G.outline(shape))
  assert.ok(Math.abs(Math.hypot(p[0] - 400, p[1] - 230) - 230) < 1e-8);
let a = new Uint8Array(25 * 25);
for (let y = 3; y < 22; y++) for (let x = 10; x < 15; x++) a[y * 25 + x] = 1;
let sk = G.skeleton(a, 25, 25),
  paths = G.trace(sk, 25, 25);
assert.ok(paths.length > 0);
assert.ok(sk.reduce((a, b) => a + b, 0) < a.reduce((a, b) => a + b, 0));
console.log("geometry: 9 assertions passed");
