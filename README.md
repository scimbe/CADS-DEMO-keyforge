# Keyforge

A single self-contained static page (plain HTML/JS, no framework, no bundler) that generates an
ed25519 holder identity and signs/verifies a real
[CADS-agent-marketplace](https://github.com/scimbe/CADS-agent-marketplace) `ServiceManifest` —
entirely in the browser, in WebAssembly. The private key never leaves the page: it is generated
locally and used only for local `wasm` calls, never sent over the network.

Part of the [bunsenbrenner.org](https://bunsenbrenner.org) CADS zero-trust tunnel demo portfolio.

## What's real vs. new

| Piece | Status |
|---|---|
| `generate_holder_identity()`, `holderSign()` | **Production-proven.** Existing `ct-agent-wasm` exports (crate `ct-agent-wasm`, [scimbe/ct-agent](https://github.com/scimbe/ct-agent), `wasm/`), already CI-built and used by other demos (e.g. `CADS-webconference-demo`). |
| `holderVerify()` | **New**, added as groundwork for this demo: [scimbe/ct-agent#124](https://github.com/scimbe/ct-agent/pull/124) (branch `feat/keyforge-holder-verify`). Mirrors `holderSign`'s existing pattern exactly (`ed25519_dalek::VerifyingKey::verify`); 5 new unit tests (sign→verify round trip, tampered message, tampered signature, wrong key, malformed input). Not yet merged — this demo pins the PR's commit SHA. |
| `ServiceManifest::sign_new/is_valid/signing_bytes` | **Production-proven.** Existing `manifest-core` crate ([scimbe/CADS-agent-marketplace](https://github.com/scimbe/CADS-agent-marketplace), `crates/manifest-core`) — the real signed-manifest schema the live registry uses. |
| `manifest-core-wasm` (the crate exposing the above to JS) | **New**, added as groundwork for this demo: [scimbe/CADS-agent-marketplace#45](https://github.com/scimbe/CADS-agent-marketplace/pull/45) (branch `feat/manifest-core-wasm-bindings`). Calls `manifest-core`'s own `sign_new`/`is_valid`/`signing_bytes` directly — the domain-separated, length-prefixed preimage-construction logic is never reimplemented in JS. Not yet merged — this demo pins the PR's commit SHA. |

## A real blocker hit and fixed along the way

While building this, `verifyManifest` returned `false` against a manifest fetched live from
`https://registry.bunsenbrenner.org/manifests/<id>` — a genuine, deployed, correctly-signed
manifest. Root cause: the live registry serves manifests carrying a `demo_prompt` field
(guided natural-language configuration), and that field turned out to be part of the *signed*
preimage in an **already-open but unmerged** PR
([scimbe/CADS-agent-marketplace#43](https://github.com/scimbe/CADS-agent-marketplace/pull/43),
`feat/manifest-core-demo-prompt`) — the deployed registry runs that branch's schema, not `main`'s.
`main`'s `ServiceManifest::signing_bytes` doesn't know about `demo_prompt` at all, so it recomputed
a *different* preimage than what the registry actually signed, and verification failed.

Fixed by rebasing PR #45 onto PR #43's tip and wiring `demo_prompt` through
`signManifest`/`verifyManifest`/`isManifestValid`. Re-running the same manifest that failed
before the rebase now verifies correctly — see `examples/verify_real_manifest.rs` in PR #45,
kept as a regression check.

**Practical implication for anyone building against this registry:** if you're implementing
against `manifest-core`'s `main` branch today, your signature verification will not match what
`registry.bunsenbrenner.org` actually serves. PR #43 needs to land on `main` for that to line up.

## What you can do on this page

1. **Generate a holder identity** — a fresh ed25519 keypair, generated locally.
2. **Verify a real manifest** — fetches a live, publisher-signed manifest from the registry and
   checks its signature client-side. (See the CORS note below — this may fall back to a manifest
   fetched live via `curl` at write-time instead of by the page's own JS, but the signature check
   itself is always against real data, and you can always paste your own.)
3. **Sign your own manifest** — edit the prefilled template (or generate a fresh random one), sign
   it with your Step-1 identity, and verify the result.
4. **Bonus: raw `holderSign`/`holderVerify`** — sign and verify an arbitrary message directly,
   exercising this demo's own groundwork PR.

### A known, real constraint: CORS

`registry.bunsenbrenner.org` does not currently send an `Access-Control-Allow-Origin` header, so a
browser `fetch()` from a page served on a *different* origin (this demo, `localhost`, GitHub
Pages, wherever) will typically be blocked by the browser's CORS policy — confirmed by checking
the registry's response headers directly (`curl -I`) and finding none. When that happens, the page
shows the failure plainly and falls back to a manifest that *was* fetched live from the registry
(via `curl`, at the time this page was written) so the signature-verification demo still runs
against genuine, non-fabricated data. Pasting any manifest JSON (including one you `curl` yourself)
always works regardless of CORS.

## Building the wasm artifacts

```sh
./build-wasm.sh
```

Hermetic (runs in a throwaway `rust:1-slim` container via Docker), mirroring
`CADS-webconference-demo`'s own `build-wasm.sh` convention. Clones `ct-agent` and
`CADS-agent-marketplace` at pinned commit SHAs (see the script — both currently point at this
demo's own unmerged groundwork PR branches, since neither PR has landed on `main` yet), builds
`ct-agent-wasm` and `manifest-core-wasm` for `wasm32-unknown-unknown --release`, and runs
`wasm-bindgen --target web` into `./pkg/ct-agent-wasm/` and `./pkg/manifest-core-wasm/` — both
gitignored generated output, not source, same as `CADS-webconference-demo`'s `/pkg/`.

Bump the pinned SHAs once PR #124 (ct-agent) and PR #45/#43 (CADS-agent-marketplace) merge to
`main`.

## Running it

```sh
./build-wasm.sh
python3 -m http.server 8000
# open http://localhost:8000/
```

Plain static file serving — `index.html` loads the two wasm-bindgen ES modules directly via
`<script type="module">`. No build step beyond `./build-wasm.sh`.

## Security notes

- The private key is generated by WebAssembly running in your tab and is held only in page memory
  (a JS variable) — it is never written to `localStorage`, never sent in any `fetch`, and is gone
  on reload. This is a demo identity for trying the signing flow, not a place to keep a real one.
- Verification (`verifyManifest`/`isManifestValid`/`holderVerify`) needs only a **public** key and
  never touches a private key at all.
- `verifyManifest` checks the ed25519 signature only (authenticity); `isManifestValid` additionally
  checks `now < expires_at`. Neither checks *trust* — a correctly-signed manifest can still be from
  a publisher nobody should trust; that's a separate, explicit allowlist decision real
  `installer-engine` deployments make, out of scope for this demo.

---

**Keep the lab running.** Bunsenbrenner is free to use and runs on donated time and server costs.
If it helped you get something live, a small contribution keeps it going.
- [Support as a member →](https://steady.page/plans/77a32d9c-c399-4ca1-9515-7a628c7a9413)
- [Buy me a coffee →](https://buymeacoffee.com/bunsenbrenner)
- [GitHub — feature requests, code review, issues →](https://github.com/scimbe/CADS-Tunnel)

© Bunsenbrenner.org — Martin Becke
