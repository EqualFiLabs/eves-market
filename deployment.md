# Eves Market — Robinhood Chain Testnet Deployment

This document records the current Eves Market deployment on Robinhood Chain
Testnet. It is a testnet release, not a production deployment.

## Release

| Field | Value |
| --- | --- |
| Network | Robinhood Chain Testnet |
| Chain ID | `46630` |
| Explorer | <https://explorer.testnet.chain.robinhood.com> |
| ConditionalTokens deployment block | `96756049` |
| ConditionalTokens creation transaction | `0x8d354e30285db00553e3e8d2f6d4052701428c1d25bfed84e6e0f386d5a6263f` |
| Eves deployment blocks | `96759486`–`96759521` |
| EveMarketDiamond creation transaction | `0xbabdc9b5a8bc333289f65c7c755c2700ac790b2c2bc104d2107eead1669e892e` |
| Senior activation block | `96766019` |
| Senior activation transaction | `0x315d647ce9256c088710b0f8c51f525efe39dcc7c57f980e01ab1a48f97a2543` |
| Deployer/owner | `0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316` |
| Treasury | `0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316` |
| Eves source branch | `main` |
| Eves source commit | `5d96ee5d53026b96feb27ceaf7d4613d4d6a74d1` |
| Statics source branch | `master` |
| Statics source commit | `71606762de01d63cd38261a88ae71a32e5f66aba` |

EqualFiLabs/eves-market currently uses `main` as its GitHub default branch; it
does not publish a `master` branch. The release therefore uses the exact current
GitHub `main` commit shown above and the exact current Statics `master` commit.

## Primary contracts

| Contract | Address |
| --- | --- |
| EveMarketDiamond | `0x9775baa49f3356D03D9b687926D4b5cD9b15C135` |
| ConditionalTokens | `0x96D4aB2F7c1077B4CeFd93206B77517e02Cd299c` |
| EVE | `0x6Db99B325a1B1Cf022727700C45dbf72c853D21A` |
| MLOInsuranceFund | `0xdfAB3a54a7793596A8131cFE0458175439a52dd6` |
| Eves faucet | `0x73B9409Fe44614ea5646e544a34BEc6D7428A3f3` |
| EvesPositionManager | `0xb01331D852978E8b9B0AD0B14454E929BD73cAd4` |
| EvesNegRiskAdapter | `0x2aF6E32154d89CB362ce7A1Bfb033061abeEF8F0` |
| EvesCTFSettlementAdapter | `0x46F93Fc61743792EDC30174F65685Fe83408775d` |
| ParimutuelShareToken | `0x18172a11A64001b7B0C9A861B82763F868191521` |
| ParlayTicketToken | `0x31ec4f65B147b666C0e94ABf048F8CCA230e9E13` |
| EveIdentity | `0xDaF5e02cbA201b2F6bcED365C002ce89b1Eb3d07` |

## Statics integration

| Contract | Address |
| --- | --- |
| StaticsDiamond / Position NFT | `0xfb3Baf22daCADE66f7CF0356aC2E342235af74bf` |
| StaticsDollarCoreDiamond | `0xB142E9c8f80Fe67a96c8B3e152BfB7fF546312CC` |
| Statics Dollar (`USDstx`) | `0x2bDE36A981353fb31a1237013e460Cac7AeAeA85` |
| Mock USDG | `0xBF85818cf213868c7aAE46d527b747e720B93054` |

The market configuration was verified live against these fresh Statics
addresses and pegged profile `2`. The release manifest pins both exact source
commits; the Eves repository's older recorded Statics gitlink was not used.

## Governance and launch configuration

| Field | Current value |
| --- | --- |
| Governance delay | `900` seconds |
| MLO profit-split delay | `900` seconds |
| Permissionless market creation | Disabled |
| Market creation fee | `0` |
| MLO insurance bootstrap | `100,000 USDstx` |
| Senior capital bootstrap | `100,000 USDstx` |
| Senior activation delay | `900` seconds |

The full Senior capital bootstrap is activated: pending principal is `0`, total
principal and available capital are each `100,000 USDstx`, and the deployer
account holds the corresponding effective principal. Available MLO insurance is
also `100,000 USDstx`.

The Eves faucet is funded with `1,000,000` Mock USDG and `10,000,000 EVE`.

## Release manifest and verification

| Field | Value |
| --- | --- |
| Facets | `67` |
| Routed selectors | `442` |
| Explicitly absent legacy selectors | `5` |
| Configuration hash | `0x5666e17985aaf37469c9387a8ad79f8488aff96249555d75d1524dfca8ff4901` |
| Deployment hash | `0x294e446fb9106b5340fbd7aa1dc19a9f69c9deb1812ff0f966d4fad67ce06b03` |

- All 139 receipts in the Eves deployment broadcast artifact succeeded.
- The separate ConditionalTokens deployment and Senior activation receipts
  succeeded.
- The live release-manifest verifier passed after Senior activation.
- Blockscout source verification was confirmed for all 83 unique contracts in
  the release manifest and deployment broadcast.
- Broadcast artifacts remain local and intentionally ignored because they may
  contain operational metadata. No RPC credentials or signing material belong
  in this document.

Published source: <https://github.com/EqualFiLabs/eves-market>
