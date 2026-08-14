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
  ROBINHOOD_BROADCAST_RECEIPT_PATH="$TEMP_DIR/missing-broadcast.json" \
  "$REPO_ROOT/scripts/robinhood-testnet-release.sh" --check-verification \
  --manifest "$TEMP_DIR/manifest.json" >"$TEMP_DIR/wrapper-verification.out"
grep -q "confirmed for 2 contracts" "$TEMP_DIR/wrapper-verification.out"

cat >"$TEMP_DIR/bin/forge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "${FOUNDRY_PROFILE:-}|${FOUNDRY_OUT:-}|$*" >>"$TOOL_LOG"
if [[ "${1:-}" == "build" ]]; then
  if [[ "${FOUNDRY_PROFILE:-}" == "conditional-tokens" ]]; then
    mkdir -p "$FOUNDRY_OUT/ConditionalTokens.sol"
    echo '{"bytecode":{"object":"0x6000"},"deployedBytecode":{"object":"0x6000"}}' >"$FOUNDRY_OUT/ConditionalTokens.sol/ConditionalTokens.json"
  fi
  exit 0
fi
if [[ "${1:-}" == "create" ]]; then
  echo '{"deployer":"0x0000000000000000000000000000000000000001","deployedTo":"0x0000000000000000000000000000000000000002","transactionHash":"0x01"}'
  exit 0
fi
if [[ "${1:-}" == "script" ]]; then
  exit 0
fi
echo "unexpected forge command" >&2
exit 1
EOF
chmod +x "$TEMP_DIR/bin/forge"

cat >"$TEMP_DIR/bin/cast" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "code" ]]; then
  echo "${MOCK_RUNTIME_CODE:-0x6000}"
  exit 0
fi
if [[ "${1:-}" == "chain-id" ]]; then
  echo "46630"
  exit 0
fi
echo "unexpected cast command" >&2
exit 1
EOF
chmod +x "$TEMP_DIR/bin/cast"

export TOOL_LOG="$TEMP_DIR/tool.log"
existing_address="0x0000000000000000000000000000000000000001"
reused_address="$(
  CONDITIONAL_TOKENS_OUT_DIR="$TEMP_DIR/out" \
  CONDITIONAL_TOKENS_CACHE_DIR="$TEMP_DIR/cache" \
  PATH="$TEMP_DIR/bin:$PATH" "$REPO_ROOT/scripts/prepare-conditional-tokens.sh" \
    --rpc-url "http://rpc.invalid" \
    --address "$existing_address"
)"
[[ "$reused_address" == "$existing_address" ]]
grep -Fq "conditional-tokens|$TEMP_DIR/out|build" "$TOOL_LOG"
if grep -q '|create ' "$TOOL_LOG"; then
  echo "existing ConditionalTokens address triggered a deployment" >&2
  exit 1
fi

if CONDITIONAL_TOKENS_OUT_DIR="$TEMP_DIR/out" \
  CONDITIONAL_TOKENS_CACHE_DIR="$TEMP_DIR/cache" \
  PATH="$TEMP_DIR/bin:$PATH" "$REPO_ROOT/scripts/prepare-conditional-tokens.sh" \
  --rpc-url "http://rpc.invalid" >"$TEMP_DIR/unset.out" 2>&1; then
  echo "ConditionalTokens helper deployed without explicit broadcast" >&2
  exit 1
fi
grep -q "use --broadcast to create it" "$TEMP_DIR/unset.out"

: >"$TOOL_LOG"
deployed_address="$(
  CONDITIONAL_TOKENS_OUT_DIR="$TEMP_DIR/out" \
  CONDITIONAL_TOKENS_CACHE_DIR="$TEMP_DIR/cache" \
  PATH="$TEMP_DIR/bin:$PATH" "$REPO_ROOT/scripts/prepare-conditional-tokens.sh" \
    --rpc-url "http://rpc.invalid" \
    --private-key "0x$(printf '11%.0s' {1..32})" \
    --broadcast \
    --verify \
    --verifier-url "https://verifier.invalid/api/"
)"
[[ "$deployed_address" == "0x0000000000000000000000000000000000000002" ]]
grep -Fq "conditional-tokens|$TEMP_DIR/out|build" "$TOOL_LOG"
grep -q '|create conditional-tokens/contracts/ConditionalTokens.sol:ConditionalTokens .* --chain-id 46630 .* --broadcast --json --verify' \
  "$TOOL_LOG"
grep -q -- '--verify --verifier blockscout --verifier-url https://verifier.invalid/api/' "$TOOL_LOG"

if MOCK_RUNTIME_CODE=0x \
  CONDITIONAL_TOKENS_OUT_DIR="$TEMP_DIR/out" \
  CONDITIONAL_TOKENS_CACHE_DIR="$TEMP_DIR/cache" \
  PATH="$TEMP_DIR/bin:$PATH" \
  "$REPO_ROOT/scripts/prepare-conditional-tokens.sh" \
  --rpc-url "http://rpc.invalid" \
  --address "$existing_address" >"$TEMP_DIR/no-code.out" 2>&1; then
  echo "ConditionalTokens helper accepted an address without runtime code" >&2
  exit 1
fi
grep -q "No ConditionalTokens runtime code" "$TEMP_DIR/no-code.out"

cat >"$TEMP_DIR/release.env" <<EOF
ROBINHOOD_TESTNET_RPC_URL=http://rpc.invalid
ROBINHOOD_TESTNET_VERIFIER_URL=https://verifier.invalid/api/
PRIVATE_KEY=0x$(printf '11%.0s' {1..32})
CONDITIONAL_TOKENS=
USDC_TOKEN=0x0000000000000000000000000000000000000003
INITIAL_OWNER=0x0000000000000000000000000000000000000004
EVE_TREASURY=0x0000000000000000000000000000000000000005
STATICS_DOLLAR_CORE_ADDRESS=0x0000000000000000000000000000000000000006
STATICS_DOLLAR_USDC_PROFILE_ID=1
EOF

: >"$TOOL_LOG"
CONDITIONAL_TOKENS_OUT_DIR="$TEMP_DIR/out" \
CONDITIONAL_TOKENS_CACHE_DIR="$TEMP_DIR/cache" \
CONDITIONAL_TOKENS_STATE_FILE="$TEMP_DIR/conditional-tokens.env" \
ROBINHOOD_BROADCAST_RECEIPT_PATH="$TEMP_DIR/broadcast.json" \
PATH="$TEMP_DIR/bin:$PATH" BLOCKSCOUT_VERIFY_ATTEMPTS=1 \
  "$REPO_ROOT/scripts/robinhood-testnet-release.sh" \
  --broadcast \
  --env "$TEMP_DIR/release.env" \
  --manifest "$TEMP_DIR/manifest.json" >"$TEMP_DIR/release.out" 2>&1

grep -q '^CONDITIONAL_TOKENS=0x0000000000000000000000000000000000000002$' \
  "$TEMP_DIR/conditional-tokens.env"
conditional_create_line="$(grep -n '|create conditional-tokens/contracts/ConditionalTokens.sol:ConditionalTokens ' "$TOOL_LOG" | cut -d: -f1)"
release_build_line="$(grep -n '|build --force script/Deploy.s.sol script/RobinhoodPreflight.s.sol script/VerifyRobinhoodRelease.s.sol script/ActivateSeniorCapital.s.sol$' "$TOOL_LOG" | cut -d: -f1)"
eves_deploy_line="$(grep -n '|script script/Deploy.s.sol:DeployScript ' "$TOOL_LOG" | cut -d: -f1)"
if [[ -z "$conditional_create_line" || -z "$release_build_line" || -z "$eves_deploy_line" \
  || "$release_build_line" -ge "$conditional_create_line" \
  || "$conditional_create_line" -ge "$eves_deploy_line" ]]; then
  echo "release wrapper did not rebuild source before preparing ConditionalTokens and deploying Eves" >&2
  exit 1
fi

echo "Robinhood release tooling tests passed."
