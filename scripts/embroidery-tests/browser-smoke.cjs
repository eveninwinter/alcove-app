const { chromium } = require("playwright-core");
(async () => {
  const browser = await chromium.launch({
    executablePath: "/snap/bin/chromium",
    headless: true,
    args: ["--no-sandbox", "--disable-dev-shm-usage", "--disable-gpu"],
  });
  try {
    const page = await browser.newPage({
      viewport: { width: 393, height: 760 },
      deviceScaleFactor: 2,
    });
    const errors = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.goto("http://127.0.0.1:18039/embroidery.html");
    await page.waitForFunction(() => window.EMB_FONTS?.length > 0);
    await page.evaluate(() => window.__emb("appearance", { night: true }));
    await page.locator("#tools button[data-tool=text]").click();
    await page.locator("textarea").fill("测试 ABC");
    await page.getByRole("button", { name: "绣出来", exact: true }).click();
    await page.waitForTimeout(3500);
    console.log(
      await page.evaluate(() => ({
        errors: ERRS,
        ops: EmbEditor.scene.ops.length,
        notice: document.getElementById("notice").textContent,
      })),
    );
    await page.screenshot({
      path: "/root/workroom/embroidery/build/editor-test.png",
    });
    let check = await page.evaluate(async () => {
      let d = EmbEditor.document;
      d.layers = [
        {
          id: "fake-draw",
          type: "draw",
          x: 0,
          y: 0,
          scale: 1,
          rot: 0,
          color: "#B8325A",
          points: [
            [100, 100],
            [200, 200],
            [300, 100],
          ],
        },
      ];
      EmbEditor.load(d);
      await EmbEditor.build();
      let p1 = await EmbEditor.exportPNG(),
        p2 = await EmbEditor.exportPNG();
      return {
        deterministic: p1 === p2,
        png: p1.length,
        ops: EmbEditor.scene.ops.length,
        errs: ERRS,
      };
    });
    console.log(check);
    if (errors.length || check.errs.length || !check.deterministic)
      throw Error(JSON.stringify(errors.concat(check.errs)));
    console.log("ERRS:[]");
  } finally {
    await browser.close();
  }
})().catch((e) => {
  console.error(e);
  process.exit(1);
});
