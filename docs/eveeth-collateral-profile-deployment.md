# eveETH Collateral Profile Deployment

**Scope:** optional WETH/eveETH collateral profile support for orderbook, parimutuel,
multi-outcome, and parlay payout collateral.

The eveETH profile is additive. The default eveUSD collateral path remains the base system collateral, and the deploy script only enables eveETH markets when the explicit flags below are set.

## Deploy Flags

```text
DEPLOY_MOCK_WETH=
DEPLOY_EVEETH=
ENABLE_EVEETH_MARKETS=
WETH_ADDRESS=
EVEETH_ADDRESS=
EVEETH_PAYOUT_UNIT=
EVEETH_MARKET_CREATION_FEE=
EVEETH_PARIMUTUEL_CREATION_SEED_AMOUNT=
EVEETH_PARIMUTUEL_MIN_ENTRY=
EVEETH_PARLAY_UNDERWRITING_FEE=
```

Recommended local Anvil configuration:

```text
DEPLOY_MOCK_WETH=true
DEPLOY_EVEETH=true
ENABLE_EVEETH_MARKETS=true
WETH_ADDRESS=
EVEETH_ADDRESS=
EVEETH_PAYOUT_UNIT=500000000000000
EVEETH_MARKET_CREATION_FEE=0
EVEETH_PARIMUTUEL_CREATION_SEED_AMOUNT=0
EVEETH_PARIMUTUEL_MIN_ENTRY=500000000000000
EVEETH_PARLAY_UNDERWRITING_FEE=200000000000000
```

Recommended testnet configuration with an existing WETH deployment:

```text
DEPLOY_MOCK_WETH=false
DEPLOY_EVEETH=true
ENABLE_EVEETH_MARKETS=true
WETH_ADDRESS=<canonical WETH address>
EVEETH_ADDRESS=
EVEETH_PAYOUT_UNIT=500000000000000
EVEETH_MARKET_CREATION_FEE=0
EVEETH_PARIMUTUEL_CREATION_SEED_AMOUNT=0
EVEETH_PARIMUTUEL_MIN_ENTRY=500000000000000
EVEETH_PARLAY_UNDERWRITING_FEE=200000000000000
```

If `EVEETH_ADDRESS` is already deployed, set `DEPLOY_EVEETH=false` and provide both `EVEETH_ADDRESS` and `WETH_ADDRESS`.

## Deployed Outputs

`script/Deploy.s.sol:DeployScript` now returns these additional full-stack deployment addresses:

```text
wethToken
eveETH
```

When `ENABLE_EVEETH_MARKETS=true`, the deploy script configures collateral profile `1` on the Diamond:

```text
profileId=1
collateralToken=eveETH
wrapperToken=WETH
payoutUnit=EVEETH_PAYOUT_UNIT
marketCreationFee=EVEETH_MARKET_CREATION_FEE
parimutuelCreationSeedAmount=EVEETH_PARIMUTUEL_CREATION_SEED_AMOUNT
parimutuelMinEntry=EVEETH_PARIMUTUEL_MIN_ENTRY
parlayUnderwritingFee=EVEETH_PARLAY_UNDERWRITING_FEE
enabled=true
```

The profile can be verified after deployment with:

```bash
cast call "$DIAMOND" "getCollateralProfile(uint8)((address,address,uint128,uint128,bool))" 1 --rpc-url "$RPC_URL"
cast call "$DIAMOND" "getCollateralProfileParimutuelConfig(uint8)(uint128,uint128)" 1 --rpc-url "$RPC_URL"
cast call "$DIAMOND" "getCollateralProfileParlayUnderwritingFee(uint8)(uint128)" 1 --rpc-url "$RPC_URL"
```

## ABI Exports

The UI ABI folder includes:

```text
eves-market-ui/lib/abi/EveETH.json
eves-market-ui/lib/abi/CanonicalWETH9.json
eves-market-ui/lib/abi/MarketFactoryFacet.json
eves-market-ui/lib/abi/MarketViewFacet.json
eves-market-ui/lib/abi/OwnershipFacet.json
eves-market-ui/lib/abi/ParimutuelFacet.json
eves-market-ui/lib/abi/MultiOutcomeOrderbookFacet.json
eves-market-ui/lib/abi/IParlayFacet.json
```

Use `EveETH.json` for `wrap(uint256,address)`, `unwrap(uint256,address)`, and `weth()`. `CanonicalWETH9.json` is for local mock WETH testing only.

## Safety Boundaries

- eveETH is supported by explicit collateral profile selection; the default path remains eveUSD.
- Parimutuel and multi-outcome eveETH markets use the market's stored collateral token and payout unit.
- Parlay payout collateral is selected independently from leg collateral; budget-backed quotes must match the budget profile.
- Maker lending remains eveUSD-only and rejects eveETH profile markets.
- USDC helper paths remain eveUSD-only and reject eveETH profile markets.
- CLOB, parimutuel, multi-outcome, combo, and parlay accounting remains raw-unit and collateral-native internally.
