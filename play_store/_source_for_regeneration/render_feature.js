const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const b = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium' });
  const p = await b.newPage({ viewport: { width: 1024, height: 500 }, deviceScaleFactor: 1 });
  await p.goto('file://' + path.join(__dirname, 'feature.html'));
  await p.waitForTimeout(600);
  await p.screenshot({ path: path.join(__dirname, '../graphics/02_feature_graphic_1024x500.png') });
  await b.close();
})();
