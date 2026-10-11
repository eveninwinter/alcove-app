/* Deterministic geometry shared by editor, export and replay. No DOM dependencies. */
(function (root) {
  "use strict";
  const clone = (x) => JSON.parse(JSON.stringify(x));
  function random(seed) {
    let a = 2166136261;
    for (const c of String(seed)) a = Math.imul(a ^ c.charCodeAt(0), 16777619);
    return () => {
      a += 0x6d2b79f5;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t ^= t + Math.imul(t ^ (t >>> 7), 61 | t);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function resample(points, step = 10) {
    if (!points.length) return [];
    let out = [points[0].slice()],
      carry = 0;
    for (let i = 1; i < points.length; i++) {
      let a = points[i - 1],
        b = points[i],
        d = Math.hypot(b[0] - a[0], b[1] - a[1]);
      if (!d) continue;
      let t = step - carry;
      for (; t <= d; t += step)
        out.push([
          a[0] + ((b[0] - a[0]) * t) / d,
          a[1] + ((b[1] - a[1]) * t) / d,
        ]);
      carry = d - (t - step);
    }
    let p = points[points.length - 1];
    if (Math.hypot(p[0] - out.at(-1)[0], p[1] - out.at(-1)[1]) > step * 0.35)
      out.push(p.slice());
    return out;
  }
  function smooth(points, closed = false) {
    let p = points.map((v) => v.slice());
    for (let n = 0; n < 2; n++) {
      let q = closed ? [] : [p[0]];
      for (let i = 0; i < p.length - (closed ? 0 : 1); i++) {
        let a = p[i],
          b = p[(i + 1) % p.length];
        q.push(
          [0.75 * a[0] + 0.25 * b[0], 0.75 * a[1] + 0.25 * b[1]],
          [0.25 * a[0] + 0.75 * b[0], 0.25 * a[1] + 0.75 * b[1]],
        );
      }
      if (!closed) q.push(p.at(-1));
      p = q;
    }
    return p;
  }
  function outline(shape, inset = 0) {
    const w = shape.w,
      h = shape.h,
      cx = w / 2,
      cy = h / 2;
    let p = [];
    if (shape.kind === "custom" && Array.isArray(shape.points)) {
      p = shape.points.map(([x, y]) => [
        cx + (x - cx) * (1 - (2 * inset) / w),
        cy + (y - cy) * (1 - (2 * inset) / h),
      ]);
    } else if (shape.kind === "rect") {
      p = [
        [inset, inset],
        [w - inset, inset],
        [w - inset, h - inset],
        [inset, h - inset],
      ];
    } else {
      for (let i = 0; i < (shape.kind === "star" ? 10 : 180); i++) {
        let t =
          (i / (shape.kind === "star" ? 10 : 180)) * Math.PI * 2 - Math.PI / 2;
        if (shape.kind === "heart") {
          let a = t + Math.PI / 2;
          p.push([
            cx + 16 * Math.sin(a) ** 3 * (w / 34 - inset / 17),
            h * 0.48 -
              (13 * Math.cos(a) -
                5 * Math.cos(2 * a) -
                2 * Math.cos(3 * a) -
                Math.cos(4 * a)) *
                (h / 32 - inset / 16),
          ]);
        } else {
          let r = shape.kind === "star" ? (i % 2 ? 0.44 : 1) : 1;
          p.push([
            cx +
              ((shape.kind === "circle" ? Math.min(cx, cy) : cx) - inset) *
                r *
                Math.cos(t),
            cy +
              ((shape.kind === "circle" ? Math.min(cx, cy) : cy) - inset) *
                r *
                Math.sin(t),
          ]);
        }
      }
    }
    return p.length ? [...p, p[0]] : [];
  }
  function inside(p, poly) {
    let yes = false;
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      let a = poly[i],
        b = poly[j];
      if (
        a[1] > p[1] !== b[1] > p[1] &&
        p[0] < ((b[0] - a[0]) * (p[1] - a[1])) / (b[1] - a[1]) + a[0]
      )
        yes = !yes;
    }
    return yes;
  }
  function stitches(paths, seed, step = 12, width = 5) {
    let rnd = random(seed),
      out = [];
    for (const path of paths) {
      let p = resample(path, step);
      for (let i = 1; i < p.length; i++) {
        let a = p[i - 1],
          b = p[i],
          jx = (rnd() - 0.5) * 1.2,
          jy = (rnd() - 0.5) * 1.2;
        out.push({
          a: [
            a[0] + (b[0] - a[0]) * 0.12 + jx,
            a[1] + (b[1] - a[1]) * 0.12 + jy,
          ],
          b: [
            b[0] - (b[0] - a[0]) * 0.12 + jx,
            b[1] - (b[1] - a[1]) * 0.12 + jy,
          ],
          width,
        });
      }
    }
    return out;
  }
  function transform(p, l) {
    const c = Math.cos(l.rot || 0),
      s = Math.sin(l.rot || 0),
      x = p[0] * (l.scale || 1) * (l.flipX ? -1 : 1),
      y = p[1] * (l.scale || 1) * (l.flipY ? -1 : 1);
    return [(l.x || 0) + x * c - y * s, (l.y || 0) + x * s + y * c];
  }
  function inverse(p, l) {
    const c = Math.cos(l.rot || 0),
      s = Math.sin(l.rot || 0),
      x = p[0] - (l.x || 0),
      y = p[1] - (l.y || 0);
    return [
      ((x * c + y * s) / (l.scale || 1)) * (l.flipX ? -1 : 1),
      ((-x * s + y * c) / (l.scale || 1)) * (l.flipY ? -1 : 1),
    ];
  }
  // Zhang–Suen thinning. The image has a one-pixel blank margin; source is never mutated.
  function skeleton(input, w, h) {
    let a = Uint8Array.from(input),
      changed = true,
      passes = 0;
    const ids = [-w, -w + 1, 1, w + 1, w, w - 1, -1, -w - 1];
    while (changed && passes++ < Math.max(w, h)) {
      changed = false;
      for (let phase = 0; phase < 2; phase++) {
        let remove = [];
        for (let y = 1; y < h - 1; y++)
          for (let x = 1; x < w - 1; x++) {
            let i = y * w + x;
            if (!a[i]) continue;
            let p = ids.map((d) => a[i + d]),
              n = p.reduce((a, b) => a + b, 0),
              trans = p.reduce(
                (s, v, k) => s + (!v && p[(k + 1) % 8] ? 1 : 0),
                0,
              );
            if (n < 2 || n > 6 || trans !== 1) continue;
            let ok =
              phase === 0
                ? (!p[0] || !p[2] || !p[4]) && (!p[2] || !p[4] || !p[6])
                : (!p[0] || !p[2] || !p[6]) && (!p[0] || !p[4] || !p[6]);
            if (ok) remove.push(i);
          }
        for (const i of remove) a[i] = 0;
        changed ||= remove.length > 0;
      }
    }
    return a;
  }
  function trace(a, w, h) {
    let nodes = [];
    const neighbors = (i) => {
      let x = i % w,
        y = Math.floor(i / w),
        ns = [];
      for (let dy = -1; dy <= 1; dy++)
        for (let dx = -1; dx <= 1; dx++) {
          if (!dx && !dy) continue;
          let xx = x + dx,
            yy = y + dy;
          if (xx < 0 || yy < 0 || xx >= w || yy >= h) continue;
          let j = yy * w + xx;
          if (!a[j]) continue;
          if (dx && dy && (a[y * w + xx] || a[yy * w + x])) continue;
          ns.push(j);
        }
      return ns;
    };
    for (let i = 0; i < a.length; i++) if (a[i]) nodes.push(i);
    let used = new Set(),
      paths = [],
      key = (i, j) => (i < j ? i + ":" + j : j + ":" + i);
    const walk = (i, j) => {
      let p = [[i % w, Math.floor(i / w)]];
      while (true) {
        used.add(key(i, j));
        p.push([j % w, Math.floor(j / w)]);
        let ns = neighbors(j);
        if (ns.length !== 2) break;
        let k = ns.find((k) => k !== i);
        if (used.has(key(j, k))) break;
        i = j;
        j = k;
      }
      if (p.length > 1) paths.push(p);
    };
    for (const i of nodes.filter((i) => neighbors(i).length !== 2))
      for (const j of neighbors(i)) if (!used.has(key(i, j))) walk(i, j);
    for (const i of nodes)
      for (const j of neighbors(i)) if (!used.has(key(i, j))) walk(i, j);
    return paths.sort((a, b) => a[0][1] - b[0][1] || a[0][0] - b[0][0]);
  }
  class History {
    constructor(doc, limit = 60) {
      this.doc = clone(doc);
      this.undoStack = [];
      this.redoStack = [];
      this.limit = limit;
    }
    change(fn) {
      const before = clone(this.doc);
      fn(this.doc);
      if (JSON.stringify(before) === JSON.stringify(this.doc)) return;
      this.undoStack.push(before);
      if (this.undoStack.length > this.limit) this.undoStack.shift();
      this.redoStack = [];
    }
    undo() {
      if (this.undoStack.length) {
        this.redoStack.push(clone(this.doc));
        this.doc = this.undoStack.pop();
      }
    }
    redo() {
      if (this.redoStack.length) {
        this.undoStack.push(clone(this.doc));
        this.doc = this.redoStack.pop();
      }
    }
  }
  const api = {
    clone,
    random,
    resample,
    smooth,
    outline,
    inside,
    stitches,
    transform,
    inverse,
    skeleton,
    trace,
    History,
  };
  root.EmbGeometry = api;
  if (typeof module !== "undefined") module.exports = api;
})(typeof globalThis !== "undefined" ? globalThis : this);
