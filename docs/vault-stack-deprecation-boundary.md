# Vault Stack Deprecation Boundary

## Purpose

This document defines the Phase 0 quarantine boundary for the current vault, lending, and
maker-lending router stack. The system is not live, but the old stack remains useful as
reference infrastructure while the senior margin pool replacement is built.

Phase 0 is behavior-neutral. It does not remove contracts, selectors, deployment wiring,
tests, or scripts.

## Quarantine Now

Do not add new product behavior to these contracts or interfaces:

- `SEveUSDCVault`
- `SEveUSDVault`
- `SEveUSDCLending`
- `SEveUSDLending`
- `MakerLendingRouter`
- `ISEveUSDCVault`
- `ISEveUSDVault`
- `ISEveUSDCLending`
- `ISEveUSDLending`
- `IMakerLendingRouter`

Reason:

- The senior margin pool replaces the current ERC-4626 staking vault and vault-share
  lending model.
- MLOs should post margin and receive bounded quote authority, not borrow against vault
  shares.
- Multi-token claimable rewards should not be carried forward into the senior pool.

## Transitional Surfaces

These surfaces still compile and remain wired until later phases replace them:

- `stakingVault` and `secondaryStakingVault` in market config.
- `LibFeeRouting`, `LibBookAccounting`, `ParimutuelFacet`, and parlay fee routing calls
  that send protocol fees to vault-like receivers through `notifyRevenue`.
- `VaultRouterFacet`, which wraps and deposits into the current staking vault.
- `Deploy.s.sol`, `UpgradeEveUSDC18.s.sol`, and `script/anvil_smoke.sh` wiring for the
  old vault, lending, maker-router, and vault-router paths.

Phase 1 should introduce the senior pool before these paths are rewritten. Phase 7 should
remove or replace them from active deployment.

## Historical Reference Tests

These suites are useful as accounting references while the senior pool is being designed,
but they should not define new product behavior:

- `test/unit/SEveUSDCVault.t.sol`
- `test/unit/SEveUSDCVaultAccounting.t.sol`
- `test/unit/SEveUSDVault.t.sol`
- `test/properties/VaultRevenueProperties.t.sol`
- `test/properties/VaultShareProperties.t.sol`
- `test/unit/VaultFeeRouting.t.sol`
- `test/properties/FeeRoutingProperties.t.sol`

Useful reference areas:

- Share mint/burn rounding.
- Fee revenue increasing NAV.
- Reserved or unavailable assets limiting withdrawals.
- Fee-routing fallback behavior when no eligible receiver exists.

## Replace Later

These suites should be removed or rewritten after senior pool, MLO margin, and recovery
paths exist:

- `test/unit/SEveUSDCLending.t.sol`
- `test/unit/SEveUSDLending.t.sol`
- `test/unit/MakerLendingRouter.t.sol`
- `test/unit/MakerLendingRouterIntegration.t.sol`
- `test/unit/LendingIntegration.t.sol`
- `test/unit/VaultRouter.t.sol`
- `test/properties/LendingBorrowProperties.t.sol`
- `test/properties/LendingRepayProperties.t.sol`
- `test/properties/LendingDefaultProperties.t.sol`
- `test/properties/LendingExtensionProperties.t.sol`
- `test/properties/LendingInvariantProperties.t.sol`
- `test/properties/LendingPreviewProperties.t.sol`
- `test/properties/LendingAccessControlProperties.t.sol`
- `test/properties/LendingVaultAccountingProperties.t.sol`
- `test/properties/LendingYieldProperties.t.sol`
- `test/properties/RouterOnrampProperties.t.sol`
- `test/properties/RouterOfframpProperties.t.sol`
- `test/properties/RouterBorrowForProperties.t.sol`
- `test/properties/RouterPreviewProperties.t.sol`
- `test/properties/RouterResidualProperties.t.sol`
- `test/properties/RouterProperties.t.sol`

Replacement coverage should target:

- Senior pool deposits, redemptions, reserved capital, and NAV.
- MLO margin deposits, bucket allocation, and risk-increase gating.
- Envelope-backed quote creation, updates, cancels, and fills.
- Delayed FIFO risk revalidation.
- Recovery and insurance waterfall accounting.

## Phase 0 Rules

- Keep all old contracts compiling.
- Keep deploy and smoke wiring unchanged.
- Keep existing tests available as regression coverage until the replacement path exists.
- Do not introduce new dependencies on vault-share lending semantics.
- Do not add new multi-token reward behavior to the old vault stack.
