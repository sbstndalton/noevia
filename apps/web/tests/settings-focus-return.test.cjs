'use strict';
// #401: closing Settings (Escape or the Close button) must hand focus back to the control that
// opened it, not to <body>. This repo has no jsdom (see tests/menu-focus.test.cjs for the same
// approach), so the pure decision (settings-focus.ts) is unit-tested directly here, and the
// wiring that feeds it — App.tsx capturing an opener before Settings mounts, AccountMenu.tsx
// capturing its trigger before it unmounts its own popover, SettingsShell.tsx using both plus
// the composer fallback — is pinned by reading the source, the same technique
// tests/edit-project-modal-focus.test.cjs uses for EditProjectModal's initial-focus wiring.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const exports_ = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/settings-focus.ts'), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, { exports: exports_ });
const { closeFocusTarget } = exports_;

const el = (connected = true) => ({ isConnected: connected });

test('a still-connected opener (Escape from the ⌘, path, or an ordinary trigger click) gets focus back', () => {
  const opener = el(true);
  assert.equal(closeFocusTarget(opener, el(true)), opener);
});

test('#401 regression: an opener the caller already unmounted (the account menu\'s own popover button) falls through to the composer, not <body>', () => {
  const composer = el(true);
  assert.equal(closeFocusTarget(el(false), composer), composer);
});

test('no opener at all (nothing was focused, e.g. a fresh page load into Settings) also falls through to the composer', () => {
  const composer = el(true);
  assert.equal(closeFocusTarget(null, composer), composer);
});

test('no composer either (an exotic entry with neither) resolves to null rather than throwing', () => {
  assert.equal(closeFocusTarget(null, null), null);
  assert.equal(closeFocusTarget(el(false), null), null);
});

// ── Wiring: the pure decision above is only correct if the right elements reach it ─────────────

const settingsShellSrc = fs.readFileSync(path.join(__dirname, '../src/components/SettingsShell.tsx'), 'utf8');
const accountMenuSrc = fs.readFileSync(path.join(__dirname, '../src/components/AccountMenu.tsx'), 'utf8');
const appSrc = fs.readFileSync(path.join(__dirname, '../src/App.tsx'), 'utf8');
const sidebarSrc = fs.readFileSync(path.join(__dirname, '../src/components/Sidebar.tsx'), 'utf8');

test('SettingsShell reads the opener from a prop rather than capturing document.activeElement on its own mount', () => {
  assert.match(settingsShellSrc, /import \{ closeFocusTarget \} from '\.\.\/settings-focus';/);
  assert.match(settingsShellSrc, /const previous = opener\?\.current \?\? \(document\.activeElement as HTMLElement \| null\);/);
  assert.match(settingsShellSrc, /closeFocusTarget\(previous, document\.querySelector<HTMLElement>\('\.composer-input'\)\)\?\.focus\(\{ preventScroll: true \}\);/);
});

test('#401 regression: AccountMenu captures its own (still-mounted) trigger before closing its popover, not after', () => {
  // The bug: `setOpen(false)` unmounts the clicked popover item in the same batched update that
  // opens Settings, so reading `trigger.current` (or activeElement) afterwards is too late.
  const settingsItem = accountMenuSrc.match(/onClick=\{\(\)=>\{const opener=trigger\.current;setOpen\(false\);onSettings\(undefined,opener\);\}\}/);
  const usageItem = accountMenuSrc.match(/onClick=\{\(\)=>\{const opener=trigger\.current;setOpen\(false\);onSettings\('usage',opener\);\}\}/);
  assert.ok(settingsItem, 'the Settings menu item must read trigger.current before setOpen(false)');
  assert.ok(usageItem, 'the Usage menu item must read trigger.current before setOpen(false)');
});

test('the opener flows end to end: AccountMenu -> Sidebar -> App.openSettings -> a ref passed to SettingsShell', () => {
  assert.match(accountMenuSrc, /onSettings:\(section\?:'general'\|'usage', opener\?: HTMLElement \| null\)=>void/);
  assert.match(sidebarSrc, /onOpenSettings: \(section\?: 'general'\|'usage'\|'connectors', opener\?: HTMLElement \| null\) => void;/);
  assert.match(sidebarSrc, /onOpenSettings\(section, opener\)/);
  assert.match(appSrc, /const openSettings = \(section: SettingsSection = 'general', opener\?: HTMLElement \| null\) => \{/);
  assert.match(appSrc, /settingsOpenerRef\.current = opener !== undefined \? opener : \(typeof document !== 'undefined' \? \(document\.activeElement as HTMLElement \| null\) : null\);/);
  assert.match(appSrc, /opener=\{settingsOpenerRef\}/);
});
