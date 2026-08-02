#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 --rpc-url URL [--address ADDRESS] [--broadcast] [--verify] [options]"
  echo "  --address ADDRESS       Reuse and validate an existing deployment"
  echo "  --broadcast             Deploy when no existing address is supplied"
  echo "  --private-key KEY       Deployment key; defaults to PRIVATE_KEY"
  echo "  --verify                Request source verification for a new deployment"
  echo "  --verifier-url URL      Blockscout-compatible verifier endpoint"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="${CONDITIONAL_TOKENS_OUT_DIR:-$REPO_ROOT/out/conditional-tokens}"
CACHE_DIR="${CONDITIONAL_TOKENS_CACHE_DIR:-$REPO_ROOT/cache/conditional-tokens}"
ARTIFACT_PATH="$OUT_DIR/ConditionalTokens.sol/ConditionalTokens.json"
CONTRACT_TARGET="conditional-tokens/contracts/ConditionalTokens.sol:ConditionalTokens"

RPC_URL=""
EXISTING_ADDRESS="${CONDITIONAL_TOKENS:-}"
DEPLOYMENT_KEY="${PRIVATE_KEY:-}"
VERIFIER_URL="${ROBINHOOD_TESTNET_VERIFIER_URL:-}"
BROADCAST=false
VERIFY=false

while (($#)); do
  case "$1" in
    --rpc-url)
      shift
      RPC_URL="${1:?missing --rpc-url value}"
      ;;
    --address)
      shift
      EXISTING_ADDRESS="${1:?missing --address value}"
      ;;
    --private-key)
      shift
      DEPLOYMENT_KEY="${1:?missing --private-key value}"
      ;;
    --broadcast) BROADCAST=true ;;
    --verify) VERIFY=true ;;
    --verifier-url)
      shift
      VERIFIER_URL="${1:?missing --verifier-url value}"
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

if [[ -z "$RPC_URL" ]]; then
  echo "Missing required --rpc-url" >&2
  exit 1
fi
if [[ "$VERIFY" == true && -z "$VERIFIER_URL" ]]; then
  echo "Missing verifier URL for --verify" >&2
  exit 1
fi

cd "$REPO_ROOT"

git submodule update --init conditional-tokens lib/openzeppelin-solidity >&2

echo "Building ConditionalTokens with the pinned Solidity 0.5.17 profile" >&2
FOUNDRY_OUT="$OUT_DIR" \
FOUNDRY_CACHE_PATH="$CACHE_DIR" \
FOUNDRY_PROFILE=conditional-tokens \
  forge build >&2

if [[ ! -s "$ARTIFACT_PATH" ]]; then
  echo "ConditionalTokens artifact was not generated: $ARTIFACT_PATH" >&2
  exit 1
fi

validate_deployment() {
  local address="$1"
  local expected_runtime
  local runtime_code

  if [[ ! "$address" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Invalid ConditionalTokens address: $address" >&2
    exit 1
  fi
  runtime_code="$(cast code "$address" --rpc-url "$RPC_URL")"
  if [[ -z "$runtime_code" || "$runtime_code" == "0x" ]]; then
    echo "No ConditionalTokens runtime code at $address" >&2
    exit 1
  fi
  expected_runtime="$(jq -r '.deployedBytecode.object // empty' "$ARTIFACT_PATH")"
  if [[ -z "$expected_runtime" ]]; then
    echo "ConditionalTokens artifact does not contain deployed bytecode" >&2
    exit 1
  fi
  if [[ "$expected_runtime" != 0x* ]]; then
    expected_runtime="0x$expected_runtime"
  fi
  if [[ "${runtime_code,,}" != "${expected_runtime,,}" ]]; then
    echo "ConditionalTokens runtime code does not match the pinned artifact at $address" >&2
    exit 1
  fi
}

if [[ -n "$EXISTING_ADDRESS" ]]; then
  validate_deployment "$EXISTING_ADDRESS"
  printf '%s\n' "$EXISTING_ADDRESS"
  exit 0
fi

if [[ "$BROADCAST" != true ]]; then
  echo "CONDITIONAL_TOKENS is unset; use --broadcast to create it or supply --address" >&2
  exit 1
fi

DEPLOYMENT_KEY="${DEPLOYMENT_KEY//[[:space:]\"\']/}"
DEPLOYMENT_KEY="${DEPLOYMENT_KEY#0x}"
if [[ ! "$DEPLOYMENT_KEY" =~ ^[0-9a-fA-F]{64}$ ]]; then
  echo "A 32-byte private key is required to deploy ConditionalTokens" >&2
  exit 1
fi

create_args=(
  "$CONTRACT_TARGET"
  --rpc-url "$RPC_URL"
  --chain-id "$(cast chain-id --rpc-url "$RPC_URL")"
  --private-key "0x$DEPLOYMENT_KEY"
  --broadcast
  --json
)
if [[ "$VERIFY" == true ]]; then
  create_args+=(
    --verify
    --verifier blockscout
    --verifier-url "$VERIFIER_URL"
  )
fi

echo "Deploying ConditionalTokens from the pinned Solidity 0.5.17 artifact" >&2
create_output="$(
  BASESCAN_API_KEY="${BASESCAN_API_KEY:-unused}" \
  FOUNDRY_OUT="$OUT_DIR" \
  FOUNDRY_CACHE_PATH="$CACHE_DIR" \
  FOUNDRY_PROFILE=conditional-tokens \
    forge create "${create_args[@]}"
)"
deployed_address="$(jq -r '.deployedTo // empty' <<<"$create_output")"
if [[ -z "$deployed_address" ]]; then
  echo "Unable to read the ConditionalTokens deployment address" >&2
  exit 1
fi

validate_deployment "$deployed_address"
printf '%s\n' "$deployed_address"
