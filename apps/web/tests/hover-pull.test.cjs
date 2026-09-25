'use strict';
// Hover pull (#313): caps, direction, the 10 Hz refresh limit (no clinging), the return, and
// the off switches (touch, coarse pointers, reduced motion, text entry). Synthetic DOM only.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const exportsObj = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(path.join(__dirname, '../src/hover-pull.ts'), 'utf8'), { compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 } }).outputText, { exports: exportsObj, Math, Number });
const pull = exportsObj;
const box = { left: 100, top: 100, width: 200, height: 40 };

test('pull points toward the pointer and never exceeds 3px or 2°', () => {
  const right = pull.pullFor(box, 300, 120);
  assert.equal(right.x, 3); assert.equal(right.y, 0); assert.ok(right.ry > 0);
  const topLeft = pull.pullFor(box, 100, 100);
  assert.equal(topLeft.x, -3); assert.equal(topLeft.y, -3); assert.ok(topLeft.rx > 0 && topLeft.ry < 0);
  for (const [x, y] of [[-5000, -5000], [5000, 5000], [200, 120], [150, 90], [301, 141]]) {
    const p = pull.pullFor(box, x, y);
    assert.ok(Math.abs(p.x) <= pull.PULL_MAX_SHIFT && Math.abs(p.y) <= pull.PULL_MAX_SHIFT, JSON.stringify(p));
    assert.ok(Math.hypot(p.rx, p.ry) <= pull.PULL_MAX_TILT * Math.SQRT2);
    const frame = pull.pullKeyframe(p);
    const angle = parseFloat(String(frame.rotate).split(' ').at(-1));
    assert.ok(Math.abs(angle) <= pull.PULL_MAX_TILT, frame.rotate);
  }
  assert.deepEqual({ ...pull.pullFor(box, 200, 120) }, { x: 0, y: 0, rx: 0, ry: 0 });
  assert.deepEqual({ ...pull.pullFor({ left: 0, top: 0, width: 0, height: 0 }, 5, 5) }, { x: 0, y: 0, rx: 0, ry: 0 });
});

test('the target list covers cards, buttons, sidebar rows and chips, never text entry', () => {
  for (const s of ['.project-card', '.btn', '.new-chat-btn', '.chat-row', '.chip']) assert.ok(pull.PULL_TARGETS.includes(s), s);
  assert.doesNotMatch(pull.PULL_TARGETS, /\b(input|textarea|select)\b/);
});

// A tiny DOM: one pullable button containing a span, one input; records animations.
function harness({ fine = true, reduced = false, motion = null } = {}) {
  const listeners = {}, animations = [];
  const media = (q) => ({ matches: q.includes('reduced-motion') ? reduced : fine, addEventListener() {}, removeEventListener() {} });
  const attrs = { 'data-motion': motion };
  const root = { getAttribute: (k) => attrs[k] ?? null };
  const el = (name, matches, parent = null) => {
    const node = {
      name, parent, disabled: false, isConnected: true, attributes: {}, style: { removeProperty() {}, getPropertyValue: () => '' },
      setAttribute(k, v) { this.attributes[k] = v; }, removeAttribute(k) { delete this.attributes[k]; }, getAttribute(k) { return this.attributes[k] ?? null; },
      getBoundingClientRect: () => box,
      contains(other) { for (let n = other; n; n = n.parent) if (n === this) return true; return false; },
      closest(sel) { for (let n = this; n; n = n.parent) if (n.matches(sel)) return n; return null; },
      matches: (sel) => matches(sel),
      animate(frames, opts) { const a = { el: node, frames, opts, cancel() {}, commitStyles() {}, addEventListener() {} }; animations.push(a); return a; },
    };
    return node;
  };
  const button = el('button', (sel) => sel === pull.PULL_TARGETS);
  const label = el('span', () => false, button);
  const input = el('input', (sel) => /\binput\b/.test(sel) && sel !== pull.PULL_TARGETS);
  const doc = { documentElement: root, addEventListener: (t, f) => { listeners[t] = f; }, removeEventListener() {} };
  const win = { matchMedia: media, getComputedStyle: () => ({ getPropertyValue: (n) => (n === '--motion-quick' ? '180ms' : n === '--motion-considered' ? '300ms' : 'ease-out') }) };
  const stop = pull.startHoverPull(doc, win);
  const fire = (type, target, extra = {}) => listeners[type]({ target, clientX: 300, clientY: 120, pointerType: 'mouse', timeStamp: 0, relatedTarget: null, ...extra });
  return { fire, button, label, input, animations, stop };
}

test('enter pulls once; moves refresh at most every 100 ms; leave springs back', () => {
  const h = harness();
  h.fire('pointerover', h.label, { timeStamp: 1000 });
  assert.equal(h.animations.length, 1);
  assert.equal(h.animations[0].opts.duration, 180);
  assert.equal(h.animations[0].frames[0].translate, '3px 0px');
  for (let t = 1010; t < 1100; t += 10) h.fire('pointermove', h.label, { timeStamp: t });
  assert.equal(h.animations.length, 1, 'no refresh inside 100 ms');
  h.fire('pointermove', h.label, { timeStamp: 1100, clientX: 100 });
  assert.equal(h.animations.length, 2);
  assert.equal(h.animations[1].frames[0].translate, '-3px 0px', 'refresh keeps the same cap');
  // Moving onto the button's own child is not a leave.
  h.fire('pointerout', h.button, { relatedTarget: h.label });
  assert.equal(h.animations.length, 2);
  h.fire('pointerout', h.label, { relatedTarget: null });
  assert.equal(h.animations.length, 3);
  assert.equal(h.animations[2].opts.duration, 300);
  assert.equal(h.animations[2].frames[0].translate, '0px 0px');
  h.stop();
});

test('off for touch, coarse pointers, reduced motion (OS or Settings) and text inputs', () => {
  for (const opts of [{ fine: false }, { reduced: true }, { motion: 'reduced' }]) {
    const h = harness(opts);
    h.fire('pointerover', h.label, { timeStamp: 1000 });
    assert.equal(h.animations.length, 0, JSON.stringify(opts));
  }
  const h = harness();
  h.fire('pointerover', h.label, { pointerType: 'touch' });
  h.fire('pointerover', h.input);
  assert.equal(h.animations.length, 0);
  h.button.disabled = true;
  h.fire('pointerover', h.label);
  assert.equal(h.animations.length, 0, 'disabled buttons stay still');
});
