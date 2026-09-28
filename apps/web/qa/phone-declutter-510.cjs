// #510: at phone width the shell drops secondary chrome (home subtitle, mode caption, Tools
// button, Recent chats, heavy drawer controls, the project-row pencil, the healthy MCP line),
// the composer sits on the bottom edge, and the header sliders open this chat's own settings.
// Everything moved stays reachable; 1280px desktop is unchanged. Built app, synthetic fixture:
// every API answer below is invented, nothing reaches inference, storage or a diary.
// npm run build -- --outDir /tmp/x && QA_DIST=/tmp/x QA_SCREENSHOTS=<dir> node qa/phone-declutter-510.cjs
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || `${os.homedir()}/noevia-local-test/node_modules/playwright-core`);
const { createFixture } = require('./diary-fixture.cjs');
const port = Number(process.env.QA_PORT || 31510), origin = `http://localhost:${port}`;
const out = process.env.QA_SCREENSHOTS || path.join(os.tmpdir(), 'noevia-phone-declutter-510');
const failures = [], errors = []; let checks = 0;
const check = (ok, label, detail) => { checks++; if (!ok) failures.push({ label, detail }); };
// A step that cannot run (an element that is not there yet) is a failure, not a crash, so a
// run against the old build still lists every check it misses.
const step = async (label, fn) => { try { await fn(); } catch (e) { checks++; failures.push({ label, detail: `${String(e.message || e).split('\n')[0]} ${(String(e.stack).match(/phone-declutter-510\.cjs:\d+/) || [''])[0]}` }); } };

const FREE_CONTEXT = { id: '__free-synthetic', name: 'Synthetic free chat', routing: 'auto', files: [], assets: [], toolboxes: ['core'] };
const PROJECTS = [
  { id: 'p1', name: 'Synthetic project', pinned: true, updatedAt: 5, files: [], assets: [], chats: [], goal: '', instructions: '', memories: [], toolboxes: ['core'] },
  { id: 'p2', name: 'Other project', updatedAt: 4, files: [], assets: [], chats: [], goal: '', instructions: '', memories: [], toolboxes: ['core'] },
];
const PERMITTED = { mode: 'chat', boxes: [{ id: 'core', label: 'Synthetic core', description: 'Synthetic tools', source: 'builtin', state: 'available', reason: null, active: false,
  tools: [{ name: 'synthetic_lookup', description: 'Looks up nothing real', permission: 'allowed', reason: null }] }] };

async function open(browser, { width, height, mcpError = null, family = null }) {
  const phone = width < 768;
  const page = await browser.newPage({ viewport: { width, height }, isMobile: phone, hasTouch: phone, reducedMotion: 'reduce' });
  if (family) await page.addInitScript(f => localStorage.setItem('noevia:theme-family', f), family);
  page.on('pageerror', e => errors.push({ width, error: e.message }));
  await page.route('https://**/*', r => r.abort());
  await page.route('**/api/toolboxes', r => r.fulfill({ json: { toolboxes: [{ id: 'core', label: 'Synthetic core', description: 'Synthetic tools', source: 'builtin', toolCount: 1, estTokens: 10 }],
    mcp: { configured: true, discovered: 175, servers: [{ id: 'synthetic-a', auth: 'internal', error: mcpError, discovered: 175 }] } } }));
  await page.route(u => u.pathname === '/api/toolboxes/permitted', r => r.fulfill({ json: PERMITTED }));
  await page.route('**/api/workspace', r => r.fulfill({ json: { projects: PROJECTS, freeChats: [
    { id: 'pin', title: 'Synthetic pinned chat', pinned: true, updatedAt: 10 }, { id: 'c1', title: 'Synthetic chat one', updatedAt: 9 }] } }));
  await page.route('**/api/chats/*/context', r => r.fulfill({ json: { project: FREE_CONTEXT } }));
  await page.route('**/api/models/installed', r => r.fulfill({ json: [{ name: 'synthetic-model-Q4_K_M', labels: [] }] }));
  await page.goto(origin);
  await page.getByRole('textbox', { name: 'Message', exact: true }).waitFor();
  await page.getByRole('button', { name: 'Thinking effort', exact: true }).waitFor();
  await page.waitForTimeout(150);
  return page;
}
const visible = (page, selector) => page.locator(selector).first().isVisible().catch(() => false);
const box = (locator) => locator.boundingBox();
const focusedName = (page) => page.evaluate(() => { const e = document.activeElement; return e && e !== document.body ? (e.getAttribute('aria-label') || e.className || e.tagName) : null; });

(async () => {
  fs.mkdirSync(out, { recursive: true });
  const fixture = createFixture(port); await fixture.listen();
  const browser = await chromium.launch({ channel: 'chrome', headless: true });
  try {
    // ── Phone, 390x844 ─────────────────────────────────────────────────────
    const W = 390, H = 844;
    await step('phone: home and composer', async () => {
      const page = await open(browser, { width: W, height: H });
      await page.screenshot({ path: path.join(out, 'phone-home.png') });
      check(await page.locator('.empty-state h1').isVisible(), 'phone: the greeting heading stays');
      check(!(await visible(page, '.empty-state > p:not(.home-diagnostic)')), 'phone: home subtitle hidden');
      check(!(await visible(page, '.composer-mode-harness')), 'phone: chat mode caption hidden');
      check(await page.locator('.home-recents').count() === 0 || !(await visible(page, '.home-recents')), 'phone: no Recent chats list on the blank page');
      check(!(await visible(page, '.tool-catalogue-trigger')), 'phone: standalone Tools button hidden');
      const modeGroup = page.getByRole('radiogroup', { name: /./ });
      check(await modeGroup.isVisible(), 'phone: Chat/Cowork switch still reachable');
      const modeBar = await box(page.locator('.composer-mode-bar'));
      check(modeBar && modeBar.height <= 52, 'phone: mode switch is one compact row', modeBar);
      for (const radio of await modeGroup.getByRole('radio').all()) { const b = await box(radio); check(b && b.height >= 44, 'phone: mode option is a 44px target', b); }

      // The composer sits on the bottom edge.
      const composer = await box(page.locator('.chat-workspace .chat-composer-inner'));
      check(composer && H - (composer.y + composer.height) <= 40, 'phone: composer bottom within 40px of the viewport bottom', composer);

      // Composer pills: short model name, Thinking as an icon; names unchanged.
      const model = page.getByRole('button', { name: 'Choose model: Auto (Fast/Smart)', exact: true });
      check(await model.isVisible(), 'phone: model pill keeps its full accessible name');
      const modelText = (await model.innerText()).trim();
      check(modelText === 'Auto', 'phone: model pill shows a short label', modelText);
      const thinking = page.getByRole('button', { name: 'Thinking effort', exact: true });
      const thinkingText = (await thinking.innerText()).trim();
      check(thinkingText === '', 'phone: Thinking pill is icon-only at Auto', thinkingText);
      const row = [];
      for (const name of ['Add files and tools', 'Choose model: Auto (Fast/Smart)', 'Thinking effort', 'Send']) {
        const b = await box(page.getByRole('button', { name, exact: true })); row.push({ name, ...b });
        check(b && b.width >= 44 && b.height >= 44, `phone: ${name} is a 44px target`, b);
      }
      check(row.every((b, i) => i === 0 || b.x >= row[i - 1].x + row[i - 1].width - 0.5), 'phone: composer controls sit side by side without overlap', row);
      check(row.every(b => Math.abs((b.y + b.height / 2) - (row[0].y + row[0].height / 2)) < 4), 'phone: composer controls share one row', row);
      await page.close();
    });
    await step('phone: Tools from the + menu', async () => {
      const page = await open(browser, { width: W, height: H });
      // Tools moved into the + menu and opens the same catalogue; Escape returns focus to +.
      await page.getByRole('button', { name: 'Add files and tools', exact: true }).click();
      const toolsRow = page.locator('.composer-actions-panel .composer-browse-tools');
      check(await toolsRow.isVisible(), 'phone: Tools is in the + menu');
      const toolsBox = await box(toolsRow); check(toolsBox && toolsBox.height >= 44, 'phone: Tools menu row is a 44px target', toolsBox);
      await page.screenshot({ path: path.join(out, 'phone-plus-menu.png') });
      await toolsRow.click();
      const search = page.getByRole('combobox');
      await search.waitFor();
      await page.getByRole('option', { name: /Synthetic core/ }).waitFor();
      const panel = await box(page.locator('.tool-catalogue-panel'));
      check(panel && panel.x >= 0 && panel.x + panel.width <= W + 1 && panel.y >= 0, 'phone: tool catalogue fits the viewport', panel);
      check(await search.evaluate(e => e === document.activeElement), 'phone: catalogue search takes focus');
      await page.waitForTimeout(200);
      await page.screenshot({ path: path.join(out, 'phone-tools.png') });
      await page.keyboard.press('Escape');
      check(!(await visible(page, '.tool-catalogue-panel')), 'phone: Escape closes the catalogue');
      check(await focusedName(page) === 'Add files and tools', 'phone: focus returns to the + button', await focusedName(page));
      await page.close();
    });
    await step('phone: header sliders and drawer', async () => {
      const page = await open(browser, { width: W, height: H });
      // Header sliders open this chat's model and tools, not global Settings.
      const chatSettings = page.getByRole('button', { name: 'Model and tools', exact: true });
      check(await chatSettings.isVisible(), 'phone: header sliders name the chat settings');
      check(await page.locator('.chat-header').getByRole('button', { name: 'Settings', exact: true }).count() === 0, 'phone: header no longer duplicates Settings');
      await chatSettings.click();
      await page.getByRole('dialog', { name: 'Model and tools' }).waitFor();
      check(!/\/settings/.test(page.url()), 'phone: sliders did not open global Settings', page.url());
      await page.screenshot({ path: path.join(out, 'phone-chat-settings.png') });
      await page.keyboard.press('Escape');
      await page.getByRole('dialog', { name: 'Model and tools' }).waitFor({ state: 'hidden' });

      // Drawer.
      await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
      await page.locator('.sidebar').waitFor({ state: 'visible' }); await page.waitForTimeout(150);
      await page.screenshot({ path: path.join(out, 'phone-drawer.png') });
      const drawerStyles = await page.evaluate(() => {
        const read = (sel) => { const e = document.querySelector(sel), c = e && getComputedStyle(e); return c && { top: c.borderTopWidth, color: c.borderTopColor, bg: c.backgroundColor, image: c.backgroundImage, shadow: c.boxShadow }; };
        return { search: read('.sidebar .shell-search'), newChat: read('.sidebar .new-chat-btn') };
      });
      const quiet = (s) => s && (s.top === '0px' || /rgba\(0, 0, 0, 0\)|transparent/.test(s.color)) && s.shadow === 'none';
      check(quiet(drawerStyles.search), 'phone: drawer search has no heavy border', drawerStyles.search);
      check(quiet(drawerStyles.newChat) && drawerStyles.newChat.bg === 'rgba(0, 0, 0, 0)' && drawerStyles.newChat.image === 'none', 'phone: drawer New chat is a quiet row', drawerStyles.newChat);
      check(await page.getByRole('textbox', { name: 'Search noevia' }).isVisible(), 'phone: drawer search stays');
      check(await page.locator('.sidebar .new-chat-btn').isVisible(), 'phone: drawer New chat stays');
      check(!(await page.getByRole('button', { name: 'New chat in Synthetic project', exact: true }).isVisible()), 'phone: project-row pencil hidden');
      check(!(await visible(page, '.sidebar .mcp-row')), 'phone: healthy MCP footer line hidden');
      check(await page.getByRole('button', { name: /Account menu for/ }).isVisible(), 'phone: account menu stays');
      check(await page.getByRole('button', { name: 'Synthetic chat one' }).first().isVisible(), 'phone: recent chats live in the drawer');
      const options = page.getByRole('button', { name: 'Options for Synthetic project', exact: true });
      const ob = await box(options); check(ob && ob.width >= 44 && ob.height >= 44, 'phone: project ⋯ is a 44px target', ob);
      await options.click();
      const newInProject = page.getByRole('menuitem', { name: 'New chat in project' });
      check(await newInProject.isVisible(), 'phone: project ⋯ menu carries New chat in project');
      await page.screenshot({ path: path.join(out, 'phone-project-menu.png') });
      await newInProject.click();
      await page.locator('.sidebar.is-expanded').waitFor({ state: 'detached' }).catch(() => {});
      await page.locator('.crumb-back', { hasText: 'Synthetic project' }).waitFor();
      check(true, 'phone: New chat in project opens a chat in that project');

      // In a project chat the sliders open the project's own settings.
      const projectSettings = page.getByRole('button', { name: 'Project settings', exact: true });
      check(await projectSettings.isVisible(), 'phone: project chat sliders name Project settings');
      await projectSettings.click();
      await page.getByRole('dialog', { name: 'Edit Synthetic project' }).waitFor();
      check(!/\/settings/.test(page.url()), 'phone: project sliders did not open global Settings', page.url());
      await page.screenshot({ path: path.join(out, 'phone-project-settings.png') });
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), 'phone: no horizontal overflow');
      await page.close();
    });
    // A problem with MCP still shows on a phone.
    await step('phone: degraded MCP', async () => {
      const page = await open(browser, { width: 390, height: 844, mcpError: 'synthetic outage' });
      await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
      await page.locator('.sidebar').waitFor({ state: 'visible' });
      check(await visible(page, '.sidebar .mcp-row.is-degraded'), 'phone: a degraded MCP line stays visible');
      await page.close();
    });
    // Every theme family gets the quiet drawer controls.
    for (const family of ['editorial', 'contemporary', 'glass']) await step(`phone: ${family} drawer`, async () => {
      const page = await open(browser, { width: W, height: H, family });
      await page.getByRole('button', { name: 'Open navigation', exact: true }).click();
      await page.locator('.sidebar').waitFor({ state: 'visible' }); await page.waitForTimeout(150);
      const s = await page.locator('.sidebar .new-chat-btn').evaluate(e => { const c = getComputedStyle(e); return { bg: c.backgroundColor, image: c.backgroundImage, shadow: c.boxShadow }; });
      check(s.bg === 'rgba(0, 0, 0, 0)' && s.image === 'none' && s.shadow === 'none', `phone: ${family} New chat is a quiet row`, s);
      const q = await page.locator('.sidebar .shell-search').evaluate(e => getComputedStyle(e).borderTopWidth);
      check(q === '0px', `phone: ${family} search has no border`, q);
      await page.screenshot({ path: path.join(out, `phone-drawer-${family}.png`) });
      await page.close();
    });
    // The narrowest phone and a small tablet keep one composer row and reach Tools.
    for (const [width, height] of [[320, 640], [700, 900]]) await step(`${width}px: composer and Tools`, async () => {
      const page = await open(browser, { width, height });
      check(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), `${width}px: no horizontal overflow`);
      const send = await box(page.getByRole('button', { name: 'Send', exact: true }));
      check(send && send.x + send.width <= width, `${width}px: send stays on screen`, send);
      await page.getByRole('button', { name: 'Add files and tools', exact: true }).click();
      await page.locator('.composer-actions-panel .composer-browse-tools').click();
      await page.getByRole('combobox').waitFor(); await page.waitForTimeout(200);
      await page.screenshot({ path: path.join(out, `tools-${width}.png`) });
      await page.close();
    });
    // ── Desktop, 1280x800: unchanged ───────────────────────────────────────
    await step('desktop: unchanged', async () => {
      const page = await open(browser, { width: 1280, height: 800 });
      await page.screenshot({ path: path.join(out, 'desktop-home.png') });
      check(await visible(page, '.empty-state > p:not(.home-diagnostic)'), 'desktop: home subtitle shown');
      check(await visible(page, '.composer-mode-harness'), 'desktop: mode caption shown');
      check(await visible(page, '.tool-catalogue-trigger'), 'desktop: Tools button shown');
      check(await visible(page, '.home-recents'), 'desktop: Recent chats shown');
      check((await page.getByRole('button', { name: 'Choose model: Auto (Fast/Smart)', exact: true }).innerText()).replace(/\s+/g, '').includes('(Fast/Smart)'), 'desktop: full model label');
      check((await page.getByRole('button', { name: 'Thinking effort', exact: true }).innerText()).includes('Thinking'), 'desktop: Thinking pill keeps its words');
      await page.getByRole('button', { name: 'Add files and tools', exact: true }).click();
      await page.locator('.composer-actions-panel').waitFor();
      check(!(await visible(page, '.composer-actions-panel .composer-browse-tools')), 'desktop: + menu has no extra Tools row');
      await page.keyboard.press('Escape');
      check(await page.locator('.chat-header').getByRole('button', { name: 'Settings', exact: true }).isVisible(), 'desktop: header sliders still open Settings');
      check(await visible(page, '.sidebar .mcp-row'), 'desktop: MCP footer line shown');
      check(await page.getByRole('button', { name: 'New chat in Synthetic project', exact: true }).count() === 1, 'desktop: project-row pencil kept');
      const nb = await page.locator('.sidebar .new-chat-btn').evaluate(e => getComputedStyle(e).borderTopWidth);
      check(nb !== '0px', 'desktop: New chat keeps its outline', nb);
      // Row actions reveal on hover at desktop, as before.
      await page.locator('.proj-row', { hasText: 'Synthetic project' }).first().hover();
      await page.getByRole('button', { name: 'Options for Synthetic project', exact: true }).click();
      await page.getByRole('menu').waitFor();
      check(await page.getByRole('menuitem', { name: 'New chat in project' }).count() === 0, 'desktop: project menu unchanged');
      await page.keyboard.press('Escape');
      await page.close();
    });
    check(errors.length === 0, 'no browser errors', errors);
    check(fixture.requests.length === 0, 'no inference requests', fixture.requests);
    fs.writeFileSync(path.join(out, 'results.json'), JSON.stringify({ checks, failures, errors }, null, 2));
    console.log(JSON.stringify({ checks, failures }, null, 2));
    if (failures.length) process.exitCode = 1;
  } finally { await browser.close(); await fixture.close(); }
})().catch(e => { console.error(e); process.exitCode = 1; });
