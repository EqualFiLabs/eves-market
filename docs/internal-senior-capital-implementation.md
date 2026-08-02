# Internal Senior Capital Implementation

**Status:** Implemented in source and covered by focused deployment, lifecycle,
fee-routing, router, and invariant regressions.

## Objective

Replace the external, transferable-share `SeniorCapitalPool` with a
non-composable Senior-capital subsystem inside `EveMarketDiamond`.

The design shares Statics' useful indexed-position accounting shape:
explicit stored units and a cumulative fee index. It does not infer liabilities
from `IERC20.balanceOf`, mint a Senior ERC-20/ERC-4626 share, or depend on an
owner-configurable external risk manager.

## Final Architecture

| Surface | Responsibility |
|---|---|
| `SeniorCapitalFacet` | Deposit, pending withdrawal, activation, exits, fee claims, and donations |
| `SeniorCapitalViewFacet` | Aggregate state, account state, exit state, bucket state, and pending fees |
| `LibSeniorCapital` | Namespaced storage, stored-unit scaling, fee index, FIFO queue, MLO reserve/deploy/repay/loss accounting |
| `LibFeeRouting` | Decide whether a configured fee share accrues to Senior or falls back to treasury |
| MLO libraries | Mutate internal bucket reservations/exposure directly; no token transfer to an external pool |

The storage slot is independent from `LibEveMarket` and the other Diamond
subsystems. The configured `marginAsset` is the Senior asset and is expected to
be Statics Dollar at launch.

## Provider Lifecycle

1. `depositSeniorCapital(assets)` transfers the margin asset to the Diamond and
   records the measured balance delta as pending principal.
2. Pending principal is not risk-bearing and earns no indexed fees. It may be
   removed through `withdrawPendingSeniorCapital`.
3. `activateSeniorCapital()` becomes available after a 24-hour weighted-age
   gate and converts pending principal into non-transferable stored units at the
   current epoch scale.
4. `requestSeniorCapitalExit(principal, receiver)` moves units into the FIFO
   exit queue. Queued units continue earning fees but no longer provide new MLO
   capacity.
5. `processSeniorCapitalExits(maxRequests)` is permissionless, capped at 50
   requests per call, and pays the queue head from unreserved principal. A
   partial head cannot be skipped.
6. A provider can cancel an unprocessed exit and restore its units.

There is no automatic deployment bootstrap. Launch operators or users must
explicitly deposit, wait through the activation gate, and activate. Until then,
Senior fee shares fall back to treasury and MLO capacity is limited to maker
margin/inventory.

## Fee Index

Each epoch stores an accumulator per stored unit, a rounding remainder, and a
fee reserve. Eligible orderbook, parimutuel, parlay, donation, and MLO-funding
fees increment that index.

- Existing active and queued units receive the increment.
- Pending deposits and future activations do not receive earlier fees.
- Fee reserve is separate from principal and cannot be reserved for MLO risk.
- Direct token transfers to the Diamond are accounting-inert.
- The last position cleared from an epoch receives any residual indexed-fee
  dust left by integer division.

## MLO Capital Lifecycle

Senior capital remains in the same Diamond accounting domain throughout the MLO
lifecycle:

```text
unreserved principal
        |
        v
bucket reservation -- release --> unreserved principal
        |
        v
active exposure ---- repay -----> unreserved principal
        |
        v
realized loss ------> lower epoch scale for every provider
```

Every reservation and exposure is bucket-attributed. A realized loss reduces
total principal and scales provider claims pro rata. A total loss exhausts the
principal epoch and starts a fresh one while preserving fees earned by the old
epoch.

MLO funding paid to Senior increases the internal fee index and the global and
bucket funding-revenue counters. Insurance remains a distinct external fund and
does not expand pre-trade Senior capacity.

## Router Balance Handling

MLO manufacturing can move Senior principal from the Diamond into position
backing during a router call. Router residual assertions therefore compare the
raw token balance after adjusting for the measured change in global Senior
active exposure. This preserves strict residual checks without misclassifying a
legitimate internal Senior deployment as leaked router funds.

The Statics Dollar router's heavy CLOB execution is exposed through
`EtUsdTradeExecutionFacet` as a Diamond-self-call-only selector. This keeps the
public router under EIP-170 while preserving the outer reentrancy boundary.

## Safety Invariants

```text
totalPrincipal = unreservedPrincipal + reservedCapital + activeExposure

availableCapital = max(
    unreservedPrincipal - effectiveQueuedExitPrincipal,
    0
)

feeReserve is never principal
pendingPrincipal is never MLO capacity
direct token transfers create no principal, units, or fee claims
bucket totals reconcile with global reservation/exposure totals
```

The system deliberately has no Senior token composability, external pool
replacement ceremony, pool `balanceOf` accounting, or owner-settable risk
manager.

## Source Changes

- Added `ISeniorCapitalFacet`, `SeniorCapitalFacet`,
  `SeniorCapitalViewFacet`, and `LibSeniorCapital`.
- Removed `SeniorCapitalPool` and `ISeniorCapitalPool`.
- Removed `seniorCapitalPool` from market config, views, MLO structs, storage,
  deployment config, and deployment environment handling.
- Replaced external pool calls and transfers in MLO and fee paths with internal
  library accounting.
- Added Senior lifecycle/view selectors to deployment and test fixtures.
- Removed deployment-time Senior auto-bootstrap.
- Split Statics Dollar execution into a self-call-only facet to retain EIP-170 headroom.

## Verification Matrix

| Coverage | Evidence |
|---|---|
| Senior lifecycle and loss/fee accounting | `test/unit/SeniorCapitalFacet.t.sol` |
| Fee eligibility and treasury fallback | `test/unit/FeeRouter.t.sol`, `test/unit/SharedHelperLibraries.t.sol` |
| Parimutuel Senior fee routing | `test/unit/ParimutuelFacet.t.sol`, `test/properties/ParimutuelFeeProperties.t.sol` |
| MLO reserve/deploy/repay reconciliation | `test/unit/MLOPredictionAdapter.t.sol`, `test/properties/MLOInventoryProperties.t.sol` |
| Canonical NegRisk split/merge/settlement and book routing | `test/unit/MLOPredictionAdapter.t.sol`, `test/unit/NegRiskCTFIntegration.t.sol` |
| Multi-outcome creation, complete sets, and redemption | `test/unit/MultiOutcomeOrderbook.t.sol` |
| Router raw-balance handling | `test/unit/TradeRouter.t.sol` |
| Full Statics Dollar launch flow and Senior exit | `test/unit/DeployScript.t.sol` |
| Every deployed facet under EIP-170 | `_assertDiamondFacetSizes` in `test/unit/DeployScript.t.sol` |

The integrated NegRisk cases use the production adapter configuration and
canonical CTF custody. They cover 3- and 16-outcome ASK manufacturing,
complete-set BID auto-merge, winning and INVALID settlement, convenience book
routing, and exact-accounted redemption that ignores unsolicited vault tokens.

## Launch Sequence

1. Deploy the 66-facet Eve Diamond and verify every registered facet's runtime
   size is at most 24,576 bytes.
2. Verify `seniorCapitalState().asset` equals the configured Statics Dollar margin asset.
3. Have providers approve the Diamond and deposit Senior capital.
4. Wait at least 24 hours and activate the deposits.
5. Confirm `availableCapital`, `totalPrincipal`, and `totalStored` before enabling
   MLO quote capacity operationally.
6. Exercise deposit, activation, MLO fill/settlement, fee claim, and FIFO exit on
   public testnet before freezing Solidity.
