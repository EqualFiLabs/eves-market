#!/usr/bin/env bash
set -euo pipefail

if (($# < 1 || $# > 3)); then
  echo "Usage: $0 MANIFEST [BLOCKSCOUT_API_URL] [BROADCAST_ARTIFACT]" >&2
  exit 2
fi

MANIFEST="$1"
API_URL="${2:-https://explorer.testnet.chain.robinhood.com/api/}"
BROADCAST_ARTIFACT="${3:-}"
ATTEMPTS="${BLOCKSCOUT_VERIFY_ATTEMPTS:-20}"
DELAY_SECONDS="${BLOCKSCOUT_VERIFY_DELAY_SECONDS:-5}"

if [[ ! -f "$MANIFEST" ]]; then
  echo "Missing release manifest: $MANIFEST" >&2
  exit 1
fi

mapfile -t CONTRACTS < <(
  jq -r '
    .criticalContractNames as $names
    | .criticalContractAddresses as $addresses
    | range(0; $addresses | length)
    | [$names[.], $addresses[.]]
    | @tsv
  ' "$MANIFEST"
  jq -r '
    .facetAddresses
    | to_entries[]
    | ["Facet[" + (.key | tostring) + "]", .value]
    | @tsv
  ' "$MANIFEST"
)

if [[ -n "$BROADCAST_ARTIFACT" && -f "$BROADCAST_ARTIFACT" ]]; then
  mapfile -t CREATED_CONTRACTS < <(
    jq -r '
      .transactions[]
      | select(.transactionType == "CREATE" or .transactionType == "CREATE2")
      | [(.contractName // "CreatedContract"), .contractAddress]
      | @tsv
    ' "$BROADCAST_ARTIFACT"
  )
  CONTRACTS+=("${CREATED_CONTRACTS[@]}")
fi

declare -A SEEN_ADDRESSES=()
UNIQUE_CONTRACTS=()
for contract in "${CONTRACTS[@]}"; do
  address="${contract#*$'\t'}"
  address="${address,,}"
  if [[ -z "${SEEN_ADDRESSES[$address]:-}" ]]; then
    SEEN_ADDRESSES["$address"]=1
    UNIQUE_CONTRACTS+=("$contract")
  fi
done
CONTRACTS=("${UNIQUE_CONTRACTS[@]}")

for ((attempt = 1; attempt <= ATTEMPTS; ++attempt)); do
  missing=()
  for contract in "${CONTRACTS[@]}"; do
    IFS=$'\t' read -r label address <<<"$contract"
    response="$(
      curl -fsS --get "$API_URL" \
        --data-urlencode "module=contract" \
        --data-urlencode "action=getsourcecode" \
        --data-urlencode "address=$address"
    )"
    source_code="$(jq -r '.result[0].SourceCode // ""' <<<"$response")"
    if [[ -z "$source_code" ]]; then
      missing+=("$label:$address")
    fi
  done

  if ((${#missing[@]} == 0)); then
    echo "Blockscout source verification confirmed for ${#CONTRACTS[@]} contracts."
    exit 0
  fi

  if ((attempt < ATTEMPTS)); then
    echo "Verification pending for ${#missing[@]} contracts (attempt $attempt/$ATTEMPTS)."
    sleep "$DELAY_SECONDS"
  fi
done

printf 'Blockscout verification missing: %s\n' "${missing[@]}" >&2
exit 1
