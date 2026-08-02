# Multiverse Markets Design Spec

**Status:** Draft
**Date:** 2026-05-15
**Author:** Eve (from Matt's direction)
**Context:** Inspired by Proof (@airtightfish) — "markets for consequence, not just probability"

---

## 1. Problem

Eves Market currently supports **binary outcome markets only** (Yes / No / Invalid). This works well for event prediction ("Will X happen?") but cannot express **conditional asset pricing** — "What is BTC worth if quantum scales?" — which represents a fundamentally larger market category.

The resolution trust layer (OBR) is already outcome-agnostic. The constraint is purely in outcome encoding and CTF payout reporting.

---

## 2. Goal

Extend Eves Market to support two new market types that enable conditional asset pricing, while reusing the existing OBR resolution system without modification.

### Market Type A: Scalar Markets
The outcome is a **numerical value** within a defined range. The creator proposes a number, the same OBR bond/dispute/escalation/vote flow validates it. Payouts are proportional to distance from the resolved value.

**Examples:**
- "What is BTC priced at on Dec 31 2026?"
- "Ethereum gas price (gwei) at next halving?"
- "US unemployment rate Q4 2026?"

### Market Type B: Multi-Outcome Discrete Markets
The outcome is one of **N discrete options** (N > 2). Each option represents a distinct scenario. The creator proposes which option occurred.

**Examples:**
- "Who wins the 2028 election?" (Candidate A, B, C, None)
- "What is BTC worth if quantum scales?" (Under $50k, $50-100k, $100-150k, $150k+)
- "Taiwan status by 2027?" (Status quo, Blockade, Conflict, Reunification)

---

## 3. Current Architecture (Baseline)

### 3.1 Market Outcome Encoding

```solidity
// LibEveMarket.sol
enum MarketOutcome {
    Unresolved,  // 0
    Yes,         // 1
    No,          // 2
    Invalid      // 3
}
```

Hardcoded to 3 meaningful outcomes. Used everywhere — resolution, settlement, frontend.

### 3.2 CTF Payout Reporting

```solidity
// OBRResolutionFacet.sol — _reportOutcome()
uint256[] memory payouts = new uint256[](2);

if (outcome == OUTCOME_YES) { payouts[0] = 1; }
else if (outcome == OUTCOME_NO) { payouts[1] = 1; }
else { payouts[0] = 1; payouts[1] = 1; }  // Invalid = refund both

IConditionalTokens(conditionalTokens).reportPayouts(questionId, payouts);
```

Fixed 2-element payout vector. Gnosis CTF supports N positions natively, but we only ever create and report 2.

### 3.3 Market Creation

```solidity
// MarketFactoryFacet.sol — createMarket()
function createMarket(
    string calldata question,
    string calldata category,
    string calldata resolutionSource,
    uint64 expiryTime,
    uint128 initialVolume,
    bool initialDirection
) external returns (bytes32 marketId)
```

No parameters for outcome type, scalar bounds, or multi-outcome options.

### 3.4 OBR Resolution (Unchanged)

The entire resolution flow is **already outcome-agnostic**:
- `settleMarket(marketId, outcome, evidenceHash)` — creator proposes any `uint8` outcome
- `openResolution(marketId, outcome, evidenceHash)` — anyone can counter-propose
- `disputeResolution(marketId, counterOutcome)` — escalate with bonds
- `castEveVote(marketId, outcome)` — vote on any outcome
- `finalizeResolution(marketId)` — resolve after deadline

The OBR machinery doesn't care *what* the outcome means — it just enforces that someone staked bonds to propose it, and gives others a chance to challenge. **No changes needed to OBR for new market types.**

---

## 4. Proposed Changes

### 4.1 New Types

```solidity
// LibEveMarket.sol — additions

enum MarketOutcomeType {
    Binary,       // existing: Yes/No/Invalid (2 CTF positions)
    Scalar,       // numerical outcome within [lowerBound, upperBound]
    MultiOutcome  // N discrete outcomes (N positions, 2 < N <= 256)
}

struct ScalarBounds {
    uint256 lowerBound;  // minimum valid value (e.g. 0)
    uint256 upperBound;  // maximum valid value (e.g. 1_000_000 * 1e18 for $1M)
    uint8   decimals;    // display/formatting hint (e.g. 2 for USD)
}

struct MultiOutcomeConfig {
    uint8 outcomeCount;           // number of discrete outcomes (3-256)
    bytes32 outcomesRoot;         // merkle root of outcome descriptions (off-chain resolution)
}
```

### 4.2 Extended MarketOutcome Encoding

For **binary markets** — no change. `MarketOutcome` enum works as-is.

For **scalar markets** — `uint8 outcome` in resolution is repurposed:
- `0` = Unresolved (unchanged)
- `1` = Scalar resolved (value stored in new field)
- `2` = Invalid (unchanged)

Scalar resolved value stored in a new mapping:

```solidity
mapping(bytes32 marketId => uint256 resolvedScalarValue) public scalarResolutionValue;
```

For **multi-outcome markets** — `uint8 outcome` directly represents the winning outcome index (1-indexed to avoid collision with Unresolved=0). `0` = Unresolved, `1..N` = outcomes, `type(uint8).max` = Invalid.

### 4.3 Scalar Payout Logic

Scalar markets use **2 CTF positions** (Below / Above), but settle proportionally:

```solidity
function _reportScalarOutcome(
    bytes32 marketId,
    address conditionalTokens,
    bytes32 questionId,
    uint256 resolvedValue,
    uint256 lowerBound,
    uint256 upperBound
) internal {
    uint256[] memory payouts = new uint256[](2);

    if (resolvedValue <= lowerBound) {
        payouts[0] = 1e18;  // Below wins full payout
        payouts[1] = 0;
    } else if (resolvedValue >= upperBound) {
        payouts[0] = 0;
        payouts[1] = 1e18;  // Above wins full payout
    } else {
        // Proportional split based on where the value falls
        uint256 range = upperBound - lowerBound;
        uint256 aboveWeight = ((resolvedValue - lowerBound) * 1e18) / range;
        uint256 belowWeight = 1e18 - aboveWeight;
        payouts[0] = belowWeight;
        payouts[1] = aboveWeight;
    }

    IConditionalTokens(conditionalTokens).reportPayouts(questionId, payouts);
}
```

Traders buy "Below" or "Above" positions at a price reflecting where they think the scalar value will land. This is the standard Gnosis scalar market pattern — already supported by the CTF framework.

### 4.4 Multi-Outcome Payout Logic

Multi-outcome markets use **N CTF positions** instead of 2:

```solidity
function _reportMultiOutcome(
    bytes32 marketId,
    address conditionalTokens,
    bytes32 questionId,
    uint8 winningOutcome,
    uint8 outcomeCount
) internal {
    uint256[] memory payouts = new uint256[](outcomeCount);

    if (winningOutcome == INVALID_OUTCOME) {
        // Invalid = refund all positions equally
        for (uint8 i = 0; i < outcomeCount; i++) {
            payouts[i] = 1;
        }
    } else {
        payouts[winningOutcome - 1] = 1;  // 1-indexed → 0-indexed
    }

    IConditionalTokens(conditionalTokens).reportPayouts(questionId, payouts);
}
```

### 4.5 Market Creation Extensions

```solidity
// New overloaded createMarket — or new dedicated functions

function createScalarMarket(
    string calldata question,
    string calldata category,
    string calldata resolutionSource,
    uint64 expiryTime,
    uint256 lowerBound,
    uint256 upperBound,
    uint8 decimals,
    uint128 initialVolume,
    bool initialDirection   // Below = true, Above = false
) external returns (bytes32 marketId)

function createMultiOutcomeMarket(
    string calldata question,
    string calldata category,
    string calldata resolutionSource,
    uint64 expiryTime,
    uint8 outcomeCount,
    bytes32 outcomesRoot,   // merkle root of outcome labels
    uint128 initialVolume,
    uint8 initialOutcome    // which outcome to seed
) external returns (bytes32 marketId)
```

### 4.6 OBR Resolution — Minimal Changes

The OBR flow stays identical. The only change is in `_reportOutcome`, which needs branching:

```solidity
function _reportOutcome(bytes32 marketId, address ct, bytes32 questionId, uint8 outcome) internal {
    MarketOutcomeType outcomeType = market.outcomeType;

    if (outcomeType == MarketOutcomeType.Binary) {
        // existing logic — unchanged
        _reportBinaryOutcome(marketId, ct, questionId, outcome);
    } else if (outcomeType == MarketOutcomeType.Scalar) {
        uint256 resolvedValue = scalarResolutionValue[marketId];
        _reportScalarOutcome(marketId, ct, questionId, resolvedValue, market.scalarBounds.lowerBound, market.scalarBounds.upperBound);
    } else if (outcomeType == MarketOutcomeType.MultiOutcome) {
        _reportMultiOutcome(marketId, ct, questionId, outcome, market.multiOutcomeConfig.outcomeCount);
    }
}
```

New storage fields on `Market` struct:

```solidity
MarketOutcomeType outcomeType;
ScalarBounds scalarBounds;           // only for scalar markets
MultiOutcomeConfig multiOutcomeConfig; // only for multi-outcome markets
```

### 4.7 Scalar Settlement Flow

For scalar markets, the resolution flow gains one extra step:

1. Creator calls `settleScalarMarket(marketId, uint256 resolvedValue, bytes32 evidenceHash)` — proposes a numerical value instead of Yes/No
2. This stores `resolvedValue` in `scalarResolutionValue[marketId]` and sets outcome to `Scalar=1`
3. Dispute window opens — challengers call `disputeResolution(marketId, counterValue, evidenceHash)` with their proposed value
4. Escalation proceeds as normal through OBR
5. Finalization calls `_reportScalarOutcome` with the winning value

### 4.8 Validation — Outcome Bounds

```solidity
// Scalar: resolved value must be within [lowerBound, upperBound]
if (outcomeType == MarketOutcomeType.Scalar) {
    require(
        resolvedValue >= market.scalarBounds.lowerBound &&
        resolvedValue <= market.scalarBounds.upperBound,
        Errors.ScalarValueOutOfBounds(resolvedValue)
    );
}

// Multi-outcome: proposed outcome must be within valid range
if (outcomeType == MarketOutcomeType.MultiOutcome) {
    require(
        outcome >= 1 && outcome <= market.multiOutcomeConfig.outcomeCount,
        Errors.InvalidOutcomeIndex(outcome)
    );
}
```

---

## 5. What Does NOT Change

| Component | Change Required |
|-----------|----------------|
| OBR bond/dispute/escalation flow | **None** |
| EVE vote mechanism | **None** |
| Fee routing (FeeRouterFacet) | **None** |
| Curve CLOB trading (curve math, packing) | **None** — curves trade positions as before |
| Parimutuel markets | **None** — separate system |
| Market creation bond | **None** — same anti-spam |
| Diamond proxy / upgrade pattern | **None** — new facet or facet upgrade |
| Vault (sEVEUSD, fee share) | **None** |
| Collateral (eveUSD) | **None** |

The beauty of this: **OBR is the hard part, and it's already done.** The only new work is outcome encoding and CTF reporting.

---

## 6. Frontend Changes

### Market Creation UI
- Add market type selector: Binary / Scalar / Multi-Outcome
- **Scalar:** Lower bound + upper bound + decimals inputs
- **Multi-Outcome:** Dynamic outcome list (add/remove outcomes, label each)

### Market Trading UI
- **Scalar:** Price axis shows Below/Above positions, price reflects probability distribution across the range. Visual slider showing "market-implied value"
- **Multi-Outcome:** One position token per outcome, similar to current Yes/No cards but N of them

### Resolution UI
- **Scalar:** Creator enters numerical value, evidence URL
- **Multi-Outcome:** Creator selects winning outcome from list
- Dispute/escalation UI stays identical

---

## 7. Implementation Phases

### Phase 1: Scalar Markets (Higher Value, Lower Complexity)
- New `MarketOutcomeType.Scalar` enum value
- `ScalarBounds` storage on Market struct
- `createScalarMarket()` factory function
- `settleScalarMarket()` resolution function
- `_reportScalarOutcome()` payout logic
- Frontend: scalar market creation + trading + resolution UI
- **Estimated effort:** 1-2 weeks contract work, 1 week frontend

### Phase 2: Multi-Outcome Discrete Markets
- New `MarketOutcomeType.MultiOutcome` enum value
- `MultiOutcomeConfig` storage on Market struct
- `createMultiOutcomeMarket()` factory function
- Extended `_reportOutcome()` dispatch
- Frontend: multi-outcome cards, dynamic outcome display
- **Estimated effort:** 1-2 weeks contract work, 1-2 weeks frontend

### Phase 3: Conditional Asset Pricing (Multiverse Markets)
- Composability layer: scalar markets where the underlying is an asset price oracle
- Cross-market hedging UI (recession portfolio vs soft-landing portfolio)
- Agent-driven market creation + settlement
- This is where Eves Market competes directly with Proof's thesis
- **Estimated effort:** 2-4 weeks, depends on oracle/price feed integration

---

## 8. Competitive Positioning

**Proof** (@ProofMarkets, @airtightfish) is building conditional perpetuals — leverage, cross-margining, perp-style settlement. Institutional-grade, complex.

**Eves Market's edge:** We don't need to build new derivative infrastructure. We have:
- Working CLOB with maker curves
- Working OBR resolution (crypto-economic trust)
- Working CTF position tokens
- Permissionless market creation

The same trust layer that validates "Did the election happen?" can validate "What was BTC's price on Dec 31?" The market mechanics are different, but the trust mechanism is identical.

Proof needs to build an exchange from scratch. We need to extend outcome encoding.

---

## 9. Open Questions

1. **Scalar position token liquidity:** Binary markets have natural 50/50 starting liquidity. Scalar markets with wide ranges may have thin books. Solution: tighter default ranges, or parimutuel as fallback for scalar markets.

2. **Multi-outcome curve seeding:** With N positions, the initial curve needs to express N-way probability. Current 2-position curve math (50/50 initial) needs extension to 1/N initial pricing.

3. **Dispute resolution for scalar values:** If creator proposes BTC = $95,000 and challenger proposes $96,000, what does the EVE vote look like? Options:
   - Binary vote on each proposed value (current model — works)
   - Range vote (new mechanism — complex)
   - Recommendation: keep binary choice between two proposed values, same as current OBR

4. **Gas costs for multi-outcome CTF:** N-position condition registration and payout reporting scales linearly with N. Upper bound on outcome count should be enforced (recommend max 32 or 64).

5. **Parimutuel + multi-outcome:** Parimutuel naturally supports N outcomes already (buy shares in any bucket). Could be the simpler path for multi-outcome markets without CLOB complexity.

---

## 10. Reference

- Proof announcement article: https://x.com/i/article/2055008253554118656
- Dave White's "Multiverse Markets" concept (credited in Proof article)
- Gnosis CTF scalar market documentation
- Current codebase: `src/facets/OBRResolutionFacet.sol`, `src/facets/MarketFactoryFacet.sol`, `src/libraries/LibEveMarket.sol`
