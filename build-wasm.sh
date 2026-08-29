#!/usr/bin/env bash
# Builds the two wasm-bindgen packages Keyforge needs, into ./pkg/ct-agent-wasm and
# ./pkg/manifest-core-wasm (both gitignored -- generated build output, not source),
# hermetically inside a throwaway container. Mirrors CADS-webconference-demo's own
# build-wasm.sh convention (clone the pinned commit, build for wasm32-unknown-unknown,
# wasm-bindgen --target web) -- Keyforge just needs two crates from two different repos
# instead of one.
#
# 1. ct-agent-wasm (crate ct-agent-wasm, scimbe/ct-agent, wasm/ member): production-proven
#    holder-identity crypto (generate_holder_identity, holderSign) PLUS holderVerify, which
#    this demo's own groundwork PR added (scimbe/ct-agent#124, not yet merged -- pinned by
#    commit SHA until it lands, same as CADS-webconference-demo pins ct-agent by SHA because
#    that repo has no tagged release covering wasm/ yet either).
#
# 2. manifest-core-wasm (crate manifest-core-wasm, scimbe/CADS-agent-marketplace,
#    crates/manifest-core-wasm): wasm-bindgen bindings over manifest-core's OWN
#    ServiceManifest::sign_new/is_valid/signing_bytes -- this demo's other groundwork PR
#    (scimbe/CADS-agent-marketplace#45, not yet merged, and itself based on the also-open
#    #43 "signed demo_prompt block" -- the live registry at registry.bunsenbrenner.org
#    already runs #43's schema, confirmed by fetching a real manifest and finding it didn't
#    verify against `main`'s manifest-core until demo_prompt was accounted for; see this
#    demo's README for the full story). Pinned by commit SHA on top of #43's tip.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# scimbe/ct-agent#124 (feat/keyforge-holder-verify): adds holderVerify, mirroring
# holderSign. Bump once merged to main and a later commit is desired.
CT_AGENT_REF="${CT_AGENT_REF:-f05b52ce6419c22997d10b345d7716b904245537}"

# scimbe/CADS-agent-marketplace#45 (feat/manifest-core-wasm-bindings, based on #43
# feat/manifest-core-demo-prompt): adds the manifest-core-wasm crate. Bump once #43+#45
# are merged to main.
MARKETPLACE_REF="${MARKETPLACE_REF:-cbf16872ee1209c2fefe93d39e23c49af133dde0}"

OUT_DIR="$REPO_ROOT/pkg"
mkdir -p "$OUT_DIR"

echo "==> Building ct-agent-wasm @ $CT_AGENT_REF"
docker run --rm -m 2g --cpus 2 \
  -v "$REPO_ROOT":/work -w /work \
  -v ct-keyforge-agent-src:/agent-src \
  -v ct-keyforge-agent-target:/cargo-target \
  -v ct-keyforge-cargo-registry:/usr/local/cargo/registry \
  -v ct-keyforge-rustup:/usr/local/rustup \
  -v ct-keyforge-wasm-bindgen-cli:/usr/local/cargo/bin-wbg \
  rust:1-slim bash -c '
set -euo pipefail
export PATH=/usr/local/cargo/bin-wbg/bin:$PATH
export CARGO_TARGET_DIR=/cargo-target
apt-get update -qq >/dev/null && apt-get install -y -qq git >/dev/null

if [ ! -d /agent-src/.git ]; then
  git clone https://github.com/scimbe/ct-agent /agent-src
fi
git -C /agent-src fetch origin
git -C /agent-src checkout "'"$CT_AGENT_REF"'"

cd /agent-src
rustup target add wasm32-unknown-unknown >/dev/null 2>&1
cargo build -p ct-agent-wasm --release --target wasm32-unknown-unknown
if ! command -v wasm-bindgen >/dev/null; then
  cargo install wasm-bindgen-cli --version 0.2.126 --root /usr/local/cargo/bin-wbg
fi
mkdir -p /work/pkg/ct-agent-wasm
wasm-bindgen --target web --out-dir /work/pkg/ct-agent-wasm \
  /cargo-target/wasm32-unknown-unknown/release/ct_agent_wasm.wasm
'

echo "==> Building manifest-core-wasm @ $MARKETPLACE_REF"
docker run --rm -m 2g --cpus 2 \
  -v "$REPO_ROOT":/work -w /work \
  -v ct-keyforge-marketplace-src:/marketplace-src \
  -v ct-keyforge-marketplace-target:/cargo-target \
  -v ct-keyforge-cargo-registry:/usr/local/cargo/registry \
  -v ct-keyforge-rustup:/usr/local/rustup \
  -v ct-keyforge-wasm-bindgen-cli:/usr/local/cargo/bin-wbg \
  rust:1-slim bash -c '
set -euo pipefail
export PATH=/usr/local/cargo/bin-wbg/bin:$PATH
export CARGO_TARGET_DIR=/cargo-target
apt-get update -qq >/dev/null && apt-get install -y -qq git >/dev/null

if [ ! -d /marketplace-src/.git ]; then
  git clone https://github.com/scimbe/CADS-agent-marketplace /marketplace-src
fi
git -C /marketplace-src fetch origin
git -C /marketplace-src checkout "'"$MARKETPLACE_REF"'"

cd /marketplace-src
rustup target add wasm32-unknown-unknown >/dev/null 2>&1
cargo build -p manifest-core-wasm --release --target wasm32-unknown-unknown
if ! command -v wasm-bindgen >/dev/null; then
  cargo install wasm-bindgen-cli --version 0.2.126 --root /usr/local/cargo/bin-wbg
fi
mkdir -p /work/pkg/manifest-core-wasm
wasm-bindgen --target web --out-dir /work/pkg/manifest-core-wasm \
  /cargo-target/wasm32-unknown-unknown/release/manifest_core_wasm.wasm
'

echo "built: $OUT_DIR/ct-agent-wasm (from ct-agent@$CT_AGENT_REF)"
echo "built: $OUT_DIR/manifest-core-wasm (from CADS-agent-marketplace@$MARKETPLACE_REF)"
