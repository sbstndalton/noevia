// compose.embed.yaml (issue #298) reproduces the live-only `embed` sidecar
// (docs/deployment.md "Release ea57c83"; docs/spec-service-boundaries.md §2,
// finding 8). No compose validation runs in CI, so this parses the overlay
// text directly rather than shelling out to `docker compose config`.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { composeEnvKeys } = require('./compose-env-keys.cjs');

const root = path.resolve(__dirname, '../../..');
const overlayPath = path.join(root, 'compose.embed.yaml');

test('compose.embed.yaml defines an embed service pinned to a digest', () => {
  const text = fs.readFileSync(overlayPath, 'utf8');
  assert.ok(/^  embed:\s*$/m.test(text), 'expected a top-level `embed:` service');
  const block = text.split('\n  embed:')[1].split(/\n  \S/)[0];
  const imageLine = block.match(/^\s*image:\s*(\S+)/m);
  assert.ok(imageLine, 'embed service has no image line');
  assert.ok(imageLine[1].includes('@sha256:'), 'embed image is not digest-pinned');
});

test('compose.embed.yaml only attaches embed to the default network', () => {
  const text = fs.readFileSync(overlayPath, 'utf8');
  const block = text.split('\n  embed:')[1].split(/\n  \S/)[0];
  const networksLine = block.match(/^\s*networks:\s*\[([^\]]*)\]/m);
  assert.ok(networksLine, 'embed service declares no networks');
  const networks = networksLine[1].split(',').map((n) => n.trim()).filter(Boolean);
  assert.deepEqual(networks, ['default'],
    'docs/spec-service-boundaries.md §2 says embed is default-network only');
});

test('compose.embed.yaml publishes no ports and declares a healthcheck', () => {
  const text = fs.readFileSync(overlayPath, 'utf8');
  const block = text.split('\n  embed:')[1].split(/\n  \S/)[0];
  assert.ok(!/^\s*ports:/m.test(block), 'embed must not publish a port');
  assert.ok(/^\s*healthcheck:/m.test(block), 'embed should declare a healthcheck');
});

test('compose.embed.yaml wires EMBEDDING_BASE_URL onto web', () => {
  const text = fs.readFileSync(overlayPath, 'utf8');
  const webKeys = composeEnvKeys(text, 'web');
  assert.ok(webKeys && webKeys.includes('EMBEDDING_BASE_URL'),
    'overlay must set web.environment.EMBEDDING_BASE_URL');
});
