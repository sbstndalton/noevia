const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const ts = require('typescript');

const source = fs.readFileSync(path.join(__dirname, '../src/setup-timezone.ts'), 'utf8');
const exportsObject = {};
vm.runInNewContext(ts.transpileModule(source, {
  compilerOptions: { module: ts.ModuleKind.CommonJS },
}).outputText, { exports: exportsObject, Intl });
const { timezoneEnvSetting } = exportsObject;

test('setup produces a usable TZ setting for IANA zones and UTC', () => {
  for (const zone of ['America/New_York', 'Asia/Kolkata', 'Europe/London', 'UTC']) {
    assert.equal(timezoneEnvSetting(` ${zone} `), `TZ=${zone}`);
  }
});

test('setup refuses invalid zones, fixed offsets, and env injection', () => {
  for (const zone of ['', 'Not/AZone', '-04:00', 'UTC\nOTHER=value', '$(date)', 'UTC#comment']) {
    assert.equal(timezoneEnvSetting(zone), null);
  }
});

test('both diary compose definitions pass through TZ with the documented default', () => {
  const root = path.resolve(__dirname, '../../..');
  const example = fs.readFileSync(path.join(root, '.env.example'), 'utf8');
  const defaultZone = example.match(/^TZ=(.+)$/m)[1];
  assert.equal(timezoneEnvSetting(defaultZone), `TZ=${defaultZone}`);
  for (const name of ['compose.yaml', 'deploy/examples/unraid-compose-manager.yml']) {
    const compose = fs.readFileSync(path.join(root, name), 'utf8');
    const diary = compose.split('  diary:')[1].split('\n  web:')[0];
    assert.ok(diary.includes(`      TZ: ${'${TZ:-'}${defaultZone}}`));
  }
});
