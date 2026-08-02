#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--rpc-file FILE]"
  echo "  --rpc-file FILE  Key/value RPC file containing ROBINHOOD_MAINNET"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/../../.." && pwd)"
RPC_FILE="$WORKSPACE_ROOT/.rpc"
FUZZ_SEED="0x7a2db6638f489e8166edbcf53e04a6643f49f0dd095981233869c9c24e478ee6"

while (($#)); do
  case "$1" in
    --rpc-file)
      shift
      RPC_FILE="${1:?missing --rpc-file value}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

if [[ -z "${ROBINHOOD_RPC_URL:-}" && -z "${ROBINHOOD_MAINNET:-}" ]]; then
  if [[ ! -f "$RPC_FILE" ]]; then
    echo "Missing RPC file: $RPC_FILE" >&2
    exit 1
  fi
  ROBINHOOD_MAINNET="$(
    awk -F= '$1 == "ROBINHOOD_MAINNET" {sub(/^[^=]*=/, ""); print; exit}' "$RPC_FILE"
  )"
  export ROBINHOOD_MAINNET
fi

if [[ -z "${ROBINHOOD_RPC_URL:-${ROBINHOOD_MAINNET:-}}" ]]; then
  echo "ROBINHOOD_MAINNET RPC is not configured" >&2
  exit 1
fi

export FOUNDRY_OUT="$REPO_ROOT/out-release"
export FOUNDRY_CACHE_PATH="$REPO_ROOT/cache-release"

cd "$REPO_ROOT"

echo "Checking Solidity formatting"
forge fmt --check

echo "Building canonical ConditionalTokens fixture"
FOUNDRY_OUT="$REPO_ROOT/out/conditional-tokens" \
FOUNDRY_CACHE_PATH="$REPO_ROOT/cache/conditional-tokens" \
FOUNDRY_PROFILE=conditional-tokens \
  forge build

echo "Testing Robinhood deployment tools"
bash test/scripts/robinhood-release-tools.sh

TEST_SHARDS=(
  'test/audit/*.t.sol'
  'test/properties/*.t.sol'
  'test/unit/*.t.sol'
)

for test_shard in "${TEST_SHARDS[@]}"; do
  echo "Testing $test_shard"
  forge test \
    --threads 1 \
    --fuzz-seed "$FUZZ_SEED" \
    --match-path "$test_shard"
done

mapfile -t INVARIANT_FILES < <(
  rg -l 'function invariant_' test/unit test/properties | LC_ALL=C sort
)

for invariant_file in "${INVARIANT_FILES[@]}"; do
  echo "Security profile: $invariant_file"
  FOUNDRY_PROFILE=security forge test \
    --threads 1 \
    --fuzz-seed "$FUZZ_SEED" \
    --match-path "$invariant_file"
done

echo "Testing pinned Robinhood Statics Dollar lifecycle"
REQUIRE_ROBINHOOD_FORK=true forge test \
  --threads 1 \
  --fuzz-seed "$FUZZ_SEED" \
  --match-path test/fork/RobinhoodStaticsDollarLifecycle.t.sol

echo "Eve release gates passed."
