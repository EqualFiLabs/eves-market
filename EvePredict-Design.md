# Eves Market — Design Document
## On-Chain Prediction Market Protocol

**Version:** 3.4
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
20. [eveUSDC Collateral Rail & Senior Capital Pool](#eveusdc-collateral-rail--senior-capital-pool)
21. [eveUSD ETH-Backed Stablecoin](#eveusd-eth-backed-stablecoin)
22. [Faucet](#faucet)
25. [Events](#events)
26. [Security Considerations](#security-considerations)
27. [Appendix: Correctness Properties](#appendix-correctness-properties)

---

## Overview

Eves Market is an on-chain prediction market protocol built on Base. It is structured as an EIP-2535 Diamond with modular facets sharing a single storage layout. The protocol started as a two-type binary market (Curve CLOB and Parimutuel) and has grown into a broader exchange surface that also supports multi-outcome orderbook markets, native combinatorial (parlay-style) positions, peer-to-peer parlays, standalone spot books, and MEV-resistant delayed taker orders.

Markets are resolved through an Optimistic Bond-based Resolution (OBR) system. Instead of escalating to token-weighted governance voting, fully escalated disputes are now decided by a **Resolver Jury** — a staked, soulbound-identity committee that uses commit-reveal randomness for selection and commit-reveal voting for the verdict.

Alongside the market machinery, the protocol includes **eveUSD**, an ETH-backed, options-style senior stablecoin. A WETH deposit into the `EveUSDPool` mints a par-denominated senior claim (`eveUSD`) plus a junior risk share (`EvRisk`, an ERC-1155 series token). The senior/junior split behaves like a collateralized options structure: senior holders hold a stable claim on the WETH collateral while junior holders absorb ETH price volatility and can be recapitalized into a new series when ETH falls through a recovery trigger.

> **Naming note:** the USDC-backed collateral wrapper used for trading is named **eveUSDC** (contract `EveUSDC`). The name **eveUSD** refers exclusively to the ETH-backed senior tranche described in [eveUSD ETH-Backed Stablecoin](#eveusd-eth-backed-stablecoin). Do not confuse the two.

### Key Characteristics

| Feature | Description |
|---------|-------------|
| **Diamond Pattern** | EIP-2535 Diamond proxy with modular facets and a shared storage layout |
| **Multiple Market Types** | CLOB (maker curves), Parimutuel (pooled entry), and Multi-Outcome Orderbook (N-way CLOB) |
| **Book Abstraction** | Per-side order books with independent fee configs and accounting |
| **Spot Books** | Standalone books for trading ERC-20 / ERC-1155 base assets (including FoT tokens) |
| **CTF Positions** | Gnosis Conditional Tokens for binary CLOB position management |
| **Native Positions** | In-Diamond ERC-1155 (`EvesPositionManager`) for combinatorial and multi-outcome positions |
| **Combinatorial Markets** | Native AND-of-legs combo conditions with split/merge/branch/compress operations |
| **Parlays** | Peer-to-peer underwritten multi-leg tiered-payout bets with shared budgets |
| **Parimutuel Shares** | Dedicated ERC-1155 (`ParimutuelShareToken`) for pooled positions with an epoch multiplier |
| **OBR Resolution** | Optimistic Bond-based Resolution backed by a generic bond token |
| **Resolver Jury** | Staked soulbound-identity commit-reveal jury as the dispute backstop |
| **Collateral Profiles** | Pluggable collateral tokens (eveUSDC, eveETH, …) selected per product |
| **eveUSDC Collateral** | USDC-backed ERC-20 wrapper, **18 decimals**, minted at a 1e12 scale over 6-decimal USDC |
| **eveETH Collateral** | WETH-backed 1:1 ERC-20 wrapper (18 decimals) |
| **Senior Capital Pool** | eveUSDC pool for senior capital, revenue, reserved capital, and loss accounting |
| **Delayed Orders** | Block-delayed taker orders with permissionless/protocol processing |
| **eveUSD Stablecoin** | ETH-backed senior/junior options structure: WETH deposit mints `eveUSD` (senior par claim) + `EvRisk` (junior series share) |
| **EvRisk Fee Routing** | Configurable trade-fee share can route into `EvRiskStakingRewards` for active-series `EvRisk` stakers |
| **ETH/USD Oracle** | Chainlink adapter (`ethUsdPriceWad`) with staleness, bounds, and sequencer-uptime checks |
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
| **Senior Capital Provider** | Deposits eveUSDC into `SeniorCapitalPool` |
| **Senior Holder** | Holds `eveUSD` — a par-denominated senior claim on pooled WETH |
| **Junior Holder** | Holds `EvRisk` series shares — absorbs ETH volatility, exposed to recovery |


---

## How It Works

### The Core Model

Eves Market follows a market creation → trading → resolution → settlement lifecycle:

1. **Create** — A creator defines a binary (or multi-outcome) question, a required `resolutionSource`, an optional `tradingStartTime`, and an `expiryTime`, pays a collateral creation fee, and posts a bond-token creation bond. Binary CLOB markets prepare a Gnosis CTF condition; multi-outcome and combinatorial markets prepare native conditions through the `EvesPositionManager`; parimutuel markets register with the `ParimutuelShareToken`.

2. **Trade** — In CLOB markets, makers split collateral into position tokens and post price curves; takers fill curves. In parimutuel markets, users buy single-side shares into a payout pool. In multi-outcome markets, users split collateral into a full outcome set and trade each outcome's book. Fees are collected per fill or entry and can route among maker, creator, protocol treasury, `SeniorCapitalPool`, the active resolver epoch, and `EvRisk` stakers depending on the product config and route eligibility.

3. **Resolve** — After expiry, the creator gets first right to settle. If they don't, the community can propose outcomes with escalating bond deposits. Fully escalated disputes are routed to the Resolver Jury for a commit-reveal verdict.

4. **Settle** — CTF and native position holders redeem winning tokens for collateral. Parimutuel winners claim their pro-rata share of the payout pool. Honest creators get their bond back and can claim escrowed fees.

### Collateral Backing

- **Binary CLOB markets:** Positions are fully backed by collateral locked in the Gnosis CTF (split mints equal YES/NO, redeem burns and releases backing).
- **Multi-outcome & combinatorial markets:** Backed by native conditions held in `EvesPositionManager`; splitting a full set mints one token per outcome (or a combo YES/NO pair), merging burns the set.
- **Parimutuel markets:** All entry collateral (minus fees) enters the payout pool; winners claim pro-rata, INVALID refunds both sides.
- **Parlays:** The underwriter escrows the maximum payout; tickets pay out from that escrow per the payout tier schedule.

### Collateral Rail

The protocol's default collateral token is **eveUSDC**, an 18-decimal ERC-20 wrapper over 6-decimal USDC (minted at a `1e12` scale). Additional collateral tokens (such as **eveETH**, a 1:1 WETH wrapper) are registered through **collateral profiles**, letting individual products choose a non-default collateral while sharing the same trading and settlement machinery. `SeniorCapitalPool` is the active senior eveUSDC capital surface.

---

## Architecture

### Contract Structure

```
eve-predict/src/
├── EveMarketDiamond.sol              # EIP-2535 Diamond proxy
├── EveUSDC.sol                        # USDC wrapper (ERC-20, 18 decimals)
├── SeniorCapitalPool.sol              # Senior eveUSDC capital pool
├── EveUSD.sol                        # ETH-backed senior stablecoin (ERC-20, pool-minted)
├── EveRiskShares.sol                 # Junior risk shares (ERC-1155 per series, pool-minted)
├── EveUSDPool.sol                    # ETH-backed stablecoin pool (deposit / recombine / recovery)
├── EveUSDRouter.sol                  # ETH/WETH ↔ eveUSD + EvRisk router (standalone)
├── ChainlinkETHUSDOracle.sol         # ETH/USD oracle adapter for the pool
├── Faucet.sol                        # Multi-token testnet faucet (standalone)
├── facets/
│   ├── MarketFactoryFacet.sol        # Market + market-group creation, metadata, views
│   ├── MarketViewFacet.sol           # Market queries and views
│   ├── CurveCLOBFacet.sol            # Aggregating CLOB entry point (delegates to curve facets)
│   ├── CurveInventoryFacet.sol       # Split/merge inventory
│   ├── CurveLifecycleFacet.sol       # Curve posting, update, cancel, top-up
│   ├── CurveViewFacet.sol            # Curve and book view functions
│   ├── BookFacet.sol                 # Standalone book creation / lifecycle (admin)
│   ├── BookOrderFacet.sol            # Book curve posting and updates
│   ├── BookTradeFacet.sol            # Book fills and sells
│   ├── BookViewFacet.sol             # Book view functions
│   ├── ParimutuelFacet.sol           # Parimutuel creation, buying, claiming
│   ├── MultiOutcomeOrderbookFacet.sol     # N-way outcome markets (create/split/merge/redeem)
│   ├── MultiOutcomeOrderbookViewFacet.sol # Multi-outcome views
│   ├── DelayedOrderFacet.sol         # Block-delayed taker orders
│   ├── TradeRouterFacet.sol          # Buy/split with eveUSDC, USDC, or profile collateral
│   ├── TradeRouterSellFacet.sol      # Sell positions with eveUSDC, USDC, or profile collateral
│   ├── FeeRouterFacet.sol            # Fee claims (maker + creator), maker rewards
│   ├── MarketSettlementFacet.sol     # CTF / parimutuel / multi-outcome settlement previews
│   ├── OBRResolutionFacet.sol        # Optimistic Bond Resolution
│   ├── BondManagerFacet.sol          # Internal bond accounting (delegatecall-only)
│   ├── BondTokenGateFacet.sol        # Resolution bond token lock/unlock (delegatecall-only)
│   ├── ResolverRegistryFacet.sol     # Resolver identity lifecycle + staking
│   ├── ResolverJuryFacet.sol         # Commit-reveal jury dispute state machine
│   ├── DiamondCutFacet.sol           # Diamond upgrades
│   ├── DiamondLoupeFacet.sol         # Diamond introspection
│   ├── OwnershipFacet.sol            # Diamond ownership
│   ├── native/
│   │   ├── NativeBinaryPositionFacet.sol  # Native binary YES/NO conditions
│   │   ├── ComboCoreFacet.sol             # Combo condition prepare/split/merge/wrap
│   │   ├── ComboBranchFacet.sol           # Combo tree branch/extract/inject operations
│   │   ├── ComboMarketFacet.sol           # Combo market creation + books
│   │   ├── ComboSettlementFacet.sol       # Combo compress/redeem/payout
│   │   └── ComboViewFacet.sol             # Combo/native position views
│   └── parlay/
│       ├── ParlayBase.sol            # Shared parlay internals
│       ├── ParlayAdminFacet.sol      # Parlay config
│       ├── ParlayUnderwritingFacet.sol    # Offers / requests / fills / cancels
│       ├── ParlayBudgetFacet.sol     # Shared underwriting budgets
│       ├── ParlayBookFacet.sol       # Ticket-backed books
│       ├── ParlaySettlementFacet.sol # Ticket finalization and claims
│       ├── ParlayViewFacet.sol       # Parlay views
│       └── ParlayMulticallFacet.sol  # Batched parlay calls
├── init/
│   └── ResolverJuryInit.sol          # Resolver jury initializer
├── tokens/
│   ├── ParimutuelShareToken.sol      # ERC-1155 for parimutuel positions
│   ├── EvesPositionManager.sol       # ERC-1155 for native / combinatorial positions
│   ├── ParlayTicketToken.sol         # ERC-1155 for parlay tickets
│   ├── EveETH.sol                    # WETH 1:1 wrapper (alternate collateral)
│   └── EveIdentity.sol               # Soulbound resolver/creator identity
├── interfaces/                       # All contract interfaces
├── types/                            # Facet param/view structs
├── libraries/                        # Storage + math + helper libraries
└── mocks/                            # Test mocks
```

### Diamond Pattern

The `EveMarketDiamond` is an EIP-2535 Diamond proxy that delegates calls to modular facets. Most facets share a single storage layout defined in `LibEveMarket.EveMarketStorage`, accessed via a deterministic storage slot. Several subsystems use their own dedicated storage slots to keep layouts isolated:

- **Parimutuel pools** — `LibParimutuel.Storage`
- **Parlays** — `LibParlay.Storage`
- **Resolver Jury** — `LibResolverJury.Storage`

The Diamond supports DiamondCut (add/replace/remove facet functions), selector freezing (permanently locking critical selectors), and ERC-1155 receiver hooks (accepting position transfers for escrow and settlement).

The CLOB engine is decomposed across multiple facets for bytecode-size management. `CurveCLOBFacet` is an aggregating entry point; `CurveInventoryFacet`, `CurveLifecycleFacet`, and `CurveViewFacet` provide split/merge, posting/lifecycle, and views respectively. Standalone book operations live in `BookFacet` / `BookOrderFacet` / `BookTradeFacet` / `BookViewFacet`.

Standalone contracts (`EveUSDC`, `EveETH`, `SeniorCapitalPool`, `EveUSD`, `EveRiskShares`, `EveUSDPool`, `EveUSDRouter`, `ChainlinkETHUSDOracle`, `Faucet`) operate outside the Diamond and interact with it (or with each other) through their public interfaces.

> **Note on renames since v2.1:** the former `SpotBook*Facet` family is now `Book*Facet`, and the former `EveTokenGateFacet` is now `BondTokenGateFacet`. The bond gate no longer locks an EVE governance token — it locks a generic `config.bondToken` for resolution bonds.

---

## Market Types

Every market declares its type at creation time. The type determines position-token semantics, trading mechanics, fee structure, and settlement path.

### MarketType Enum

```solidity
enum MarketType {
    CLOB,                    // Binary curve-based order book with CTF positions
    PARIMUTUEL,              // Pooled entry with pro-rata payout
    MULTI_OUTCOME_ORDERBOOK  // N-way mutually-exclusive outcome book (native positions)
}
```

### PositionTokenType Enum

```solidity
enum PositionTokenType {
    CTF,            // Gnosis Conditional Tokens Framework (ERC-1155)
    PARIMUTUEL,     // ParimutuelShareToken (ERC-1155)
    EVES_POSITION   // EvesPositionManager (ERC-1155, native + combinatorial)
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

Collateral profiles let the protocol support multiple collateral tokens without changing market logic. Each product entry point that touches collateral has a `…WithCollateralProfile(uint8 profileId, …)` variant. Profile `0` conventionally maps to eveUSDC; additional profiles (e.g., eveETH) are registered by the owner.

### CollateralProfile

```solidity
struct CollateralProfile {
    address collateralToken;   // ERC-20 used as the unit of account for the product
    address wrapperToken;      // Optional wrapper (e.g., eveETH) for one-click on/off ramps
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

### eveUSDC (18 decimals)

`EveUSDC` is an 18-decimal ERC-20 wrapper over 6-decimal USDC. Wrapping mints at a `1e12` scale via `LibEveUSDCUnits`:

```solidity
USDC_TO_EVEUSDC_SCALE = 1e12;
toEveUSDC(usdcAmount)       = usdcAmount * 1e12;
convertibleEveUSDC(amount)  = (amount / 1e12) * 1e12;   // floors to a USDC-convertible amount
eveUSDCDust(amount)         = amount % 1e12;            // sub-USDC remainder
```

```solidity
interface IEveUSDC is IERC20 {
    function wrap(uint256 usdcAmount, address to) external returns (uint256 eveUSDCMinted); // mints usdcAmount * 1e12
    function unwrap(uint256 eveUSDCAmount, address to) external returns (uint256 usdcOut);  // reverts on non-zero dust
    function mint(address to, uint256 amount) external;   // onramp only
    function burn(address from, uint256 amount) external; // offramp only
    function usdc() external view returns (address);
    function onramp() external view returns (address);
    function offramp() external view returns (address);
}
```

- `decimals()` returns **18**.
- `wrap` transfers USDC from the caller and mints `usdcAmount * 1e12` eveUSDC.
- `unwrap` burns eveUSDC and returns USDC; it reverts if the amount carries non-convertible dust (`amount % 1e12 != 0`).
- `mint`/`burn` are restricted to immutable onramp/offramp addresses.

### eveETH

`EveETH` is a 1:1 WETH wrapper (18 decimals, no scaling) used as an alternate collateral via a collateral profile.

```solidity
contract EveETH is ERC20 {            // "eveETH", 18 decimals
    function wrap(uint256 amount, address to) external returns (uint256 eveETHMinted); // pulls WETH 1:1
    function unwrap(uint256 amount, address to) external returns (uint256 wethOut);    // burns, returns WETH 1:1
    function weth() external view returns (address);
}
```

Native ETH can be wrapped to WETH and then into the profile's eveETH wrapper.


---

## Curve CLOB Trading

### Inventory Management

Before posting curves, makers split collateral into YES/NO position tokens:

```solidity
uint128 sharesMinted  = curveInventory.splitInventory(marketId, collateralAmount);
uint128 collateralOut = curveInventory.mergeInventory(marketId, shareAmount);
```

`splitInventory` transfers collateral from the maker, splits it via the CTF (or native condition), and returns both YES and NO tokens. `mergeInventory` does the reverse.

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
uint256 curveId = curveLifecycle.postBidCurve(marketId, isYesSide, volume, startPrice, endPrice, durationMinutes, profileId, positionTokenType);

// Escrow quote sourced from USDC (auto-wrapped to eveUSDC)
(uint256 curveId, uint128 usdcEscrowed) =
    curveLifecycle.postBidCurveWithUSDC(marketId, isYesSide, volume, startPrice, endPrice, durationMinutes, profileId, positionTokenType);
```

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

// Delegated variant for approved internal callers (routers)
FillBestResult memory result = curveTrade.fillBestFor(params);
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
- Require a `spotBookCreationFee` in eveUSDC paid to the treasury (waived for the Diamond owner)
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
// p: amountIn, totalFee, creatorFee, protocolFee, vaultFee, netCollateral,
//    sharesMinted, multiplierBps, epoch, effectiveBasisWad,
//    totalYesSharesAfter, totalNoSharesAfter, payoutPoolAfter

(uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 vaultFee, uint128 resolverFee, uint128 netShares) =
    parimutuel.previewEntryFee(marketId, amount);
```

```
totalFee    = amount × parimutuelEntryFeeBps / 10,000
creatorFee  = totalFee × creatorFeeBps / 10,000
protocolFee = totalFee × protocolFeeBps / 10,000
resolverFee = totalFee × resolverFeeBps / 10,000
vaultFee    = totalFee - creatorFee - protocolFee - resolverFee   // residual, exhaustive
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

Multi-outcome markets (`MarketType.MULTI_OUTCOME_ORDERBOOK`) support N mutually-exclusive outcomes traded as NegRisk-style native positions. Users split collateral into a full outcome set (one ERC-1155 token per outcome through `EvesPositionManager`), trade each outcome on its own book, and redeem the winning outcome after resolution.

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
(uint128[] memory bestAsk, uint128[] memory bestBid, uint128[] memory mid, uint128[] memory last) =
    multiOutcome.getMultiOutcomeTopOfBook(marketId);
```

`MultiOutcomeMarketView` exposes `outcomeCount`, `resolvedOutcome`, `payoutDenominator`, `invalid`, `resolved`, `collateralProfileId`, and `payoutUnit`. Resolution sets `resolved`, `invalid`, `resolvedOutcome`, and `payoutDenominator` (`= outcomeCount` for INVALID, otherwise `1`), and reports the payout vector.


---

## Native Positions & Combinatorial Markets

### EvesPositionManager

`EvesPositionManager` is an in-Diamond ERC-1155 (minted/burned only by the Diamond) that holds native binary, multi-outcome, and combinatorial positions. It delegates token metadata to the Diamond via `IPositionMetadataProvider.positionTokenURI`.

### Native Binary Conditions

`NativeBinaryPositionFacet` provides CTF-equivalent binary YES/NO splitting using native positions instead of Gnosis CTF:

```solidity
BinaryPositionIds memory ids = nativeBinary.prepareNativeBinaryCondition(marketId);
BinaryPositionIds memory ids = nativeBinary.getNativeBinaryCondition(marketId);
(uint256 yesId, uint256 noId) = nativeBinary.splitNativeBinary(marketId, amount, receiver);
uint128 collateralOut         = nativeBinary.mergeNativeBinary(marketId, amount, receiver);
uint128 collateralOut         = nativeBinary.redeemNativeBinary(marketId, outcomeIndex, amount, receiver);
(bool resolved, uint256 payoutNumerator) = nativeBinary.getNativeBinaryPayout(conditionId, outcomeIndex);
```

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

`ComboBranchFacet` provides tree operations for restructuring combo positions along a binary condition:

```solidity
(uint256 childYes, uint256 childNo) = comboBranch.splitComboOnCondition(parentYesId, binaryConditionId, amount, yesReceiver, noReceiver);
uint256 parentId = comboBranch.mergeComboOnCondition(parentYesId, binaryConditionId, amount, receiver);
(uint256 reducedNo, uint256 residualYes) = comboBranch.extractComboNoLeg(fullNoId, legIndex, amount, reducedNoReceiver, residualYesReceiver);
uint256 fullNoOut = comboBranch.injectComboNoLeg(fullNoId, legIndex, amount, receiver);
uint256[] memory basket = comboBranch.convertComboNoToYesBasket(fullNoId, amount, receivers);
uint256 fullNoOut = comboBranch.mergeComboNoFromYesBasket(fullNoId, amount, receiver);
```

`ComboMarketFacet` turns a set of binary markets/legs into a tradable combo market with its own YES/NO books:

```solidity
ComboMarketPreparation memory prep = comboMarket.createComboMarket(marketIds, yesLegs);
bytes32 bookId = comboMarket.computeComboBookId(comboMarketId, isYesSide);
ComboMarketView memory m = comboMarket.getComboMarket(comboMarketId);
bytes32 bookId = comboMarket.getComboBook(positionToken, positionId);
```

`ComboSettlementFacet` handles compression and redemption:

```solidity
CompressionResult memory r = comboSettlement.compressCombo(positionId, amount, receiver);
uint128 collateralOut      = comboSettlement.redeemCombo(positionId, amount, receiver);
(bool redeemable, uint128 collateralOut) = comboSettlement.getComboPayout(positionId, amount);
```

`ComboViewFacet` exposes `getNativePositionMetadata`, `isComboCompressible`, and `previewComboCompression`.

Combo market creation charges `comboMarketCreationFee` (to treasury) and books use `config.comboFeeConfig`.


---

## Parlays

### Overview

Parlays are peer-to-peer underwritten multi-leg bets with tiered payouts. A parlay **template** binds an ordered set of legs (each a market + required outcome) to a payout-tier schedule and an invalid policy. Underwriters post **offers** (escrowing the maximum payout) and takers post **requests** (escrowing premium + fee); filling either side mints ERC-1155 ticket buckets (`ParlayTicketToken`). Shared **budgets** let an underwriter back many offers/requests from one pool.

Parlay state lives in its own storage slot (`LibParlay.Storage`).

### Configuration

```solidity
parlay.setParlayConfig(ticketToken, feeRecipient, underwritingFee, vaultFeeBps, feeRecipientBps);
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

Finalization counts leg hits/misses/invalids and resolves the payout per unit using the tier schedule and the template's `InvalidPolicy` (`VoidInvalidLegs` or `InvalidCountsAsMiss`). The flat underwriting fee is split between the vault and `feeRecipient`.

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
registry.finalizeResolverEpochSeed(epochId);
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

### Resolver Jury State Machine

```solidity
jury.initiateDispute(marketId);            // called from OBR at maxEscalation
jury.openRandomnessCommit(disputeId);
jury.commitRandomness(disputeId, commitment);
jury.closeRandomnessCommit(disputeId);
jury.revealRandomness(disputeId, value, salt);
jury.closeRandomnessReveal(disputeId);
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

Fees are configured per product family. Each market and each book snapshots its fee config at creation, so protocol-wide changes don't affect existing markets/books.

```solidity
struct BookFeeConfig {       // orderbook (CLOB) and market-linked books
    uint16 entryFeeBps;      // static fee on gross cost per fill
    uint16 makerFeeBps;      // maker share (default ~8500)
    uint16 creatorFeeBps;    // creator share
    uint16 protocolFeeBps;   // protocol share
    uint16 vaultFeeBps;      // vault revenue share of protocol fee
    uint16 resolverFeeBps;   // resolver epoch share
    uint16 evRiskFeeBps;     // active-series EvRisk staking share
}

struct SpotFeeConfig {       // standalone spot books
    uint16 tradeFeeBps;
    uint16 makerFeeBps;
    uint16 protocolFeeBps;
    uint16 vaultFeeBps;
    uint16 resolverFeeBps;
    uint16 evRiskFeeBps;
}

struct ComboFeeConfig {      // combinatorial markets
    uint16 tradeFeeBps;
    uint16 makerFeeBps;
    uint16 creatorFeeBps;
    uint16 protocolFeeBps;
    uint16 vaultFeeBps;
    uint16 resolverFeeBps;
    uint16 evRiskFeeBps;
}

struct ParimutuelFeeConfig {
    uint16 entryFeeBps;
    uint16 creatorFeeBps;
    uint16 protocolFeeBps;
    uint16 vaultFeeBps;
    uint16 resolverFeeBps;
    uint16 evRiskFeeBps;
}
```

### CLOB Trading Fee Split

```
grossCost = baseAmount × price / priceDenominator
fee       = grossCost × entryFeeBps / 10,000

makerFee    = fee × makerFeeBps / 10,000
creatorFee  = fee × creatorFeeBps / 10,000
resolverFee = fee × resolverFeeBps / 10,000
evRiskFee   = fee × evRiskFeeBps / 10,000
rawSeniorPoolFee = fee × vaultFeeBps / 10,000
treasuryFee = fee - makerFee - creatorFee - resolverFee - evRiskFee - rawSeniorPoolFee
  └─ seniorPoolFee = rawSeniorPoolFee routed to SeniorCapitalPool when eligible
  └─ seniorPool fallback = ineligible senior-pool share is added back to treasury
  └─ evRisk fallback = ineligible evRisk share is added back to treasury
```

Fee distribution reads from the **book's** snapshotted fee config. When permissionless creation is disabled, the creator share is redirected to the protocol fee pool. The senior-pool share is routed by `LibFeeRouting.previewSeniorPoolFeeRoute` to `SeniorCapitalPool` when the pool exists, its asset matches the fee token, and it has non-zero supply. Otherwise that share falls back to the treasury. The resolver share is retained in-protocol, accrued to the current resolver epoch, and later split evenly across compliant active jurors. The evRisk share is routed by `LibFeeRouting.previewEvRiskFeeRoute` to `EvRiskStakingRewards` when configured; otherwise it falls back to treasury.

### Parimutuel Entry Fee Split

```
totalFee    = amount × parimutuelEntryFeeBps / 10,000
creatorFee  = totalFee × creatorFeeBps / 10,000
protocolFee = totalFee × protocolFeeBps / 10,000
resolverFee = totalFee × resolverFeeBps / 10,000
evRiskFee   = totalFee × evRiskFeeBps / 10,000
rawSeniorPoolFee = totalFee - creatorFee - protocolFee - resolverFee - evRiskFee   // residual, exhaustive
netShares   = amount - totalFee
```

The same route rules apply as CLOB fees: the senior-pool slice only leaves the market when `SeniorCapitalPool` is compatible with the fee token, and the evRisk slice only leaves the market when `EvRiskStakingRewards` is configured. Otherwise those slices are absorbed into treasury/protocol fee accounting.

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

### EvRisk Staking Rewards

`EvRiskStakingRewards` is separate from juror rewards. It accepts configured fee-token revenue on behalf of the active `EveUSDPool` risk series and distributes it **pro rata by staked active-series `EvRisk` balance**.

- `stake(amount)` only accepts the pool's current active series.
- `notifyReward(token, amount)` routes the reward to treasury instead of accruing it when the active series is not actually `Active`, or when nothing is staked.
- `unstake` and `exit` release the ERC-1155 `EvRisk` stake; accrued rewards remain claimable.
- Rewards are token-by-token and series-by-series. This is not equal-seat accounting.

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

### Native Binary / Multi-Outcome / Combo Redemption

```solidity
nativeBinary.redeemNativeBinary(marketId, outcomeIndex, amount, receiver);
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
    address collateralToken;                // default = eveUSDC
    address eveToken;
    address eveTreasury;
    address seniorCapitalPool;              // senior eveUSDC pool for eligible protocol fee share
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

Core state lives in `LibEveMarket.EveMarketStorage` (slot `eve.prediction.market.storage`). Beyond markets/books/curves/resolutions/metadata, it holds market groups, multi-outcome state (`multiOutcomeMarkets`, labels, displays, position IDs, book IDs), native/combo state (`nativePositionMetadata`, `nativeBinaryConditions`, `comboConditions`, `comboConditionLegs`, `comboMarkets`, `comboBookByPositionKey`), collateral profiles and per-profile side mappings, resolution bond accounting (`resolutionBonded`, `bondedByMarket`), delayed-order storage, and the Diamond's own selector/facet/freeze maps.

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
(uint128 totalFee, uint128 creatorFee, uint128 protocolFee, uint128 vaultFee, uint128 netShares) = previewEntryFee(marketId, amount);
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

### TradeRouterFacet

A Diamond facet wrapping the CLOB engine with convenience buy/sell flows that handle wrapping, approval, and selling in single calls. Buy/split entry points live on `TradeRouterFacet`; the sell entry points live on the companion `TradeRouterSellFacet` (shared internals in `LibTradeRouter`). Both are exposed through the same Diamond and the `ITradeRouter` interface.

```solidity
// Buy (eveUSDC / USDC auto-wrap / arbitrary profile collateral)
FillBestResult memory r = tradeRouter.buyWithEveUSDC(fillBestParams);
FillBestResult memory r = tradeRouter.buyWithUSDC(fillBestParams);     // wraps USDC, refunds residual
FillBestResult memory r = tradeRouter.buyWithCollateral(fillBestParams);

// Sell
SellBestResult memory r = tradeRouter.sellWithEveUSDC(sellParams);
SellBestResult memory r = tradeRouter.sellWithUSDC(sellParams);        // unwraps to USDC
SellBestResult memory r = tradeRouter.sellWithCollateral(sellParams);
SellBestResult memory r = tradeRouter.previewSellBest(sellParams);

// Split with USDC
uint128 sharesMinted = tradeRouter.splitWithUSDC(marketId, usdcAmount, receiver);
```

```solidity
struct SellBestParams {
    bytes32 marketId; bool isYesSide;
    uint128 maxSharesIn; uint128 minCollateralOut;
    uint256[] curveIds; uint32[] expectedGenerations; bytes32[] expectedCommitments;
    address receiver;
}
struct SellBestResult { uint128 sharesSold; uint128 collateralOut; uint128 feePaid; uint128 averagePrice; uint128 unfilledShares; }
```

Selling fills counter-side curves (complement-sell through ask curves or direct-sell into bid curves). All router operations assert zero residual balances.

---

## eveUSDC Collateral Rail & Senior Capital Pool

### Overview

```text
USDC <-> eveUSDC <-> SeniorCapitalPool
WETH <-> eveETH
  ^        ^          ^
  |        |          +-- Senior capital layer
  |        +------------- Trading / settlement layer
  +---------------------- Base external stablecoin
```

- `eveUSDC` — 18-decimal USDC wrapper (minted at `1e12` scale over 6-decimal USDC). Default `config.collateralToken`.
- `eveETH` — 1:1 WETH wrapper (18 decimals), used as alternate collateral via a collateral profile.
- `SeniorCapitalPool` — senior eveUSDC capital pool for eligible protocol revenue, reserved capital, and loss accounting.

### Contracts

| Contract | File | Type |
|---|---|---|
| EveUSDC | `src/EveUSDC.sol` | ERC-20 wrapper (immutable) |
| EveETH | `src/tokens/EveETH.sol` | ERC-20 wrapper (immutable) |
| SeniorCapitalPool | `src/SeniorCapitalPool.sol` | ERC4626-like senior capital pool |

### SeniorCapitalPool

```solidity
function deposit(uint256 assets, address receiver) external returns (uint256 shares);
function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
function notifyRevenue(address token, uint256 amount) external;
function reserveCapital(uint256 amount) external;
function releaseReservedCapital(uint256 amount) external;
function absorbLoss(uint256 amount) external;
```

**NAV model:** `totalAssets()` reflects on-hand eveUSDC plus active accounting adjustments for reserved capital and losses. Deposits mint shares against NAV; redemptions are limited by available capital.

**Fee routing:** orderbook, parimutuel, and parlay protocol fee shares can route to the senior pool only when the pool exists, its `asset()` matches the fee token, and `totalSupply() != 0`. Otherwise the share falls back to treasury.

**Risk-manager boundary:** the Diamond is the configured risk manager in full-stack deployment and is the only caller expected to reserve/release capital or record losses for margin-layer exposure.


---

## eveUSD ETH-Backed Stablecoin

### Overview

`eveUSD` is an ETH-backed, options-style senior stablecoin — a separate subsystem from the eveUSDC trading collateral. A user deposits collateral into the `EveUSDPool` and receives two tokens minted against the same collateral:

- **`eveUSD`** — an 18-decimal ERC-20 **senior** claim, minted at par against the deposit at the pool's collateral ratio. It is the stable leg.
- **`EvRisk`** — an ERC-1155 **junior** risk share, one token ID per *risk series*. It is the volatile leg that absorbs collateral price movement and carries recovery/recapitalization exposure.

Every deposit mints equal amounts of `eveUSD` and `EvRisk` for the current active series (a "pair"). Recombining a full pair (equal `eveUSD` + `EvRisk` of the same series) returns the proportional collateral. The structure behaves like a covered call / collateralized option split: senior holders get downside protection funded by junior holders, and when collateral drops through a recovery trigger the impaired series is frozen and rolled into a fresh series so new deposits are never diluted by legacy risk.

> This is a clean-break ERC-1155 series model: an impaired series can never claim junior equity created by a later series.

### Contracts

| Contract | File | Type | Role |
|---|---|---|---|
| EveUSD | `src/EveUSD.sol` | ERC-20 (18 decimals) | Senior par claim; `mint`/`burn` gated to the pool |
| EveRiskShares (`EvRisk`) | `src/EveRiskShares.sol` | ERC-1155 | Junior risk shares, one ID per series; `mint`/`burn`/batch gated to the pool |
| EveUSDPool | `src/EveUSDPool.sol` | Standalone | Core accounting: profiles, deposit, recombine, recovery lifecycle |
| EveUSDRouter | `src/EveUSDRouter.sol` | Standalone | ETH/WETH deposit + recombine with slippage bounds and residual snapshots |
| ChainlinkETHUSDOracle | `src/ChainlinkETHUSDOracle.sol` | Standalone | ETH/USD price adapter (`ethUsdPriceWad`) |
| EvRiskStakingRewards | `src/EvRiskStakingRewards.sol` | Standalone | Optional fee distributor for staked active-series `EvRisk` |

`EveUSD.pool()` and `EveRiskShares.pool()` must both point at the pool; the pool and router validate these links at construction.

### Pricing & Accounting

All math is WAD (1e18) fixed point; ratios are in bps (`BPS_DENOMINATOR = 10_000`).

```
collateralPerPairWad = (WAD × collateralRatioBps / 10_000) × WAD / priceWad
```

- On deposit, `minted = netCollateral × WAD / series.collateralPerPairWad`, and equal `eveUSD` and `EvRisk` are minted (`sharesMinted == eveUSDMinted`).
- The series is priced from the collateral profile's USD oracle **at series creation**; `collateralPerPairWad` is fixed for the life of the series.
- `collateralRatioBps` (global) = `collateralValueWad × 10_000 / seniorLiabilities`, where `collateralValueWad = accountedCollateral × priceWad / WAD` and `seniorLiabilities = eveUSD.totalSupply()`.
- Direct WETH donations do not inflate share pricing — the pool tracks `accountedCollateral` and per-series `accountedCollateral` rather than raw balances.

### Configuration & Bounds

Owner-set, lockable via `lockConfig()` (irreversible). Constants enforce bounds:

| Parameter | Bounds |
|---|---|
| `collateralRatioBps` (per profile, next series) | `10_001` – `30_000` |
| `recoveryTriggerBps` (per profile, next series) | `1` – `9_999` |
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
  ├─ depositCollateral → mint eveUSD + EvRisk(seriesId)
  ├─ recombine         → burn pair, return proportional collateral
  └─ startRecovery (oracle price ≤ trigger) → RecoveryPending

RecoveryPending
  ├─ returnRiskShares / reclaimReturnedRiskShares   (junior holders opt in/out of migration)
  ├─ cancelRecovery (price recovers above trigger)  → Active
  └─ finalizeRecovery (after timelock, still impaired) → OperatorRecoverable + new Active series

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

`EveUSDRouter` wraps the pool for ETH-native UX and enforces slippage plus strict residual-balance snapshots (WETH, eveUSD, EvRisk-by-series, native ETH) after each call. It implements `IERC1155Receiver`.

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
event NativeBinaryConditionPrepared(bytes32 indexed marketId, bytes32 indexed conditionId, uint256 yesPositionId, uint256 noPositionId);
event NativeBinarySplit(...);  event NativeBinaryMerged(...);  event NativeBinaryRedeemed(...);
event ComboConditionPrepared(bytes32 indexed conditionId, bytes32 indexed legsHash, uint16 legCount, uint256 yesPositionId, uint256 noPositionId, uint256[] legs);
event ComboSplit(...);  event ComboMerged(...);  event ComboWrapped(...);  event ComboUnwrapped(...);
event ComboCompressed(...);  event ComboRedeemed(...);
event ComboSplitOnCondition(...);  event ComboMergedOnCondition(...);
event ComboNoLegExtracted(...);  event ComboNoLegInjected(...);
event ComboNoConvertedToYesBasket(...);  event ComboNoMergedFromYesBasket(...);
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

### eveUSD Stablecoin (EveUSDPool / EveUSDRouter)

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

1. **Conditional / native token backing.** Binary CLOB positions are backed by collateral in the Gnosis CTF; multi-outcome and combinatorial positions are backed by native conditions in `EvesPositionManager`. Redemption reverts if backing is insufficient.
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
12. **Whole-token enforcement.** `splitInventory` requires collateral to be an exact multiple of the position unit; eveUSDC `unwrap` reverts on non-convertible (`% 1e12`) dust.
13. **Curve expiry enforcement.** Expired curves cannot be filled (`createdAt + durationMinutes × 60`).
14. **Top-up volume balance.** `splitAndTopUp` variants enforce equal total YES and NO volume per market batch.
15. **Zero-winning-side protection (parimutuel).** A YES/NO outcome with no shares on the winning side becomes effectively INVALID, preventing division by zero.
16. **Delayed-order MEV resistance.** Orders become executable only after a block delay and must be processed along a committed route hash; `ProtocolOnly` mode restricts processing to registered processors.
17. **Router residual assertions.** `TradeRouterFacet` asserts zero residual balances after router operations. `EveUSDRouter` asserts snapshot-restored balances (WETH, eveUSD, EvRisk-by-series, native ETH) after every operation.
18. **Reentrancy protection.** `SeniorCapitalPool`, Diamond router/mutating facets, and the eveUSD pool/router use reentrancy guards (`nonReentrant` / `LibReentrancy`).
19. **Network-exposed surfaces.** All on/off-ramp mint/burn paths are gated to immutable onramp/offramp addresses (eveUSDC) or require backing transfers (eveETH). `eveUSD` / `EvRisk` mint/burn are gated to the pool (`NotMinter` / `NotBurner` / `NotPool`).
20. **eveUSD oracle safety.** `ChainlinkETHUSDOracle` rejects non-positive, future-dated, stale, and out-of-bounds prices, and honors an optional L2 sequencer-uptime feed with a grace period. The pool re-reads the oracle on every deposit, recovery transition, and recombine preview.
21. **eveUSD series isolation.** Junior risk is series-scoped ERC-1155; an impaired (`OperatorRecoverable`) series can never claim junior equity minted for a later series. `finalizeRecovery` requires the new series to be non-dilutive to the old series' per-pair claim.
22. **eveUSD collateral integrity.** The pool tracks `accountedCollateral` (global and per-series) rather than raw WETH balances, so donations cannot distort share pricing; recombine and recovery burn tokens before transferring WETH.
23. **eveUSD config immutability option.** `lockConfig()` permanently freezes oracle, series, timelock, fee-recipient, and fee-bps changes.


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
makerFee + creatorFee + protocolFee == fee
```

### Property 3: Fee Split Completeness (Parimutuel)
```
totalFee = creatorFee + protocolFee + vaultFee
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

### Property 13: USDC Backing Invariant (eveUSDC)
```
USDC.balanceOf(eveUSDC) × 1e12 >= eveUSDC.totalSupply()
wrap(x) mints x × 1e12; unwrap of a convertible amount returns exactly x USDC
unwrap reverts on non-zero dust (amount % 1e12 != 0)
```

### Property 14: WETH Backing Invariant (eveETH)
```
WETH.balanceOf(eveETH) >= eveETH.totalSupply()
wrap(x) then unwrap(x) returns exactly x WETH
```

### Property 15: Vault Share Fairness
```
Depositors before revenue redeem more than deposited (minus AUM fees)
Depositors after revenue do not receive past yield
AUM fees dilute all stakers proportionally
```

### Property 16: AUM Fee Compounding
```
feeTransferred = totalAssets × (1 - (1 - dailyRate)^epochs), within 1 unit of asset token
lastAccrualTimestamp advances by exactly epochs × epochLength
```

### Property 17: Revenue Notification Invariant
```
notifyRevenue(assets): totalAssets += assets, totalSupply unchanged, exchange rate increases
notifyRevenue(token, amount): accRewardPerShare[token] increases monotonically
```

### Property 18: Managed Assets Accounting
```
totalAssets = onHandEveUSDC + outstandingPrincipal - recognizedLosses
outstandingPrincipal = Σ debtPrincipal over active loans
recognizedLosses only increases (default shortfalls)
```

### Property 19: Max LTV Enforcement
```
debtPrincipal = borrowAmount + originationFee
debtPrincipal ≤ convertToAssets(collateralShares) × maxLtvBps / 10,000, maxLtvBps ≤ 9,500
```

### Property 20: Default Recovery
```
After maturity + grace, anyone may recover; vault.settleDefault redeems seized shares
redeemed ≥ debt → surplus retained in NAV; redeemed < debt → recognizedLosses += shortfall
outstandingPrincipal decreases by debtPrincipal
```

### Property 21: Router Residual Balance
```
∀ successful router operation: router holds zero residual USDC / eveUSDC / position tokens
```

### Property 22: Parimutuel Payout Solvency
```
Σ claimed payouts ≤ payoutPool; claimedPayout monotonically increasing
claimedClaimableShares ≤ totalClaimableSharesAtResolution
```

### Property 23: Zero-Winning-Side Safety
```
Resolved YES with totalYesShares == 0 (or NO with totalNoShares == 0) → effectiveOutcome = Invalid
All participants receive pro-rata refund from payoutPool
```

### Property 24: Epoch Multiplier Solvency
```
payoutPool += netCollateral (not inflated shares)
sharesMinted = netCollateral × multiplierBps / 10,000
The multiplier never creates unbacked obligations; Σ payouts ≤ payoutPool
```

### Property 25: Multi-Outcome Set Conservation
```
splitOutcomeSet mints one token per outcome backed 1:1 by collateral
mergeOutcomeSet burns a full set and releases collateral
Only the resolved outcome (or full set for INVALID) is redeemable post-resolution
```

### Property 26: Combinatorial Position Backing
```
Combo split/merge preserve collateral backing across legs
compressCombo and branch operations are value-preserving transformations of native positions
redeemCombo pays out only when the underlying legs resolve favorably
```

### Property 27: Parlay Escrow Solvency
```
Offers escrow maxPayoutPerUnit × units; ticket payouts are bounded by escrowRemaining
finalize resolves payoutPerUnit from the tier schedule and invalid policy
Σ claimed ≤ escrow reserved at finalization
```

### Property 28: Delayed Order Integrity
```
An order is executable only at/after executableBlock and before expiryBlock
Processing must supply a route whose hash equals the committed routeHash
ProtocolOnly mode restricts processing to registered processors
Unfilled/expired escrow is returned as withdrawable credit
```

### Property 29: Multi-Token Reward Distribution
```
notifyRevenue(token, amount) distributes pro-rata to all stakers
accRewardPerShare[token] increases monotonically; claimRewards returns exactly accrued since last claim
Disabled tokens reject new revenue notifications
```

### Property 30: Book Accounting Consistency
```
Market-linked book and market fee/volume accounting update in lockstep
Standalone books snapshot fee config at creation and accrue independently
```

### Property 30b: Dual-Vault Fee Routing
```
vaultShare is split across primary + secondary staking vaults by each eligible vault's totalSupply
A vault is eligible iff non-zero, token is an active reward token, and totalSupply > 0
primaryAmount + secondaryAmount + treasuryAmount == vaultShare (exhaustive)
If neither vault is eligible, the whole vaultShare falls back to the treasury
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
startRecovery requires oracle price ≤ startPrice × recoveryTriggerBps / 10_000
cancelRecovery requires price restored above the trigger
finalizeRecovery requires block.timestamp ≥ recoveryEndsAt AND price still ≤ trigger
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

**Document Version:** 3.2
**Module:** Eves Market — On-Chain Prediction Market Protocol
