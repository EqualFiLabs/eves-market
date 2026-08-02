# Beta Combinatorial Positions Spec

**Status:** Beta design spec
**Date:** 2026-05-23
**Owner:** Eves Market protocol
**Scope:** Orderbook CTF-style markets only. Alpha CLOB launch remains unchanged.

## 1. Intent

Alpha should ship with the current orderbook/CLOB system so we can collect real
maker behavior, update cadence, fill quality, gas, and UX data. The CLOB metrics
are still useful because beta combo markets will reuse the same maker concepts:
inventory, prices, curve updates, taker fills, fees, and portfolio accounting.

Beta is the product-parity push against Polymarket v2-style combinatorial
positions. This spec captures the beta architecture so the alpha release does
not block on CTF redesign, while the beta work has a concrete target.

## 2. Product Goal

Users and makers should be able to trade complete probabilistic scenarios:

```text
YES(A) AND YES(B) AND NO(C)
```

The position should be:

- a single ERC1155 balance
- backed by one unit of collateral per complete YES/NO pair
- tradeable in dedicated combo/branch books
- decomposable through exact split, merge, compression, and complement flows
- redeemable from the same resolution outcomes as the underlying markets
- expressive enough for 50-leg scenarios

These are "parlays" in user language, but not traditional sportsbook parlays.
The precise product term is a decomposable scenario position. If a leg resolves
against an exact `AND` branch, that exact branch can be worth zero; the position
can stay economically useful only when the holder can compress winning resolved
legs, owns complementary branches, or can acquire missing branches from makers.

## 3. Alpha/Beta Boundary

Alpha remains:

- current orderbook markets
- current CLOB maker flows
- parimutuel markets
- spot ERC20 DEX surface
- current Base Sepolia alpha deployment and docs

Beta adds:

- a clean-room ERC1155 position manager
- binary and combinatorial position modules/facets
- dedicated combo/branch orderbooks for ERC1155 scenario inventory
- compression, extraction, complement, and wrap/unwrap UX
- maker-created combo products and creator reputation surfaces

Beta does not require alpha market migration. Treat beta as a redeploy or a new
position layer unless a later migration plan is explicitly designed.

## 4. Core Architecture Decision

For pure competition and product parity, do not build beta around raw Gnosis CTF
as the final user-facing position layer.

Use Gnosis CTF as a semantic reference and compatibility benchmark, but build an
Eves-native position layer:

```text
EvesPositionManager ERC1155
  - BinaryMarketModule
  - NegRiskModule, if needed later
  - CombinatorialModule

Diamond / Protocol Facets
  - market creation and resolution
  - orderbook/CLOB trading
  - combo/branch books
  - fee routing
  - portfolio/indexer events
```

Reasoning:

- Raw Gnosis CTF is excellent for conditional token algebra, but it does not
  give us a modern module system with controlled mint/burn authority, clean
  compression helpers, callbacks, bridge roles, or product-specific events.
- Polymarket v2 appears to have moved toward a custom modular position manager
  that preserves CTF-like semantics without depending on raw Gnosis CTF as the
  primary token contract.
- Product parity requires the higher-level operations users and makers care
  about: `splitOnCondition`, `extract`, `compress`, `wrap`, `unwrap`, curated
  combo books, and top-up/complement flows.
- A clean-room implementation avoids copying BUSL code and lets us shape storage,
  events, tests, and indexer behavior around Eves Market.

## 5. Non-Negotiable Accounting Invariants

1. One unit of collateral backs one complete binary partition.
2. `YES(P) + NO(P)` can merge back into one collateral unit.
3. `YES(A AND B)` pays at most one collateral unit, not one unit per leg.
4. A combo trade price can be above a fair probability estimate, but must not
   exceed the maximum redeemable payout for one unit.
5. A losing exact `AND` branch does not magically preserve residual value.
6. Moving upward in the tree requires the complete sibling/complement branch set.
7. All position minting and burning must go through authorized modules.
8. Every state transition must be callable by someone with a clear reason to pay
   gas. No protocol behavior should assume automatic execution.

## 6. Position Model

### 6.1 IDs

Use explicit typed concepts even if encoded as `uint256` onchain:

```solidity
type ConditionId is bytes32;
type PositionId is uint256;
```

Position IDs should encode or derive:

- module id
- condition id
- outcome index

Required module ids:

- `BINARY`: normal two-outcome orderbook markets
- `COMBINATORIAL`: multi-leg scenario positions

Future module ids:

- `NEGRISK`: mutually exclusive outcome sets
- `PARIMUTUEL`: only if we later decide parimutuel shares should be composable

For beta, combinatorial positions should only reference started orderbook markets.
Do not include parimutuel markets in combo construction.

### 6.2 Legs

```solidity
struct ComboLeg {
    bytes32 marketId;
    uint256 positionId;
}
```

The leg's `positionId` represents the exact binary branch being included:

```text
A.YES
A.NO
B.YES
B.NO
```

Leg arrays must be canonical:

- non-empty
- length <= 50
- sorted by underlying market/condition identity and branch identity
- no duplicate market condition
- no contradictory pair like `A.YES` and `A.NO` in the same conjunction
- every referenced market is started and unresolved at creation time
- every referenced market uses the same collateral token

### 6.3 Combo Conditions

```solidity
struct ComboCondition {
    PositionId[] legs;
    uint64 preparedAt;
    bool exists;
}
```

`conditionId = keccak256(abi.encode(moduleId, canonicalLegs))`

The condition store is an indexer and validation aid. Position correctness comes
from mint/burn invariants, not metadata.

## 7. Core Contracts and Facets

### 7.1 EvesPositionManager

ERC1155 token contract responsible for balances and approvals.

Responsibilities:

- mint and burn positions only for authorized modules
- batch mint and batch burn
- ERC1155 safe transfer compatibility
- operator approvals for orderbooks and helper contracts
- optional URI support, but metadata is not correctness-critical

The position manager should not own market rules. It is the token ledger.

### 7.2 BinaryMarketModule

Responsibilities:

- create binary conditions from Diamond market creation
- split collateral into YES/NO
- merge YES/NO into collateral
- resolve conditions from the existing resolution path
- expose payout result for each condition
- redeem resolved positions

This replaces raw CTF behavior for beta orderbook markets.

### 7.3 CombinatorialModule

Responsibilities:

- prepare canonical combo conditions
- split collateral into `YES(combo)` and `NO(combo)`
- merge `YES(combo)` and `NO(combo)` into collateral
- split a YES combo on a new binary condition
- merge child YES combos back into a parent YES combo
- extract a leg from a NO combo
- inject a leg back into a NO combo
- convert a NO combo to its canonical YES basket
- merge a canonical YES basket back into a NO combo
- compress resolved legs
- redeem final resolved combo positions
- wrap and unwrap single-condition combo positions

The function names can mirror the known v2 semantics, but implementation must be
clean-room and built from our own storage and tests.

### 7.4 ComboBookFacet

Do not use the Spot DEX for combo positions. Spot is ERC20-only.

Add a dedicated ERC1155 combo/branch book surface:

```text
base asset:  EvesPositionManager ERC1155 positionId
quote asset: eveUSD
```

Responsibilities:

- create books for exact combo branches
- create books for sibling/complement branches
- allow makers to post branch inventory asks
- allow makers/users to post collateral-backed bids
- support flat quotes and curve quotes if the CLOB engine is generalized
- route fills through the same fee accounting style as orderbook markets
- emit book and fill events that the indexer can follow without decoding token
  metadata

This is the primary liquidity model. We should not claim instant executable
liquidity from the underlying binary books.

## 8. User-Facing Flows

### 8.1 Curated Combo Creation

Makers and creators can create scenario products:

```text
"Creator X macro combo"
  YES(Election outcome)
  AND YES(BTC above threshold)
  AND NO(Fed path outcome)
```

Flow:

1. Creator selects started orderbook markets and branches.
2. Protocol canonicalizes legs and prepares the combo condition.
3. Creator either mints combo inventory or posts a collateral-backed bid.
4. Creator opens a combo book.
5. Buyers buy the combo ERC1155 position from that book.

This creates a market for people who are known for building good scenario
packages. The creator's reputation and book history become part of the product.

### 8.2 Buyer Purchase

Flow:

1. User opens a combo book.
2. UI shows legs, status, max payout, book depth, creator, and implied payout.
3. User buys ERC1155 combo inventory with eveUSD.
4. User receives one ERC1155 combo balance.

The price is set by makers. The UI can show implied independent pricing, but the
execution price is the maker's quote.

### 8.3 Complement Top-Up

If a user holds a branch and needs a sibling branch to merge upward:

```text
User holds: A.YES AND B.YES
Needs:      A.YES AND B.NO
Goal:       merge back into A.YES
```

Minimal beta flow:

1. UI computes the missing sibling branch.
2. User posts a bid/reward for that branch in the relevant combo book.
3. Maker fills by selling the sibling branch.
4. User calls merge manually.

Improved beta flow:

```text
fillComplementAndMerge(...)
```

The maker supplies the sibling, receives the reward, and the helper merges both
branches into the parent for the user in one transaction.

### 8.4 Compression

Compression removes resolved legs when the outcome allows it.

Example:

```text
Holder owns: YES(A AND B AND C)
B resolves true
Output: YES(A AND C)
```

If a YES combo has a resolved false leg, the exact YES combo is worth zero.

For NO/complement positions:

```text
NO(A AND B AND C)
```

If any leg makes the full conjunction impossible, the NO position may become
fully or partially redeemable depending on remaining unresolved legs and payout
math.

## 9. Pricing Rules

Core payout tokens have a hard economic bound:

```text
0 <= price <= 1 collateral unit
```

An 8-leg combo is not priced above one dollar because it has eight legs. It is a
single claim that pays at most one collateral unit if the whole scenario wins.
The upside comes from buying a low-probability scenario below one dollar.

Makers can charge a premium above implied fair probability:

```text
independent fair probability = 0.18
maker ask = 0.24
```

Makers cannot rationally sell the core payout token for `1.25` if max payout is
`1.00`; the protocol should reject prices above the payout cap in combo books.

If we want "each leg requires collateral" later, that is a separate product:

- basket of individual positions
- all-or-nothing escrowed pack
- sponsored/boosted payout wrapper

It should not be mixed into the core CTF-style combo model.

## 10. Liquidity Model

Beta combo liquidity comes from maker-owned inventory and collateral-backed bids.

Supported sources:

- makers split collateral into combo YES/NO pairs and sell one side
- makers split/merge/recycle child branches as outcomes evolve
- users post bids for missing complements
- creators curate combo books and update quotes over time
- arbitrageurs buy/sell between binary books and combo books when prices diverge

Unsupported claim:

- "Every combo has instant liquidity from binary books."

Synthetic routing from binary books can be researched later, but it should not be
the beta promise. The beta promise is executable book liquidity for exact
scenario inventory.

## 11. Fees

Combo books should use a separate fee config from:

- normal orderbook markets
- parimutuel markets
- spot ERC20 trading

Suggested config names:

```text
COMBO_TRADE_FEE_BPS
COMBO_MAKER_FEE_BPS
COMBO_CREATOR_FEE_BPS
COMBO_PROTOCOL_FEE_BPS
COMBO_VAULT_FEE_BPS
COMBO_BOOK_CREATION_FEE
```

Creator fees make sense for combo books because curated combo construction is a
product surface. This is different from ERC20 Spot, where creator fees were
removed because the code did not support a meaningful creator role.

Fee shares must sum to the total trade fee distribution exactly.

## 12. Resolution

Underlying orderbook markets resolve through the existing resolution path.
Combos do not need separate oracle questions.

Required data from each underlying condition:

- unresolved
- resolved YES payout
- resolved NO payout
- invalid/refund state, if supported

Combo payout:

- YES combo payout is the product of referenced leg payouts.
- NO combo payout is the complement of the full conjunction.
- Compressing resolved legs should preserve value and apply deterministic
  rounding rules.

Use high-precision internal math for payout products. Round YES conservatively
down and NO conservatively in the way that preserves collateral solvency.

## 13. Frontend and Indexer Requirements

Frontend:

- combo builder for started orderbook markets
- creator combo pages/books
- max payout and current ask/bid display
- clear "parlay-like, not traditional parlay" copy
- exact branch status per leg
- complement-needed action when a merge requires missing branches
- compression and redemption buttons
- portfolio grouping for combo positions and child branches

Indexer:

- index prepared combo conditions
- index leg arrays from events
- index combo book creation
- index ERC1155 transfers for position balances
- index combo fills and fee events
- derive leg status from underlying market resolution events
- expose missing-sibling/complement hints for the UI

Do not depend on wallet metadata for correctness.

## 14. Security and Solvency Requirements

- No module can mint positions without an equal burn, collateral lock, or
  authorized resolution payout path.
- Split/merge/redeem paths must be reentrancy-safe.
- ERC1155 callbacks must not allow state/accounting reentry.
- Max legs must be enforced at 50.
- Canonical ordering must prevent duplicate condition definitions.
- Conflicting legs must revert.
- All batch operations must have bounded loops.
- Rounding must never overpay collateral across all positions.
- Book fills must verify the seller owns or has escrowed the exact `positionId`.
- Complement helper flows must be atomic or leave user funds unchanged.
- Permissioned module roles must be minimal and auditable.

## 15. Test Requirements

Contract tests must cover real value-moving flows, not only harness shortcuts.

Required live-style flows:

- deploy position manager and modules
- create binary markets
- split collateral into binary YES/NO
- prepare 2-leg, 3-leg, 10-leg, and 50-leg combos
- split collateral into combo YES/NO
- merge combo YES/NO back into collateral
- split a parent YES combo on a new condition
- merge child YES combos back to parent
- extract and inject a NO combo leg
- convert NO combo to YES basket and merge back
- wrap and unwrap single-condition combos
- resolve an underlying leg true and compress
- resolve an underlying leg false and verify exact YES branch is zero
- redeem fully resolved YES and NO combos
- create combo book, post inventory, fill taker buy
- post complement bid, maker fills, user merges upward
- verify 50-leg gas stays within the target chain block gas budget

Fuzz/invariant coverage:

- split/merge conservation
- no collateral overpayment
- canonical leg uniqueness
- no duplicate/conflicting legs
- total payout bounds
- compression equivalence before/after resolution

## 16. Implementation Tracks

### Track A: Position Layer

- Implement `EvesPositionManager` ERC1155.
- Implement authorized module mint/burn roles.
- Implement binary split, merge, resolution, and redemption.
- Prove parity with current binary market behavior.

### Track B: Combinatorial Module

- Implement canonical leg storage and condition derivation.
- Implement split/merge, split-on-condition, merge-on-condition.
- Implement extract/inject and YES basket conversion.
- Implement compression and redemption.
- Enforce 50-leg cap.

### Track C: Combo Books

- Add dedicated ERC1155 combo/branch books.
- Support maker inventory asks and collateral-backed bids.
- Add complement bid and fill-and-merge helper.
- Add independent combo fee config.

### Track D: UI and Indexer

- Add combo builder and creator combo pages.
- Add portfolio grouping, compression, redemption, and complement UX.
- Add indexer tables/events for combo conditions, books, and fills.

### Track E: Beta Deployment

- Deploy fresh beta contracts on Anvil.
- Run full smoke flows with cast/scripts.
- Deploy beta to Base Sepolia.
- Record addresses separately from alpha deployment docs.
- Keep alpha docs and metrics intact.

## 17. Acceptance Criteria

Beta is ready for user testing when:

- 50-leg combo preparation works.
- 50-leg split or documented paginated preparation path works within Base limits.
- Makers can create and sell combo inventory from dedicated combo books.
- Users can buy, hold, transfer, compress, and redeem combos.
- Users can acquire missing complements through books or helper flows.
- Exact losing `AND` branch behavior is clear in UI.
- No public docs claim synthetic instant liquidity from binary books.
- CLOB alpha metrics remain usable for maker tooling and fee calibration.

## 18. Explicit Non-Goals

- Blocking alpha release.
- Migrating alpha CTF balances.
- Using raw Gnosis CTF as the final beta position manager.
- Copying Polymarket v2 code.
- Treating combo books as ERC20 Spot books.
- Supporting parimutuel combos in beta.
- Charging more than max payout for a core combo claim.
- Claiming a combo always survives a dead leg.

## 19. Open Questions

- Should combo books support time-varying curve orders immediately, or start with
  flat ERC1155 bids/asks and generalize after beta data?
- Should `NO(combo)` be first-class in the UI, or mostly exposed through advanced
  trader flows?
- Should creator reputation be onchain, indexed offchain, or both?
- Should book creation require a creation fee, an EVE bond, or both?
- Should invalid/refund outcomes compress as full payout, zero payout, or a
  proportional payout depending on the market policy?
