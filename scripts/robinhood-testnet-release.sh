#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 [--broadcast|--verify-only|--activate-senior|--check-verification] [options]"
  echo "  --env FILE       Private deployment environment file"
  echo "  --manifest FILE  Release manifest path"
  echo "  --rpc-file FILE  Key/value RPC file containing ROBINHOOD_TESTNET"
  echo "  --key-file FILE  Key/value file containing PRIVATE_KEY"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WORKSPACE_ROOT="$(cd "$REPO_ROOT/../../.." && pwd)"

MODE="dry-run"
ENV_FILE="$REPO_ROOT/.env.robinhood-testnet"
RPC_FILE="$WORKSPACE_ROOT/.rpc"
KEY_FILE="$WORKSPACE_ROOT/.rhdeploy"
MANIFEST_PATH=""

while (($#)); do
  case "$1" in
    --broadcast) MODE="broadcast" ;;
    --verify-only) MODE="verify-only" ;;
    --activate-senior) MODE="activate-senior" ;;
    --check-verification) MODE="check-verification" ;;
    --env)
      shift
      ENV_FILE="${1:?missing --env value}"
      ;;
    --manifest)
      shift
      MANIFEST_PATH="${1:?missing --manifest value}"
      ;;
    --rpc-file)
      shift
      RPC_FILE="${1:?missing --rpc-file value}"
      ;;
    --key-file)
      shift
      KEY_FILE="${1:?missing --key-file value}"
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

if [[ -z "$MANIFEST_PATH" ]]; then
  if [[ "$MODE" == "dry-run" ]]; then
    MANIFEST_PATH="cache/robinhood-testnet-dry-run.json"
  else
    MANIFEST_PATH="deployments/robinhood-testnet-46630.json"
  fi
fi

if [[ "$MODE" == "check-verification" ]]; then
  cd "$REPO_ROOT"
  "$SCRIPT_DIR/check-blockscout-verification.sh" \
    "$MANIFEST_PATH" \
    "${ROBINHOOD_TESTNET_VERIFIER_URL:-https://explorer.testnet.chain.robinhood.com/api/}" \
    "broadcast/Deploy.s.sol/46630/run-latest.json"
  exit 0
fi

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a
elif [[ "$MODE" == "dry-run" || "$MODE" == "broadcast" ]]; then
  echo "Missing deployment environment: $ENV_FILE" >&2
  echo "Copy .env.example to .env.robinhood-testnet and fill the deployed dependency addresses." >&2
  exit 1
fi

if [[ -z "${ROBINHOOD_TESTNET_RPC_URL:-}" ]]; then
  if [[ ! -f "$RPC_FILE" ]]; then
    echo "Missing RPC file: $RPC_FILE" >&2
    exit 1
  fi
  ROBINHOOD_TESTNET_RPC_URL="$(
    awk -F= '$1 == "ROBINHOOD_TESTNET" {sub(/^[^=]*=/, ""); print; exit}' "$RPC_FILE"
  )"
fi
if [[ -z "$ROBINHOOD_TESTNET_RPC_URL" ]]; then
  echo "ROBINHOOD_TESTNET RPC is not configured" >&2
  exit 1
fi

if [[ "$MODE" != "verify-only" ]]; then
  if [[ -z "${PRIVATE_KEY:-}" ]]; then
    if [[ ! -f "$KEY_FILE" ]]; then
      echo "Missing deployer key file: $KEY_FILE" >&2
      exit 1
    fi
    PRIVATE_KEY="$(awk -F= '$1 == "PRIVATE_KEY" {sub(/^[^=]*=/, ""); print; exit}' "$KEY_FILE")"
  fi
  PRIVATE_KEY="${PRIVATE_KEY//[[:space:]\"\']/}"
  PRIVATE_KEY="${PRIVATE_KEY#0x}"
  if [[ ! "$PRIVATE_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
    echo "PRIVATE_KEY must contain exactly 32 bytes of hex" >&2
    exit 1
  fi
  export PRIVATE_KEY="0x$PRIVATE_KEY"
fi
export ROBINHOOD_TESTNET_RPC_URL

if [[ "$MODE" == "dry-run" || "$MODE" == "broadcast" ]]; then
  for required in CONDITIONAL_TOKENS USDC_TOKEN INITIAL_OWNER EVE_TREASURY \
    STATICS_DOLLAR_CORE_ADDRESS STATICS_DOLLAR_USDC_PROFILE_ID; do
    if [[ -z "${!required:-}" ]]; then
      echo "Missing required deployment variable: $required" >&2
      exit 1
    fi
  done
fi

actual_chain_id="$(cast chain-id --rpc-url "$ROBINHOOD_TESTNET_RPC_URL")"
if [[ "$actual_chain_id" != "46630" ]]; then
  echo "RPC chain mismatch: expected 46630, received $actual_chain_id" >&2
  exit 1
fi

if [[ "$MODE" == "dry-run" || "$MODE" == "broadcast" ]]; then
  export RELEASE_COMMIT
  RELEASE_COMMIT="$(git -C "$REPO_ROOT" rev-parse HEAD)"
  export STATICS_RELEASE_COMMIT
  STATICS_RELEASE_COMMIT="$(git -C "$REPO_ROOT/lib/statics" rev-parse HEAD)"
fi
export DEPLOYMENT_MANIFEST_PATH="$MANIFEST_PATH"

cd "$REPO_ROOT"

case "$MODE" in
  verify-only)
    forge script script/VerifyRobinhoodRelease.s.sol:VerifyRobinhoodRelease \
      --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
      --chain-id 46630 \
      -vv
    ;;
  activate-senior)
    if [[ -z "${EVE_DIAMOND:-}" ]]; then
      EVE_DIAMOND="$(
        jq -r '
          .criticalContractNames as $names
          | .criticalContractAddresses as $addresses
          | ($names | index("EveMarketDiamond")) as $index
          | $addresses[$index]
        ' "$MANIFEST_PATH"
      )"
      export EVE_DIAMOND
    fi
    forge script script/ActivateSeniorCapital.s.sol:ActivateSeniorCapital \
      --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
      --chain-id 46630 \
      --broadcast \
      -vv
    ;;
  dry-run|broadcast)
    forge script script/RobinhoodPreflight.s.sol:RobinhoodPreflight \
      --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
      --chain-id 46630 \
      -vv

    if [[ "$MODE" == "dry-run" ]]; then
      forge script script/Deploy.s.sol:DeployScript \
        --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
        --chain-id 46630 \
        -vv
      echo "Simulation passed. No transaction was broadcast."
    else
      mkdir -p "$(dirname "$MANIFEST_PATH")"
      BASESCAN_API_KEY="${BASESCAN_API_KEY:-unused}" \
      forge script script/Deploy.s.sol:DeployScript \
        --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
        --chain-id 46630 \
        --broadcast \
        --verify \
        --verifier blockscout \
        --verifier-url "${ROBINHOOD_TESTNET_VERIFIER_URL:-https://explorer.testnet.chain.robinhood.com/api/}" \
        --retries 20 \
        --delay 5 \
        -vv
      forge script script/VerifyRobinhoodRelease.s.sol:VerifyRobinhoodRelease \
        --rpc-url "$ROBINHOOD_TESTNET_RPC_URL" \
        --chain-id 46630 \
        -vv
      "$SCRIPT_DIR/check-blockscout-verification.sh" \
        "$MANIFEST_PATH" \
        "${ROBINHOOD_TESTNET_VERIFIER_URL:-https://explorer.testnet.chain.robinhood.com/api/}" \
        "broadcast/Deploy.s.sol/46630/run-latest.json"
    fi
    ;;
esac
