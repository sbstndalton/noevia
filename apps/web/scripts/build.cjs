#!/usr/bin/env node
// Wraps `vite build` so extra CLI args (e.g. `--outDir`) reach vite, and then
// stamps the icon/manifest cache-busting query in whatever directory vite
// actually wrote to. `npm run build -- --outDir X` appends its extra args to
// the end of the whole npm script line, not just the first command in it, so
// a plain `vite build && node scripts/stamp-icons.cjs` script would hand
// `--outDir X` to stamp-icons instead of to vite.
'use strict';
const path = require('node:path');
const { spawnSync } = require('node:child_process');

const args = process.argv.slice(2);
const outDirFlagIndex = args.indexOf('--outDir');
const outDir = outDirFlagIndex !== -1 && args[outDirFlagIndex + 1]
  ? path.resolve(args[outDirFlagIndex + 1])
  : path.join(__dirname, '..', 'dist');

const vite = spawnSync(process.execPath, [
  path.join(__dirname, '..', 'node_modules', 'vite', 'bin', 'vite.js'),
  'build', '--configLoader', 'runner', ...args,
], { stdio: 'inherit' });
if (vite.status !== 0) process.exit(vite.status || 1);

const stamp = spawnSync(process.execPath, [path.join(__dirname, 'stamp-icons.cjs'), outDir], { stdio: 'inherit' });
process.exit(stamp.status || 0);
