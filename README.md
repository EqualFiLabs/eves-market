# Eves Market

Onchain prediction market protocol targeting Robinhood Chain, implemented as an EIP-2535 Diamond with modular facets and a shared storage layout. It supports binary CLOB markets, parimutuel pools, N-way multi-outcome orderbook markets, native combinatorial (parlay-style) positions, peer-to-peer parlays, standalone spot books, and MEV-resistant delayed taker orders. Disputes settle through an Optimistic Bond-based Resolution (OBR) system backed by a staked commit-reveal Resolver Jury.

For market data models, math, and resolution flows, see [`EvePredict-Design.md`](./EvePredict-Design.md). Its historical collateral chapters are superseded by the current [launch collateral direction](./docs/launch-collateral-direction-change.md).

---

## Table of Contents

- [Highlights](#highlights)
- [Architecture at a Glance](#architecture-at-a-glance)
- [Repository Layout](#repository-layout)
- [Prerequisites](#prerequisites)
- [Setup](#setup)
- [Build](#build)
- [Test](#test)
- [Deploy](#deploy)
- [Core Concepts](#core-concepts)
- [Common Flows](#common-flows)
- [Configuration Reference](#configuration-reference)
- [Conventions & Contributing](#conventions--contributing)
- [License](#license)

---

## Highlights

| Capability | Summary |
|---|---|
| **Diamond architecture** | EIP-2535 proxy; facets share `LibEveMarket.EveMarketStorage`. Parimutuel, parlay, and resolver-jury state use isolated storage slots. |
| **Market types** | `CLOB` (binary curve order book), `PARIMUTUEL` (pooled entry), `MULTI_OUTCOME_ORDERBOOK` (N-way). |
| **Position tokens** | Gnosis CTF (binary + NegRisk multi-outcome), `ParimutuelShareToken`, and native `EvesPositionManager` (binary + combinatorial). |
| **Combinatorial markets** | Native AND-of-legs combo conditions with split / merge / branch / compress / redeem. |
| **Parlays** | Peer-to-peer underwritten multi-leg tiered-payout bets with shared budgets and tradable tickets. |
| **Delayed orders** | Block-delayed taker orders with committed routes and protocol/permissionless processing. |
| **Collateral profiles** | Pluggable product collateral, with Statics Dollar as the launch default through a pegged USDC profile. |
| **USDC entry** | Exact Statics Dollar mint-and-buy through the shared `StaticsDiamond`; pegged mint fees remain isolated Statics protocol revenue. |
| **Senior capital** | Non-transferable Statics Dollar principal accounting inside the Eve Diamond, with indexed fees, bounded activation, FIFO exits, MLO reservations, and pro-rata loss accounting. |
| **OBR + Resolver Jury** | Optimistic bond resolution escalating to a staked, soulbound-identity commit-reveal jury. |

---

## Architecture at a Glance

```text
   USDC ── pegged mint ──▶ StaticsDiamond ──▶ StaticsDollarCoreDiamond
                               │                        │
                               └── Statics Dollar ─────┘
                                          │
                                          ▼
                        ┌─────────────────────────────┐
   Statics Dollar ─────▶│ EveMarketDiamond (EIP-2535) ──▶ Gnosis CTF + NegRisk adapter
   Senior deposit ─────▶│ facets share storage             ParimutuelShareToken
                        │                                   EvesPositionManager / ParlayTicketToken
                        │        ├─ Market creation / metadata / groups
                        │        ├─ Curve CLOB engine + books (spot)
                        │        ├─ Parimutuel pools (epoch multiplier)
                        │        ├─ Multi-outcome + native/combo positions
                        │        ├─ Parlays (offers / requests / budgets / tickets)
                        │        ├─ Delayed orders (queue + processors)
                        │        ├─ OBR resolution → Resolver Jury
                        │        └─ Fee routing + maker rewards
```

Local standalone contracts (`MLOInsuranceFund`, `Faucet`) live outside the Eve Diamond. Senior capital is held and accounted for by the Eve Diamond itself; no external pool, share token, or replaceable pool address exists. The pinned Statics dependency supplies `StaticsDollarCoreDiamond`, the shared `StaticsDiamond` gateway/position address, and `StaticsDollar`. Eve derives the Diamond and token from an already bootstrapped Core with an active pegged USDC profile; mutable profile policy remains authoritative in Statics.

---

## Repository Layout

```
eve-predict/
├── src/
│   ├── EveMarketDiamond.sol          # EIP-2535 proxy
│   ├── MLOInsuranceFund.sol           # Dedicated Statics Dollar insurance reserve
│   ├── Faucet.sol                    # Multi-token testnet faucet
│   ├── facets/                       # Diamond facets
│   │   ├── SeniorCapitalFacet.sol     # Deposit, activation, exit, fee claims
│   │   ├── SeniorCapitalViewFacet.sol # Senior state, accounts, exits, buckets
│   │   ├── native/                   # Native binary + combinatorial facets
│   │   └── parlay/                   # Parlay facets
│   ├── tokens/                       # ERC-1155 / identity / wrapper tokens
│   ├── interfaces/                   # Contract interfaces
│   ├── types/                        # Facet param / view structs
│   ├── libraries/                    # Storage + math + helper libraries
│   ├── init/                         # Diamond initializers
│   └── mocks/                        # Test mocks (WETH9, USDC, etc.)
├── lib/statics/                      # Pinned canonical Statics submodule
├── script/                           # Foundry deploy + upgrade scripts
├── scripts/                          # Operational shell scripts (seeding, markets)
├── test/
│   ├── unit/                         # Unit + harness tests
│   ├── properties/                   # Invariant / fuzz / property tests
│   └── helpers/                      # Test fixtures and helpers
├── docs/                             # Specs and deep-dive design notes
├── conditional-tokens/               # Canonical Gnosis Conditional Tokens submodule
├── EvePredict-Design.md              # Full protocol design document
├── foundry.toml
├── conditional-tokens-build/         # Isolated Solidity 0.5 CTF artifact build config
└── remappings.txt
```

---

## Prerequisites

- [Foundry](https://book.getfoundry.rs/getting-started/installation) (`forge`, `cast`, `anvil`)
- Solidity `0.8.33` (pinned in `foundry.toml`), EVM target `cancun`

---

## Setup

OpenZeppelin Contracts, Gnosis Conditional Tokens, and Statics are tracked as pinned git submodules for reproducible builds and audits. Initialize them after cloning:

```shell
git submodule update --init --recursive
forge install foundry-rs/forge-std --no-git
```

Main protocol remappings are defined in `foundry.toml`:

```
@openzeppelin/contracts/=lib/openzeppelin-contracts/contracts/
forge-std/=lib/forge-std/src/
```

The Conditional Tokens artifact is built from the canonical Solidity 0.5 submodule with a separate pinned OpenZeppelin 2.3 dependency:

```shell
forge build --config-path conditional-tokens-build/foundry.toml
```

---

## Build

```shell
forge build --config-path conditional-tokens-build/foundry.toml
forge build
```

> The protocol is large. Avoid full clean rebuilds during iteration. Do **not** run `forge build --force`, `forge build --contracts`, or `forge clean` — they trigger a full rebuild that is slow. Prefer incremental builds and path-scoped tests.

---

## Test

Run scoped test paths rather than the whole suite while iterating:

```shell
# A single property suite
forge test --match-path test/properties/BitpackingProperties.t.sol

# A single unit suite
forge test --match-path test/unit/SharedLibraries.t.sol

# A specific test by name
forge test --match-test test_fillBest_respectsMaxAveragePrice -vvv
```

Test organization:

- `test/unit/` — narrow unit and harness tests (branch coverage, storage checks, otherwise-unreachable state-machine edges).
- `test/properties/` — invariant and fuzz suites that broaden state-machine coverage.
- `test/helpers/` — shared fixtures and helpers.

Fuzz runs are configured low (`runs = 12`) in `foundry.toml` for speed; raise locally when hardening a change.

### Testing guidance

- Keep the test pyramid balanced: unit harnesses for edges, live/launch-level tests for every value-moving lifecycle, invariant/fuzz to broaden coverage. Prefer real flows.
- Every code change should come with tests proving functionality.
- Synthetic shortcuts (direct accounting drift, status jumps) must be documented in-file and kept narrow; they do not count as end-to-end confidence on their own.

---

## Deploy

The deployment entry point is `script/Deploy.s.sol`. It deploys Eve's standalone contracts, cuts every facet into the Eve Diamond, attaches the configured Statics Dollar Core, and initializes protocol config from environment variables. Build `out/conditional-tokens/ConditionalTokens.sol/ConditionalTokens.json` before running deploys that auto-deploy Gnosis CTF. Environment templates are provided:

- `.env.anvil` — local Anvil defaults
- `.env.base-sepolia` — historical Base Sepolia testing

Example (local Anvil):

```shell
anvil   # in a separate terminal

source .env.anvil
forge script script/Deploy.s.sol:Deploy \
  --rpc-url http://127.0.0.1:8545 \
  --broadcast
```

Historical Base Sepolia example (not the active launch target):

```shell
source .env.base-sepolia
forge script script/Deploy.s.sol:Deploy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  --broadcast --verify
```

Upgrade scripts (each performs a targeted DiamondCut) live alongside `Deploy.s.sol`, e.g. `UpgradeOBRResolutionFacet.s.sol`, `UpgradeSpotCurveFacets.s.sol`, and `UpgradeBookDecommission.s.sol`.

Operational helper scripts (market seeding, demo markets) are under `scripts/`.

---

## Core Concepts

### Markets and position tokens

Each market declares a `MarketType` and a `PositionTokenType` at creation:

- **Binary CLOB** → Gnosis CTF positions; makers split collateral into YES/NO and post curves.
- **Parimutuel** → `ParimutuelShareToken`; bettors buy single-side shares into a pooled payout with an epoch-based share multiplier.
- **Multi-Outcome Orderbook** → canonical one-vs-rest Gnosis CTF positions produced by `EvesNegRiskAdapter`; users split collateral into a full YES-outcome set and trade per-outcome books.

Market IDs fold in the type, position-token type, and collateral (plus the profile `payoutUnit` for non-default collateral) so variants never collide.

### Books

Every CLOB-style market auto-creates per-side books with independent fee config and accounting. Books can also be created standalone for spot trading of arbitrary ERC-20 / ERC-1155 base assets (including fee-on-transfer tokens via `BALANCE_DELTA`) using tick-based pricing.

### Curves

Liquidity is posted as time-decaying price curves (linear / step / exponential-decay or custom profiles). Curves carry a monotonic `generation` and a `commitment` hash; fills supply both for optimistic-concurrency protection plus slippage guards (`minSharesOut`, `maxAveragePrice`). `ASK` curves escrow base; `BID` curves escrow quote.

### Resolution

After expiry the creator may settle; otherwise the community proposes outcomes with escalating bond-token deposits. At `maxEscalation` the dispute is handed to the **Resolver Jury** — staked, soulbound `EveIdentity` holders selected by commit-reveal randomness who vote by commit-reveal. Honest creators reclaim their creation bond and escrowed fees; dishonest ones are slashed (10% to the winning resolver, remainder to treasury).

### Collateral rail

Statics Dollar is the launch collateral, bond, Senior-capital, and MLO-insurance rail. Users can supply existing Statics Dollar directly or call `mintAndBuyWithUSDC`, which mints exact Statics Dollar through the configured pegged USDC profile. Pegged profiles have no Risk Share receiver; their static mint fee is retained as isolated Statics protocol revenue. Other collateral can still be added through generic collateral profiles. Senior principal is non-transferable internal Diamond accounting: deposits wait 24 hours before activation, active principal earns indexed protocol and MLO funding fees, and withdrawals use a FIFO exit queue constrained by unreserved liquidity.

---

## Common Flows

These are illustrative; see [`EvePredict-Design.md`](./EvePredict-Design.md) for full signatures and structs.

**Create a binary CLOB market**

```solidity
bytes32 marketId = marketFactory.createMarket(
    "Will ETH close above 4k by Dec 2026?",
    "crypto",
    "Coinbase ETH/USD daily close at 00:00 UTC on 2026-12-31",
    0,                              // tradingStartTime (0 = immediate)
    uint64(block.timestamp + 30 days),
    1000,                           // initial liquidity (shares)
    true                            // seed a YES curve
);
```

**Make a market (split + post + top up)**

```solidity
IERC20(staticsDollar).approve(diamond, 5000e18);
curveInventory.splitInventory(marketId, 5000e18);
IERC1155(ctf).setApprovalForAll(diamond, true);

uint256 curveId = curveLifecycle.postCurve(
    marketId, true, 5000, 400_000_000, 600_000_000, 120, 0,
    LibEveMarket.PositionTokenType.CTF
);
curveLifecycle.topUpCurvesBatch(marketId, topUps);
feeRouter.claimMakerFees(marketId);
```

**Take (mint Statics Dollar from USDC and buy via the router)**

```solidity
IERC20(usdc).approve(diamond, 500e6);
FillBestResult memory result = tradeRouter.mintAndBuyWithUSDC(buyWithUSDCParams);
```

**Bet a parimutuel market**

```solidity
IERC20(staticsDollar).approve(diamond, 100e18);
uint128 minOut = parimutuel.previewParimutuelEntry(marketId, true, 100e18).sharesMinted;
parimutuel.buyShares(marketId, true, 100e18, msg.sender, minOut);
// after resolution
parimutuel.claimPayout(marketId);
```

**Provide senior capital**

```solidity
IERC20(staticsDollar).approve(diamond, 10_000e18);
seniorCapital.depositSeniorCapital(10_000e18);
// after the 24-hour activation gate
seniorCapital.activateSeniorCapital();
seniorCapital.requestSeniorCapitalExit(10_000e18, msg.sender);
seniorCapital.processSeniorCapitalExits(1);
```

---

## Configuration Reference

Deployment reads protocol parameters from environment variables (see `.env.anvil`). Selected keys:

| Variable | Meaning |
|---|---|
| `PRIVATE_KEY` | Deployer key |
| `INITIAL_OWNER` | Diamond owner |
| `EVE_TREASURY` | Protocol treasury recipient |
| `USDC_TOKEN` | Pegged collateral used by the Statics Dollar rail |
| `STATICS_DOLLAR_CORE_ADDRESS` | Bootstrapped canonical Statics Dollar Core |
| `STATICS_DOLLAR_USDC_PROFILE_ID` | Pegged USDC profile selected for Eve entry |
| `ROBINHOOD_RPC_URL` | Robinhood Chain RPC used only by local fork verification |
| `ROBINHOOD_FORK_BLOCK` | Must match the pinned launch verification block |
| `PERMISSIONLESS_CREATION_ENABLED` | Allow non-owner market creation |
| `MARKET_CREATION_FEE` | Collateral fee to create a market |
| `MARKET_CREATION_BOND_EVE` | Creation bond amount (bond token) |
| `MIN_MARKET_DURATION` / `MAX_MARKET_DURATION` | Market duration bounds (seconds) |
| `DISPUTE_WINDOW` | Dispute window after a settlement proposal (seconds) |
| `CREATOR_SETTLE_GRACE` | Creator-only settlement window after expiry (seconds) |
| `OPEN_RESOLUTION_TIMEOUT` | Community resolution window after grace (seconds) |
| `MAX_ESCALATION` | Dispute level at which the Resolver Jury is invoked |

> Note: some legacy `.env` keys (e.g. `DISPUTE_BOND_L*_ETH`, `EVE_VOTE_*`) reflect an earlier ETH-bond / token-vote model. The current protocol uses a generic resolution `bondToken` and the Resolver Jury; treat live config as the source of truth and confirm the active `Deploy.s.sol` mapping before relying on a key.

Runtime config is readable on-chain via `MarketFactoryFacet.getMarketConfig()`.

---

## Conventions & Contributing

- **TypeScript** (UI / tooling in sibling packages): always run `npm run typecheck`.
- **Solidity builds**: avoid full clean rebuilds (`forge build --force/--contracts`, `forge clean`); use incremental builds and `forge test --match-path …`.
- **Compiler-resilience for harnesses**: in broad test-harness contracts, prefer `uint256` for external/public numeric params and cast to narrower types internally with explicit bounds checks to avoid `stack too deep` failures. Do not change production ABI widths without checking call sites.
- **Tests required**: all code changes ship with tests; prefer real value-moving flows over synthetic shortcuts.
- **Commits**: Conventional Commits (`feat(scope): …`), title ≤72 chars, present tense, with a bulleted body explaining what/where/how/why.

---

## License

Source files are marked `BUSL-1.1` (Business Source License 1.1). See individual file headers for the authoritative license declaration.
