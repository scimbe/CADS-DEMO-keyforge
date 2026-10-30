// Runs the verdict logic from index.html itself (no copy of it): node --test tests/
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const m = /\/\/ VERDICT-START[^\n]*\n([\s\S]*?)\/\/ VERDICT-END/.exec(html);
assert.ok(m, 'verdict block missing from index.html');
const ctx = {};
vm.runInNewContext(`${m[1]}; this.manifestVerdict = manifestVerdict; this.unsignedFields = unsignedFields;`, ctx);
const { manifestVerdict } = ctx;

const PUB = 'aa'.repeat(32), ATTACKER = 'bb'.repeat(32);
const manifest = (extra = {}, key = PUB) => ({
  publisher_pubkey: key, manifest_id: '00', name: 'travel', version: '1', installer_kind: 'compose',
  bundle: { url: 'u', sha256: '00', compose_file: 'c' },
  env_template: [{ name: 'A', required: true, description: 'd' }],
  verify: { script: 's', timeout_secs: 1 }, issued_at: 1, expires_at: 2, signature: 'cc', ...extra,
});
const trusted = new Set([PUB]);

test('a re-signed manifest with a foreign key is not reported as authentic', () => {
  const v = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest({}, ATTACKER), trustedKeys: trusted });
  assert.equal(v.kind, 'bad');
  assert.match(v.text, /NOT a publisher key/);
  assert.doesNotMatch(v.text, /authentic/);
});

test('a field outside the signed schema is reported, not "unmodified"', () => {
  const v = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest({ evil_field: 'x' }), trustedKeys: trusted });
  assert.equal(v.kind, 'bad');
  assert.match(v.text, /NOT covered by the signature: evil_field/);
  const nested = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest({ bundle: { url: 'u', sha256: '0', compose_file: 'c', mirror: 'x' } }), trustedKeys: trusted });
  assert.match(nested.text, /bundle\.mirror/);
});

test('a registry key with a clean manifest passes', () => {
  const v = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest(), trustedKeys: trusted });
  assert.equal(v.kind, 'ok');
  assert.match(v.text, /listed by the live registry/);
});

test('without a registry answer the publisher is not vouched for', () => {
  const v = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest(), trustedKeys: null });
  assert.equal(v.kind, 'bad');
  assert.match(v.text, /not checked/);
});

test('own key from step 1 is named as such', () => {
  const v = manifestVerdict({ sigOk: true, validOk: true, manifest: manifest({}, ATTACKER), trustedKeys: trusted, ownKey: ATTACKER });
  assert.equal(v.kind, 'ok');
  assert.match(v.text, /your own key/);
});

test('expired and failed signatures stay bad', () => {
  assert.equal(manifestVerdict({ sigOk: true, validOk: false, manifest: manifest(), trustedKeys: trusted }).kind, 'bad');
  assert.equal(manifestVerdict({ sigOk: false, validOk: true, manifest: manifest(), trustedKeys: trusted }).kind, 'bad');
});
