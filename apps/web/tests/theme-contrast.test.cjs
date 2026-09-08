const { test } = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const css = readFileSync(join(__dirname, '../src/styles/tokens.css'), 'utf8');
function luminance(hex) {
  const rgb = hex.slice(1).match(/../g).map(v => parseInt(v, 16) / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4);
  return rgb[0] * .2126 + rgb[1] * .7152 + rgb[2] * .0722;
}
function contrast(a,b) { const x=luminance(a),y=luminance(b);return (Math.max(x,y)+.05)/(Math.min(x,y)+.05); }
for (const mode of ['dark','light']) test(`Polymetal ${mode}: semantic text, actions and control contrast`, () => {
  const block=css.match(new RegExp(`\\[data-theme='${mode}'\\] \\{([^}]+)`))[1];
  const tokens=Object.fromEntries([...block.matchAll(/--([\w-]+):\s*(#[\da-f]{6})/gi)].map(m=>[m[1],m[2]]));
  for (const bg of ['bg-canvas','bg-surface','tint-garnet','bg-chrome','bg-app']) {
    for (const fg of ['text-primary','text-secondary','accent-text','good']) {
      const ratio=contrast(tokens[fg],tokens[bg]);
      assert.ok(ratio >= (fg==='text-primary'?7:4.5),`${mode} ${fg}/${bg}: ${ratio.toFixed(2)}`);
    }
    for (const fg of ['focus-ring','control-border']) assert.ok(contrast(tokens[fg],tokens[bg]) >= 3,`${mode} ${fg}/${bg}`);
  }
  assert.ok(contrast('#FFFFFF',tokens['accent-garnet']) >= 4.5,`${mode} primary action text`);
});
