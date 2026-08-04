# Eves Market — Design Document
## On-Chain Prediction Market Protocol

> **Status notice (updated 2026-08-04):** Active protocol chapters track the
> canonical Statics Dollar launch rail, internal Senior capital, canonical CTF,
> and current governance controls. The predecessor `eveUSDC` wrapper and
> `eveUSD`/`EtRisk` chapters are retained only as historical design context and
> are superseded by
> [`docs/launch-collateral-direction-change.md`](./docs/launch-collateral-direction-change.md).

**Version:** 3.5
**Module:** Eves Market — On-Chain Prediction Market Protocol

---

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Architecture](#architecture)
4. [Market Types](#market-types)
5. [Collateral Profiles & Wrappers](#collateral-profiles--wrappers)
6. [Curve CLOB Trading](#curve-clob-trading)
7. [Books & Spot Trading](#books--spot-trading)
8. [Parimutuel Markets](#parimutuel-markets)
9. [Multi-Outcome Orderbook Markets](#multi-outcome-orderbook-markets)
10. [Native Positions & Combinatorial Markets](#native-positions--combinatorial-markets)
11. [Parlays](#parlays)
12. [Delayed Orders](#delayed-orders)
13. [Resolution & Disputes](#resolution--disputes)
14. [Resolver Jury, Registry & Identity](#resolver-jury-registry--identity)
15. [Fee System](#fee-system)
16. [Market Settlement](#market-settlement)
17. [Data Models](#data-models)
18. [View Functions](#view-functions)
19. [Trade Router](#trade-router)
20. [Statics Dollar Collateral Rail & Internal Senior Capital](#statics-dollar-collateral-rail--internal-senior-capital)
21. [Historical Predecessor: eveUSD ETH-Backed Stablecoin](#historical-predecessor-eveusd-eth-backed-stablecoin)
22. [Faucet](#faucet)
23. [Events](#events)
24. [Security Considerations](#security-considerations)
25. [Appendix: Correctness Properties](#appendix-correctness-properties)

---

## Overview

Eves Market is an onchain prediction market protocol targeting Robinhood Chain. It is structured as an EIP-2535 Diamond with modular facets sharing a single storage layout. The protocol started as a two-type binary market (Curve CLOB and Parimutuel) and has grown into a broader exchange surface that also supports multi-outcome orderbook markets, native combinatorial (parlay-style) positions, peer-to-peer parlays, standalone spot books, and MEV-resistant delayed taker orders.

Markets are resolved through an Optimistic Bond-based Resolution (OBR) system. Instead of escalating to token-weighted governance voting, fully escalated disputes are now decided by a **Resolver Jury** — a staked, soulbound-identity committee that uses commit-reveal randomness for selection and commit-reveal voting for the verdict.

Eves uses **Statics Dollar** from the pinned canonical Statics protocol as its launch collateral, bond, Senior-capital, and MLO-insurance asset. Users may supply Statics Dollar directly or mint an exact amount from the configured pegged asset (USDG on Robinhood testnet) through the shared `StaticsDiamond` gateway. Pegged profiles mint no Risk Shares; their mint fee remains isolated Statics protocol revenue.

> **Naming note:** `USDC` remains in a few internal selector and environment names for compatibility, but the Robinhood testnet pegged asset is USDG. Names such as `eveUSDC`, `etUSD`, `eveUSD`, and `EtRisk` describe predecessor designs only and are not live deployment surfaces.

### Key Characteristics

| Feature | Description |
|---------|-------------|
| **Diamond Pattern** | EIP-2535 Diamond proxy with modular facets and a shared storage layout |
| **Multiple Market Types** | CLOB (maker curves), Parimutuel (pooled entry), and Multi-Outcome Orderbook (N-way CLOB) |
| **Book Abstraction** | Per-side order books with independent fee configs and accounting |
| **Spot Books** | Standalone books for trading ERC-20 / ERC-1155 base assets (including FoT tokens) |
| **CTF Positions** | Gnosis Conditional Tokens for binary CLOB and NegRisk multi-outcome position management |
| **Native Positions** | In-Diamond ERC-1155 (`EvesPositionManager`) for combinatorial positions |
| **Combinatorial Markets** | Native AND-of-legs combo conditions with split/merge/branch/compress operations |
| **Parlays** | Peer-to-peer underwritten multi-leg tiered-payout bets with shared budgets |
| **Parimutuel Shares** | Dedicated ERC-1155 (`ParimutuelShareToken`) for pooled positions with an epoch multiplier |
| **OBR Resolution** | Optimistic Bond-based Resolution backed by a generic bond token |
| **Resolver Jury** | Staked soulbound-identity commit-reveal jury as the dispute backstop |
| **Collateral Profiles** | Pluggable collateral tokens selected per product, with Statics Dollar as the launch default |
| **Statics Dollar Collateral** | Canonical Statics stable asset with exact USDG mint-and-buy routing through `StaticsDiamond` |
| **Internal Senior Capital** | Non-transferable stored units, indexed fees, bucket reservations, pro-rata loss scaling, and FIFO exits inside the Eve Diamond |
| **Delayed Orders** | Block-delayed taker orders with permissionless/protocol processing |
| **Statics Dependency** | A pinned external Core/gateway supplies Statics Dollar and enforces current pegged-profile policy |
| **Governance Delay** | Exact-calldata timelock protects owner-gated configuration and integration rotation after finalization |
| **Permissionless** | Anyone can create markets, post curves, and resolve |

### System Participants

| Role | Description |
|------|-------------|
| **Creator** | Creates markets with a creation fee and bond token deposit |
| **Maker** | Posts price curves and earns maker fees |
| **Taker** | Fills curves to acquire positions |
| **Bettor** | Buys YES or NO shares in parimutuel markets |
| **Underwriter / Requester** | Posts or fills parlay offers/requests |
| **Resolver** | Submits settlement proposals (creator or community) |
| **Juror** | Staked soulbound resolver identity selected onto a dispute committee |
| **Processor** | Executes queued delayed orders (protocol or permissionless) |
| **Senior Capital Provider** | Deposits Statics Dollar into the Diamond's non-transferable Senior-capital ledger |


---

## How It Works

### The Core Model

Eves Market follows a market creation → trading → resolution → settlement lifecycle:

1. **Create** — A creator defines a binary (or multi-outcome) question, a required `resolutionSource`, an optional `tradingStartTime`, and an `expiryTime`, pays a collateral creation fee, and posts a bond-token creation bond. Binary CLOB markets prepare a Gnosis CTF condition; multi-outcome markets prepare one binary CTF condition per outcome through `EvesNegRiskAdapter`; combinatorial markets use the native `EvesPositionManager`; parimutuel markets register with the `ParimutuelShareToken`.

2. **Trade** — In CLOB markets, makers split collateral into position tokens and post price curves; takers fill curves. In parimutuel markets, users buy single-side shares into a payout pool. In multi-outcome markets, users split collateral into a full outcome set and trade each outcome's book. Fees can route among maker, creator, protocol treasury, the Diamond's Senior fee index, and the active resolver epoch depending on the product config and route eligibility.

3. **Resolve** — After expiry, the creator gets first right to settle. If they don't, the community can propose outcomes with escalating bond deposits. Fully escalated disputes are routed to the Resolver Jury for a commit-reveal verdict.

4. **Settle** — CTF and native position holders redeem winning tokens for collateral. Parimutuel winners claim their pro-rata share of the payout pool. Honest creators get their bond back and can claim escrowed fees.

### Collateral Backing

- **Binary CLOB markets:** Positions are fully backed by collateral locked in the Gnosis CTF (split mints equal YES/NO, redeem burns and releases backing).
- **Multi-outcome markets:** Backed by mutually exclusive one-vs-rest CTF conditions managed by `EvesNegRiskAdapter`; splitting produces one tradable YES token per outcome and merging consumes an equal complete set.
- **Combinatorial markets:** Backed by native conditions held in `EvesPositionManager`; splitting and merging operate on a combo YES/NO pair.
- **Parimutuel markets:** All entry collateral (minus fees) enters the payout pool; winners claim pro-rata, INVALID refunds both sides.
- **Parlays:** The underwriter escrows the maximum payout; tickets pay out from that escrow per the payout tier schedule.

### Collateral Rail

The protocol's launch collateral and margin asset is **Statics Dollar** from the pinned Statics Core. USDG enters through an active pegged profile on the shared `StaticsDiamond`; additional collateral tokens can be registered through Eve collateral profiles. Senior capital is a Statics-Dollar-denominated namespaced ledger inside the Diamond, and direct ERC-20 transfers do not create principal or fee claims.

---

## Architecture

### Contract Structure

```text
eve-predict/src/
├── EveMarketDiamond.sol              # EIP-2535 Diamond proxy
├── EvesCTFSettlementAdapter.sol       # Binary CTF split/merge/redeem adapter
├── EvesNegRiskAdapter.sol             # Canonical NegRisk multi-outcome adapter
├── MLOInventoryVault.sol              # Bucket-scoped MLO outcome custody
├── MLOInsuranceFund.sol               # Dedicated Statics Dollar insurance reserve
├── Faucet.sol                         # Multi-token testnet faucet
├── facets/
│   ├── MarketFactoryFacet.sol         # Market creation and lifecycle
│   ├── MarketGroupFacet.sol           # Market-group registration and metadata
│   ├── MarketViewFacet.sol            # Market queries and views
│   ├── CurveCLOBFacet.sol             # Public binary CLOB fills
│   ├── CurveInventoryFacet.sol        # Split/merge inventory
│   ├── CurveLifecycleFacet.sol        # Curve posting, update, cancel, top-up
│   ├── CurveViewFacet.sol             # Curve views and previews
│   ├── BookFacet.sol / BookOrderFacet.sol / BookTradeFacet.sol / BookSellFacet.sol
│   ├── BookViewFacet.sol              # Standalone and market-linked book views
│   ├── CollateralTradeRouterFacet.sol # Direct collateral buys (+ permit)
│   ├── CollateralTradeRouterExactFacet.sol # Exact-fill collateral buys
│   ├── CollateralTradeRouterSellFacet.sol  # Direct collateral sells
│   ├── StaticsDollarTradeRouterFacet.sol   # USDG → Statics Dollar → position
│   ├── TradeRouterBookFacet.sol / TradeRouterBookSellFacet.sol
│   ├── ParimutuelFacet.sol / ParimutuelViewFacet.sol
│   ├── MultiOutcomeOrderbookFacet.sol / MultiOutcomeOrderbookViewFacet.sol
│   ├── MLOPrediction*Facet.sol        # MLO post/update/trade/recovery/settlement
│   ├── MarginAccountFacet.sol         # Shared margin accounts and risk buckets
│   ├── SeniorCapitalFacet.sol / SeniorCapitalViewFacet.sol
│   ├── MLOProfitShareFacet.sol        # Delayed MLO profit-split configuration
│   ├── MarkOracleFacet.sol / QuoteEnvelopeFacet.sol
│   ├── NegRiskConfigFacet.sol         # Validated CTF adapter configuration
│   ├── DelayedOrderFacet.sol          # Block-delayed taker orders
│   ├── FeeConfigFacet.sol / FeeRouterFacet.sol
│   ├── OBRResolutionFacet.sol / BondManagerFacet.sol / BondTokenGateFacet.sol
│   ├── ResolverRegistry*Facet.sol / ResolverJuryFacet.sol
│   ├── DiamondCutFacet.sol / DiamondLoupeFacet.sol / OwnershipFacet.sol
│   ├── native/
│   │   ├── ComboCoreFacet.sol
│   │   ├── ComboMarketFacet.sol
│   │   ├── ComboSettlementFacet.sol
│   │   └── ComboViewFacet.sol
│   └── parlay/                        # Admin, underwriting, budgets, books, settlement, views
├── init/                              # Diamond initializers
├── tokens/                            # Position, ticket, and identity tokens
├── interfaces/                       # Contract interfaces
├── types/                            # Facet param/view structs
├── libraries/                        # Storage, execution, risk, and helper libraries
└── mocks/                            # Test-only assets and integrations
```

### Diamond Pattern

The `EveMarketDiamond` is an EIP-2535 Diamond proxy that delegates calls to modular facets. Most facets share a single storage layout defined in `LibEveMarket.EveMarketStorage`, accessed via a deterministic storage slot. Several subsystems use their own dedicated storage slots to keep layouts isolated:

- **Parimutuel pools** — `LibParimutuel.Storage`
- **Parlays** — `LibParlay.Storage`
- **Resolver Jury** — `LibResolverJury.Storage`
- **Senior capital** — `LibSeniorCapital.Storage`
- **MLO profit sharing** — `LibMLOProfitShare.Storage`
- **Governance delay** — `LibGovernanceDelay.Storage`

The Diamond supports DiamondCut (add/replace/remove facet functions), selector freezing (permanently locking critical selectors), and ERC-1155 receiver hooks (accepting position transfers for escrow and settlement).

### Governance Delay

After one-time finalization, every owner-gated call that uses `LibDiamond.enforceIsContractOwner()` must match an exact calldata operation previously scheduled through `DiamondCutFacet`. Operation IDs bind `block.chainid`, the Diamond address, and calldata; execution consumes the schedule entry. Raw-owner bootstrap and schedule/cancel calls remain available through `enforceIsContractOwnerRaw()`.

```solidity
(bytes32 operationId, uint256 readyAt) = diamondCut.scheduleGovernanceOperation(callData);
diamondCut.cancelGovernanceOperation(operationId);
diamondCut.finalizeGovernanceDelay(finalOwner, initialDelay); // one time
// A change to the delay is itself governed by the active delay.
diamondCut.setGovernanceDelay(newDelay);
uint64 delay = diamondCut.governanceDelay();
```

The delay is deployment-configured: the current Robinhood testnet fallback is 15 minutes, while production configuration is expected to set seven days explicitly. Selector freezing remains irreversible and independent of the timelock.

### Governed Integration Rotation

The configured margin asset, NegRisk adapter, and binary CTF settlement adapter can be replaced through owner-gated calls only after the exact calldata has passed the finalized Diamond delay:

```solidity
marginAccount.setMarginAsset(newAsset);
negRiskConfig.setNegRiskAdapter(newNegRiskAdapter);
negRiskConfig.setCTFSettlementAdapter(newCTFSettlementAdapter);
```

`setMarginAsset` requires the replacement to be a contract and rejects rotation while any user-margin liability, pending or active Senior principal, exit claim, Senior fee reserve, or MLO Senior-reward reserve remains. Adapter setters validate their CTF, collateral, and oracle bindings. Markets and CTF positions snapshot collateral and settlement-adapter addresses, so rotation applies to new exposure without changing historical settlement routes; combo custody classifies those historical routes by the position's stored module ID rather than the current global adapter.

The CLOB engine is decomposed across multiple facets for bytecode-size management. `CurveCLOBFacet` is an aggregating entry point; `CurveInventoryFacet`, `CurveLifecycleFacet`, and `CurveViewFacet` provide split/merge, posting/lifecycle, and views respectively. Standalone book operations live in `BookFacet` / `BookOrderFacet` / `BookTradeFacet` / `BookViewFacet`.

Standalone contracts (`EvesCTFSettlementAdapter`, `EvesNegRiskAdapter`, `MLOInventoryVault`, `MLOInsuranceFund`, and `Faucet`) operate outside the Eve Diamond. The pinned Statics Core/gateway provides Statics Dollar externally. Senior capital is deliberately not an external contract: custody, MLO reservations, indexed fee accounting, loss scaling, and exits share a dedicated namespaced Diamond storage slot.

> **Note on renames since v2.1:** the former `SpotBook*Facet` family is now `Book*Facet`, and the former `EveTokenGateFacet` is now `BondTokenGateFacet`. The bond gate no longer locks an EVE governance token — it locks a generic `config.bondToken` for resolution bonds.

---

## Market Types

Every market declares its type at creation time. The type determines position-token semantics, trading mechanics, fee structure, and settlement path.

### MarketType Enum

```solidity
enum MarketType {
    CLOB,                    // Binary curve-based order book with CTF positions
    PARIMUTUEL,              // Pooled entry with pro-rata payout
    MULTI_OUTCOME_ORDERBOOK  // N-way mutually-exclusive outcome book (NegRisk CTF positions)
}
```

### PositionTokenType Enum

```solidity
enum PositionTokenType {
    CTF,            // Gnosis Conditional Tokens Framework (ERC-1155)
    PARIMUTUEL,     // ParimutuelShareToken (ERC-1155)
    EVES_POSITION   // EvesPositionManager (ERC-1155, combinatorial positions)
}
```

> Combinatorial "combo" markets are not a distinct `MarketType`; they are built on the native `EVES_POSITION` infrastructure (`ComboMarket` records and combo conditions) rather than a market-type enum value.

### MarketState Enum

```solidity
enum MarketState {
    Inactive,
    Scheduled,   // Created with a future tradingStartTime
    Trading,
    Pending,     // Expired, awaiting resolution
    Resolved,
    Disputed
}
```

`Scheduled` supports markets created ahead of a `tradingStartTime`; they transition to `Trading` once the start time passes.

### MarketOutcome Enum

```solidity
enum MarketOutcome { Unresolved, Yes, No, Invalid }   // 0,1,2,3
```

For multi-outcome markets the resolved outcome is the winning outcome index (or an INVALID sentinel).

### Other Enums

```solidity
enum CurveSide { ASK, BID }
enum BookAssetType { ERC1155, ERC20 }
enum BaseTransferMode { EXACT, BALANCE_DELTA }   // BALANCE_DELTA for fee-on-transfer tokens
enum BookPricingMode { PREDICTION_PAYOUT, GENERIC }
enum BookLifecycle { ACTIVE, DECOMMISSION_PENDING, DECOMMISSIONED }
enum DelayedOrderKind { MarketBuy, LimitBuy, MarketSell, LimitSell }
enum DelayedOrderStatus { Pending, Filled, PartiallyFilled, Resting, Cancelled, Expired, Refunded }
enum ProcessingMode { ProtocolOnly, Permissionless, Paused }
```

### Market Identity

Market IDs include the market type and position-token type to prevent collisions. With collateral profiles, the ID also folds in the profile's `payoutUnit`:

```solidity
// Default-collateral path
marketId = computeMarketId(question, category, tradingStartTime, expiryTime,
                           collateralToken, marketType, positionTokenType);

// Collateral-profile path
marketId = computeProfileMarketId(question, category, tradingStartTime, expiryTime,
                                  collateralToken, profileId, payoutUnit,
                                  marketType, positionTokenType);
```

### Position Token Abstraction

Each market stores a `positionToken` address pointing to the ERC-1155 contract that holds its positions:

- **Binary CLOB markets:** `positionToken = config.defaultConditionalTokens` (Gnosis CTF)
- **Parimutuel markets:** `positionToken = config.parimutuelShareToken`
- **Multi-outcome & combinatorial markets:** `positionToken = config.evesPositionManager`

CLOB trade logic uses `IERC1155(market.positionToken)` for all position transfers, making it generic across position-token types.

### Creating Markets

```solidity
// Struct-based creation (preferred — carries display + external-reference metadata)
bytes32 marketId = marketFactory.createMarket(MarketCreationParams params);

// Convenience overload
bytes32 marketId = marketFactory.createMarket(
    question, category, resolutionSource,
    tradingStartTime, expiryTime, initialVolume, initialDirection
);

// Non-default collateral
bytes32 marketId = marketFactory.createMarketWithCollateralProfile(profileId, params);

// Batch + groups
bytes32[] memory ids = marketFactory.createMarkets(paramsArray);
(bytes32 groupId, bytes32[] memory ids) = marketFactory.createMarketGroup(groupParams);
(bytes32 groupId, bytes32[] memory ids) = marketFactory.createMarketGroup(title, paramsArray);
bytes32 groupId = marketFactory.createMarketGroupFromExisting(existingGroupParams);
marketFactory.addMarketsToGroup(groupId, marketRefs);
```

`MarketCreationParams` carries optional `MarketDisplayInput` (slug, title, subtitle, rules, image/icon URLs, metadata URI, tags) and `ExternalMarketRefInput` (source, external IDs, snapshot hash) used for indexing and UI display. Market groups bundle related markets (e.g., a sports event) under a `MarketGroupMetadata` record with per-market display lines.


---

## Collateral Profiles & Wrappers

### Overview

Collateral profiles let the protocol support multiple collateral tokens without changing market logic. Product creation entry points that support alternate collateral expose `…WithCollateralProfile(uint8 profileId, …)` variants. The launch/default profile uses Statics Dollar; USDG is the pegged entry asset used by the Statics mint-and-buy router rather than an Eve-issued wrapper.

### CollateralProfile

```solidity
struct CollateralProfile {
    address collateralToken;   // ERC-20 used as the unit of account for the product
    address wrapperToken;      // Optional paired external token/wrapper metadata for UI/router use
    uint128 payoutUnit;        // Per-share collateral unit for payouts/redemption
    uint128 marketCreationFee; // Creation fee in this collateral
    bool enabled;
}
```

Profiles are stored in `EveMarketStorage.collateralProfiles[uint8]`. Product-specific per-profile parameters are kept in side mappings to preserve storage layout:

- `parimutuelProfileCreationSeedAmount[profileId]`
- `parimutuelProfileMinEntry[profileId]`
- `parlayUnderwritingFeeByProfile[profileId]`

View accessors:

```solidity
function getCollateralProfile(uint8 profileId) external view returns (CollateralProfileView memory);
function getCollateralProfileParimutuelConfig(uint8 profileId)
    external view returns (uint128 creationSeedAmount, uint128 minEntry);
function getCollateralProfileParlayUnderwritingFee(uint8 profileId) external view returns (uint128);
```

### Statics Dollar Launch Rail

Eve does not deploy a protocol-specific stablecoin wrapper. The configured `staticsDollarCore` is authoritative for the `StaticsDollar` token and shared `StaticsDiamond` gateway. `StaticsDollarTradeRouterFacet` previews the configured pegged profile, pulls the exact USDG principal plus static mint fee, mints Statics Dollar, executes the purchase, and returns unfilled Statics Dollar to the buyer. The permit variant authorizes only the previewed input amount.

> The example entrypoints below keep the `USDC` identifier from the internal pegged-collateral profile. On the Robinhood testnet launch rail that profile is bound to USDG, not mainnet USDC; the `USDC` suffix is retained only as the historical internal name for the pegged token.

```solidity
FillBestResult memory result = tradeRouter.mintAndBuyWithUSDC(params);
FillBestResult memory result = tradeRouter.mintAndBuyWithUSDCPermit(params, permitSignature);
```

The pegged profile mints no Risk Shares. Statics retains authority over profile mode, debt ceilings, fees, solvency, and redemption policy; Eve stores only the Core/gateway/token bindings and profile ID needed to identify the rail.

---

## Curve CLOB Trading

### Inventory Management

Before posting curves, makers split collateral into YES/NO position tokens:

```solidity
uint128 sharesMinted  = curveInventory.splitInventory(marketId, collateralAmount);
uint128 collateralOut = curveInventory.mergeInventory(marketId, shareAmount);
```

`splitInventory` transfers collateral from the maker, splits it via the market's position system, and returns both sides. Binary markets use CTF YES/NO positions; multi-outcome complete sets use the NegRisk adapter; native combo operations use `EvesPositionManager`.

### Posting Curves

**Ask curves (maker sells base asset):**
```solidity
uint256 curveId = curveLifecycle.postCurve(
    marketId,
    isYesSide,              // true = selling YES shares
    volume,                 // shares offered
    startPrice,             // 9-decimal fixed point
    endPrice,
    durationMinutes,
    profileId,              // 0=linear, 1=step, 2=expDecay, or custom
    positionTokenType       // CTF, PARIMUTUEL, or EVES_POSITION
);
```

**Bid curves (maker buys base asset with escrowed quote):**
```solidity
uint256 curveId = curveLifecycle.postBidCurve(
    marketId, isYesSide, volume, startPrice, endPrice,
    durationMinutes, profileId, positionTokenType
);
```

The maker supplies the book's quote token directly; no Eve wrapper-specific bid-posting route exists.

Bid curves escrow quote tokens from the maker. When a seller fills a bid curve, the maker receives the base asset and the seller receives quote minus fees.

Requirements:
- Market must be in `Trading` state and not expired (`Scheduled` markets transition at `tradingStartTime`)
- Maker must hold sufficient position tokens (the quoted side is escrowed)
- Volume must be non-zero; prices must be ≤ `1_000_000_000`
- Profile ID must be built-in or a governance-approved custom profile

### Batch & Multi-Market Operations

```solidity
uint256[]   memory ids   = curveLifecycle.postCurvesBatch(marketId, positionTokenType, params);
uint256[]   memory ids   = curveLifecycle.postBidCurvesBatch(marketId, positionTokenType, params);
uint256[][] memory ids   = curveLifecycle.postCurvesMultiMarket(batches);
uint256[][] memory ids   = curveLifecycle.postBidCurvesMultiMarket(batches);
```

### Topping Up Curves

```solidity
curveLifecycle.topUpCurvesBatch(marketId, topUpParams);
curveLifecycle.topUpCurvesMultiMarket(batches);
uint128   sharesMinted = curveLifecycle.splitAndTopUpCurvesBatch(marketId, topUpParams);
uint128[] memory minted = curveLifecycle.splitAndTopUpCurvesMultiMarket(batches);
```

Top-up requirements: caller owns each curve, each curve is active and not expired, `addedVolume` is non-zero, and for `splitAndTopUp` variants total YES volume must equal total NO volume per market batch.

### Updating Curves

```solidity
curveLifecycle.updateCurve(curveId, newPacked, expectedGeneration);
curveLifecycle.updateCurvesBatch(params);
curveLifecycle.updateCurveFromNow(curveId, newPacked, expectedGeneration);   // resets createdAt to now
curveLifecycle.updateCurvesFromNowBatch(params);
```

Each update increments the curve `generation` counter, invalidating in-flight fills bound to the old generation. The `…FromNow` variants additionally reset the curve's `createdAt`, restarting the time-decay schedule.

### Filling Curves

**Single curve fill:**
```solidity
uint128 sharesOut = curveTrade.fillCurve(curveId, collateralIn, minSharesOut, expectedGeneration, expectedCommitment);
```

**Multi-curve aggregated fill:**
```solidity
FillBestResult memory result = curveTrade.fillBest(FillBestParams({
    marketId: marketId,
    isYesSide: true,
    maxCollateralIn: collateralIn,
    minSharesOut: minShares,
    maxAveragePrice: maxPrice,
    curveIds: curveIds,
    expectedGenerations: generations,
    expectedCommitments: commitments,
    payer: msg.sender,
    receiver: msg.sender
}));

```

`fillBest` iterates the provided curves, filling each until collateral is exhausted or curves are consumed, enforcing both minimum shares and maximum average price.

### Curve Pricing Math

Pricing is centralized in `LibCurveMath`. Books expose two pricing modes:

**Prediction books (`PREDICTION_PAYOUT`):** `tickSize = 1`, `priceDenominator = PRICE_SCALE (1e9)`, ticks in `[1, PRICE_SCALE]` so `price = tick`.

**Generic / spot books (`GENERIC`):** `price = tick × tickSize`, with `tickSize`/`priceDenominator`/`minTick`/`maxTick` from the book's tick preset.

```
grossCost = baseAmount × price / priceDenominator
fee       = grossCost × entryFeeBps / 10,000
totalCost = grossCost + fee
```

**Pricing profiles** (applied to ticks):
- Profile 0 (Linear): interpolates linearly from `startTick` to `endTick` over duration
- Profile 1 (Step): jumps at the midpoint
- Profile 2 (Exponential Decay): decays quadratically toward `endTick`
- Custom profiles: registered via governance, called through `ICurveProfile.computePrice(...)`

### Cancelling Curves

```solidity
curveLifecycle.cancelCurve(curveId);
curveLifecycle.cancelCurvesBatch(curveIds);
```

Returns remaining escrowed inventory (or quote escrow for bid curves) to the maker and marks the curve inactive. Only the curve owner can cancel.


---

## Books & Spot Trading

### Book Abstraction

Every CLOB-style market automatically creates **books** — per-side order books with their own fee config, accounting (volume, fees, maker tracking), and curve ownership. Binary markets create a YES book and a NO book; multi-outcome markets create one book per outcome. Books can also be created standalone (not linked to a market) for trading arbitrary ERC-20 or ERC-1155 base assets against a quote token.

**Market-linked books:**
- Created automatically with the market
- Inherit the market's fee config, expiry, and creator
- Base asset is the market's position token (ERC-1155)

**Standalone (spot) books:**
- Created via `BookFacet.createBook(...)`
- Support ERC-20 base assets (including fee-on-transfer via `BALANCE_DELTA` mode) and ERC-1155 base assets
- No expiry (perpetual); snapshot the protocol default fee config at creation
- Require the configured `spotBookCreationFee` in the default collateral token, paid to treasury (waived for the Diamond owner)
- Use `GENERIC` pricing with a tick preset (`tickPresetId`)
- Support a decommission lifecycle (`requestBookDecommission` → cooldown → `finalizeBookDecommission`)

### Book Admin & Creation

```solidity
bytes32 bookId = bookAdmin.createBook(assetType, baseTransferMode, baseToken, baseTokenId, quoteToken, tickPresetId, salt);
bytes32 bookId = bookAdmin.computeBookId(creator, assetType, baseTransferMode, baseToken, baseTokenId, quoteToken, tickPresetId, salt);
bytes32 bookId = bookAdmin.getMarketSideBook(marketId, isYesSide);
BookInfo memory info = bookAdmin.getBookInfo(bookId);
bool materialized   = bookAdmin.isBookMaterialized(bookId);
bookAdmin.requestBookDecommission(bookId);
bookAdmin.finalizeBookDecommission(bookId);
```

### Book Curve Posting & Trading

```solidity
// Posting (start/end expressed as ticks for spot books)
uint256 curveId = bookOrder.postBookCurve(bookId, curveSide, volume, startPrice, endPrice, durationMinutes, profileId, tickPresetId);
uint256[] memory ids = bookOrder.postBookCurvesBatch(bookId, curveSide, params);
bookOrder.topUpBookCurvesBatch(bookId, topUpParams);
bookOrder.reactivateBookCurve(bookId, curveId, newVolume, newPacked, expectedGeneration);

// Buying (fill ask/bid curves)
FillBestResult memory result = bookTrade.fillBookBest(FillBookParams{...});
FillBestResult memory result = bookTrade.fillBookBestFor(params);     // delegated

// Selling base into bid curves
SellBookResult memory result = bookTrade.sellBookBest(SellBookParams{...});
```

### Tick-Based Pricing

Standalone books use tick-based pricing where `price = tick × tickSize`. Tick presets (IDs 0–29) use a 1-2-5 series across decades: `tickSize = mantissa × 10^(presetId/3)` with `mantissa ∈ {1,2,5}`. Each book stores `tickSize`, `priceDenominator`, and a valid `[minTick, maxTick]` range. Prediction books use `PREDICTION_PAYOUT` mode with `tickSize = 1` and `priceDenominator = 1e9`.

**Curve sides within a book:**
- **ASK:** maker escrows base asset, taker pays quote (sell-side liquidity)
- **BID:** maker escrows quote, taker delivers base asset (buy-side liquidity without holding base)


---

## Parimutuel Markets

### Overview

Parimutuel markets let users pick YES or NO, deposit collateral, and receive single-side ERC-1155 shares. On resolution, the winning side splits the payout pool pro rata. There is no order book and no position splitting.

### ParimutuelShareToken

A dedicated ERC-1155 where the Diamond is the sole minter/burner. Position IDs derive from the market ID:

```solidity
yesPositionId = uint256(keccak256(abi.encode(marketId, "YES")));
noPositionId  = uint256(keccak256(abi.encode(marketId, "NO")));
```

The token delegates `uri()` back to the Diamond's `positionTokenURI()` for on-chain metadata.

### Creating Parimutuel Markets

```solidity
// Struct form (carries display + external-ref metadata and an explicit epochWindow)
bytes32 marketId = parimutuel.createParimutuelMarket(CreateParimutuelMarketParams params);

// Convenience form
bytes32 marketId = parimutuel.createParimutuelMarket(
    question, category, resolutionSource, tradingStartTime, expiryTime, epochWindow
);

// Non-default collateral
bytes32 marketId = parimutuel.createParimutuelMarketWithCollateralProfile(profileId, params);
```

`epochWindow` sets the duration used for the share-multiplier schedule (see below). The protocol may seed initial pool liquidity at creation (`parimutuelCreationSeedAmount` / per-profile override), emitting `ParimutuelCreationSeeded`.

### Buying Shares

```solidity
uint128 sharesMinted = parimutuel.buyShares(marketId, isYes, amount, receiver, minSharesOut);

uint128[] memory minted = parimutuel.buySharesBatch(marketIds, isYes, amounts, minSharesOut, receiver);
```

The entry fee is deducted from the deposit; net collateral enters the payout pool. Shares are minted with an epoch-based multiplier applied to the net amount.

### Epoch-Based Share Multiplier

Parimutuel markets divide their effective window into 8 stages with a configurable multiplier schedule (`config.parimutuelEpochMultipliersBps`). Default V1 schedule:

| Stage | Window | Multiplier |
|-------|--------|------------|
| 0 | First eighth | 2.00x (20,000 bps) |
| 1 | Second eighth | 1.50x (15,000 bps) |
| 2 | Third eighth | 1.15x (11,500 bps) |
| 3 | Fourth eighth | 1.00x (10,000 bps) |
| 4 | Fifth eighth | 0.85x (8,500 bps) |
| 5 | Sixth eighth | 0.70x (7,000 bps) |
| 6 | Seventh eighth | 0.55x (5,500 bps) |
| 7 | Final eighth | 0.40x (4,000 bps) |

```
netCollateral = amount - totalFee
sharesMinted  = netCollateral × multiplierBps / 10,000
payoutPool   += netCollateral   // pool receives net collateral, not shares
```

The payout pool receives only net collateral; the multiplier changes how many shares are minted against it, rewarding early entries. The effective window is bounded by the market's `parimutuelEpochWindow` (derived from `epochWindow` and capped by `config.parimutuelEpochWindowCap`), so long-duration markets can compress the multiplier window.

```solidity
(uint256 multiplierBps, uint256 epoch) = parimutuel.getEpochMultiplier(marketId);
uint16[8] memory schedule = parimutuel.getParimutuelEpochMultipliers();
uint64 window = parimutuel.getParimutuelEpochWindow(marketId);
```

### Entry Preview

```solidity
EntryPreview memory p = parimutuel.previewParimutuelEntry(marketId, isYes, amount);
// p: amountIn, totalFee, creatorFee, protocolFee, seniorPoolFee, resolverFee,
//    netCollateral, sharesMinted, multiplierBps, epoch, effectiveBasisWad,
//    totalYesSharesAfter, totalNoSharesAfter, payoutPoolAfter

(uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 seniorPoolFee, uint128 resolverFee, uint128 netShares) =
    parimutuel.previewEntryFee(marketId, amount);
```

```
totalFee    = amount × parimutuelEntryFeeBps / 10,000
creatorFee  = totalFee × creatorFeeBps / 10,000
protocolFee = totalFee × protocolFeeBps / 10,000
seniorPoolFee = route(totalFee × seniorPoolFeeBps / 10,000)
resolverFee = totalFee × resolverFeeBps / 10,000
rawSeniorPoolFee = totalFee - creatorFee - protocolFee - resolverFee
seniorPoolFee = route(rawSeniorPoolFee)   // treasury fallback is added to protocolFee
netShares   = amount - totalFee
```

### Claiming Payouts

```solidity
uint128 payout = parimutuel.claimPayout(marketId);
```

| Outcome | Payout Formula |
|---------|---------------|
| YES wins | `userYesShares × payoutPool / totalYesShares` |
| NO wins | `userNoShares × payoutPool / totalNoShares` |
| INVALID | `(userYesShares + userNoShares) × payoutPool / totalClaimableShares` (pro-rata refund) |

**Zero-winning-side rule:** if the resolved outcome is YES but `totalYesShares == 0` (or NO with `totalNoShares == 0`), the effective payout outcome becomes INVALID.

### Dust Sweeping & Pool View

```solidity
uint128 swept = parimutuel.sweepParimutuelDust(marketId);   // reverts if claimable shares remain
PoolView memory pool = parimutuel.getParimutuelPool(marketId);
```

`PoolView` returns `totalYesShares`, `totalNoShares`, `payoutPool`, `claimedPayout`, `claimedClaimableShares`, `rawResolvedOutcome`, `effectivePayoutOutcome`, `payoutPoolAtResolution`, `totalClaimableSharesAtResolution`, `dustSwept`, `finalized`, `impliedYesProbability`, `impliedNoProbability`.

### Pool Finalization

On OBR resolution the pool is finalized: `rawResolvedOutcome`/`effectivePayoutOutcome` recorded, `payoutPoolAtResolution`/`totalClaimableSharesAtResolution` snapshotted, and `finalized` set — enabling claims (`ParimutuelFinalized`).


---

## Multi-Outcome Orderbook Markets

### Overview

Multi-outcome markets (`MarketType.MULTI_OUTCOME_ORDERBOOK`) support N mutually-exclusive outcomes as canonical NegRisk CTF positions. `EvesNegRiskAdapter` prepares one binary condition per outcome, wraps the event collateral, and exposes the mutually exclusive YES set. Users split collateral into one tradable ERC-1155 YES token per outcome, trade each outcome on its own book, and redeem after adapter-backed resolution.

### Creation

```solidity
bytes32 marketId = multiOutcome.createMultiOutcomeMarket(CreateMultiOutcomeMarketParams params);
bytes32 marketId = multiOutcome.createMultiOutcomeMarketWithCollateralProfile(profileId, params);
```

`CreateMultiOutcomeMarketParams` includes `question`, `category`, `resolutionSource`, `tradingStartTime`, `expiryTime`, `string[] outcomes`, `MarketDisplayInput display`, `ExternalMarketRefInput externalRef`, and per-outcome `OutcomeDisplayInput[]` (slug, label, abbreviation, icon, external outcome id).

### Position Operations

```solidity
uint256[] memory positionIds = multiOutcome.splitOutcomeSet(marketId, amount, receiver);
uint128 collateralOut        = multiOutcome.mergeOutcomeSet(marketId, amount, receiver);
uint128 collateralOut        = multiOutcome.redeemOutcome(marketId, outcome, amount, receiver);
```

### Views

```solidity
MultiOutcomeMarketView memory m = multiOutcome.getMultiOutcomeMarket(marketId);
string[] memory outcomes        = multiOutcome.getMultiOutcomeOutcomes(marketId);
OutcomeDisplayView memory d     = multiOutcome.getMultiOutcomeDisplay(marketId, outcome);
uint256 positionId              = multiOutcome.getOutcomePositionId(marketId, outcome);
bytes32[] memory bookIds        = multiOutcome.getMultiOutcomeBooks(marketId);
OutcomeCTFPositionView memory p = multiOutcome.getOutcomeCTFPositions(marketId, outcome);
```

`MultiOutcomeMarketView` exposes `outcomeCount`, `resolvedOutcome`, `payoutDenominator`, `invalid`, `resolved`, `collateralProfileId`, and `payoutUnit`. Resolution sets `resolved`, `invalid`, `resolvedOutcome`, and `payoutDenominator` (`= outcomeCount` for INVALID, otherwise `1`), and reports the payout vector.


---

## Native Positions & Combinatorial Markets

### EvesPositionManager

`EvesPositionManager` is an in-Diamond ERC-1155 (minted/burned only by the Diamond) that holds native and combinatorial positions. Multi-outcome markets instead use canonical CTF positions produced by `EvesNegRiskAdapter`. The position manager delegates token metadata to the Diamond via `IPositionMetadataProvider.positionTokenURI`.

### Combinatorial (Combo) Positions

Combo positions represent an AND over multiple binary legs (a parlay expressed as a position). `ComboCoreFacet` prepares a combo condition from canonical legs and provides split/merge/wrap:

```solidity
(bytes32 conditionId, uint256 yesId, uint256 noId) = comboCore.prepareComboCondition(canonicalLegs);
(uint256 yesId, uint256 noId) = comboCore.splitCombo(conditionId, amount, yesReceiver, noReceiver);
uint128 collateralOut         = comboCore.mergeCombo(conditionId, amount, receiver);
uint256 comboPositionId       = comboCore.wrapCombo(underlyingPositionId, amount, receiver);
uint256 underlyingPositionId  = comboCore.unwrapCombo(comboPositionId, amount, receiver);
ComboConditionView memory c   = comboCore.getComboCondition(conditionId);
uint256[] memory legs         = comboCore.getComboLegs(conditionId);
```


`ComboMarketFacet` turns a set of binary markets/legs into a tradable combo market with its own YES/NO books:

```solidity
ComboMarketPreparation memory prep = comboMarket.createComboMarket(marketIds, yesLegs);
bytes32 bookId = comboMarket.computeComboBookId(comboMarketId, isYesSide);
ComboMarketView memory m = comboMarket.getComboMarket(comboMarketId);
bytes32 bookId = comboMarket.getComboBook(positionToken, positionId);
```

`ComboSettlementFacet` handles redemption and payout previews:

```solidity
uint128 collateralOut = comboSettlement.redeemCombo(positionId, amount, receiver);
(bool redeemable, uint128 collateralOut) = comboSettlement.getComboPayout(positionId, amount);
```

`ComboViewFacet` exposes `getComboPositionMetadata`, `getComboPositionPayout`, and `getComboCollateralStatus`.

Combo market creation charges `comboMarketCreationFee` (to treasury) and books use `config.comboFeeConfig`.


---

## Parlays

### Overview

Parlays are peer-to-peer underwritten multi-leg bets with tiered payouts. A parlay **template** binds an ordered set of legs (each a market + required outcome) to a payout-tier schedule and an invalid policy. Underwriters post **offers** (escrowing the maximum payout) and takers post **requests** (escrowing premium + fee); filling either side mints ERC-1155 ticket buckets (`ParlayTicketToken`). Shared **budgets** let an underwriter back many offers/requests from one pool.

Parlay state lives in its own storage slot (`LibParlay.Storage`).

### Configuration

```solidity
parlay.setParlayConfig(ticketToken, feeRecipient, underwritingFee, seniorPoolFeeBps, feeRecipientBps);
ParlayConfigView memory cfg = parlay.getParlayConfig();
```

### Offers & Requests

```solidity
uint256 offerId = parlay.postParlayOffer(legs, payoutTiers, invalidPolicy, metadataHint, premiumPerUnit, maxPayoutPerUnit, units, fillDeadline);
uint256 ticketId = parlay.fillParlayOffer(offerId, units, receiver);
uint256 escrowReturned = parlay.cancelParlayOffer(offerId);

uint256 requestId = parlay.postParlayRequest(legs, payoutTiers, invalidPolicy, metadataHint, premiumPerUnit, desiredMaxPayoutPerUnit, units, fillDeadline);
uint256 ticketId = parlay.fillParlayRequest(requestId, units, ticketReceiver);
(uint256 premiumReturned, uint256 feeReturned) = parlay.cancelParlayRequest(requestId);
```

Each of `postParlayOffer` / `postParlayRequest` has `…WithCollateralProfile`, `…FromBudget`, `…FromBudgetWithCollateralProfile`, and batch-from-budget variants.

### Shared Budgets

```solidity
uint256 budgetId = parlay.createParlayBudget(BudgetMode mode, uint256 amount);   // MakerPayout or TakerSpend
uint256 budgetId = parlay.createParlayBudgetWithCollateralProfile(profileId, mode, amount);
parlay.fundParlayBudget(budgetId, amount);
uint256 refunded = parlay.cancelParlayBudget(budgetId);
SharedBudgetView memory b = parlay.getParlayBudget(budgetId);
```

### Settlement

```solidity
uint128 payoutPerUnit = parlay.finalizeParlayTicketBucket(ticketId);
uint256 payout        = parlay.claimParlayTicket(ticketId, units, receiver);
```

Finalization counts leg hits/misses/invalids and resolves the payout per unit using the tier schedule and the template's `InvalidPolicy` (`VoidInvalidLegs` or `InvalidCountsAsMiss`). The flat underwriting fee is split between the senior pool and `feeRecipient`.

### Helpers & Views

```solidity
uint256 templateId = parlay.computeParlayTemplateId(legs, payoutTiers, invalidPolicy);
uint256 ticketId   = parlay.computeParlayTicketId(templateId, sourceType, sourceId, underwriter, maxPayoutPerUnit);
bytes32 bookId     = parlay.createParlayTicketBook(ticketId, tickPresetId, salt);   // tradable ticket book
parlay.emitStrategyCreated(strategyId, directMarketIds, directOutcomes, parlayTemplateIds, metadataHint);
ParlayTemplateView    memory t = parlay.getParlayTemplate(templateId);
ParlayOfferView       memory o = parlay.getParlayOffer(offerId);
ParlayRequestView     memory r = parlay.getParlayRequest(requestId);
ParlayTicketBucketView memory k = parlay.getParlayTicketBucket(ticketId);
bytes[] memory results = parlay.multicall(calls);
```

### Key Types

```solidity
enum InvalidPolicy { VoidInvalidLegs, InvalidCountsAsMiss }
enum SourceType    { Offer, Request }
enum BudgetMode    { MakerPayout, TakerSpend }

struct ParlayLeg  { bytes32 marketId; uint8 requiredOutcome; }
struct PayoutTier { uint8 minHits; uint128 payout; }
```


---

## Delayed Orders

### Overview

Delayed orders provide MEV-resistant taker execution: an order is submitted with escrow and a committed route, becomes executable only after a block-delay, and is then executed (or expired) by a processor. Limit remainders can rest as flat curves. Per-book/market gating is controlled by `Book.delayedExecutionEnabled` / `Market.delayedExecutionEnabled`. Only `PREDICTION_PAYOUT` / ERC-1155 books are supported.

### Entry Points

```solidity
uint256 orderId = delayedOrder.submitDelayedOrder(SubmitDelayedOrderParams params);

ProcessDelayedOrderResult memory result =
    delayedOrder.processDelayedOrders(bookId, maxOrders, routes);

delayedOrder.withdrawQuoteCredit(token, amount);
delayedOrder.withdrawBaseCredit(assetType, token, tokenId, amount);
```

- `submitDelayedOrder` escrows quote (buys) or base (sells), validates kind and limit price (`≤ type(uint72).max`), and records the order's committed `routeHash`. Reverts if processing mode is `Paused`.
- `processDelayedOrders` walks the book's FIFO queue: orders before their `executableBlock` stop processing; expired orders are refunded; otherwise the order is filled along the supplied route (whose hash must match the committed `routeHash`). In `ProtocolOnly` mode only registered protocol processors may process.
- Leftover escrow is returned as withdrawable credit balances.

### Configuration (in `MarketConfig`)

```
delayedOrderProtectionDelayBlocks   // blocks before an order becomes executable
delayedOrderExecutionGraceBlocks    // blocks before an unexecuted order expires
delayedOrderRestingDurationMinutes  // resting curve lifetime for limit remainders
delayedOrderProcessorFeeShareBps    // processor reward share
delayedOrderProcessingMode          // ProtocolOnly | Permissionless | Paused
```

### Key Types

```solidity
struct SubmitDelayedOrderParams {
    bytes32 bookId;
    DelayedOrderKind kind;
    uint128 amountIn;
    uint128 limitPrice;
    uint128 minOut;
    uint128 maxAveragePrice;
    uint256[] curveIds;
    uint32[] expectedGenerations;
    bytes32[] expectedCommitments;
}

struct DelayedOrderRoute {
    uint256[] curveIds;
    uint32[] expectedGenerations;
    bytes32[] expectedCommitments;
}

struct ProcessDelayedOrderResult { uint256 processedCount; uint256 stoppedOrderId; }
```

Order state (`DelayedOrder`) tracks owner, book/market, kind, status, amounts, limit/avg-price guards, submit/executable/expiry blocks, sequence, route hash, and any resting curve. Storage lives in `EveMarketStorage.delayedOrders` (`DelayedOrderStorage`).

---

## Resolution & Disputes

### Overview

Eves Market uses an Optimistic Bond-based Resolution (OBR) system shared by all market types. The creator gets first right to settle. If they don't, the community can propose outcomes backed by escalating **bond-token** deposits. When escalation reaches the configured maximum, the dispute is handed to the **Resolver Jury** (see next section) for a commit-reveal verdict.

Resolution bonds are denominated in `config.bondToken` (a generic ERC-20), not in a governance token. There is no longer an ETH bond, no ETH-bond-credit accounting, and no EVE token-weighted voting.

### Resolution Flow

```
Market Expires (Trading → Pending)
    │
    ▼
Creator Grace Period (creatorSettleGrace)
    │
    ├─ Creator settles (settleMarket) → Dispute window opens (Disputed)
    │                                        │
    │                                        ├─ No dispute → finalizeResolution
    │                                        └─ Disputed → escalate
    │
    └─ Grace expires → Open Resolution Period (openResolutionTimeout)
                           │
                           ├─ Community proposes (openResolution, bond L1) → Dispute window
                           │        │
                           │        ├─ disputeResolution (bond L2 ...) → escalate
                           │        └─ at maxEscalation → Resolver Jury dispute
                           │
                           └─ Timeout with no proposal → finalizeResolution = Invalid
```

### Creator Settlement

```solidity
obr.settleMarket(marketId, outcome);        // creator only, during grace; opens dispute window
obr.settleMarketEarly(marketId, outcome);   // creator only, while still Trading (early settle)
```

No bond required (the creator already has a creation bond at stake). `settleMarketEarly` lets the creator settle a still-trading market and emits `EarlyCreatorSettled`.

### Open Resolution

```solidity
obr.openResolution(marketId, outcome);
```

Available after the creator grace period and before `openResolutionTimeout`. Locks an L1 resolution bond (`config.resolutionBondL1`) via `BondTokenGateFacet` and opens a dispute window.

### Disputing

```solidity
obr.disputeResolution(marketId, counterOutcome);
```

Must propose a different outcome than the current proposal, before the dispute deadline. Locks the next escalation level's bond (`resolutionBondL1` at L1, `resolutionBondL2` at L2+). When the previous level already equals `config.maxEscalation`, disputing triggers `initiateDispute` on the Resolver Jury and further OBR disputes/finalization are blocked until the jury returns a verdict.

### Resolution Modes

```solidity
enum ResolutionMode {
    CreatorAdminBootstrap,
    ObrJury
}
```

The market config carries a global `resolutionMode`.

- `CreatorAdminBootstrap` — bootstrapping mode for genesis or low-participation periods. Standard OBR escalation paths are disabled, and the owner can finalize expired pending markets directly through `adminFinalizeResolution(marketId, outcome)`.
- `ObrJury` — full production mode. OBR open-resolution, disputes, and Resolver Jury escalation are enabled.

`OwnershipFacet.setResolutionMode(uint8)` switches modes. Entering `ObrJury` requires an already-active resolver epoch, which prevents turning on jury resolution before the active set is actually populated.

### Finalization

```solidity
obr.finalizeResolution(marketId);                  // public, after dispute window
obr.finalizeFromJury(marketId, finalResult);       // internal self-call from the jury
obr.adminFinalizeResolution(marketId, outcome);    // owner-only bootstrap mode
```

Finalization:
1. Sets the market outcome and transitions to `Resolved`.
2. Settles all recorded bonds (return to winning-outcome proposers, slash losers to treasury).
3. Settles the creation bond (return if creator settled honestly, otherwise slash — 10% to the winning resolver, remainder to treasury).
4. Evaluates creator settlement honesty (`CreatorSettlementEvaluated`) and sets `creatorFeeEligible` / `creationBondReturnable`.
5. Routes creator fees: forfeited to treasury (10% to the winning challenger) when the creator was dishonest and a different winning claimant exists; otherwise fully to treasury.
6. Reports payouts per market type — CTF binary markets report `[YES,NO]` payout vectors, multi-outcome markets set the winning index, parimutuel markets finalize the pool.

If a market reaches the open-resolution timeout with no proposal, `finalizeResolution` resolves it as **Invalid**.

In `CreatorAdminBootstrap` mode, `adminFinalizeResolution` bypasses OBR escalation entirely and exists specifically so markets can run before the first resolver epoch is live.

### Bond Amounts

| Level | Bond (in `config.bondToken`) |
|-------|------------------------------|
| Creator Settlement | 0 (creation bond at risk) |
| Level 1 (Open Resolution) | `resolutionBondL1` |
| Level 2+ (Escalation) | `resolutionBondL2` |

### Resolution View

```solidity
(ResolutionInfo[] memory history, uint8 currentEscalationLevel, uint64 disputeDeadline, bool isActive) =
    obr.getResolutionHistory(marketId);

(uint8 state, uint8 outcome, uint64 disputeDeadline, uint128 creatorFeesEscrowed) =
    obr.getMarketStatus(marketId);
```

`ResolutionInfo` carries `proposer`, `proposedOutcome`, `escalationLevel`, `disputed`, `bondAmount`, `proposedAt`, `disputeDeadline`, `snapshotBlock`.


---

## Resolver Jury, Registry & Identity

### Overview

Fully escalated disputes are decided by the **Resolver Jury**, replacing token-weighted EVE governance voting. Jurors are addresses holding a soulbound **resolver identity** who hold the fixed seat stake and are selected into the active resolver epoch. Committee selection uses commit-reveal randomness; the verdict uses commit-reveal voting. Verdicts carry equal weight per juror (not token-weighted).

Until the protocol switches from `CreatorAdminBootstrap` into `ObrJury`, identities can register and prepare for epoch candidacy, but jury resolution is not used.

The system spans three pieces:

- **EveIdentity** (`tokens/EveIdentity.sol`) — a non-transferable (soulbound) identity token. `mint`/`setRoles` are Diamond-only; approvals and transfers revert; `votingWeightOf` returns 0 (equal-weight design). One identity per address.
- **ResolverRegistryFacet** — identity lifecycle, role flags, staking, and reputation.
- **ResolverJuryFacet** — the per-dispute commit-reveal state machine.

Jury state lives in its own storage slot (`LibResolverJury.Storage`), initialized via `init/ResolverJuryInit.sol::initResolverJury(eveIdentity)`.

### Resolver Registry

```solidity
uint256 identityId = registry.mintIdentity();
registry.setCreatorRole(enabled);
registry.setResolverRole(enabled);
registry.depositResolverStake(amount);                       // tops up to fixed resolverSeatStake
uint64 epochId = registry.openResolverEpochRotation();      // opens the next epoch during the rotation window
registry.optIntoResolverEpoch(randomnessCommitment);        // pays candidate fee when configured
registry.commitResolverEpochRandomness(epochId, commitment);
registry.revealResolverEpochRandomness(epochId, value, salt);
registry.finalizeResolverEpochSeed(epochId);                 // schedules a future reference block
registry.finalizeResolverEpochSeed(epochId);                 // later call consumes its block hash
registry.submitResolverEpochCandidateScore(epochId, identityId);
registry.finalizeResolverEpochSelection(epochId);
registry.activateFinalizedResolverEpoch(epochId);
registry.requestResolverExit();
registry.withdrawResolverStake();                           // after exitCooldown or finalized-unselected candidate path
```

Views include `resolverDashboard`, `resolverIdentity(ByOwner)`, `resolverJuryConfig`, `resolverEpoch`, `resolverEpochCandidate`, `isEligibleResolver`, `hasConflict`, `creatorReputation`, `resolverReputation`, `eligibleResolverCount`, `activeResolverCount`, `activeResolverEpochSize`, `activeResolverAt`, and `previewResolverRewards`. `claimResolverRewards(token)` withdraws accrued resolver rewards, and `finalizeResolverTradingRewards(epochId, token)` crystallizes an epoch's resolver trading-fee share after epoch end. `applyFinalityReputation(disputeId, finalResult)` updates reputation after finality.

Key current lifecycle rules:

- The active set cap means **active seats per epoch**, not lifetime membership.
- Epoch activation is strict: `activateFinalizedResolverEpoch(epochId)` reverts if the selection is underfilled. An epoch only becomes active once `selected.length == activeEpochSize`.
- Candidate count is not the same as active count. More identities can register and opt in than there are active seats.
- Epoch `1` waives the configured candidate fee, so genesis candidates can queue for the first selection without paying the recurring candidacy fee.
- For later epochs, `optIntoResolverEpoch` collects `epochCandidateFeeAmount` in `epochCandidateFeeToken` and sends it directly to treasury.
- Slashing for missed epoch-randomness duties immediately redistributes the slashed stake through resolver rewards and slash-locks the offender until the cooldown expires.
- Epoch seed finalization cannot be permanently missed. An absent, expired, or unavailable reference hash causes `finalizeResolverEpochSeed` to emit `ResolverEpochSeedReferenceBlockSet` with a fresh future block. The candidate score-submission deadline begins only after a seed is successfully finalized.

### Resolver Jury State Machine

```solidity
jury.initiateDispute(marketId);            // called from OBR at maxEscalation
jury.openRandomnessCommit(disputeId);
jury.commitRandomness(disputeId, commitment);
jury.closeRandomnessCommit(disputeId);
jury.revealRandomness(disputeId, value, salt);
jury.closeRandomnessReveal(disputeId);       // schedules a future reference block
jury.closeRandomnessReveal(disputeId);       // later call consumes its block hash
jury.selectCommittee(disputeId);
jury.commitVote(disputeId, commitment);
jury.revealVote(disputeId, outcome, salt);
jury.closeCommit(disputeId);
jury.closeRevealAndTally(disputeId);
jury.openAppeal(disputeId);
jury.applyRandomnessFallback(disputeId);   // used on randomness failure
jury.finalizeDispute(disputeId);           // routes verdict back via OBR.finalizeFromJury
```

Views: `disputeView`, `committeeMembers`, `outcomeTally`, `revealedVote`, `provisionalResult`.

With enough valid reveals, closing dispute randomness is deliberately two-stage.
The first post-deadline call emits `RandomnessSeedReferenceBlockSet`; a later call
derives the seed from that block hash. If the reference hash expires from the EVM's
256-block lookup window or is otherwise unavailable, closing again schedules a fresh
reference instead of weakening the entropy or bricking the dispute. Low-reveal
rounds still follow the configured retry or all-eligible fallback immediately.

### Configuration (`ResolverJuryConfig`)

The jury config (embedded in `MarketConfig.resolverJuryConfig`) covers identity mint fee/token, fixed `resolverSeatStake`, `epochCandidateFeeToken` / `epochCandidateFeeAmount`, `activeEpochSize`, epoch duration and rotation timing, epoch-randomness commit/reveal/selection windows, activation delay, exit cooldown, participation threshold/grace, concurrency limit, conflict threshold, `committeeSizesByRound[]`, max appeal rounds, appeal bond multiplier, dispute randomness/commit/reveal durations and timeouts, quorum, redraw limit, slash bps (missed commit / missed reveal / invalid reveal) and slash cooldown, protocol fee allocation, appeal success/failure routing (`appealSuccessRoutingBps[4]`, `appealFailureRoutingBps[3]`), and per-action incentive amounts (select committee, close commit, close reveal, open appeal, finalize, randomness). Behavior enums:

```solidity
enum LowQuorumMode        { Redraw, Escalate, FinalizeInvalid }
enum TieBreakMode         { Escalate, ResolveInvalid }
enum RandomnessFailureMode{ Retry, AllEligible }
```


---

## Fee System

### Fee Configuration

Fees are configured per product family through `FeeConfigFacet`. Each market and each book snapshots its fee config at creation, so protocol-wide changes don't affect existing markets/books. Non-fee protocol configuration remains on `OwnershipFacet`.

```solidity
struct BookFeeConfig {       // orderbook (CLOB) and market-linked books
    uint16 entryFeeBps;
    uint16 makerFeeBps;
    uint16 creatorFeeBps;
    uint16 protocolFeeBps;
    uint16 seniorPoolFeeBps;
    uint16 resolverFeeBps;
}

struct SpotFeeConfig {       // standalone spot books
    uint16 tradeFeeBps;
    uint16 makerFeeBps;
    uint16 protocolFeeBps;
    uint16 seniorPoolFeeBps;
    uint16 resolverFeeBps;
}

struct ComboFeeConfig {      // combinatorial markets
    uint16 tradeFeeBps;
    uint16 makerFeeBps;
    uint16 creatorFeeBps;
    uint16 protocolFeeBps;
    uint16 seniorPoolFeeBps;
    uint16 resolverFeeBps;
}

struct ParimutuelFeeConfig {
    uint16 entryFeeBps;
    uint16 creatorFeeBps;
    uint16 protocolFeeBps;
    uint16 seniorPoolFeeBps;
    uint16 resolverFeeBps;
}
```

### CLOB Trading Fee Split

```
grossCost = baseAmount × price / priceDenominator
fee       = grossCost × entryFeeBps / 10,000

makerFee    = fee × makerFeeBps / 10,000
creatorFee  = fee × creatorFeeBps / 10,000
resolverFee = fee × resolverFeeBps / 10,000
rawSeniorPoolFee = fee × seniorPoolFeeBps / 10,000
treasuryFee = fee - makerFee - creatorFee - resolverFee - rawSeniorPoolFee
  └─ seniorPoolFee = rawSeniorPoolFee accrued to the internal Senior fee index when eligible
  └─ seniorPool fallback = ineligible senior-pool share is added back to treasury
```

Fee distribution reads from the **book's** snapshotted fee config. When permissionless creation is disabled, the creator share is redirected to treasury accounting. The `seniorPoolFeeBps` share accrues through `LibSeniorCapital` when the quote token equals the configured margin asset and active Senior stored units exist; otherwise it falls back to treasury. The resolver share is retained in-protocol, accrued to the current resolver epoch, and later split evenly across compliant active jurors.

### Parimutuel Entry Fee Split

```
totalFee    = amount × parimutuelEntryFeeBps / 10,000
creatorFee  = totalFee × creatorFeeBps / 10,000
protocolFee = totalFee × protocolFeeBps / 10,000
resolverFee = totalFee × resolverFeeBps / 10,000
rawSeniorPoolFee = totalFee - creatorFee - protocolFee - resolverFee   // residual, exhaustive
netShares   = amount - totalFee
```

The same route rules apply as CLOB fees: the Senior slice accrues internally only for the margin asset while active Senior units exist; otherwise it is absorbed into treasury/protocol fee accounting.

### Creator Fee Escrow

Creator fees are escrowed during trading and only released if the creator settles honestly:
- **Honest settlement** (creator's level-0 proposal matches the final non-INVALID outcome) → fees claimable
- **Dishonest settlement** → fees forfeited to treasury (10% to the winning challenger when one exists)
- **No settlement** → fees forfeited

### Resolver Rewards

Resolver compensation has two current paths:

- **Slashed seat stake** — slashed EVE from active-juror epoch duties, missed dispute votes, or invalid reveals is split evenly across the compliant active jurors of the current epoch. The slashed juror is excluded from that epoch's reward distribution until they restore the fixed seat stake and later re-enter.
- **Trading-fee share** — each fee config includes `resolverFeeBps`. That fee share accrues to the current resolver epoch in the fee token and is split evenly across compliant active jurors after `finalizeResolverTradingRewards(epochId, token)`.

Rewards are not stake-weighted. Every active seat uses the same fixed `resolverSeatStake`, and every compliant active juror receives an equal share.

### Maker Rewards (incentive program)

Beyond fee sharing, markets can run a maker-rewards program funded in a reward token:

```solidity
feeRouter.configureMarketMakerRewards(marketId, rewardRateBps);
feeRouter.fundMarketMakerRewards(marketId, amount);
feeRouter.claimMarketMakerRewards(marketId);
(address rewardToken, uint16 rewardRateBps, uint128 rewardsRemaining, uint128 claimable) =
    feeRouter.previewMarketMakerRewards(marketId, maker);
```

Rewards accrue against a maker's quote volume at `rewardRateBps` while funded.

### Claiming Fees

```solidity
feeRouter.claimCreatorFees(marketId);    // creator, after honest resolution
feeRouter.claimMakerFees(marketId);      // maker, anytime
feeRouter.claimBookCreatorFees(bookId);  // standalone book creator
feeRouter.claimBookMakerFees(bookId);    // standalone book maker
```

### Creation Bond

The creation bond (in `config.bondToken`) incentivizes honest creation/resolution:
- Returned to the creator on honest settlement
- Slashed otherwise — 10% to the winning resolver, remainder to treasury


---

## Market Settlement

### Overview

After resolution, position holders redeem winning tokens. The path depends on market/position type.

### Binary CLOB Redemption (CTF)

```solidity
(address collateralToken, bytes32 conditionId, uint256[] memory indexSets) =
    settlement.getCTFRedemptionParams(marketId);
conditionalTokens.redeemPositions(IERC20(collateralToken), bytes32(0), conditionId, indexSets);
```

Users call the CTF directly from the wallet holding the YES/NO positions; the CTF burns balances and releases collateral.

### Multi-Outcome / Combo Redemption

```solidity
multiOutcome.redeemOutcome(marketId, outcome, amount, receiver);
comboSettlement.redeemCombo(positionId, amount, receiver);
```

### Parimutuel Claiming

```solidity
uint128 payout = parimutuel.claimPayout(marketId);
```

### Settlement Previews (Type-Aware)

```solidity
// Generic preview (routes to the correct type)
(uint256 claimable, uint256 yesBalance, uint256 noBalance, uint8 outcome) =
    settlement.previewRedemption(marketId, user);

settlement.previewCTFRedemption(marketId, user);
settlement.previewParimutuelPayout(marketId, user);
```

### Payout Rules

**Binary markets:**

| Outcome | YES Holders | NO Holders |
|---------|-------------|------------|
| Yes | `yesBalance × payoutUnit` | 0 |
| No | 0 | `noBalance × payoutUnit` |
| Invalid | `(yesBalance + noBalance) × payoutUnit / 2` | (same) |

**Parimutuel markets:**

| Outcome | Winners | Losers |
|---------|---------|--------|
| Yes | `userYesShares × payoutPool / totalYesShares` | 0 |
| No | `userNoShares × payoutPool / totalNoShares` | 0 |
| Invalid | `(userYesShares + userNoShares) × payoutPool / totalClaimableShares` | N/A |

**Multi-outcome markets:** the winning outcome redeems at `payoutUnit`; INVALID redeems the full set pro-rata (`payoutDenominator = outcomeCount`).

---

## Data Models

### Market

```solidity
struct Market {
    bytes32 marketId;
    MarketType marketType;
    PositionTokenType positionTokenType;
    address positionToken;
    address collateralToken;
    address creator;
    bytes32 questionId;
    bytes32 resolutionId;
    bytes32 conditionId;
    uint256 yesPositionId;
    uint256 noPositionId;
    bytes32 yesBookId;
    bytes32 noBookId;
    uint64 createdAt;
    uint64 tradingStartTime;
    uint64 expiryTime;
    uint64 parimutuelEpochWindow;
    uint64 resolutionTime;
    uint64 disputeDeadline;
    uint96 lastTradePrice;                  // 9-decimal fixed point
    BookFeeConfig orderbookFeeConfig;
    ParimutuelFeeConfig parimutuelFeeConfig;
    uint128 creationFeePaid;
    uint128 creationBond;                   // in config.bondToken
    uint128 totalFeePool;
    uint128 totalQuoteVolume;
    uint128 creatorFeesEscrowed;
    uint128 protocolFeesAccrued;
    bool creatorFeesClaimed;
    bool creatorSettledHonestly;
    bool creatorFeeEligible;
    bool creationBondReturnable;
    bool creationBondReleased;
    MarketOutcome outcome;
    MarketState state;
    uint256 curveCount;
    bool delayedExecutionEnabled;
    mapping(address => uint128) makerQuoteVolume;
    mapping(address => uint128) makerFeesAccrued;
    mapping(address => uint128) makerFeesClaimed;
    uint16 makerRewardRateBps;
    uint128 makerRewardsRemaining;
    mapping(address => uint128) makerRewardsClaimable;
    uint8 collateralProfileId;
    uint128 payoutUnit;
}
```

### Resolution

```solidity
struct Resolution {
    bytes32 marketId;
    address proposer;
    uint8 proposedOutcome;
    uint8 escalationLevel;
    bool disputed;
    uint128 bondAmount;          // in config.bondToken
    uint128 reservedBondAmount;
    uint64 proposedAt;
    uint64 disputeDeadline;
    uint64 snapshotBlock;
}
```

### Book

```solidity
struct Book {
    bytes32 bookId;
    bytes32 marketId;                       // bytes32(0) for standalone
    bool isYesSide;
    BookAssetType assetType;                // ERC1155 | ERC20
    BaseTransferMode baseTransferMode;      // EXACT | BALANCE_DELTA
    address baseToken;
    uint256 baseTokenId;
    address quoteToken;
    address creator;
    uint64 createdAt;
    uint64 expiryTime;
    bool active;
    BookFeeConfig feeConfig;
    uint96 lastTradePrice;
    uint256 curveCount;
    uint128 totalFeePool;
    uint128 totalQuoteVolume;
    uint128 creatorFeesEscrowed;
    uint128 protocolFeesAccrued;
    bool creatorFeesClaimed;
    BookPricingMode pricingMode;            // PREDICTION_PAYOUT | GENERIC
    BookLifecycle lifecycle;                // ACTIVE | DECOMMISSION_PENDING | DECOMMISSIONED
    uint8 tickPresetId;
    uint64 decommissionRequestedAt;
    uint64 decommissionAvailableAt;
    uint128 tickSize;
    uint128 priceDenominator;
    uint128 minTick;
    uint128 maxTick;
    bool delayedExecutionEnabled;
    mapping(address => uint128) makerQuoteVolume;
    mapping(address => uint128) makerFeesAccrued;
    mapping(address => uint128) makerFeesClaimed;
}
```

### StoredCurve

```solidity
struct StoredCurve {
    uint256 packed;             // startPrice | endPrice | durationMinutes | profileId
    uint128 remainingVolume;
    uint64 createdAt;
    uint32 generation;
    bool active;
    bool isYesSide;
    CurveSide curveSide;        // ASK | BID
    address maker;
    bytes32 bookId;
    uint128 quoteEscrowRemaining; // BID curves only
}
```

### MarketConfig

```solidity
struct MarketConfig {
    // Core addresses
    address defaultConditionalTokens;       // Gnosis CTF (binary CLOB)
    address evesPositionManager;            // native/combinatorial ERC-1155
    address parimutuelShareToken;
    address collateralToken;                // launch default = Statics Dollar
    address eveToken;
    address eveTreasury;
    // Fee configs
    BookFeeConfig orderbookFeeConfig;
    SpotFeeConfig spotFeeConfig;
    ParimutuelFeeConfig parimutuelFeeConfig;
    // Amounts
    uint128 parimutuelMinEntry;
    uint128 marketCreationFee;
    uint128 spotBookCreationFee;
    uint128 marketCreationBond;
    uint128 reservedConfigSlot0..3;
    // Durations
    uint64 minMarketDuration;
    uint64 maxMarketDuration;
    uint64 disputeWindow;
    uint64 creatorSettleGrace;
    uint64 openResolutionTimeout;
    uint64 parimutuelEpochWindowCap;
    uint16[8] parimutuelEpochMultipliersBps;
    uint16 marketCreationBatchCap;
    uint8 maxEscalation;
    bool permissionlessCreationEnabled;
    uint128 parimutuelCreationSeedAmount;
    // Combinatorial
    ComboFeeConfig comboFeeConfig;
    uint128 comboMarketCreationFee;
    // Resolver jury
    ResolverJuryConfig resolverJuryConfig;
    // Resolution bonds
    address bondToken;
    uint128 resolutionBondL1;
    uint128 resolutionBondL2;
    // Delayed orders
    uint64 delayedOrderProtectionDelayBlocks;
    uint64 delayedOrderExecutionGraceBlocks;
    uint24 delayedOrderRestingDurationMinutes;
    uint16 delayedOrderProcessorFeeShareBps;
    ProcessingMode delayedOrderProcessingMode;
}
```

### Storage Layout

Core state lives in `LibEveMarket.EveMarketStorage` (slot `eve.prediction.market.storage`). Beyond markets/books/curves/resolutions/metadata, it holds market groups, multi-outcome state (`multiOutcomeMarkets`, labels, displays, position IDs, book IDs), native/combo state (`nativePositionMetadata`, `comboConditions`, `comboConditionLegs`, `comboMarkets`, `comboBookByPositionKey`), collateral profiles and per-profile side mappings, resolution bond accounting (`resolutionBonded`, `bondedByMarket`), delayed-order storage, and the Diamond's own selector/facet/freeze maps.

Subsystems with **separate** storage slots:

```solidity
// LibParimutuel.Storage
struct Storage { mapping(bytes32 => Pool) pools; }

// LibParlay.Storage  (offers, requests, budgets, templates, ticket buckets)
// LibResolverJury.Storage  (disputes, committees, votes, identity/staking, reputation)
```


---

## View Functions

### Market Queries (MarketFactoryFacet / MarketViewFacet)

```solidity
MarketInfo memory info        = getMarketInfo(marketId);
MarketSummary[] memory s      = getMarketSummaries(user, marketIds);
MarketTokenInfo memory t      = getMarketTokenInfo(marketId);
(bytes32 conditionId, address collateral, uint256 yesId, uint256 noId) = getMarketPositions(marketId);
MarketMetadataView memory m   = getMarketMetadata(marketId);
MarketDisplayView memory d    = getMarketDisplay(marketId);
MarketExternalRefView memory r= getMarketExternalRef(marketId);
PositionMetadataView memory p = getPositionMetadata(positionToken, positionId);
string memory uri             = positionTokenURI(positionToken, positionId);
MarketConfigView memory cfg   = getMarketConfig();
(uint256[] memory yes, uint256[] memory no) = getUserMarketPositions(user, marketIds);

// Market groups
MarketGroupView memory g       = getMarketGroup(groupId);
bytes32[] memory ids           = getMarketGroupMarkets(groupId);
GroupMarketDisplayView memory gd = getGroupMarketDisplay(groupId, marketId);

// Collateral profiles
CollateralProfileView memory cp = getCollateralProfile(profileId);

// ID computation
bytes32 id = computeMarketId(question, category, tradingStartTime, expiryTime, collateralToken, marketType, positionTokenType);
bytes32 id = computeProfileMarketId(question, category, tradingStartTime, expiryTime, collateralToken, profileId, payoutUnit, marketType, positionTokenType);
```

### Curve & Book Queries

```solidity
CurveInfo memory c = getCurveInfo(curveId);
(uint32 generation, bytes32 commitment) = getCurveCommitment(curveId);
(uint128 sharesOut, uint128 fee, uint128 price, uint128 makerTopUp) = previewCurveQuote(curveId, collateralIn);
(uint128 sharesOut, uint128 fee, uint128 avgPrice, uint128 unfilled) = previewBestExecution(marketId, isYesSide, collateralIn, curveIds);
(uint128 bestYes, uint128 bestNo, uint128 midpoint, uint128 lastTrade, uint128 display) = getMarketTopOfBook(marketId);

BookInfo memory b = getBookInfo(bookId);
bytes32 bookId    = getMarketSideBook(marketId, isYesSide);
bytes32 bookId    = computeBookId(creator, assetType, baseTransferMode, baseToken, baseTokenId, quoteToken, tickPresetId, salt);
```

### Parimutuel Queries

```solidity
PoolView memory pool = getParimutuelPool(marketId);
(uint256 yesShares, uint256 noShares) = getParimutuelBalances(marketId, user);
(uint256 claimable, uint256 userWinning, uint256 totalWinning, uint256 pool) = previewPayout(marketId, user);
(uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 seniorPoolFee, uint128 resolverFee, uint128 netShares) = previewEntryFee(marketId, amount);
EntryPreview memory p = previewParimutuelEntry(marketId, isYes, amount);
bool isPari = isParimutuelMarket(marketId);
(uint256 multiplierBps, uint256 epoch) = getEpochMultiplier(marketId);
uint16[8] memory schedule = getParimutuelEpochMultipliers();
uint64 window = getParimutuelEpochWindow(marketId);
```

### Resolution & Fee Queries

```solidity
(ResolutionInfo[] memory history, uint8 level, uint64 deadline, bool active) = getResolutionHistory(marketId);
(uint8 state, uint8 outcome, uint64 deadline, uint128 escrowed) = getMarketStatus(marketId);

(uint128 accrued, uint128 claimed, uint128 claimable) = previewMakerFees(marketId, maker);
(uint128 quoteVolume, uint128 accrued, uint128 claimed, uint128 claimable) = getMakerMarketAccounting(marketId, maker);
(uint128 accrued, uint128 claimed, uint128 claimable) = previewBookMakerFees(bookId, maker);
```

### Settlement Queries

```solidity
(uint256 claimable, uint256 yesBalance, uint256 noBalance, uint8 outcome) = previewRedemption(marketId, user);
(address collateral, bytes32 conditionId, uint256[] memory indexSets) = getCTFRedemptionParams(marketId);
previewCTFRedemption(marketId, user);
previewParimutuelPayout(marketId, user);
```


---

## Trade Router

The current router surface is split by execution responsibility while remaining exposed through the Diamond. Market routers (mint-and-buy, collateral buy/sell, exact-fill, preview) are declared on `ITradeRouter`; book-addressed routers live on the separate `ITradeRouterBook` interface. Both interfaces are cut into the same Diamond proxy, so callers address them through the Diamond and select the facet by selector:

- `StaticsDollarTradeRouterFacet` — exact USDG pegged mint followed by a Statics-Dollar market buy, with approval and permit variants.
- `CollateralTradeRouterFacet` / `CollateralTradeRouterExactFacet` — direct collateral buys, optional permit, and exact-fill enforcement.
- `CollateralTradeRouterSellFacet` / `CollateralTradeRouterPreviewFacet` — direct collateral sells and previews.
- `TradeRouterBookFacet` / `TradeRouterBookSellFacet` — book-addressed buys and sells.

```solidity
FillBestResult memory r = tradeRouter.mintAndBuyWithUSDC(params);
FillBestResult memory r = tradeRouter.mintAndBuyWithUSDCPermit(params, permitSignature);
FillBestResult memory r = tradeRouter.buyWithCollateral(fillBestParams);
FillBestResult memory r = tradeRouter.buyWithCollateralWithPermit(fillBestParams, permitSignature);
FillBestResult memory r = tradeRouter.buyWithCollateralExact(fillBestParams);
SellBestResult memory r = tradeRouter.sellWithCollateral(sellParams);
SellBestResult memory r = tradeRouter.previewSellBest(sellParams);
FillBestResult memory r = tradeRouter.buyBookWithCollateral(fillBookParams);
SellBookResult memory r = tradeRouter.sellBookWithCollateral(sellBookParams);
```

Routers snapshot token balances and internal margin, MLO reward, native-position, and Senior-exposure liabilities. Successful calls restore the expected residual balance rather than assuming the Diamond must hold zero of a shared custody token.

---

## Statics Dollar Collateral Rail & Internal Senior Capital

### Overview

```text
USDG <-> StaticsDiamond <-> Statics Dollar
                              |
                              v
                    EveMarketDiamond custody
                              |
                  Senior namespaced accounting
                 /             |              \
          MLO capacity    indexed fee yield    FIFO exits
```

- `Statics Dollar` — the canonical Statics stable asset and Eve launch collateral/margin asset.
- `SeniorCapitalFacet` — user deposit, pending withdrawal, activation, exit, fee claim, and donation lifecycle.
- `SeniorCapitalViewFacet` — aggregate, account, exit, bucket, and pending-fee views.
- `LibSeniorCapital` — isolated storage and the only internal accounting primitive used by fee and MLO paths.

### Contracts

| Contract | File | Type |
|---|---|---|
| SeniorCapitalFacet | `src/facets/SeniorCapitalFacet.sol` | User lifecycle |
| SeniorCapitalViewFacet | `src/facets/SeniorCapitalViewFacet.sol` | Read surface |
| LibSeniorCapital | `src/libraries/LibSeniorCapital.sol` | Namespaced accounting |

### Senior capital lifecycle

```solidity
function depositSeniorCapital(uint256 assets) external returns (uint256 credited);
function withdrawPendingSeniorCapital(uint256 assets, address receiver) external returns (uint256 withdrawn);
function activateSeniorCapital() external returns (uint256 principal, uint256 storedUnits);
function requestSeniorCapitalExit(uint256 principal, address receiver) external returns (...);
function cancelSeniorCapitalExit(uint256 exitId) external returns (uint256 principalRestored);
function processSeniorCapitalExits(uint256 maxRequests) external returns (...);
function claimSeniorCapitalFees(address receiver) external returns (uint256 amount);
function donateSeniorCapitalFees(uint256 assets) external returns (uint256 credited);
```

Deposits are explicit accounting operations, not `balanceOf` inference. They remain pending for 15 minutes and may be withdrawn during that window. Activation converts eligible principal into non-transferable stored units at the current epoch scale. No ERC-20 or ERC-4626 Senior share exists, so capital cannot be transferred, pledged, or manipulated by donating tokens to the Diamond.

**Fee index:** orderbook, parimutuel, parlay, donations, and the Senior share of MLO funding add Statics Dollar to an accumulator-per-stored-unit index. Existing active and queued units earn the increment; pending deposits and future activations do not. Direct transfers are inert. Rounding remainder stays in the epoch and the final claimant receives residual fee dust.

**MLO accounting:** MLO code calls `LibSeniorCapital` directly to reserve available principal, deploy reserved principal, repay exposure, and record a realized loss. These are internal library operations, not owner-configurable calls into an external risk manager. Reserved and active principal are bucket-attributed; `availableCapital` excludes both queued exit claims and reservations.

**Losses and exits:** realized loss reduces total principal and scales every unit in the current epoch pro rata. A total loss exhausts the epoch without destroying previously earned fee claims. Exits are FIFO and permissionlessly processed in bounded batches of at most 50 requests. A head exit may be partially paid when only part of its principal is liquid; later exits cannot skip it.

**Custody invariant:** accounted pending principal, effective active principal, and fee reserve are distinct liabilities. MLO deployment can move principal into position backing without changing its accounted ownership. Router residual checks compensate only for the measured change in internal Senior active exposure, rather than treating all Diamond token balance as router residue.

### MLO Inventory, Quotes, And Senior Backing

MLO curves use a generic side-aware lifecycle across binary CTF books and canonical
2-through-16-outcome NegRisk CTF books. Each curve binds one quote envelope, bucket, market,
outcome index, outcome count, the internal Senior bucket, and side. There are no legacy ASK-only
lifecycle aliases.

MLO ASK curves use two explicit, non-overlapping sources of executable backing:

1. Sold-outcome inventory held in a bucket-specific `MLOInventoryVault`.
2. Senior capital reserved for the remaining curve capacity.

Curve creation earmarks available sold-outcome inventory first and reserves Senior
capital only for the deficit. Per-curve and per-market reservation ledgers prevent the
same inventory or Senior capacity from backing multiple executable curves. A
permissionless `rebalanceMLOAskCurve` call can replace a curve's Senior reservation
with inventory that becomes available later without changing total curve backing.

ASK fills consume the curve's inventory reservation first. The internal Senior ledger deploys
capital and creates a fresh binary CTF or adapter-backed N-way complete set only for any remaining
fill deficit. Gross proceeds repay no more than outstanding Senior principal; proceeds
above debt are cash-backed maker profit. The maker's filled scenario vector is then
rebuilt from the exact market debt and per-outcome vault inventory rather than inferred
from the displayed curve price.

`mergeMLOCompleteSet` permissionlessly merges equal, unreserved inventory across every
market outcome. Returned collateral repays Senior debt first and credits only the
residual to maker margin. Inventory reserved by an active curve cannot be merged or
consumed during resolution settlement. Bucket-attributed reservations and active debt
remain in the same immutable Diamond storage namespace until both are zero; there is no
external pool address to swap during a live exposure.

MLO BID curves reserve Senior capital at the envelope's maximum price. A fill deploys
only the actual gross payment, releases the consumed reservation surplus, pays the
seller net of book fees, and moves the sold outcome into the bucket vault. ASK and BID
fees use the same book fee accounting as ordinary escrow-backed curves.

Direct `BookTradeFacet` routes and delayed FIFO routes dispatch ordinary escrow curves
and MLO curves through one price-ordered execution engine. Delayed fills consume assets
already escrowed by the Diamond but preserve the original taker or seller for self-fill
and event accounting. Book-addressed convenience routers support direct quote-collateral buys and sells.

For NegRisk outcomes, ASK execution calls the configured event adapter, transfers the sold
CTF position to the buyer, and transfers every complementary YES position to the bucket
vault. Complete-set merge returns an exact equal set through the adapter. Winning and
INVALID settlement redeem only the inventory amounts recorded by the MLO ledger; unsolicited
vault tokens neither increase collateral proceeds nor maker profit. Binary CTF behavior
continues to use direct CTF split, merge, and redemption.

All reservation, rebalance, fill, merge, and settlement transitions operate on one
curve and one bounded market ledger. They do not scan a maker's other curves or markets.
The public ASK fill and Diamond-only ASK route selectors are split across facets, and
the Phase 4 suite enforces the EIP-170 runtime limit for all MLO and book-router facets.

### MLO Profit-Split Governance

Each margin bucket snapshots the active maker/Senior/insurance split version when capital is allocated. A later split proposal cannot rewrite an existing bucket's economics. New split proposals use an independently configured delay and a fixed two-day execution window.

```solidity
mloProfitShare.initializeMLOProfitSplit(makerBps, seniorBps, insuranceBps, profitSplitDelay);
mloProfitShare.scheduleMLOProfitSplit(makerBps, seniorBps, insuranceBps);
mloProfitShare.cancelMLOProfitSplit();
mloProfitShare.executeMLOProfitSplit();
mloProfitShare.setMLOProfitSplitDelay(newDelay); // itself protected by Diamond governance delay
uint64 delay = mloProfitShare.mloProfitSplitDelay();
```

The current testnet default follows the 15-minute Diamond delay; production configuration is expected to set seven days explicitly.


---

## Historical Predecessor: eveUSD ETH-Backed Stablecoin

> **Historical only:** The contracts and selectors in this section are not present in the canonical launch codebase. Statics Dollar plus internal Senior capital supersede this design. This section is retained solely to explain predecessor accounting and recovery decisions.

### Overview

`eveUSD` was designed as an ETH-backed, options-style senior stablecoin — a separate subsystem from the eveUSDC trading collateral. A user deposits collateral into the `EveUSDPool` and receives two tokens minted against the same collateral:

- **`eveUSD`** — an 18-decimal ERC-20 **senior** claim, minted at par against the deposit at the pool's collateral ratio. It is the stable leg.
- **`EtRisk`** — an ERC-1155 **junior** risk share, one token ID per *risk series*. It is the volatile leg that absorbs collateral price movement and carries recovery/recapitalization exposure.

Every deposit mints equal amounts of `eveUSD` and `EtRisk` for the current active series (a "pair"). Recombining a full pair (equal `eveUSD` + `EtRisk` of the same series) returns the proportional collateral. The structure behaves like a covered call / collateralized option split: senior holders get downside protection funded by junior holders, and when collateral drops through a price band the impaired series is frozen and rolled into a fresh series so new deposits are never diluted by legacy risk.

> This is a clean-break ERC-1155 series model: an impaired series can never claim junior equity created by a later series.

### Contracts

| Contract | File | Type | Role |
|---|---|---|---|
| EveUSD | `src/EveUSD.sol` | ERC-20 (18 decimals) | Senior par claim; active pool can mint, active or burn-only retired pools can burn |
| EveRiskShares (`EtRisk`) | `src/EveRiskShares.sol` | ERC-1155 | Junior risk shares, one ID per series; active pool can mint, active or burn-only retired pools can burn |
| EveUSDPool | `src/EveUSDPool.sol` | Standalone | Core accounting: profiles, deposit, recombine, recovery lifecycle |
| EveUSDRouter | `src/EveUSDRouter.sol` | Standalone | ETH/WETH deposit + recombine with slippage bounds and residual snapshots |
| ChainlinkETHUSDOracle | `src/ChainlinkETHUSDOracle.sol` | Standalone | ETH/USD price adapter (`ethUsdPriceWad`) |
| EtRiskStakingRewards | `src/EtRiskStakingRewards.sol` | Standalone | Optional fee distributor for staked active-series `EtRisk` |

`EveUSD.pool()` and `EveRiskShares.pool()` return the active minting pool; the pool and router validate these links at construction. Pool replacement is token-local, timelocked, and marks the previous pool burn-only so old series can exit without letting retired pools mint new supply.

### Pricing & Accounting

All math is WAD (1e18) fixed point; ratios are in bps (`BPS_DENOMINATOR = 10_000`).

```
collateralPerPairWad = (WAD × collateralRatioBps / 10_000) × WAD / priceWad
```

- On deposit, `minted = netCollateral × WAD / series.collateralPerPairWad`, and equal `eveUSD` and `EtRisk` are minted (`sharesMinted == eveUSDMinted`).
- The series is priced from the collateral profile's USD oracle **at series creation**; `collateralPerPairWad` is fixed for the life of the series.
- `collateralRatioBps` (global) = `collateralValueWad × 10_000 / seniorLiabilities`, where `collateralValueWad = accountedCollateral × priceWad / WAD` and `seniorLiabilities = eveUSD.totalSupply()`.
- Direct WETH donations do not inflate share pricing — the pool tracks `accountedCollateral` and per-series `accountedCollateral` rather than raw balances.

### Configuration & Bounds

Owner-set, lockable via `lockConfig()` (irreversible). Constants enforce bounds:

| Parameter | Bounds |
|---|---|
| `collateralRatioBps` (per profile, next series) | `10_001` – `30_000` |
| `priceBandBps` (per profile, next series) | `10_001` – `30_000`, and `≤ collateralRatioBps` |
| `recoveryTimelock` | `1 day` – `30 days` (default `7 days`) |
| `mintFeeBps` / `recombinationFeeBps` (per profile) | ≤ `1_000` (10%) |
| `insuranceTargetBps` / `insuranceFeeBps` (per profile) | ≤ `10_000` |

Config setters: `createCollateralProfile`, `setCollateralProfileOracle`, `setCollateralProfileConfig`, `setCollateralProfileFeeBps`, `setCollateralProfileInsuranceBps`, `setRecoveryTimelock`, `setFeeRecipient`, `transferOwnership`, `lockConfig`. Fees are taken in the profile's collateral token and sent to `feeRecipient`.

### Series Lifecycle

```solidity
enum SeriesStatus { None, Active, RecoveryPending, RecoveryFinalized, OperatorRecoverable, Retired }
```

```
Active
  ├─ depositCollateral → mint eveUSD + EtRisk(seriesId)
  ├─ recombine         → burn pair, return proportional collateral
  ├─ setCollateralProfileExitOnly(true) → no new deposits, recombination still available
  └─ startRecovery (oracle price ≤ trigger) → RecoveryPending

RecoveryPending
  ├─ returnRiskShares / reclaimReturnedRiskShares   (junior holders opt in/out of migration)
  ├─ cancelRecovery (price recovers above trigger)  → Active
  └─ finalizeRecovery (after timelock, still impaired) → OperatorRecoverable + new Active series

If the profile is exit-only, `finalizeRecovery` reverts instead of opening a successor series.

OperatorRecoverable (old series)
  ├─ claimRecoveredRiskShares    (returned holders migrate into the new series)
  └─ recoverExpiredRisk          (operator sweeps stragglers into the new series)
```

### Key Operations

```solidity
// Deposit collateral → senior + junior
(uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
    pool.depositCollateral(profileId, collateralAmount, eveUSDReceiver, shareReceiver);

// Recombine a full pair (exact shareAmount == required) → collateral
uint256 collateralOut = pool.recombine(seriesId, eveUSDAmount, shareAmount, receiver);

// Recovery lifecycle
pool.startRecovery(seriesId);                                  // price ≤ trigger
pool.returnRiskShares(seriesId, shares);                       // opt into migration
uint256 shares = pool.reclaimReturnedRiskShares(seriesId, receiver); // opt back out (while Active/RecoveryPending)
pool.cancelRecovery(seriesId);                                 // price restored
uint256 newSeriesId = pool.finalizeRecovery(seriesId);         // after timelock, still impaired

// Post-finalization junior migration
(uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOutAfterMigration) =
    pool.claimRecoveredRiskShares(oldSeriesId, receiver, mode);
(uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted) =
    pool.recoverExpiredRisk(holder, oldSeriesId, shares);      // operator-driven
```

### Recovery Claim Modes

When a returned junior holder migrates from an `OperatorRecoverable` old series into the new series:

```solidity
enum RecoveryClaimMode { CollateralDifference, MorePairs }
```

Let `oldClaimCollateral` be the collateral value of the holder's returned shares in the old series and `baseNewClaimCollateral` the collateral needed to mint the same share count in the new series (which requires `baseNewClaimCollateral ≤ oldClaimCollateral`):

- **`CollateralDifference`** — mint the same number of new-series shares (`sharesMinted == shares`) and pay out the surplus `oldClaimCollateral − baseNewClaimCollateral` as collateral.
- **`MorePairs`** — roll the full `oldClaimCollateral` into the new series, minting the maximum new senior/junior pair amount it supports.

`finalizeRecovery` opens the successor series at the live oracle price, and migration math ensures the old series cannot claim junior equity created by the successor.

### Router

`EveUSDRouter` wraps the pool for ETH-native UX and enforces slippage plus strict residual-balance snapshots (WETH, eveUSD, EtRisk-by-series, native ETH) after each call. It implements `IERC1155Receiver`.

```solidity
(uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
    router.depositETH{value: x}(eveUSDReceiver, shareReceiver, minEveUSD, minShares);
router.depositWETH(wethAmount, eveUSDReceiver, shareReceiver, minEveUSD, minShares);
uint256 wethOut = router.recombineToWETH(seriesId, eveUSDAmount, maxSharesIn, receiver, minWETHOut);
uint256 ethOut  = router.recombineToETH(seriesId, eveUSDAmount, maxSharesIn, receiver, minETHOut);
```

### Oracle

`ChainlinkETHUSDOracle` adapts a Chainlink ETH/USD aggregator to `ethUsdPriceWad()` and enforces:

- Positive answer, non-future `updatedAt`, `answeredInRound ≥ roundId`
- Staleness: `block.timestamp − updatedAt ≤ maxStaleness`
- Optional price bounds (`minPriceWad` / `maxPriceWad`, exclusive)
- Optional L2 sequencer-uptime feed with a grace period (`SequencerDown` / `SequencerGracePeriodActive`)
- Feed decimals ≤ 18, scaled up to WAD

`MockETHUSDOracle` provides a settable price for tests.

### Preview & View Functions

```solidity
DepositPreview       memory p = pool.previewDeposit(wethAmount);
RedemptionPreview    memory p = pool.previewRecombine(seriesId, eveUSDAmount);
uint256 shares                = pool.requiredSharesForRecombine(seriesId, eveUSDAmount); // == eveUSDAmount
OperatorRecoveryPreview memory p = pool.previewOperatorRecovery(holder, oldSeriesId, shares);
RecoveredRiskClaimPreview memory p = pool.previewRecoveredRiskClaim(account, oldSeriesId, mode);

RiskSeries memory s = pool.riskSeries(seriesId);
uint256 shares      = pool.returnedShares(seriesId, account);
uint256 wethAmount  = pool.totalCollateral();
uint256 eveUSDAmt   = pool.seniorLiabilities();
uint256 usdValueWad = pool.collateralValueWad();
uint256 ratioBps    = pool.collateralRatioBps();
uint256 seriesId    = pool.currentRiskSeriesId();
```


---

## Faucet

`Faucet.sol` is a standalone owner-managed multi-token testnet faucet (`Ownable`, `ReentrancyGuard`, `CLAIM_INTERVAL = 1 days`). The owner configures per-token amounts via `setToken` / `setTokenAmount` / `setTokenEnabled`; users call `claim()` once per interval to receive the configured amount of every enabled token; `withdraw` (owner) recovers funds. Testnet-only utility.

---

## Events

All shared events are defined in `libraries/Events.sol`. Key groups:

### Market Lifecycle

```solidity
event MarketCreated(bytes32 indexed marketId, uint8 indexed marketType, address indexed creator, uint8 positionTokenType, address positionToken, address collateralToken, bytes32 resolutionId, bytes32 conditionId, uint256 yesPositionId, uint256 noPositionId, string question, uint64 expiryTime);
event MarketCollateralProfile(bytes32 indexed marketId, uint8 indexed collateralProfileId, address indexed collateralToken, uint128 payoutUnit, uint128 marketCreationFee);
event MarketDisplayMetadataSet(...);
event MarketExternalReferenceSet(...);
event MarketGroupCreated(bytes32 indexed groupId, address indexed creator, bytes32 indexed titleHash, string title, uint256 marketCount);
event MarketGroupMarketAdded(bytes32 indexed groupId, bytes32 indexed marketId, uint256 indexed index);
event MarketExpired(bytes32 indexed marketId);
event MarketResolved(bytes32 indexed marketId, uint8 outcome);
event MarketSettled(bytes32 indexed marketId);
```

### Creation Bond

```solidity
event CreationBondLocked(bytes32 indexed marketId, address indexed creator, uint128 amount);
event CreationBondReleased(bytes32 indexed marketId, address indexed creator, uint128 amount);
event CreationBondSlashed(bytes32 indexed marketId, address indexed creator, address indexed rewardRecipient, uint128 amount);
```

### Curve / Book

```solidity
event BookCreated(bytes32 indexed bookId, bytes32 indexed marketId, address indexed creator, uint8 assetType, address baseToken, uint256 baseTokenId, address quoteToken, bool isYesSide);
event SpotBookCreationFeePaid(bytes32 indexed bookId, address indexed creator, address indexed treasury, uint128 amount);
event BookDecommissionRequested(bytes32 indexed bookId, address indexed caller, uint64 requestedAt, uint64 availableAt);
event BookDecommissioned(bytes32 indexed bookId, address indexed caller);
event CurvePosted(bytes32 indexed marketId, uint256 curveId, address maker, bool isYesSide, uint256 packed);
event BookCurvePosted(bytes32 indexed bookId, bytes32 indexed marketId, uint256 indexed curveId, address maker, bool isYesSide, uint8 curveSide, uint256 packed);
event CurveUpdated(uint256 indexed curveId, uint256 newPacked, uint32 generation);
event CurveUpdatedFromNow(uint256 indexed curveId, uint256 newPacked, uint32 generation, uint64 createdAt);
event CurveReactivated(...);
event CurveToppedUp(bytes32 indexed marketId, uint256 indexed curveId, address indexed maker, uint128 addedVolume, uint128 newRemainingVolume);
event CurveFilled(uint256 indexed curveId, address indexed maker, address taker, uint128 collateralIn, uint128 sharesOut, uint128 fee);
event TradeRouted(bytes32 indexed marketId, address indexed taker, bool isYesSide, uint128 totalCollateralIn, uint128 totalSharesOut, uint128 averagePrice, uint256 curveCount);
event CurveCancelled(uint256 indexed curveId);
event CurveExpired(uint256 indexed curveId);
```

### Delayed Orders

```solidity
event UserCreditChanged(address indexed owner, uint8 indexed creditAssetType, address indexed token, uint256 tokenId, int256 delta);
event DelayedOrderSubmitted(uint256 indexed orderId, bytes32 indexed bookId, address indexed owner, uint8 kind, uint128 amountIn, uint128 limitPrice, uint64 sequence, bytes32 routeHash, uint256[] curveIds, uint32[] expectedGenerations, bytes32[] expectedCommitments);
event DelayedOrderProcessed(uint256 indexed orderId, bytes32 indexed bookId, address indexed owner, address processor, uint8 status, uint128 filledIn, uint128 filledOut, uint128 creditedQuote, uint128 creditedBase, uint128 processorReward, uint256 restingCurveId);
event DelayedOrderExpired(uint256 indexed orderId, bytes32 indexed bookId, address indexed owner, uint128 creditedQuote, uint128 creditedBase);
```

### Parimutuel

```solidity
event ParimutuelMarketCreated(bytes32 indexed marketId, address indexed creator, address indexed positionToken, uint256 yesPositionId, uint256 noPositionId, uint64 expiryTime, uint64 epochWindow);
event ParimutuelCreationSeeded(bytes32 indexed marketId, address indexed creator, uint128 amount);
event ParimutuelSharesBought(bytes32 indexed marketId, address indexed buyer, address indexed receiver, bool isYes, uint128 amountIn, uint128 sharesMinted, uint128 feePaid);
event ParimutuelPayoutClaimed(bytes32 indexed marketId, address indexed claimer, uint256 indexed positionId, uint128 sharesBurned, uint128 payout);
event ParimutuelFinalized(bytes32 indexed marketId, uint8 rawOutcome, uint8 effectiveOutcome, uint128 payoutPool, uint128 totalClaimableShares);
event ParimutuelDustSwept(bytes32 indexed marketId, address indexed recipient, uint128 amount);
event ParimutuelEpochMultipliersUpdated(uint16[8] multipliersBps);
```

### Multi-Outcome

```solidity
event MultiOutcomeMarketCreated(bytes32 indexed marketId, bytes32 indexed conditionId, address indexed creator, uint8 outcomeCount, bytes32 outcomesHash);
event MultiOutcomeDisplaySet(...);
event OutcomePositionPrepared(bytes32 indexed marketId, uint8 indexed outcome, uint256 indexed positionId);
event OutcomeBookPrepared(bytes32 indexed marketId, uint8 indexed outcome, bytes32 indexed bookId);
event OutcomeSetSplit(bytes32 indexed marketId, address indexed account, uint128 amount);
event OutcomeSetMerged(bytes32 indexed marketId, address indexed account, uint128 amount);
event MultiOutcomeResolved(bytes32 indexed marketId, uint8 indexed outcome, bool invalid, uint256 payoutDenominator);
event OutcomeRedeemed(bytes32 indexed marketId, address indexed account, uint8 indexed outcome, uint128 amountIn, uint128 collateralOut);
```

### Native / Combinatorial

```solidity
event ComboConditionPrepared(bytes32 indexed conditionId, bytes32 indexed legsHash, uint16 legCount, uint256 yesPositionId, uint256 noPositionId, uint256[] legs);
event ComboSplit(...);  event ComboMerged(...);  event ComboWrapped(...);  event ComboUnwrapped(...);
event ComboRedeemed(...);
event ComboMarketCreated(bytes32 indexed marketId, bytes32 indexed conditionId, address creator, address positionToken, uint256 yesPositionId, uint256 noPositionId, bytes32 yesBookId, bytes32 noBookId, address quoteToken, uint64 expiryTime);
event ComboMarketCreationFeePaid(bytes32 indexed marketId, address indexed creator, address indexed treasury, uint128 amount);
```

### Parlays

```solidity
event ParlayConfigSet(...);  event ParlayTemplateCreated(...);
event ParlayOfferPosted(...);  event ParlayOfferFilled(...);  event ParlayOfferCancelled(...);
event ParlayRequestPosted(...);  event ParlayRequestFilled(...);  event ParlayRequestCancelled(...);
event ParlayFlatFeeRouted(...);
event ParlayBudgetCreated(...);  event ParlayBudgetFunded(...);  event ParlayBudgetConsumed(...);  event ParlayBudgetCancelled(...);
event ParlayBudgetOfferPosted(...);  event ParlayBudgetRequestPosted(...);
event ParlayTicketBucketFinalized(...);  event ParlayTicketClaimed(...);
event StrategyCreated(...);
```

### Resolution

```solidity
event CreatorSettled(bytes32 indexed marketId, uint8 outcome);
event EarlyCreatorSettled(bytes32 indexed marketId, uint8 outcome);
event OpenResolutionStarted(bytes32 indexed marketId, address indexed proposer, uint8 outcome);
event ResolutionDisputed(bytes32 indexed marketId, address disputer, uint8 counterOutcome, uint8 escalationLevel);
event ResolutionFinalized(bytes32 indexed marketId, uint8 outcome);
event CreatorSettlementEvaluated(bytes32 indexed marketId, address indexed creator, uint8 creatorOutcome, uint8 finalOutcome, bool settledHonestly);
event CreatorFeeEligibilitySet(bytes32 indexed marketId, address indexed creator, bool eligible, uint128 escrowedFees);
event CreationBondReturnabilitySet(bytes32 indexed marketId, address indexed creator, bool returnable, uint128 amount);
event BondSlashed(bytes32 indexed marketId, address slashedAddress, uint128 amount);
event CreatorFeesForfeited(bytes32 indexed marketId, uint128 amount);
event PayoutReported(bytes32 indexed marketId, uint8 outcome, bytes32 payoutVectorHash);
```

### Resolver Identity & Jury

```solidity
event IdentityMinted(uint256 indexed identityId, address indexed owner);
event IdentityRolesUpdated(uint256 indexed identityId, bool creatorRole, bool resolverRole);
event CreatorReputationUpdated(...);  event ResolverReputationUpdated(...);
event ResolverActivationRequested(uint256 indexed identityId, uint64 activationTimestamp);
event ResolverBecameEligible(uint256 indexed identityId, uint64 eligibleAt);
event ResolverExitRequested(uint256 indexed identityId, uint64 exitTimestamp);
event ResolverStakeDeposited(...);  event ResolverStakeWithdrawn(...);
event ResolverPoolCapacityUpdated(uint16 priorValue, uint16 newValue);
event ResolverJuryInitiated(bytes32 indexed disputeId, bytes32 indexed marketId, uint8 round);
event RandomnessCommitted(...);  event RandomnessRevealed(...);  event RandomnessFailure(...);
event CommitteeSelected(bytes32 indexed disputeId, uint8 indexed round, uint16 committeeSize, bytes32 seed, uint256[] identityIds);
event VoteCommitted(...);  event VoteRevealed(...);
event AppealOpened(...);  event RewardDistributed(...);  event ResolverSlashed(...);
event DisputeFinalized(bytes32 indexed disputeId, bytes32 indexed marketId, uint8 finalResult);
event ConfigUpdated(bytes32 paramName, uint256 priorValue, uint256 newValue);
```

### Fees & Maker Rewards

```solidity
event MakerFeesClaimed(bytes32 indexed marketId, address indexed maker, uint128 amount);
event CreatorFeesClaimed(bytes32 indexed marketId, uint128 amount);
event MarketMakerRewardsConfigured(bytes32 indexed marketId, address indexed rewardToken, uint16 rewardRateBps);
event MarketMakerRewardsFunded(...);  event MarketMakerRewardAccrued(...);  event MarketMakerRewardsClaimed(...);
event BookMakerFeesClaimed(bytes32 indexed bookId, address indexed maker, uint128 amount);
event BookCreatorFeesClaimed(bytes32 indexed bookId, address indexed creator, uint128 amount);
```

### Historical eveUSD Events (removed predecessor contracts)

```solidity
event Deposited(address indexed caller, address indexed eveUSDReceiver, address indexed shareReceiver, uint256 profileId, uint256 seriesId, uint256 collateralAmount, uint256 eveUSDMinted, uint256 sharesMinted, uint256 priceWad, uint256 collateralPerPairWad);
event Recombined(address indexed caller, address indexed receiver, uint256 indexed seriesId, uint256 eveUSDBurned, uint256 sharesBurned, address collateralToken, uint256 collateralOut, uint256 collateralRatioBpsAfter);
event RecoveryStarted(uint256 indexed profileId, uint256 indexed seriesId, uint256 recoveryEndsAt, uint256 priceWad);
event RiskSharesReturned(address indexed account, uint256 indexed seriesId, uint256 shares);
event ReturnedRiskSharesReclaimed(address indexed account, uint256 indexed seriesId, uint256 shares);
event RecoveryCancelled(uint256 indexed profileId, uint256 indexed seriesId);
event RecoveryFinalized(uint256 indexed profileId, uint256 indexed oldSeriesId, uint256 indexed newSeriesId, uint256 priceWad);
event RecoveredRiskSharesClaimed(address indexed account, uint256 indexed oldSeriesId, uint256 indexed newSeriesId, RecoveryClaimMode mode, uint256 returnedShares, uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOut);
event ExpiredRiskRecovered(address indexed operator, address indexed holder, uint256 indexed oldSeriesId, uint256 newSeriesId, uint256 sharesBurned, uint256 sharesMinted, uint256 eveUSDMinted);
// Config / ownership: OwnershipTransferred, ConfigLockedForever, CollateralProfileCreated,
//                     CollateralProfileConfigured, CollateralProfileOracleSet,
//                     CollateralProfileFeeBpsSet, CollateralProfileInsuranceBpsSet,
//                     RecoveryTimelockSet, FeeRecipientSet, FeeCollected
// Router: ETHDeposited, WETHDeposited, RecombinedToWETH, RecombinedToETH
```


---

## Security Considerations

1. **Conditional / native token backing.** Binary CLOB positions are backed by collateral in Gnosis CTF; multi-outcome positions use wrapped-collateral CTF conditions managed by a snapshotted settlement adapter; combinatorial positions use `EvesPositionManager`. Adapter rotation affects new markets only because historical positions retain their stored adapter. Redemption reverts if backing is insufficient.
2. **Parimutuel pool solvency.** The payout pool equals net collateral after fees; total claimed payouts can never exceed the pool. Dust is swept to treasury only after all claims.
3. **Optimistic concurrency control.** Curve fills verify `expectedGeneration` and `expectedCommitment` (keccak256 of packed params). The generation counter is monotonically increasing.
4. **Slippage protection.** `fillCurve` enforces `minSharesOut`; `fillBest` adds `maxAveragePrice`.
5. **Bond-secured resolution.** Escalation requires increasing bond-token deposits; winning-outcome proposers get bonds returned, losers are slashed to treasury.
6. **Resolver jury integrity.** Committee selection uses commit-reveal randomness; verdicts use commit-reveal voting with equal weight per soulbound identity. Misbehavior (missed commit/reveal, invalid reveal) is slashable. Configurable low-quorum, tie-break, and randomness-failure handling.
7. **Soulbound identities.** `EveIdentity` is non-transferable; approvals/transfers revert; one identity per address; voting weight is equal (`votingWeightOf == 0`), not token-weighted.
8. **Creator accountability.** Creation bond and escrowed creator fees incentivize honest resolution. `creatorSettledHonestly` is evaluated at finalization and drives both fee eligibility and bond returnability.
9. **Time-bounded markets.** Trading allowed only between `tradingStartTime` and `expiryTime`; resolution only after expiry.
10. **Internal facet isolation.** `BondManagerFacet`, `BondTokenGateFacet`, and `OBRResolutionFacet.finalizeFromJury` enforce `msg.sender == address(this)` (delegatecall/self-call only).
11. **Selector freezing.** `DiamondCutFacet` can permanently freeze critical selectors.
12. **Whole-position enforcement.** Inventory split/merge operations enforce the market payout unit and exact transfer deltas; Statics mint-and-buy uses the gateway's exact pegged-mint preview.
13. **Curve expiry enforcement.** Expired curves cannot be filled (`createdAt + durationMinutes × 60`).
14. **Top-up volume balance.** `splitAndTopUp` variants enforce equal total YES and NO volume per market batch.
15. **Zero-winning-side protection (parimutuel).** A YES/NO outcome with no shares on the winning side becomes effectively INVALID, preventing division by zero.
16. **Delayed-order MEV resistance.** Orders become executable only after a block delay and must be processed along a committed route hash; `ProtocolOnly` mode restricts processing to registered processors.
17. **Router residual assertions.** Collateral, Statics-Dollar, and book routers snapshot balances plus shared Diamond liabilities and require the expected balance to be restored after every operation.
18. **Reentrancy protection.** Senior-capital lifecycle calls and Diamond router/mutating facets share `LibReentrancy`; Statics applies its own guards at its separate trust boundary.
19. **External collateral boundary.** Statics Core and `StaticsDiamond` remain authoritative for pegged-profile policy and issuance. Eve validates configured bindings, approves only exact previewed amounts, and clears gateway allowances after minting.
20. **eveUSD oracle safety.** `ChainlinkETHUSDOracle` rejects non-positive, future-dated, stale, and out-of-bounds prices, and honors an optional L2 sequencer-uptime feed with a grace period. The pool re-reads the oracle on every deposit, recovery transition, and recombine preview.
21. **eveUSD series isolation.** Junior risk is series-scoped ERC-1155; an impaired (`OperatorRecoverable`) series can never claim junior equity minted for a later series. `finalizeRecovery` requires the new series to be non-dilutive to the old series' per-pair claim.
22. **eveUSD collateral integrity.** The pool tracks `accountedCollateral` (global and per-series) rather than raw WETH balances, so donations cannot distort share pricing; recombine and recovery burn tokens before transferring WETH.
23. **Historical predecessor controls.** The oracle, series-isolation, collateral-accounting, and config-lock properties above apply only to the removed eveUSD predecessor design.
24. **Governance delay.** After finalization, owner-gated configuration consumes an exact-calldata schedule entry. Changes to the Diamond delay, MLO split delay, margin asset, and settlement adapters are themselves delayed.
25. **Safe integration rotation.** Margin-asset replacement requires zero user-margin, Senior principal, exit, fee, and MLO Senior-reward liabilities. Adapter replacement validates canonical bindings, while historical positions retain snapshotted settlement routes.


---

## Appendix: Correctness Properties

### Property 1: Collateral Conservation (Binary CLOB)
```
backingReserve = total collateral locked in CTF/native condition for this market
Redemption cannot exceed backingReserve
```

### Property 2: Fee Split Completeness (CLOB)
```
fee = grossCost × entryFeeBps / 10,000
fee = makerFee + creatorFee + treasuryFee + seniorPoolFee + resolverFee
ineligible seniorPoolFee routes back to treasury
```

### Property 3: Fee Split Completeness (Parimutuel)
```
totalFee = creatorFee + protocolFee + seniorPoolFee + resolverFee
ineligible seniorPoolFee routes back to protocol fee accounting
netShares = amount - totalFee
```

### Property 4: Curve Volume Conservation
```
remainingVolume decreases only via fills, resets to 0 on cancel, increases only via top-ups
∀ fill: sharesOut ≤ remainingVolume
```

### Property 5: Generation Monotonicity & Commitment Integrity
```
generation increases by 1 on each update; commitment = keccak256(packed)
Stale fills revert on generation or commitment mismatch
```

### Property 6: Market State Machine
```
Inactive → Scheduled → Trading → Pending → Disputed → Resolved
Scheduled → Trading at tradingStartTime
Pending → Resolved (Invalid) on open-resolution timeout
Disputed → Resolver Jury → Resolved at maxEscalation
```

### Property 7: Bond Accounting
```
∀ resolved market: every recorded bond is returned (winning outcome) or slashed (treasury)
resolutionBonded[bonder] and bondedByMarket[marketId][bonder] track locked bond-token amounts
```

### Property 8: Creator Fee Eligibility
```
creatorFeeEligible == true iff creator proposed at level 0,
that outcome equals the final outcome, final outcome != Invalid, and escrowed fees != 0
```

### Property 9: Resolver Jury Verdict Integrity
```
Committee chosen by commit-reveal randomness; verdict by commit-reveal vote (equal weight)
Below quorum / tie / randomness failure handled per configured mode
finalizeDispute routes the verdict back through OBR.finalizeFromJury (self-call only)
```

### Property 10: Deterministic Market Identity
```
marketId folds in marketType, positionTokenType, collateralToken (+ profile payoutUnit when profiled)
No two markets share a marketId; CLOB / parimutuel / multi-outcome variants produce distinct IDs
```

### Property 11: Price Bounds
```
Prediction books: tick ∈ [1, PRICE_SCALE], price = tick
Spot books: tick ∈ [minTick, maxTick], price = tick × tickSize
Curves outside the valid range revert
```

### Property 12: Bid Curve Quote Escrow
```
∀ active BID curve: quoteEscrowRemaining tracks escrowed quote, decreasing by grossCost per fill
Cancel returns quoteEscrowRemaining to the maker
```

### Property 13: Statics Mint-and-Buy Isolation
```
USDG pulled == gateway.previewPeggedMint(profileId, exact Statics Dollar out).totalCollateralIn
gateway allowance is cleared after minting
unfilled Statics Dollar is returned to the buyer
router USDG balance and expected shared-custody liabilities are restored
```

### Property 14: Senior Activation Fairness
```
Deposits remain pending for 15 minutes and earn neither fees nor risk exposure
Activation mints non-transferable stored units at the current epoch scale
The activation checkpoint prevents new capital from receiving past indexed fees
```

### Property 15: Senior Liquidity Bound
```
availableCapital = max(unreservedPrincipal - effectiveQueuedExitPrincipal, 0)
MLO reservations cannot exceed availableCapital
FIFO exits cannot pay more principal than unreservedPrincipal
```

### Property 16: Senior Fee Index Conservation
```
fee accrual increases feeReserve and the epoch accumulator without increasing principal
pending deposits and future activations receive none of the prior index increment
direct etUSD transfers to the Diamond do not alter stored units, principal, or feeReserve
```

### Property 17: Senior Principal Accounting
```
totalPrincipal = unreservedPrincipal + reservedCapital + activeExposure
realized MLO loss reduces totalPrincipal and the epoch scale pro rata
full loss exhausts the principal epoch but preserves its earned fee reserve
```

### Property 18: Internal Senior Authority
```
Only production MLO/funding/fee code linked into the Diamond can mutate reservations,
active exposure, realized loss, and indexed fee state through LibSeniorCapital
There is no owner-configurable external riskManager or Senior pool address
```

### Property 19: Bucket Accounting Conservation
```
For each bucket:
reservedCapital + activeExposure + recovery/insurance allocations are bounded by pool accounting
Deploying reserved bucket capital decreases bucket reserved capital and increases bucket active exposure
Repayment decreases bucket active exposure; realized loss decreases active exposure and increases losses
```

### Property 20: Router Residual Balance
```
∀ successful router operation: router holds zero residual USDC / eveUSDC / position tokens
```

### Property 21: Parimutuel Payout Solvency
```
Σ claimed payouts ≤ payoutPool; claimedPayout monotonically increasing
claimedClaimableShares ≤ totalClaimableSharesAtResolution
```

### Property 22: Zero-Winning-Side Safety
```
Resolved YES with totalYesShares == 0 (or NO with totalNoShares == 0) → effectiveOutcome = Invalid
All participants receive pro-rata refund from payoutPool
```

### Property 23: Epoch Multiplier Solvency
```
payoutPool += netCollateral (not inflated shares)
sharesMinted = netCollateral × multiplierBps / 10,000
The multiplier never creates unbacked obligations; Σ payouts ≤ payoutPool
```

### Property 24: Multi-Outcome Set Conservation
```
splitOutcomeSet mints one token per outcome backed 1:1 by collateral
mergeOutcomeSet burns a full set and releases collateral
Only the resolved outcome (or full set for INVALID) is redeemable post-resolution
```

### Property 25: Combinatorial Position Backing
```
Combo split/merge preserve collateral backing across legs
wrap/unwrap and split/merge preserve the backing assigned to combo conditions
redeemCombo pays out only when the underlying legs resolve favorably
```

### Property 26: Parlay Escrow Solvency
```
Offers escrow maxPayoutPerUnit × units; ticket payouts are bounded by escrowRemaining
finalize resolves payoutPerUnit from the tier schedule and invalid policy
Σ claimed ≤ escrow reserved at finalization
```

### Property 27: Delayed Order Integrity
```
An order is executable only at/after executableBlock and before expiryBlock
Processing must supply a route whose hash equals the committed routeHash
ProtocolOnly mode restricts processing to registered processors
Unfilled/expired escrow is returned as withdrawable credit
```

### Property 28: MLO Profit-Split Delay
```
new proposals become executable at block.timestamp + profitSplitDelay
execution is valid only during the following two-day window
existing buckets retain their snapshotted split version
changing profitSplitDelay requires the active Diamond governance delay
```

### Property 29: Book Accounting Consistency
```
Market-linked book and market fee/volume accounting update in lockstep
Standalone books snapshot fee config at creation and accrue independently
```

### Property 30: Senior-Pool Fee Routing
```
seniorPoolShare accrues to the internal fee index only for the margin asset while active stored units exist
seniorPoolAmount + treasuryFallback == seniorPoolShare (exhaustive)
If internal Senior accounting is ineligible, the whole seniorPoolShare falls back to treasury
```

### Property 31: eveUSD Pair Backing
```
Each deposit mints eveUSDMinted == sharesMinted against net collateral at series.collateralPerPairWad
accountedCollateral (global) == Σ series.accountedCollateral
Recombining a full pair returns collateralOut ≤ series.accountedCollateral pro-rata
Fees are taken from the active collateral profile token only; senior/junior units are never minted unbacked
```

### Property 32: eveUSD Series Isolation
```
Junior risk is ERC-1155 keyed by seriesId
An OperatorRecoverable series never receives junior equity minted for a later series
Successor-series activation never reopens the old series for deposits
```

### Property 33: eveUSD Recovery Trigger Monotonicity
```
startRecovery requires oracle price ≤ startPrice × 10_000 / priceBandBps
cancelRecovery requires price restored above the downside trigger
finalizeRecovery requires block.timestamp ≥ recoveryEndsAt AND price still ≤ downside trigger
rolloverAppreciatedSeries requires oracle price ≥ startPrice × priceBandBps / 10_000
```

### Property 34: eveUSD Recovery Claim Value Preservation
```
Migration requires baseNewClaimCollateral ≤ oldClaimCollateral
CollateralDifference: sharesMinted == returnedShares, collateralOut == oldClaimCollateral − baseNewClaimCollateral
MorePairs:            collateralMoved reflects the old-series collateral claim rolled into the successor pair math
No claim mode increases the holder's collateral-denominated value beyond oldClaimCollateral
```

### Property 35: eveUSD Oracle Validity
```
ethUsdPriceWad reverts on non-positive, future-dated, stale (> maxStaleness), or out-of-bounds prices
When a sequencer feed is set, prices revert while the sequencer is down or within the grace period
Feed answers are scaled to 18-decimal WAD
```

---

**Document Version:** 3.5
**Module:** Eves Market — On-Chain Prediction Market Protocol
