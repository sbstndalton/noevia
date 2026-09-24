// Interface translations (#231) against synthetic APIs only: no model, no inference, no Diary.
// Serves the built app from ../dist. The account preference is de-DE; the browser says en-US,
// so every German string on screen came from the saved choice, not the browser.
//   PLAYWRIGHT_MODULE=~/noevia-local-test/node_modules/playwright-core node qa/i18n-locale.cjs
// Screenshots (375 and 1440, light): the chat shell with the composer, and Settings →
// Appearance & language. Each is checked for horizontal overflow and clipped controls.
const os = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || `${os.homedir()}/noevia-local-test/node_modules/playwright-core`);
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { createFixture } = require('./diary-fixture.cjs');
const out = process.env.QA_SCREENSHOTS || '/tmp/i18n-shots';
const PORT = 31477;

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const fixture = createFixture(PORT); await fixture.listen();
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  const errors = [];
  try {
    for (const width of [375, 1440]) {
      const touch = width < 800;
      const page = await browser.newPage({ viewport: { width, height: touch ? 812 : 900 }, locale: 'en-US', hasTouch: touch, isMobile: touch, deviceScaleFactor: touch ? 2 : 1 });
      page.on('pageerror', (e) => errors.push(`${width}: ${e.message}`));
      await page.addInitScript(() => { localStorage.setItem('cowork-theme', 'light'); });
      let prefs = { notifications: { replyFinished: true, approvalNeeded: true }, sendKey: 'enter', locale: 'de-DE' };
      const user = { id: 'synthetic-i18n-qa', username: 'i18nqa', displayName: 'Synthetische Person', role: 'member', diaryEnabled: false, onboarded: true };
      await page.route('**/api/profile', (r) => r.fulfill({ json: { user, passkeys: [] } }));
      await page.route('**/api/auth/session', (r) => r.fulfill({ json: { user, passkeys: [] } }));
      await page.route('**/api/profile/appearance', (r) => r.fulfill({ json: { theme: 'light', light: 'iris', dark: 'iris' } }));
      await page.route('**/api/account/preferences', async (r) => {
        if (r.request().method() === 'PUT') prefs = { ...prefs, ...JSON.parse(r.request().postData() || '{}') };
        return r.fulfill({ json: prefs });
      });
      await page.route('**/api/workspace', (r) => r.fulfill({ json: { projects: [{ id: 'p1', name: 'Synthetische Recherche', updatedAt: 1000, files: [], assets: [], chats: [], toolboxes: ['core'] }], freeChats: [{ id: 'c1', title: 'Synthetische Reiseplanung', updatedAt: 1000, pinned: false, messages: [] }] } }));
      await page.goto(`http://localhost:${PORT}`);

      // The saved locale reaches the composer and <html lang> without a reload.
      const composer = page.getByPlaceholder('Nachricht an noevia…');
      await composer.waitFor();
      assert.equal(await page.evaluate(() => document.documentElement.lang), 'de-DE');
      await page.getByRole('radiogroup', { name: 'Sitzungsmodus' }).waitFor();
      assert.ok(await page.getByRole('button', { name: 'Dateien und Werkzeuge hinzufügen' }).isVisible());
      const check = async (name) => {
        await page.evaluate(() => document.fonts.ready);
        await page.waitForTimeout(300);
        const state = await page.evaluate(() => {
          const overflow = document.documentElement.scrollWidth > window.innerWidth + 1;
          // A control whose text is wider than its box is clipped (ellipsis or hidden overflow).
          const clipped = [...document.querySelectorAll('button, .set-row-label, .composer-mode-harness, .composer-hint, label, .settings-nav-title, h1, h2')]
            .filter((e) => e.offsetParent && e.getClientRects().length && e.scrollWidth > e.clientWidth + 1 && getComputedStyle(e).overflow !== 'visible' && !e.closest('.chat-row, .proj-row, .model-pill, [hidden]'))
            .map((e) => (e.getAttribute('aria-label') || e.textContent || '').trim().slice(0, 60));
          return { overflow, clipped };
        });
        assert.equal(state.overflow, false, `${width} ${name}: horizontal overflow`);
        assert.deepEqual(state.clipped, [], `${width} ${name}: clipped ${state.clipped.join(' | ')}`);
        await page.screenshot({ path: path.join(out, `de-DE-light-${width}-${name}.png`) });
      };
      await check('chat-composer');

      // Settings → Darstellung & Sprache.
      await page.getByTitle('Settings', { exact: true }).first().click();
      const settings = page.getByRole('region', { name: 'Einstellungen', exact: true });
      await settings.waitFor();
      const back = settings.getByRole('button', { name: 'Alle Einstellungen', exact: true });
      if (await back.isVisible()) await back.click();
      // Search finds a page by a German task word, and by the English one.
      const search = settings.getByLabel('Einstellungen durchsuchen');
      await search.fill('tastenkürzel');
      await settings.getByRole('button', { name: 'Tastatur & Eingabe', exact: true }).waitFor();
      await search.fill('shortcuts');
      await settings.getByRole('button', { name: 'Tastatur & Eingabe', exact: true }).waitFor();
      await search.fill('');
      await settings.locator('.settings-navigation').getByRole('button', { name: 'Darstellung & Sprache', exact: true }).click();
      const select = settings.getByLabel('Sprache der Oberfläche, Datum und Zahlen');
      await select.waitFor();
      assert.equal(await select.inputValue(), 'de-DE');
      await settings.getByText('Noch nicht übersetzte Bereiche erscheinen auf Englisch.', { exact: false }).waitFor();
      await select.scrollIntoViewIfNeeded();
      await check('settings-appearance-language');

      // Switching back to the browser's language re-renders at once, with no reload.
      await settings.getByRole('button', { name: 'Auf Browser zurücksetzen', exact: true }).click();
      await page.getByRole('region', { name: 'Settings', exact: true }).waitFor();
      assert.equal(await page.evaluate(() => document.documentElement.lang), 'en-US');
      assert.equal(prefs.locale, 'system');
      await page.close();
    }
    assert.deepEqual(errors, []);
    console.log(`i18n locale QA passed; screenshots in ${out}`);
  } finally { await browser.close(); await fixture.close?.(); }
})().catch((e) => { console.error(e); process.exit(1); });
