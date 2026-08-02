# NegRisk Multi-Outcome Orderbook Spec

**Status:** Draft
**Owner:** Eves Market protocol
**Target:** Beta position layer
**Scope:** Orderbook/CLOB markets only. Parimutuel multi-outcome markets are covered by `Multi-Outcome-Parimutuel-Spec.md`.

## 1. Intent

Add Polymarket-style multi-outcome orderbook markets without copying the Polymarket adapter or importing its operator model.

The product should let users trade a single market with many mutually exclusive outcomes:

```text
Who wins the election?
- Candidate A
- Candidate B
- Candidate C
- Candidate D
```

Each outcome should trade like a normal prediction market claim:

```text
Candidate A pays 1 collateral if Candidate A wins, else 0.
Candidate B pays 1 collateral if Candidate B wins, else 0.
...
```

Exactly one outcome wins unless the market is finalized invalid.

## 2. Relationship to Existing Specs

This is not the same system as multi-outcome parimutuel.

- Parimutuel multi-outcome uses one pooled collateral balance and N share buckets.
- Orderbook multi-outcome uses separately transferable ERC1155 outcome positions with dedicated CLOB books.
- Combinatorial positions may later reference these outcome positions as legs.
- Alpha binary CLOB markets remain valid and do not need migration.

This spec is inspired by negative-risk CTF adapters, but the preferred Eves implementation is a native module in the beta position layer.

## 3. Product Model

Retail users should see one market page with N outcomes:

```text
Who wins the election?

Candidate A   42c
Candidate B   31c
Candidate C   19c
Candidate D    8c
```

Clicking an outcome opens the same CLOB trading flow as binary markets:

- market order
- limit order
- visible depth
- user position
- claim/redeem after resolution

Makers should be able to quote all outcomes from one strategy and recycle inventory through complete-set split/merge operations.

## 4. Core Accounting Invariant

For a market with N outcomes, one complete set is worth exactly one unit of collateral:

```text
OUTCOME_0 + OUTCOME_1 + ... + OUTCOME_N-1 == 1 collateral
```

This invariant replaces the binary invariant:

```text
YES + NO == 1 collateral
```

The practical arbitrage is:

- If all outcome asks sum below 1, buy one of every outcome and merge the complete set into collateral.
- If all outcome bids sum above 1, split collateral into a complete outcome set and sell the outcomes.

This is the liquidity/pricing mechanism we want. It gives makers a way to inventory multi-outcome markets without every outcome being isolated.

## 5. Market Shape

Add a new market shape for orderbook markets:

```text
BinaryOrderbook
MultiOutcomeOrderbook
Parimutuel
Spot
```

The multi-outcome shape should store:

```solidity
struct MultiOutcomeMarket {
    bytes32 marketId;
    bytes32 conditionId;
    address collateralToken;
    address creator;
    uint64 tradingStartTime;
    uint64 expiryTime;
    uint8 outcomeCount;
    uint8 resolvedOutcome;
    bool invalid;
    bool resolved;
}
```

Outcome labels should live with market metadata:

```solidity
struct MultiOutcomeMetadata {
    string question;
    string category;
    string resolutionSource;
    string[] outcomes;
}
```

Recommended caps:

- minimum outcomes: 2
- initial maximum outcomes: 16
- possible later maximum: 32

Sixteen is enough for most product needs while keeping UI, gas, and maker operations sane.

## 6. Position Model

Use the beta `EvesPositionManager` ERC1155 position layer.

Each outcome gets one position ID:

```text
positionId = hash(moduleId, conditionId, outcomeIndex)
```

The condition ID represents the full mutually exclusive market, not an individual binary question:

```text
conditionId = hash(MULTI_OUTCOME_MODULE, marketId, outcomeCount, outcomesHash)
```

The core position type is:

```text
OUTCOME(i)
```

`OUTCOME(i)` pays one collateral unit if `i` is the final winning outcome. It pays zero if any other real outcome wins.

## 7. Why Not N Separate Binary Markets

Do not model this as independent binary markets:

```text
Will A win? YES/NO
Will B win? YES/NO
Will C win? YES/NO
```

That representation is wrong unless the protocol also understands that exactly one can resolve YES.

The clean native representation is one N-outcome condition. This gives us:

- one market identity
- one resolution result
- one complete-set invariant
- one market page
- one creator reputation trail
- exact collateral accounting

## 8. Core Operations

### 8.1 Split Collateral Into Complete Set

Mints one unit of every outcome token per unit of collateral deposited.

```solidity
function splitOutcomeSet(
    bytes32 marketId,
    uint128 amount,
    address receiver
) external returns (uint256[] memory positionIds);
```

For `amount = 100` and `N = 4`, receiver gets:

```text
100 OUTCOME_0
100 OUTCOME_1
100 OUTCOME_2
100 OUTCOME_3
```

The module takes 100 collateral.

### 8.2 Merge Complete Set Into Collateral

Burns equal amounts of every outcome token and returns collateral.

```solidity
function mergeOutcomeSet(
    bytes32 marketId,
    uint128 amount,
    address receiver
) external returns (uint128 collateralOut);
```

The caller must provide `amount` of every outcome token.

This is the main maker inventory recycling path.

### 8.3 Redeem Resolved Outcome

After resolution, the winning outcome redeems for collateral.

```solidity
function redeemOutcome(
    bytes32 marketId,
    uint8 outcome,
    uint128 amount,
    address receiver
) external returns (uint128 collateralOut);
```

If `outcome == resolvedOutcome`, payout is `amount`.

If another real outcome wins, payout is zero.

If the market is invalid, use the invalid payout rule in section 10.

### 8.4 Batch Operations

Batch versions are required for maker UX and gas efficiency:

```solidity
function batchRedeemOutcomes(
    bytes32[] calldata marketIds,
    uint8[] calldata outcomes,
    uint128[] calldata amounts,
    address receiver
) external returns (uint128 collateralOut);
```

Batch split/merge should be added if maker simulations show meaningful savings.

## 9. CLOB Integration

Each outcome gets its own book:

```text
bookId = hash(marketId, outcomeIndex)
```

Order price bounds:

```text
0 < price <= 1 collateral
```

The existing curve/order machinery should remain outcome-token based:

- makers post curves for `OUTCOME(i)`
- takers buy or sell `OUTCOME(i)`
- flat orders are represented as profiles where start price equals end price
- linear profiles can quote across quantity or time where useful

The market page should aggregate all outcome books under one market.

## 10. Invalid Market Behavior

Invalid cannot pay every outcome token one full collateral unit. That would break the complete-set invariant.

Recommended invalid payout:

```text
Each outcome token pays 1 / N collateral.
```

So a full complete set still redeems to one unit of collateral:

```text
N outcomes * (1 / N) == 1 collateral
```

For integer math:

- store invalid payout numerator as `1`
- store payout denominator as `outcomeCount`
- use `mulDiv` for redemption
- route dust to the protocol or staking vault after all practical claims, using the existing dust sweep pattern

This is not a perfect user refund, but it is the cleanest invariant-preserving invalid result for transferable outcome tokens.

## 11. NO Exposure

The core protocol should not initially mint standalone `NO(outcome)` tokens.

For an N-outcome market:

```text
NO(A) == OUTCOME(B) + OUTCOME(C) + ... + OUTCOME(N-1)
```

That means a NO position is a basket, not a primitive token.

Initial beta should support:

- direct trading of YES-style outcome tokens
- UI explanation that selling an outcome or buying the other outcomes expresses negative exposure
- maker/helper routing that can buy or sell the complement basket

Later optional extension:

```text
ComplementWrapper
```

The wrapper could custody the basket of all non-selected outcomes and issue a single ERC1155 `NO(outcome)` wrapper token. That should be a separate feature after the core complete-set system is tested.

## 12. Resolution Flow

Resolution should reuse the Eves OBR flow:

1. Market reaches expiry, or creator uses allowed early finalization.
2. Creator proposes `winningOutcome`.
3. Disputers can challenge with a different `winningOutcome` or invalid.
4. EVE vote can select any valid outcome or invalid.
5. Finalization records one payout vector.

Payout vector for real winner `i`:

```text
OUTCOME_i = 1
all other outcomes = 0
denominator = 1
```

Payout vector for invalid:

```text
all outcomes = 1
denominator = outcomeCount
```

Validation:

- `winningOutcome < outcomeCount`, or
- `winningOutcome == OUTCOME_INVALID`

No tie result should exist.

## 13. Fees

Use orderbook fee configuration.

Do not use parimutuel fee configuration.
Do not use spot fee configuration.

Creator fees should work the same way as binary orderbook creator fees:

- creator earns from trades in the market they created
- creator reputation matters because bad/ambiguous markets will attract disputes and less liquidity
- fee accounting is aggregated across all outcome books under the market

## 14. Events

Events should be indexer-first.

```solidity
event MultiOutcomeMarketCreated(
    bytes32 indexed marketId,
    bytes32 indexed conditionId,
    address indexed creator,
    uint8 outcomeCount,
    bytes32 outcomesHash
);

event OutcomePositionPrepared(
    bytes32 indexed marketId,
    uint8 indexed outcome,
    uint256 indexed positionId
);

event OutcomeSetSplit(
    bytes32 indexed marketId,
    address indexed account,
    uint128 amount
);

event OutcomeSetMerged(
    bytes32 indexed marketId,
    address indexed account,
    uint128 amount
);

event MultiOutcomeResolved(
    bytes32 indexed marketId,
    uint8 indexed outcome,
    bool invalid,
    uint256 payoutDenominator
);

event OutcomeRedeemed(
    bytes32 indexed marketId,
    address indexed account,
    uint8 indexed outcome,
    uint128 amountIn,
    uint128 collateralOut
);
```

Outcome labels should not be emitted in full if they are large. Emit an `outcomesHash` and store labels in metadata/indexer storage.

## 15. UI Requirements

Market list cards:

- show the question
- show the top 3-5 outcomes by best price or liquidity
- show a "multi-outcome" marker
- do not create separate cards for each outcome

Market detail:

- show all outcomes in one table
- show best bid/ask/last per outcome
- show depth for selected outcome
- show aggregate implied sum across outcomes
- warn makers when best asks sum below 1 or best bids sum above 1

Trade panel:

- outcome selector
- market/limit modes
- optional "complete set" maker control for split/merge

Portfolio:

- group positions by market
- list outcome balances
- show claimable value after resolution
- show invalid payout estimate if invalid is final

## 16. Maker UX

Makers need tools that are specific to multi-outcome markets:

- split collateral into all outcomes
- merge complete sets back into collateral
- quote multiple outcome books from one strategy
- see current sum of best bids and asks
- rebalance inventory across outcomes
- cancel/update curves by outcome

The maker bot should be able to treat one multi-outcome market as a vector:

```text
[A price, B price, C price, D price]
```

The protocol should not force the vector to sum to exactly one. Arbitrage and maker competition should pressure it toward one.

## 17. Combinatorial Compatibility

Combinatorial positions can later include multi-outcome legs:

```text
OUTCOME(Election, Candidate A)
AND YES(BTC > 150k)
AND NO(Fed cuts)
```

Rules:

- a combo may include at most one outcome from a given multi-outcome market
- outcome legs are treated as atomic payout claims
- if the selected outcome loses, that exact combo branch pays zero
- if the selected outcome wins, that leg contributes payout factor 1
- invalid multi-outcome legs contribute `1 / N` unless the combo module explicitly rejects invalid legs

For the first beta implementation, it is acceptable to keep combos limited to binary markets and add multi-outcome legs later.

## 18. Storage and Upgrade Boundary

This should be beta/redeploy work.

Do not try to mutate alpha binary storage into this model.

Recommended storage separation:

```text
LibMultiOutcomeMarket
LibMultiOutcomePosition
MultiOutcomeMarketFacet
MultiOutcomePositionFacet or module
```

Keep parimutuel multi-outcome storage separate from orderbook multi-outcome storage.

## 19. Test Plan

Minimum contract coverage:

- create market with 2 outcomes
- create market with max outcomes
- reject duplicate/empty outcome labels
- reject outcome count below min or above max
- split collateral into a full outcome set
- merge full outcome set back into collateral
- reject merge with missing outcome inventory
- trade each outcome through CLOB
- resolve each possible outcome
- redeem winning outcome
- confirm losing outcomes redeem zero
- resolve invalid and confirm each outcome pays `1 / N`
- invariant: complete set redemption value never exceeds deposited collateral
- invariant: split followed by merge is collateral-neutral before fees
- invariant: no more than one real outcome can resolve true
- creator/dispute/EVE vote flow supports all valid outcome indexes

Integration coverage:

- maker splits inventory, posts curves on all outcomes, taker buys one outcome, maker merges remaining complete sets where possible
- indexer reconstructs one market with N books
- UI renders one market page with all outcome books

## 20. Open Decisions

1. Initial max outcome count: 8, 16, or 32.
2. Whether creator fees should be identical across all outcome books or configurable per outcome.
3. Whether to add a complement basket helper in the first beta or defer it.
4. Whether invalid should always pay equal `1 / N`, or whether certain markets should include an explicit "Other / None" real outcome instead.
5. Whether multi-outcome legs should be allowed in the first combinatorial beta or added after binary combo markets are stable.

## 21. Recommended First Build

Build the smallest complete version:

- one N-outcome condition
- one ERC1155 outcome token per outcome
- split complete set
- merge complete set
- resolve one winner or invalid
- redeem outcome tokens
- one CLOB book per outcome
- one market page with all outcome books

Defer:

- standalone NO wrapper tokens
- complement basket routing
- multi-outcome combo legs
- per-outcome creator fee overrides

This gets the economically important primitive live without overbuilding around edge-case UX.
