#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

"$REPO_ROOT/scripts/test-release.sh" --help >/dev/null

if "$REPO_ROOT/scripts/test-release.sh" --rpc-file "$TEMP_DIR/missing.rpc" \
  >"$TEMP_DIR/missing.out" 2>&1; then
  echo "release gate accepted a missing RPC file" >&2
  exit 1
fi
grep -q "Missing RPC file" "$TEMP_DIR/missing.out"

mkdir -p "$TEMP_DIR/bin"
cat >"$TEMP_DIR/bin/forge" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s|%s\n' \
  "${FOUNDRY_PROFILE:-default}" \
  "${REQUIRE_ROBINHOOD_FORK:-false}" \
  "$*" >>"$FORGE_CALL_LOG"
EOF
chmod +x "$TEMP_DIR/bin/forge"

cat >"$TEMP_DIR/rpc" <<'EOF'
ROBINHOOD_MAINNET=https://rpc.invalid
EOF

FORGE_CALL_LOG="$TEMP_DIR/forge.log" \
PATH="$TEMP_DIR/bin:$PATH" \
  "$REPO_ROOT/scripts/test-release.sh" --rpc-file "$TEMP_DIR/rpc" \
  >"$TEMP_DIR/gate.out"

grep -q '^conditional-tokens|false|build$' "$TEMP_DIR/forge.log"
grep -Fq '|false|test --threads 1 --fuzz-seed 0x7a2db6638f489e8166edbcf53e04a6643f49f0dd095981233869c9c24e478ee6 --match-path test/unit/*.t.sol' \
  "$TEMP_DIR/forge.log"
grep -q '^security|false|test .*test/properties/MLOSeniorCapitalInvariants.t.sol' "$TEMP_DIR/forge.log"
grep -q '^default|true|test .*test/fork/RobinhoodStaticsDollarLifecycle.t.sol' "$TEMP_DIR/forge.log"
grep -q "Eve release gates passed." "$TEMP_DIR/gate.out"

mkdir -p "$TEMP_DIR/empty-bin"
cp "$TEMP_DIR/bin/forge" "$TEMP_DIR/empty-bin/forge"
cat >"$TEMP_DIR/empty-bin/grep" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-Rsl" ]]; then
  exit 1
fi
command -p grep "$@"
EOF
chmod +x "$TEMP_DIR/empty-bin/grep"

if FORGE_CALL_LOG="$TEMP_DIR/empty-forge.log" \
  PATH="$TEMP_DIR/empty-bin:$PATH" \
  "$REPO_ROOT/scripts/test-release.sh" --rpc-file "$TEMP_DIR/rpc" \
  >"$TEMP_DIR/empty.out" 2>&1; then
  echo "release gate accepted an empty invariant set" >&2
  exit 1
fi
grep -q "No invariant test files were discovered" "$TEMP_DIR/empty.out"

echo "Release gate tooling tests passed."
