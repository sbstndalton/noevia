// #951 UI redo: one design system matching the Claude/ChatGPT reference. Synthetic APIs only
// (qa/diary-fixture.cjs plus page routes): no model, no inference, no real Diary, no live server.
//   npm run build && PLAYWRIGHT_MODULE=~/noevia-local-test/node_modules/playwright-core node qa/ui-redo-951.cjs
// QA_SHOTS=<dir> writes light/dark × desktop 1440×900 / phone 390×844 screenshots of the key
// screens. QA_SHOTS_ONLY=1 skips the assertions (used for the "before" set on the old build).
// The assertions pin the computed tokens and motion of the redo:
//   dark page rgb(21,21,21), light page hsl(48 33.3% 97.1%), no mint/green surface tints, a saved
//   Soft material mapping onto Editorial, all three theme families in light and dark,
//   sidebar rows 32px / radius 8px, Settings opens as a modal window over the dimmed app
//   (radius 12px, transition 200ms cubic-bezier(.165,.84,.44,1), scale .98 → 1, 50% black scrim),
//   switch knob 120ms overshoot, and reduced motion (system or Settings) collapses all of it.
const os = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || `${os.homedir()}/noevia-local-test/node_modules/playwright-core`);
const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path');
const { createFixture } = require('./diary-fixture.cjs');
const { openSettings } = require('./nav.cjs');
const PORT = 31951;
const shots = process.env.QA_SHOTS || '';
const shotsOnly = process.env.QA_SHOTS_ONLY === '1';

const user = { id: 'synthetic-ui-951', username: 'uiqa', displayName: 'UI QA', role: 'member', diaryEnabled: true, onboarded: true };
const chat = (id, title) => ({ id, title, updatedAt: 1000, pinned: false, messages: [] });
const project = { id: 'p1', name: 'Synthetic research', goal: 'A synthetic project for the redo screenshots.', instructions: '', memories: [], modes: ['chat'], updatedAt: 1000, files: [], assets: [], chats: [chat('pc1', 'Synthetic project chat')], toolboxes: ['core'] };

async function routes(page, theme) {
  await page.route('**/api/profile', (r) => r.fulfill({ json: { user, passkeys: [] } }));
  await page.route('**/api/auth/session', (r) => r.fulfill({ json: { user, passkeys: [] } }));
  await page.route('**/api/profile/appearance', (r) => r.fulfill({ json: { theme, light: 'iris', dark: 'iris' } }));
  await page.route('**/api/workspace', (r) => r.fulfill({ json: { projects: [project], freeChats: [chat('c1', 'Synthetic trip plan'), chat('c2', 'A synthetic chat with a much longer title that has to truncate'), chat('c3', 'Synthetic notes')] } }));
  await page.route('**/api/chats/*/history', (r) => r.fulfill({ json: { revision: 'r1', history: [
    { role: 'user', content: 'Summarise the synthetic notes in three points.' },
    { role: 'assistant', content: '## Summary\n\n1. **Scope** — the synthetic fixture covers the redo.\n2. **Motion** — short and decelerating.\n3. **Depth** — layered surfaces, not borders.\n\n```js\nconst page = "rgb(21, 21, 21)";\n```' },
  ] } }));
}

const MINT = (rgb) => { const m = rgb.match(/\d+(\.\d+)?/g); if (!m) return false; const [r, g, b] = m.map(Number); return g > r + 6 && g > b + 2; };

(async () => {
  if (shots) fs.mkdirSync(shots, { recursive: true });
  const fixture = createFixture(PORT); await fixture.listen();
  const browser = await chromium.launch({ headless: true, channel: 'chrome' });
  const errors = [];
  let checks = 0;
  const ok = (cond, msg) => { if (shotsOnly) return; assert.ok(cond, msg); checks++; };
  const eq = (a, b, msg) => { if (shotsOnly) return; assert.equal(a, b, msg); checks++; };
  try {
    for (const theme of ['dark', 'light']) for (const [form, viewport] of [['desktop', { width: 1440, height: 900 }], ['phone', { width: 390, height: 844 }]]) {
      const phone = form === 'phone';
      const ctx = await browser.newContext({ viewport, hasTouch: phone, isMobile: phone, locale: 'en-GB', reducedMotion: 'no-preference' });
      const page = await ctx.newPage();
      page.on('pageerror', (e) => errors.push(`${theme} ${form} ${page.url()}: ${e.message}`));
      await page.addInitScript((t) => { if (!sessionStorage.getItem('qa-init')) { localStorage.setItem('cowork-theme', t); localStorage.setItem('noevia:material', 'soft'); sessionStorage.setItem('qa-init', '1'); } }, theme);
      await routes(page, theme);
      const shot = async (name) => { if (shots) { await page.waitForTimeout(350); await page.screenshot({ path: path.join(shots, `${name}-${theme}-${form}.png`) }); } };
      await page.goto(`http://localhost:${PORT}/`);
      await page.getByPlaceholder('Message noevia…').waitFor();
      await page.evaluate(() => document.fonts.ready);

      // Tokens: the page ground and text, and no mint/green tints on the structural surfaces
      // (a saved retired family/material must not leak back in).
      const ground = await page.evaluate(() => {
        const bg = (s) => { const e = document.querySelector(s); return e ? getComputedStyle(e).backgroundColor : null; };
        return { body: getComputedStyle(document.body).backgroundColor, bodyImage: getComputedStyle(document.body).backgroundImage,
          text: getComputedStyle(document.body).color, family: document.documentElement.dataset.family || null,
          surfaces: ['.app .sidebar', '.app .app-stack', '.composer-inner'].map(bg).filter(Boolean),
          composerRadius: (() => { const e = document.querySelector('.composer-inner'); return e ? getComputedStyle(e).borderTopLeftRadius : null; })(),
          font: getComputedStyle(document.body).fontFamily };
      });
      if (theme === 'dark') { eq(ground.body, 'rgb(21, 21, 21)', 'dark page ground is rgb(21,21,21)'); eq(ground.text, 'rgb(240, 239, 236)', 'dark primary text'); }
      else { eq(ground.body, 'rgb(250, 249, 245)', 'light page ground is hsl(48 33.3% 97.1%)'); }
      eq(ground.bodyImage, 'none', 'no atmosphere gradient behind the app');
      eq(ground.family, 'editorial', 'a saved Soft material maps onto Editorial, the reference default');
      for (const s of [ground.body, ...ground.surfaces]) ok(!MINT(s), `no mint/green surface tint: ${s}`);
      eq(ground.composerRadius, '14px', 'composer radius 14px');
      ok(/Inter/.test(ground.font), `UI face is Inter: ${ground.font}`);
      await shot('home');

      if (!phone) {
        // Sidebar rows: 32px, radius 8px, 60ms easeOutQuart hover.
        const row = await page.locator('.app .sidebar .side-nav .nav-item').first().evaluate((e) => { const s = getComputedStyle(e); return { h: e.getBoundingClientRect().height, r: s.borderTopLeftRadius, d: s.transitionDuration, f: s.transitionTimingFunction }; });
        eq(row.h, 32, 'sidebar row is 32px tall'); eq(row.r, '8px', 'sidebar row radius 8px');
        ok(/0\.06s/.test(row.d), `row hover 60ms: ${row.d}`); ok(/cubic-bezier\(0\.165, 0\.84, 0\.44, 1\)/.test(row.f), `row hover easeOutQuart: ${row.f}`);
      }

      // Chat transcript.
      if (phone) await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
      await page.getByText('Synthetic trip plan', { exact: true }).first().click();
      await page.getByText('short and decelerating').waitFor();
      await shot('chat');

      // Settings: a modal window over the dimmed app (full-screen sheet on a phone).
      // Record the window's first computed frame the moment it is inserted.
      await page.evaluate(() => { window.__stageFirst = null; new MutationObserver((_, obs) => { const e = document.querySelector('.settings-stage:not(.view-loading)'); if (!e) return; const s = getComputedStyle(e); window.__stageFirst = { scale: Number(s.scale), opacity: Number(s.opacity) }; obs.disconnect(); }).observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ['class'] }); });
      await openSettings(page);
      const stage = page.locator('.settings-stage:not(.view-loading)');
      await stage.waitFor();
      // The first frame of the window is still on its way in (scale .98 → 1, fading).
      const opening = await page.evaluate(() => window.__stageFirst);
      await page.waitForTimeout(450);
      const modal = await page.evaluate(() => {
        const e = document.querySelector('.settings-stage'), s = getComputedStyle(e), r = e.getBoundingClientRect();
        const nav = getComputedStyle(document.querySelector('.settings-stage .settings-navigation'));
        const scrim = document.querySelector('.settings-scrim');
        return { radius: s.borderTopLeftRadius, dur: s.transitionDuration, ease: s.transitionTimingFunction, prop: s.transitionProperty, scale: s.scale,
          bg: s.backgroundColor, navBg: nav.backgroundColor, navW: document.querySelector('.settings-stage .settings-navigation').getBoundingClientRect().width,
          x: r.left, w: r.width, vw: innerWidth, scrim: scrim ? getComputedStyle(scrim).backgroundColor : null,
          appVisible: getComputedStyle(document.querySelector('.app-main')).visibility };
      });
      if (!phone) {
        eq(modal.radius, '12px', 'settings window radius 12px');
        ok(modal.x > 0 && modal.w < modal.vw, `settings is a window, not the full app: ${modal.x} ${modal.w}`);
        eq(modal.scrim, 'rgba(0, 0, 0, 0.5)', 'scrim dims the app at 50% black');
        eq(modal.appVisible, 'visible', 'the app stays visible behind the window');
        ok(/scale/.test(modal.prop) && /opacity/.test(modal.prop), `settings fades and scales: ${modal.prop}`);
        ok(/0\.2s/.test(modal.dur), `settings 200ms: ${modal.dur}`);
        ok(/cubic-bezier\(0\.165, 0\.84, 0\.44, 1\)/.test(modal.ease), `settings easeOutQuart: ${modal.ease}`);
        ok(opening && (opening.scale < 1 || opening.opacity < 1), `settings opens with a fade/scale, not a cut: ${JSON.stringify(opening)}`);
        eq(modal.scale, '1', 'settings settles at scale 1');
        eq(Math.round(modal.navW), 192, 'settings nav 192px');
        ok(modal.navBg !== modal.bg, 'settings nav is darker than the content');
        if (theme === 'dark') { eq(modal.bg, 'rgb(26, 26, 25)', 'dialog surface rgb(26,26,25)'); eq(modal.navBg, 'rgb(21, 21, 21)', 'settings nav rgb(21,21,21)'); }
      }
      if (phone) { const back = page.getByRole('button', { name: 'All settings', exact: true }); if (await back.isVisible()) await back.click(); }
      await page.locator('.settings-navigation').getByRole('button', { name: 'Appearance & language', exact: true }).click();
      await page.locator('.settings-detail-scroll').waitFor();
      eq((await page.getByRole('radiogroup', { name: 'Theme family' }).locator('.family-tile-name').allTextContents()).join(','), 'Editorial,Contemporary,Glass', 'the three theme families stay in Appearance');
      await shot('settings');
      // The switch contract (class + aria-checked), as Switch.tsx renders it.
      const knob = await page.evaluate(() => {
        const b = document.createElement('button'); b.className = 'glass-switch'; b.setAttribute('role', 'switch'); b.setAttribute('aria-checked', 'true');
        const k = document.createElement('span'); k.className = 'knob glass'; b.append(k); document.querySelector('.settings-detail-scroll').append(b);
        const s = getComputedStyle(k), t = getComputedStyle(b); const out = { d: s.transitionDuration, f: s.transitionTimingFunction, tr: s.transform, w: t.width, h: t.height }; b.remove(); return out;
      });
      ok(/0\.12s/.test(knob.d) && /cubic-bezier\(0\.34, 1\.3, 0\.64, 1\)/.test(knob.f), `switch knob 120ms overshoot: ${knob.d} ${knob.f}`);
      eq(`${knob.w}x${knob.h}`, '36pxx20px', 'switch track 36×20');
      ok(/matrix\(1, 0, 0, 1, 16, 0\)/.test(knob.tr), `checked knob travels 16px: ${knob.tr}`);
      await page.keyboard.press('Escape');
      await page.locator('.settings-stage').waitFor({ state: 'detached' });

      // Projects list and a project page.
      await page.goto(`http://localhost:${PORT}/projects`);
      await page.waitForTimeout(800);
      await shot('projects');
      await page.goto(`http://localhost:${PORT}/p/p1`);
      await page.waitForTimeout(500);
      await shot('project');
      // Customise → Connectors.
      await page.goto(`http://localhost:${PORT}/customize/connectors`);
      await page.waitForTimeout(700);
      await shot('customize');
      // Diary.
      await page.goto(`http://localhost:${PORT}/diary`);
      await page.waitForTimeout(900);
      await shot('diary');

      // Deep link: /settings/<section> still opens Settings (as the window).
      await page.goto(`http://localhost:${PORT}/settings/appearance`);
      await page.locator('.settings-stage:not(.view-loading)').waitFor();
      ok(true, 'settings deep link opens');

      // Reduced motion: the Settings preference collapses the window transition.
      await page.evaluate(() => { document.documentElement.dataset.motion = 'reduced'; });
      const reduced = await page.locator('.settings-stage:not(.view-loading)').evaluate((e) => getComputedStyle(e).transitionDuration);
      ok(/^0\.001s|^0s|1e-03s/.test(reduced), `reduced motion collapses the settings transition: ${reduced}`);
      await ctx.close();
    }
    // Every theme family, light and dark, on the same token system: screenshots plus each
    // family's signature (Contemporary: 28px composer and pill buttons; Glass: frosted panes).
    for (const family of ['editorial', 'contemporary', 'glass']) for (const theme of ['light', 'dark']) {
      const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, locale: 'en-GB' });
      const page = await ctx.newPage();
      page.on('pageerror', (e) => errors.push(`${family} ${theme}: ${e.message}`));
      await page.addInitScript(({ t, f }) => { localStorage.setItem('cowork-theme', t); localStorage.setItem('noevia:theme-family', f); }, { t: theme, f: family });
      await routes(page, theme);
      await page.goto(`http://localhost:${PORT}/`);
      await page.getByPlaceholder('Message noevia…').waitFor();
      await page.evaluate(() => document.fonts.ready);
      const look = await page.evaluate(() => {
        const c = document.querySelector('.composer-inner'), side = document.querySelector('.app .sidebar');
        return { family: document.documentElement.dataset.family, radius: getComputedStyle(c).borderTopLeftRadius, side: getComputedStyle(side).backdropFilter,
          body: getComputedStyle(document.body).backgroundColor, h1: getComputedStyle(document.querySelector('.chat-workspace .empty-state h1')).fontFamily };
      });
      eq(look.family, family, `${family} applied`);
      ok(!MINT(look.body), `${family} ${theme}: no mint page`);
      if (family === 'editorial') { eq(look.radius, '14px', 'editorial composer 14px'); ok(/Source Serif/.test(look.h1), 'editorial serif greeting'); }
      if (family === 'contemporary') { eq(look.radius, '28px', 'contemporary composer 28px'); ok(/Inter/.test(look.h1), 'contemporary sans greeting'); }
      if (family === 'glass') ok(/blur\(/.test(look.side), `glass sidebar is frosted: ${look.side}`);
      if (shots) { await page.waitForTimeout(300); await page.screenshot({ path: path.join(shots, `theme-${family}-${theme}-home.png`) }); }
      await page.goto(`http://localhost:${PORT}/settings/appearance`);
      await page.locator('.settings-stage:not(.view-loading)').waitFor();
      await page.locator('.family-tile').first().waitFor();
      if (shots) { await page.waitForTimeout(400); await page.screenshot({ path: path.join(shots, `theme-${family}-${theme}-settings.png`) }); }
      await ctx.close();
    }

    // System reduced motion.
    const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, reducedMotion: 'reduce', locale: 'en-GB' });
    const page = await ctx.newPage();
    await routes(page, 'dark');
    await page.goto(`http://localhost:${PORT}/settings/appearance`);
    await page.locator('.settings-stage:not(.view-loading)').waitFor();
    const dur = await page.locator('.settings-stage:not(.view-loading)').evaluate((e) => getComputedStyle(e).transitionDuration);
    ok(/^0\.001s|^0s|1e-03s/.test(dur), `prefers-reduced-motion collapses the settings transition: ${dur}`);
    await ctx.close();
    assert.deepEqual(errors, [], 'no page errors');
    console.log(JSON.stringify({ ok: true, checks, shots: shots || null, shotsOnly }));
  } finally { await browser.close(); await fixture.close?.(); }
})().catch((e) => { console.error(e); process.exit(1); });
