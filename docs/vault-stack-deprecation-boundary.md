# Vault Stack Removal Boundary

## Status

Current implementation has removed the deprecated `sEVEUSDC` vault, vault-share
lending, and maker-lending router surfaces. The protocol is unreleased, so there is no
compatibility shim or migration layer.

Removed active surfaces:

- `SEveUSDCVault`
- `SEveUSDCLending`
- `MakerLendingRouter`
- vault/lending/router interfaces
- `stakingVault` and `stakingVaultFeeShareBps` market config fields

## Current Active Surface

`SeniorCapitalPool` is the senior eveUSDC capital surface. The fee bucket still named
`vaultFeeBps` now routes entirely to `SeniorCapitalPool` when eligible:

- configured senior pool address is non-zero,
- `SeniorCapitalPool.asset()` matches the fee token, and
- `SeniorCapitalPool.totalSupply()` is non-zero.

If SCP is ineligible, that fee slice falls back to treasury.

## Coverage

Current regression coverage lives in:

- `test/unit/SeniorCapitalPool.t.sol`
- `test/unit/FeeRouter.t.sol`
- `test/unit/DeployScript.t.sol`
- product flow tests that exercise fee routing through orderbook, parimutuel, combo,
  spot, and parlay paths

Historical audit and deployment documents may still mention removed contracts as
historical records. Current source and launch docs should not reintroduce the deleted
vault/lending/router path without a fresh design decision.
