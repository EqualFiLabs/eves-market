# Multi-Outcome Parimutuel — Specification Document

**Status:** Draft
**Author:** Eve (Eves Market)
**Date:** 2026-05-24
**Target:** EvePredict v2.2+

---

## 1. Overview

Extend the current binary (YES/NO) parimutuel market type to support **N outcomes** (2–8). This enables markets like "Who wins the 2024 election?" with candidates Trump, Harris, Kennedy rather than requiring separate binary markets or NegRisk-style CTF adapters.

**Key principle:** Keep the simple pooled-entry mechanics. Replace the two hardcoded share counters with a mapping. Everything else (fees, epochs, OBR resolution) stays structurally identical.

---

## 2. Current State (Binary)

```solidity
// LibParimutuel.sol
struct Pool {
    uint128 totalYesShares;
    uint128 totalNoShares;
    uint128 payoutPool;
    uint128 claimedPayout;
    uint128 claimedClaimableShares;
    LibEveMarket.MarketOutcome rawResolvedOutcome;
    LibEveMarket.MarketOutcome effectivePayoutOutcome;
    uint128 payoutPoolAtResolution;
    uint128 totalClaimableSharesAtResolution;
    bool dustSwept;
    bool finalized;
}

// ParimutuelFacet.sol
function buyShares(bytes32 marketId, bool isYes, uint128 amount, ...)

// LibEveMarket.sol
enum MarketOutcome { Yes, No, Invalid }
```

**Current token model:** One ERC-1155 token ID per market. `isYes` determines which side the user is on.

---

## 3. Target State (Multi-Outcome)

### 3.1 Pool Structure

```solidity
// LibParimutuel.sol
struct Pool {
    // REMOVED: uint128 totalYesShares;
    // REMOVED: uint128 totalNoShares;

    // NEW: outcomeId => shares
    mapping(uint8 => uint128) outcomeShares;
    uint8 outcomeCount;              // 2–8 outcomes

    uint128 payoutPool;              // unchanged: total collateral
    uint128 claimedPayout;           // unchanged
    uint128 claimedClaimableShares;  // unchanged

    // REMOVED: MarketOutcome (enum)
    // NEW: raw uint8 outcome
    uint8 rawResolvedOutcome;
    uint8 effectivePayoutOutcome;

    uint128 payoutPoolAtResolution;      // unchanged
    uint128 totalClaimableSharesAtResolution; // winning outcome total
    bool dustSwept;                    // unchanged
    bool finalized;                      // unchanged
}
```

### 3.2 Market Outcome Type

Replace the `MarketOutcome` enum with a raw `uint8` everywhere:

```solidity
// LibEveMarket.sol — REMOVE enum, use uint8 directly
// OLD: enum MarketOutcome { Yes, No, Invalid }
// NEW: uint8 constant OUTCOME_INVALID = type(uint8).max; // 255 reserved
```

**Rationale:** An enum with 3 values doesn't scale. Using `uint8` lets us support up to 254 outcomes (realistically capped at 8 for UX). `255` is reserved for `Invalid`.

### 3.3 Market Creation

```solidity
// ParimutuelFacet.sol
struct CreateParimutuelArgs {
    string question;
    string category;
    string resolutionSource;
    uint64 tradingStartTime;
    uint64 expiryTime;
    uint64 epochWindow;
    string[] outcomes;          // NEW: ["Trump", "Harris", "Kennedy"]
}

// Validation:
// - outcomes.length >= 2 && outcomes.length <= 8
// - All outcome strings non-empty and unique
```

**Storage of outcome names:**
Option A: Store in `LibMarketMetadata` (already stores question/category)
Option B: Store in a new mapping: `mapping(bytes32 => string[]) marketOutcomes`

**Recommended:** Option A — extend `LibMarketMetadata` with an `outcomes` field. Keeps creation logic centralized.

---

## 4. Interface Changes

### 4.1 Buying Shares

```solidity
// CURRENT:
function buyShares(
    bytes32 marketId,
    bool isYes,           // CHANGED
    uint128 amount,
    address receiver,
    uint128 minSharesOut
) external returns (uint128 sharesMinted);

// NEW:
function buyShares(
    bytes32 marketId,
    uint8 outcome,        // 0 = first outcome, 1 = second, etc.
    uint128 amount,
    address receiver,
    uint128 minSharesOut
) external returns (uint128 sharesMinted);
```

**Validation:** `outcome < pool.outcomeCount`

### 4.2 Batch Buying

```solidity
// NEW:
function buySharesBatch(
    bytes32[] calldata marketIds,
    uint8[] calldata outcomes,    // CHANGED from bool[]
    uint128[] calldata amounts,
    uint128[] calldata minSharesOut,
    address receiver
) external returns (uint128[] memory sharesMinted);
```

### 4.3 View Functions

```solidity
// CURRENT: getParimutuelPool returns impliedYesProbability + impliedNoProbability
// NEW:
function getParimutuelPool(bytes32 marketId) external view returns (PoolView memory pool);

struct PoolView {
    uint128[] outcomeShares;        // length = outcomeCount
    uint128 payoutPool;
    uint128 claimedPayout;
    uint128 claimedClaimableShares;
    uint8 rawResolvedOutcome;
    uint8 effectivePayoutOutcome;
    uint128 payoutPoolAtResolution;
    uint128 totalClaimableSharesAtResolution;
    bool dustSwept;
    bool finalized;
    uint128[] impliedProbabilities; // each outcome's probability (basis points or wad)
}

// NEW:
function getOutcomeNames(bytes32 marketId) external view returns (string[] memory);

// CURRENT: getParimutuelBalances returns (yesShares, noShares)
// NEW:
function getParimutuelBalances(bytes32 marketId, address user)
    external view returns (uint128[] memory shares); // length = outcomeCount
```

---

## 5. Token Layer Changes

### 5.1 ERC-1155 Token ID Derivation

**Current:** One token ID per market.

**New:** Token ID derived from `(marketId, outcome)`:

```solidity
function _parimutuelTokenId(bytes32 marketId, uint8 outcome)
    internal pure returns (uint256 tokenId)
{
    tokenId = uint256(keccak256(abi.encodePacked(marketId, outcome)));
}
```

**Impact:** Users see multiple token IDs in their wallet per market (one per outcome they bet on).

### 5.2 Mint / Burn

```solidity
// On buy:
uint256 tokenId = _parimutuelTokenId(marketId, outcome);
_parimutuelShareToken.mint(receiver, tokenId, sharesMinted, "");

// On claim (non-winning outcomes become worthless):
// No burn needed — just don't allow claim. Tokens become dead.
// Optional: burn non-winning tokens to clean state.
```

---

## 6. Resolution Changes

### 6.1 OBR Resolution Facet

**Current:** Outcome validation checks `Yes | No | Invalid`.

**New:** Validate `outcome < market.outcomeCount || outcome == INVALID`.

```solidity
// OBRResolutionFacet._validateOutcome
function _validateOutcome(uint8 outcome, uint8 outcomeCount) internal pure {
    if (outcome != OUTCOME_INVALID && outcome >= outcomeCount) {
        revert Errors.InvalidOutcome(outcome, outcomeCount);
    }
}
```

**Resolution flow unchanged:**
1. Creator settles with `outcome`
2. Disputes escalate with counter-outcome
3. Final EVE vote picks any valid outcome

### 6.2 Effective Outcome Logic

**Current:** If winning side has 0 shares → Invalid.

**New:** Same logic extended:

```solidity
function effectivePayoutOutcome(Pool storage pool, uint8 resolvedOutcome)
    internal view returns (uint8)
{
    // If resolved outcome has 0 shares, fallback to Invalid
    if (pool.outcomeShares[resolvedOutcome] == 0) {
        return OUTCOME_INVALID;
    }
    return resolvedOutcome;
}
```

### 6.3 Invalid Outcome Payout

**Current:** Invalid refunds both sides (all shares become claimable).

**New:** Invalid refunds ALL outcomes (everyone gets pro-rata of their own shares).

```solidity
function claimableSharesForOutcome(Pool storage pool, uint8 payoutOutcome)
    internal view returns (uint128)
{
    if (payoutOutcome == OUTCOME_INVALID) {
        // Sum ALL outcome shares
        uint128 total;
        for (uint8 i = 0; i < pool.outcomeCount; i++) {
            total += pool.outcomeShares[i];
        }
        return total;
    }
    return pool.outcomeShares[payoutOutcome];
}
```

---

## 7. Fee Layer

**No changes required.** Entry fees are taken from `amount` before shares are minted. Fee split (creator / protocol / vault) is independent of outcomes.

```solidity
EntryFeeBreakdown memory fees = _entryFeeBreakdown(market, state.config, amount);
uint128 netCollateral = fees.netShares;  // collateral after fees
pool.payoutPool += netCollateral;
```

---

## 8. Epoch Multipliers

**No changes required.** Epoch system is time-based (trading start + window). It applies equally regardless of outcome count or which outcome the user picks.

---

## 9. Payout Claim Logic

### 9.1 Pro-Rata Calculation

```solidity
// For winning outcome W:
function _claimPayout(...) internal returns (uint128 payout) {
    uint8 winningOutcome = pool.effectivePayoutOutcome;
    uint256 userShares = _balanceOf(user, _parimutuelTokenId(marketId, winningOutcome));
    uint256 totalWinningShares = pool.outcomeShares[winningOutcome];

    if (userShares == 0 || totalWinningShares == 0) return 0;

    // Pro-rata: user's share of payoutPool
    payout = uint128((pool.payoutPoolAtResolution * userShares) / totalWinningShares);
}
```

### 9.2 Invalid Payout

Everyone claims pro-rata from their own outcome pool:

```solidity
if (winningOutcome == OUTCOME_INVALID) {
    for each outcome i:
        userShares = balanceOf(user, tokenId_i)
        totalShares = pool.outcomeShares[i]
        payout += (pool.payoutPoolAtResolution * userShares) / totalAllShares
}
```

---

## 10. Migration Path

### 10.1 Storage Layout

**Problem:** `LibParimutuel.Pool` is a struct in a mapping. Changing struct fields shifts storage slots.

**Solution:** Since `Pool` is stored in `mapping(bytes32 => Pool) pools`, and each market has its own slot, we can:

1. **Version the pool:** Add `uint8 version` field at start of struct
2. **New markets:** Use `version = 2`, read/write new fields
3. **Old markets:** Keep `version = 1`, legacy code paths still work

```solidity
struct Pool {
    uint8 version;  // NEW: 1 = legacy binary, 2 = multi-outcome

    // Version 1 fields (kept for compatibility)
    uint128 totalYesShares;
    uint128 totalNoShares;

    // Version 2 fields (used when version >= 2)
    mapping(uint8 => uint128) outcomeShares;
    uint8 outcomeCount;

    // Common fields
    uint128 payoutPool;
    ...
}
```

**Alternative (cleaner):** Accept that this is a breaking change. Deploy new facet, keep old facet for existing markets. Markets are immutable after resolution anyway.

**Recommended:** Clean break. Existing parimutuel markets are grandfathered (they resolve and are done). New markets use the new struct. No dual-path code.

### 10.2 Deployment Order

1. Update `LibParimutuel.sol`
2. Update `ParimutuelFacet.sol`
3. Update `OBRResolutionFacet.sol` (outcome validation)
4. Update `LibEveMarket.sol` (remove enum, add constant)
5. Update `MarketFactoryFacet.sol` (creation args)
6. Update `ParimutuelShareToken.sol` (token ID derivation)
7. Deploy new facet addresses
8. Diamond cut upgrade

---

## 11. Files Modified

| File | Change Type | Description |
|------|-------------|-------------|
| `LibParimutuel.sol` | **Major** | Pool struct: replace binary counters with `mapping(uint8 => uint128) outcomeShares` |
| `ParimutuelFacet.sol` | **Major** | All buy/view/claim functions accept `uint8 outcome` instead of `bool isYes` |
| `LibEveMarket.sol` | **Major** | Remove `MarketOutcome` enum; use `uint8` + `OUTCOME_INVALID` constant |
| `OBRResolutionFacet.sol` | **Minor** | Outcome validation: allow any `outcome < outcomeCount` |
| `MarketFactoryFacet.sol` | **Minor** | `CreateParimutuelArgs` adds `string[] outcomes` |
| `ParimutuelShareToken.sol` | **Minor** | Token ID = `keccak256(marketId, outcome)` |
| `LibMarketMetadata.sol` | **Minor** | Store outcome strings |
| `LibMarketCreation.sol` | **Minor** | Validate outcome count and uniqueness |

---

## 12. Frontend Requirements

### 12.1 Market Creation
- Allow adding 2–8 outcome strings
- Validate uniqueness
- Show preview of outcome options

### 12.2 Market Display
- Replace YES/NO toggle with outcome buttons/dropdown
- Show probability bar per outcome: `outcomeShares[i] / totalAllShares`
- Color-code outcomes

### 12.3 User Portfolio
- Show shares per outcome per market
- Payout preview based on selected outcome

### 12.4 Resolution
- Creator selects from outcome list (not YES/NO toggle)
- Disputers select different outcome from same list
- EVE voters see outcome names, not numbers

---

## 13. Open Questions

1. **Max outcomes:** Cap at 8? 16? UX degrades with too many options.
2. **Outcome naming:** Store on-chain (gas) or off-chain IPFS + hash on-chain?
3. **Combos / parlays:** Can users bet on multiple outcomes in one tx? (e.g., "Trump OR Harris")
4. **PartialInvalid:** Allow "None of the above" as an explicit outcome, or reserve Invalid for disputes only?
5. **Spot market integration:** Multi-outcome parimutuel shares tradeable on spot books?

---

## 14. Gas Impact

- **Buy shares:** Same gas (one storage write to `outcomeShares[outcome]`)
- **Claim payout:** Slightly more if Invalid (loop over N outcomes)
- **View functions:** Return arrays instead of tuples (more calldata)
- **Overall:** Negligible increase for N <= 8

---

*End of Spec*
