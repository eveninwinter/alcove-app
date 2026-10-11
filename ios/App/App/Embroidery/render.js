(function (root) {
  "use strict";
  const G = EmbGeometry,
    images = new Map(),
    assetPaths = new Map(),
    compiled = new Map();
  function image(src) {
    if (!images.has(src))
      images.set(
        src,
        new Promise((resolve, reject) => {
          let im = new Image();
          im.onload = () => resolve(im);
          im.onerror = () => reject(Error("图片未载入"));
          im.src = src;
        }).catch((e) => {
          images.delete(src);
          throw e;
        }),
      );
    return images.get(src);
  }
  function polygon(ctx, p) {
    ctx.beginPath();
    p.forEach(([x, y], i) => (i ? ctx.lineTo(x, y) : ctx.moveTo(x, y)));
    ctx.closePath();
  }
  const fabrics = {
    linen: { name: "麻布", color: "#EFE9DE" },
    cotton: { name: "棉布", color: "#F1EFF0" },
    denim: { name: "牛仔", color: "#465D79" },
    silk: { name: "丝绸", color: "#E0D4DD" },
    felt: { name: "毛毡", color: "#C2CBD0" },
    plaid: { name: "格子布", color: "#E9E3E8" },
  };
  const clothCache = new Map();
  function cloth(ctx, doc) {
    const key = JSON.stringify([doc.fabric, doc.shape]);
    if (!clothCache.has(key)) {
      const c = document.createElement("canvas");
      c.width = (doc.shape.w + 40) * 2;
      c.height = (doc.shape.h + 40) * 2;
      const x = c.getContext("2d");
      x.scale(2, 2);
      x.translate(20, 20);
      paintCloth(x, doc);
      clothCache.set(key, c);
      if (clothCache.size > 4)
        clothCache.delete(clothCache.keys().next().value);
    }
    const c = clothCache.get(key);
    ctx.drawImage(c, -20, -20, c.width / 2, c.height / 2);
  }
  function paintCloth(ctx, doc) {
    let { w, h } = doc.shape,
      poly = G.outline(doc.shape),
      f = fabrics[doc.fabric] || fabrics.linen,
      r = G.random("fabric:" + doc.fabric);
    ctx.save();
    polygon(ctx, poly);
    ctx.shadowColor = "rgba(0,0,0,.22)";
    ctx.shadowBlur = 12;
    ctx.shadowOffsetY = 6;
    ctx.fillStyle = f.color;
    ctx.fill();
    ctx.shadowColor = "transparent";
    ctx.clip();
    if (doc.fabric === "plaid") {
      for (let i = 0; i < w; i += 60) {
        ctx.fillStyle = "rgba(95,53,83,.14)";
        ctx.fillRect(i, 0, 22, h);
      }
      for (let i = 0; i < h; i += 60) ctx.fillRect(0, i, w, 22);
    }
    let gap = doc.fabric === "linen" ? 3 : doc.fabric === "denim" ? 2 : 4;
    for (let x = 0; x < w; x += gap) {
      ctx.strokeStyle = `rgba(255,255,255,${0.05 + r() * 0.1})`;
      ctx.lineWidth = 0.5 + r() * 0.65;
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(doc.fabric === "denim" ? x - h * 0.4 : x, h);
      ctx.stroke();
    }
    for (let y = 0; y < h; y += gap) {
      ctx.strokeStyle = `rgba(30,25,40,${0.025 + r() * 0.07})`;
      ctx.lineWidth = 0.5;
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }
    for (let i = 0; i < (doc.fabric === "felt" ? 7000 : 1600); i++) {
      ctx.fillStyle =
        r() > 0.5 ? "rgba(255,255,255,.15)" : "rgba(20,20,30,.05)";
      ctx.fillRect(
        r() * w,
        r() * h,
        doc.fabric === "felt" ? 1.5 : 1,
        doc.fabric === "felt" ? 1.5 : 1,
      );
    }
    if (doc.fabric === "silk") {
      ctx.strokeStyle = "rgba(255,255,255,.18)";
      for (let j = 0; j < 5; j++) {
        ctx.lineWidth = 8;
        ctx.beginPath();
        ctx.moveTo(0, j * 120);
        ctx.bezierCurveTo(
          w * 0.3,
          j * 120 - 70,
          w * 0.7,
          j * 120 + 65,
          w,
          j * 120 - 40,
        );
        ctx.stroke();
      }
    }
    ctx.restore();
    const fringe = G.resample(poly, doc.fabric === "felt" ? 8 : 3.8),
      cx = w / 2,
      cy = h / 2;
    ctx.save();
    ctx.strokeStyle = f.color;
    ctx.lineWidth = 0.65;
    for (const [x, y] of fringe) {
      let len =
          doc.fabric === "felt"
            ? r() * 2
            : doc.fabric === "silk"
              ? r() * 3
              : 3 + r() * 10,
        dx = x - cx,
        dy = y - cy,
        d = Math.hypot(dx, dy);
      ctx.beginPath();
      ctx.moveTo(x, y);
      ctx.lineTo(
        x + (dx / d) * len + (r() - 0.5) * 3,
        y + (dy / d) * len + (r() - 0.5) * 3,
      );
      ctx.stroke();
    }
    ctx.restore();
  }
  function stitch(ctx, s, color) {
    let { a, b, width: w } = s;
    ctx.lineCap = "round";
    ctx.beginPath();
    ctx.moveTo(a[0], a[1] + 1.6);
    ctx.lineTo(b[0], b[1] + 1.6);
    ctx.lineWidth = w + 1;
    ctx.strokeStyle = "rgba(35,20,30,.23)";
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(...a);
    ctx.lineTo(...b);
    ctx.strokeStyle = color;
    ctx.lineWidth = w;
    ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(a[0], a[1] - w * 0.22);
    ctx.lineTo(b[0], b[1] - w * 0.22);
    ctx.strokeStyle = "rgba(255,255,255,.38)";
    ctx.lineWidth = w * 0.28;
    ctx.setLineDash([2, 3]);
    ctx.stroke();
    ctx.setLineDash([]);
    for (const p of [a, b]) {
      ctx.beginPath();
      ctx.arc(p[0], p[1], w * 0.24, 0, Math.PI * 2);
      ctx.fillStyle = "rgba(25,12,20,.28)";
      ctx.fill();
    }
  }
  async function motif(asset) {
    if (assetPaths.has(asset)) return assetPaths.get(asset);
    let im = await image("data/assets/" + asset + ".png"),
      c = document.createElement("canvas"),
      scale = Math.min(1, 240 / Math.max(im.width, im.height));
    c.width = Math.round(im.width * scale) + 4;
    c.height = Math.round(im.height * scale) + 4;
    let ctx = c.getContext("2d");
    ctx.drawImage(im, 2, 2, c.width - 4, c.height - 4);
    let d = ctx.getImageData(0, 0, c.width, c.height).data,
      a = new Uint8Array(c.width * c.height);
    for (let i = 0; i < a.length; i++) a[i] = d[i * 4 + 3] > 90 ? 1 : 0;
    let paths = G.trace(
      G.skeleton(a, c.width, c.height),
      c.width,
      c.height,
    ).map((p) =>
      p.map(([x, y]) => [
        (x - 2) / scale - im.width / 2,
        (y - 2) / scale - im.height / 2,
      ]),
    );
    let obj = { paths, w: im.width, h: im.height };
    assetPaths.set(asset, obj);
    return obj;
  }
  function along(paths, shape, w, h) {
    let poly = G.resample(G.outline(shape, 24), 2),
      length = 0,
      dist = [0];
    for (let i = 1; i < poly.length; i++) {
      length += Math.hypot(
        poly[i][0] - poly[i - 1][0],
        poly[i][1] - poly[i - 1][1],
      );
      dist.push(length);
    }
    let n = Math.max(1, Math.round(length / Math.max(w, 20))),
      segment = length / n;
    function at(s, offset) {
      s = ((s % length) + length) % length;
      let lo = 0,
        hi = dist.length - 1;
      while (lo + 1 < hi) {
        let m = (lo + hi) >> 1;
        if (dist[m] < s) lo = m;
        else hi = m;
      }
      let a = poly[lo],
        b = poly[hi],
        dd = dist[hi] - dist[lo] || 1,
        t = (s - dist[lo]) / dd,
        dx = (b[0] - a[0]) / dd,
        dy = (b[1] - a[1]) / dd;
      return [
        a[0] + (b[0] - a[0]) * t - dy * offset,
        a[1] + (b[1] - a[1]) * t + dx * offset,
      ];
    }
    let out = [];
    for (let k = 0; k < n; k++)
      for (const p of paths)
        out.push(
          p.map(([x, y]) =>
            at(
              k * segment + ((x + w / 2) * segment) / w,
              y * Math.min(1, 24 / h),
            ),
          ),
        );
    return out;
  }
  async function compile(doc) {
    let ops = [],
      bounds = {},
      warnings = [];
    for (const l of doc.layers) {
      if (l.hidden) continue;
      let key =
          JSON.stringify(l) +
          JSON.stringify(doc.shape) +
          (l.mode === "loop"
            ? JSON.stringify(doc.layers.filter((x) => x.anchor))
            : ""),
        part = compiled.get(key);
      if (!part) {
        part = { ops: [], warnings: [], bounds: [-30, -30, 60, 60] };
        let paths = [];
        if (l.type === "text") {
          let t = await EmbGlyphs.textPaths(l);
          paths = t.paths;
          part.warnings = t.warnings;
        } else if (l.type === "draw") paths = [l.points];
        else if (l.type === "border" || l.type === "motif") {
          let m = await motif(l.asset);
          paths =
            l.mode === "loop" ? along(m.paths, doc.shape, m.w, m.h) : m.paths;
        } else if (l.type === "image") {
          let im = await image(l.src),
            w = l.w || 200,
            h = l.h || (w * im.height) / im.width;
          part.bounds = [-w / 2, -h / 2, w, h];
          part.ops.push({ kind: "image", layer: l, image: im, w, h });
          if (l.style === "patch")
            paths = [
              [
                [-w / 2, -h / 2],
                [w / 2, -h / 2],
                [w / 2, h / 2],
                [-w / 2, h / 2],
                [-w / 2, -h / 2],
              ],
            ];
        }
        if (paths.length) {
          let flat = paths.flat(),
            xs = flat.map((p) => p[0]),
            ys = flat.map((p) => p[1]),
            minX = Math.min(...xs),
            minY = Math.min(...ys);
          if (l.type !== "image")
            part.bounds = [
              minX,
              minY,
              Math.max(...xs) - minX,
              Math.max(...ys) - minY,
            ];
          let ss = G.stitches(
            paths,
            l.id,
            l.type === "text" ? l.size * 0.11 : 8,
            l.type === "text" ? l.size * 0.045 : l.width || 3,
          );
          if (l.mode === "loop") {
            const corners = doc.layers.filter((x) => x.anchor && !x.hidden);
            ss = ss.filter(
              (s) =>
                !corners.some(
                  (c) =>
                    Math.abs(s.a[0] - c.x) < (c.w || 100) * c.scale * 0.55 &&
                    Math.abs(s.a[1] - c.y) < (c.h || 100) * c.scale * 0.55,
                ),
            );
          }
          for (const s of ss)
            part.ops.push({
              kind: "stitch",
              layer: l,
              stitch: s,
              color: l.color || "#B8325A",
            });
        }
        compiled.set(key, part);
        if (compiled.size > 150) compiled.delete(compiled.keys().next().value);
      }
      ops.push(...part.ops);
      bounds[l.id] = part.bounds;
      warnings.push(...part.warnings);
      if (l.type === "text") {
        const [x, y, w, h] = part.bounds;
        if (
          [
            [x, y],
            [x + w, y],
            [x, y + h],
            [x + w, y + h],
          ].some((p) => !G.inside(G.transform(p, l), G.outline(doc.shape)))
        )
          warnings.push("文字超出布面，请缩小或换行");
      }
    }
    return { ops, bounds, warnings: [...new Set(warnings)] };
  }
  function render(ctx, doc, scene, progress = 1, revealLayer = null) {
    cloth(ctx, doc);
    ctx.save();
    polygon(ctx, G.outline(doc.shape));
    ctx.clip();
    let visible;
    if (revealLayer) {
      let budget = Math.floor(
        scene.ops.filter((o) => o.layer.id === revealLayer).length * progress,
      );
      visible = scene.ops.filter(
        (o) => o.layer.id !== revealLayer || budget-- > 0,
      );
    } else
      visible = scene.ops.slice(0, Math.floor(scene.ops.length * progress));
    for (const op of visible) {
      let l = op.layer;
      ctx.save();
      if (l.mode !== "loop") {
        ctx.translate(l.x || 0, l.y || 0);
        ctx.rotate(l.rot || 0);
        ctx.scale(
          (l.scale || 1) * (l.flipX ? -1 : 1),
          (l.scale || 1) * (l.flipY ? -1 : 1),
        );
      }
      if (op.kind === "stitch") stitch(ctx, op.stitch, op.color);
      else {
        let { image: im, w, h } = op,
          c = l.crop || { x: 0, y: 0, w: 1, h: 1 };
        if (l.style === "patch") {
          ctx.fillStyle = "#F1ECE9";
          ctx.shadowColor = "rgba(0,0,0,.2)";
          ctx.shadowBlur = 4;
          ctx.fillRect(-w / 2 - 3, -h / 2 - 3, w + 6, h + 6);
          ctx.shadowBlur = 0;
        }
        ctx.globalAlpha = l.style === "print" ? 0.86 : 1;
        ctx.drawImage(
          im,
          c.x * im.width,
          c.y * im.height,
          c.w * im.width,
          c.h * im.height,
          -w / 2,
          -h / 2,
          w,
          h,
        );
        if (l.style === "print") {
          ctx.fillStyle = "rgba(245,241,238,.16)";
          for (let x = -w / 2; x < w / 2; x += 3)
            ctx.fillRect(x, -h / 2, 0.6, h);
        }
      }
      ctx.restore();
    }
    ctx.restore();
    return revealLayer
      ? visible.filter((o) => o.layer.id === revealLayer).at(-1)
      : visible.at(-1);
  }
  root.EmbRender = { compile, render, cloth, image, motif, fabrics, along };
})(globalThis);
