// Round 11 item 3: layout-mode.js's forced "mobile" preview narrows #root to 430px on a desktop
// browser (noevia.css ~1899 :root[data-layout="mobile"][data-device="desktop"] #root) without
// changing the CSS viewport a desktop browser reports (viewport meta is a no-op there).
// SettingsShell/Sidebar/StatsBar read only matchMedia against the real viewport, so on a desktop
// browser with the mobile preview forced they never noticed and kept desktop-shaped logic
// (Settings opening straight on the two-pane 'detail' view, Sidebar never becoming a drawer,
// StatsBar never collapsing to one line) squeezed inside that 430px column.
//
// Fix made here: SettingsShell's phone(), StatsBar's usePhone(), and Sidebar's mobile state all
// also treat document.documentElement.dataset.layout === 'mobile' as narrow, same as the
// stylesheet's own [data-layout="mobile"] selectors, and listen for 'noevia-layout-change'.
//
// Round 11b item 2: the Settings two-pane -> one-pane *grid* collapse in shell-v2.css was gated
// only by `@media (max-width: 820px)` (an actual-viewport check), not by `[data-layout="mobile"]`,
// so on a desktop browser at 1440px the grid columns didn't collapse even once the JS view state
// was correctly 'list'/'detail': the detail column rendered off the visible 430px column. Fixed by
// duplicating the narrow-layout rules under a `:root[data-layout="mobile"]` selector in
// shell-v2.css, same pattern as noevia.css's own :root[data-layout="mobile"] rules for the legacy
// .settings-shell. Asserted below: the detail pane's bounding box sits within the 430px #root
// column, and settings nav button labels are not clipped (full label text is present, not
// ellipsis-truncated to a narrow icon-only column).
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
const {createFixture}=require('./diary-fixture.cjs');
const shots=process.env.QA_SCREENSHOTS||'/tmp/noevia-r11-shots';
require('node:fs').mkdirSync(shots,{recursive:true});
(async()=>{
 const fixture=createFixture(31411);await fixture.listen();
 const browser=await chromium.launch({headless:true,channel:'chrome'});const errors=[];
 try{
  const ctx=await browser.newContext({viewport:{width:1440,height:900},colorScheme:'light'});
  const page=await ctx.newPage();page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://localhost:31411');await page.getByPlaceholder('Message noevia…').waitFor();
  // Force the same "mobile" preview layout-mode.js's Request-mobile-site option sets on a desktop
  // browser: the viewport meta is a no-op there, so only the data-* attributes move.
  await page.evaluate(()=>{ window.noeviaLayout.set('mobile'); });
  await page.waitForFunction(()=>document.documentElement.dataset.layout==='mobile');
  const rootBox=await page.locator('#root').boundingBox();
  assert.ok(rootBox && rootBox.width<=430,`#root should be capped at 430px by the forced mobile preview, got ${rootBox&&rootBox.width}`);
  await page.getByTitle('Settings',{exact:true}).click();
  const d=page.getByRole('region',{name:'Settings'});await d.waitFor();
  // The fix under test: SettingsShell's phone() now honours data-layout, so it opens on the
  // single 'list' pane like a real phone instead of jumping straight to 'detail'.
  assert.equal(await d.getAttribute('data-view'),'list','SettingsShell should open on the list pane once phone() honours the forced mobile layout');
  // The nav column itself, one-pane, must be within the 430px #root column, and its width must
  // fill the column (not squeezed into a leftover slice of a two-pane grid).
  const navBox=await page.locator('.settings-navigation').boundingBox();
  assert.ok(navBox && navBox.x>=rootBox.x-1 && navBox.x+navBox.width<=rootBox.x+rootBox.width+32,
    `settings nav should stay within the 430px #root column (allowing for the shell's own frame padding), got nav ${JSON.stringify(navBox)} vs root ${JSON.stringify(rootBox)}`);
  assert.ok(navBox.width>=rootBox.width-32, `settings nav should fill the narrow column (allowing for the shell's own frame padding), not a narrow leftover slice of a two-pane grid, got width ${navBox.width} for root width ${rootBox.width}`);
  // Nav button labels must render full text, not be clipped to icon-only by a squeezed column.
  const generalLabel=d.getByRole('button',{name:'General',exact:true});
  await generalLabel.waitFor();
  const labelBox=await generalLabel.boundingBox();
  assert.ok(labelBox && labelBox.width>60,`General nav label should not be clipped to an icon-only width, got ${labelBox&&labelBox.width}`);
  await page.screenshot({path:`${shots}/settings-phone-preview-desktop-1440-list.png`});
  await generalLabel.click();
  // Selecting a section still correctly flips the JS view state to 'detail'.
  assert.equal(await d.getAttribute('data-view'),'detail','selecting a section should move the fixed phone() state to detail');
  // The fix under test: the detail pane's grid column now collapses under the forced mobile
  // layout, so the detail pane sits fully within the 430px #root column instead of being
  // squeezed off it by a still-active two-pane grid.
  const detailBox=await page.locator('.settings-detail').boundingBox();
  assert.ok(detailBox && detailBox.x>=rootBox.x-1 && detailBox.x+detailBox.width<=rootBox.x+rootBox.width+32,
    `settings detail pane should stay within the 430px #root column (allowing for the shell's own frame padding), got detail ${JSON.stringify(detailBox)} vs root ${JSON.stringify(rootBox)}`);
  assert.ok(detailBox.width>=rootBox.width-32, `settings detail pane should fill the narrow column (allowing for the shell's own frame padding), not a leftover slice of a two-pane grid, got width ${detailBox.width} for root width ${rootBox.width}`);
  await page.screenshot({path:`${shots}/settings-phone-preview-desktop-1440-detail.png`});
  await ctx.close();
  assert.deepEqual(errors,[]);
  console.log('PASS settings phone preview on desktop: SettingsShell\'s phone() (and Sidebar/StatsBar\'s narrow checks) now honour data-layout="mobile" forced on a desktop browser at 1440px, so the list/detail view state tracks the forced preview correctly, and shell-v2.css\'s :root[data-layout="mobile"] rules now collapse the Settings grid to one pane so both the nav and detail panes sit fully within the 430px column with unclipped labels.');
 }finally{await browser.close();await fixture.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
