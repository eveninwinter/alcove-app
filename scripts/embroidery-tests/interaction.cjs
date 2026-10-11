const { chromium } = require("playwright-core");
(async () => {
  const b = await chromium.launch({
    executablePath: "/snap/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage"],
  });
  try {
    const p = await b.newPage({ viewport: { width: 393, height: 650 } });
    await p.goto("http://127.0.0.1:18039/embroidery.html");
    await p.waitForFunction(() => EMB_FONTS.length === 15);
    await p.waitForTimeout(300);
    await p.locator("[data-tool=draw]").click();
    let box = await p.locator("#canvas").boundingBox();
    await p.mouse.move(box.x + 80, box.y + 90);
    await p.mouse.down();
    await p.mouse.move(box.x + 230, box.y + 125, { steps: 14 });
    await p.mouse.up();
    await p.waitForTimeout(300);
    if ((await p.evaluate(() => EmbEditor.document.layers.length)) !== 1)
      throw Error("stroke");
    await p.locator("#undo").click();
    await p.waitForTimeout(200);
    if ((await p.evaluate(() => EmbEditor.document.layers.length)) !== 0)
      throw Error("stroke undo");
    await p.locator("#redo").click();
    await p.waitForTimeout(200);
    console.log(
      await p.evaluate(async () => {
        let c = document.createElement("canvas");
        c.width = 100;
        c.height = 60;
        let x = c.getContext("2d");
        x.fillStyle = "#D59BB1";
        x.fillRect(0, 0, 100, 60);
        x.fillStyle = "#ffffff";
        x.fillRect(20, 10, 40, 40);
        let d = EmbEditor.document;
        d.layers = [
          {
            id: "fake-image",
            type: "image",
            src: c.toDataURL(),
            style: "print",
            x: 400,
            y: 230,
            scale: 1,
            rot: 0,
            w: 300,
            h: 180,
          },
        ];
        EmbEditor.load(d);
        await EmbEditor.build();
        let a = await EmbEditor.exportPNG();
        d.layers[0].style = "patch";
        EmbEditor.load(d);
        await EmbEditor.build();
        let b = await EmbEditor.exportPNG();
        if (a === b) throw Error("image styles identical");
        return "image print/patch distinct";
      }),
    );
    await p.reload();
    await p.waitForFunction(
      () => window.EmbEditor?.document.layers.length === 1,
    );
    console.log("draft reload passed");
    await p.setViewportSize({ width: 393, height: 420 });
    await p.waitForTimeout(300);
    console.log(
      await p.evaluate(() => ({
        canvasHeight: document.getElementById("canvas").clientHeight,
        ERRS,
      })),
    );
    if ((await p.evaluate(() => ERRS.length)) !== 0) throw Error("errors");
    console.log("ERRS:[]");
  } finally {
    await b.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
