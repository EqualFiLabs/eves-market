# Eves Market — Robinhood Chain Testnet Deployment

This is the current Eves Market testnet release. It replaces all previous
Robinhood testnet deployments.

## Release

| Field | Value |
| --- | --- |
| Network | Robinhood Chain Testnet |
| Chain ID | `46630` |
| Explorer | <https://explorer.testnet.chain.robinhood.com> |
| Conservative indexing start block | `97389252` |
| EveMarketDiamond creation block | `97389649` |
| Eve source branch | `main` |
| Eve source commit | `646437775fbac63b4d04f287ec5cf63f92d01042` |
| Statics source commit | `724df0fe80be8e376a5cb61811d02e1ef7413707` |
| Deployer and owner | `0x6Ae2aD9905FEDC8270b828294D4b9CEC7CBBE316` |

## Critical contracts

| Contract | Address |
| --- | --- |
| EveMarketDiamond | `0x9f3e87C9c60FB1F983eb5319dfa557E804A5fffa` |
| ConditionalTokens | `0xc32100943b65A89b7404FC4021D9bbD0B7148209` |
| EVE | `0x6b4f26468Ea05e0b0516b352B2b5f486DCeCdAB5` |
| MLOInsuranceFund | `0x5Fe2b9c5A3E5326df00fA60426211D2FBAAb853c` |
| Faucet | `0x357101E37b12Ee7522903c9D2d6B4b5B5a395a24` |
| EvesPositionManager | `0xa5D02f138A8Ab3eC0FeCe3bDA32696BBe25F4EBA` |
| EvesNegRiskAdapter | `0x59a33ab3F65e707bf2024afF5bA709D95985eC99` |
| EvesCTFSettlementAdapter | `0x2366Dc68641F6c8ADec562Cc4FA52A5363C435C6` |
| ParimutuelShareToken | `0xf35fcecf6584e6806d74CC9E429aAC52bab0fb91` |
| ParlayTicketToken | `0xD42d2E0223E487E2eD5095222aC64137Db417eb9` |
| EveIdentity | `0x9d5F94c0608b85d66902E92d57A69A2EA17d16cF` |

The generated manifest additionally pins all 67 facet addresses, runtime code
hashes, and selector routes.

## Statics integration

| Contract | Address |
| --- | --- |
| StaticsDiamond / Position NFT | `0x2340741Ec94dF12678312f564eBc2c776d8FaA6a` |
| StaticsDollarCoreDiamond | `0x6AB8009073e0e6E0b0458e39E3b547DA31b5724f` |
| Statics Dollar (`USDstx`) | `0xd1F2DC3Ed9b70a85B6629C04afCEdb43B2Ca25ce` |
| Mock USDG | `0x3c9dCe3FD17f3FC8A1929B1614b2c99124129Da1` |

The Eves Position Manager is wired to this fresh Statics Position NFT release.
That Position NFT exposes the standardized state nonce and Statics portfolio
enumeration surfaces.

## Governance and bootstrap state

| Field | Current value |
| --- | --- |
| Diamond owner | Deployer |
| Treasury | Deployer |
| Governance delay | `900` seconds |
| Market creation fee | `0` |
| Permissionless market creation | Disabled |
| MLO insurance bootstrap | `100,000 USDstx` |
| Senior capital | `100,000 USDstx`, activated |
| Senior capital available | `100,000 USDstx` |

The initial senior deposit completed its required 15-minute pending period and
was activated in transaction
`0x07b1a9ff7284768f119ca16ebd341f3d406da7284b3a5f4f81ff79d84c256061`
at block `97402010`. Live readback confirmed zero pending principal and
`100,000 USDstx` of effective and available principal.

## Faucet

The faucet is owned by the deployer and is funded with:

| Asset | Claim amount | Inventory |
| --- | ---: | ---: |
| Mock USDG | `1,000` | `1,000,000` |
| EVE | `10,000` | `10,000,000` |

Both assets are enabled and the live token balances match these inventories.

## Verification

- The preflight and full deployment simulation passed before broadcast.
- All 79 broadcast contracts were source verified by the release workflow.
- Blockscout verification was confirmed for all 83 release contracts, including
  separately deployed dependencies.
- The release verifier confirmed the pinned Statics addresses, governance,
  runtime code hashes, selector routing, and required absent legacy selectors.
- Senior capital activation and its resulting state were confirmed live.

Broadcast artifacts, operational environment files, and signing material remain
local and ignored. The machine-readable companion record is
[`deployments/robinhood-testnet-46630.json`](deployments/robinhood-testnet-46630.json).
