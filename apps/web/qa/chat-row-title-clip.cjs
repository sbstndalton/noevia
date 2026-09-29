// Regression: sidebar chat row title clipped its first character on hover. When the
// pin/archive/"..." actions appear, the row's padding-right squeeze re-measured the title as
// overflowing and the hover marquee (sidebar-title-scroll) translated the text left, sliding the
// leading character(s) out of the clipped view. Chat rows must keep a static ellipsis title
// (no transform, no lifted max-width, starts at the label's left edge) while hovered or
// keyboard-focused; project rows keep their marquee. Synthetic data only (page.route mocks).
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const { createFixture } = require('./diary-fixture.cjs');
const { withLocale } = require('./qa-locale.cjs');
const out = process.env.QA_SCREENSHOTS || '/tmp/noevia-shots';
(async () => {
  const fixture = createFixture(31481); await fixture.listen();
  const browser = await chromium.launch({ headless: true, channel: process.env.QA_CHANNEL || 'chrome' });
  const errors = [];
  const title = 'QA synthetic chat title that is far too long to fit inside the sidebar row';
  try {
    for (const width of [375, 1440]) for (const theme of ['light', 'dark']) {
      const page = await browser.newPage(withLocale({ viewport: { width, height: 800 } }));
      page.on('pageerror', (e) => errors.push(e.message));
      await page.addInitScript((t) => localStorage.setItem('cowork-theme', t), theme);
      await page.route('**/api/workspace', (r) => r.fulfill({ json: { projects: [], freeChats: [{ id: 'c1', title, updatedAt: 1000, pinned: false, messages: [] }] } }));
      await page.goto('http://localhost:31481');
      await page.getByPlaceholder('Message noevia…').waitFor();
      if (width < 520) await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
      const row = page.locator('.sidebar .chat-row', { hasText: 'QA synthetic' });
      await row.waitFor();
      const tag = `${width}px ${theme}`;
      if (theme === 'light') await row.screenshot({ path: `${out}/chat-row-${width}-${theme}-before-hover.png` });
      await row.hover();
      // Sample across the marquee delay + travel window: the title must never move.
      for (let i = 0; i < 6; i++) {
        await page.waitForTimeout(350);
        const info = await row.evaluate((el) => {
          const label = el.querySelector('.sidebar-label'); const text = el.querySelector('.sidebar-label-text');
          const l = label.getBoundingClientRect(); const t = text.getBoundingClientRect();
          const cs = getComputedStyle(text);
          return { overflowing: label.classList.contains('is-overflowing'), transform: cs.transform, animation: cs.animationName, dLeft: t.left - l.left, dRight: t.right - l.right };
        });
        assert.ok(info.overflowing, `${tag}: fixture title should overflow`);
        assert.equal(info.transform, 'none', `${tag} #${i}: title translated on hover (${info.transform})`);
        assert.equal(info.animation, 'none', `${tag} #${i}: marquee running on chat row (${info.animation})`);
        assert.ok(info.dLeft >= -1 && info.dRight <= 1, `${tag} #${i}: title escapes its label (left ${info.dLeft}, right ${info.dRight})`);
      }
      if (theme === 'light') await row.screenshot({ path: `${out}/chat-row-${width}-${theme}-after-hover.png` });
      console.log(`PASS chat-row-title-clip: ${tag}`);
      await page.close();
    }
    assert.deepEqual(errors, []);
    console.log('chat-row-title-clip: all checks passed');
  } finally { await browser.close(); await fixture.close?.(); }
})().catch((e) => { console.error(e); process.exit(1); });
