# EVE Prediction Market — Technical Specification

**Version:** 0.4.0-draft
**Date:** 2026-04-12
**Status:** Draft
**Author:** Eve (from Matt's direction)
**License:** BUSL-1.1

---

## 1. Overview

A standalone on-chain prediction market protocol for $EVE utility. Markets are binary (YES/NO), resolved via Optimistic Bonded Resolution (OBR), and traded against maker-posted curves using a gas-efficient bitpacked format.

This document specifies the standalone EVM V1 only. Future rebuilds, integrations, or semantic ports are intentionally out of scope here.

V1 uses the Gnosis Conditional Tokens Framework (CTF) as the canonical outcome asset layer. Outcome exposure is represented as ERC-1155 position IDs, not bespoke ERC-20 tokens.

### Design Principles

1. **Low friction** — Polymarket-like UX. Anyone can trade. Market creation requires a modest protocol fee.
2. **On-chain CLOB via curves** — Makers post and update curves cheaply. The orderbook emerges from active curve management.
3. **Progressive immutability** — Diamond proxy with facets that freeze after verification.
4. **Event-forward state** — Events drive discovery and history, while views expose current executable state.
5. **No external oracle dependency** — Resolution is optimistic + bonded, not oracle-fed.

---

## 2. Architecture

### 2.1 Diamond Proxy

```
                    ┌─────────────────┐
                    │  EveMarketDiamond │
                    │  (proxy)         │
                    └────────┬────────┘
                             │ delegatecall
            ┌────────────────┼────────────────┐
            │                │                │
   ┌────────▼──────┐ ┌──────▼────────┐ ┌─────▼──────────┐
   │ MarketFactory │ │ CurveCLOB     │ │ OBRResolution  │
   │ Facet         │ │ Facet         │ │ Facet          │
   │ (upgradeable) │ │ (freezeable)  │ │ (freezeable)   │
   └───────────────┘ └───────────────┘ └────────────────┘
            │                │                │
   ┌────────▼──────┐ ┌──────▼────────┐ ┌─────▼──────────┐
   │ MarketFactory │ │ CurveCLOB     │ │ OBRResolution  │
   │ Facet         │ │ Facet         │ │ Facet          │
   │ (upgradeable) │ │ (freezeable)  │ │ (freezeable)   │
   └───────────────┘ └───────────────┘ └────────────────┘
            │                │                │
            └────────────────┼────────────────┘
                             │
                    ┌────────▼────────┐
                    │ LibEveMarket    │
                    │ (shared storage)│
                    └─────────────────┘
```

### 2.2 Facet Breakdown

| Facet | Purpose | Mutability |
|-------|---------|------------|
| `DiamondCutFacet` | Standard diamond upgrades | Owner-only, permanent |
| `DiamondLoupeFacet` | Standard diamond introspection | Immutable |
| `OwnershipFacet` | Access control | Owner-only |
| `MarketFactoryFacet` | Create markets, manage lifecycle | Upgradeable (V1) |
| `CurveCLOBFacet` | Post/update/fill curves | Freezable after audit |
| `OBRResolutionFacet` | Propose, dispute, resolve | Freezable after audit |
| `MarketSettlementFacet` | Claim winnings, refund losers | Freezable after audit |
| `FeeRouterFacet` | Split fee pool on settlement | Freezable after audit |
| `BondManagerFacet` | Resolution dispute bonding and slashing | Upgradeable (V1) |
| `EveTokenGateFacet` | EVE requirements for actions | Upgradeable (V1) |

### 2.3 Progressive Immutability

After deployment and audit verification, `freezeFacet(bytes4[] selectors)` is called:

- **CurveCLOBFacet** — frozen after first audit. Core trading logic must never change.
- **OBRResolutionFacet** — frozen after first audit. Resolution rules must be immutable.
- **MarketSettlementFacet** — frozen after first audit. Payout logic must be immutable.
- **FeeRouterFacet** — frozen after first audit. Fee split logic must be immutable.
- **MarketFactoryFacet** — upgradeable in V1 (market parameters may need tuning).
- **BondManagerFacet** — upgradeable in V1 (dispute bond amounts may need adjustment).
- **EveTokenGateFacet** — upgradeable in V1 (EVE requirements may evolve).

Frozen facets cannot be upgraded via `diamondCut`. The freeze is irreversible.

---

## 3. Core Data Structures

### 3.1 Bitpacked Curve (uint256)

Every maker curve is stored as a single uint256:

```
┌──────────────────────────────────────────────────────────────────┐
│ 255                                              0 (bit index)  │
├──────────┬──────────┬──────────┬──────────┬──────────┬─────────┤
│  reserved│ profileId│ feeBps   │ duration │ endPrice │startPrc │
│  32 bits │ 8 bits   │ 16 bits  │ 20 bits  │ 72 bits  │ 72 bits │
│          │          │          │  (mins)  │ (fixedpt)│(fixedpt)│
├──────────┼──────────┼──────────┼──────────┼──────────┼─────────┤
│ 32 bits  │ 8 bits   │ 16 bits  │ 20 bits  │ 72 bits  │ 72 bits │
└──────────┴──────────┴──────────┴──────────┴──────────┴─────────┘

Remaining volume: stored separately (changes on fill)
Generation: stored separately (changes on update)
Active flag: stored separately
```

**Fixed-point encoding:** Prices stored as `price * 10^9`. For prediction markets, prices are [0, 1]:
- 0.50 → `500_000_000` (fits in 72 bits, max ~4.7T)
- 0.01 → `10_000_000`
- 1.00 → `1_000_000_000`

**Gas cost:** One SSTORE for update = ~22k gas (cold) or ~5k gas (warm). With overhead, ~50k total per curve update.

### 3.2 Market struct

```solidity
struct Market {
    bytes32 marketId;           // keccak256(question + outcomes + expiry)
    address collateralToken;    // ERC-20 collateral token used by CTF (WETH in V1)
    bytes32 questionId;         // Canonical question hash used for CTF condition prep
    bytes32 conditionId;        // CTF condition id
    uint256 yesPositionId;      // ERC-1155 YES position id from CTF
    uint256 noPositionId;       // ERC-1155 NO position id from CTF
    address creator;            // Market creator
    uint64  createdAt;          // Creation timestamp
    uint64  expiryTime;         // When market expires
    uint64  resolutionTime;     // When market was resolved (0 = unresolved)
    uint128 creationFeePaid;    // Protocol fee paid to create the market
    uint128 totalFeePool;       // All fees accrued (single SSTORE per fill)
    uint128 totalQuoteVolume;   // Cumulative taker collateral volume across all curves
    bool    creatorFeesClaimed; // Prevent double-claim
    mapping(address => uint128) makerQuoteVolume; // Per-maker cumulative collateral volume
    mapping(address => uint128) makerFeesClaimed; // Prevent repeat maker claims
    uint8   outcome;            // 0=unresolved, 1=YES, 2=NO, 3=invalid
    uint8   state;              // 0=inactive, 1=trading, 2=pending, 3=resolved, 4=disputed
    uint32  curveCount;         // Number of active curves
}
```

### 3.3 Resolution struct

```solidity
struct Resolution {
    bytes32 marketId;
    address proposer;
    uint8   proposedOutcome;    // 1=YES, 2=NO, 3=invalid
    uint128 ethBond;            // ETH bonded by proposer
    uint128 eveBond;            // EVE bonded by proposer
    uint64  proposedAt;
    uint64  disputeDeadline;    // proposedAt + DISPUTE_WINDOW
    bool    disputed;
    uint8   escalationLevel;    // 0=initial, 1=first dispute, 2=final
}
```

### 3.4 Stored Curve

```solidity
struct StoredCurve {
    uint256 packed;             // Bitpacked curve data
    uint128 remainingVolume;    // Remaining fillable volume
    uint32  generation;         // Incremented on update
    bool    active;             // false = cancelled/expired
    address maker;              // Curve owner
    bytes32 marketId;           // Parent market
    bool    isYesSide;          // true = quote YES shares, false = quote NO shares
}
```

---

## 4. Market Lifecycle

```
CREATE → TRADE → EXPIRE → CREATOR SETTLES → (DISPUTE?) → RESOLVE → SETTLE
  │         │        │      [creator proposes]   │            │         │
  │         │        │      [if honest: done]    │       [outcome      [winners
  │         │        │                           │        fixed]       claim]
  │         │        │                           │
  fee       fill     trading  2hr window          escalate
  paid      curves   stops    for anyone         (if disputed)
                             to challenge
```

**Happy path:** Creator settles honestly. No dispute. Creator earns trading fees. Done.
**Sad path:** Someone catches a dishonest settle → disputes → OBR escalation.

### 4.1 Market Creation

```solidity
function createMarket(
    string calldata question,     // Human-readable market question
    string calldata category,     // "crypto", "sports", etc.
    uint64 expiryTime,            // When the market event occurs
    uint128 initialVolume,        // Initial liquidity to provide
    bool    initialDirection      // true = provide YES liquidity
) external payable returns (bytes32 marketId);
```

**Requirements:**
- `msg.value >= marketCreationFee + initialCurveEscrow` where `marketCreationFee` is a protocol fee and `initialCurveEscrow` is any ETH needed to seed the opening curve
- `expiryTime > block.timestamp + MIN_MARKET_DURATION` (e.g., 1 hour)
- `expiryTime < block.timestamp + MAX_MARKET_DURATION` (e.g., 90 days)
- `collateralToken` is the protocol's configured CTF collateral rail for V1 (WETH)
- Fee rate is global (admin-set `tradingFeeBps`), not per-market

**Actions:**
1. Canonicalize the market question into `questionId`
2. Prepare a binary CTF condition using `prepareCondition(address(this), questionId, 2)`
3. Derive the binary position ids:
   `yesPositionId = getPositionId(collateralToken, getCollectionId(0x0, conditionId, 0b01))`
   `noPositionId = getPositionId(collateralToken, getCollectionId(0x0, conditionId, 0b10))`
4. Route `marketCreationFee` to `EveTreasury`
5. Emit `MarketCreated` event with condition and collateral metadata
6. If `initialVolume > 0`, create the initial maker curve from the creator's opening escrow at 50/50

**CTF note:** V1 uses CTF's ERC-1155 positions as the canonical outcome assets. Frontends may present ETH-native UX, but the protocol's collateral rail is the configured ERC-20 collateral token used for `splitPosition`, `mergePositions`, and `redeemPositions`. V1 should standardize on WETH to preserve ETH-denominated UX while remaining CTF-compatible.

### 4.2 Trading (Curve CLOB)

Makers post curves quoting YES or NO CTF positions against collateral. Takers fill against curves by buying the quoted ERC-1155 outcome side. The collection of active curves forms the orderbook.

**Post a curve:**
```solidity
function postCurve(
    bytes32 marketId,
    bool    isYesSide,        // Quote YES or NO side
    uint128 volume,           // Max outcome shares fillable
    uint72  startPrice,       // Starting price in collateral units per share (fixed-point)
    uint72  endPrice,         // Ending price in collateral units per share (fixed-point)
    uint20  durationMinutes,  // How long the curve is active
    uint16  feeBps,           // Fee for taker
    uint8   profileId         // Curve shape (linear, step, etc.)
) external payable returns (uint256 curveId);
```

**Update a curve (~50k gas):**
```solidity
function updateCurve(
    uint256 curveId,
    uint256 newPacked,           // New bitpacked curve data
    uint32  expectedGeneration   // Prevents front-running
) external;
```

**Fill against a curve:**
```solidity
function fillCurve(
    uint256 curveId,
    uint128 collateralIn,        // collateral token amount the taker is willing to spend
    uint128 minSharesOut,        // minimum ERC-1155 outcome tokens out
    uint32  expectedGeneration,  // Prevents stale fills
    bytes32 expectedCommitment   // Hash of curve params
) external payable returns (uint128 sharesOut);
```

**Fill flow (2 warm SSTOREs for fee tracking):**
1. Compute current price from curve parameters at `block.timestamp`
2. Calculate taker fee: `fee = (collateralIn * tradingFeeBps) / 10000` (global admin-set rate)
3. Calculate net collateral: `netCollateral = collateralIn - fee`
4. Calculate output shares: `sharesOut = netCollateral / price`
5. Verify `sharesOut >= minSharesOut`
6. Pull collateral token from taker
7. Pull maker top-up collateral from the curve reserve: `makerTopUp = sharesOut - netCollateral`
8. Call `ConditionalTokens.splitPosition(collateralToken, 0x0, conditionId, [0b01, 0b10], sharesOut)`
9. Transfer the quoted ERC-1155 position id to taker and credit the complementary ERC-1155 position id to the maker inventory rail
10. Accrue to single pool: `market.totalFeePool += fee` (1 warm SSTORE)
11. Track maker volume: `market.makerQuoteVolume[curve.maker] += collateralIn` (1 warm SSTORE)
12. Track total volume: `market.totalQuoteVolume += collateralIn`
13. Update curve `remainingVolume`
14. Emit `CurveFilled` event with fee amount

**Gas cost:** ~160k per fill (was ~150k). Two extra warm SSTOREs = ~10k gas. Negligible.

**Curve reserve requirement:** When a curve is posted, the maker escrows enough collateral token reserve to fund the worst-case complementary collateral required across the full remaining volume:

`requiredMakerReserve = volume * (1 - min(startPrice, endPrice))`

This reserve is reduced as fills consume maker top-up collateral and is released when the curve is cancelled or expires.

**Quoted asset semantics:**

- YES and NO inventory are CTF ERC-1155 positions, not ERC-20 tokens.
- The quoted side of a curve determines which position id the taker receives.
- The maker's complementary exposure is tracked as the opposite position id produced by the same `splitPosition` call.
- Curves therefore sell CTF inventory while preserving full collateralization through complete-set minting.

### 4.3 Expiry

When `block.timestamp >= market.expiryTime`:
- Trading halts (curve fills revert)
- Market enters `pending` state
- Resolution can be proposed

---

## 5. Optimistic Bonded Resolution (OBR)

### 5.1 Overview

The market **creator** proposes the initial resolution when the market expires. This is the intended happy path: the creator is economically motivated by their creator-fee share and by avoiding forfeiture of that share if they fail to settle or are overturned. If the creator settles correctly and nobody disputes within 2 hours, the market resolves cleanly and the creator earns their accrued creator fees.

Only if someone believes the creator is dishonest does the OBR escalation process activate.

**Resolution priority:**
1. **Creator settles** (no additional bond during the 24-hour creator grace window)
2. **Anyone disputes** (posts counter-bond, escalation begins)
3. **Higher bond rounds** if disputed again
4. **Final escalation → EVE vote**

### 5.2 Part 1 — Creator Settles

```solidity
function settleMarket(
    bytes32 marketId,
    uint8   outcome,              // 1=YES, 2=NO, 3=invalid
    bytes32 evidenceHash          // IPFS hash or on-chain proof
) external;
```

**Who calls:** `msg.sender == market.creator` during the 24-hour `CREATOR_SETTLE_GRACE` after expiry. After that grace window, anyone may open resolution by posting the level-1 dispute bond and proposing an outcome.

**Requirements:**
- Market is in `pending` state (expired, not yet resolved)
- `outcome ∈ {1, 2, 3}`
- `block.timestamp >= market.expiryTime`

**Actions:**
1. Record proposed outcome
2. Start 2-hour dispute window
3. Market enters `pending_resolution` state
4. Creator fee eligibility becomes provisional until the dispute window closes

**If no dispute within 2 hours:**
- Market resolves to creator's proposed outcome
- Creator may claim the accrued creator fee share
- This is the happy path. No additional bond, no escalation, and no refund step.

### 5.3 Part 2 — Dispute (Anyone)

```solidity
function disputeResolution(
    bytes32 marketId,
    uint8   counterOutcome,       // Must differ from proposed
    bytes32 counterEvidenceHash
) external payable;
```

**Who calls:** Anyone. Not restricted to the creator.

**Requirements:**
- Within `proposedAt + DISPUTE_WINDOW` (2 hours)
- `counterOutcome != proposedOutcome`
- `msg.value >= disputeBondETH(escalationLevel)`
- `eveToken.transferFrom(msg.sender, ..., disputeBondEVE(escalationLevel))`

**Dispute bond schedule:**

| Escalation | ETH Bond | EVE Bond |
|------------|----------|----------|
| Level 0 (creator settle) | 0 ETH | 0 EVE |
| Level 1 (first dispute) | 0.1 ETH | 1,000 EVE |
| Level 2 (final dispute) | 0.5 ETH | 5,000 EVE |

**Dispute flow:**
1. New bond is posted by disputer
2. `escalationLevel` increments
3. Dispute deadline extends by `DISPUTE_WINDOW` (2 hours)
4. If escalationLevel reaches `MAX_ESCALATION` (2) and no further dispute → last proposer wins
5. If further dispute at max escalation → market resolves `invalid`

### 5.4 Finalization

**If undisputed:** After `disputeDeadline` passes, anyone can finalize:

```solidity
function finalizeResolution(bytes32 marketId) external;
```

- Proposed outcome becomes final
- If creator proposed and was honest: accrued creator fees become claimable
- If a non-creator proposer won: their bond is returned and any eligible resolver reward is unlocked
- Market state → `resolved`

**If final bonded escalation is still disputed:** Market enters `vote_pending` and resolution escalates to EVE token voting.

### 5.5 Bond Slashing, Creator Fee Forfeiture, and Final Vote

When resolution finalizes:

| Scenario | Creator | Disputer |
|----------|---------|----------|
| Creator honest, no dispute | Creator fee share earned | N/A |
| Creator honest, dispute fails | Creator fee share earned | Disputer bond slashed → treasury |
| Creator dishonest, disputer wins | Creator fee share forfeited | Bond returned + 10% of forfeited creator fees + any slashed portion from loser |
| Creator misses grace, third party resolves | Creator fee share forfeited | Winning proposer may earn resolver reward if they survive challenge |
| Final escalation to EVE vote | Creator fee share depends on vote result | Highest surviving proposer bond returned; creator-fee reward decided by vote outcome |

**Key incentive:** The creator only earns the creator fee share if they perform the initial settlement job and are not overturned. If they lie, fail to appear, or the market fails into invalid, that creator share is forfeited.

Slashed dispute bonds go to the `EveTreasury` address unless the protocol allocates a portion to a winning higher-level proposer. If the creator is overturned, 10% of the forfeited creator fee share is paid to the winning challenger or surviving non-creator resolver and 90% goes to the protocol.

### 5.6 Resolution Failure Modes

**Creator absence**

- The creator has an exclusive `CREATOR_SETTLE_GRACE` window after expiry to post the initial resolution.
- `CREATOR_SETTLE_GRACE` is 24 hours in V1.
- After `expiryTime + CREATOR_SETTLE_GRACE`, anyone may open resolution by posting the level-1 dispute bond and proposing an outcome.
- If no one opens resolution before `OPEN_RESOLUTION_TIMEOUT`, anyone may finalize the market as `invalid`.

**Stalled disputes**

- Every live proposal has a bounded `disputeDeadline`.
- If the current proposal is undisputed when the deadline passes, anyone may finalize it.
- If a proposal is disputed at `MAX_ESCALATION`, the market enters EVE-vote final escalation instead of auto-invalidating.

**Final constitutional backstop**

- The final layer is **EVE token voting**.
- The vote chooses between `YES`, `NO`, or `INVALID`.
- The winning vote result is used to finalize the CTF payout vector through the protocol's oracle surface.
- This vote is the constitutional backstop, not the normal path.

**Creator fee treatment when absent**

- If the creator never appears and the market resolves cleanly from a third-party proposal, the creator forfeits the creator fee share for that market.
- If the market reaches timeout-invalid with no usable settlement path, the creator fee share is forfeited to treasury.

---

## 6. Settlement

### 6.1 Claim Winnings

```solidity
function claimWinnings(bytes32 marketId) external;
```

After resolution:
- The protocol reports the final payout vector into CTF using `reportPayouts`
- Users redeem ERC-1155 positions through `ConditionalTokens.redeemPositions`
- If outcome = YES: payout vector is `[1, 0]`
- If outcome = NO: payout vector is `[0, 1]`
- If outcome = INVALID: payout vector is `[1, 1]`, so each binary position redeems `0.5` units of collateral per token

### 6.2 Outcome Token Mechanics

YES and NO exposure is represented by CTF ERC-1155 position ids:

- `yesPositionId = getPositionId(collateralToken, getCollectionId(0x0, conditionId, 0b01))`
- `noPositionId = getPositionId(collateralToken, getCollectionId(0x0, conditionId, 0b10))`
- One complete set is `1 YES + 1 NO`, fully backed by `1` unit of collateral token
- A taker fill never mints an unpaired token
- For a YES-side fill at price `P`, the taker contributes `P` units of collateral per share and the maker reserve contributes `(1-P)`
- For a NO-side fill at price `P`, the taker contributes `P` units of collateral per share and the maker reserve contributes `(1-P)`
- The quoted ERC-1155 position id is transferred to the taker; the complementary position id is credited back to maker inventory
- After resolution, redemption uses CTF payout vectors rather than custom market token burn logic

This is the standard conditional token framework adapted to a curve-based onchain execution layer.

### 6.3 Collateral and Liability Model

The solvency invariant for V1 is:

`totalEscrowedCollateral >= winningClaims + invalidClaims`

Operationally:

1. Every token mint occurs through complete-set creation, never through single-sided minting.
2. Every live outcome token is therefore backed by exactly one half of a complete set.
3. Curve execution consumes taker collateral plus maker-reserved collateral to create a fully collateralized complete set through CTF `splitPosition`.
4. Fees are carved out of taker collateral before mint sizing, so fee extraction never creates undercollateralized claims.
5. Invalid resolution uses the payout vector `[1,1]`, so each binary token redeems `0.5` units of collateral and a complete set still redeems for exactly `1`.

This avoids per-wallet cost-basis tracking and keeps redemption deterministic even when holders acquired shares at different market prices.

---

## 7. EVE Token Integration

### 7.1 EVE Requirements

| Action | EVE Required | Locked? |
|--------|-------------|---------|
| Create market | 0 EVE | No |
| Creator settle | 0 EVE | No |
| Dispute resolution (L0→L1) | 1,000 EVE | Yes (until finalized) |
| Dispute resolution (L1→L2) | 5,000 EVE | Yes (until finalized) |
| Post curve | 0 EVE | No |
| Fill curve | 0 EVE | No |
| Claim winnings | 0 EVE | No |

### 7.2 Revenue Flows — FeeRouter Split

**Single global fee** (`tradingFeeBps`, admin-set, same for all markets) is deducted on every fill. No per-market fee configuration. The fee pool is split on settlement, not on each trade.

**Fee split (FeeRouterFacet — immutable after freeze):**

| Recipient | Share | How |
|-----------|-------|-----|
| Protocol (EveTreasury) | 10% + market creation fees | Creation fee routed immediately; trading-fee share auto-credited on `finalizeResolution()` |
| Market Creator | 5% | Lazy claim via `claimCreatorFees(marketId)` only if the creator settles within grace and is not overturned |
| Market Makers | 85% | Lazy claim via `claimMakerFees(marketId)` — proportional to quote volume |

**On each trade (no split, just accrue):**
- `market.totalFeePool += fee` — one warm SSTORE
- `market.makerQuoteVolume[maker] += collateralIn` — one warm SSTORE
- `market.totalQuoteVolume += collateralIn` — included in existing storage write

**On settlement (FeeRouter splits the pool):**

```solidity
// Auto-credited on finalizeResolution()
protocolShare = (market.totalFeePool * PROTOCOL_FEE_BPS) / 10000;  // 10%
EveTreasury.transfer(protocolShare);

// Lazy claim by creator
creatorShare = (market.totalFeePool * CREATOR_FEE_BPS) / 10000;  // 5%
// Only claimable if creator settled within grace and their proposal was not overturned

// Lazy claim by each market maker
makerPool = market.totalFeePool - protocolShare - creatorShare;  // 85%
// Each maker claims: (their volume / total volume) * makerPool
```

**MM claim math (deterministic, no iteration):**
```
makerEntitled = (market.makerQuoteVolume[msg.sender] * makerPool) / market.totalQuoteVolume
makerShare = makerEntitled - market.makerFeesClaimed[msg.sender]
```

Each maker calls `claimMakerFees(marketId)` independently. The contract records `makerFeesClaimed[msg.sender]` after each payout so the same share cannot be claimed twice. No batch processing or merkle proofs are required.

**Creator fee forfeiture:**
- If creator settles honestly during grace and is not overturned: gets 5%
- If creator is caught lying: forfeits their 5% to the winning non-creator proposer or protocol treasury
- If creator misses grace entirely: forfeits their 5%
- MMs always get their 85% regardless of creator honesty — they provided liquidity in good faith
- Protocol gets 10% + market creation fees + any forfeited creator share not paid as resolver reward + slashed dispute bonds

**Revenue sources:**
- Market creation fees → EveTreasury
- Protocol trading fees (10% of all fills) → EveTreasury
- Forfeited creator fees (dishonest, absent, or invalid creator path) → EveTreasury
- Slashed dispute bonds → EveTreasury
- Creator fees (5% of fills) → creator (if honest)
- MM fees (85% of fills) → market makers (always)

## 8. Event-Driven State

### 8.1 Core Events

```solidity
// Market lifecycle
event MarketCreated(
    bytes32 indexed marketId,
    bytes32 indexed conditionId,
    address indexed creator,
    address collateralToken,
    uint256 yesPositionId,
    uint256 noPositionId,
    string question,
    uint64 expiryTime
);
event MarketExpired(bytes32 indexed marketId);
event MarketResolved(bytes32 indexed marketId, uint8 outcome);
event MarketSettled(bytes32 indexed marketId);

// Curve CLOB
event CurvePosted(bytes32 indexed marketId, uint256 curveId, address maker, bool isYesSide, uint256 packed);
event CurveUpdated(uint256 indexed curveId, uint256 newPacked, uint32 generation);
event CurveFilled(uint256 indexed curveId, address indexed maker, address taker, uint128 collateralIn, uint128 sharesOut, uint128 fee);
event CurveCancelled(uint256 indexed curveId);
event CurveExpired(uint256 indexed curveId);

// OBR Resolution
event CreatorSettled(bytes32 indexed marketId, uint8 outcome, bytes32 evidenceHash);
event ResolutionDisputed(bytes32 indexed marketId, address disputer, uint8 counterOutcome, uint8 escalationLevel);
event ResolutionFinalized(bytes32 indexed marketId, uint8 outcome);
event BondSlashed(bytes32 indexed marketId, address slashedAddress, uint128 ethAmount, uint128 eveAmount);
event CreatorFeesForfeited(bytes32 indexed marketId, uint128 amount);
event MakerFeesClaimed(bytes32 indexed marketId, address indexed maker, uint128 amount);
event CreatorFeesClaimed(bytes32 indexed marketId, uint128 amount);

// Settlement
event WinningsClaimed(bytes32 indexed marketId, address claimer, uint128 amount);
```

### 8.2 Off-Chain Indexer Requirements

UIs should index:
1. All `CurvePosted`/`CurveUpdated`/`CurveFilled`/`CurveCancelled` events → reconstruct full orderbook
2. All `MarketCreated` events → market listing
3. All resolution events → market status
4. CTF `ConditionPreparation`, `PositionSplit`, and `PayoutRedemption` events for reconciliation
5. Compute aggregated views: best bid/ask, depth, spread, volume

Events should drive discovery, history, and analytics. Executable trading state should still be read from view functions immediately before fill submission.

Required view surface:

- `getCurveCommitment(curveId) → (generation, commitment)`
- `previewCurveQuote(curveId, collateralIn) → sharesOut, fee, price, makerTopUp`
- `getMarketStatus(marketId) → state, outcome, disputeDeadline, totalFeePool`
- `previewMakerFees(marketId, maker) → entitled, claimed, claimable`
- `getMarketPositions(marketId) → conditionId, collateralToken, yesPositionId, noPositionId`

---

## 9. Storage Layout

```solidity
struct EveMarketStorage {
    // ── Market Registry ──
    mapping(bytes32 => Market) markets;
    bytes32[] marketIds;
    uint256 marketCount;

    // ── Curves ──
    mapping(uint256 => StoredCurve) curves;
    uint256 nextCurveId;
    mapping(bytes32 => uint256[]) marketCurves;     // marketId → curve IDs
    mapping(address => uint256[]) makerCurves;       // maker → curve IDs

    // ── OBR Resolution ──
    mapping(bytes32 => Resolution) resolutions;      // marketId → active resolution
    mapping(bytes32 => Resolution[]) resolutionHistory; // marketId → all proposals

    // ── Resolution Bonds ──
    mapping(address => uint128) eveResolutionBonded;  // user → total EVE bonded in live disputes
    mapping(address => uint128) ethResolutionBonded;  // user → total ETH bonded in live disputes

    // ── Config ──
    address conditionalTokens;
    address eveToken;
    address eveTreasury;
    uint128 marketCreationFee;      // Flat protocol fee to create a market
    uint128 disputeBondEthL1;
    uint128 disputeBondEthL2;
    uint128 disputeBondEveL1;
    uint128 disputeBondEveL2;
    uint16  tradingFeeBps;          // Global trading fee (set by admin, e.g., 100 = 1%)
    uint16  protocolFeeBps;         // Protocol share of trading fee (1000 = 10%)
    uint16  creatorFeeBps;          // Creator share of trading fee (500 = 5%)
    uint16  makerFeeBps;            // Maker share of trading fee (8500 = 85%)
    uint16  resolverRewardBps;      // Share of forfeited creator fees paid to winning non-creator proposer
    uint64  minMarketDuration;
    uint64  maxMarketDuration;
    uint64  disputeWindow;          // default: 2 hours
    uint64  creatorSettleGrace;     // creator-only initial settlement window (24 hours in V1)
    uint64  openResolutionTimeout;  // invalid fallback if nobody opens resolution
    uint8   maxEscalation;          // default: 2
    bool    frozen;                 // global freeze flag

    // ── Facet Freeze ──
    mapping(bytes4 => bool) frozenSelectors;
}
```

Storage slot: `keccak256("eve.prediction.market.storage") - 1`

---

## 10. Gas Estimates

| Operation | Gas (estimated) | Notes |
|-----------|-----------------|-------|
| Create market | ~250k | Prepare CTF condition, route creation fee, store market data |
| Post curve | ~120k | Store packed uint256 + collateral lock |
| Update curve | ~50k | Single SSTORE + event |
| Fill curve | ~160k | `splitPosition` + ERC-1155 transfers + curve update + 2 warm SSTOREs for fee tracking |
| Propose resolution | ~100k | Store resolution + lock bonds |
| Dispute resolution | ~100k | Escalate + lock higher bonds |
| Finalize resolution | ~80k | Set outcome, report CTF payouts, emit event |
| Claim winnings | ~90k | Redeem ERC-1155 positions via CTF |

---

## 11. Security Considerations

### 11.1 Curve Front-Running

- **Protection:** `expectedGeneration` + `expectedCommitment` params on fill. If the curve was updated between the taker's view and execution, the tx reverts.
- **Maker can update** price in ~50k gas, but takers always fill against the on-chain state at execution time.

### 11.2 Resolution Manipulation

- **Bond escalation** makes it exponentially expensive to repeatedly dispute
- **Time-bound** dispute windows prevent indefinite stalling
- **Constitutional backstop:** final escalation routes to EVE token voting rather than leaving the market unresolved.

### 11.3 Market Creation Spam

- **Protocol creation fee** filters spam without forcing locked capital.
- **Flat, reasonable cost** keeps market creation low-friction while still making spam expensive at scale.
- **Creator reputation** (future): repeated invalid or abandoned markets can justify a higher creation fee tier.

### 11.4 Invalid Outcome Edge Cases

- Market resolves invalid → each YES and each NO redeems for `0.5` collateral units through the CTF payout vector `[1,1]`
- A complete set still redeems for exactly `1` collateral unit
- No per-wallet mint-price tracking is required
- Slashed dispute bonds and unresolved-resolution penalties still go to treasury as operational cost

### 11.5 ERC-1155 / CTF Integration Risks

- Curve execution must validate the expected YES/NO position ids for the market's `conditionId` and `collateralToken`.
- The protocol must handle ERC-1155 safe transfer acceptance correctly for any internal inventory custody path.
- `reportPayouts` must only be callable through the protocol's authorized oracle surface for that prepared condition.
- Split, merge, and redeem flows must never mix condition ids or collateral tokens across markets.

---

## 12. Deployment Plan

1. Deploy `EveMarketDiamond` with all facets
2. Configure: ConditionalTokens address, EVE token address, treasury, market creation fee, dispute bond parameters
3. Verify all facets on Arbiscan
4. Run audit (Pashov skill + manual pass)
5. Freeze `CurveCLOBFacet`, `OBRResolutionFacet`, `MarketSettlementFacet`, `FeeRouterFacet`
6. Open for public market creation

---

## Appendix A: Curve Profile System

Profiles define how price moves from `startPrice` to `endPrice` over `duration`:

| Profile ID | Shape | Use Case |
|------------|-------|----------|
| 0 | Linear | Default. Even price progression. |
| 1 | Step | Flat price, jumps at midpoint. |
| 2 | Exponential decay | Starts high, decays to end. Good for time-sensitive markets. |
| 3 | Custom | External contract implements `ICurveProfile`. |

Profile contract interface:
```solidity
interface ICurveProfile {
    function computePrice(
        uint128 startPrice,
        uint128 endPrice,
        uint64  startTime,
        uint64  duration,
        uint64  currentTime,
        bytes32 profileParams
    ) external view returns (uint128 price);
}
```

Profiles are registered and approved by owner, then frozen after audit.

---

## Appendix B: Comparison with Polymarket

| Feature | Polymarket | EVE Markets |
|---------|------------|-------------|
| Chain | Polygon | Base |
| Trading | CLOB (off-chain matcher) | On-chain curve CLOB |
| Resolution | UMA Optimistic Oracle | On-chain OBR with final EVE vote |
| Market creation | Free (via API) | Protocol creation fee |
| Token utility | None | EVE required for dispute escalation |
| Outcome asset | ERC-1155 conditional tokens | CTF ERC-1155 position ids |
| Collateral efficiency | Idle in positions | Maker-backed complete-set minting |
| Orderbook | Off-chain relayer | On-chain curves + event-driven index |
| Liquidity | External AMM + orderbook | Maker curves (intent-based) |

---

*This spec is a living document. Version 0.4.0-draft for review.*
