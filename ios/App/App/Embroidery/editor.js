/* One document and one web view survive half/full screen changes. */
"use strict";
var EMB_FONTS = [];
var readOnly = false;
var textRandomColor = true;
const G = EmbGeometry,
  R = EmbRender,
  $ = (id) => document.getElementById(id),
  canvas = $("canvas"),
  ctx = canvas.getContext("2d");
const uid = () =>
  "l_" + Date.now().toString(36) + "_" + Math.random().toString(36).slice(2, 8);
const blank = () => ({
  id: "emb_" + Date.now(),
  version: 1,
  author: "ji",
  created_at: new Date().toISOString(),
  finished_at: null,
  title: "",
  fabric: "linen",
  shape: { kind: "rect", w: 800, h: 460 },
  layers: [],
});
let history = new G.History(blank()),
  selected = null,
  tool = null,
  mode = "select",
  color = "#B8325A",
  scene = { ops: [], bounds: {}, warnings: [] },
  revision = 0,
  assets = [],
  view = { scale: 1, x: 0, y: 0, zoom: 1, panX: 0, panY: 0 },
  pointers = new Map(),
  drag = null,
  guide = [],
  cutPreview = null,
  progress = 1,
  playing = false,
  lastTime = 0,
  rate = 1,
  saveTimer,
  compileTimer,
  pendingImage = null,
  isComposing = false,
  animationLayer = null;
function bridge(kind, payload = {}) {
  if (window.webkit?.messageHandlers?.embroidery) {
    window.webkit.messageHandlers.embroidery.postMessage({ kind, ...payload });
    return true;
  }
  return false;
}
function notice(s) {
  $("notice").textContent = s || "";
}
function report(e) {
  notice(e.message || String(e));
}
function current() {
  return history.doc.layers.find((l) => l.id === selected);
}
function base(type, extra = {}) {
  return {
    id: uid(),
    type,
    x: 400,
    y: 180,
    scale: 1,
    rot: 0,
    hidden: false,
    locked: false,
    color,
    ...extra,
  };
}
function change(fn, animate = false) {
  if (readOnly) {
    notice("这是定版，先另存新版本再修改");
    return;
  }
  history.change(fn);
  schedule(animate);
}
function add(layer, animate = true) {
  change((d) => d.layers.push(layer), animate);
  selected = layer.id;
}
function flushSave() {
  if (readOnly) return;
  clearTimeout(saveTimer);
  const d = G.clone(history.doc);
  if (!bridge("save", { document: d })) {
    try {
      localStorage.setItem("embroidery.draft", JSON.stringify(d));
      $("status").textContent = "草稿已存";
    } catch (e) {
      notice("草稿保存失败，请勿退出");
    }
  }
}
function save() {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(flushSave, 400);
}
window.addEventListener("pagehide", flushSave);
document.addEventListener("visibilitychange", () => {
  if (document.hidden) flushSave();
});
function schedule(animate = false) {
  save();
  clearTimeout(compileTimer);
  compileTimer = setTimeout(() => build(animate), 25);
}
async function build(animate = false) {
  const r = ++revision;
  try {
    let next = await R.compile(history.doc);
    if (r !== revision) return;
    scene = next;
    if (history.doc.shape.auto && autoHeight()) return build(animate);
    notice(next.warnings.join("；"));
    animationLayer = animate ? selected : null;
    progress =
      animate && !matchMedia("(prefers-reduced-motion: reduce)").matches
        ? 0
        : 1;
    playing = progress < 1;
    draw();
  } catch (e) {
    report(e);
  }
  buttons();
}
function buttons() {
  $("undo").disabled = !history.undoStack.length;
  $("redo").disabled = !history.redoStack.length;
}
function fit() {
  let rect = $("stage").getBoundingClientRect(),
    dpr = Math.min(devicePixelRatio || 1, 3);
  canvas.width = Math.max(1, Math.round(rect.width * dpr));
  canvas.height = Math.max(1, Math.round(rect.height * dpr));
  let s = history.doc.shape;
  view.scale =
    Math.min((rect.width - 48) / s.w, (rect.height - 70) / s.h) * view.zoom;
  view.scale = Math.max(0.05, view.scale);
  view.x = (rect.width - s.w * view.scale) / 2 + view.panX;
  view.y = (rect.height - s.h * view.scale) / 2 + view.panY;
  draw();
}
function draw() {
  const rect = canvas.getBoundingClientRect(),
    dpr = canvas.width / Math.max(1, rect.width);
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, rect.width, rect.height);
  ctx.translate(view.x, view.y);
  ctx.scale(view.scale, view.scale);
  if (exportBg(history.doc) !== "transparent") {
    // 跟导出同一个框：布四周各 70（长线头和影子要地方）
    ctx.fillStyle = exportBg(history.doc);
    ctx.fillRect(-70, -70, history.doc.shape.w + 140, history.doc.shape.h + 140);
  }
  let last = R.render(ctx, history.doc, scene, progress, animationLayer);
  let l = current();
  if (l && !l.hidden && scene.bounds[l.id] && mode === "select") {
    let b = scene.bounds[l.id];
    ctx.save();
    ctx.translate(l.x, l.y);
    ctx.rotate(l.rot || 0);
    ctx.scale(l.scale || 1, l.scale || 1);
    ctx.strokeStyle = window.NIGHT ? "#DADAE4" : "#343444";
    ctx.lineWidth = 1 / view.scale / (l.scale || 1);
    ctx.setLineDash([4, 4]);
    ctx.strokeRect(b[0] - 8, b[1] - 8, b[2] + 16, b[3] + 16);
    ctx.setLineDash([]);
    for (let p of [
      [b[0] + b[2] + 8, b[1] + b[3] + 8],
      [b[0] + b[2] / 2, b[1] - 36],
    ]) {
      ctx.beginPath();
      ctx.arc(...p, 5 / view.scale / (l.scale || 1), 0, Math.PI * 2);
      ctx.fillStyle = "#EEE";
      ctx.fill();
      ctx.stroke();
    }
    ctx.restore();
  }
  if (guide.length || cutPreview) {
    ctx.beginPath();
    (cutPreview || guide).forEach((p, i) =>
      i ? ctx.lineTo(...p) : ctx.moveTo(...p),
    );
    ctx.strokeStyle = color;
    ctx.lineWidth = 2 / view.scale;
    ctx.stroke();
  }
  const yarn = [history.doc.shape.w - 20, history.doc.shape.h + 20];
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(...yarn, 22, 0, Math.PI * 2);
  ctx.fill();
  ctx.save();
  ctx.beginPath();
  ctx.arc(...yarn, 22, 0, Math.PI * 2);
  ctx.clip();
  ctx.strokeStyle = "#FFFFFF30";
  ctx.lineWidth = 1;
  for (let i = -40; i < 45; i += 8) {
    ctx.beginPath();
    ctx.moveTo(yarn[0] - 30, yarn[1] + i);
    ctx.lineTo(yarn[0] + 30, yarn[1] + i + 35);
    ctx.stroke();
  }
  ctx.restore();
  if (playing && last?.kind === "stitch") {
    let p = G.transform(last.stitch.b, last.layer);
    ctx.strokeStyle = last.color;
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(...p);
    ctx.bezierCurveTo(
      p[0] + 20,
      yarn[1] + 20,
      yarn[0] - 50,
      yarn[1] + 60,
      ...yarn,
    );
    ctx.stroke();
    ctx.strokeStyle = "#BFC6CE";
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(p[0] - 25, p[1] - 48);
    ctx.lineTo(...p);
    ctx.stroke();
  }
}
function frame(t) {
  if (playing && scene.ops.length) {
    progress = Math.min(
      1,
      progress +
        ((t - lastTime) * rate) / Math.max(1600, scene.ops.length * 12),
    );
    if (progress >= 1) playing = false;
    draw();
  }
  lastTime = t;
  requestAnimationFrame(frame);
}
requestAnimationFrame(frame);
function point(e) {
  let r = canvas.getBoundingClientRect();
  return [
    (e.clientX - r.left - view.x) / view.scale,
    (e.clientY - r.top - view.y) / view.scale,
  ];
}
function hit(p) {
  for (const l of history.doc.layers.slice().reverse()) {
    if (l.hidden || l.locked) continue;
    let b = scene.bounds[l.id],
      q = G.inverse(p, l);
    if (
      b &&
      q[0] >= b[0] - 10 &&
      q[0] <= b[0] + b[2] + 10 &&
      q[1] >= b[1] - 10 &&
      q[1] <= b[1] + b[3] + 10
    )
      return l;
  }
  return null;
}
canvas.addEventListener("pointerdown", (e) => {
  if (readOnly) return;
  canvas.setPointerCapture(e.pointerId);
  pointers.set(e.pointerId, [e.clientX, e.clientY]);
  if (pointers.size === 2) {
    if (drag?.before) history.doc = drag.before;
    guide = [];
    const p = [...pointers.values()];
    drag = {
      type: "pinch",
      distance: Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]),
      center: [(p[0][0] + p[1][0]) / 2, (p[0][1] + p[1][1]) / 2],
      zoom: view.zoom,
      panX: view.panX,
      panY: view.panY,
    };
    return;
  }
  let p = point(e);
  if (mode === "draw" || mode === "cut") {
    guide = [p];
    return;
  }
  let l = current(),
    b = l && scene.bounds[l.id];
  if (l && !l.locked && b) {
    let q = G.inverse(p, l),
      radius = 20 / view.scale / (l.scale || 1);
    if (Math.hypot(q[0] - b[0] - b[2] - 8, q[1] - b[1] - b[3] - 8) < radius) {
      drag = {
        type: "scale",
        before: G.clone(history.doc),
        start: p,
        layer: G.clone(l),
      };
      return;
    }
    if (Math.hypot(q[0] - b[0] - b[2] / 2, q[1] - b[1] + 36) < radius) {
      drag = {
        type: "rotate",
        before: G.clone(history.doc),
        start: p,
        layer: G.clone(l),
      };
      return;
    }
  }
  l = hit(p);
  selected = l?.id || null;
  if (l)
    drag = {
      type: "move",
      before: G.clone(history.doc),
      start: p,
      layer: G.clone(l),
    };
  draw();
});
canvas.addEventListener("pointermove", (e) => {
  if (!pointers.has(e.pointerId)) return;
  pointers.set(e.pointerId, [e.clientX, e.clientY]);
  if (drag?.type === "pinch" && pointers.size === 2) {
    let p = [...pointers.values()],
      d = Math.hypot(p[0][0] - p[1][0], p[0][1] - p[1][1]);
    view.zoom = Math.max(
      0.4,
      Math.min(5, (drag.zoom * d) / Math.max(1, drag.distance)),
    );
    view.panX = drag.panX + (p[0][0] + p[1][0]) / 2 - drag.center[0];
    view.panY = drag.panY + (p[0][1] + p[1][1]) / 2 - drag.center[1];
    fit();
    return;
  }
  let p = point(e);
  if ((mode === "draw" || mode === "cut") && pointers.size === 1) {
    guide.push(p);
    draw();
    return;
  }
  if (!drag || !current() || drag.type === "pinch") return;
  let l = current(),
    o = drag.layer;
  if (drag.type === "move") {
    l.x = o.x + p[0] - drag.start[0];
    l.y = o.y + p[1] - drag.start[1];
  }
  if (drag.type === "scale")
    l.scale = Math.max(
      0.08,
      Math.min(
        6,
        (o.scale * Math.hypot(p[0] - o.x, p[1] - o.y)) /
          Math.max(1, Math.hypot(drag.start[0] - o.x, drag.start[1] - o.y)),
      ),
    );
  if (drag.type === "rotate")
    l.rot =
      o.rot +
      Math.atan2(p[1] - o.y, p[0] - o.x) -
      Math.atan2(drag.start[1] - o.y, drag.start[0] - o.x);
  draw();
});
function release(e, cancel = false) {
  pointers.delete(e.pointerId);
  if (drag?.type === "pinch") {
    if (!pointers.size) drag = null;
    return;
  }
  if (cancel) {
    if (drag?.before) history.doc = drag.before;
    guide = [];
    drag = null;
    draw();
    return;
  }
  if (mode === "draw" && guide.length > 1) {
    add(base("draw", { x: 0, y: 0, points: G.smooth(G.resample(guide, 3)) }));
    guide = [];
  } else if (mode === "cut" && guide.length > 3) {
    let p = G.resample(guide, 8);
    if (Math.hypot(p[0][0] - p.at(-1)[0], p[0][1] - p.at(-1)[1]) > 60) {
      notice("轮廓还没闭合，请画回起点附近");
      guide = [];
    } else {
      cutPreview = G.smooth(p, true);
      guide = [];
      notice("确认切边后生效，布外内容仍会保留");
    }
  }
  if (drag?.before) {
    let after = G.clone(history.doc);
    history.doc = drag.before;
    history.change((d) => Object.assign(d, after));
    schedule();
  }
  drag = null;
  draw();
}
canvas.addEventListener("pointerup", (e) => release(e));
canvas.addEventListener("pointercancel", (e) => release(e, true));
function el(tag, text, attrs = {}) {
  const n = document.createElement(tag);
  if (text) n.textContent = text;
  Object.assign(n, attrs);
  return n;
}
function button(text, fn, container = $("drawer")) {
  let b = el("button", text);
  b.onclick = fn;
  container.append(b);
  return b;
}
function row() {
  const n = el("div", "", { className: "row" });
  $("drawer").append(n);
  return n;
}
// 1012 她：「保存之后的背景颜色也要可以换，现在全是黑的不好看」——导出的图原来是透明底，相册里显示成黑的。
// 背景跟着作品存（export_bg），默认米白；编辑时布外面那一圈就画成这个色，所见即所得
const BG_CHOICES = [
  ["白", "#FFFFFF"],
  ["米白", "#F4F1EC"],
  ["雾粉", "#F3E6EA"],
  ["雾蓝", "#E6ECF2"],
  ["炭灰", "#2A2B31"],
  ["透明", "transparent"],
];
function exportBg(doc) {
  return doc.export_bg || "#F4F1EC";
}
function bgRow(pick) {
  let r = row();
  r.append(el("span", "背景"));
  for (const [name, color] of BG_CHOICES) {
    let b = button(name, () => pick(color), r);
    b.style.borderBottom =
      "5px " + (color === "transparent" ? "dashed #999" : "solid " + color);
    if (exportBg(history.doc) === color) b.style.fontWeight = "700";
  }
  let custom = el("input", "", { type: "color", value: "#F4F1EC" });
  custom.oninput = () => pick(custom.value);
  r.append(custom);
  return r;
}
// 1012 布色（原色＝这种布本来的颜色）
const CLOTH_COLORS = [
  ["原色", null],
  ["米白", "#F4F1EC"],
  ["浅粉", "#F3DDE3"],
  ["浅黄", "#F3EBCD"],
  ["薄荷", "#DCEFE6"],
  ["浅蓝", "#DDE7F3"],
  ["浅紫", "#E6DFF0"],
  ["浅灰", "#E3E3E6"],
];
const BORDER_PRESETS = [
  ["bow", "蝴蝶结"],
  ["vine", "花藤"],
  ["hearts", "小爱心"],
  ["wheat", "麦穗"],
  ["starmoon", "星星月亮"],
  ["wave", "波浪边"],
  ["lock", "锁边"],
];
const BORDER_COLORS = ["#D23C77", "#C8333F", "#E89AB0", "#6E4C8E", "#3B5BA9", "#2AA3B8", "#1F8A70", "#5A9E3A", "#232326", "#ECE6DA"];
function setPresetBorder(key) {
  change((d) => {
    const i = d.layers.findIndex((l) => String(l.asset).startsWith("preset:"));
    if (!key) { if (i >= 0) d.layers.splice(i, 1); return; }
    if (i >= 0) { d.layers[i].asset = "preset:" + key; return; }
    d.layers.unshift({ id: uid(), type: "border", asset: "preset:" + key, mode: "loop", color: "#D23C77", x: 0, y: 0, scale: 1, rot: 0, stitch: 4, width: 2.4 });
  });
  openTool("border");
}
// 1012 上下对齐：用这段字绣出来的实际范围（scene.bounds）挪 y
function verticalAlign(where) {
  const l = current();
  if (!l || l.type !== "text" || !scene.bounds[l.id]) return;
  const b = scene.bounds[l.id], H = history.doc.shape.h, pad = 40, sc = l.scale || 1;
  const height = b[3] * sc, top = b[1] * sc;
  const y = where === "top" ? pad - top : where === "bottom" ? H - pad - height - top : (H - height) / 2 - top;
  property((x) => (x.y = y));
}
// 1012 长卷：布的高度跟着内容走（最低 460，最高 3000），角花跟着贴到新的底边
function autoHeight() {
  const d = history.doc;
  let bottom = 0;
  for (const l of d.layers) {
    if (l.mode === "loop" || l.anchor || l.hidden || !scene.bounds[l.id]) continue;
    const b = scene.bounds[l.id];
    bottom = Math.max(bottom, (l.y || 0) + (b[1] + b[3]) * (l.scale || 1));
  }
  const target = Math.max(460, Math.min(3000, Math.ceil(bottom + 70)));
  if (Math.abs(target - d.shape.h) < 12) return false;
  d.shape.h = target;
  for (const l of d.layers.filter((l) => l.anchor && l.anchor[1]))
    l.y = target - 24 - ((l.h || 100) * l.scale) / 2;
  fit();
  return true;
}
let lastSearch = "", lastResults = null;
async function runSearch(text, box) {
  text = (text || "").trim();
  if (!text) return;
  lastSearch = text;
  box.replaceChildren(el("small", "搜索中…"));
  try {
    const r = await api("search", { q: text });
    lastResults = r;
    showResults(r, box);
  } catch (e) {
    box.replaceChildren(el("small", "搜索失败：" + e.message));
  }
}
function showResults(r, box) {
  box.replaceChildren();
  const all = (r.local || []).concat(r.icons || []);
  if (!all.length) { box.append(el("small", "没搜到，换个词试试（比如 花、星星、猫、月亮）")); return; }
  for (const a of all) {
    let b = button(
      "",
      () => {
        add(base("motif", { asset: a.id, scale: Math.min(1, 150 / a.w), w: a.w, h: a.h, corner: a.corner || [0, 0] }));
        openTool("object");
      },
      box,
    );
    b.title = a.id;
    b.append(el("img", "", { src: "data/" + a.file, alt: a.id, loading: "lazy" }));
  }
}
function select(options, value, fn, container) {
  let n = el("select");
  for (const [v, t] of options)
    n.append(el("option", t, { value: v, selected: v === value }));
  n.onchange = () => fn(n.value);
  container.append(n);
  return n;
}
function range(name, min, max, value, fn, container) {
  let label = el("label", name + " "),
    n = el("input", "", { type: "range", min, max, value, step: 1 });
  n.onchange = () => fn(+n.value);
  label.append(n);
  container.append(label);
  return n;
}
function property(fn) {
  if (!current() || current().locked) return;
  change((d) => fn(d.layers.find((l) => l.id === selected)));
}
function openTool(id) {
  if (readOnly && id) {
    notice("这是定版，先另存新版本再修改");
    return;
  }
  tool = id;
  mode = id === "draw" ? "draw" : "select";
  guide = [];
  cutPreview = null;
  $("drawer").replaceChildren();
  document
    .querySelectorAll("#tools button")
    .forEach((b) => b.classList.toggle("active", b.dataset.tool === id));
  if (id === "fabric") {
    let r = row();
    for (const [key, f] of Object.entries(R.fabrics)) {
      let b = button(
        f.name,
        () =>
          change((d) => {
            d.fabric = key;
          }),
        r,
      );
      b.style.borderBottom = "5px solid " + f.color;
    }
    // 1012 布色：同一种布换颜色（原色＝这种布本来的颜色）
    let cr = row();
    cr.append(el("span", "布色"));
    for (const [name, color] of CLOTH_COLORS) {
      let b = button(name, () => change((d) => { if (color) d.cloth_color = color; else delete d.cloth_color; }), cr);
      b.style.borderBottom = "5px solid " + (color || R.fabrics[history.doc.fabric]?.color || "#F1EFEC");
      if ((history.doc.cloth_color || null) === color) b.style.fontWeight = "700";
    }
    bgRow((color) =>
      change((d) => {
        d.export_bg = color;
      }),
    );
  }
  if (id === "shape") {
    let dimensions = row();
    for (const [name, w, h] of [
      ["小卡片 5:3", 800, 480],
      ["方形 1:1", 650, 650],
      ["竖版 3:4", 540, 720],
      ["横版 16:9", 800, 450],
    ])
      button(
        name,
        () => {
          change((d) => {
            delete d.shape.auto;
            let sx = w / d.shape.w,
              sy = h / d.shape.h;
            d.shape.w = w;
            d.shape.h = h;
            if (d.shape.points)
              d.shape.points = d.shape.points.map(([x, y]) => [x * sx, y * sy]);
            for (const l of d.layers) {
              if (l.mode === "loop") continue;
              l.x = (l.x || 0) * sx;
              l.y = (l.y || 0) * sy;
              if (l.anchor) {
                l.x = l.anchor[0]
                  ? w - 24 - ((l.w || 100) * l.scale) / 2
                  : 24 + ((l.w || 100) * l.scale) / 2;
                l.y = l.anchor[1]
                  ? h - 24 - ((l.h || 100) * l.scale) / 2
                  : 24 + ((l.h || 100) * l.scale) / 2;
              }
            }
          });
          openTool("shape");
          fit();
        },
        dimensions,
      );
    // 1012 长卷：字多了布自动往下变长（只长高，宽度不动）
    let longb = button(
      "长卷 · 自动变长",
      () => {
        change((d) => {
          d.shape.auto = !d.shape.auto;
          if (d.shape.kind !== "rect" && d.shape.auto) d.shape.kind = "rect";
        });
        openTool("shape");
        fit();
      },
      dimensions,
    );
    if (history.doc.shape.auto) longb.style.fontWeight = "700";
    for (const [axis, label] of [
      ["w", "布宽"],
      ["h", "布高"],
    ])
      range(
        label,
        300,
        1000,
        history.doc.shape[axis],
        (v) => {
          change((d) => {
            const old = d.shape[axis];
            d.shape[axis] = v;
            for (const l of d.layers.filter(
              (l) => !l.anchor && l.mode !== "loop",
            )) {
              const k = axis === "w" ? "x" : "y";
              l[k] = ((l[k] || 0) * v) / old;
            }
            if (d.shape.points)
              d.shape.points = d.shape.points.map((p) =>
                axis === "w"
                  ? [(p[0] * v) / old, p[1]]
                  : [p[0], (p[1] * v) / old],
              );
            for (const l of d.layers.filter((l) => l.anchor)) {
              l.x = l.anchor[0]
                ? d.shape.w - 24 - ((l.w || 100) * l.scale) / 2
                : 24 + ((l.w || 100) * l.scale) / 2;
              l.y = l.anchor[1]
                ? d.shape.h - 24 - ((l.h || 100) * l.scale) / 2
                : 24 + ((l.h || 100) * l.scale) / 2;
            }
          });
          fit();
        },
        dimensions,
      );
    let r = row();
    for (const [key, n] of [
      ["rect", "长方形"],
      ["circle", "圆形"],
      ["heart", "爱心"],
      ["star", "星星"],
    ])
      button(
        n,
        () => {
          change((d) => {
            d.shape.kind = key;
          });
          fit();
        },
        r,
      );
    button(
      "自己画",
      () => {
        mode = "cut";
        notice("沿布面画闭合轮廓");
        const r = row();
        button(
          "确认切边",
          () => {
            if (!cutPreview) {
              notice("先画一个闭合轮廓");
              return;
            }
            change((d) => {
              d.shape.kind = "custom";
              d.shape.points = cutPreview;
              d.shape.path =
                "M" + cutPreview.map((p) => p.join(",")).join(" L") + " Z";
            });
            mode = "select";
            cutPreview = null;
            openTool("shape");
          },
          r,
        );
        button("取消", () => openTool("shape"), r);
      },
      r,
    );
  }
  if (id === "text") {
    let l = current();
    if (l?.type !== "text") {
      l = base("text", {
        text: "",
        colorMode: textRandomColor ? "random-character" : "solid",
        font: "kai-stroke",
        size: 100,
        align: "left",
        lineGap: 1.35,
        x: 100,
        y: 150,
      });
      add(l, false);
    }
    let ta = el("textarea", "", {
      id: "editorText",
      value: l.text,
      placeholder: "在布上留一句话…",
    });
    $("drawer").append(ta);
    ta.addEventListener("compositionstart", () => (isComposing = true));
    ta.addEventListener("compositionend", () => {
      isComposing = false;
      property((l) => (l.text = ta.value));
      clearTimeout(compileTimer);
      compileTimer = setTimeout(() => build(true), 25);
    });
    ta.oninput = () => {
      if (!isComposing) {
        property((l) => (l.text = ta.value));
        clearTimeout(compileTimer);
        compileTimer = setTimeout(() => build(true), 180);
      }
    };
    ta.onfocus = () => {
      document.body.classList.add("typing");
      setTimeout(fit, 100);
    };
    ta.onblur = () => {
      document.body.classList.remove("typing");
      setTimeout(fit, 100);
    };
    let r = row();
    select(
      EMB_FONTS.map((f) => [f.id, f.name]),
      l.font,
      (v) => property((l) => (l.font = v)),
      r,
    );
    range("字号", 12, 160, l.size, (v) => property((l) => (l.size = v)), r);
    range(
      "行距",
      1,
      2,
      l.lineGap || 1.35,
      (v) => property((l) => (l.lineGap = v)),
      r,
    ).step = 0.05;
    range(
      "字距",
      0,
      40,
      l.letterSpacing || 0,
      (v) => property((l) => (l.letterSpacing = v)),
      r,
    );
    select(
      [
        ["left", "左对齐"],
        ["center", "居中"],
        ["right", "右对齐"],
      ],
      l.align,
      (v) => property((l) => (l.align = v)),
      r,
    );
    button(
      "绣出来",
      () => {
        ta.blur();
        build(true);
      },
      r,
    );
    // 1012 上下：整段字在布上靠上 / 居中 / 靠下（按这段字实际绣出来的高度算）
    let vr = row();
    vr.append(el("span", "上下"));
    for (const [key, name] of [["top", "靠上"], ["middle", "居中"], ["bottom", "靠下"]])
      button(name, () => verticalAlign(key), vr);
    // 1012 渐变一排：点哪组用哪组
    let gr = row();
    gr.append(el("span", "渐变"));
    for (const [name, stops] of R.GRADIENTS) {
      let g = button(name, () => setGradient(stops), gr);
      g.style.backgroundImage = "linear-gradient(90deg," + stops.join(",") + ")";
      g.style.color = stops[0] === "#F0B8C8" ? "#333" : "#fff";
      if (l.colorMode === "gradient" && JSON.stringify(l.gradient) === JSON.stringify(stops)) g.style.fontWeight = "700";
    }
    notice("楷体按笔顺；其他字体沿中线绣");
  }
  if (id === "draw") {
    notice("手指画线，松手后落针；双指移动画布");
    let r = row();
    button("完成", () => openTool(null), r);
    button(
      "取消当前笔",
      () => {
        guide = [];
        mode = "select";
        openTool(null);
      },
      r,
    );
  }
  if (id === "image") {
    let l = current();
    if (l?.type === "image") {
      let r = row();
      button("印在布上", () => property((l) => (l.style = "print")), r);
      button("缝成补丁", () => property((l) => (l.style = "patch")), r);
      range(
        "裁切放大",
        100,
        250,
        Math.round(100 / (l.crop?.w || 1)),
        (v) =>
          property((l) => {
            let w = 100 / v;
            l.crop = { x: (1 - w) / 2, y: (1 - w) / 2, w, h: w };
          }),
        r,
      );
    }
    button("从相册选图", () => {
      if (!bridge("pickImage")) {
        let input = el("input", "", { type: "file", accept: "image/*" });
        input.onchange = () => {
          let f = input.files[0];
          if (!f) return;
          let reader = new FileReader();
          reader.onload = () => chooseImage(reader.result);
          reader.readAsDataURL(f);
        };
        input.click();
      }
    });
  }
  if (id === "border") {
    // 1012 一键花边：点一下整圈花边就上去；再点别的就换，「不要花边」拿掉；下面挑花边颜色
    const cur = history.doc.layers.find((l) => String(l.asset).startsWith("preset:"));
    let r = row();
    for (const [key, name] of BORDER_PRESETS) {
      let b = button(name, () => setPresetBorder(key), r);
      if (cur && cur.asset === "preset:" + key) b.style.fontWeight = "700";
    }
    button("不要花边", () => setPresetBorder(null), r);
    let cr = row();
    cr.append(el("span", "花边色"));
    for (const c of BORDER_COLORS) {
      let b = button("", () => change((d) => { const l = d.layers.find((x) => String(x.asset).startsWith("preset:")); if (l) l.color = c; }), cr);
      b.className = "spool";
      b.title = c;
      b.style.background = c;
    }
  }
  if (id === "assets") {
    // 1012 搜素材：像修图软件搜贴纸，先出预览，点一下贴到布上再调
    let sr = row();
    let q = el("input", "", { type: "search", placeholder: "搜素材：星星、蝴蝶、角花…", value: lastSearch });
    q.style.flex = "1";
    sr.append(q);
    let go = button("搜", () => runSearch(q.value, results), sr);
    q.onkeydown = (e) => { if (e.key === "Enter") { e.preventDefault(); q.blur(); runSearch(q.value, results); } };
    let results = el("div", "", { className: "assets" });
    $("drawer").append(results);
    if (lastSearch && lastResults) showResults(lastResults, results);
    let grid = el("div", "", { className: "assets" });
    $("drawer").append(el("small", "全部素材"));
    $("drawer").append(grid);
    for (const a of assets) {
      let b = button(
        "",
        () => {
          add(
            base("motif", {
              asset: a.id,
              scale: Math.min(1, 150 / a.w),
              w: a.w,
              h: a.h,
              corner: a.corner,
            }),
          );
          openTool("object");
        },
        grid,
      );
      b.title = a.id;
      let im = el("img", "", {
        src: "data/assets/" + a.file,
        alt: a.id,
        loading: "lazy",
      });
      b.append(im);
    }
  }
  if (id === "layers") layerPanel();
  if (id === "object" && current()) {
    let l = current(),
      r = row();
    button(
      "删除",
      () => {
        change((d) => {
          d.layers = d.layers.filter((x) => x.id !== selected);
        });
        selected = null;
        openTool(null);
      },
      r,
    );
    button(
      l.locked ? "解锁" : "锁定",
      () => {
        change((d) => {
          const v = d.layers.find((x) => x.id === selected);
          v.locked = !v.locked;
        });
        openTool("object");
      },
      r,
    );
    if (l.type === "text") button("改字", () => openTool("text"), r);
    if (l.type === "image") button("图片样式", () => openTool("image"), r);
    if (l.type === "motif" || l.type === "border") {
      range(
        "线粗",
        1,
        10,
        l.width || 3,
        (v) => property((l) => (l.width = v)),
        r,
      ).step = 0.5;
      button("补齐四角", corners, r);
      button(
        "绕一圈",
        () =>
          property((l) => {
            l.type = "border";
            l.mode = "loop";
            l.x = 0;
            l.y = 0;
            l.scale = 1;
            l.rot = 0;
          }),
        r,
      );
    }
  }
  setTimeout(fit, 0);
}
function layerPanel() {
  for (const l of history.doc.layers.slice().reverse()) {
    let r = el("div", "", { className: "layer", draggable: true });
    $("drawer").append(r);
    const thumb = el("canvas");
    thumb.width = 40;
    thumb.height = 30;
    thumb.style.cssText = "width:40px;height:30px;flex-shrink:0";
    const tx = thumb.getContext("2d");
    let box = scene.bounds[l.id];
    if (box) {
      let scale = Math.min(36 / Math.max(1, box[2]), 26 / Math.max(1, box[3]));
      tx.translate(2 - box[0] * scale, 2 - box[1] * scale);
      tx.scale(scale, scale);
      for (const o of scene.ops.filter((o) => o.layer.id === l.id)) {
        if (o.kind === "stitch") {
          tx.strokeStyle = o.color;
          tx.lineWidth = o.stitch.width;
          tx.beginPath();
          tx.moveTo(...o.stitch.a);
          tx.lineTo(...o.stitch.b);
          tx.stroke();
        } else tx.drawImage(o.image, -o.w / 2, -o.h / 2, o.w, o.h);
      }
    }
    r.append(thumb);
    button(
      (l.id === selected ? "✓ " : "") +
        (l.text?.slice(0, 12) ||
          { image: "照片", draw: "手绘线", motif: "花样", border: "花边" }[
            l.type
          ] ||
          l.type),
      () => {
        selected = l.id;
        openTool("object");
        draw();
      },
      r,
    );
    button(
      l.hidden ? "显示" : "隐藏",
      () => {
        change((d) => {
          let x = d.layers.find((x) => x.id === l.id);
          x.hidden = !x.hidden;
        });
        openTool("layers");
      },
      r,
    );
    button(
      l.locked ? "解锁" : "锁定",
      () => {
        change((d) => {
          let x = d.layers.find((x) => x.id === l.id);
          x.locked = !x.locked;
        });
        openTool("layers");
      },
      r,
    );
    button("↑", () => reorder(l.id, 1), r);
    button("↓", () => reorder(l.id, -1), r);
    r.ondragstart = (e) => e.dataTransfer.setData("text/plain", l.id);
    r.ondragover = (e) => e.preventDefault();
    r.ondrop = (e) => {
      e.preventDefault();
      let id = e.dataTransfer.getData("text/plain");
      change((d) => {
        let from = d.layers.findIndex((x) => x.id === id),
          to = d.layers.findIndex((x) => x.id === l.id);
        if (from >= 0 && to >= 0)
          d.layers.splice(to, 0, d.layers.splice(from, 1)[0]);
      });
      openTool("layers");
    };
  }
}
function reorder(id, delta) {
  change((d) => {
    let i = d.layers.findIndex((l) => l.id === id),
      j = Math.max(0, Math.min(d.layers.length - 1, i + delta));
    d.layers.splice(j, 0, d.layers.splice(i, 1)[0]);
  });
  openTool("layers");
}
function corners() {
  let l = current();
  if (!l || l.locked) return;
  change((d) => {
    let src = d.layers.find((x) => x.id === l.id),
      w = d.shape.w,
      h = d.shape.h,
      margin = 24,
      halfW = ((src.w || 100) * src.scale) / 2,
      halfH = ((src.h || 100) * src.scale) / 2;
    let corner = src.corner || [0, 0];
    for (let y = 0; y < 2; y++)
      for (let x = 0; x < 2; x++) {
        let n = x === corner[0] && y === corner[1] ? src : G.clone(src);
        if (n !== src) {
          n.id = uid();
          d.layers.push(n);
        }
        n.mode = "single";
        n.anchor = [x, y];
        n.x = x ? w - margin - halfW : margin + halfW;
        n.y = y ? h - margin - halfH : margin + halfH;
        n.flipX = x !== corner[0];
        n.flipY = y !== corner[1];
        n.rot = 0;
      }
  });
  openTool("layers");
}
async function chooseImage(src) {
  pendingImage = src;
  $("drawer").replaceChildren();
  let r = row();
  for (const [style, label] of [
    ["print", "印在布上"],
    ["patch", "缝成补丁"],
  ]) {
    let b = button(
      label,
      async () => {
        let im = await R.image(src);
        add(
          base("image", {
            src,
            style,
            w: 220,
            h: (220 * im.height) / im.width,
            crop: { x: 0, y: 0, w: 1, h: 1 },
          }),
          false,
        );
        pendingImage = null;
        openTool("image");
      },
      r,
    );
    let preview = el("img", "", { src });
    preview.style.cssText =
      "display:block;width:90px;height:65px;object-fit:cover;" +
      (style === "patch" ? "border:2px dashed currentColor;" : "opacity:.7");
    b.prepend(preview);
  }
  button(
    "取消",
    () => {
      pendingImage = null;
      openTool(null);
    },
    r,
  );
  fit();
}
const colors = [
  "#B8325A",
  "#6E4C8E",
  "#2F4C9B",
  "#2F5E4E",
  "#232326",
  "#ECE6DA",
];
button(
  "逐字混色",
  () => {
    textRandomColor = true;
    property((l) => {
      if (l.type === "text") l.colorMode = "random-character";
    });
    document
      .querySelectorAll(".spool")
      .forEach((b) => b.classList.remove("active"));
  },
  $("palette"),
);
// 1012 渐变：每点一下换一组渐变，按钮上画着这组颜色
let gradientIndex = -1;
let gradButton = button(
  "渐变",
  () => {
    gradientIndex = (gradientIndex + 1) % R.GRADIENTS.length;
    setGradient(R.GRADIENTS[gradientIndex][1]);
  },
  $("palette"),
);
gradButton.style.backgroundImage = "linear-gradient(90deg," + R.GRADIENTS[0][1].join(",") + ")";
gradButton.style.color = "#fff";
function setGradient(stops) {
  textRandomColor = false;
  property((l) => {
    if (l.type === "text") { l.colorMode = "gradient"; l.gradient = stops; }
  });
  gradButton.style.backgroundImage = "linear-gradient(90deg," + stops.join(",") + ")";
  document.querySelectorAll(".spool").forEach((b) => b.classList.remove("active"));
  draw();
}
for (const c of colors) {
  let b = button("", () => setColor(c), $("palette"));
  b.className = "spool";
  b.style.setProperty("--thread", c);
  b.title = c;
}
let colorInput = el("input", "", {
  type: "color",
  value: color,
  title: "自定义线色",
});
colorInput.oninput = () => setColor(colorInput.value);
$("palette").append(colorInput);
button(
  "跳过",
  () => {
    playing = false;
    progress = 1;
    draw();
  },
  $("palette"),
);
function setColor(c) {
  textRandomColor = false;
  color = c;
  property((l) => {
    l.color = c;
    if (l.type === "text") l.colorMode = "solid";
  });
  document
    .querySelectorAll(".spool")
    .forEach((b) => b.classList.toggle("active", b.title === c));
  draw();
}
for (const [id, name] of [
  ["fabric", "布料"],
  ["shape", "形状"],
  ["text", "绣字"],
  ["draw", "画线"],
  ["image", "图片"],
  ["border", "花边"],
  ["assets", "素材"],
  ["object", "选中项"],
]) {
  let b = button(name, () => openTool(id), $("tools"));
  b.dataset.tool = id;
}
$("undo").onclick = () => {
  if (readOnly) return;
  history.undo();
  selected = null;
  schedule();
};
$("redo").onclick = () => {
  if (readOnly) return;
  history.redo();
  selected = null;
  schedule();
};
$("layers").onclick = () => openTool("layers");
$("full").onclick = () => bridge("toggleFull");
$("close").onclick = () => {
  save();
  bridge("close", { document: readOnly ? null : history.doc });
};
$("keyboardHide").onclick = () => document.activeElement?.blur();
$("keyboardFont").onclick = () => {
  $("drawer").querySelector("select")?.focus();
};
// 1012 存图两种：透明 PNG（不画背景）/ 带桌面 JPG（画上选的背景色；选的是透明就用米白）
async function exportCanvas(mode = "auto", k = 2) {
  const s = history.doc.shape,
    c = document.createElement("canvas");
  c.width = (s.w + 140) * k;
  c.height = (s.h + 140) * k;
  let x = c.getContext("2d");
  x.scale(k, k);
  let bg = exportBg(history.doc);
  if (mode === "transparent") bg = "transparent";
  if (mode === "solid" && bg === "transparent") bg = "#F4F1EC";
  if (bg !== "transparent") {
    x.fillStyle = bg;
    x.fillRect(0, 0, s.w + 140, s.h + 140);
  }
  x.translate(70, 70);
  let sc = await R.compile(history.doc);
  R.render(x, history.doc, sc, 1);
  return c;
}
async function exportPNG(mode = "auto") {
  return (await exportCanvas(mode)).toDataURL("image/png");
}
async function exportJPG() {
  return (await exportCanvas("solid")).toDataURL("image/jpeg", 0.92);
}
// 1012 存绣字的过程：照回放一帧帧画（只放最终留下的针脚），存成 GIF 动图或视频
async function replayFrames(onFrame, frames = 60, hold = 14, k = 1) {
  const s = history.doc.shape, w = (s.w + 140) * k, h = (s.h + 140) * k;
  const c = document.createElement("canvas");
  c.width = Math.round(w); c.height = Math.round(h);
  const x = c.getContext("2d");
  const sc = await R.compile(history.doc);
  let bg = exportBg(history.doc);
  if (bg === "transparent") bg = "#F4F1EC";
  for (let i = 0; i <= frames + hold; i++) {
    x.setTransform(k, 0, 0, k, 0, 0);
    x.fillStyle = bg;
    x.fillRect(0, 0, s.w + 140, s.h + 140);
    x.translate(70, 70);
    R.render(x, history.doc, sc, Math.min(1, i / frames));
    await onFrame(c, i);
  }
  return c;
}
async function exportGIF() {
  const s = history.doc.shape, k = Math.min(1, 560 / (s.w + 140));
  const enc = new GifWriter();
  // 调色板按成品算：第一帧还没有线，按它算线的颜色就全丢了
  const fin = await exportCanvas("solid", k);
  const palette = GifWriter.palette(fin.getContext("2d").getImageData(0, 0, fin.width, fin.height).data);
  await replayFrames(async (c, i) => {
    const d = c.getContext("2d").getImageData(0, 0, c.width, c.height);
    enc.frame(c.width, c.height, d.data, palette, i >= 60 ? 12 : 8);
    if (i % 6 === 0) await new Promise((r) => setTimeout(r, 0));
  }, 60, 14, k);
  return "data:image/gif;base64," + enc.base64();
}
async function exportVideo() {
  if (!window.MediaRecorder) throw Error("这台设备不支持录视频，先存 GIF 吧");
  const s = history.doc.shape, k = Math.min(1.5, 900 / (s.w + 140));
  const c = document.createElement("canvas");
  c.width = Math.round((s.w + 140) * k); c.height = Math.round((s.h + 140) * k);
  const stream = c.captureStream(30);
  const type = ["video/mp4", "video/webm;codecs=vp9", "video/webm"].find((t) => MediaRecorder.isTypeSupported(t)) || "";
  const rec = new MediaRecorder(stream, type ? { mimeType: type } : {});
  const chunks = [];
  rec.ondataavailable = (e) => e.data.size && chunks.push(e.data);
  const done = new Promise((r) => (rec.onstop = r));
  rec.start();
  const x = c.getContext("2d");
  await replayFrames(async (frame) => {
    x.drawImage(frame, 0, 0);
    await new Promise((r) => setTimeout(r, 1000 / 24));
  }, 96, 30, k);
  rec.stop();
  await done;
  const blob = new Blob(chunks, { type: rec.mimeType || type || "video/mp4" });
  return await new Promise((resolve) => { const fr = new FileReader(); fr.onload = () => resolve(fr.result); fr.readAsDataURL(blob); });
}
// 极简 GIF 编码（256 色、LZW）：手机上几秒能编完一段回放
class GifWriter {
  constructor() { this.bytes = []; this.started = false; }
  static palette(rgba) {
    const counts = new Map();
    for (let i = 0; i < rgba.length; i += 16) {
      const key = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
      counts.set(key, (counts.get(key) || 0) + 1);
    }
    const top = [...counts.entries()].sort((a, b) => b[1] - a[1]).slice(0, 256).map(([k]) => [((k >> 10) & 31) * 8 + 4, ((k >> 5) & 31) * 8 + 4, (k & 31) * 8 + 4]);
    while (top.length < 256) top.push([0, 0, 0]);
    return top;
  }
  u16(v) { this.bytes.push(v & 255, (v >> 8) & 255); }
  frame(w, h, rgba, pal, delay) {
    const B = this.bytes;
    if (!this.started) {
      this.started = true;
      for (const ch of "GIF89a") B.push(ch.charCodeAt(0));
      this.u16(w); this.u16(h); B.push(0xf7, 0, 0);
      for (const [r, g, b] of pal) B.push(r, g, b);
      B.push(0x21, 0xff, 11); for (const ch of "NETSCAPE2.0") B.push(ch.charCodeAt(0)); B.push(3, 1, 0, 0, 0);
    }
    B.push(0x21, 0xf9, 4, 0); this.u16(delay); B.push(0, 0);
    B.push(0x2c); this.u16(0); this.u16(0); this.u16(w); this.u16(h); B.push(0);
    const cache = new Map(), idx = new Uint8Array(w * h);
    for (let i = 0, p = 0; i < rgba.length; i += 4, p++) {
      const key = ((rgba[i] >> 3) << 10) | ((rgba[i + 1] >> 3) << 5) | (rgba[i + 2] >> 3);
      let v = cache.get(key);
      if (v === undefined) {
        let best = 0, bd = 1e9;
        for (let j = 0; j < 256; j++) {
          const q = pal[j], dd = (q[0] - rgba[i]) ** 2 + (q[1] - rgba[i + 1]) ** 2 + (q[2] - rgba[i + 2]) ** 2;
          if (dd < bd) { bd = dd; best = j; }
        }
        cache.set(key, (v = best));
      }
      idx[p] = v;
    }
    this.lzw(idx);
  }
  lzw(idx) {
    const B = this.bytes, min = 8, clear = 256, eoi = 257;
    let size = 9, next = 258, dict = new Map(), out = [], cur = 0, bits = 0;
    const emit = (code) => { cur |= code << bits; bits += size; while (bits >= 8) { out.push(cur & 255); cur >>= 8; bits -= 8; } };
    B.push(min);
    emit(clear);
    let prefix = idx[0];
    for (let i = 1; i < idx.length; i++) {
      const c = idx[i], key = prefix * 256 + c, hit = dict.get(key);
      if (hit !== undefined) { prefix = hit; continue; }
      emit(prefix);
      if (next < 4096) { dict.set(key, next++); if (next > (1 << size) && size < 12) size++; }
      else { emit(clear); dict = new Map(); next = 258; size = 9; }
      prefix = c;
    }
    emit(prefix); emit(eoi);
    if (bits > 0) out.push(cur & 255);
    for (let i = 0; i < out.length; i += 255) { const chunk = out.slice(i, i + 255); B.push(chunk.length, ...chunk); }
    B.push(0);
  }
  base64() {
    this.bytes.push(0x3b);
    let bin = "";
    for (let i = 0; i < this.bytes.length; i += 32768) bin += String.fromCharCode.apply(null, this.bytes.slice(i, i + 32768));
    return btoa(bin);
  }
}
$("done").onclick = () => {
  document.activeElement?.blur();
  $("drawer").replaceChildren();
  let r = row();
  button(
    "存相册",
    async () => {
      try {
        const png = await exportPNG();
        if (!bridge("exportPNG", { png })) {
          let a = el("a", "", { download: "embroidery.png", href: png });
          a.click();
        }
      } catch (e) {
        report(e);
      }
    },
    r,
  );
  button("继续绣", () => openTool(null), r);
  notice("草稿保留在本机；发送和拼布被在下一阶段接入");
  fit();
};
window.__emb = (kind, p) => {
  if (window.EmbFinish?.receive(kind, p)) return;
  if (kind === "appearance") {
    window.NIGHT = !!p.night;
    document.body.classList.toggle("night", window.NIGHT);
    document.documentElement.style.setProperty(
      "--safe-top",
      (p.safeTop || 0) + "px",
    );
    document.documentElement.style.setProperty(
      "--safe-bottom",
      (p.safeBottom || 0) + "px",
    );
    fit();
  }
  if (kind === "load") {
    history = new G.History(p);
    selected = null;
    fit();
    schedule();
  }
  if (kind === "image") chooseImage(p.src);
  if (kind === "saved") $("status").textContent = "草稿已存";
  if (kind === "error") notice(p.message);
};
window.EmbEditor = {
  get document() {
    return G.clone(history.doc);
  },
  load: (d) => __emb("load", d),
  exportPNG,
  build,
  get scene() {
    return scene;
  },
  get history() {
    return history;
  },
};
new ResizeObserver(fit).observe($("stage"));
window.visualViewport?.addEventListener("resize", () => {
  document.querySelector("main").style.height = visualViewport.height + "px";
  fit();
});
(async () => {
  try {
    EMB_FONTS = await (await fetch("fonts.json")).json();
    if (!bridge("ready")) {
      let stored = localStorage.getItem("embroidery.draft");
      if (stored) history = new G.History(JSON.parse(stored));
    }
    __emb("appearance", { night: !!window.NIGHT });
    await build();
    try {
      const response = await fetch("data/assets/index.json");
      if (!response.ok) throw Error("花边资源暂不可用，其他工具仍可使用");
      assets = await response.json();
    } catch (e) {
      report(e);
    }
  } catch (e) {
    report(e);
  }
})();
