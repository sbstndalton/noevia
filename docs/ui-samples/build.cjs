#!/usr/bin/env node
'use strict';
// Builds foundation.html from foundation.src.html by inlining the Lucide icon nodes it uses.
// Usage: node docs/ui-samples/build.cjs <path to lucide-static icon-nodes.json>
// Then open foundation.html?screen=settings|project|connectors&theme=light|dark in a browser.
const fs = require('node:fs');
const path = require('node:path');
const nodes = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
const src = fs.readFileSync(path.join(__dirname, 'foundation.src.html'), 'utf8');
const used = new Set(['check', 'hand', 'ban', ...[...src.matchAll(/\{\{([a-z0-9-]+)\}\}/g)].map((m) => m[1])]);
used.delete('gdrive');
const icons = {};
for (const name of used) {
  if (!nodes[name]) throw Error(`unknown Lucide icon: ${name}`);
  icons[name] = nodes[name];
}
fs.writeFileSync(path.join(__dirname, 'foundation.html'), src.replace('/*ICONS*/{}', JSON.stringify(icons)));
console.log(`foundation.html: ${used.size} icons`);
