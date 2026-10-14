const { chromium } = require("playwright-core");
(async () => {
  const b = await chromium.launch({
    executablePath: "/snap/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
  });
  try {
    const p = await b.newPage({ viewport: { width: 393, height: 700 } });
    const errs = [];
    p.on("pageerror", (e) => errs.push(e.message));
    await p.goto("http://127.0.0.1:18039/embroidery.html");
    await p.waitForFunction(() => EMB_FONTS.length === 15);
    await p.waitForTimeout(400);
    console.log(
      await p.evaluate(async () => {
        let results = [];
        for (const font of EMB_FONTS) {
          let c =
            font.type === "hershey"
              ? "A"
              : font.id === "kai-stroke"
                ? "繡"
                : "A";
          let g = await EmbGlyphs.glyph(c, font);
          if (!g.paths.length) throw Error("no glyph " + font.id);
          results.push([font.id, g.paths.length]);
        }
        return results;
      }),
    );
    console.log(
      await p.evaluate(async () => {
        const assert = (v, s) => {
          if (!v) throw Error(s);
        };
        let d = EmbEditor.document;
        d.layers = [
          {
            id: "fake-line",
            type: "draw",
            points: [
              [40, 40],
              [240, 240],
              [440, 40],
            ],
            x: 0,
            y: 0,
            scale: 1,
            rot: 0,
            color: "#2F5E4E",
          },
        ];
        for (const kind of ["rect", "circle", "heart", "star", "custom"]) {
          d.shape = {
            kind,
            w: 800,
            h: 460,
            points: [
              [10, 10],
              [790, 20],
              [700, 450],
              [10, 400],
            ],
          };
          for (const fabric of Object.keys(EmbRender.fabrics)) {
            d.fabric = fabric;
            EmbEditor.load(d);
            await EmbEditor.build();
            assert(
              (await EmbEditor.exportPNG()).startsWith(
                "data:image/png;base64,",
              ),
              kind + fabric,
            );
          }
        }
        return "30 fabric/shape exports";
      }),
    );
    await p.locator("#tools button[data-tool=deco]").click(); await p.locator(".subtabs button[data-sub=assets]").click();   // 1014 素材收进「装饰」
    await p.locator(".assets button").first().click();
    await p.getByRole("button", { name: "补齐四角", exact: true }).click();
    await p.waitForTimeout(300);
    console.log(
      await p.evaluate(() => {
        let layers = EmbEditor.document.layers.filter((x) => x.anchor);
        if (layers.length !== 4 || new Set(layers.map((x) => x.id)).size !== 4)
          throw Error("corners");
        return layers.map((x) => [x.anchor, x.flipX, x.flipY]);
      }),
    );
    await p.locator("#undo").click();
    await p.waitForTimeout(250);
    console.log(await p.evaluate(() => EmbEditor.document.layers.length));
    await p.locator("#redo").click();
    await p.waitForTimeout(250);
    console.log(
      await p.evaluate(async () => {
        let d = EmbEditor.document;
        d.layers = [
          {
            id: "fake-loop",
            type: "border",
            asset: "01-flourish",
            mode: "loop",
            color: "#B8325A",
            scale: 1,
            x: 0,
            y: 0,
          },
        ];
        d.shape = { kind: "heart", w: 800, h: 460 };
        EmbEditor.load(d);
        await EmbEditor.build();
        let before = JSON.stringify(EmbEditor.scene.ops.map((x) => x.stitch));
        await EmbEditor.build();
        if (before !== JSON.stringify(EmbEditor.scene.ops.map((x) => x.stitch)))
          throw Error("unstable loop");
        return { loopOps: EmbEditor.scene.ops.length };
      }),
    );
    await p.screenshot({
      path: "/root/workroom/embroidery/build/loop-test.png",
    });
    const er = await p.evaluate(() => ERRS);
    console.log("ERRS:" + JSON.stringify([...errs, ...er]));
    if (errs.length || er.length) throw Error("browser errors");
  } finally {
    await b.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
