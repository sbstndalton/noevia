// Sidebar navigation that works at every width: below 600px the sidebar is a
// drawer behind "Open navigation", so open it first when that toggle is showing.
async function navClick(page, name) {
  const toggle = page.getByRole('button', { name: 'Open navigation', exact: true });
  if (await toggle.isVisible()) {
    await toggle.click();
    await page.getByRole('dialog', { name: 'Navigation' }).waitFor();
  }
  const sidebar = page.locator('.sidebar');
  const entry = sidebar.getByRole('button', { name, exact: true }).and(page.locator('.nav-item'));
  await (await entry.count() ? entry : sidebar.getByRole('button', { name, exact: true })).first().click();
}
// Opens Settings at every width. #510: on a phone the chat header's sliders open the chat's
// own settings (its project, or its model and tools), so Settings is reached from the account
// menu there, as it is everywhere; wider screens keep the header shortcut.
async function openSettings(page) {
  await page.locator('[title="Settings"], [title="Model and tools"], [title="Project settings"], .account-trigger, .nav-drawer-toggle').filter({ visible: true }).first().waitFor();
  const header = page.getByTitle('Settings', { exact: true }).first();
  if (await header.isVisible()) { await header.click(); return; }
  const toggle = page.getByRole('button', { name: 'Open navigation', exact: true });
  if (await toggle.isVisible()) {
    await toggle.click();
    await page.getByRole('dialog', { name: 'Navigation' }).waitFor();
  }
  await page.getByRole('button', { name: /Account menu for/ }).click();
  await page.locator('.account-popover').getByRole('menuitem', { name: 'Settings', exact: true }).click();
}
module.exports = { navClick, openSettings };
