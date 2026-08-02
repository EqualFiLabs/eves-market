# eveUSD — Design Document
## Collateral-Backed Junior / Senior Stablecoin

**Version:** 1.2
**Module:** eveUSD — Options-Style Senior/Junior Tranche

---

## Table of Contents

1. [Overview](#overview)
2. [How It Works](#how-it-works)
3. [Architecture](#architecture)
4. [Tokens](#tokens)
5. [Collateral Profiles](#collateral-profiles)
6. [Risk Series](#risk-series)
7. [Pricing & Accounting](#pricing--accounting)
8. [Deposit — Minting a Pair](#deposit--minting-a-pair)
9. [Recombination — Redeeming a Pair](#recombination--redeeming-a-pair)
10. [Recovery Lifecycle](#recovery-lifecycle)
11. [Insurance Reserve](#insurance-reserve)
12. [Oracle](#oracle)
13. [Router](#router)
14. [Configuration & Governance](#configuration--governance)
15. [View & Preview Functions](#view--preview-functions)
16. [Data Models](#data-models)
17. [Events](#events)
18. [Security Considerations](#security-considerations)
19. [Appendix: Correctness Properties](#appendix-correctness-properties)

---

## Overview

**eveUSD** is a collateral-backed, options-style stablecoin. A user deposits volatile collateral (canonically WETH) into the `EveUSDPool` and receives two tokens minted against the same deposit:

- **`eveUSD`** — an 18-decimal ERC-20 **senior** claim. It is the stable leg, minted at par against the deposit at the pool's configured collateral ratio.
- **`EvRisk`** — an ERC-1155 **junior** risk share, with one token ID per *risk series*. It is the volatile leg that absorbs collateral price movement and carries recovery / recapitalization exposure.

Every deposit mints an equal amount of `eveUSD` and `EvRisk` for the active series — a **pair**. Holding both legs of a pair is equivalent to holding the underlying collateral; recombining a full pair returns the proportional collateral. The split behaves like a collateralized option structure: senior holders get downside protection funded by junior holders, and when collateral falls through a recovery trigger the impaired series is frozen and rolled into a fresh series so new deposits are never diluted by legacy risk.

> This is a clean-break ERC-1155 series model: an impaired series can never claim junior equity created by a later series.

> **Naming note:** `eveUSD` (this document) is distinct from **eveUSDC**, the USDC-backed 1:1 trading-collateral wrapper used inside Eves Market. `eveUSD` is a senior tranche over volatile collateral. Do not confuse the two.

### Key Characteristics

| Feature | Description |
|---|---|
| **Two-token split** | Each deposit mints equal `eveUSD` (senior) + `EvRisk` (junior series share) |
| **Senior par claim** | `eveUSD` is minted at par against the deposit at the pool collateral ratio |
| **Junior volatility leg** | `EvRisk` absorbs collateral price movement and recovery exposure |
| **Series model** | One `EvRisk` ID per risk series; impaired series roll cleanly into successors |
| **Collateral profiles** | Multiple collateral tokens (WETH and others ≤ 18 decimals) each with independent config |
| **Overcollateralized** | Collateral ratio bounded to `10_001`–`30_000` bps (100.01%–300%) |
| **Recovery trigger** | Price-driven trigger freezes an impaired series and recapitalizes into a new one |
| **Insurance reserve** | Optional per-profile reserve that backstops senior shortfalls at finalization |
| **Oracle-priced** | Chainlink-style USD price adapter (`priceWad`) with staleness, bounds, sequencer checks |
| **Standalone** | Operates outside the Eves Market Diamond; current direct integration is via `EvRiskStakingRewards` |
| **Restricted mint/burn** | Only the pool can mint/burn `eveUSD` and `EvRisk` |
| **Lockable config** | Owner controls are bounded and can be permanently frozen via `lockConfig()` |

### System Participants

| Role | Description |
|---|---|
| **Depositor** | Deposits collateral, receives a senior + junior pair |
| **Senior Holder** | Holds `eveUSD` — a par-denominated senior claim on pooled collateral |
| **Junior Holder** | Holds `EvRisk` series shares — absorbs price volatility and recovery exposure |
| **Recombiner** | Burns a full pair to withdraw proportional collateral |
| **Recovery Caller** | Permissionlessly starts / cancels / finalizes recovery based on oracle price |
| **Operator** | Sweeps straggler junior holders from a retired series into its successor |
| **Owner** | Configures profiles, fees, timelock, and oracle within hard bounds; can lock config |

---

## How It Works

### The Core Model

The pool follows a deposit → hold → redeem lifecycle, with a recovery lifecycle layered on top of the junior leg:

1. **Deposit** — A depositor sends collateral to the pool. The pool reads the collateral's USD price, computes how many pairs the net collateral buys at the series' fixed per-pair cost, and mints equal `eveUSD` and `EvRisk` of the active series.

2. **Hold** — `eveUSD` behaves as a stable senior claim; `EvRisk` behaves as the volatile junior leg. As the collateral price moves, the junior equity (collateral value minus senior liabilities) expands or contracts. The senior claim is insulated until junior equity is exhausted.

3. **Recombine** — Any holder of a full pair (equal `eveUSD` + `EvRisk` of the same series) can burn both legs and withdraw the proportional collateral, less a recombination fee.

4. **Recover** — If the collateral price falls to a series' recovery trigger, anyone can start recovery. After a timelock (if the price is still impaired) the series is finalized: it is frozen, an insurance draw covers any senior shortfall, and a fresh series is opened at the current price. Junior holders migrate their residual value into the new series.

### Why Split Senior and Junior

Splitting a volatile deposit into a stable senior claim and a volatile junior share lets each holder choose their exposure:

- **Senior (`eveUSD`)** wants price stability. It is overcollateralized and protected by junior equity, so moderate collateral drawdowns do not impair it.
- **Junior (`EvRisk`)** wants leveraged upside and accepts downside. It captures collateral appreciation above the senior claim and absorbs depreciation first.

The recovery mechanism ensures that when junior equity is nearly exhausted, the system recapitalizes cleanly rather than letting the senior claim silently break.

---

## Architecture

### Contract Structure

```
eve-predict/src/
├── EveUSD.sol                     # Senior claim (ERC-20, 18 decimals, pool-minted)
├── EveRiskShares.sol              # Junior risk shares (ERC-1155 per series, pool-minted)
├── EveUSDPool.sol                 # Core accounting: profiles, deposit, recombine, recovery, insurance
├── EveUSDRouter.sol               # ETH/WETH-native deposit + recombine with slippage & residual guards
├── EvRiskStakingRewards.sol       # Optional fee distributor for staked active-series EvRisk
├── ChainlinkETHUSDOracle.sol      # USD price adapter (priceWad) with safety checks
├── interfaces/
│   ├── IEveUSD.sol                # Senior token interface (restricted mint/burn, pool view)
│   ├── IEveRiskShares.sol         # Junior share interface (restricted mint/burn/batch, pool view)
│   ├── IEveUSDPool.sol            # Pool interface: structs, enums, errors, events, functions
│   ├── IEveUSDRouter.sol          # Router interface
│   ├── IUsdOracle.sol             # Minimal priceWad() oracle interface consumed by the pool
│   ├── IETHUSDOracle.sol          # ETH/USD oracle adapter interface
│   └── IWETH9.sol                 # WETH deposit/withdraw interface
└── mocks/
    └── MockETHUSDOracle.sol       # Settable price oracle for tests
```

`EveUSD.pool()` and `EveRiskShares.pool()` must both point at the pool; the pool validates these links at construction (`InvalidTokenPool` otherwise), and the router re-validates the full wiring.

### Standalone by Design

eveUSD operates entirely outside the Eves Market Diamond. It has its own owner, its own storage, and its own token contracts. In the current codebase, prediction markets still default to `eveUSDC` as their trading collateral; the direct eveUSD-side integration that exists today is `EvRiskStakingRewards`, which can receive configured market fees and distribute them to staked active-series `EvRisk`. Nothing in the pool depends on Diamond internals.

Markets could also register `eveUSD` as a collateral profile through the broader market-collateral system, but that is optional configuration rather than the default deployment path.

---

## Tokens

### eveUSD (senior)

`EveUSD` is a minimal ERC-20:

```solidity
contract EveUSD is ERC20, IEveUSD {           // name "eveUSD", symbol "eveUSD"
    address public immutable pool;
    function decimals() public pure returns (uint8);      // 18
    function mint(address to, uint256 amount) external;   // pool-only, reverts NotMinter otherwise
    function burn(address from, uint256 amount) external; // pool-only, reverts NotBurner otherwise
}
```

- 18 decimals.
- `mint` / `burn` are restricted to the immutable `pool` address; there is no other supply control.
- No blacklist, no pause, no arbitrary seizure, no owner withdrawal. Transfers are unrestricted ERC-20.

### EvRisk (junior)

`EveRiskShares` is an ERC-1155 where **each token ID is a risk series**:

```solidity
contract EveRiskShares is ERC1155, IEveRiskShares {   // name "EvRisk", symbol "EVRISK"
    address public immutable pool;
    function mint(address to, uint256 id, uint256 amount) external;       // pool-only
    function burn(address from, uint256 id, uint256 amount) external;     // pool-only
    function batchMint(address to, uint256[] ids, uint256[] amounts) external;  // pool-only
    function batchBurn(address from, uint256[] ids, uint256[] amounts) external; // pool-only
}
```

- `mint` / `burn` / `batchMint` / `batchBurn` are gated to the pool (`NotPool` otherwise).
- Transfers are unrestricted ERC-1155, so junior shares are freely tradeable per series.
- The series ID returned by a deposit is the ERC-1155 token ID a junior holder owns.

### EvRisk Staking Rewards

`EvRiskStakingRewards` is an optional companion distributor that bridges market-fee routing back to the active junior series:

```solidity
contract EvRiskStakingRewards is ERC1155Holder {
    address public immutable evRisk;
    address public immutable eveUSDPool;
    uint256 public immutable primaryProfileId;

    function stake(uint256 amount) external returns (uint256 seriesId);
    function unstake(uint256 seriesId, uint256 amount) external;
    function notifyReward(address token, uint256 amount) external;
    function claim(uint256 seriesId, address token) external returns (uint256 amount);
}
```

- Only the current active series for `primaryProfileId` can be newly staked.
- Rewards are distributed pro rata by staked `EvRisk` balance, per token and per series.
- If the current series is not actually `Active`, or no one is staked, incoming rewards are routed to treasury instead of accruing.
- The distributor is separate from the pool's accounting; it reads the pool only to discover and validate the active series.

---

## Collateral Profiles

The pool supports multiple collateral tokens through **collateral profiles**. Profile `1` (`firstCollateralProfileId`) is created in the constructor — canonically the WETH profile. The owner can register additional profiles for other collateral tokens (any ERC-20 with ≤ 18 decimals).

Each profile carries its own oracle, collateral ratio, recovery trigger, fee rates, insurance parameters, active series pointer, and accounting totals.

```solidity
struct StableCollateralProfile {
    address collateralToken;
    address oracle;
    uint8   decimals;              // collateral token decimals, ≤ 18
    uint16  collateralRatioBps;    // next-series mint ratio, 10_001–30_000
    uint16  recoveryTriggerBps;    // next-series trigger, 1–9_999 (fraction of series start price)
    uint16  mintFeeBps;            // ≤ 1_000 (10%)
    uint16  recombinationFeeBps;   // ≤ 1_000 (10%)
    uint16  insuranceTargetBps;    // ≤ 10_000
    uint16  insuranceFeeBps;       // ≤ 10_000
    bool    enabled;
    uint256 activeSeriesId;
    uint256 accountedCollateral;   // pair collateral tracked for the profile (excludes insurance reserve)
    uint256 insuranceReserve;
    uint256 seniorOutstanding;     // eveUSD attributable to this profile
}
```

Registration and configuration:

```solidity
(uint256 profileId, uint256 seriesId) = pool.createCollateralProfile(
    collateralToken, oracle, collateralRatioBps, recoveryTriggerBps,
    mintFeeBps, recombinationFeeBps, enabled
);
pool.setCollateralProfileConfig(profileId, newCollateralRatioBps, newRecoveryTriggerBps, enabled);
pool.setCollateralProfileFeeBps(profileId, newMintFeeBps, newRecombinationFeeBps);
pool.setCollateralProfileInsuranceBps(profileId, newInsuranceTargetBps, newInsuranceFeeBps);
pool.setCollateralProfileOracle(profileId, newOracle);
```

Collateral amounts are normalized to WAD (1e18) internally so a profile can use a collateral token with fewer than 18 decimals without corrupting pair math. Direct token donations do not inflate share pricing — the pool tracks `accountedCollateral` per profile and per series rather than raw balances.

---

## Risk Series

A **risk series** is a generation of the junior/senior split under a single collateral profile. Each series pins the collateral price at creation and derives a fixed per-pair collateral cost from it, so all deposits into the same series mint pairs at the same rate.

```solidity
struct RiskSeries {
    uint256 profileId;
    address collateralToken;
    uint256 seniorOutstanding;        // eveUSD minted for this series
    uint256 riskSharesOutstanding;    // EvRisk currently held by users
    uint256 returnedSharesSupply;     // EvRisk returned by holders opting into migration
    uint256 accountedCollateral;      // pair collateral backing this series
    uint256 startPriceWad;            // oracle price at series creation
    uint256 collateralPerPairWad;     // fixed collateral cost of one pair
    uint256 collateralRatioBps;
    uint256 recoveryTriggerBps;
    uint256 startedAt;
    uint256 recoveryStartedAt;
    uint256 recoveryEndsAt;
    uint256 finalizedAt;
    uint256 successorSeriesId;
    SeriesStatus status;
}
```

```solidity
enum SeriesStatus { None, Active, RecoveryPending, RecoveryFinalized, OperatorRecoverable, Retired }
```

Only the profile's `activeSeriesId` accepts new deposits, and only when its status is `Active`. When a series is finalized, a fresh `Active` series becomes the profile's active series and the old series moves directly to `OperatorRecoverable` for junior migration.

---

## Pricing & Accounting

All math is WAD (1e18) fixed point; ratios are in basis points (`BPS_DENOMINATOR = 10_000`).

**Per-pair collateral cost** (fixed at series creation from the oracle price and the profile's collateral ratio):

```
collateralPerPairWad = (WAD × collateralRatioBps / 10_000) × WAD / priceWad
```

**Pairs minted on deposit** (net of fee and insurance contribution, normalized to WAD):

```
eveUSDMinted = netPairCollateralWad × WAD / collateralPerPairWad
sharesMinted = eveUSDMinted                                  // always equal
```

**Global / profile / series health:**

```
collateralValueWad   = accountedCollateral(normalized to WAD) × priceWad / WAD
seniorLiabilities    = eveUSD.totalSupply()                  // global
collateralRatioBps   = collateralValueWad × 10_000 / liabilities
```

Because the per-pair cost is fixed for the life of a series, the *senior* claim stays at par while the *junior* residual (collateral value minus the senior reserve) breathes with the collateral price. When the price rises, junior equity grows; when it falls, junior equity shrinks first, protecting senior holders until the recovery trigger.

---

## Deposit — Minting a Pair

```solidity
(uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
    pool.depositCollateral(profileId, collateralAmount, eveUSDReceiver, shareReceiver);
```

Flow:

1. Preview the deposit (`previewDeposit`) to compute fee, insurance contribution, pairs minted, and the post-deposit collateral ratio. The active series must be `Active` and the price must be above the recovery trigger (`RecoveryRequired` otherwise).
2. Pull `collateralAmount` exactly (balance-delta checked; `InvalidCollateralAmount` on mismatch — safe against fee-on-transfer surprises).
3. Deduct the mint fee (sent to `feeRecipient`) and any insurance contribution.
4. Mint equal `eveUSD` to `eveUSDReceiver` and `EvRisk(seriesId)` to `shareReceiver`.

Senior and junior receivers can differ, so a depositor can route the stable leg and the volatile leg to different addresses in one call.

---

## Recombination — Redeeming a Pair

```solidity
uint256 collateralOut = pool.recombine(seriesId, eveUSDAmount, shareAmount, receiver);
```

Recombination burns a **full pair** and returns proportional collateral:

- The required share amount always equals the eveUSD amount (`requiredSharesForRecombine(seriesId, x) == x`); the caller passes `shareAmount` explicitly and it must match (`InvalidShareAmount` otherwise).
- Gross collateral out is proportional to the series' accounted collateral: `grossOut = accountedCollateral × eveUSDAmount / seniorOutstanding`.
- A recombination fee is deducted and sent to `feeRecipient`; the remainder goes to `receiver`.
- Recombination is allowed while the series is `Active`, `RecoveryPending`, or `OperatorRecoverable`.

Because recombination is pro-rata on the series' collateral, it is the deterministic, symmetric inverse of depositing — there is no first-mover advantage within a series.

---

## Recovery Lifecycle

Recovery protects the senior claim when a series' collateral price falls to its trigger. The trigger price is `startPriceWad × recoveryTriggerBps / 10_000`.

```
Active
  ├─ depositCollateral → mint eveUSD + EvRisk(seriesId)
  ├─ recombine         → burn pair, return proportional collateral
  └─ startRecovery (price ≤ trigger) → RecoveryPending

RecoveryPending
  ├─ returnRiskShares / reclaimReturnedRiskShares   (junior holders opt in / out of migration)
  ├─ recombine                                       (still allowed)
  ├─ cancelRecovery (price recovers above trigger)   → Active
  └─ finalizeRecovery (after timelock, still impaired) → OperatorRecoverable + new Active series

OperatorRecoverable (old series)
  ├─ recombine                                       (still allowed)
  ├─ claimRecoveredRiskShares    (returned holders migrate into the successor series)
  └─ recoverExpiredRisk          (operator sweeps stragglers into the successor series)
```

```solidity
pool.startRecovery(seriesId);                                       // price ≤ trigger, permissionless
pool.returnRiskShares(seriesId, shares);                            // opt into migration (burns EvRisk into a claim)
uint256 shares = pool.reclaimReturnedRiskShares(seriesId, receiver);// opt back out (while Active/RecoveryPending)
pool.cancelRecovery(seriesId);                                      // price restored above trigger
uint256 newSeriesId = pool.finalizeRecovery(seriesId);             // after timelock, still impaired
```

**Finalization** (`finalizeRecovery`) is the pivot:

1. Requires `RecoveryPending`, the timelock elapsed (`recoveryEndsAt`), and the price still at or below the trigger (`RecoveryRestored` otherwise).
2. Draws from the profile insurance reserve to cover any senior shortfall (see [Insurance Reserve](#insurance-reserve); reverts `InsuranceInsufficient` if the reserve cannot cover it).
3. Opens a fresh `Active` series priced at the current oracle price and points the profile's `activeSeriesId` at it.
4. Moves the old series to `OperatorRecoverable`, recording the successor series ID.

### Junior Migration Claim Modes

After finalization, junior holders migrate their residual value from the old series into the successor:

```solidity
enum RecoveryClaimMode { CollateralDifference, MorePairs }
```

Let `oldClaimCollateral` be the returned shares' pro-rata slice of the old series' collateral, and `baseNewClaimCollateral` the collateral needed to mint the same share count in the new series:

- **`CollateralDifference`** — if the holder's junior residual covers the base new claim, mint the same number of new-series shares and pay the surplus collateral out; otherwise mint as many new-series pairs as the residual affords.
- **`MorePairs`** — roll the full junior residual into the new series, minting the maximum pairs (senior + junior) it supports.

Migration entry points:

```solidity
// Holders who returned shares during RecoveryPending
(uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOut) =
    pool.claimRecoveredRiskShares(oldSeriesId, receiver, mode);

// Operator sweeps stragglers who still hold old-series EvRisk (MorePairs semantics)
(uint256 newSeriesId, uint256 sharesMinted, uint256 eveUSDMinted) =
    pool.recoverExpiredRisk(holder, oldSeriesId, shares);
```

Migration is non-dilutive to the successor series: new-series pairs are minted at the successor's fixed per-pair cost, and the old series can never draw on collateral created by a later series.

---

## Insurance Reserve

Each profile can maintain an optional **insurance reserve** in the collateral token, controlled by two parameters:

- `insuranceTargetBps` — the reserve target as a fraction of senior outstanding.
- `insuranceFeeBps` — the per-pair contribution skimmed from deposits until the target is met.

Behavior:

- On deposit, `_depositInsuranceContribution` computes how much of the net collateral to divert to the reserve. Contributions stop once the reserve reaches its target and resume if the target grows. If both bps are zero, no insurance is taken.
- Anyone can top up a reserve directly with `topUpInsurance(profileId, amount)`.
- At `finalizeRecovery`, if the impaired series' accounted collateral is below the senior reserve requirement, the shortfall is drawn from the profile insurance reserve so senior claims stay whole. If the reserve cannot cover the shortfall, finalization reverts (`InsuranceInsufficient`).

Reserve collateral is tracked separately from pair collateral, so it never inflates pair pricing or recombination payouts.

Views:

```solidity
uint256 reserve  = pool.insuranceReserve(profileId);
uint256 target   = pool.insuranceTarget(profileId);
uint256 deficit  = pool.insuranceDeficit(profileId);
```

---

## Oracle

The pool consumes a minimal price interface:

```solidity
interface IUsdOracle {
    function priceWad() external view returns (uint256 priceWad);   // USD price of 1 collateral unit, WAD
}
```

`ChainlinkETHUSDOracle` adapts a Chainlink aggregator to `priceWad()` / `ethUsdPriceWad()` and enforces:

- Positive answer, non-zero and non-future `updatedAt`, `answeredInRound ≥ roundId` (`InvalidPrice` otherwise).
- Staleness: `block.timestamp − updatedAt ≤ maxStaleness` (`StalePrice` otherwise).
- Optional price bounds `minPriceWad` / `maxPriceWad` (exclusive; `PriceOutOfBounds` otherwise).
- Optional L2 sequencer-uptime feed with a grace period (`SequencerDown` / `SequencerGracePeriodActive`).
- Feed decimals ≤ 18, scaled up to WAD (`UnsupportedFeedDecimals` otherwise).

`MockETHUSDOracle` provides a settable price and configurable failure modes for tests. Every price-sensitive path (deposit, recovery start/cancel/finalize) reads the live oracle, so a stale or invalid feed safely blocks minting and recovery transitions rather than pricing off bad data.

---

## Router

`EveUSDRouter` wraps the pool for ETH-native UX and enforces slippage bounds plus strict residual-balance snapshots. It implements `IERC1155Receiver` so it can hold `EvRisk` mid-transaction, and it rejects recombination previews that do not point at its immutable `wethProfileId`.

```solidity
(uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
    router.depositETH{value: x}(eveUSDReceiver, shareReceiver, minEveUSD, minShares);
(uint256 seriesId, uint256 eveUSDMinted, uint256 sharesMinted) =
    router.depositWETH(wethAmount, eveUSDReceiver, shareReceiver, minEveUSD, minShares);
uint256 wethOut = router.recombineToWETH(seriesId, eveUSDAmount, maxSharesIn, receiver, minWETHOut);
uint256 ethOut  = router.recombineToETH(seriesId, eveUSDAmount, maxSharesIn, receiver, minETHOut);
```

- `depositETH` wraps native ETH to WETH, approves the pool for the exact amount, deposits, then re-zeroes the approval.
- Deposit and recombine calls enforce `minEveUSD` / `minShares` / `minWETHOut` / `minETHOut` (`OutputBelowMinimum`) and a `maxSharesIn` ceiling on recombination (`SharesAboveMaximum`).
- The router asserts that its own WETH, `eveUSD`, per-series `EvRisk`, and native balances return to their pre-call snapshot after every operation (`ResidualRouterBalance` and related errors), guaranteeing it never traps or leaks funds.
- The router binds to a single WETH collateral profile at construction and re-validates the entire pool/token wiring, so it cannot be pointed at a mismatched deployment.

---

## Configuration & Governance

All owner controls are bounded by constants and revert outside their range. They can be permanently frozen with `lockConfig()` (irreversible; guarded by `whenConfigUnlocked`).

| Parameter | Bounds |
|---|---|
| `collateralRatioBps` (per profile, next series) | `10_001` – `30_000` |
| `recoveryTriggerBps` (per profile, next series) | `1` – `9_999` |
| `recoveryTimelock` (global) | `1 day` – `30 days` (default `7 days`) |
| `mintFeeBps` / `recombinationFeeBps` (per profile) | ≤ `1_000` (10%) |
| `insuranceTargetBps` / `insuranceFeeBps` (per profile) | ≤ `10_000` |
| collateral token decimals | ≤ `18` |

Owner functions: `createCollateralProfile`, `setCollateralProfileConfig`, `setCollateralProfileFeeBps`, `setCollateralProfileInsuranceBps`, `setCollateralProfileOracle`, `setRecoveryTimelock`, `setFeeRecipient`, `transferOwnership`, `lockConfig`. Fees are taken in the collateral token and sent to `feeRecipient`.

**Excluded by design** — the owner cannot arbitrarily withdraw collateral, seize user tokens, or mint out-of-ratio `eveUSD`. The only mint/burn authority for the tokens is the pool, exercised through the bounded deposit/recombine/recovery paths.

---

## View & Preview Functions

```solidity
// Previews (mirror the exact accounting of their state-changing counterparts)
DepositPreview           memory p = pool.previewDeposit(profileId, collateralAmount);
RedemptionPreview        memory p = pool.previewRecombine(seriesId, eveUSDAmount);
uint256 shares                    = pool.requiredSharesForRecombine(seriesId, eveUSDAmount); // == eveUSDAmount
OperatorRecoveryPreview  memory p = pool.previewOperatorRecovery(holder, oldSeriesId, shares);
RecoveredRiskClaimPreview memory p = pool.previewRecoveredRiskClaim(account, oldSeriesId, mode);

// State
StableCollateralProfile memory profile = pool.collateralProfile(profileId);
RiskSeries              memory series  = pool.riskSeries(seriesId);
uint256 shares      = pool.returnedShares(seriesId, account);

// Health
uint256 collateral  = pool.totalCollateral(collateralToken);
uint256 usdValueWad = pool.seriesCollateralValueWad(seriesId);
uint256 ratioBps    = pool.seriesCollateralRatioBps(seriesId);
uint256 priceWad    = pool.collateralUsdPriceWad(profileId);
uint256 liabilities = pool.seniorLiabilities();             // eveUSD total supply
uint256 pLiab       = pool.profileSeniorLiabilities(profileId);
uint256 reserve     = pool.insuranceReserve(profileId);
uint256 target      = pool.insuranceTarget(profileId);
uint256 deficit     = pool.insuranceDeficit(profileId);
```

Previews are the authoritative UX surface: they read the live oracle and reproduce fee, insurance, and rounding rules exactly, so a caller can size deposits/redemptions and set slippage minimums without simulating the mutation.

---

## Data Models

### Enums

```solidity
enum SeriesStatus     { None, Active, RecoveryPending, RecoveryFinalized, OperatorRecoverable, Retired }
enum RecoveryClaimMode { CollateralDifference, MorePairs }
```

### Structs

- `StableCollateralProfile` — per-collateral configuration and running totals (see [Collateral Profiles](#collateral-profiles)).
- `RiskSeries` — a single junior/senior generation (see [Risk Series](#risk-series)).
- `DepositPreview` — `{ profileId, seriesId, collateralIn, eveUSDMinted, sharesMinted, feeAmount, insuranceContribution, priceWad, collateralPerPairWad, collateralRatioBpsAfter }`.
- `RedemptionPreview` — `{ profileId, seriesId, collateralToken, eveUSDBurned, sharesBurned, collateralOut, feeAmount, priceWad, collateralRatioBpsAfter }`.
- `OperatorRecoveryPreview` — `{ oldSeriesId, newSeriesId, sharesBurned, sharesMinted, collateralMoved, eveUSDMinted }`.
- `RecoveredRiskClaimPreview` — full migration breakdown including `oldClaimCollateral`, `baseNewClaimCollateral`, `seniorReserveCollateral`, `juniorResidualCollateral`, `seniorShortfallCollateral`, `surplusCollateral`, `collateralMoved`, `sharesMinted`, `eveUSDMinted`, `collateralOut`, `mode`.

### Key Constants

```solidity
WAD                      = 1e18;
BPS_DENOMINATOR          = 10_000;
MAX_FEE_BPS              = 1_000;
MAX_INSURANCE_BPS        = 10_000;
MIN_COLLATERAL_RATIO_BPS = 10_001;
MAX_COLLATERAL_RATIO_BPS = 30_000;
MIN_RECOVERY_TRIGGER_BPS = 1;
MAX_RECOVERY_TRIGGER_BPS = 9_999;
MIN_RECOVERY_TIMELOCK    = 1 days;
MAX_RECOVERY_TIMELOCK    = 30 days;
```

---

## Events

### Pool Lifecycle

```solidity
event Deposited(address indexed caller, address indexed eveUSDReceiver, address indexed shareReceiver,
    uint256 profileId, uint256 seriesId, uint256 collateralAmount, uint256 eveUSDMinted,
    uint256 sharesMinted, uint256 priceWad, uint256 collateralPerPairWad);
event Recombined(address indexed caller, address indexed receiver, uint256 indexed seriesId,
    uint256 eveUSDBurned, uint256 sharesBurned, address collateralToken, uint256 collateralOut,
    uint256 collateralRatioBpsAfter);
```

### Recovery

```solidity
event RecoveryStarted(uint256 indexed profileId, uint256 indexed seriesId, uint256 recoveryEndsAt, uint256 priceWad);
event RiskSharesReturned(address indexed account, uint256 indexed seriesId, uint256 shares);
event ReturnedRiskSharesReclaimed(address indexed account, uint256 indexed seriesId, uint256 shares);
event RecoveryCancelled(uint256 indexed profileId, uint256 indexed seriesId);
event RecoveryFinalized(uint256 indexed profileId, uint256 indexed oldSeriesId, uint256 indexed newSeriesId, uint256 priceWad);
event RecoveredRiskSharesClaimed(address indexed account, uint256 indexed oldSeriesId, uint256 indexed newSeriesId,
    RecoveryClaimMode mode, uint256 returnedShares, uint256 sharesMinted, uint256 eveUSDMinted, uint256 collateralOut);
event ExpiredRiskRecovered(address indexed operator, address indexed holder, uint256 indexed oldSeriesId,
    uint256 newSeriesId, uint256 sharesBurned, uint256 sharesMinted, uint256 eveUSDMinted);
```

### Profiles, Insurance & Config

```solidity
event CollateralProfileCreated(uint256 indexed profileId, address indexed collateralToken, address indexed oracle, uint8 decimals, uint256 activeSeriesId);
event CollateralProfileConfigured(uint256 indexed profileId, uint256 collateralRatioBps, uint256 recoveryTriggerBps, bool enabled);
event CollateralProfileOracleSet(uint256 indexed profileId, address indexed oracle);
event CollateralProfileFeeBpsSet(uint256 indexed profileId, uint256 mintFeeBps, uint256 recombinationFeeBps);
event CollateralProfileInsuranceBpsSet(uint256 indexed profileId, uint256 targetBps, uint256 feeBps);
event InsuranceContributed(address indexed payer, uint256 indexed profileId, address indexed collateralToken, uint256 amount);
event InsuranceToppedUp(address indexed payer, uint256 indexed profileId, address indexed collateralToken, uint256 amount);
event InsuranceDrawn(uint256 indexed profileId, uint256 indexed seriesId, address indexed collateralToken, uint256 amount);
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
event ConfigLockedForever(address indexed owner);
event RecoveryTimelockSet(uint256 recoveryTimelock);
event FeeRecipientSet(address indexed feeRecipient);
event FeeCollected(address indexed payer, address indexed recipient, address indexed collateralToken, uint256 amount);
```

### Router

```solidity
event ETHDeposited(address indexed caller, address indexed eveUSDReceiver, address indexed shareReceiver,
    uint256 profileId, uint256 seriesId, uint256 wethAmount, uint256 eveUSDMinted, uint256 sharesMinted);
event WETHDeposited(...);           // same shape as ETHDeposited
event RecombinedToWETH(address indexed caller, address indexed receiver, uint256 indexed seriesId,
    uint256 eveUSDAmount, uint256 sharesBurned, uint256 wethOut);
event RecombinedToETH(...);         // same shape, native ETH out
```

---

## Security Considerations

### Reentrancy
The pool and router entry points are `nonReentrant`. External token transfers (collateral pulls, fee payouts, redemptions) sit behind the guard, and state is updated before minting/burning.

### Restricted Mint/Burn
Only the pool can mint or burn `eveUSD` and `EvRisk`. The pool validates at construction that both tokens point back at it (`InvalidTokenPool`), and the router re-validates the whole wiring, so a misconfigured deployment fails fast.

### Oracle Discipline
Every price-sensitive path reads the live oracle. Stale, non-positive, out-of-bounds, or sequencer-down prices revert, blocking minting and recovery transitions rather than acting on bad data. Series pin their price at creation, so in-flight deposits price consistently.

### Donation Resistance
The pool tracks `accountedCollateral` per profile and per series instead of raw balances, and `depositCollateral` verifies the exact received amount (`InvalidCollateralAmount`). Direct token donations cannot inflate pair pricing or recombination payouts.

### Senior Protection & Clean-Break Series
Junior equity absorbs price drops first. When a series is impaired past its trigger, finalization freezes it, draws insurance to cover any senior shortfall, and opens a fresh series. An impaired series can never claim collateral or junior equity created by a later series, so new depositors are not diluted by legacy losses.

### No First-Exit Advantage
Recombination is strictly pro-rata on a series' accounted collateral, and junior migration is priced at the successor series' fixed per-pair cost with a non-dilution check. There is no advantage to exiting first within a series or to migrating first after finalization.

### Bounded, Lockable Governance
All owner parameters are range-checked constants, and the owner has no power to withdraw collateral, seize tokens, or mint out of ratio. `lockConfig()` can permanently freeze all configuration.

### Router Residual Guards
The router snapshots and asserts restoration of its WETH, `eveUSD`, per-series `EvRisk`, and native balances around every call, guaranteeing it neither traps nor leaks user funds.

---

## Appendix: Correctness Properties

The following properties are covered by the property/invariant and launch-level suites:

- **No unbacked senior mint** — every `eveUSD` minted is backed by pair collateral at ≥ the series collateral ratio; the post-mint ratio is enforced.
- **Pair equality** — each deposit mints `eveUSDMinted == sharesMinted`; a full pair recombines to proportional collateral.
- **Junior-first downside** — as the collateral price falls, junior equity decreases before any senior haircut; a wipeout impairs junior fully before touching senior.
- **Deterministic recombination** — recombination is pro-rata and fractional recombination preserves accounting; `requiredSharesForRecombine == eveUSDAmount`.
- **Recovery correctness** — `startRecovery` only at/below trigger, `cancelRecovery` only above trigger, `finalizeRecovery` only after timelock while still impaired; insurance covers senior shortfall or the finalize reverts.
- **Non-dilutive migration** — junior migration into a successor series mints at the successor's per-pair cost and never dilutes it; `previewOperatorRecovery` matches `recoverExpiredRisk`.
- **Oracle failure safety** — stale, zero/negative, out-of-bounds, or sequencer-down prices revert on every price-sensitive path.
- **Rounding & dust** — tiny deposits/redemptions and near-empty series preserve accounting without value leakage; ceil-rounding favors the pool on senior-reserve and insurance math.
- **Preview fidelity** — `previewDeposit` / `previewRecombine` / `previewRecoveredRiskClaim` match their state-changing counterparts within documented rounding rules.
