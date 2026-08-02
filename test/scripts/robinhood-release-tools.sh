#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT

"$REPO_ROOT/scripts/robinhood-testnet-release.sh" --help >/dev/null

verification_calls="$(
  grep -c 'forge script script/VerifyRobinhoodRelease.s.sol:VerifyRobinhoodRelease' \
    "$REPO_ROOT/scripts/robinhood-testnet-release.sh"
)"
if [[ "$verification_calls" != "2" ]]; then
  echo "release wrapper has an unexpected live-verification call count" >&2
  exit 1
fi

if "$REPO_ROOT/scripts/robinhood-testnet-release.sh" --env "$TEMP_DIR/missing.env" \
  >"$TEMP_DIR/missing.out" 2>&1; then
  echo "release wrapper accepted a missing environment" >&2
  exit 1
fi
grep -q "Missing deployment environment" "$TEMP_DIR/missing.out"

mkdir -p "$TEMP_DIR/bin"
cat >"$TEMP_DIR/bin/curl" <<'EOF'
#!/usr/bin/env bash
echo '{"status":"1","message":"OK","result":[{"SourceCode":"verified source"}]}'
EOF
chmod +x "$TEMP_DIR/bin/curl"

cat >"$TEMP_DIR/manifest.json" <<'EOF'
{
  "criticalContractNames": ["EveMarketDiamond"],
  "criticalContractAddresses": ["0x0000000000000000000000000000000000000001"],
  "facetAddresses": ["0x0000000000000000000000000000000000000002"]
}
EOF

cat >"$TEMP_DIR/broadcast.json" <<'EOF'
{
  "transactions": [
    {
      "transactionType": "CREATE",
      "contractName": "EveMarketDiamond",
      "contractAddress": "0x0000000000000000000000000000000000000001"
    },
    {
      "transactionType": "CREATE2",
      "contractName": "LinkedLibrary",
      "contractAddress": "0x0000000000000000000000000000000000000003"
    }
  ]
}
EOF

PATH="$TEMP_DIR/bin:$PATH" BLOCKSCOUT_VERIFY_ATTEMPTS=1 \
  "$REPO_ROOT/scripts/check-blockscout-verification.sh" "$TEMP_DIR/manifest.json" \
  "https://blockscout.invalid/api/" "$TEMP_DIR/broadcast.json" >"$TEMP_DIR/verification.out"
grep -q "confirmed for 3 contracts" "$TEMP_DIR/verification.out"

PATH="$TEMP_DIR/bin:$PATH" BLOCKSCOUT_VERIFY_ATTEMPTS=1 \
  "$REPO_ROOT/scripts/robinhood-testnet-release.sh" --check-verification \
  --manifest "$TEMP_DIR/manifest.json" >"$TEMP_DIR/wrapper-verification.out"
grep -q "confirmed for 2 contracts" "$TEMP_DIR/wrapper-verification.out"

echo "Robinhood release tooling tests passed."
