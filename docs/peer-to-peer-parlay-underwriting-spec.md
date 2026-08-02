# Peer-to-Peer Parlay Underwriting Spec

**Status:** Draft
**Date:** 2026-05-27
**Owner:** Eves Market protocol
**Scope:** Native peer-to-peer parlay offers, parlay requests, underwriter escrow, ticket finalization/claims, social reputation, and walkaway-safe metadata.
**Target:** EvePredict beta / v2.x candidate

---

## 1. Intent

Build a native peer-to-peer parlay system for Eve's Market where users and makers can create compound event theses and let the market underwrite them.

This is not a sportsbook and not a protocol-priced parlay engine. The protocol does not quote odds, does not take balance-sheet risk, and does not decide whether a parlay is fairly priced.

Instead:

- users can publish desired parlay theses with wanted premium/payout terms,
- makers can choose to underwrite those requests if they think the thesis is overpriced or unlikely,
- makers can publish their own pre-priced parlay offers,
- buyers can purchase maker-created parlay tickets,
- all max payout liability is escrowed at fill/post time,
- filled tickets settle deterministically from underlying Eve market outcomes,
- underlying Eve markets may be orderbook or parimutuel markets as long as they resolve to a canonical on-chain binary outcome,
- creator and underwriter reputation emerges from real filled volume and realized outcomes, but parlay fills do not route creator fees.

The product primitive:

> Create your thesis. Let the market underwrite it.

The financial primitive:

> A permissionless underwriting market for compound event risk.

---

## 2. Core Product Thesis

Normal parlays are offered by centralized bookmakers. The bookmaker prices a compound ticket, takes the bettor's premium/stake, and eats the payout if the ticket hits. Bookmakers profit because they price probability, embed margin, limit exposure, and most parlays lose.

Eves Market replaces the bookmaker with a peer-to-peer underwriter marketplace.

### 2.1 Buyer Side

A buyer wants upside on a compound thesis:

```text
I will pay 10 eveUSD for a shot at 100 eveUSD if these 5 events hit.
```

The buyer may:

- fill an existing maker offer,
- publish a request and wait for a maker to underwrite it,
- resell a live ticket later through secondary markets.

### 2.2 Underwriter / Maker Side

An underwriter sells structured event risk for premium:

```text
I think this 5-leg thesis is unlikely. I will accept 10 eveUSD premium and escrow 100 eveUSD max payout.
```

If the ticket loses, the underwriter keeps premium and receives unused escrow back.

If the ticket wins, the underwriter pays from escrow.

This is not passive liquidity provision. It is active risk underwriting.

### 2.3 Creator Economy

The parlay creator may be different from both buyer and underwriter.

A sharp creator can publish compelling theses that buyers want and underwriters are willing to price. Their reputation is social and indexer-visible, not a protocol fee entitlement. It comes from:

- fill volume,
- copied templates,
- buyer ROI,
- hit rate,
- underwriter interest,
- downstream ticket trading.

A sharp underwriter can build a book by consistently writing parlays that look attractive but are overpriced from the underwriter's perspective.

---

## 3. Roles

| Role | Description |
|------|-------------|
| **Template Creator** | Creates the parlay thesis/template: legs, payout tiers, invalid policy, metadata. |
| **Request Creator / Buyer** | Publishes a wanted parlay: premium willing to pay, desired payout, units, deadline. |
| **Offer Maker / Underwriter** | Publishes a priced parlay offer or fills a buyer request by escrowing max liability. |
| **Ticket Holder** | Owns filled ERC-1155 parlay ticket units and can claim settlement payout. |
| **Settler** | Any address that calls settlement once outcomes are knowable. |
| **Indexer/UI Operator** | Reads events, renders templates/tickets, computes reputation, and surfaces offers/requests. |

Roles may overlap. A maker can create a template and underwrite it. A buyer can create a request. A creator can buy their own thesis.

---

## 4. Walkaway Requirement

The parlay system must pass the walkaway test.

If DevCo infra disappears and admin is revoked, users must still be able to:

- discover templates, offers, requests, tickets, and fills from chain events,
- fill live on-chain offers/requests,
- transfer parlay tickets,
- settle tickets from underlying market outcomes,
- claim payouts,
- run their own indexer/UI.

Off-chain infra may improve UX, reputation, ranking, recommendations, and search. It must not be required for custody, settlement, payout, or recovery.

### 4.1 Canonical Source Hierarchy

| Layer | Canonical? | Purpose |
|-------|------------|---------|
| Contract storage | Yes | Settlement, escrow, fill state, ticket accounting |
| Events | Yes/reconstructable | Full template/request/offer discovery and indexing |
| Token metadata | Display only | UI/wallet rendering of parlay/ticket info |
| DevCo API/indexer | No | Convenience, ranking, search, reputation, caching |

---

## 5. Core Market Shapes

The system must support both directions.

### 5.1 Maker-Posted Offer

A maker/underwriter publishes a priced parlay offer:

```text
Template: 5-leg NBA chaos thesis
Buyer premium: 10 eveUSD per unit
Max payout: 100 eveUSD per unit
Units available: 50
Invalid policy: void invalid legs
Fill deadline: Friday 17:00 UTC
```

The maker escrows max liability when posting or before the offer becomes fillable.

A buyer fills one or more units and receives ERC-1155 parlay tickets.

Maker psychology:

```text
Nah, no way this hits. Thanks for the easy premium.
```

But if it hits, the maker pays from escrow.

### 5.2 Buyer-Posted Request

A buyer publishes a wanted parlay:

```text
Template: 8-leg macro moonshot
Premium offered: 25 eveUSD per unit
Desired max payout: 1,000 eveUSD per unit
Units requested: 1
Request deadline: Sunday 20:00 UTC
```

The buyer escrows premium.

A maker/underwriter can fill the request by escrowing the requested max payout.

This is critical product surface. It lets users publish crazy theses and lets makers choose whether to write the other side.

### 5.3 Secondary Ticket Trading

A filled parlay ticket is an ERC-1155 asset and should be treated as a live repricing market instrument, not merely a receipt.

A ticket should trade through a generic ERC-1155 CLOB surface:

```text
base asset: ParlayTicket ERC1155 ticketId
quote asset: eveUSD
```

This is not automatically available through the current ERC-20 spot book creation path. V1 should add a dedicated `createParlayTicketBook` entrypoint for parlay-ticket secondary markets.

Parlay ticket books should use generic ERC-1155/eveUSD pricing unless ticket units are intentionally normalized to a one eveUSD maximum payout. Tickets with larger max payouts need prices expressed as absolute eveUSD per ticket unit, not prediction-share cents.

This allows:

- ticket holders to sell live parlays before final resolution,
- buyers to purchase partially de-risked tickets,
- makers to buy back their own exposure,
- traders to speculate on partially resolved tickets,
- creator reputation to compound through visible secondary volume.

This is core product surface, not decorative UX. A normal sportsbook may offer a controlled cashout price. Eve's Market should make cashout a market.

Example:

```text
Original ticket:
5-leg parlay
Buyer pays: 10 eveUSD
Payout if 5/5 hit: 100 eveUSD

After 4 legs hit:
Only 1 leg remains.
If final leg market implies 40% probability, rough fair value is 40 eveUSD.

Original buyer can sell for 20 eveUSD:
- paid 10
- exits at 20
- locks 2x profit
- removes final-leg risk

Secondary buyer pays 20 eveUSD:
- receives a live ticket with potential 100 eveUSD payout
- may have favorable odds if fair value is closer to 40
```

The ticket price should evolve as:

- legs resolve,
- underlying market odds move,
- time passes,
- invalid/dispute risk changes,
- liquidity changes,
- underwriter exposure changes.

Underwriters can also use the secondary market defensively. If a ticket becomes dangerous after several legs hit, the underwriter can buy it back to eliminate or reduce payout liability.

### 5.4 Live Ticket Valuation

The UI and indexer should expose live ticket state and rough valuation tools.

For a simple all-or-nothing ticket:

```text
expected value ~= payout_if_hit * probability_remaining_conditions_hit
```

For partial payout tiers:

```text
5/5 pays 100
4/5 pays 25
3/5 pays 0

If 4 legs have hit and 1 remains:
EV ~= P(final hits) * 100 + P(final misses) * 25
```

If final leg probability is 40%:

```text
0.40 * 100 + 0.60 * 25 = 55
```

The protocol does not enforce these valuations. They are UI/indexer analytics. The CLOB decides actual tradable price.

Recommended UI fields:

- original premium,
- max payout,
- current listed bids/asks,
- resolved hits/misses/invalids,
- remaining legs,
- rough implied value from underlying markets,
- payout scenarios,
- breakeven resale price,
- underwriter buyback bids if present.

---

## 6. Economic Model

### 6.1 Fully Collateralized Liability

Hard rule:

> No escrow, no underwriting.

Every filled or fillable underwritten unit must be backed by escrowed max payout.

If max payout is 100 eveUSD per unit and 50 units are offered, the maker must escrow 5,000 eveUSD for all posted fillable units or escrow pro-rata as each unit is filled.

V1 should prefer escrow at post time for maker offers because it creates real executable liquidity.

Buyer requests escrow the premium plus flat parlay fee at post time. Maker fills by escrowing max payout.

### 6.2 Premium Flow

Parlay economics should be simple:

```text
buyer pays X premium
buyer pays F flat protocol fee per parlay unit
ticket pays up to Y if it hits, or according to configured payout tiers
underwriter escrows Y max payout
```

There are no parlay creator fees and no underlying market creator fees.

The protocol fee is a flat eveUSD amount charged per parlay unit underwritten. It is not a percentage of premium and it is not taken out of the underwriter's premium.

Example:

```text
Parlay premium/cost: 10 eveUSD
Flat parlay fee:      2 eveUSD
Buyer all-in cost:   12 eveUSD
Underwriter premium: 10 eveUSD
Fee routed:           2 eveUSD
```

For maker-posted offers, the buyer pays `premiumPerUnit + flatFeePerUnit` when filling.

For buyer-posted requests, the requester escrows `premiumPerUnit + flatFeePerUnit` while waiting for an underwriter. When an underwriter fills, `premiumPerUnit` goes to the underwriter and `flatFeePerUnit` is split according to the configured vault/`feeRecipient` split.

Simple V1 flow:

```text
buyer all-in payment
  -> parlay premium -> underwriter
  -> flat parlay fee -> vault + feeRecipient
```

Underwriter receives premium because they are selling risk.

Flat fee config:

```text
PARLAY_UNDERWRITING_FEE = fixed eveUSD amount per parlay unit
Suggested initial value: 3 eveUSD
PARLAY_FEE_VAULT_BPS + PARLAY_FEE_RECIPIENT_BPS = 10_000
```

Template creators can still build reputation from copied templates, fills, secondary volume, and outcomes, but that reputation is a social/indexer layer. It should not create a protocol-enforced fee claim in V1.

### 6.3 Underwriter Yield Metrics

UI should expose underwriting risk/yield clearly:

```text
Escrow required: 100 eveUSD
Premium received: 8 eveUSD
Duration: 10 days
Max payout: 100 eveUSD
Max net loss: 92 eveUSD
Premium yield: 8%
Annualized yield: 292%
Breakeven hit probability: 8%
```

Breakeven approximation:

```text
premium / maxPayout
```

If underwriter believes true hit probability is below breakeven, underwriting is positive expected value.

### 6.4 Protocol Risk

The protocol never eats parlay losses. The protocol only:

- validates terms,
- escrows collateral,
- mints/burns tickets,
- routes fees,
- settles according to outcomes.

All economic risk belongs to ticket buyers and underwriters.

### 6.5 Cash-Covered vs Hedge-Covered Underwriting

V1 is explicitly **cash-covered**.

A cash-covered parlay is a side bet on existing Eve market outcomes. It references underlying markets, but it does **not** buy YES/NO positions in those markets.

```text
Underlying markets:
A, B, C, D, E

Parlay ticket:
Pays if A/B/C/D/E resolve in the required pattern.

V1 collateral:
Underwriter escrows eveUSD max payout.
```

Settlement reads the final outcomes of referenced markets and pays from the underwriter's escrow. The parlay ticket does not redeem underlying market positions.

The parlay layer must consume the canonical Eve market outcome only. It should not care whether the referenced market traded through the orderbook CLOB, the parimutuel pool, or both.

```text
Parlay leg input:
  marketId + requiredOutcome

Settlement read:
  resolved market outcome from Eve market storage

Ignored by parlay settlement:
  orderbook fills
  parimutuel epochs
  parimutuel pool balances
  secondary CLOB liquidity
```

This keeps parlay settlement independent from the underlying liquidity mechanism. A binary Eve market either resolves to the required outcome, resolves to another outcome, resolves invalid, or is not yet settleable.

This is capital-efficient because the underwriter only locks the maximum payout, not a basket of underlying leg positions.

A later **hedge builder** flow can be handled by UI/router orchestration rather than a separate parlay collateral mode:

```text
User builds direct multi-leg exposure
UI suggests hedge profile
Router batch-executes direct market buys
Router creates/parses matching parlay templates or requests
Makers still choose whether to underwrite open hedge requests
```

The parlay protocol should remain cash-covered: underwriter escrows max eveUSD payout and receives premium. If the UI buys underlying legs as part of a strategy, those positions remain normal user positions and are not part of parlay settlement.

V1 should not require underlying market purchases when a parlay is filled.

### 6.6 Portfolio Hedging and Payoff Engineering

Parlays are not only bettor moonshots. They are also portfolio-shaping tools.

A trader can combine direct market positions with bought or written parlays to create custom payoff profiles.

Example: direct thesis plus cheap hedge.

```text
Trader is heavily long several underlying markets:
- A.YES
- B.YES
- C.YES

Trader buys a cheap opposite-way parlay:
- A.NO + B.NO + C.NO pays 100

If main thesis hits:
- direct positions win
- hedge parlay expires worthless
- trader only spent the parlay premium

If main thesis breaks badly:
- some direct positions lose
- opposite-way parlay may pay and soften the loss
```

Example: writing parlays against a held book.

```text
Trader owns direct positions that benefit if A/B/C happen.
Trader writes a parlay that pays if the opposite scenario happens.

If A/B/C happen:
- direct book wins
- written parlay expires worthless
- trader keeps premium

If the opposite scenario happens:
- direct book loses
- written parlay pays out
- loss is bounded by escrowed max payout
```

Example: scenario laddering.

```text
Trader creates several parlays for different paths:
- soft landing path
- hard landing path
- chaos path
- sideways/noise path

Each ticket has different payout tiers and underwriters.
```

This turns Eve's Market into a payoff engineering surface:

- buy markets directly for base exposure,
- buy parlays for convex upside or downside protection,
- write parlays to earn premium against scenarios considered unlikely,
- trade live tickets as probabilities update.

The UI should eventually show net portfolio exposure across:

- direct market positions,
- bought parlay tickets,
- written/underwritten parlay liability,
- secondary ticket bids/asks,
- estimated worst-case and best-case outcomes by scenario.

V1 does not need a full portfolio risk engine, but events and ticket metadata should make this analysis reconstructable by indexers.

### 6.7 Visual Strategy Builder and Auto-Hedge Requests

The intended UX is not a static parlay form. It should feel like a visual payoff builder.

A user constructs a primary multi-leg batch bet, then the UI helps generate hedge parlay requests that makers can underwrite.

Product flow:

```text
Build thesis
  -> choose underlying markets and outcomes
  -> batch buy direct market positions
  -> UI computes risk gaps / failure modes
  -> UI suggests hedge parlay requests
  -> user publishes selected hedge requests
  -> makers underwrite requests
  -> user holds direct positions + parlay tickets / open hedge requests
```

Example primary thesis:

```text
I think these 5 things happen:
A.YES
B.YES
C.NO
D.YES
E.NO

Primary batch bet:
Buy positions for A.YES, B.YES, C.NO, D.YES, E.NO
Estimated cost: 250 eveUSD
Max direct payout: 500 eveUSD
```

Example auto-generated hedge requests:

```text
Hedge 1: Partial miss protection
If exactly/at most 3 of 5 hit, pay 80
Premium offered: 10

Hedge 2: Disaster hedge
If 0-2 of 5 hit, pay 150
Premium offered: 8

Hedge 3: Key-leg failure hedge
If A/B hit but C fails, pay 50
Premium offered: 5

Hedge 4: Protected payout ladder
2/5 pays 20
3/5 pays 40
4/5 pays 80
5/5 pays 100
Premium offered: 12
```

The UI may auto-generate hedge parlay templates and requests. The protocol does not auto-underwrite them. Makers still choose whether to take the other side.

If a matching maker-posted offer already exists, the UI can offer immediate fill. If no matching offer exists, the UI posts a buyer request and waits for underwriters.

#### Visual Builder Components

Recommended UX components:

- **Leg cards** — each market/outcome/amount as a draggable card.
- **Batch bet summary** — total cost, max direct payout, worst case, all-hit profit.
- **Scenario matrix** — 5/5, 4/5, 3/5, 2/5, 0-1/5 outcome bands.
- **Auto-hedge suggestions** — miss-one, disaster, key-leg fail, opposite thesis, protected payout ladder.
- **Underwriter queue** — open hedge requests waiting for makers.
- **Live strategy dashboard** — direct positions, open requests, filled parlay tickets, current bids/asks, and scenario PnL.

#### Strategy Grouping

A strategy groups direct market positions and related parlay templates/requests/tickets for UI/indexer purposes.

V1 should emit an on-chain grouping event so maker/taker attribution and strategy pages can be reconstructed. The strategy object must remain metadata only and must not control custody or settlement.

Possible event shape:

```solidity
event StrategyCreated(
    bytes32 indexed strategyId,
    address indexed creator,
    bytes32[] directMarketIds,
    uint8[] directOutcomes,
    uint256[] parlayTemplateIds,
    string metadataHint
);
```

The strategy object should not control custody or settlement. It is a grouping primitive for thesis pages and portfolio visualization.

Product line:

> Build the thesis. Buy the exposure. Hedge the failure modes.

---

## 7. Data Model

### 7.1 Outcomes

For existing binary Eve markets, use the current `LibEveMarket.MarketOutcome` values:

```solidity
enum MarketOutcome {
    Unresolved, // 0
    Yes,        // 1
    No,         // 2
    Invalid     // 3
}
```

V1 supports binary Eve markets regardless of trading mechanism:

- orderbook/CLOB binary markets,
- parimutuel binary markets,
- markets that have both pooled parimutuel entry and secondary CLOB liquidity.

The parlay engine reads the finalized market outcome from Eve market storage. It does not read parimutuel share balances, CTF balances, CLOB books, or pool accounting.

Future multi-outcome markets can use raw `uint8` outcome IDs. V1 should restrict to binary markets until multi-outcome resolution semantics are stable.

### 7.2 Parlay Leg

```solidity
struct ParlayLeg {
    bytes32 marketId;
    uint8 requiredOutcome;
}
```

V1 validation:

- market exists,
- market is unresolved when template/request/offer is created,
- scheduled markets are valid parlay legs,
- market is binary and resolves through Eve's canonical market outcome storage,
- market outcome type is supported,
- required outcome is valid for that market,
- no duplicate market IDs in one template,
- all referenced markets use compatible collateral and resolution semantics.

Fill-time validation:

- all referenced markets are still unresolved,
- referenced markets may be scheduled or actively trading,
- no referenced market is already pending settlement, resolved, disputed, or otherwise closed to new information-neutral fills,
- fill deadline is before or equal to the earliest referenced market close time unless governance explicitly allows otherwise.

A parlay with scheduled legs cannot finalize until every referenced market has resolved.

### 7.3 Payout Tier

```solidity
struct PayoutTier {
    uint8 minHits;
    uint128 payout;
}
```

All-or-nothing example:

```text
5/5 hit -> 100 eveUSD
0-4 hit -> 0 eveUSD
```

Tiered/system payout example:

```text
5 legs total
5/5 hit -> 100 eveUSD
4/5 hit -> 80 eveUSD
3/5 hit -> 40 eveUSD
2/5 hit -> 20 eveUSD
0-1 hit -> 0 eveUSD
```

Represented as:

```text
PayoutTier({ minHits: 5, payout: 100 })
PayoutTier({ minHits: 4, payout: 80 })
PayoutTier({ minHits: 3, payout: 40 })
PayoutTier({ minHits: 2, payout: 20 })
```

Traditional sportsbook parlays are usually all-or-nothing. Tiered payout parlays are closer to system bets, round-robin-style products, or protected parlays. Eve's Market should support both through one shared payout tier mechanism.

Rules:

- tiers sorted descending or ascending by `minHits`, with canonical order enforced,
- no duplicate `minHits`,
- `minHits` must be > 0 and <= leg count after invalid policy rules,
- higher `minHits` should not pay less than lower `minHits` unless the UI clearly marks a custom/non-monotonic structure; V1 should require monotonic payouts,
- the highest payout tier defines `maxPayoutPerUnit`, or `maxPayoutPerUnit` must exactly equal the highest payout tier,
- missing lower tiers imply zero payout below the lowest configured `minHits`,
- payout tiers are deterministic from hit count after invalid policy is applied,
- V1 can support only hit-count payout tiers, not arbitrary per-leg scripts.

All payout values are raw configured collateral token units. In the current deployment shape, eveUSD is 18 decimals, so `100 eveUSD` is represented as `100e18`.

### 7.4 Invalid Policy

```solidity
enum InvalidPolicy {
    VoidInvalidLegs,
    InvalidCountsAsMiss
}
```

Recommended V1 policies:

- `VoidInvalidLegs`
- `InvalidCountsAsMiss`

Do not support `RefundAll` in V1. Premium is paid to the underwriter and the flat fee is routed at fill time, so refund semantics require a separate premium/fee escrow or clawback model. If this policy is added later, it must be designed as a distinct custody mode, not a toggle on the current cash-covered flow.

Avoid too many hidden poison terms at launch. `InvalidCountsAsLoss` can be revisited later if makers want harsher underwriting terms, but it should not be part of the first implementation.

### 7.5 Parlay Template

A parlay template defines the thesis and settlement shape.

Recommended V1 storage: typed structured storage, not JSON-as-source-of-truth.

```solidity
struct ParlayTemplate {
    address creator;
    uint8 invalidPolicy;
    uint8 legCount;
    uint8 tierCount;
    bool exists;
}

mapping(uint256 templateId => ParlayTemplate) templates;
mapping(uint256 templateId => mapping(uint256 index => ParlayLeg)) templateLegs;
mapping(uint256 templateId => mapping(uint256 index => PayoutTier)) templatePayoutTiers;
```

`templateId` is a canonical `uint256` commitment:

```solidity
templateId = uint256(keccak256(abi.encode(
    PARLAY_TEMPLATE_DOMAIN,
    block.chainid,
    address(this),
    creator,
    canonicalLegs,
    canonicalPayoutTiers,
    invalidPolicy
)));
```

Full terms should also be emitted in events for indexers and walkaway reconstruction.

### 7.6 Maker Offer

```solidity
struct ParlayOffer {
    uint256 templateId;
    address maker;
    uint128 premiumPerUnit;
    uint128 maxPayoutPerUnit;
    uint128 totalUnits;
    uint128 remainingUnits;
    uint256 escrowRemaining;
    uint64 fillDeadline;
    bool active;
}
```

Maker offer semantics:

- maker posts terms,
- maker escrows max liability for offered units,
- buyers fill units,
- buyer pays premium plus flat fee on fill,
- full premium is transferred to maker/underwriter,
- flat fee is split between the vault and `feeRecipient`,
- ticket is minted to buyer,
- maker escrow remains locked until bucket finalization or cancellation of unfilled units.

### 7.7 Buyer Request

```solidity
struct ParlayRequest {
    uint256 templateId;
    address requester;
    uint128 premiumPerUnit;
    uint128 desiredMaxPayoutPerUnit;
    uint128 totalUnits;
    uint128 remainingUnits;
    uint256 premiumEscrowRemaining;
    uint256 feeEscrowRemaining;
    uint64 fillDeadline;
    bool active;
}
```

Buyer request semantics:

- buyer posts desired premium/payout terms,
- buyer escrows premium plus flat parlay fee,
- underwriter fills by escrowing max payout,
- ticket is minted to buyer/requester,
- underwriter receives the full posted premium,
- flat parlay fee is split between the vault and `feeRecipient`,
- filled ticket references the underwriter exposure bucket.

Aggregate escrow math must be done in `uint256`:

```text
premiumEscrow = premiumPerUnit * units
feeEscrow = PARLAY_UNDERWRITING_FEE * units
payoutEscrow = maxPayoutPerUnit * units
```

If per-unit values are stored as `uint128`, the implementation must either store aggregate escrow as `uint256` or reject products that exceed the chosen storage width. V1 should use `uint256` for aggregate escrow fields.

### 7.8 Filled Position / Ticket Bucket

Filled tickets must know which escrow bucket backs them.

```solidity
struct ParlayTicketBucket {
    uint256 templateId;
    uint256 sourceId; // offerId or requestId
    address underwriter;
    uint128 maxPayoutPerUnit;
    uint128 unitsMinted;
    uint128 unitsClaimed;
    uint128 payoutPerUnit;
    uint256 escrowRemaining;
    uint8 sourceType; // offer or request
    bool finalized;
}
```

Ticket ID:

```solidity
ticketId = uint256(keccak256(abi.encode(
    PARLAY_TICKET_DOMAIN,
    templateId,
    sourceType,
    sourceId,
    underwriter,
    maxPayoutPerUnit
)));
```

Recommended V1 ticket model:

- ERC-1155 semi-fungible units,
- one ticket ID per homogeneous filled offer/request exposure bucket,
- amount = units held.

Bucket accounting is settlement-critical because ticket units can transfer after fill. The protocol must not assume the original buyer still owns the tickets.

Finalization and claim accounting:

- `finalized == false` while any referenced leg is unresolved,
- once all required outcomes are known, anyone can finalize the bucket,
- finalization computes one immutable `payoutPerUnit`,
- finalization releases unused escrow back to the underwriter immediately,
- ticket holders claim by burning ERC-1155 units,
- each burned unit receives `payoutPerUnit`,
- `unitsClaimed` tracks burned/claimed units,
- `escrowRemaining` must always be enough to pay all unclaimed ticket units at `payoutPerUnit`.

This avoids a liveness failure where underwriters cannot recover residual escrow because holders of worthless or low-value tickets never call settlement.

---

## 8. Metadata Model

Use on-chain Base64 metadata for human/UI display, consistent with current `LibMarketMetadata` patterns.

Current code already supports Base64 `data:application/json;base64,...` metadata for market position tokens through `positionTokenURI`.

Parlay tickets should follow the same design.

### 8.1 Important Rule

Metadata is not the settlement source.

```text
Typed storage / validated terms -> settlement
Base64 JSON metadata -> display
```

Do not parse JSON on-chain.

### 8.2 Ticket Metadata Fields

Generated token metadata should include:

```json
{
  "name": "Eves Parlay Ticket",
  "description": "Peer-to-peer underwritten compound event ticket.",
  "template_id": "...",
  "ticket_id": "...",
  "creator": "0x...",
  "underwriter": "0x...",
  "premium_per_unit": "10",
  "max_payout_per_unit": "100",
  "invalid_policy": "VoidInvalidLegs",
  "legs": [
    { "market_id": "0x...", "required_outcome": "YES" },
    { "market_id": "0x...", "required_outcome": "NO" }
  ],
  "payout_tiers": [
    { "min_hits": 5, "payout": "100" },
    { "min_hits": 4, "payout": "25" }
  ]
}
```

For gas/display sanity, V1 may generate compact metadata and let indexers render richer UI from events.

---

## 9. Core Flows

### 9.1 Create Template

```solidity
function createParlayTemplate(
    ParlayLeg[] calldata legs,
    PayoutTier[] calldata payoutTiers,
    InvalidPolicy invalidPolicy,
    string calldata metadataHint
) external returns (uint256 templateId);
```

Flow:

1. Validate legs.
2. Validate payout tiers.
3. Canonicalize terms.
4. Compute `templateId`.
5. Store template and terms.
6. Emit full `ParlayTemplateCreated` event.

### 9.2 Post Maker Offer

```solidity
function postParlayOffer(
    uint256 templateId,
    uint128 premiumPerUnit,
    uint128 maxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
) external returns (uint256 offerId);
```

Flow:

1. Validate template exists.
2. Validate template still fillable.
3. Validate premium/payout/units/deadline.
4. Transfer `maxPayoutPerUnit * units` from maker to escrow.
5. Store offer.
6. Emit `ParlayOfferPosted`.

### 9.3 Fill Maker Offer

```solidity
function fillParlayOffer(
    uint256 offerId,
    uint128 units,
    address receiver
) external returns (uint256 ticketId);
```

Flow:

1. Validate offer active and not expired.
2. Validate units <= remaining units.
3. Transfer `(premiumPerUnit + PARLAY_UNDERWRITING_FEE) * units` from buyer.
4. Route `premiumPerUnit * units` to the underwriter.
5. Split `PARLAY_UNDERWRITING_FEE * units` between the vault and `feeRecipient`.
6. Reduce offer remaining units.
7. Create/update filled position bucket.
8. Mint ERC-1155 parlay ticket units to receiver.
9. Emit `ParlayOfferFilled`.

### 9.4 Post Buyer Request

```solidity
function postParlayRequest(
    uint256 templateId,
    uint128 premiumPerUnit,
    uint128 desiredMaxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
) external returns (uint256 requestId);
```

Flow:

1. Validate template exists.
2. Validate requested terms.
3. Transfer `(premiumPerUnit + PARLAY_UNDERWRITING_FEE) * units` from requester to escrow.
4. Store request.
5. Emit `ParlayRequestPosted`.

### 9.5 Fill Buyer Request as Underwriter

```solidity
function fillParlayRequest(
    uint256 requestId,
    uint128 units,
    address ticketReceiver
) external returns (uint256 ticketId);
```

Flow:

1. Validate request active and not expired.
2. Validate units <= remaining units.
3. Transfer `desiredMaxPayoutPerUnit * units` from underwriter to payout escrow.
4. Release `premiumPerUnit * units` from request escrow to underwriter.
5. Split `PARLAY_UNDERWRITING_FEE * units` from request escrow between the vault and `feeRecipient`.
6. Mint ERC-1155 parlay ticket units to requester or `ticketReceiver` depending UX choice.
7. Emit `ParlayRequestFilled`.

Default V1 should mint to original requester. Optional delegated receiver can be added with care.

### 9.6 Cancel Unfilled Offer/Request

Offer cancellation:

- maker can cancel unfilled units,
- unfilled escrow returns to maker,
- already filled ticket escrow remains locked.

Request cancellation:

- requester can cancel unfilled units,
- unfilled premium and flat fee escrow returns to requester,
- already filled tickets remain live.

### 9.7 Finalize Ticket Bucket

```solidity
function finalizeParlayTicketBucket(uint256 ticketId) external returns (uint128 payoutPerUnit);
```

Flow:

1. Validate ticket bucket exists.
2. Check all referenced markets are resolved to canonical final outcomes.
3. Compute hits/misses/invalids.
4. Apply invalid policy.
5. Determine immutable `payoutPerUnit` from payout tiers.
6. Mark bucket finalized.
7. Reserve `payoutPerUnit * unclaimedUnits` for ticket holders.
8. Return any excess escrow to the underwriter.
9. Emit `ParlayTicketBucketFinalized`.

Finalization is permissionless. It should not require the ticket holder to call, because underwriters need a way to recover residual escrow even when ticket holders are inactive.

### 9.8 Claim Ticket Payout

```solidity
function claimParlayTicket(
    uint256 ticketId,
    uint128 units,
    address receiver
) external returns (uint256 payout);
```

Flow:

1. Validate ticket exists.
2. Validate ticket bucket is finalized.
3. Validate caller has at least `units` ticket units.
4. Burn claimed ERC-1155 ticket units.
5. Transfer `payoutPerUnit * units` to `receiver`.
6. Increment `unitsClaimed`.
7. Emit `ParlayTicketClaimed`.

V1 can require all legs resolved before settlement. Later optimization can allow early settlement when payout is mathematically fixed.

---

## 10. Settlement Semantics

### 10.1 Hit Count

For each leg:

- if underlying market outcome == required outcome: hit,
- if underlying market outcome is another real outcome: miss,
- if underlying market outcome invalid: invalid.

### 10.2 Invalid Policy Behavior

`VoidInvalidLegs`:

- invalid legs are removed from denominator,
- payout tiers apply against remaining valid legs,
- recommended V1 default.

`InvalidCountsAsMiss`:

- invalid leg counts as a miss.

V1 recommendation:

- implement `VoidInvalidLegs`,
- implement `InvalidCountsAsMiss` if product wants a stricter maker-friendly option,
- reject unsupported invalid policies at template creation.

`RefundAll` is not a V1 policy. Premium is paid to the underwriter and the flat fee is routed at fill time. Supporting refund semantics requires premium/fee escrow until finalization or explicitly non-refundable premium and fee terms. That is a separate design.

For `VoidInvalidLegs`, tiers apply to the remaining valid legs using absolute hit counts. They do not automatically rescale.

Example:

```text
Original ticket:
5 legs
5/5 pays 100
4/5 pays 25

One leg resolves invalid.
Four valid legs remain.

If all four valid legs hit:
hits = 4
payout = 25
```

If all legs are invalid under `VoidInvalidLegs`, V1 should pay zero from the payout escrow and release escrow to the underwriter. The UI must label this clearly because the premium remains paid.

### 10.3 Partial Payouts

Payout tiers support partial hits.

Traditional parlays are normally one-and-done:

```text
5 legs total
5 hits -> 100
0-4 hits -> 0
```

Eves parlays may also be tiered/system-style:

```text
5 legs total
5 hits -> 100
4 hits -> 80
3 hits -> 40
2 hits -> 20
0-1 hits -> 0
```

This allows makers to write softer or more nuanced contracts without arbitrary payout scripts.

Tiered payouts are especially valuable for secondary markets because tickets can retain value after a miss.

All-or-nothing:

```text
first leg misses -> ticket is likely dead
```

Tiered payout:

```text
first leg misses -> 5/5 is impossible, but 4/5 may still pay
```

This makes live tickets more tradeable and gives underwriters more ways to shape risk.

Recommended UI labels:

- **All-or-nothing parlay** — only the highest hit count pays.
- **Tiered payout parlay** — multiple hit counts pay.
- **Protected parlay** — miss tolerance is part of the product framing.
- **System parlay** — more traditional betting terminology for multi-tier hit-count payouts.

### 10.4 Early Settlement

V1:

- settle only after all legs are resolved.

Later:

- settle early if the maximum possible future hit count cannot change payout tier.

Example:

```text
5/5-only parlay
first leg misses
payout locked at 0
can settle early
```

---

## 11. CLOB Integration

### 11.1 Primary Book

Primary parlay offers/requests are a native on-chain order surface, not a normal fungible CLOB, because every template/offer/request can be unique.

They behave like a structured orderbook:

- offers are executable maker quotes,
- requests are executable buyer bids,
- fill/cancel state is on-chain,
- collateral/premium escrow is on-chain.

### 11.2 Secondary Ticket CLOB

Filled parlay tickets are ERC-1155 assets and should use a generic ERC-1155 book architecture:

```text
base asset: ParlayTicket ERC1155 ticketId
quote asset: eveUSD
```

This is where standard CLOB mechanics fit best.

Implementation requirement:

- add dedicated `createParlayTicketBook(ticketId, ...)` support.

Parlay ticket books should use generic absolute quote pricing. A ticket that can pay 100 eveUSD should be listable at 10, 20, 40, or 90 eveUSD per ticket unit. It should not be forced into prediction-share pricing unless ticket units are normalized to one eveUSD of max payout.

Secondary trading should be added after primary fill/finalize/claim works, unless generalized ERC-1155 books make it nearly free to support immediately.

---

## 12. Reputation and Ranking

Reputation should be mostly reconstructable from events.

### 12.1 Template Creator Metrics

- templates created,
- filled volume,
- unique buyers,
- unique underwriters,
- copied/remixed templates,
- total ticket payouts,
- buyer ROI,
- hit rate,
- invalid/dispute frequency,
- secondary ticket volume.

### 12.2 Underwriter Metrics

- total premium earned,
- total payout paid,
- net PnL,
- ROI on escrow,
- average escrow duration,
- categories underwritten,
- fill responsiveness,
- cancelled offer rate,
- risk concentration.

### 12.3 Buyer Metrics

- ticket volume,
- realized PnL,
- hit rate,
- followed creators,
- active tickets.

Reputation can be calculated by DevCo infra at first, but the core economic inputs must come from events so others can rebuild it.

---

## 13. Events

Events should emit enough data for walkaway reconstruction.

```solidity
event ParlayTemplateCreated(
    uint256 indexed templateId,
    address indexed creator,
    ParlayLeg[] legs,
    PayoutTier[] payoutTiers,
    uint8 invalidPolicy,
    string metadataHint
);

event ParlayOfferPosted(
    uint256 indexed offerId,
    uint256 indexed templateId,
    address indexed maker,
    uint128 premiumPerUnit,
    uint128 maxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
);

event ParlayOfferFilled(
    uint256 indexed offerId,
    uint256 indexed ticketId,
    address indexed buyer,
    uint128 units,
    uint128 premiumPaid,
    uint128 flatFeePaid,
    uint128 escrowLocked
);

event ParlayRequestPosted(
    uint256 indexed requestId,
    uint256 indexed templateId,
    address indexed requester,
    uint128 premiumPerUnit,
    uint128 desiredMaxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
);

event ParlayRequestFilled(
    uint256 indexed requestId,
    uint256 indexed ticketId,
    address indexed underwriter,
    uint128 units,
    uint128 premiumPaid,
    uint128 flatFeePaid,
    uint128 escrowLocked
);

event ParlayFlatFeeRouted(
    uint256 indexed ticketId,
    uint256 indexed sourceId,
    uint8 indexed sourceType,
    uint256 feeAmount,
    uint256 vaultAmount,
    uint256 feeRecipientAmount
);

event ParlayTicketBucketFinalized(
    uint256 indexed ticketId,
    address indexed underwriter,
    uint8 hits,
    uint8 misses,
    uint8 invalids,
    uint128 payoutPerUnit,
    uint128 unitsOutstanding,
    uint256 claimReserve,
    uint256 escrowReturned
);

event ParlayTicketClaimed(
    uint256 indexed ticketId,
    address indexed holder,
    address indexed receiver,
    uint128 units,
    uint128 payoutPerUnit,
    uint256 payout
);
```

---

## 14. Security and Invariants

### 14.1 Hard Invariants

1. Max payout liability for every filled ticket unit is fully escrowed.
2. Ticket payout cannot exceed escrow assigned to that ticket bucket.
3. A ticket can only be settled once per burned unit.
4. Offer/request remaining units cannot underflow.
5. Cancelled unfilled units cannot be filled.
6. Filled ticket escrow cannot be withdrawn by maker before settlement.
7. Settlement must derive only from underlying on-chain market outcomes and typed parlay terms.
8. Base64 metadata must never be parsed for settlement.
9. Flat parlay fee routing cannot exceed collected flat fees.
10. Invalid policy must be explicit and immutable per template/ticket.
11. Finalized bucket `payoutPerUnit` must be immutable.
12. Bucket claim reserve must always cover every outstanding ticket unit at `payoutPerUnit`.
13. Finalization must release only escrow above the required claim reserve.
14. Parlay settlement must not depend on whether the referenced market used orderbook or parimutuel liquidity.

### 14.2 Threats

| Threat | Mitigation |
|--------|------------|
| Underwriter cannot pay | Require full escrow before fill/live offer |
| Metadata lies | Settlement ignores metadata; uses typed storage |
| DevCo API disappears | Events + storage reconstruct state |
| Maker cancels after fill | Only unfilled units cancellable |
| Worthless ticket holders never claim | Permissionless bucket finalization releases residual escrow |
| Duplicate/contradictory legs | Canonical validation rejects duplicate markets |
| Poison invalid policy | Small allowed enum; clear UI warnings |
| Overly complex payout scripts | V1 hit-count payout tiers only |
| Fee drain | Bounded flat fee routing and split-sum tests |
| Reentrancy | Use existing Diamond reentrancy guard pattern |

---

## 15. Relationship to Existing Eve Predict Code

Current relevant code:

- `LibEveMarket.sol` defines market/outcome/state types.
- `LibParimutuel.sol` manages binary parimutuel payout pools.
- `ParimutuelFacet.sol` handles pooled YES/NO entry and claim.
- `ParimutuelShareToken.sol` is ERC-1155 with Diamond-only mint/burn and on-chain metadata hook.
- `LibMarketMetadata.sol` already builds Base64 on-chain metadata.
- Existing fee routing code may be useful for protocol/vault accounting, but parlay fills should not create template creator or underlying market creator fee claims in V1.
- `OBRResolutionFacet.sol` finalizes market outcomes and parimutuel pools.
- `MarketSettlementFacet.sol` previews CTF/parimutuel redemption.

Recommended implementation is a distinct parlay surface:

```text
LibParlay
ParlayAdminFacet
ParlayUnderwritingFacet
ParlaySettlementFacet
ParlayBookFacet
ParlayViewFacet
ParlayMulticallFacet
ParlayTicketToken
IParlayFacet shared external surface
```

Do not overload current `ParimutuelFacet`. Parlays are bilateral underwritten payout contracts, not pooled parimutuel markets.

Parimutuel markets are still valid parlay legs. The distinction is architectural:

- `ParimutuelFacet` manages pooled entry, epoch multipliers, share minting, and parimutuel claims.
- The parlay facets share `LibParlay` diamond storage and only read finalized Eve market outcomes for referenced markets.

The parlay layer should treat orderbook and parimutuel markets the same once they have a canonical final binary outcome.

---

## 16. V1 Scope Recommendation

V1 should include:

- binary underlying Eve markets only, including both orderbook and parimutuel markets,
- scheduled and active unresolved markets as valid legs,
- 2-8 legs,
- hit-count payout tiers supporting both all-or-nothing and tiered/system payout structures,
- events/metadata sufficient for indexers to compute portfolio-level exposure across direct positions and parlay tickets,
- visual strategy-builder support at the event/indexer layer for grouping direct positions, hedge requests, and filled tickets,
- `VoidInvalidLegs` invalid policy, with optional `InvalidCountsAsMiss` if product wants a stricter maker-friendly option,
- maker-posted offers with escrow at post time,
- buyer-posted requests with premium plus flat fee escrow,
- underwriter fill of buyer requests,
- cash-covered underwriting only: escrow eveUSD max payout, do not buy underlying leg positions,
- ERC-1155 semi-fungible tickets,
- ticket transferability and secondary CLOB-ready ticket IDs,
- permissionless ticket bucket finalization,
- holder claims by burning ticket units,
- immediate release of residual escrow above the claim reserve during finalization,
- dedicated `createParlayTicketBook` support for secondary ticket trading,
- on-chain Base64 ticket metadata,
- settlement after all legs resolve,
- configurable flat eveUSD fee per underwritten parlay unit, initially 3 eveUSD, split between vault and `feeRecipient`,
- on-chain `StrategyCreated` event for maker/taker attribution and grouped strategy reconstruction,
- router support for batch-buying direct positions and posting hedge parlay requests,
- events sufficient for walkaway indexing,
- tests for all value-moving flows.

V1 should not include:

- undercollateralized underwriting,
- arbitrary payout scripts,
- JSON parsing on-chain,
- off-chain-only order discovery,
- protocol-priced odds,
- protocol balance-sheet risk,
- multi-outcome legs unless already stable,
- `RefundAll` invalid policy,
- protocol-managed hedge-covered underwriting,
- underwriter receipt tokens for residual hedge value,
- early settlement optimization unless simple.

---

## 17. Resolved V1 Decisions

1. Maker offers escrow all units at post time.
2. Buyer request tickets mint to the original requester in V1.
3. `RefundAll` is not supported.
4. `PARLAY_UNDERWRITING_FEE` is configurable, with an initial target of 3 eveUSD per underwritten parlay unit.
5. Flat parlay fees split between the vault and `feeRecipient` using configurable bps.
6. Secondary ticket trading uses a dedicated `createParlayTicketBook(ticketId, ...)` path.
7. Token metadata should include enough ticket/template information to be useful in wallets and explorers, but rich displays should be reconstructed by indexers from events.
8. Ticket bucket finalization has no bounty in V1. Ticket holders want finalization to claim payouts; underwriters want finalization to recover residual escrow.
9. Remixing/copying templates is supported at the UI/indexer layer. On-chain events must record template creator, offer maker, request creator, underwriter, ticket holder, and strategy creator for attribution.
10. Offers and requests support partial fills by default, so makers can post volume such as ten 10 eveUSD five-leg parlays.
11. Hedge construction is a UI/router flow, not a separate parlay collateral mode. The UI can build direct multi-leg exposure, apply a hedge profile, write/post parlay requests, and execute direct bet legs.
12. No `UnderwriterReceipt` token is needed for V1.
13. `StrategyCreated` should be an on-chain event for maker/taker attribution and strategy reconstruction.
14. The router should support combined execution that batch-buys direct positions and posts hedge parlay requests.
15. Scheduled markets are valid parlay legs. Parlays cannot finalize until every referenced market has resolved.

### 17.1 Indexer Event Requirements

Events should be sufficient to reconstruct:

- template creator and canonical template terms,
- offer maker and offer inventory,
- request creator and request inventory,
- underwriter for every filled ticket bucket,
- ticket holder claims,
- premium paid,
- flat fee paid and routed amounts,
- max payout escrow locked,
- payout per unit at finalization,
- escrow returned to underwriter,
- strategy creator and grouped direct/parlay components.

---

## 18. Product Copy

Buyer-facing:

> Build a moonshot thesis. Buy the payout you want.

Strategy-builder-facing:

> Build the thesis. Buy the exposure. Hedge the failure modes.

Request-facing:

> Publish your parlay. Let underwriters compete to take the other side.

Underwriter-facing:

> Earn premium by underwriting compound event risk. Choose your exposure. Set your price.

Secondary-market-facing:

> Buy the thesis. Sell the sweat.

Creator-facing:

> Create parlays people want to trade. Build reputation from real volume and outcomes.

Protocol-facing:

> No house. No hidden balance sheet. Every ticket is escrowed and settled on-chain.

Secondary liquidity framing:

> Cashout is not a house feature. It is a market.

---

## 19. Bottom Line

This turns parlays from a centralized sportsbook product into a permissionless risk marketplace.

The exciting loop is two-sided:

1. A user publishes a crazy parlay and desired odds.
2. A maker sees it and thinks, "no way this hits, easy premium."
3. The maker underwrites it with escrowed collateral.
4. If it misses, the maker earns yield.
5. If it hits, the buyer gets paid from escrow.
6. Both outcomes create public reputation data.

That is the product.
