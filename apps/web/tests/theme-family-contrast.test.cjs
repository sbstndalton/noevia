'use strict';
// Each theme family re-tones the neutral grounds (themes.css). The accent palettes are checked
// by theme-contrast.test.cjs on the unmixed tokens; this repeats the text and control checks on
// every family ground, in both modes, for every accent, evaluating color-mix() the way the
// browser does (sRGB, translucent grounds composited over the canvas they sit on).
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const palette = require('../scripts/palette.cjs');

const css = fs.readFileSync(path.join(__dirname, '../src/styles/tokens.css'), 'utf8');
const themes = fs.readFileSync(path.join(__dirname, '../src/styles/themes.css'), 'utf8').replace(/@media[^{]*\{(?:[^{}]*\{[^}]*\})*[^}]*\}/g, '');

const hex = (h) => h.slice(1).match(/../g).map((v) => parseInt(v, 16));
const toHex = (rgb) => '#' + rgb.map((v) => Math.round(v).toString(16).padStart(2, '0')).join('');
const lum = (h) => { const c = hex(h).map((v) => v / 255).map((v) => (v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4)); return c[0] * .2126 + c[1] * .7152 + c[2] * .0722; };
const contrast = (a, b) => { const x = lum(a), y = lum(b); return (Math.max(x, y) + .05) / (Math.min(x, y) + .05); };

function base(mode, accent) {
  const top = css.replace(/@media[^{]*\{(?:[^{}]*\{[^}]*\})*[^}]*\}/g, '');
  const applies = (s) => s === ':root' || s === '.theme-scope' || s === `[data-theme='${mode}']`
    || (s === `[data-palette='${accent}']:not([data-theme='light'])` && mode === 'dark')
    || (s === `[data-palette='${accent}'][data-theme='light']` && mode === 'light')
    || (s === ":root:not([data-theme='light'])" && mode === 'dark');
  const values = {};
  for (const [, selector, body] of top.matchAll(/([^{}]+)\{([^}]*)\}/g)) {
    if (!selector.replace(/\/\*[\s\S]*?\*\//g, '').split(',').map((s) => s.trim()).some(applies)) continue;
    for (const [, name, v] of body.matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) values[name] = v.trim();
  }
  return values;
}

function withFamily(values, family, mode) {
  const out = { ...values };
  const blocks = [`[data-family='${family}']`, mode === 'light' ? `[data-family='${family}'][data-theme='light']` : `[data-family='${family}']:not([data-theme='light'])`];
  for (const [, selector, body] of themes.matchAll(/([^{}]+)\{([^}]*)\}/g)) {
    if (!blocks.includes(selector.replace(/\/\*[\s\S]*?\*\//g, '').trim())) continue;
    for (const [, name, v] of body.matchAll(/--([\w-]+)\s*:\s*([^;]+);/g)) out[name] = v.trim();
  }
  const resolve = (name, over, seen = new Set()) => {
    if (seen.has(name)) throw Error(`cycle at --${name}`);
    const v = out[name];
    if (!v) throw Error(`--${name} undefined`);
    const color = (expr) => {
      expr = expr.trim();
      if (/^#[\da-f]{6}$/i.test(expr)) return { rgb: hex(expr), a: 1 };
      if (expr === 'transparent') return { rgb: [0, 0, 0], a: 0 };
      const ref = expr.match(/^var\(--([\w-]+)\)$/);
      if (ref) return { rgb: hex(resolve(ref[1], over, new Set([...seen, name]))), a: 1 };
      const mix = expr.match(/^color-mix\(in srgb,\s*(.+?)\s+(\d+)%,\s*(.+)\)$/);
      if (mix) {
        const p = Number(mix[2]) / 100, a = color(mix[1]), b = color(mix[3]);
        const alpha = a.a * p + b.a * (1 - p);
        const rgb = a.rgb.map((c, i) => (alpha ? (c * a.a * p + b.rgb[i] * b.a * (1 - p)) / alpha : 0));
        return { rgb, a: alpha };
      }
      throw Error(`cannot evaluate --${name}: ${expr}`);
    };
    const { rgb, a } = color(v);
    if (a >= .999) return toHex(rgb);
    const under = hex(over);
    return toHex(rgb.map((c, i) => c * a + under[i] * (1 - a)));
  };
  return { get: (name) => resolve(name, resolve('bg-app')), over: (name, ground) => resolve(name, ground) };
}

for (const family of ['editorial', 'contemporary', 'glass']) for (const mode of ['light', 'dark']) for (const accent of palette.PALETTE_NAMES) {
  test(`${family} · ${mode} · ${accent}: text and controls keep contrast on the family grounds`, () => {
    const t = withFamily(base(mode, accent), family, mode);
    for (const ground of ['bg-app', 'bg-chrome', 'bg-surface']) {
      const g = t.get(ground);
      assert.ok(contrast(t.get('text-primary'), g) >= 7, `${ground} ${g} text-primary ${contrast(t.get('text-primary'), g).toFixed(2)}`);
      for (const fg of ['text-secondary', 'accent-text']) assert.ok(contrast(t.get(fg), g) >= 4.5, `${ground} ${fg} ${contrast(t.get(fg), g).toFixed(2)}`);
      for (const fg of ['focus-ring', 'control-border']) assert.ok(contrast(t.get(fg), g) >= 3, `${ground} ${fg} ${contrast(t.get(fg), g).toFixed(2)}`);
    }
  });
}

// #313: the grounds each family adds. Contemporary's accent-tinted surface containers; Glass's
// translucent chrome, reading plane and sheets composited over the strongest bloom of the
// atmosphere behind them (the worst case for text), in both modes and every accent.
const GROUNDS = {
  editorial: [],
  contemporary: ['m3-surface', 'm3-container-low', 'm3-container', 'm3-container-high', 'm3-container-highest'],
  glass: [],
};
for (const family of ['editorial', 'contemporary', 'glass']) for (const mode of ['light', 'dark']) for (const accent of palette.PALETTE_NAMES) {
  test(`${family} · ${mode} · ${accent}: text keeps AA on the #313 family grounds`, () => {
    const t = withFamily(base(mode, accent), family, mode);
    const grounds = GROUNDS[family].map((name) => [name, t.get(name)]);
    if (family === 'glass') {
      for (const peak of ['glass-canvas-peak', 'glass-canvas-peak-2', 'glass-canvas-peak-3']) {
        const under = t.get(peak);
        for (const layer of ['bg-chrome', 'glass-plane', 'glass-sheet']) grounds.push([`${layer} over ${peak}`, t.over(layer, under)]);
      }
    }
    if (family === 'editorial') grounds.push(['bg-app', t.get('bg-app')]);
    for (const [name, g] of grounds) {
      assert.ok(contrast(t.get('text-primary'), g) >= 7, `${name} ${g} text-primary ${contrast(t.get('text-primary'), g).toFixed(2)}`);
      for (const fg of ['text-secondary', 'accent-text']) assert.ok(contrast(t.get(fg), g) >= 4.5, `${name} ${g} ${fg} ${contrast(t.get(fg), g).toFixed(2)}`);
      assert.ok(contrast(t.get('focus-ring'), g) >= 3, `${name} focus-ring ${contrast(t.get('focus-ring'), g).toFixed(2)}`);
    }
    // M3 roles used as containers keep their on-colours readable.
    for (const [bg, fg] of [['md-primary-container', 'md-on-primary-container'], ['md-secondary-container', 'md-on-secondary-container'], ['md-primary', 'md-on-primary']]) {
      assert.ok(contrast(t.get(fg), t.get(bg)) >= 4.5, `${fg} on ${bg} ${contrast(t.get(fg), t.get(bg)).toFixed(2)}`);
    }
  });
}
