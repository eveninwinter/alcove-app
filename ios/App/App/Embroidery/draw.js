/* 1014 画图：跟刺绣同一个半屏，顶上切换。钢笔 / 水彩 / 蜡笔 / 橡皮，每一笔都记成一串点，
   发出去以后服务器照着这串点一笔一笔重画，做成回放视频（聊天卡片点一下就播）。
   画法全是确定的（随机数按笔的编号播种），App 里画的、服务器回放的、存相册的，长得一模一样。 */
(function (root) {
  "use strict";
  const W = 900, H = 1200;
  const PRESET = [
    ["白", "#FFFFFF"], ["黑", "#26262B"], ["粉", "#E48DA6"], ["蓝", "#4E6FC6"],
    ["绿", "#5E9B7B"], ["灰", "#9A9AA3"], ["紫", "#9A7BC8"], ["黄", "#E6C25C"],
  ];
  const TOOLS = [["pen", "钢笔"], ["water", "水彩"], ["crayon", "蜡笔"], ["eraser", "橡皮"]];
  const SIZES = [2, 4, 7, 12, 20];

  function seeded(seed) {
    let h = 2166136261;
    for (const c of String(seed)) h = Math.imul(h ^ c.charCodeAt(0), 16777619);
    return () => {
      h += 0x6d2b79f5;
      let t = h;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  function rgba(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${(n >> 16) & 255},${(n >> 8) & 255},${n & 255},${a})`;
  }
  const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
  function smoothPath(ctx, pts) {
    ctx.beginPath();
    if (pts.length === 1) { ctx.moveTo(pts[0][0], pts[0][1]); ctx.lineTo(pts[0][0] + 0.01, pts[0][1]); return; }
    ctx.moveTo(pts[0][0], pts[0][1]);
    for (let i = 1; i < pts.length - 1; i++) {
      const m = mid(pts[i], pts[i + 1]);
      ctx.quadraticCurveTo(pts[i][0], pts[i][1], m[0], m[1]);
    }
    const l = pts[pts.length - 1];
    ctx.lineTo(l[0], l[1]);
  }

  // ── 纸：暖白，一点点纸纹（缓存一张） ──
  const paperCache = new Map();
  function paper(doc, k) {
    const key = doc.id + ":" + k;
    if (paperCache.has(key)) return paperCache.get(key);
    const c = document.createElement("canvas");
    c.width = Math.round(doc.w * k); c.height = Math.round(doc.h * k);
    const x = c.getContext("2d");
    x.scale(k, k);
    x.fillStyle = doc.paper || "#FBFAF7";
    x.fillRect(0, 0, doc.w, doc.h);
    const r = seeded("paper:" + doc.id);
    for (let i = 0; i < 2600; i++) {
      x.fillStyle = r() < 0.55 ? "rgba(140,140,150,.05)" : "rgba(255,255,255,.7)";
      x.fillRect(r() * doc.w, r() * doc.h, 1 + r() * 1.6, 1 + r() * 1.6);
    }
    paperCache.clear();
    paperCache.set(key, c);
    return c;
  }

  // ── 四种笔 ──
  let scratch = null;
  function scratchFor(ctx) {
    const w = ctx.canvas.width, h = ctx.canvas.height;
    if (!scratch || scratch.width !== w || scratch.height !== h) {
      scratch = document.createElement("canvas");
      scratch.width = w; scratch.height = h;
    }
    const s = scratch.getContext("2d");
    s.setTransform(1, 0, 0, 1, 0, 0);
    s.clearRect(0, 0, w, h);
    s.setTransform(ctx.getTransform());
    return s;
  }
  function stroke(ctx, st, n) {
    const pts = n == null ? st.points : st.points.slice(0, Math.max(1, n));
    const a = st.alpha == null ? 1 : st.alpha;
    ctx.save();
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    if (st.tool === "pen") {
      // 钢笔：细、实，快的地方细一点，慢的地方粗一点
      ctx.strokeStyle = rgba(st.color, a);
      let w = st.size;
      if (pts.length < 3) {
        ctx.lineWidth = st.size; smoothPath(ctx, pts); ctx.stroke();
      } else {
        for (let i = 1; i < pts.length; i++) {
          const p0 = pts[i - 1], p1 = pts[i];
          const d = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]);
          w = w * 0.65 + st.size * Math.max(0.5, Math.min(1.25, 1.3 - d / 30)) * 0.35;
          ctx.lineWidth = w;
          ctx.beginPath();
          const s0 = i > 1 ? mid(pts[i - 2], p0) : p0, s1 = mid(p0, p1);
          ctx.moveTo(s0[0], s0[1]);
          ctx.quadraticCurveTo(p0[0], p0[1], s1[0], s1[1]);
          ctx.stroke();
        }
        const l = pts[pts.length - 1], m = mid(pts[pts.length - 2], l);
        ctx.beginPath(); ctx.moveTo(m[0], m[1]); ctx.lineTo(l[0], l[1]); ctx.stroke();
      }
    } else if (st.tool === "water") {
      // 水彩：半透明、边缘颜料多一点（深一圈），中间淡；叠上去会一层层加深
      const s = scratchFor(ctx);
      s.lineCap = "round"; s.lineJoin = "round";
      s.strokeStyle = st.color;
      s.lineWidth = st.size * 2.2;
      smoothPath(s, pts); s.stroke();
      s.globalCompositeOperation = "destination-out";
      s.strokeStyle = "rgba(0,0,0,.5)";
      s.lineWidth = st.size * 1.6;
      smoothPath(s, pts); s.stroke();
      const r = seeded("water:" + (st.id || ""));
      s.fillStyle = "rgba(0,0,0,.18)";
      for (let i = 1; i < pts.length; i += 2) {
        const p = pts[i];
        for (let j = 0; j < 3; j++) {
          const ang = r() * 6.283, rad = r() * st.size * 0.9;
          s.beginPath(); s.arc(p[0] + Math.cos(ang) * rad, p[1] + Math.sin(ang) * rad, 0.6 + r() * st.size * 0.12, 0, 6.283); s.fill();
        }
      }
      s.globalCompositeOperation = "source-over";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.globalAlpha = 0.62 * a;
      ctx.drawImage(scratch, 0, 0);
    } else if (st.tool === "crayon") {
      // 蜡笔：一粒粒颜料蹭在纸纹上，颗粒感，边缘毛
      const r = seeded("crayon:" + (st.id || ""));
      ctx.fillStyle = rgba(st.color, 0.8 * a);
      const R = st.size * 0.9;
      const dot = (x, y) => {
        const n = Math.max(3, Math.round(R * 1.6));
        for (let j = 0; j < n; j++) {
          const ang = r() * 6.283, rad = Math.sqrt(r()) * R;
          if (r() < 0.28) continue;
          const sz = 0.7 + r() * Math.max(1, R * 0.28);
          ctx.fillRect(x + Math.cos(ang) * rad, y + Math.sin(ang) * rad, sz, sz * (0.6 + r() * 0.8));
        }
      };
      dot(pts[0][0], pts[0][1]);
      for (let i = 1; i < pts.length; i++) {
        const p0 = pts[i - 1], p1 = pts[i];
        const d = Math.hypot(p1[0] - p0[0], p1[1] - p0[1]), steps = Math.max(1, Math.ceil(d / Math.max(1.2, R * 0.35)));
        for (let k = 1; k <= steps; k++) dot(p0[0] + ((p1[0] - p0[0]) * k) / steps, p0[1] + ((p1[1] - p0[1]) * k) / steps);
      }
    } else if (st.tool === "eraser") {
      ctx.globalCompositeOperation = "destination-out";
      ctx.strokeStyle = "rgba(0,0,0,1)";
      ctx.lineWidth = st.size * 2.6;
      smoothPath(ctx, pts); ctx.stroke();
    }
    ctx.restore();
  }

  // 画到某个进度：progress 0–1，按点数算（一笔一笔、一点一点）
  function inkTo(ctx, doc, progress = 1) {
    const total = doc.strokes.reduce((n, s) => n + s.points.length, 0);
    let budget = Math.round(total * progress);
    for (const st of doc.strokes) {
      if (budget <= 0) break;
      const n = Math.min(st.points.length, budget);
      stroke(ctx, st, n === st.points.length ? null : n);
      budget -= n;
    }
  }
  function compose(doc, progress, k, type = "image/png", q) {
    const c = document.createElement("canvas");
    c.width = Math.round(doc.w * k); c.height = Math.round(doc.h * k);
    const x = c.getContext("2d");
    const ink = document.createElement("canvas");
    ink.width = c.width; ink.height = c.height;
    const ix = ink.getContext("2d");
    ix.scale(k, k);
    inkTo(ix, doc, progress);
    x.drawImage(paper(doc, k), 0, 0);
    x.drawImage(ink, 0, 0);
    return c.toDataURL(type, q);
  }
  // 服务器拍回放用：宽 width 像素的一帧 jpeg
  function frame(doc, progress, width = 720) {
    return compose(doc, progress, width / doc.w, "image/jpeg", 0.88);
  }

  root.EmbDraw = { frame, compose, stroke, inkTo, PRESET, TOOLS, SIZES };

  // ── 以下是 App 里的画图页；服务器渲染时没有这些节点就不装 ──
  const $ = (id) => document.getElementById(id);
  if (!$("drawMode")) return;

  const DRAFT = "alcove-draw-draft";
  const blank = () => ({ id: "emb_d" + Date.now() + "_" + Math.random().toString(36).slice(2, 7), kind: "drawing", version: 1,
                         author: "ji", w: W, h: H, paper: "#FBFAF7", strokes: [] });
  let doc = blank();
  try { const d = JSON.parse(localStorage.getItem(DRAFT) || "null"); if (d && d.kind === "drawing" && Array.isArray(d.strokes)) doc = d; } catch (e) {}
  let redo = [], toolName = "pen", size = 4, alpha = 1, color = "#26262B", live = null, busy = false;
  const canvas = $("dcanvas"), ctx = canvas.getContext("2d");
  let ink = document.createElement("canvas"), view = { k: 1, x: 0, y: 0, dpr: 1 };

  function saveDraft() { try { localStorage.setItem(DRAFT, JSON.stringify(doc)); } catch (e) {} }
  function note(t) { $("dnotice").textContent = t || ""; }

  function fit() {
    const r = $("dstage").getBoundingClientRect();
    view.dpr = Math.min(devicePixelRatio || 1, 3);
    canvas.width = Math.max(1, Math.round(r.width * view.dpr));
    canvas.height = Math.max(1, Math.round(r.height * view.dpr));
    view.k = Math.min((r.width - 28) / doc.w, (r.height - 20) / doc.h);
    view.x = (r.width - doc.w * view.k) / 2;
    view.y = (r.height - doc.h * view.k) / 2;
    rebuildInk();
  }
  function rebuildInk() {
    const k = view.k * view.dpr;
    ink.width = Math.max(1, Math.round(doc.w * k)); ink.height = Math.max(1, Math.round(doc.h * k));
    const x = ink.getContext("2d");
    x.setTransform(k, 0, 0, k, 0, 0);
    inkTo(x, doc, 1);
    paint();
  }
  function paint() {
    const r = canvas.getBoundingClientRect();
    ctx.setTransform(view.dpr, 0, 0, view.dpr, 0, 0);
    ctx.clearRect(0, 0, r.width, r.height);
    ctx.save();
    ctx.shadowColor = "rgba(40,40,60,.10)"; ctx.shadowBlur = 18; ctx.shadowOffsetY = 4;
    ctx.fillStyle = "#FBFAF7";
    ctx.fillRect(view.x, view.y, doc.w * view.k, doc.h * view.k);
    ctx.restore();
    ctx.drawImage(paper(doc, view.k * view.dpr), view.x, view.y, doc.w * view.k, doc.h * view.k);
    if (live && (live.tool === "water" || live.tool === "eraser")) {
      // 水彩 / 橡皮要整笔一起算：拷一份墨层，把正在画的这笔画上去再贴
      const tmp = document.createElement("canvas");
      tmp.width = ink.width; tmp.height = ink.height;
      const t = tmp.getContext("2d");
      t.drawImage(ink, 0, 0);
      const k = view.k * view.dpr;
      t.setTransform(k, 0, 0, k, 0, 0);
      stroke(t, live);
      ctx.drawImage(tmp, view.x, view.y, doc.w * view.k, doc.h * view.k);
    } else {
      ctx.drawImage(ink, view.x, view.y, doc.w * view.k, doc.h * view.k);
    }
    $("dundo").disabled = !doc.strokes.length;
    $("dredo").disabled = !redo.length;
  }
  function point(e) {
    const r = canvas.getBoundingClientRect();
    return [Math.round(((e.clientX - r.left - view.x) / view.k) * 10) / 10, Math.round(((e.clientY - r.top - view.y) / view.k) * 10) / 10];
  }
  let pid = null;
  canvas.addEventListener("pointerdown", (e) => {
    if (pid !== null || busy) return;
    pid = e.pointerId; canvas.setPointerCapture(pid);
    hidePop();
    live = { id: Math.random().toString(36).slice(2, 9), tool: toolName, color, size, alpha, points: [point(e)] };
    if (toolName === "pen" || toolName === "crayon") {
      const k = view.k * view.dpr, x = ink.getContext("2d");
      x.setTransform(k, 0, 0, k, 0, 0);
      stroke(x, live);
    }
    paint();
  });
  canvas.addEventListener("pointermove", (e) => {
    if (e.pointerId !== pid || !live) return;
    const p = point(e), l = live.points[live.points.length - 1];
    if (Math.hypot(p[0] - l[0], p[1] - l[1]) < 1.5 || live.points.length >= 7900) return;
    live.points.push(p);
    if (live.tool === "pen" || live.tool === "crayon") {
      // 实心的笔只补画最后一小段，省得每动一下整笔重画
      const k = view.k * view.dpr, x = ink.getContext("2d");
      x.setTransform(k, 0, 0, k, 0, 0);
      const n = live.points.length;
      stroke(x, { ...live, points: live.points.slice(Math.max(0, n - 3)) });
    }
    paint();
  });
  const finishStroke = (e) => {
    if (e.pointerId !== pid) return;
    pid = null;
    if (!live) return;
    doc.strokes.push(live);
    live = null; redo = [];
    rebuildInk();      // 整笔按存下来的点重画一遍，跟回放、导出完全一致
    saveDraft();
  };
  canvas.addEventListener("pointerup", finishStroke);
  canvas.addEventListener("pointercancel", finishStroke);

  // ── 工具栏 ──
  function btn(text, fn, parent, cls) {
    const b = document.createElement("button");
    b.type = "button"; b.textContent = text; b.onclick = fn;
    if (cls) b.className = cls;
    parent.append(b);
    return b;
  }
  const ICON = {
    pen: '<svg viewBox="0 0 24 24"><path d="M5 19l2.5-.6L18 7.9a1.6 1.6 0 0 0 0-2.3l-.6-.6a1.6 1.6 0 0 0-2.3 0L4.6 15.5 4 18z"/><path d="M13.8 6.3l3 3"/></svg>',
    water: '<svg viewBox="0 0 24 24"><path d="M14.5 4.5c2 0 4 2 4 4L11 16l-3-3z"/><path d="M8 13c-2.2.3-3.3 2.2-3.5 5.5 3.3-.2 5.2-1.3 5.5-3.5"/></svg>',
    crayon: '<svg viewBox="0 0 24 24"><path d="M15 4l5 5-9.5 9.5H5.5v-5z"/><path d="M13 6l5 5M5.5 13.5l5 5"/></svg>',
    eraser: '<svg viewBox="0 0 24 24"><path d="M9 19l-4.3-4.3a1.4 1.4 0 0 1 0-2L13 4.4a1.4 1.4 0 0 1 2 0l4.3 4.3a1.4 1.4 0 0 1 0 2L11 19z"/><path d="M8 11l5 5M9 19h10"/></svg>',
  };
  const toolRow = $("dtools");
  for (const [k, name] of TOOLS) {
    const b = btn("", () => { toolName = k; refresh(); }, toolRow, "dtool");
    b.dataset.tool = k;
    b.innerHTML = ICON[k] + "<span>" + name + "</span>";
  }
  const sizeBtn = btn("", () => togglePop(), toolRow, "dsize");
  const pop = $("dpop");
  const sizeRow = document.createElement("div"); sizeRow.className = "dsizes"; pop.append(sizeRow);
  for (const s of SIZES) {
    const b = btn("", () => { size = s; refresh(); }, sizeRow, "dsizeopt");
    b.dataset.size = s;
    const i = document.createElement("i"); i.style.width = i.style.height = Math.min(26, 4 + s * 1.1) + "px"; b.append(i);
  }
  const alphaLab = document.createElement("label"); alphaLab.className = "dalpha";
  alphaLab.innerHTML = "<small>浓淡</small>";
  const alphaIn = document.createElement("input");
  Object.assign(alphaIn, { type: "range", min: "0.15", max: "1", step: "0.05", value: "1" });
  alphaIn.oninput = () => { alpha = +alphaIn.value; refresh(); };
  alphaLab.append(alphaIn); pop.append(alphaLab);
  function togglePop() { pop.hidden = !pop.hidden; }
  function hidePop() { pop.hidden = true; }

  const pal = $("dpalette");
  for (const [name, c] of PRESET) {
    const b = btn("", () => { color = c; if (toolName === "eraser") toolName = "pen"; refresh(); }, pal, "dswatch");
    b.title = name; b.dataset.color = c; b.style.setProperty("--c", c);
  }
  // 其余颜色：系统取色盘（iOS 会弹自己的那个）
  const more = document.createElement("label"); more.className = "dswatch dmore"; more.title = "更多颜色";
  const colorIn = document.createElement("input"); colorIn.type = "color"; colorIn.value = "#E48DA6";
  colorIn.oninput = () => { color = colorIn.value.toUpperCase(); if (toolName === "eraser") toolName = "pen"; refresh(); };
  more.append(colorIn); pal.append(more);

  function refresh() {
    toolRow.querySelectorAll(".dtool").forEach((b) => b.classList.toggle("active", b.dataset.tool === toolName));
    sizeRow.querySelectorAll(".dsizeopt").forEach((b) => b.classList.toggle("active", +b.dataset.size === size));
    pal.querySelectorAll(".dswatch[data-color]").forEach((b) => b.classList.toggle("active", b.dataset.color === color && toolName !== "eraser"));
    more.classList.toggle("active", toolName !== "eraser" && !PRESET.some(([, c]) => c === color));
    more.style.setProperty("--c", color);
    sizeBtn.innerHTML = "";
    const i = document.createElement("i");
    i.style.width = i.style.height = Math.min(22, 4 + size * 0.9) + "px";
    i.style.background = toolName === "eraser" ? "transparent" : rgba(color, alpha);
    sizeBtn.append(i);
    const sp = document.createElement("span"); sp.textContent = "粗细"; sizeBtn.append(sp);
  }

  $("dundo").onclick = () => { if (doc.strokes.length) { redo.push(doc.strokes.pop()); rebuildInk(); saveDraft(); } };
  $("dredo").onclick = () => { if (redo.length) { doc.strokes.push(redo.pop()); rebuildInk(); saveDraft(); } };
  let clearArmed = 0;
  $("dclear").onclick = () => {
    if (!doc.strokes.length) return;
    if (Date.now() - clearArmed > 2500) { clearArmed = Date.now(); note("再点一次「清空」就全擦掉"); return; }
    redo = doc.strokes.splice(0).reverse(); clearArmed = 0; note(""); rebuildInk(); saveDraft();
  };

  function exportPNG() { return compose(doc, 1, 2); }
  $("dsave").onclick = () => {
    if (!doc.strokes.length) return note("先画一笔");
    const data = exportPNG();
    if (window.webkit?.messageHandlers?.embroidery) window.webkit.messageHandlers.embroidery.postMessage({ kind: "exportMedia", data, media: "png" });
    else { const a = document.createElement("a"); a.download = doc.id + ".png"; a.href = data; a.click(); }
  };
  $("dsend").onclick = async () => {
    if (busy) return;
    if (!doc.strokes.length) return note("先画一笔");
    busy = true; $("dsend").disabled = true; note("在发…");
    try {
      const out = JSON.parse(JSON.stringify(doc));
      const cap = $("dcaption").value.trim();
      if (cap) out.caption = cap.slice(0, 500);
      const done = await EmbFinish.api("finish", { document: out, png: exportPNG() });
      await EmbFinish.api("send", { id: done.document.id });
      note("发给陈璟了");
      doc = blank(); redo = []; $("dcaption").value = "";
      try { localStorage.removeItem(DRAFT); } catch (e) {}
      rebuildInk();
    } catch (e) {
      note("没发出去：" + (e.message || e));
    } finally { busy = false; $("dsend").disabled = false; }
  };

  // ── 刺绣 / 画图 切换 ──
  function setMode(m) {
    document.body.classList.toggle("drawing", m === "draw");
    $("modeStitch").classList.toggle("active", m !== "draw");
    $("modeDraw").classList.toggle("active", m === "draw");
    try { localStorage.setItem("alcove-emb-mode", m); } catch (e) {}
    if (m === "draw") requestAnimationFrame(fit);
    else window.dispatchEvent(new Event("resize"));
  }
  $("modeStitch").onclick = () => setMode("stitch");
  $("modeDraw").onclick = () => setMode("draw");
  new ResizeObserver(() => { if (document.body.classList.contains("drawing")) fit(); }).observe($("dstage"));
  refresh();
  let m0 = "stitch";
  try { m0 = localStorage.getItem("alcove-emb-mode") || "stitch"; } catch (e) {}
  setMode(m0);
})(globalThis);
