const { chromium } = require("playwright-core");
const fs = require("fs");
(async () => {
  const b = await chromium.launch({
    executablePath: "/snap/bin/chromium",
    args: ["--no-sandbox"],
  });
  try {
    const p = await b.newPage({ viewport: { width: 393, height: 750 } });
    await p.goto("http://127.0.0.1:18039/embroidery.html");
    await p.waitForFunction(() => EMB_FONTS.length === 15);
    console.log(
      await p.evaluate(async () => {
        for (const f of Object.keys(EmbRender.fabrics)) {
          const pool = EmbRender.randomPool(f);
          if (
            pool.length < 3 ||
            pool.some(
              (c) => EmbRender.contrast(c, EmbRender.fabrics[f].color) < 3,
            )
          )
            throw Error("contrast " + f);
        }
        const dots = {};
        for (const id of [
          "02-star-10",
          "02-star-08",
          "07-pearl-swirl",
          "08-pearl-flower",
          "10-gem-flower",
        ]) {
          dots[id] = (await EmbRender.motif(id)).dotCount;
          if (!dots[id]) throw Error("missing dots " + id);
        }
        let layer = {
          id: "test",
          text: "AB",
          font: "hershey-print",
          size: 18,
          lineGap: 1.6,
        };
        let a = await EmbGlyphs.textPaths(layer),
          b = await EmbGlyphs.textPaths({ ...layer, letterSpacing: 10 });
        if (b.w <= a.w) throw Error("spacing");
        return { dots, errors: ERRS };
      }),
    );
    await p.getByRole("button", { name: "形状", exact: true }).click();
    await p.getByRole("button", { name: "竖版", exact: true }).click();
    let shape = await p.evaluate(() => EmbEditor.document.shape);
    if (shape.w !== 520 || shape.h !== 700) throw Error("portrait");
    console.log("contrast, round motifs, spacing, portrait passed");
    if ((await p.evaluate(() => ERRS)).length) throw Error("browser errors");
  } finally {
    await b.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
