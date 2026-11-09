// Rasterizes SVG files to PNG: node raster.js in.svg out.png width height [background]
const { chromium } = require('playwright');
const fs = require('fs');
(async () => {
  const jobs = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage({ deviceScaleFactor: 1 });
  for (const [src, out, w, h, bg] of jobs) {
    await page.setViewportSize({ width: w, height: h });
    const svg = fs.readFileSync(src, 'utf8').replace('<svg ', `<svg width="${w}" height="${h}" preserveAspectRatio="xMidYMid meet" `);
    await page.setContent(`<html><body style="margin:0;background:${bg || 'transparent'}">${svg}</body></html>`);
    await page.screenshot({ path: out, omitBackground: !bg, clip: { x: 0, y: 0, width: w, height: h } });
  }
  await browser.close();
})().catch((e) => { console.error(e.message); process.exit(1); });
