# Vault Stack Removal Boundary

## Status

The old vault, vault-share lending, maker-lending router, and vault-router surfaces have
been removed from active source, deployment wiring, smoke scripts, and tests.

Removed production surfaces:

- `SEveUSDCVault`
- `SEveUSDVault`
- `SEveUSDCLending`
- `SEveUSDLending`
- `MakerLendingRouter`
- `VaultRouterFacet`
- Old vault/lending/router interfaces
- `stakingVault` and `secondaryStakingVault` market config fields

## Replacement

`SeniorCapitalPool` is now the active senior eveUSDC capital surface. Protocol fee shares
that previously targeted vault receivers now route to the senior pool only when:

- the configured senior pool address is non-zero,
- `SeniorCapitalPool.asset()` matches the fee token, and
- `SeniorCapitalPool.totalSupply()` is non-zero.

If any condition fails, the share falls back to treasury. This keeps fee routing fail-closed
without preserving old vault reward-token semantics.

## Coverage

Current regression coverage lives in:

- `test/unit/SeniorCapitalPool.t.sol`
- `test/unit/SharedHelperLibraries.t.sol`
- `test/unit/DeployScript.t.sol`
- `test/unit/TradeRouter.t.sol`
- `test/unit/LaunchFlows.t.sol`
- `test/unit/ParimutuelFacet.t.sol`
- `test/properties/ParimutuelFeeProperties.t.sol`

Historical audit and deployment documents may still mention removed contracts as historical
records, but current source and deployment paths should not reintroduce the old vault stack.
