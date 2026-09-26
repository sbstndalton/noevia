// #446 + #401 (reopened), against the synthetic diary fixture only:
//
// (a) Settings -> AI providers -> "Connect a provider" -> Cancel returns focus to the button
//     that opened the form, at a wide (1440) and a narrow (390) width — the inline ProviderForm
//     unmounting with no focus management at all used to drop focus to <body>.
//
// (b)/(c) At the app's own nav/detail-split width (500px), opening Settings from the account
//     menu and closing it (Close button or Escape) must not drop focus to <body>, or onto an
//     opener that is technically still `.isConnected` but sits inside the sidebar drawer while
//     the drawer is `display:none` (the drawer collapses the moment the account menu opens
//     Settings, and does not reopen on its own when Settings closes). At 1440 the sidebar is
//     never display:none, so the original #401 case — focus back on the account trigger — still
//     holds there.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const { createFixture } = require('./diary-fixture.cjs');
const { withLocale } = require('./qa-locale.cjs');

const PORT = 31463;

/** The one thing worth mocking beyond the fixture's defaults: a provider create/test round trip,
 *  so the successful-add path (not just Cancel) can be exercised against synthetic data only. */
async function routeProviders(page) {
  let created = null;
  await page.route('**/api/providers/test', (route) => route.fulfill({ json: { ok: true, models: ['synthetic-model'] } }));
  await page.route('**/api/providers', (route) => {
    const method = route.request().method();
    if (method === 'POST') {
      const body = route.request().postDataJSON();
      created = { id: 'synthetic-provider-1', label: body.label, baseUrl: body.baseUrl, isDefault: false };
      return route.fulfill({ json: created });
    }
    if (method === 'GET') return route.fulfill({ json: { providers: created ? [created] : [] } });
    return route.continue();
  });
  return () => created;
}

(async () => {
  const fixture = createFixture(PORT);
  await fixture.listen();
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  const errors = [];
  try {
    // ── (a) Providers "Connect a provider" -> Cancel, at 1440 and 390 ──────────────────────────
    for (const width of [1440, 390]) {
      const page = await browser.newPage(withLocale({ viewport: { width, height: 900 } }));
      page.on('pageerror', (e) => errors.push(e.message));
      await routeProviders(page);
      await page.goto(`http://localhost:${PORT}/settings/providers`);
      const connect = page.getByRole('button', { name: 'Connect a provider', exact: true });
      await connect.waitFor();
      const connectHandle = await connect.elementHandle();

      await connect.click();
      const cancel = page.getByRole('button', { name: 'Cancel', exact: true });
      await cancel.waitFor();
      await cancel.click();
      await page.waitForFunction((el) => el === document.activeElement, connectHandle).catch(() => {});
      const onOpenerAfterCancel = await connect.evaluate((el) => el === document.activeElement);
      assert.ok(onOpenerAfterCancel, `${width}px Cancel: focus landed on ${await page.evaluate(() => document.activeElement?.outerHTML?.slice(0, 140))} instead of "Connect a provider"`);

      // Successful add: focus lands on the new row's remove button (the connect button is the
      // fallback only if the row genuinely never renders).
      await connect.click();
      await page.getByLabel('Provider name', { exact: true }).fill('Synthetic Provider');
      await page.getByLabel('Provider base URL', { exact: true }).fill('https://synthetic.example/v1');
      await page.getByRole('button', { name: 'Connect provider', exact: true }).click();
      const newRow = page.getByRole('button', { name: 'Remove Synthetic Provider', exact: true });
      await newRow.waitFor();
      const newRowHandle = await newRow.elementHandle();
      await page.waitForFunction((el) => el === document.activeElement, newRowHandle).catch(() => {});
      const afterAdd = await page.evaluate(() => ({ isBody: document.activeElement === document.body, rects: document.activeElement ? document.activeElement.getClientRects().length : 0 }));
      const onNewRow = await newRow.evaluate((el) => el === document.activeElement);
      assert.ok(!afterAdd.isBody, `${width}px after a successful add: focus fell to <body>`);
      assert.ok(afterAdd.rects > 0, `${width}px after a successful add: focus landed on a hidden element`);
      assert.ok(onNewRow, `${width}px after a successful add: focus should land on the new provider row's remove button`);

      await page.close();
    }

    // ── (b)/(c) Settings opened from the account menu, closed both ways, at 500px and 1440px ──
    for (const width of [500, 1440]) {
      for (const closeWith of ['Close button', 'Escape']) {
        const page = await browser.newPage(withLocale({ viewport: { width, height: 800 } }));
        page.on('pageerror', (e) => errors.push(e.message));
        await routeProviders(page);
        await page.goto(`http://localhost:${PORT}`);
        await page.getByPlaceholder('Message noevia…').waitFor();

        if (width <= 519) await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
        const accountTrigger = page.getByRole('button', { name: /Account menu for/ });
        await accountTrigger.waitFor();
        await accountTrigger.click();
        await page.getByRole('menuitem', { name: 'Settings', exact: true }).click();
        const settings = page.getByRole('region', { name: 'Settings' });
        await settings.waitFor();

        if (closeWith === 'Escape') await page.keyboard.press('Escape');
        else await settings.getByRole('button', { name: 'Close settings', exact: true }).click();

        // The focus-restore effect defers a frame (rAF, with a timer fallback for a hidden tab)
        // past Settings' real unmount (~240ms after Escape/Close, once its exit animation
        // finishes) — poll for the settled result instead of a fixed sleep.
        await page.waitForFunction(() => document.activeElement !== document.body, null, { timeout: 2000 }).catch(() => {});
        const state = await page.evaluate(() => {
          const el = document.activeElement;
          return {
            isBody: el === document.body,
            visible: !!el && el.getClientRects().length > 0,
            isAccountTrigger: !!el && el.classList?.contains('account-trigger'),
            tag: el?.tagName,
            cls: el?.className,
          };
        });
        assert.ok(!state.isBody, `${width}px ${closeWith}: focus fell to <body>`);
        assert.ok(state.visible, `${width}px ${closeWith}: focus landed on a hidden element (${JSON.stringify(state)})`);
        if (width > 519) {
          assert.ok(state.isAccountTrigger, `${width}px ${closeWith}: #401's original case — focus should return to the account trigger (${JSON.stringify(state)})`);
        }
        await page.close();
      }
    }

    assert.deepEqual(errors, [], `uncaught page errors: ${errors.join('; ')}`);
    console.log('PASS settings focus fallback (#446/#401): providers Cancel returns to "Connect a provider" at 1440 and 390 (and a successful add lands on a visible, non-<body> target); at 500px closing Settings opened from the account menu (Close button and Escape) never leaves focus on <body> or a hidden element, even though the sidebar drawer holding the opener stays collapsed; at 1440px it still returns to the account trigger.');
  } finally {
    await browser.close();
    await fixture.close();
  }
})().catch((e) => {
  console.error(e);
  process.exitCode = 1;
});
