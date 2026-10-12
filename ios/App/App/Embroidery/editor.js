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
    bgRow((color) =>
      change((d) => {
        d.export_bg = color;
      }),
    );
  }
  if (id === "shape") {
    let dimensions = row();
    for (const [name, w, h] of [
      ["横版", 800, 460],
      ["竖版", 520, 700],
      ["方形", 650, 650],
    ])
      button(
        name,
        () => {
          change((d) => {
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
  if (id === "assets") {
    let grid = el("div", "", { className: "assets" });
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
  ["assets", "花边"],
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
async function exportPNG() {
  const s = history.doc.shape,
    c = document.createElement("canvas");
  c.width = (s.w + 140) * 2;
  c.height = (s.h + 140) * 2;
  let x = c.getContext("2d");
  x.scale(2, 2);
  if (exportBg(history.doc) !== "transparent") {
    x.fillStyle = exportBg(history.doc);
    x.fillRect(0, 0, s.w + 140, s.h + 140);
  }
  x.translate(70, 70);
  let sc = await R.compile(history.doc);
  R.render(x, history.doc, sc, 1);
  return c.toDataURL("image/png");
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
