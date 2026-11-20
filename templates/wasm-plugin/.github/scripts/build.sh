#!/usr/bin/env bash
# Build the selected Cargo package and stage its verified Pumpkin Wasm component.
set -euo pipefail
source .github/plugin.env

target=wasm32-wasip3
component=$(cargo metadata --locked --no-deps --format-version 1 | jq -er \
    --arg pkg "$CARGO_PACKAGE" --arg target "$target" '
    .target_directory as $dir
    | [.packages[] | select(.name == $pkg) | .targets[] | select(.crate_types | index("cdylib")) | .name]
    | if length == 1 then "\($dir)/\($target)/release/\(.[0]).wasm"
      else error("Expected one cdylib target for Cargo package \($pkg)") end')
cargo fmt --check --package "$CARGO_PACKAGE"
cargo clippy --release --locked --package "$CARGO_PACKAGE" --lib --target "$target" -- -D warnings
cargo build --release --locked --package "$CARGO_PACKAGE" --lib --target "$target"
wasm-tools validate --features all "$component"

# Check the exported callback names and async ABI in Pumpkin's v0.2.0 plugin world.
mkdir -p target
stage=$(mktemp -d target/.plugin-build.XXXXXXXX)
trap 'rm -rf -- "$stage"' EXIT
wit="$stage/component.wit"
wasm-tools component wit "$component" > "$wit"
for interface in metadata gametest-callbacks; do
    grep -Fxq "  export pumpkin:plugin/$interface@0.2.0;" "$wit" || { echo "Missing Pumpkin 0.2.0 export: $interface" >&2; exit 1; }
done
grep -Fxq '  export init-plugin: func();' "$wit" || { echo 'Missing synchronous init-plugin export.' >&2; exit 1; }
for callback in on-load on-unload handle-event handle-command handle-command-suggestion \
    handle-task handle-ipc-message handle-ai-goal-can-start handle-ai-goal-should-continue \
    handle-ai-goal-start handle-ai-goal-stop handle-ai-goal-tick handle-generate-phase; do
    grep -Fq "  export $callback: async func(" "$wit" || { echo "Missing async Pumpkin export: $callback" >&2; exit 1; }
done
if grep '^  import wasi:' "$wit" | grep -vE '@0\.3\.[0-9]+;$'; then
    echo 'Expected WASI 0.3 for the imports listed above.' >&2
    exit 1
fi

# Assemble the complete bundle before replacing the dedicated output directory.
mkdir "$stage/assets"
cp -- "$component" "$stage/assets/$PLUGIN_NAME.wasm"
(cd "$stage/assets" && sha256sum "$PLUGIN_NAME.wasm" > SHA256SUMS)
rm -rf -- target/release-assets
mv -T -- "$stage/assets" target/release-assets
