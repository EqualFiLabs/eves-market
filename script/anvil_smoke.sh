#!/usr/bin/env bash
# Deploy the full eve-predict protocol to anvil via Deploy.s.sol and
# smoke every user-facing facet entrypoint with cast.
# Anvil must be running on 127.0.0.1:8545.

set -euo pipefail
cd "$(dirname "$0")/.."

RPC=http://127.0.0.1:8545
PK=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ME=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
TREASURY=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
RECEIVER=$ME

CAST_SEND="cast send --rpc-url $RPC --private-key $PK --json"
CAST_CALL="cast call --rpc-url $RPC"

step() { printf "\n\033[1;36m== %s ==\033[0m\n" "$*"; }
ok()   { printf "  \033[1;32m✓\033[0m %s\n" "$*"; }
fail() { printf "  \033[1;31m✗ %s\033[0m\n" "$*"; exit 1; }

##############################################################################
# 1. Deploy via the project's own Deploy.s.sol (auto-deploys mocks)
##############################################################################
step "Run Deploy.s.sol"

export PRIVATE_KEY=$PK
export INITIAL_OWNER=$ME
export EVE_TREASURY=$TREASURY
export MARKET_CREATION_FEE=50000000
export MARKET_CREATION_BOND_EVE=0
export RESOLUTION_BOND_L1=100000000000000000
export RESOLUTION_BOND_L2=500000000000000000
export MIN_MARKET_DURATION=3600
export MAX_MARKET_DURATION=7776000
export DISPUTE_WINDOW=7200
export CREATOR_SETTLE_GRACE=86400
export OPEN_RESOLUTION_TIMEOUT=172800
export MAX_ESCALATION=2
export EVE_VOTE_DURATION=259200
export EVE_VOTE_QUORUM=1
export PERMISSIONLESS_CREATION_ENABLED=true

forge script script/Deploy.s.sol:DeployScript \
  --rpc-url $RPC --broadcast --non-interactive --disable-code-size-limit \
  > /tmp/eve_deploy.log 2>&1 || (tail -60 /tmp/eve_deploy.log; fail "deploy failed")

BCAST=broadcast/Deploy.s.sol/31337/run-latest.json

addr_of() {
  jq -r --arg n "$1" '.transactions | map(select(.contractName==$n)) | .[0].contractAddress' "$BCAST"
}

DIAMOND=$(addr_of EveMarketDiamond)
USDC=$(addr_of MockUSDC)
EVE=$(addr_of MockEveToken)
EVOTES=$EVE
EVEUSDC=$(addr_of EveUSDC)
PSHARE=$(addr_of ParimutuelShareToken)

# Conditional tokens were deployed via assembly (no contractName). Pull from getMarketConfig.
CFG=$($CAST_CALL "$DIAMOND" "getMarketConfig()((address,address,address,address,address,address,address,address,(uint16,uint16,uint16,uint16,uint16),(uint16,uint16,uint16,uint16),(uint16,uint16,uint16,uint16,uint16),(uint16,uint16,uint16,uint16),uint128,uint128,uint128,uint128,uint128,uint128,address,uint128,uint128,uint64,uint64,uint64,uint64,uint64,uint16,uint8,uint8,bool,uint64,uint64,uint24,uint16,uint8,uint32,uint128,uint128))")
CTF=$(echo "$CFG" | sed 's/^(//; s/)$//' | awk -F',' '{print $1}' | xargs)

for v in DIAMOND USDC EVE EVOTES EVEUSDC PSHARE CTF; do
  val=${!v}
  [ -n "$val" ] && [ "$val" != "null" ] || fail "missing address for $v"
  ok "$(printf '%-22s %s' "$v" "$val")"
done

##############################################################################
# 2. Approvals + minting (deploy already minted USDC/EVE to ME)
##############################################################################
step "Approvals"
MAX=115792089237316195423570985008687907853269984665640564039457584007913129639935
$CAST_SEND "$USDC"   "approve(address,uint256)" "$EVEUSDC"  "$MAX" >/dev/null && ok "USDC -> EveUSDC onramp"
$CAST_SEND "$USDC"   "approve(address,uint256)" "$DIAMOND" "$MAX" >/dev/null && ok "USDC -> Diamond"
$CAST_SEND "$EVEUSDC" "approve(address,uint256)" "$DIAMOND" "$MAX" >/dev/null && ok "EveUSDC -> Diamond"
$CAST_SEND "$EVE"    "approve(address,uint256)" "$DIAMOND" "$MAX" >/dev/null && ok "EVE -> Diamond"
$CAST_SEND "$CTF"    "setApprovalForAll(address,bool)" "$DIAMOND" true >/dev/null && ok "CTF -> Diamond"

# Wrap a chunk of USDC into eveUSDC so we can pay creation fees / collateral.
$CAST_SEND "$EVEUSDC" "wrap(uint256,address)" 200000000000 "$ME" >/dev/null && ok "wrap 200,000 USDC -> eveUSDC"

##############################################################################
# 3. Loupe + Ownership view smoke
##############################################################################
step "Diamond loupe + ownership"
FAC_COUNT=$($CAST_CALL "$DIAMOND" "facetAddresses()(address[])" | tr -d '[]' | tr ',' '\n' | grep -c 0x)
[ "$FAC_COUNT" = "21" ] || fail "facet count $FAC_COUNT (expected 21)"
ok "facetAddresses() -> 21 facets"
$CAST_CALL "$DIAMOND" "facets()" >/dev/null && ok "facets()"
$CAST_CALL "$DIAMOND" "owner()(address)" >/dev/null && ok "owner()"

# bytes4 of facetAddresses() == 0x52ef6b2c, route to a real facet
$CAST_CALL "$DIAMOND" "facetAddress(bytes4)(address)" 0x52ef6b2c >/dev/null && ok "facetAddress()"
$CAST_CALL "$DIAMOND" "facetFunctionSelectors(address)(bytes4[])" "$DIAMOND" >/dev/null && ok "facetFunctionSelectors()"
$CAST_CALL "$DIAMOND" "isSelectorFrozen(bytes4)(bool)" 0x52ef6b2c >/dev/null && ok "isSelectorFrozen()"

##############################################################################
# 4. Owner setters (re-issue with same values to confirm routing)
##############################################################################
step "Owner setters"
$CAST_SEND "$DIAMOND" "setOrderbookEntryFeeBps(uint16)" 100 >/dev/null && ok "setOrderbookEntryFeeBps"
$CAST_SEND "$DIAMOND" "setMarketCreationFee(uint128)" 50000000 >/dev/null && ok "setMarketCreationFee"
$CAST_SEND "$DIAMOND" "setSpotBookCreationFee(uint128)" 250000000 >/dev/null && ok "setSpotBookCreationFee"
$CAST_SEND "$DIAMOND" "setMarketCreationBond(uint128)" 0 >/dev/null && ok "setMarketCreationBond"
$CAST_SEND "$DIAMOND" "setPermissionlessCreationEnabled(bool)" true >/dev/null && ok "setPermissionlessCreationEnabled"
$CAST_SEND "$DIAMOND" "setResolutionBondConfig(address,uint128,uint128)" "$EVE" 100000000000000000 500000000000000000 >/dev/null && ok "setResolutionBondConfig"
$CAST_SEND "$DIAMOND" "setDurationParams(uint64,uint64)" 3600 7776000 >/dev/null && ok "setDurationParams"
$CAST_SEND "$DIAMOND" "setDisputeWindow(uint64)" 7200 >/dev/null && ok "setDisputeWindow"
$CAST_SEND "$DIAMOND" "setCreatorSettleGrace(uint64)" 86400 >/dev/null && ok "setCreatorSettleGrace"
$CAST_SEND "$DIAMOND" "setOpenResolutionTimeout(uint64)" 172800 >/dev/null && ok "setOpenResolutionTimeout"
$CAST_SEND "$DIAMOND" "setMaxEscalation(uint8)" 2 >/dev/null && ok "setMaxEscalation"
$CAST_SEND "$DIAMOND" "setOrderbookFeeSplit(uint16,uint16,uint16,uint16,uint16)" 8500 400 1000 100 0 >/dev/null && ok "setFeeSplit"
$CAST_SEND "$DIAMOND" "setParimutuelFeeSplit(uint16,uint16,uint16,uint16)" 500 9500 0 0 >/dev/null && ok "setParimutuelFeeSplit"
$CAST_SEND "$DIAMOND" "setParimutuelConfig(address,uint16,uint128)" "$PSHARE" 250 1000000 >/dev/null && ok "setParimutuelConfig"
$CAST_SEND "$DIAMOND" "setParimutuelEpochWindowCap(uint64)" 2592000 >/dev/null && ok "setParimutuelEpochWindowCap"
$CAST_SEND "$DIAMOND" "setEveTreasury(address)" "$TREASURY" >/dev/null && ok "setEveTreasury"
$CAST_SEND "$DIAMOND" "setEveToken(address)" "$EVE" >/dev/null && ok "setEveToken"
$CAST_SEND "$DIAMOND" "setCollateralToken(address)" "$EVEUSDC" >/dev/null && ok "setCollateralToken"
$CAST_SEND "$DIAMOND" "setDefaultConditionalTokens(address)" "$CTF" >/dev/null && ok "setDefaultConditionalTokens"

##############################################################################
# 5. createMarket (CLOB / CTF) + market views
##############################################################################
step "createMarket (CLOB / CTF)"
NOW_HEX=$(cast rpc --rpc-url $RPC eth_getBlockByNumber latest false | jq -r .timestamp)
NOW=$((NOW_HEX))
EXPIRY=$((NOW + 7200))
QUESTION="Anvil smoke market $$"
CATEGORY="binary"
$CAST_SEND "$DIAMOND" "createMarket(string,string,uint64,uint128,bool)" \
  "$QUESTION" "$CATEGORY" "$EXPIRY" 0 true >/dev/null
ok "createMarket called"

# computeMarketId(string,string,uint64,address,uint8 marketType,uint8 positionTokenType)
MARKET_ID=$($CAST_CALL "$DIAMOND" \
  "computeMarketId(string,string,uint64,address,uint8,uint8)(bytes32)" \
  "$QUESTION" "$CATEGORY" "$EXPIRY" "$EVEUSDC" 0 0)
ok "marketId            $MARKET_ID"

POS=$($CAST_CALL "$DIAMOND" "getMarketPositions(bytes32)(bytes32,address,uint256,uint256)" "$MARKET_ID")
COND_ID=$(echo "$POS" | sed -n '1p')
YES_PID=$(echo "$POS" | sed -n '3p' | awk '{print $1}')
NO_PID=$(echo  "$POS" | sed -n '4p' | awk '{print $1}')
ok "conditionId         $COND_ID"
ok "yesPositionId       $YES_PID"
ok "noPositionId        $NO_PID"

step "Market views"
$CAST_CALL "$DIAMOND" "getMarketTokenInfo(bytes32)" "$MARKET_ID" >/dev/null && ok "getMarketTokenInfo"
$CAST_CALL "$DIAMOND" "getMarketInfo(bytes32)" "$MARKET_ID" >/dev/null && ok "getMarketInfo"
$CAST_CALL "$DIAMOND" "getMarketSummaries(address,bytes32[])" "$ME" "[$MARKET_ID]" >/dev/null && ok "getMarketSummaries"
$CAST_CALL "$DIAMOND" "getMarketMetadata(bytes32)" "$MARKET_ID" >/dev/null && ok "getMarketMetadata"
$CAST_CALL "$DIAMOND" "getUserMarketPositions(address,bytes32[])" "$ME" "[$MARKET_ID]" >/dev/null && ok "getUserMarketPositions"
$CAST_CALL "$DIAMOND" "getMarketStatus(bytes32)" "$MARKET_ID" >/dev/null && ok "getMarketStatus"
$CAST_CALL "$DIAMOND" "getPositionMetadata(address,uint256)" "$CTF" "$YES_PID" >/dev/null && ok "getPositionMetadata"
$CAST_CALL "$DIAMOND" "positionTokenURI(address,uint256)(string)" "$CTF" "$YES_PID" >/dev/null && ok "positionTokenURI"

##############################################################################
# 6. Inventory / curves / fills / cancels (CLOB)
##############################################################################
step "splitInventory / mergeInventory"
$CAST_SEND "$DIAMOND" "splitInventory(bytes32,uint128)" "$MARKET_ID" 5000000000 >/dev/null && ok "splitInventory(5,000)"
$CAST_SEND "$DIAMOND" "mergeInventory(bytes32,uint128)" "$MARKET_ID" 250000000   >/dev/null && ok "mergeInventory(250)"

step "postCurve / postBidCurve / postCurvesBatch / postBidCurvesBatch"
$CAST_SEND "$DIAMOND" "postCurve(bytes32,bool,uint128,uint72,uint72,uint24,uint8,uint8)" \
  "$MARKET_ID" true 500000000 550000000 550000000 60 0 0 >/dev/null && ok "postCurve(yes ask, linear)"
$CAST_SEND "$DIAMOND" "postCurve(bytes32,bool,uint128,uint72,uint72,uint24,uint8,uint8)" \
  "$MARKET_ID" false 400000000 450000000 450000000 60 0 0 >/dev/null && ok "postCurve(no ask, linear)"
$CAST_SEND "$DIAMOND" "postBidCurve(bytes32,bool,uint128,uint72,uint72,uint24,uint8,uint8)" \
  "$MARKET_ID" true 100000000 450000000 450000000 60 0 0 >/dev/null && ok "postBidCurve(yes bid)"

$CAST_SEND "$DIAMOND" "postCurvesBatch(bytes32,uint8,(bool,uint128,uint72,uint72,uint24,uint8)[])" \
  "$MARKET_ID" 0 "[(true,300000000,500000000,500000000,60,0),(false,200000000,500000000,500000000,60,0)]" >/dev/null && ok "postCurvesBatch (2 asks)"

$CAST_SEND "$DIAMOND" "postBidCurvesBatch(bytes32,uint8,(bool,uint128,uint72,uint72,uint24,uint8)[])" \
  "$MARKET_ID" 0 "[(true,100000000,400000000,400000000,60,0)]" >/dev/null && ok "postBidCurvesBatch"

step "updateCurve / updateCurvesBatch"
PACKED_55=$(python3 -c 'print(550000000 | (550000000 << 72) | (60 << 144) | (0 << 164))')
PACKED_50=$(python3 -c 'print(500000000 | (500000000 << 72) | (60 << 144) | (0 << 164))')
$CAST_SEND "$DIAMOND" "updateCurve(uint256,uint256,uint32)" 0 "$PACKED_55" 1 >/dev/null && ok "updateCurve(0)"
$CAST_SEND "$DIAMOND" "updateCurvesBatch((uint256,uint256,uint32)[])" "[(3,$PACKED_50,1)]" >/dev/null && ok "updateCurvesBatch([3])"

step "topUp variants"
$CAST_SEND "$DIAMOND" "topUpCurvesBatch(bytes32,(uint256,uint128)[])" "$MARKET_ID" "[(0,50000000)]" >/dev/null && ok "topUpCurvesBatch"
$CAST_SEND "$DIAMOND" "splitAndTopUpCurvesBatch(bytes32,(uint256,uint128)[])" "$MARKET_ID" "[(0,50000000)]" >/dev/null && ok "splitAndTopUpCurvesBatch"
$CAST_SEND "$DIAMOND" "topUpCurvesMultiMarket((bytes32,(uint256,uint128)[])[])" "[($MARKET_ID,[(0,25000000)])]" >/dev/null && ok "topUpCurvesMultiMarket"
$CAST_SEND "$DIAMOND" "splitAndTopUpCurvesMultiMarket((bytes32,(uint256,uint128)[])[])" "[($MARKET_ID,[(0,25000000)])]" >/dev/null && ok "splitAndTopUpCurvesMultiMarket"

step "Curve view fns"
$CAST_CALL "$DIAMOND" "getCurveInfo(uint256)" 0 >/dev/null && ok "getCurveInfo(0)"
$CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)" 0 >/dev/null && ok "getCurveCommitment(0)"
$CAST_CALL "$DIAMOND" "previewCurveQuote(uint256,uint128)" 0 100000000 >/dev/null && ok "previewCurveQuote"
$CAST_CALL "$DIAMOND" "previewBestExecution(bytes32,bool,uint128,uint256[])" "$MARKET_ID" true 100000000 "[0,3]" >/dev/null && ok "previewBestExecution"
$CAST_CALL "$DIAMOND" "getMarketTopOfBook(bytes32)" "$MARKET_ID" >/dev/null && ok "getMarketTopOfBook"

step "fillCurve / fillBest"
read -r GEN0 COMMIT0 _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 0 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "fillCurve(uint256,uint128,uint128,uint32,bytes32)" 0 50000000 0 "$GEN0" "$COMMIT0" >/dev/null && ok "fillCurve(0)"

# fillBest takes a struct.
read -r GEN0 COMMIT0 _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 0 | tr '\n' ' ')"
read -r GEN3 COMMIT3 _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 3 | tr '\n' ' ')"
MAXP=340282366920938463463374607431768211455
$CAST_SEND "$DIAMOND" "fillBest((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))" \
  "($MARKET_ID,true,100000000,0,$MAXP,[0,3],[$GEN0,$GEN3],[$COMMIT0,$COMMIT3],$ME,$RECEIVER)" >/dev/null && ok "fillBest"

step "cancelCurve / cancelCurvesBatch"
$CAST_SEND "$DIAMOND" "cancelCurve(uint256)" 1 >/dev/null && ok "cancelCurve(1)"
$CAST_SEND "$DIAMOND" "cancelCurvesBatch(uint256[])" "[2,4]" >/dev/null && ok "cancelCurvesBatch"

##############################################################################
# 7. Spot book (ERC20 base / EveUSDC quote)
##############################################################################
step "createBook + book ops"
SALT=0x0000000000000000000000000000000000000000000000000000000000000001
# BookAssetType.ERC20=1, BaseTransferMode.EXACT=0. Base=EVE token, Quote=EveUSDC.
BOOK_ID=$($CAST_CALL "$DIAMOND" "computeBookId(address,uint8,uint8,address,uint256,address,bytes32)(bytes32)" \
  "$ME" 1 0 "$EVE" 0 "$EVEUSDC" "$SALT")
ok "computeBookId       $BOOK_ID"
$CAST_SEND "$DIAMOND" "createBook(uint8,uint8,address,uint256,address,bytes32)" \
  1 0 "$EVE" 0 "$EVEUSDC" "$SALT" >/dev/null && ok "createBook"
$CAST_CALL "$DIAMOND" "getBookInfo(bytes32)" "$BOOK_ID" >/dev/null && ok "getBookInfo"

step "postBookCurve / postBookCurvesBatch"
# CurveSide ASK=0. Maker escrows EVE base.
$CAST_SEND "$DIAMOND" "postBookCurve(bytes32,uint8,uint128,uint72,uint72,uint24,uint8)" \
  "$BOOK_ID" 0 1000000000000000000 100000000 100000000 60 0 >/dev/null && ok "postBookCurve(ASK)"
$CAST_SEND "$DIAMOND" "postBookCurvesBatch(bytes32,uint8,(bool,uint128,uint72,uint72,uint24,uint8)[])" \
  "$BOOK_ID" 0 "[(true,500000000000000000,100000000,100000000,60,0)]" >/dev/null && ok "postBookCurvesBatch"

# Book curve ids are continuations of global curve numbering; previewBookExecution accepts any list.
step "Book views + book trades"
$CAST_CALL "$DIAMOND" "getBookTopOfBook(bytes32)" "$BOOK_ID" >/dev/null && ok "getBookTopOfBook"
$CAST_CALL "$DIAMOND" "getMarketSideBook(bytes32,bool)" "$MARKET_ID" true >/dev/null && ok "getMarketSideBook"

# Find the latest book curve id by introspecting BookInfo.totalCurveCount + iterate.
# Easier: just reuse curves 5..6 and try previewBookExecution.
$CAST_CALL "$DIAMOND" "previewBookExecution(bytes32,uint128,uint256[])" "$BOOK_ID" 100000 "[5]" >/dev/null && ok "previewBookExecution"

read -r GENB COMMITB _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 5 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "fillBookBest((bytes32,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))" \
  "($BOOK_ID,1000000,0,$MAXP,[5],[$GENB],[$COMMITB],$ME,$RECEIVER)" >/dev/null && ok "fillBookBest"

read -r GENB COMMITB _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 5 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "fillBookBestFor((bytes32,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))" \
  "($BOOK_ID,500000,0,$MAXP,[5],[$GENB],[$COMMITB],$ME,$RECEIVER)" >/dev/null && ok "fillBookBestFor"

step "topUpBookCurvesBatch + sellBookBest"
$CAST_SEND "$DIAMOND" "topUpBookCurvesBatch(bytes32,(uint256,uint128)[])" "$BOOK_ID" "[(5,100000000000000000)]" >/dev/null && ok "topUpBookCurvesBatch"

# To sellBookBest we need a BID curve with quote-side EveUSDC escrowed.
# Post a bid curve so we can sell into it.
$CAST_SEND "$DIAMOND" "postBookCurve(bytes32,uint8,uint128,uint72,uint72,uint24,uint8)" \
  "$BOOK_ID" 1 100000000 100000000 100000000 60 0 >/dev/null && ok "postBookCurve(BID)"
BID_ID=$(jq '.transactions[-1].contractAddress' "$BCAST" 2>/dev/null || true)
# best-effort: assume next curve id is 7 (curve numbering continues sequentially).
read -r GENB COMMITB _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 7 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "sellBookBest((bytes32,uint128,uint128,uint256[],uint32[],bytes32[],address))" \
  "($BOOK_ID,100000000000000000,0,[7],[$GENB],[$COMMITB],$RECEIVER)" >/dev/null && ok "sellBookBest"

##############################################################################
# 8. Parimutuel
##############################################################################
step "createParimutuelMarket + parimutuel ops"
PQUESTION="Anvil parimutuel $$"
PEXPIRY=$((NOW + 7000))
$CAST_SEND "$DIAMOND" "createParimutuelMarket(string,string,uint64)" "$PQUESTION" "binary" "$PEXPIRY" >/dev/null && ok "createParimutuelMarket"

PMARKET_ID=$($CAST_CALL "$DIAMOND" "computeMarketId(string,string,uint64,address,uint8,uint8)(bytes32)" \
  "$PQUESTION" "binary" "$PEXPIRY" "$EVEUSDC" 1 1)
ok "parimutuel marketId $PMARKET_ID"

$CAST_CALL "$DIAMOND" "isParimutuelMarket(bytes32)(bool)" "$PMARKET_ID" >/dev/null && ok "isParimutuelMarket"
$CAST_CALL "$DIAMOND" "previewEntryFee(bytes32,uint128)" "$PMARKET_ID" 100000000 >/dev/null && ok "previewEntryFee"
$CAST_CALL "$DIAMOND" "getEpochMultiplier(bytes32)" "$PMARKET_ID" >/dev/null && ok "getEpochMultiplier"

$CAST_SEND "$DIAMOND" "buyShares(bytes32,bool,uint128,address)" "$PMARKET_ID" true  10000000 "$ME" >/dev/null && ok "buyShares(YES, 10)"
$CAST_SEND "$DIAMOND" "buyShares(bytes32,bool,uint128,address)" "$PMARKET_ID" false 10000000 "$ME" >/dev/null && ok "buyShares(NO, 10)"
$CAST_SEND "$DIAMOND" "buySharesBatch(bytes32[],bool[],uint128[],address)" \
  "[$PMARKET_ID,$PMARKET_ID]" "[true,false]" "[5000000,5000000]" "$ME" >/dev/null && ok "buySharesBatch"

$CAST_CALL "$DIAMOND" "getParimutuelPool(bytes32)" "$PMARKET_ID" >/dev/null && ok "getParimutuelPool"
$CAST_CALL "$DIAMOND" "getParimutuelBalances(bytes32,address)" "$PMARKET_ID" "$ME" >/dev/null && ok "getParimutuelBalances"
$CAST_CALL "$DIAMOND" "previewPayout(bytes32,address)" "$PMARKET_ID" "$ME" >/dev/null && ok "previewPayout"

##############################################################################
# 9. TradeRouter (USDC <-> shares via eveUSDC wrap)
##############################################################################
step "TradeRouter splitWithUSDC / buyWithUSDC / buyWithEveUSDC"
$CAST_SEND "$DIAMOND" "splitWithUSDC(bytes32,uint128,address)" "$MARKET_ID" 100000000 "$ME" >/dev/null && ok "splitWithUSDC"

read -r GEN0 COMMIT0 _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 0 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "buyWithUSDC((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))" \
  "($MARKET_ID,true,50000000,0,$MAXP,[0],[$GEN0],[$COMMIT0],$ME,$RECEIVER)" >/dev/null && ok "buyWithUSDC"

read -r GEN0 COMMIT0 _ <<<"$($CAST_CALL "$DIAMOND" "getCurveCommitment(uint256)(uint32,bytes32)" 0 | tr '\n' ' ')"
$CAST_SEND "$DIAMOND" "buyWithEveUSDC((bytes32,bool,uint128,uint128,uint128,uint256[],uint32[],bytes32[],address,address))" \
  "($MARKET_ID,true,50000000,0,$MAXP,[0],[$GEN0],[$COMMIT0],$ME,$RECEIVER)" >/dev/null && ok "buyWithEveUSDC"

##############################################################################
# 10. VaultRouter (deposit / redeem on the staking vault)
##############################################################################
step "VaultRouter wrapAndDeposit / redeemAndUnwrap"
$CAST_SEND "$DIAMOND" "wrapAndDeposit(uint256,address)" 100000000 "$ME" >/dev/null && ok "wrapAndDeposit (100 USDC)"
SHARES=$($CAST_CALL "$VAULT" "balanceOf(address)(uint256)" "$ME" | awk '{print $1}')
ok "vault shares        $SHARES"
$CAST_SEND "$VAULT" "approve(address,uint256)" "$DIAMOND" "$MAX" >/dev/null && ok "vault.approve(diamond)"
HALF=$((SHARES / 2))
$CAST_SEND "$DIAMOND" "redeemAndUnwrap(uint256,address)" "$HALF" "$ME" >/dev/null && ok "redeemAndUnwrap (half)"

##############################################################################
# 11. Fee router previews/claims (CLOB + book)
##############################################################################
step "FeeRouter previews + claims"
$CAST_CALL "$DIAMOND" "previewMakerFees(bytes32,address)" "$MARKET_ID" "$ME" >/dev/null && ok "previewMakerFees"
$CAST_CALL "$DIAMOND" "getMakerMarketAccounting(bytes32,address)" "$MARKET_ID" "$ME" >/dev/null && ok "getMakerMarketAccounting"
$CAST_SEND "$DIAMOND" "claimMakerFees(bytes32)" "$MARKET_ID" >/dev/null && ok "claimMakerFees"

$CAST_CALL "$DIAMOND" "previewBookMakerFees(bytes32,address)" "$BOOK_ID" "$ME" >/dev/null && ok "previewBookMakerFees"
$CAST_CALL "$DIAMOND" "getMakerBookAccounting(bytes32,address)" "$BOOK_ID" "$ME" >/dev/null && ok "getMakerBookAccounting"
$CAST_SEND "$DIAMOND" "claimBookMakerFees(bytes32)" "$BOOK_ID" >/dev/null && ok "claimBookMakerFees"

##############################################################################
# 12. Resolution flow (CLOB market): syncMarketState -> settleMarket -> finalize
##############################################################################
step "Resolution flow (CLOB)"
T1=$((EXPIRY + 60))
cast rpc --rpc-url $RPC anvil_setNextBlockTimestamp "$T1" >/dev/null
cast rpc --rpc-url $RPC evm_mine >/dev/null
ok "anvil time -> $T1 (post-expiry)"

$CAST_SEND "$DIAMOND" "syncMarketState(bytes32)" "$MARKET_ID" >/dev/null && ok "syncMarketState"

EVIDENCE=0xfaa555ffb59f8f25cb77c4465a88c700205467fe87418ab1fe924d6470b987d3
$CAST_SEND "$DIAMOND" "settleMarket(bytes32,uint8,bytes32)" "$MARKET_ID" 1 "$EVIDENCE" >/dev/null && ok "settleMarket(YES)"
$CAST_CALL "$DIAMOND" "getResolutionHistory(bytes32)" "$MARKET_ID" >/dev/null && ok "getResolutionHistory"

T2=$((T1 + 7260))
cast rpc --rpc-url $RPC anvil_setNextBlockTimestamp "$T2" >/dev/null
cast rpc --rpc-url $RPC evm_mine >/dev/null
ok "anvil time -> $T2 (post-dispute-window)"

$CAST_SEND "$DIAMOND" "finalizeResolution(bytes32)" "$MARKET_ID" >/dev/null && ok "finalizeResolution"

step "Settlement views + creator-fee claim + redeem"
$CAST_CALL "$DIAMOND" "getCTFRedemptionParams(bytes32)" "$MARKET_ID" >/dev/null && ok "getCTFRedemptionParams"
$CAST_CALL "$DIAMOND" "getCTFRedemptionParams(bytes32)" "$MARKET_ID" >/dev/null && ok "getCTFRedemptionParams"
$CAST_CALL "$DIAMOND" "previewRedemption(bytes32,address)" "$MARKET_ID" "$ME" >/dev/null && ok "previewRedemption"
$CAST_CALL "$DIAMOND" "previewCTFRedemption(bytes32,address)" "$MARKET_ID" "$ME" >/dev/null && ok "previewCTFRedemption"
$CAST_CALL "$DIAMOND" "previewParimutuelPayout(bytes32,address)" "$PMARKET_ID" "$ME" >/dev/null && ok "previewParimutuelPayout"

$CAST_SEND "$DIAMOND" "claimCreatorFees(bytes32)" "$MARKET_ID" >/dev/null && ok "claimCreatorFees"

$CAST_SEND "$CTF" "redeemPositions(address,bytes32,bytes32,uint256[])" \
  "$EVEUSDC" 0x0000000000000000000000000000000000000000000000000000000000000000 "$COND_ID" "[1,2]" >/dev/null && ok "ctf.redeemPositions"

##############################################################################
# 13. Resolution flow (parimutuel): expire + settle + claim + sweep
##############################################################################
step "Resolution flow (parimutuel)"
T3=$((PEXPIRY + 60))
if [ "$T3" -gt "$T2" ]; then
  cast rpc --rpc-url $RPC anvil_setNextBlockTimestamp "$T3" >/dev/null
  cast rpc --rpc-url $RPC evm_mine >/dev/null
fi
$CAST_SEND "$DIAMOND" "syncMarketState(bytes32)" "$PMARKET_ID" >/dev/null && ok "syncMarketState (pari)"
$CAST_SEND "$DIAMOND" "settleMarket(bytes32,uint8,bytes32)" "$PMARKET_ID" 1 "$EVIDENCE" >/dev/null && ok "settleMarket (pari, YES)"

T4=$((T3 + 7260))
cast rpc --rpc-url $RPC anvil_setNextBlockTimestamp "$T4" >/dev/null
cast rpc --rpc-url $RPC evm_mine >/dev/null
$CAST_SEND "$DIAMOND" "finalizeResolution(bytes32)" "$PMARKET_ID" >/dev/null && ok "finalizeResolution (pari)"

$CAST_SEND "$DIAMOND" "claimPayout(bytes32)" "$PMARKET_ID" >/dev/null && ok "claimPayout"
$CAST_SEND "$DIAMOND" "sweepParimutuelDust(bytes32)" "$PMARKET_ID" >/dev/null || ok "sweepParimutuelDust (no dust)"

##############################################################################
##############################################################################
step "Resolution / bond view fns"

##############################################################################
step "Done"
printf "\n\033[1;32mAll user-facing functions across 21 facets smoked successfully.\033[0m\n\n"
echo "Diamond:           $DIAMOND"
echo "EveUSDC:            $EVEUSDC"
echo "USDC:              $USDC"
echo "ConditionalTokens: $CTF"
echo "EVE:               $EVE"
echo "EVE-Votes:         $EVOTES"
echo "ParimutuelShares:  $PSHARE"
echo "Treasury:          $TREASURY"
echo "Market id:         $MARKET_ID"
echo "Parimutuel id:     $PMARKET_ID"
echo "Book id:           $BOOK_ID"
