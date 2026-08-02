# Native Combinatorial Position Layer Spec

**Status:** Draft
**Date:** 2026-05-28
**Owner:** Eves Market protocol
**Scope:** Clean-room beta design for Polymarket-v2-style decomposable scenario positions, native ERC1155 position accounting, combo books, and future multioutcome support.
**Non-scope:** Copying external code, replacing peer-to-peer parlay underwriting, migrating alpha balances, or changing the alpha CLOB launch plan.

---

## 1. Intent

Eves Market should support two distinct "parlay" products:

1. **Peer-to-peer parlay underwriting:** fixed-premium, fixed-payout tickets written by makers or requested by buyers.
2. **Native combinatorial positions:** decomposable ERC1155 scenario tokens that behave like CTF-style multi-leg positions and can be split, merged, compressed, redeemed, and traded.

This spec covers the second product.

The goal is feature parity with the behavior pattern of Polymarket v2 combinatorial positions, implemented clean-room for Eves Market:

```text
YES(A) AND NO(B) AND YES(C)
```

as one ERC1155 position that:

- pays at most one collateral unit,
- is backed by collateral through complete partition accounting,
- can be traded in dedicated ERC1155 orderbooks,
- can be decomposed into related branches,
- can be compressed as legs resolve,
- can be redeemed from existing market outcomes,
- can support up to 50 legs.

The product language can call these "Parlays" because that is how users think about them. The protocol primitive is more precise: **decomposable scenario positions**.

---

## 2. Current System Boundary

### 2.1 What We Already Have

Current Eves Market alpha/beta work includes:

- orderbook markets,
- parimutuel markets,
- ERC20 spot trading,
- curve/flat order CLOB mechanics,
- Gnosis CTF-compatible orderbook market support,
- limited combo position derivation through current CTF position IDs,
- peer-to-peer parlay underwriting tickets.

The current peer-to-peer parlay system is valuable, but it is not the same primitive as decomposable scenario positions.

### 2.2 What This Adds

This design adds a native position layer:

```text
EvesPositionManager ERC1155
  - BinaryPositionModule
  - CombinatorialPositionModule
  - NegRiskPositionModule, later

Eves CLOB
  - normal orderbook markets
  - ERC1155 scenario books
  - ERC1155 parlay ticket books
```

This becomes the beta/v2 position framework for scenario trading.

### 2.3 What We Should Not Do

Do not try to reach feature parity by only extending raw Gnosis CTF usage.

Gnosis CTF is a useful semantic reference, but product parity needs higher-level operations and events:

- canonical condition preparation,
- split/merge helpers,
- branch extraction,
- NO-basket conversion,
- compression,
- single-leg wrapping/unwrapping,
- dedicated book creation,
- clear indexer support.

The native layer lets us implement those behaviors directly and safely.

---

## 3. Product Model

### 3.1 Core Scenario

A scenario position is a conjunction of exact branches:

```text
YES(Lakers win)
AND NO(Celtics win)
AND YES(BTC above threshold)
```

The position has one max payout:

```text
max payout = 1 collateral unit per share
```

An eight-leg position is not worth eight dollars because it has eight legs. It is a single one-dollar max payout claim whose probability may be low.

### 3.2 YES and NO Meaning

For a combo condition `P = A AND B AND C`:

```text
YES(P) = A and B and C all happen
NO(P)  = not(A and B and C)
```

Important distinction:

```text
NO(A AND B AND C) != NO(A) AND NO(B) AND NO(C)
```

The NO side is the complement of the whole scenario, not a conjunction of individual NO legs.

### 3.3 "Position Stays Alive" Nuance

Marketing copy must be careful.

If a YES combo contains a resolved losing leg, that exact YES branch is worth zero.

A user may still preserve or recover value only if they can:

- compress winning resolved legs,
- hold a NO/complement branch,
- acquire missing sibling branches,
- merge upward into a parent branch,
- sell remaining valuable related inventory.

The protocol should never imply that an exact losing AND branch magically survives.

---

## 4. Architecture

### 4.1 EvesPositionManager

`EvesPositionManager` is the ERC1155 ledger for native scenario positions.

Responsibilities:

- hold ERC1155 balances,
- expose standard ERC1155 approvals and transfers,
- mint and burn only for authorized modules,
- support batch mint and batch burn,
- dispatch payout lookups to modules where needed,
- expose module registration,
- expose cross-module mint/burn authorization for wrap/unwrap flows.

The position manager should not contain market rules. It is the accounting ledger.

### 4.2 Module Registry

Each position belongs to one module family.

Required module ids:

| Module | Purpose |
| --- | --- |
| `BINARY` | Normal two-outcome prediction market conditions. |
| `COMBINATORIAL` | Multi-leg conjunction and complement positions. |

Future module ids:

| Module | Purpose |
| --- | --- |
| `NEGRISK` | Mutually exclusive multioutcome sets. |
| `PARIMUTUEL` | Only if we later make parimutuel shares composable positions. |

The first beta version should support orderbook/binary markets inside combinatorial positions. Peer-to-peer parlay underwriting can continue to support both orderbook and parimutuel legs because it settles from final outcomes rather than splitting ERC1155 collateral partitions.

### 4.3 Position ID Model

Every native position must derive from:

- module id,
- condition id,
- outcome index.

Suggested conceptual types:

```solidity
type ConditionId is bytes32;
type PositionId is uint256;
```

The concrete encoding can be chosen during implementation, but it must provide:

- deterministic local calculation,
- no collision across modules,
- cheap module id extraction,
- cheap condition id extraction or lookup,
- cheap outcome index extraction.

### 4.4 Collateral

The native position layer should use `eveUSD` as collateral.

Accounting rules:

- splitting collateral burns or locks one collateral unit and mints a complete outcome partition,
- merging a complete partition burns positions and releases or mints collateral,
- redeeming burns winning positions and releases or mints collateral payout,
- rounding must never overpay collateral across the complete partition.

---

## 5. BinaryPositionModule

### 5.1 Purpose

`BinaryPositionModule` adapts existing Eves orderbook markets into native binary conditions.

It should not replace the market creation or resolution system. It should read from it.

### 5.2 Required Behavior

For each binary orderbook market:

- prepare or register a binary condition,
- expose YES and NO position ids,
- split collateral into YES/NO,
- merge YES/NO back into collateral,
- report condition resolution result,
- redeem resolved YES/NO positions.

### 5.3 Resolution Source

The module reads canonical market state from the existing protocol storage:

- unresolved,
- resolved YES,
- resolved NO,
- invalid/refund if applicable.

Invalid policy must be explicit. For normal binary positions, invalid/refund likely maps to both sides redeeming pro rata or the protocol's existing refund semantics. This must be consistent with orderbook market settlement.

### 5.4 Incentives

Required state transitions and callers:

| Transition | Caller | Reason |
| --- | --- | --- |
| Split collateral | Trader or maker | Mint tradable inventory. |
| Merge YES/NO | Arbitrageur, maker, holder | Recover collateral from complete set. |
| Redeem resolved position | Holder or helper | Receive collateral payout. |
| Resolve market | Existing resolution path | Existing creator/dispute/voter incentives. |

No transition depends on an offchain operator.

---

## 6. CombinatorialPositionModule

### 6.1 Purpose

`CombinatorialPositionModule` creates native multi-leg scenario positions.

A combo condition stores a canonical list of underlying binary or future negrisk position ids:

```text
legs = [A.YES, B.NO, C.YES]
condition = hash(COMBINATORIAL, legs)
YES(condition) = all legs true
NO(condition) = complement of all legs true
```

### 6.2 Canonical Leg Rules

Leg arrays must be:

- non-empty,
- length <= 50,
- sorted by canonical position id,
- free of duplicate position ids,
- free of duplicate underlying condition ids,
- free of contradictory branches like `A.YES` and `A.NO`,
- restricted to supported modules,
- restricted to markets that exist,
- restricted to markets that have started,
- restricted to markets that are not finalized at initial combo creation unless the operation is compression/wrap logic.

Canonicalization should happen in the UI and be rechecked onchain.

### 6.3 Required Functions

The clean-room implementation should support the following behavior.

| Function | Behavior |
| --- | --- |
| `prepareCondition` | Store canonical leg array and emit the condition definition. |
| `split` | Collateral -> YES(combo) + NO(combo). |
| `merge` | YES(combo) + NO(combo) -> collateral. |
| `splitOnCondition` | YES(parent) -> YES(parent AND new.YES) + YES(parent AND new.NO). |
| `mergeOnCondition` | Child YES branches -> parent YES. |
| `extract` | NO(full combo) -> reduced NO + residual YES branch. |
| `inject` | Inverse of extract. |
| `convertToYesBasket` | NO(full combo) -> canonical disjoint YES basket. |
| `mergeFromYesBasket` | Canonical YES basket -> NO(full combo). |
| `compress` | Remove resolved legs and mint reduced position and/or collateral. |
| `redeem` | Burn fully resolved position and pay collateral. |
| `wrap` | Convert one underlying position into a single-leg combo. |
| `unwrap` | Convert a single-leg combo back to the underlying position. |
| `multicall` | Batch user operations where useful. |

Names can change, but the behavior should remain recognizable and testable.

### 6.4 Compression Semantics

For `YES(A AND B AND C)`:

- if a resolved leg pays zero, the YES combo pays zero,
- if a resolved leg pays one, remove it from the combo,
- if all legs resolve true, redeem to collateral,
- unresolved legs remain in a reduced combo.

For `NO(A AND B AND C)`:

- if any resolved leg makes the full conjunction impossible, the NO side can become immediately valuable,
- if some legs resolve true, reduce the NO position over the unresolved remainder,
- if all legs resolve true, NO pays zero,
- if all legs resolve and the full conjunction is false, NO pays one collateral unit.

Rounding must be deterministic and collateral-conservative.

### 6.5 NO Basket Semantics

The complement of a conjunction can be represented as a disjoint YES basket:

```text
NO(A AND B AND C)
= YES(!A)
  OR YES(A AND !B)
  OR YES(A AND B AND !C)
```

The module should support converting a NO combo into this canonical basket and merging it back. This is important for unbundling and for maker inventory management.

### 6.6 Incentives

Required state transitions and callers:

| Transition | Caller | Reason |
| --- | --- | --- |
| Prepare condition | Creator, maker, buyer, book helper | Needed before minting or trading. |
| Split combo | Maker or trader | Create YES/NO inventory. |
| Merge combo | Holder or arbitrageur | Recover collateral from complete partition. |
| Split on condition | Maker or holder | Extend scenario or create sibling branches. |
| Extract/inject | Holder, maker, arbitrageur | Rebalance complement exposure. |
| Convert NO basket | Holder, maker | Make NO exposure easier to trade or merge. |
| Compress | Holder, keeper, UI helper | Unlock value after legs resolve. |
| Redeem | Holder, keeper, UI helper | Claim payout. |
| Wrap/unwrap | Holder, maker | Move between binary and combo liquidity surfaces. |

Any keeper/helper reward should be optional. The base system works because holders have direct economic incentive to call these functions.

---

## 7. Dedicated ERC1155 Books

### 7.1 Naming Boundary

Do not call these Spot books.

Spot is ERC20/ERC20 trading. Scenario books are ERC1155/eveUSD books.

Suggested naming:

- `ScenarioBookFacet`,
- `PositionBookFacet`,
- `ERC1155BookFacet`,
- or `ComboBookFacet`.

### 7.2 Book Types

The book layer should support:

- binary YES/NO native positions,
- combo YES/NO positions,
- extracted branches,
- NO basket branches,
- peer-to-peer parlay ticket ERC1155s.

This does not mean every asset needs a default book at market creation. Books should be lazily created when there is trading intent.

### 7.3 Trading Model

Each book is:

```text
base asset:  ERC1155 contract + token id
quote asset: eveUSD
```

Required order forms:

- maker sells escrowed ERC1155 inventory for eveUSD,
- maker bids escrowed eveUSD for ERC1155 inventory,
- taker buys against maker asks,
- taker sells against maker bids,
- cancel one order,
- cancel all orders for caller in a book.

If the existing CLOB curve engine is generalized, scenario books should support both:

- flat orders,
- linear price profiles.

The UI may call both "orders" while maker tooling can expose profile details.

### 7.4 Price Bounds

For native payout positions:

```text
0 <= price <= 1 collateral unit
```

For parlay tickets:

```text
0 <= price <= max remaining ticket payout
```

The book contract should enforce the relevant cap where practical.

### 7.5 Fee Config

Scenario books should not reuse Spot fees.

Suggested config:

```text
SCENARIO_TRADE_FEE_BPS
SCENARIO_MAKER_FEE_BPS
SCENARIO_CREATOR_FEE_BPS
SCENARIO_PROTOCOL_FEE_BPS
SCENARIO_VAULT_FEE_BPS
SCENARIO_BOOK_CREATION_FEE
```

Creator fees make sense here because curated scenario creation is a product surface. That is different from ERC20 Spot trading.

---

## 8. Liquidity Strategy

### 8.1 What We Can Honestly Promise

The beta promise:

- makers can create exact scenario inventory,
- makers can open books for those exact branches,
- users can buy and sell executable combo positions,
- holders can unbundle and compress positions through protocol functions.

### 8.2 What We Should Not Claim Initially

Do not claim every arbitrary combo has instant liquidity from underlying binary books.

That is a routing problem, not a guaranteed property. It can be researched after the native position layer is working.

### 8.3 Maker-Created Combo Market

The strongest product surface is curated scenario creation:

```text
Creator X builds strong sports combos.
Creator X mints or acquires inventory.
Creator X sells those combos in dedicated books.
Users follow Creator X and buy their positions.
```

This creates a market for reputation, not just a market for isolated event probabilities.

### 8.4 Complement Top-Up Flow

If a user needs a missing sibling branch to merge upward:

```text
User holds: A.YES AND B.YES
Needs:      A.YES AND B.NO
Goal:       merge back into A.YES
```

The protocol should support:

- computing the missing branch,
- opening a book for it,
- posting a bid/reward,
- maker filling that bid,
- user merging manually or through an atomic helper.

Atomic helper target:

```text
fillComplementAndMerge(...)
```

This should only execute if every step succeeds.

---

## 9. Multioutcome and NegRisk Parity

### 9.1 Why It Matters

Sports and politics often need mutually exclusive outcomes:

```text
Who wins the series?
- Team A
- Team B
```

or:

```text
Which candidate wins?
- Candidate A
- Candidate B
- Candidate C
- Other
```

Binary markets can represent these awkwardly. A negrisk/multioutcome module can represent them cleanly.

### 9.2 Future NegRiskPositionModule

The native system should reserve room for a module that supports:

- event id,
- N mutually exclusive conditions,
- horizontal split from collateral into all outcome YES positions,
- horizontal merge from all outcome YES positions back into collateral,
- NO-to-YES-basket conversion,
- "Other" or residual outcome support where needed,
- resolution of one outcome implying NO for incompatible outcomes.

### 9.3 Relation to Existing Multioutcome Specs

This module should align with the orderbook multioutcome spec, not duplicate it.

Parimutuel multioutcome is a separate flow because parimutuel shares are pool claims, not a CTF-style collateral partition. They can be used inside peer-to-peer parlay underwriting once final outcomes are readable, but they should not be included in native decomposable combo positions until a separate composability design exists.

---

## 10. UI Requirements

### 10.1 Product Separation

The UI must clearly separate:

| Product | User Language | Protocol Meaning |
| --- | --- | --- |
| Peer-to-peer parlay | Fixed-payout parlay | Underwritten ticket with escrowed liability. |
| Scenario position | Parlay / Combo | Decomposable ERC1155 condition token. |
| Normal orderbook market | Market | Binary YES/NO trading. |
| Parimutuel market | Pool market | Minted pool shares and CLOB resale. |

### 10.2 Builder

The scenario builder should let users:

- select started orderbook markets,
- choose YES or NO per leg,
- see canonical leg count,
- see estimated fair probability from market prices,
- see max payout,
- choose whether to buy an existing combo or create one,
- create a book if no book exists,
- understand that creator pricing can include premium.

### 10.3 Portfolio

Portfolio should show:

- combo position balance,
- leg list,
- leg status,
- current book value where available,
- max payout,
- compress eligibility,
- redeem eligibility,
- missing sibling hints,
- unwrap option for single-leg combos.

### 10.4 Maker UX

Makers should be able to:

- prepare combo conditions,
- split collateral into inventory,
- post combo asks,
- post combo bids,
- update flat orders or profile orders,
- cancel inventory orders,
- see exposure by underlying market,
- see positions that are compressible or redeemable,
- create curated combo pages/books.

---

## 11. Indexer Requirements

The indexer should not depend on wallet metadata.

Required indexed entities:

- native position manager deployment,
- module registrations,
- binary condition registration,
- combo condition prepared,
- combo leg arrays,
- ERC1155 transfers,
- split/merge events,
- compression events,
- redemption events,
- wrap/unwrap events,
- scenario book creation,
- scenario order creation/update/cancel,
- scenario fills,
- fee distribution,
- creator attribution,
- condition status by underlying market.

Helpful derived fields:

- combo leg count,
- resolved leg count,
- has losing YES leg,
- compressible,
- redeemable,
- missing sibling candidates,
- current best bid/ask,
- estimated fair value,
- creator volume,
- maker volume.

---

## 12. Security Requirements

### 12.1 Solvency

The most important invariant:

```text
The protocol must never pay out more collateral than was locked, burned, or otherwise accounted for.
```

Required invariants:

- splitting and merging preserves value,
- complete outcome partitions merge to exactly one collateral unit,
- YES combo payout is bounded by one collateral unit,
- NO combo payout is bounded by one collateral unit,
- YES and NO payouts cannot sum above one unit for the same condition and amount,
- compression preserves value,
- wrapping and unwrapping preserves value,
- basket conversion preserves value.

### 12.2 Authorization

- Only registered modules can mint or burn their own module positions.
- Cross-module authorization must be explicit and minimal.
- Admin/module registration powers should be behind deployment governance.
- No book fill path can mint scenario positions directly unless it routes through a valid module operation.

### 12.3 Reentrancy and ERC1155 Callbacks

- ERC1155 receiver callbacks must not allow accounting reentry.
- Split/merge/redeem should use checks-effects-interactions or equivalent protections.
- Book fills must settle escrow and balances atomically.

### 12.4 Canonicalization

- Duplicate conditions must revert.
- Contradictory legs must revert.
- Unsorted input must revert or be normalized in a clearly specified way.
- Max 50 legs must be enforced.
- All loops must be bounded.

### 12.5 Rounding

- Use high precision for payout products.
- Round YES payouts down when needed.
- Round NO/complement accounting conservatively.
- Add invariant tests for dust and repeated compression.

---

## 13. Testing Requirements

Follow the repo's test fidelity guardrails: real value-moving flows should have live-style regression coverage, not only storage harness coverage.

### 13.1 Unit and Flow Tests

Required coverage:

- deploy position manager and modules,
- register binary module,
- register combinatorial module,
- create binary market condition,
- split collateral into binary YES/NO,
- merge binary YES/NO,
- redeem binary winner,
- prepare 1-leg combo through wrap path,
- prepare 2-leg combo,
- prepare 3-leg combo,
- prepare 10-leg combo,
- prepare 50-leg combo,
- reject 51-leg combo,
- reject duplicate legs,
- reject contradictory legs,
- reject unsupported modules,
- split collateral into combo YES/NO,
- merge combo YES/NO,
- split parent YES on a new condition,
- merge child YES positions back to parent,
- extract from NO combo,
- inject back into NO combo,
- convert NO combo to YES basket,
- merge YES basket back to NO combo,
- compress winning resolved leg,
- compress losing YES leg to zero,
- redeem fully resolved winning YES combo,
- redeem fully resolved winning NO combo,
- wrap and unwrap a single underlying position.

### 13.2 Book Tests

Required coverage:

- create scenario book lazily,
- post ERC1155 inventory ask,
- post eveUSD bid,
- fill ask,
- fill bid,
- cancel one order,
- cancel all user orders in a book,
- reject price above max payout,
- reject fill against wrong token id,
- charge scenario fee config,
- route maker/protocol/vault/creator fee shares,
- indexable events include enough data to reconstruct state.

### 13.3 Invariant Tests

Required invariants:

- no collateral overpayment,
- split/merge conservation,
- compression equivalence,
- wrap/unwrap conservation,
- basket conversion conservation,
- total payout bound,
- canonical leg uniqueness,
- book escrow cannot go negative,
- unauthorized modules cannot mint or burn.

### 13.4 Gas Tests

Measure:

- prepare 10 legs,
- prepare 50 legs,
- split 10-leg combo,
- split 50-leg combo,
- compress 10-leg combo,
- compress 50-leg combo,
- convert 10-leg NO basket,
- convert 50-leg NO basket,
- book create,
- order post,
- order fill.

50-leg flows must either fit within Base limits or be split into a documented multi-transaction preparation path.

---

## 14. Deployment Strategy

### 14.1 Alpha

Alpha remains focused on:

- current CLOB,
- orderbook trading,
- parimutuel markets,
- peer-to-peer parlay underwriting,
- market creation,
- maker data collection.

No alpha data depends on native combinatorial positions.

### 14.2 Beta

Beta should be a fresh deployment or explicitly versioned upgrade path.

Beta deployment sequence:

1. Deploy `EvesPositionManager`.
2. Deploy `BinaryPositionModule`.
3. Deploy `CombinatorialPositionModule`.
4. Register modules.
5. Grant minimal cross-module authorization.
6. Deploy or upgrade scenario book facet.
7. Configure scenario fees.
8. Deploy indexer schema update.
9. Deploy UI feature flags.
10. Smoke test split, combo creation, book fill, compression, and redemption.

### 14.3 Upgrade Compatibility

If this ships as a Diamond upgrade:

- isolate storage namespaces,
- do not reuse Spot storage for scenario books,
- do not change existing orderbook storage layout,
- add feature flags for UI/indexer rollout,
- provide a rollback plan for UI exposure, not for irreversible contract storage.

---

## 15. Implementation Workstreams

### 15.1 Position Layer

Deliverables:

- ERC1155 position manager,
- module registry,
- authorized mint/burn,
- batch mint/burn,
- payout dispatch,
- tests for authorization and ERC1155 behavior.

### 15.2 Binary Module

Deliverables:

- binary condition registration,
- split/merge/redeem,
- resolution adapter to existing market state,
- invalid/refund policy,
- tests for all settlement outcomes.

### 15.3 Combinatorial Module

Deliverables:

- canonical condition preparation,
- split/merge,
- split-on-condition and merge-on-condition,
- extract/inject,
- NO basket conversion,
- compression,
- redeem,
- wrap/unwrap,
- 50-leg tests.

### 15.4 Scenario Books

Deliverables:

- dedicated ERC1155/eveUSD book surface,
- lazy book creation,
- flat orders,
- optional profile orders,
- bid/ask escrow,
- cancellation,
- fee routing,
- exact token id validation.

### 15.5 UI and Indexer

Deliverables:

- scenario builder,
- creator combo pages,
- book pages,
- portfolio actions,
- compression/redeem buttons,
- complement helper UX,
- indexer schema and API updates.

### 15.6 NegRisk and Multioutcome

Deliverables:

- finalized orderbook multioutcome spec alignment,
- negrisk module design,
- horizontal split/merge,
- NO conversion,
- multioutcome scenario leg support.

This should come after binary combo parity unless product testing says multioutcome is urgent.

---

## 16. Acceptance Criteria

The native combinatorial layer is ready for beta testing when:

- makers can create and sell native combo inventory,
- users can buy and hold combo ERC1155s,
- users can transfer combo ERC1155s,
- holders can compress after partial resolution,
- holders can redeem after final resolution,
- one-leg wrap/unwrap works,
- NO basket conversion works,
- 50-leg condition preparation works,
- dedicated scenario books work without Spot fee or storage conflation,
- the indexer can reconstruct combo conditions and balances from events,
- the UI does not claim instant liquidity from underlying binary books,
- all value-moving flows have live-style tests,
- invariant tests prove no collateral overpayment.

---

## 17. Explicit Non-Goals

- Copying Polymarket code.
- Depending on Polymarket contracts.
- Replacing peer-to-peer parlay underwriting.
- Treating raw Gnosis CTF as the final beta position layer.
- Creating books for every possible combo automatically.
- Calling scenario books Spot books.
- Including parimutuel markets in native decomposable combos before a separate composability design.
- Guaranteeing synthetic liquidity from binary books.
- Letting core combo positions sell above max payout.

---

## 18. Open Design Questions

1. Should scenario books use the existing CLOB curve engine immediately, or start with flat bid/ask orders and add profiles afterward?
2. Should creators receive scenario-book creator fees by default, or should creator monetization start as reputation-only?
3. Should combo condition preparation require a fee, an EVE bond, or only book creation fees?
4. Should keepers receive a small reward for third-party compression/redeem calls, or is holder incentive enough?
5. Should invalid orderbook market outcomes map to refund, zero, or proportional payout for native binary positions?
6. Should single-leg combos be exposed to retail users or treated as internal wrap/unwrap plumbing?
7. Should NegRisk ship in the same beta milestone or follow after binary combo parity?

---

## 19. Recommended Build Order

1. Build and test `EvesPositionManager`.
2. Build and test `BinaryPositionModule`.
3. Build and test basic `CombinatorialPositionModule` split/merge/redeem.
4. Add advanced combo operations: split-on-condition, extract/inject, NO baskets, compression, wrap/unwrap.
5. Add dedicated ERC1155 scenario books.
6. Add indexer support.
7. Add UI builder, portfolio actions, and creator surfaces.
8. Add NegRisk/multioutcome support.

This order gets the solvency-critical state machine correct before layering maker UX and routing complexity on top.
