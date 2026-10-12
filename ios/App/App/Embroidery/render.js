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
    linen: { name: "麻布", color: "#F1EFEC" },   // 1012 她嫌脏：米黄换冷白
    cotton: { name: "棉布", color: "#F1EFF0" },
    denim: { name: "牛仔", color: "#465D79" },
    silk: { name: "丝绸", color: "#E0D4DD" },
    felt: { name: "毛毡", color: "#C2CBD0" },
    plaid: { name: "格子布", color: "#E9E3E8" },
  };
  const clothCache = new Map();
  // 1012 布四周留的边从 20 加到 50：浮起来的影子要散开，20 会把影子切成一个硬框
  const PAD = 70;
  function cloth(ctx, doc) {
    const key = JSON.stringify([doc.fabric, doc.shape]);
    if (!clothCache.has(key)) {
      const c = document.createElement("canvas");
      c.width = (doc.shape.w + PAD * 2) * 2;
      c.height = (doc.shape.h + PAD * 2) * 2;
      const x = c.getContext("2d");
      x.scale(2, 2);
      x.translate(PAD, PAD);
      paintCloth(x, doc);
      clothCache.set(key, c);
      if (clothCache.size > 4)
        clothCache.delete(clothCache.keys().next().value);
    }
    const c = clothCache.get(key);
    ctx.drawImage(c, -PAD, -PAD, c.width / 2, c.height / 2);
  }
  function paintCloth(ctx, doc) {
    let { w, h } = doc.shape,
      poly0 = G.outline(doc.shape),
      f = fabrics[doc.fabric] || fabrics.linen,
      r = G.random("fabric:" + doc.fabric);
    // 1012 毛边重做：①布边本身不再是一条笔直的线，沿法线方向轻轻起伏；②纤维顺着布边的法线长出去（不再从布中心放射），
    // 短而密、长短不一、粗细透明度各不相同、微微弯；③隔一段甩出一根长长的松线头，弯着、有的贴着布边；④毛毡不脱线，只起一点绒
    const fab = doc.fabric,
      felt = fab === "felt",
      silk = fab === "silk",
      denim = fab === "denim";
    const cxy = poly0.reduce((a, p) => [a[0] + p[0] / poly0.length, a[1] + p[1] / poly0.length], [0, 0]);
    const ph = [r() * 6.28, r() * 6.28, r() * 6.28];
    let base = G.resample(poly0, 2);   // 下面会再轻轻扭一下（warp）
    const outward = (i, pts) => {
      const p = pts[i], q = pts[(i + 1) % pts.length], o = pts[(i - 1 + pts.length) % pts.length];
      let tx = q[0] - o[0], ty = q[1] - o[1], tl = Math.hypot(tx, ty) || 1;
      tx /= tl; ty /= tl;
      let nx = ty, ny = -tx;
      if (nx * (p[0] - cxy[0]) + ny * (p[1] - cxy[1]) < 0) { nx = -nx; ny = -ny; }
      return [nx, ny, tx, ty];
    };
    // 1012 真布不会是正正的几何形：四个角各自轻轻偏一点，整块布带一点歪（最多 3，别让绕边花边出界）
    const cw = [0, 1, 2, 3].map(() => [(r() - 0.5) * 6, (r() - 0.5) * 6]);
    const warp = (x, y) => {
      const u = Math.min(1, Math.max(0, x / w)), v = Math.min(1, Math.max(0, y / h));
      return [
        x + (cw[0][0] * (1 - u) * (1 - v) + cw[1][0] * u * (1 - v) + cw[2][0] * (1 - u) * v + cw[3][0] * u * v),
        y + (cw[0][1] * (1 - u) * (1 - v) + cw[1][1] * u * (1 - v) + cw[2][1] * (1 - u) * v + cw[3][1] * u * v),
      ];
    };
    base = base.map(([x, y]) => warp(x, y));
    let along = 0;
    const poly = base.map((p, i) => {
      if (i) along += Math.hypot(p[0] - base[i - 1][0], p[1] - base[i - 1][1]);
      const [nx, ny] = outward(i, base);
      const j = felt ? 0.4 : 1.1 * Math.sin(along / 23 + ph[0]) + 0.7 * Math.sin(along / 7.3 + ph[1]) + 0.35 * Math.sin(along / 2.9 + ph[2]);
      return [p[0] + nx * j, p[1] + ny * j];
    });
    ctx.save();
    // 两层影子让布浮在底上：一层散开的浅影（离纸远一点）、一层贴着布边的深影（接触的那一下）
    ctx.fillStyle = f.color;
    polygon(ctx, poly);
    ctx.shadowColor = "rgba(40,25,35,.26)";
    ctx.shadowBlur = 30;
    ctx.shadowOffsetY = 16;
    ctx.fill();
    ctx.shadowColor = "rgba(40,25,35,.34)";
    ctx.shadowBlur = 5;
    ctx.shadowOffsetY = 2.5;
    ctx.fill();
    ctx.shadowColor = "transparent";
    polygon(ctx, poly);
    ctx.clip();
    if (fab === "plaid") {
      for (let i = 0; i < w; i += 60) {
        ctx.fillStyle = "rgba(95,53,83,.14)";
        ctx.fillRect(i, 0, 22, h);
      }
      for (let i = 0; i < h; i += 60) ctx.fillRect(0, i, w, 22);
    }
    // 1012 她：「画布不像刺绣底」——原来是一排排等距细线，像横格纸。改成真的织物：
    // 经线、纬线一根一根画，每根粗细不匀（隔一段鼓出一个纱结）、有深有浅、微微歪；再铺几块大的明暗斑、一两道浅折痕
    const loose = { linen: 2.0, cotton: 1.6, denim: 1.6, silk: 1.3, felt: 0, plaid: 1.8 }[fab] ?? 1.9;
    const slub = fab === "linen" ? 0.12 : fab === "cotton" ? 0.05 : 0.03;
    const yarn = (horizontal) => {
      const span = horizontal ? h : w, run = horizontal ? w : h;
      for (let p = r() * loose; p < span; p += loose * (0.8 + r() * 0.45)) {
        const tone = r() - 0.3, wob = (r() - 0.5) * 0.8;
        let q = -r() * 20;
        while (q < run) {
          const seg = 12 + r() * 46, fat = r() < slub ? 1.5 + r() * 0.8 : 1;
          ctx.lineWidth = loose * (0.28 + r() * 0.3) * fat;
          ctx.strokeStyle = tone > 0
            ? `rgba(255,255,255,${(0.03 + r() * 0.06) * (fat > 1 ? 2.2 : 1)})`
            : `rgba(100,102,115,${(0.008 + r() * 0.014) * (fat > 1 ? 2 : 1)})`;
          ctx.beginPath();
          if (horizontal) { ctx.moveTo(q, p + wob); ctx.lineTo(q + seg, p + wob + (r() - 0.5) * 0.5); }
          else if (denim) { ctx.moveTo(p + wob - q * 0.35, q); ctx.lineTo(p + wob - (q + seg) * 0.35, q + seg); }   // 牛仔斜纹
          else { ctx.moveTo(p + wob, q); ctx.lineTo(p + wob + (r() - 0.5) * 0.5, q + seg); }
          ctx.stroke();
          q += seg + (r() < 0.12 ? r() * 4 : 0);    // 偶尔断一下，像纱线起伏
        }
      }
    };
    // 1012 她给看真布料：真布是一上一下交织的纱，每个交叉点有亮面暗面，才看得出「织」的颗粒。
    // 先画一小块织纹贴片（平纹 / 牛仔斜纹），每粒纱一个小椭圆、左上亮右下暗、粗细深浅各不同，再平铺满布
    if (!felt) {
      const pitch = { linen: 3.4, cotton: 2.3, denim: 2.5, silk: 1.7, plaid: 2.6 }[fab] ?? 2.8;
      const n = Math.round(72 / pitch), S = n * pitch, k = 4;
      const tile = document.createElement("canvas");
      tile.width = tile.height = Math.round(S * k);
      const t = tile.getContext("2d");
      t.scale(k, k);
      const rowFat = Array.from({ length: n }, () => 0.75 + r() * 0.5), colFat = Array.from({ length: n }, () => 0.75 + r() * 0.5);
      const strong = denim ? 1.25 : fab === "linen" ? 1.15 : silk ? 0.55 : 0.9;
      for (let j = 0; j < n; j++)
        for (let i = 0; i < n; i++) {
          const over = denim ? ((i + j) % 4) < 2 : (i + j) % 2 === 0;   // 牛仔是二上二下的斜纹
          const cx = (i + 0.5) * pitch, cy = (j + 0.5) * pitch;
          const fat = over ? rowFat[j] : colFat[i];
          const rx = (over ? 0.62 : 0.36) * pitch * (over ? 1 : fat), ry = (over ? 0.36 : 0.62) * pitch * (over ? fat : 1);
          const g = t.createRadialGradient(cx - rx * 0.35, cy - ry * 0.35, 0, cx, cy, Math.max(rx, ry) * 1.1);
          const lit = (0.20 + r() * 0.12) * strong, dark = (0.05 + r() * 0.04) * strong;
          g.addColorStop(0, `rgba(255,255,255,${lit})`);
          g.addColorStop(0.55, "rgba(255,255,255,0)");
          g.addColorStop(1, `rgba(96,98,110,${dark})`);   // 暗面用冷灰，不用棕
          t.fillStyle = g;
          t.beginPath();
          t.ellipse(cx, cy, rx, ry, 0, 0, Math.PI * 2);
          t.fill();
        }
      const pat = ctx.createPattern(tile, "repeat");
      if (pat.setTransform) pat.setTransform(new DOMMatrix().scale(1 / k));
      ctx.fillStyle = pat;
      ctx.fillRect(-10, -10, w + 20, h + 20);
      yarn(false); yarn(true);
    }
    // 颜色不匀：生麻里的一粒粒深色杂点；蓝染（牛仔）深一块浅一块
    // 1012：原来这里撒棕色杂点模仿生麻，她说「显得很脏」——去掉，只留极少几粒很淡的冷灰纱结
    if (fab === "linen") {
      for (let i = 0; i < 40; i++) {
        ctx.fillStyle = `rgba(120,122,135,${0.06 + r() * 0.08})`;
        ctx.fillRect(r() * w, r() * h, 1 + r() * 3, 0.6);
      }
    }
    // 1012 她：「不要出现一坨一坨的光斑」——大明暗斑整段拿掉
    for (let i = 0; i < (felt ? 9000 : 2600); i++) {
      ctx.fillStyle = r() > 0.35 ? "rgba(255,255,255,.16)" : "rgba(90,92,105,.035)";
      ctx.fillRect(r() * w, r() * h, felt ? 1.5 : 0.9, felt ? 1.5 : 0.9);
    }
    // 1012 她：「你的折痕很突兀」——原来是一条横贯整块布、亮暗两边都很硬的线。
    // 改成一两道短的、很宽很淡的软褶：只占布宽的三到六成，两头渐隐，亮面和暗面都压到几乎看不出
    if (!felt) {
      for (let k = 0; k < (r() < 0.5 ? 1 : 2); k++) {
        const len = w * (0.3 + r() * 0.3), x0 = r() * (w - len), y0 = h * (0.2 + r() * 0.6);
        const ang = (r() - 0.5) * 0.5, x1 = x0 + len * Math.cos(ang), y1 = y0 + len * Math.sin(ang), bend = (r() - 0.5) * 30;
        const along = (rgba) => {
          const g = ctx.createLinearGradient(x0, y0, x1, y1);
          g.addColorStop(0, "rgba(0,0,0,0)");
          g.addColorStop(0.5, rgba);
          g.addColorStop(1, "rgba(0,0,0,0)");
          return g;
        };
        const path = (dy) => {
          ctx.beginPath();
          ctx.moveTo(x0, y0 + dy);
          ctx.quadraticCurveTo((x0 + x1) / 2, (y0 + y1) / 2 + bend + dy, x1, y1 + dy);
        };
        for (let j = 8; j >= 1; j--) {
          ctx.lineWidth = j * 4;
          ctx.strokeStyle = along(`rgba(255,255,255,${denim ? 0.004 : 0.012})`);
          path(0); ctx.stroke();
          ctx.strokeStyle = along(`rgba(90,92,105,${0.005})`);
          path(j * 2.5 + 4); ctx.stroke();
        }
      }
    }
    if (silk) {
      ctx.strokeStyle = "rgba(255,255,255,.18)";
      for (let j = 0; j < 5; j++) {
        ctx.lineWidth = 8;
        ctx.beginPath();
        ctx.moveTo(0, j * 120);
        ctx.bezierCurveTo(w * 0.3, j * 120 - 70, w * 0.7, j * 120 + 65, w, j * 120 - 40);
        ctx.stroke();
      }
    }
    // 有光：一整块布左上亮、右下暗；靠近布边一圈稍暗，看得出布有厚度
    const lg = ctx.createLinearGradient(0, 0, w, h);
    lg.addColorStop(0, "rgba(255,255,255,.10)");
    lg.addColorStop(0.5, "rgba(255,255,255,0)");
    lg.addColorStop(1, "rgba(80,82,95,.035)");
    ctx.fillStyle = lg;
    ctx.fillRect(-10, -10, w + 20, h + 20);
    for (let j = 6; j >= 1; j--) {
      ctx.lineWidth = j * 3;
      ctx.strokeStyle = "rgba(90,92,105,.006)";   // 布边只一点点厚度，别压出一圈脏边
      polygon(ctx, poly);
      ctx.stroke();
    }
    // 布边往里 2–5px 是脱了纬线的那一圈：浅一点、稀一点
    if (!felt) {
      ctx.lineWidth = 3.2;
      ctx.strokeStyle = "rgba(255,255,255,.16)";
      polygon(ctx, poly);
      ctx.stroke();
    }
    ctx.restore();
    // 纤维颜色：布色往白里提一点（脱出来的线比布面亮），牛仔布的纬线是白的
    const hex = f.color.replace("#", ""),
      rgb = [0, 2, 4].map((k) => parseInt(hex.slice(k, k + 2), 16)),
      lift = denim ? [222, 228, 238] : rgb.map((v) => Math.round(v + (255 - v) * 0.7));
    const fiber = (a) => `rgba(${lift[0]},${lift[1]},${lift[2]},${a})`;
    const shade = (a) => `rgba(${Math.round(rgb[0] * 0.6)},${Math.round(rgb[1] * 0.6)},${Math.round(rgb[2] * 0.6)},${a})`;
    ctx.save();
    ctx.lineCap = "round";
    const step = felt ? 3 : silk ? 1.2 : 0.8;
    const pts = G.resample(poly, step);
    for (let i = 0; i < pts.length; i++) {
      if (r() < (felt ? 0.5 : 0.18)) continue;          // 有疏有密
      const [nx, ny, tx, ty] = outward(i, pts), p = pts[i];
      const len = felt ? 0.8 + r() * 2.4 : silk ? 2 + Math.pow(r(), 1.8) * 14 : 2.5 + Math.pow(r(), 1.9) * 20;   // 1012 她：毛边太小看不见，长度约放大两倍
      const lean = (r() - 0.5) * 1.5, bend = (r() - 0.5) * len * 0.9;
      const sx = p[0] - nx * (1 + r() * 2), sy = p[1] - ny * (1 + r() * 2);
      const ex = p[0] + nx * len + tx * lean * len, ey = p[1] + ny * len + ty * lean * len;
      const mx = (sx + ex) / 2 + tx * bend, my = (sy + ey) / 2 + ty * bend;
      const a = felt ? 0.4 : 0.45 + r() * 0.5;
      ctx.lineWidth = (silk ? 0.3 : 0.45) + r() * (silk ? 0.4 : 0.7);
      ctx.strokeStyle = shade(a * 0.5);      // 每根纤维底下一道细影：浅色底上也看得见
      ctx.beginPath(); ctx.moveTo(sx, sy + 0.8); ctx.quadraticCurveTo(mx, my + 0.8, ex, ey + 0.8); ctx.stroke();
      ctx.strokeStyle = fiber(a);
      ctx.beginPath(); ctx.moveTo(sx, sy); ctx.quadraticCurveTo(mx, my, ex, ey); ctx.stroke();
    }
    // 长松线头：隔一段甩一根，弯弯的，有的顺着布边躺着
    if (!felt) {
      let per = 0;
      for (let i = 1; i < pts.length; i++) per += Math.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]);
      const n = Math.round(per / (silk ? 70 : 42));
      for (let k = 0; k < n; k++) {
        const i = Math.floor(r() * pts.length), p = pts[i], [nx, ny, tx, ty] = outward(i, pts);
        const L = 26 + r() * (silk ? 60 : 52), lie = r() < 0.5;
        const dirx = lie ? tx * (r() < 0.5 ? 1 : -1) * 0.85 + nx * 0.35 : nx, diry = lie ? ty * (r() < 0.5 ? 1 : -1) * 0.85 + ny * 0.35 : ny;
        const reach = lie ? L : L * 0.7;      // 往外翘的别超出画布留的 70
        const ex = p[0] + dirx * reach, ey = p[1] + diry * reach;
        const c1x = p[0] + dirx * L * 0.35 + tx * (r() - 0.5) * L * 0.8, c1y = p[1] + diry * L * 0.35 + ty * (r() - 0.5) * L * 0.8;
        const c2x = p[0] + dirx * L * 0.7 + nx * (r() - 0.5) * L * 0.6, c2y = p[1] + diry * L * 0.7 + ny * (r() - 0.5) * L * 0.6;
        ctx.lineWidth = 0.6 + r() * 0.5;
        ctx.strokeStyle = shade(0.28);
        ctx.beginPath(); ctx.moveTo(p[0] - nx * 2, p[1] - ny * 2 + 0.6); ctx.bezierCurveTo(c1x, c1y + 0.6, c2x, c2y + 0.6, ex, ey + 0.6); ctx.stroke();
        ctx.strokeStyle = fiber(0.7 + r() * 0.25);
        ctx.beginPath(); ctx.moveTo(p[0] - nx * 2, p[1] - ny * 2); ctx.bezierCurveTo(c1x, c1y, c2x, c2y, ex, ey); ctx.stroke();
      }
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
      scale = Math.min(
        1,
        (/^(07-pearl|08-pearl)/.test(asset) ? 480 : 240) /
          Math.max(im.width, im.height),
      );
    c.width = Math.round(im.width * scale) + 4;
    c.height = Math.round(im.height * scale) + 4;
    let ctx = c.getContext("2d");
    ctx.drawImage(im, 2, 2, c.width - 4, c.height - 4);
    let d = ctx.getImageData(0, 0, c.width, c.height).data,
      a = new Uint8Array(c.width * c.height);
    for (let i = 0; i < a.length; i++)
      a[i] =
        d[i * 4 + 3] > 90 &&
        (!/^(07-pearl|08-pearl|10-gem)/.test(asset) || d[i * 4] > 155)
          ? 1
          : 0;
    if (/^(07-pearl|08-pearl)/.test(asset)) {
      // Distance peaks separate touching beads without skeletonizing their interiors.
      const w = c.width,
        h = c.height,
        dist = Float32Array.from(a, (v) => (v ? 10000 : 0));
      for (let y = 1; y < h - 1; y++)
        for (let x = 1; x < w - 1; x++) {
          let i = y * w + x;
          if (a[i])
            dist[i] = Math.min(
              dist[i],
              dist[i - 1] + 1,
              dist[i - w] + 1,
              dist[i - w - 1] + 1.414,
              dist[i - w + 1] + 1.414,
            );
        }
      for (let y = h - 2; y > 0; y--)
        for (let x = w - 2; x > 0; x--) {
          let i = y * w + x;
          if (a[i])
            dist[i] = Math.min(
              dist[i],
              dist[i + 1] + 1,
              dist[i + w] + 1,
              dist[i + w + 1] + 1.414,
              dist[i + w - 1] + 1.414,
            );
        }
      const peaks = [];
      for (let y = 1; y < h - 1; y++)
        for (let x = 1; x < w - 1; x++) {
          let i = y * w + x,
            r = dist[i];
          if (r < 2) continue;
          let max = true;
          for (let dy = -1; dy <= 1; dy++)
            for (let dx = -1; dx <= 1; dx++)
              if (dist[i + dy * w + dx] > r) max = false;
          if (max) peaks.push({ x, y, r });
        }
      peaks.sort((a, b) => b.r - a.r || a.y - b.y || a.x - b.x);
      const beads = [];
      for (const p of peaks)
        if (
          !beads.some(
            (b) => Math.hypot(p.x - b.x, p.y - b.y) < Math.max(p.r, b.r) * 1.5,
          )
        )
          beads.push(p);
      beads.sort((a, b) => a.y - b.y || a.x - b.x);
      const paths = beads.map((b) =>
        Array.from({ length: 25 }, (_, i) => [
          (b.x + b.r * 0.75 * Math.cos((i * Math.PI) / 12) - 2) / scale -
            im.width / 2,
          (b.y + b.r * 0.75 * Math.sin((i * Math.PI) / 12) - 2) / scale -
            im.height / 2,
        ]),
      );
      const obj = { paths, dotCount: beads.length, w: im.width, h: im.height };
      assetPaths.set(asset, obj);
      return obj;
    }
    const circles = [],
      seen = new Uint8Array(a.length),
      mask = a.slice();
    for (let start = 0; start < a.length; start++) {
      if (!a[start] || seen[start]) continue;
      const queue = [start];
      seen[start] = 1;
      let minX = c.width,
        minY = c.height,
        maxX = 0,
        maxY = 0,
        sx = 0,
        sy = 0;
      for (let q = 0; q < queue.length; q++) {
        let i = queue[q],
          x = i % c.width,
          y = Math.floor(i / c.width);
        minX = Math.min(minX, x);
        maxX = Math.max(maxX, x);
        minY = Math.min(minY, y);
        maxY = Math.max(maxY, y);
        sx += x;
        sy += y;
        for (let dy = -1; dy <= 1; dy++)
          for (let dx = -1; dx <= 1; dx++) {
            let xx = x + dx,
              yy = y + dy,
              j = yy * c.width + xx;
            if (
              xx >= 0 &&
              xx < c.width &&
              yy >= 0 &&
              yy < c.height &&
              a[j] &&
              !seen[j]
            ) {
              seen[j] = 1;
              queue.push(j);
            }
          }
      }
      const w = maxX - minX + 1,
        h = maxY - minY + 1,
        fill = queue.length / (w * h);
      if (
        queue.length >= 3 &&
        w / h > 0.55 &&
        w / h < 1.8 &&
        fill > 0.52 &&
        Math.max(w, h) < 32
      ) {
        const cx = sx / queue.length,
          cy = sy / queue.length,
          rad = Math.max(0.7, Math.sqrt(queue.length / Math.PI) * 0.65);
        circles.push(
          Array.from({ length: 17 }, (_, i) => [
            cx + rad * Math.cos((i * Math.PI) / 8),
            cy + rad * Math.sin((i * Math.PI) / 8),
          ]),
        );
        for (const i of queue) mask[i] = 0;
      }
    }
    let paths = [
      ...G.trace(G.skeleton(mask, c.width, c.height), c.width, c.height),
      ...circles,
    ].map((p) =>
      p.map(([x, y]) => [
        (x - 2) / scale - im.width / 2,
        (y - 2) / scale - im.height / 2,
      ]),
    );
    let obj = { paths, dotCount: circles.length, w: im.width, h: im.height };
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
  function contrast(a, b) {
    const lum = (hex) => {
      const c = hex
        .match(/[0-9a-f]{2}/gi)
        .map((v) => parseInt(v, 16) / 255)
        .map((v) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4));
      return c[0] * 0.2126 + c[1] * 0.7152 + c[2] * 0.0722;
    };
    const x = lum(a),
      y = lum(b);
    return (Math.max(x, y) + 0.05) / (Math.min(x, y) + 0.05);
  }
  function randomPool(fabric) {
    const base = fabrics[fabric]?.color || fabrics.linen.color;
    const candidates = [
      "#B8325A",
      "#6E4C8E",
      "#2F4C9B",
      "#2F5E4E",
      "#232326",
      "#ECE6DA",
      "#F0B8C8",
      "#D9C3EF",
      "#BFE0D3",
    ];
    return candidates.filter((c) => contrast(c, base) >= 3);
  }
  async function compile(doc) {
    let ops = [],
      bounds = {},
      warnings = [];
    for (const l of doc.layers) {
      if (l.hidden) continue;
      let key =
          JSON.stringify(l) +
          doc.fabric +
          JSON.stringify(doc.shape) +
          (l.mode === "loop"
            ? JSON.stringify(doc.layers.filter((x) => x.anchor))
            : ""),
        part = compiled.get(key);
      if (!part) {
        part = { ops: [], warnings: [], bounds: [-30, -30, 60, 60] };
        let paths = [],
          charIndices = [];
        if (l.type === "text") {
          let t = await EmbGlyphs.textPaths(l);
          paths = t.paths;
          charIndices = t.charIndices;
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
              color:
                l.type === "text" && l.colorMode === "random-character"
                  ? randomPool(doc.fabric)[
                      Math.floor(
                        G.random(l.id + ":char:" + charIndices[s.pathIndex])() *
                          randomPool(doc.fabric).length,
                      )
                    ]
                  : l.color || "#B8325A",
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
  root.EmbRender = {
    compile,
    render,
    cloth,
    image,
    motif,
    fabrics,
    along,
    contrast,
    randomPool,
  };
})(globalThis);
