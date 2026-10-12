/* Single-line glyph generation. Centerline fonts explicitly have no stroke-order claim. */
(function (root) {
  "use strict";
  const G = EmbGeometry,
    cache = new Map(),
    fontCache = new Map();
  async function json(url) {
    const r = await fetch(url);
    if (!r.ok) throw Error("资源未下载：" + url);
    return r.json();
  }
  function hershey(d) {
    const groups = d.match(/M[^M]+/g) || [];
    return groups.map((s) => {
      const a = s.match(/-?\d+(?:\.\d+)?/g).map(Number),
        p = [];
      for (let i = 0; i < a.length; i += 2) p.push([a[i], a[i + 1]]);
      return p;
    });
  }
  async function font(file) {
    if (fontCache.size >= 2 && !fontCache.has(file))
      fontCache.delete(fontCache.keys().next().value);
    if (!fontCache.has(file))
      fontCache.set(
        file,
        (async () => {
          let r = await fetch("font/" + file);
          if (!r.ok) throw Error("字体下载失败，请重试");
          return opentype.parse(await r.arrayBuffer());
        })().catch((e) => {
          fontCache.delete(file);
          throw e;
        }),
      );
    return fontCache.get(file);
  }
  async function glyph(c, conf) {
    const key = conf.id + ":" + c;
    if (cache.has(key)) return cache.get(key);
    let result;
    if (c === " ") {
      result = { paths: [], advance: 0.4 };
    } else if (conf.type === "stroke" && c.codePointAt(0) > 127) {
      try {
        const data = await json(
          "data/hanzi/" + encodeURIComponent(c) + ".json",
        );
        result = {
          paths: data.medians.map((p) =>
            p.map(([x, y]) => [x / 1024, (900 - y) / 1024]),
          ),
          advance: 1,
        };
      } catch (e) {
        result = await glyph(
          c,
          root.EMB_FONTS.find((f) => f.id === "neozhisong"),
        );
        result = {
          ...result,
          warning: "「" + c + "」没有笔顺数据，使用字体中线",
        };
      }
    } else if (conf.type === "hershey" || conf.type === "stroke") {
      let data = await json("data/hershey.json"),
        f = data[conf.face || "futural"],
        v = f.chars[c.charCodeAt(0) - 33];
      if (c.codePointAt(0) > 126 || !v) {
        result = await glyph(
          c,
          root.EMB_FONTS.find((f) => f.id === "neozhisong"),
        );
      } else
        result = {
          paths: hershey(v.d).map((p) => p.map(([x, y]) => [x / 24, y / 24])),
          advance: (v.o + 2) / 24,
        };
    } else {
      let f = await font(conf.file),
        g = f.charToGlyph(c);
      if (g.index === 0) {
        result = {
          paths: [
            [
              [0.1, 0.1],
              [0.7, 0.1],
              [0.7, 0.9],
              [0.1, 0.9],
              [0.1, 0.1],
            ],
          ],
          advance: 0.85,
          warning: "字体缺字：" + c,
        };
      } else {
        const size = 112,
          canvas = document.createElement("canvas");
        canvas.width = 160;
        canvas.height = 160;
        let ctx = canvas.getContext("2d");
        g.getPath(20, 120, size).draw(ctx);
        let rgba = ctx.getImageData(0, 0, 160, 160).data,
          a = new Uint8Array(25600);
        for (let i = 0; i < a.length; i++) a[i] = rgba[i * 4 + 3] > 90 ? 1 : 0;
        result = {
          paths: G.trace(G.skeleton(a, 160, 160), 160, 160).map((p) =>
            p.map(([x, y]) => [(x - 20) / size, (y - 120) / size + 1]),
          ),
          advance: g.advanceWidth / f.unitsPerEm,
        };
      }
    }
    cache.set(key, result);
    if (cache.size > 512) cache.delete(cache.keys().next().value);
    return result;
  }
  async function textPaths(layer) {
    let conf =
        root.EMB_FONTS.find((f) => f.id === layer.font) || root.EMB_FONTS[0],
      size = layer.size || 100,
      lines = String(layer.text).split("\n"),
      out = [],
      charIndices = [],
      charIndex = 0,
      warnings = [],
      max = 0;
    for (let row = 0; row < lines.length; row++) {
      let items = [],
        width = 0;
      for (const c of lines[row]) {
        let g = await glyph(c, conf);
        items.push({ g, x: width, index: charIndex++ });
        width += (g.advance + 0.06) * size;
        if (g.warning) warnings.push(g.warning);
      }
      max = Math.max(max, width);
      const shift =
        layer.align === "center"
          ? -width / 2
          : layer.align === "right"
            ? -width
            : 0;
      for (const { g, x, index } of items)
        for (const p of g.paths) {
          charIndices.push(index);
          out.push(
            p.map(([px, py]) => [
              px * size + x + shift,
              py * size + row * size * (layer.lineGap || 1.35),
            ]),
          );
        }
    }
    return {
      charIndices,
      paths: out,
      w: max,
      h: lines.length * size * (layer.lineGap || 1.35),
      warnings: [...new Set(warnings)],
    };
  }
  root.EmbGlyphs = { textPaths, glyph, font };
})(globalThis);
