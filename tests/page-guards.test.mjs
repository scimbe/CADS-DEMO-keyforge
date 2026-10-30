// Source guards for page behaviour that needs a browser to reach.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');

test('status text is never rendered as HTML', () => {
  assert.doesNotMatch(html, /el\.innerHTML = `<div class="status/);
});

test('a failed detail fetch never silently swaps in the stored manifest', () => {
  const fn = /async function loadManifestDetail[\s\S]*?\n  }\n/.exec(html)[0];
  assert.doesNotMatch(fn, /FALLBACK_MANIFEST/);
});
