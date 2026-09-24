// Regression for the sidebar chat row title clip bug (live QA, 2026-09-24, Brave ~983px):
// once the pin/archive/"…" actions appear on hover/focus, the row's padding-right
// squeeze re-measured the title's overflow and kicked off the marquee-scroll
// animation, which translated the text left and slid the leading character(s) out
// of the clipped view. The title must stay visible from its first character and
// truncate with an ellipsis on the right, with no horizontal transform while hovered.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict');
const {createFixture}=require('./diary-fixture.cjs');
const out=process.env.QA_SCREENSHOTS||'/tmp/noevia-shots';
(async()=>{
 const fixture=createFixture(31401);await fixture.listen();
 const browser=await chromium.launch({headless:true,channel:'chrome'});
 const errors=[];
 try{
  const page=await browser.newPage({viewport:{width:983,height:800}});
  page.on('pageerror',e=>errors.push(e.message));
  const title='QA test message 1';
  await page.route('**/api/workspace',r=>r.fulfill({json:{projects:[],freeChats:[{id:'c1',title,updatedAt:1000,pinned:false,messages:[]}]}}));
  await page.goto('http://localhost:31401');
  await page.getByPlaceholder('Message noevia…').waitFor();
  const row=page.locator('.chat-row',{hasText:title});
  await row.waitFor();
  await row.hover();
  // Sample across the full marquee cycle window: the title must never scroll away
  // from its first character while the row is hovered.
  for(let i=0;i<6;i++){
   await page.waitForTimeout(300);
   const info=await row.evaluate(el=>{
    const label=el.querySelector('.sidebar-label');
    const text=el.querySelector('.sidebar-label-text');
    return {
     transform:getComputedStyle(text).transform,
     startsWithFirstChar:text.getBoundingClientRect().left>=label.getBoundingClientRect().left-1 && text.textContent.startsWith('QA'),
    };
   });
   assert.equal(info.transform,'none',`iteration ${i}: title text should not be translated while hovered, got ${info.transform}`);
   assert.ok(info.startsWithFirstChar,`iteration ${i}: title should still start with its first characters ("QA…")`);
  }
  await row.screenshot({path:`${out}/chat-row-title-clip-hover.png`});
  assert.deepEqual(errors,[]);
  console.log('chat-row-title-clip: all checks passed');
 }finally{await browser.close();await fixture.close?.();}
})().catch(e=>{console.error(e);process.exit(1);});
