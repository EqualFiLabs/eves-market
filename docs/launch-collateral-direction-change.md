# Launch Collateral Direction

**Status:** Current direction memo

**Updated:** 2026-07-20

**Target:** Robinhood Chain, chain ID `4663`

## Decision

Launch with Statics Dollar as the primary market, bond, Senior Capital, and
MLO insurance asset. USDG enters through a pegged Statics Dollar profile. The
production Eve Diamond does not install legacy eveUSDC adapters or maintain a
second copy of Statics profile policy.

## Launch model

```text
USDG + static pegged fee
        |
        v
StaticsDiamond gateway ----------------> StaticsDollarCoreDiamond
        |                                  principal custody + issuance
        +---- Statics Dollar --------------------------+
                                                       v
                                            EveMarketDiamond
                                      markets + Senior Capital + MLO
```

- Existing Statics Dollar can be used directly.
- `mintAndBuyWithUSDCPermit` authorizes the exact previewed USDG collateral,
  mints through the shared `StaticsDiamond`, executes the Eve purchase, and
  returns unfilled Statics Dollar to the buyer in one transaction.
- `mintAndBuyWithUSDC` preserves the same economics for the explicit
  exact-approval fallback. The temporary `USDC` identifier remains internal;
  user-facing surfaces call the asset USDG.
- Pegged profiles mint no Risk Shares. Their mint fee becomes isolated Statics
  protocol revenue.
- Statics remains authoritative for profile mode, oracle policy, debt ceiling,
  fee configuration, solvency, and redemption status.
- Eve stores the Core, the Diamond and token derived from that Core, the USDG
  token, and the pegged profile ID needed to identify the rail.

## Governance reconfiguration

The configured margin asset, NegRisk adapter, and CTF settlement adapter may be
replaced only through the Diamond's finalized calldata timelock. Margin-asset
replacement additionally requires all user-margin, Senior principal, exit,
fee, and MLO Senior-reward liabilities to be settled first.

Existing markets and CTF positions retain their stored collateral and adapter
addresses. Adapter rotation therefore affects new markets without changing the
settlement route for historical positions. A margin-asset migration must also
stage the matching collateral, Statics Core, and MLO insurance configuration;
governance should keep new exposure disabled until that sequence is complete.

## Deployment inputs

Production launch requires explicit values for:

- `USDC_TOKEN` (temporary internal name; set it to canonical USDG)
- `STATICS_DOLLAR_CORE_ADDRESS`
- `STATICS_DOLLAR_USDC_PROFILE_ID`

The attached Core must be bootstrapped and report exact bindings for
`StaticsDollar`, `StaticsDiamond`, and the shared PositionNFT. The selected
profile must be pegged and use the configured USDG token. Eve does not cache
the profile's mutable operating mode; the Statics gateway enforces current
policy when a user executes.

The canonical Statics source is pinned under `lib/statics`. There is no legacy
collateral submodule, adjacent-repository import, symlink, or runtime source
dependency.

## Fee routing

Eve's total trade fee rates are unchanged. The former Risk Share distribution
is now part of the Senior Capital allocation:

| Market path | Maker | Creator | Protocol | Senior Capital | Resolver |
| --- | ---: | ---: | ---: | ---: | ---: |
| Orderbook | 4,000 | 500 | 1,000 | 4,000 | 500 |
| Spot | 4,000 | 0 | 1,500 | 4,000 | 500 |
| Combo | 4,000 | 500 | 1,000 | 4,000 | 500 |
| Parimutuel | 0 | 500 | 5,000 | 4,000 | 500 |

These are basis-point allocations of an already calculated fee. When the fee
asset is the configured margin asset and active Senior units exist, the Senior
share accrues to their internal fee index. Otherwise the existing treasury
fallback applies.

## Verification boundary

The launch proof uses a fresh local deployment of both protocol stacks on a
fork pinned to Robinhood Chain block `14,498,238`. It verifies the canonical
PoolManager runtime, current diamond selector routing, Statics bindings, USDG
permit metadata, USDG principal custody, isolated pegged protocol revenue,
Statics Dollar issuance, exact allowance consumption, and delivery of the
purchased Eve position. The test broadcasts no public transaction.
