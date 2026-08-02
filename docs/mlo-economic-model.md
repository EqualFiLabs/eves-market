# EvePredict MLO Economic Model

**Status:** Current source baseline through the net-funded ASK implementation (2026-07-13)
**Launch asset:** `eveUSDC`
**Scope:** Economic and accounting rules implemented by the launch MLO quote and
execution surface. Funding, recovery, and insurance are implemented; deployment and
adversarial verification phases remain specified but
not implemented unless stated below.

## 1. Terminology And Units

- **Share notional** is the number of outcome shares in an execution, denominated in
  the launch asset's internal units.
- **Gross proceeds** are the taker's payment received by an ASK execution, excluding
  trade fees.
- **Gross payment** is the maker's payment to the seller in a BID execution, excluding
  trade fees.
- **Debt** is the remaining Senior principal attributable to a fill after the taker's
  gross cash flow. It is not maker profit and it is not a fee.
- **Inventory payout** is the resolution-specific value of outcome tokens held by the
  bucket.
- **Signed loss** is `debt - inventory payout`. Positive values require collateral;
  negative values are scenario profit. A vector has one entry for every valid outcome
  and one final entry for invalid resolution.
- **Maximum scenario loss** is `max(0, maximum signed loss)` across an aggregate vector.
- **Open reservation loss** is positive-clipped per quote and per scenario. An
  unfilled quote's possible profit never offsets another optional quote's loss.
- **Filled position loss** remains signed because executed debt and inventory are
  real positions that can economically offset across mutually exclusive outcomes.
- **Initial margin (IM)** and **maintenance margin (MM)** are requirements, not losses.
  They are rounded up after applying their basis-point rate.
- The scenario vector is the single representation of position loss for this model.
  Senior debt must not be added again as a separate position-loss term.

All examples below use 18-decimal integer units. Native multi-outcome markets support
2 through 16 valid outcomes. The invalid scenario is always appended after the valid
outcome entries.

## 2. Scenario Formulas

For `N` valid outcomes, outcome index `k`, share amount `S`, and actual cash amount `C`:

### ASK

For a fresh ASK with no reusable inventory or prior market debt, taker gross proceeds
fund the priced portion of the complete-set split and Senior deploys only the remaining
net deficit. The bucket retains every complementary outcome token.

```text
grossProceeds = ceil(S * executionPrice / D)
seniorDeployed = S - grossProceeds
debt = seniorDeployed
valid payout[i] = 0       when i == k
                 S       otherwise
invalid payout = (N - 1) * floor(S / N)
loss[i] = debt - valid payout[i]
loss[invalid] = debt - invalid payout
```

The invalid remainder is not presumed redeemable. Its effect is included in loss.

For an inventory-first fill, let `I` be sold-outcome inventory consumed, `U = S - I`
be newly manufactured shares, `priorDebt` be debt before the fill, and `C` be total
gross proceeds:

```text
splitContribution = ceil(U * executionPrice / D)
seniorDeployed = U - splitContribution
repaymentCash = C - splitContribution
debtAfter = max(0, priorDebt + seniorDeployed - repaymentCash)
makerProfitBeforeFunding = max(0, repaymentCash - priorDebt - seniorDeployed)
```

Only the fresh Senior-backed portion creates complementary inventory. After the fill,
the market scenario vector is rebuilt from `debtAfter` and the bucket's actual aggregate
per-outcome vault inventory. This aggregate reconciliation, rather than the fresh-fill
formula above, is authoritative when inventory or prior debt exists.

### BID

Senior pays the seller's gross payment and the bucket receives the bought outcome token.

```text
debt = grossPayment
valid payout[i] = S       when i == k
                 0       otherwise
invalid payout = floor(S / N)
loss[i] = debt - valid payout[i]
loss[invalid] = debt - invalid payout
```

The executed vector receives the actual gross proceeds or payment. It never recomputes
settlement from a displayed price.

### Reservation cash

At a price bound `P` and denominator `D`, the maker bears quote rounding:

```text
ASK cash = ceil(S * minimumPrice / D)
BID cash = ceil(S * maximumPrice / D)
ASK Senior reservation = unbackedShares - ASK cash
```

Posted curve price is bounded to `0 < P <= D`, `D > 0`, and supported amounts are
bounded so the conversion to signed scenario entries is safe. Zero rounded cash is
valid for a positive minimum-unit price; zero shares are not.

## 3. Worked Examples

### Binary ASK: 100 YES at 0.40

`S = 100`, `grossProceeds = 40`, and `debt = 60`.

```text
YES wins:    60 loss
NO wins:    -40 profit
Invalid:     10 loss   (60 - floor(100 / 2))
Vector: [60, -40, 10]
IM at 10,000 bps: 60
```

### Binary BID: 100 YES at 0.40

`grossPayment = 40` and `debt = 40`.

```text
YES wins:   -60 profit
NO wins:     40 loss
Invalid:    -10 profit  (40 - floor(100 / 2))
Vector: [-60, 40, -10]
IM at 10,000 bps: 40
```

### Four-way examples

For 100 shares of outcome 0 at 0.20, an ASK vector is:

```text
[80 loss, -20 profit, -20 profit, -20 profit, 5 invalid loss]
```

The invalid retained payout is `3 * floor(100 / 4) = 75`. The BID vector for the same
quote is:

```text
[-80 profit, 20 loss, 20 loss, 20 loss, -5 invalid profit]
```

### Partial fill and cancellation

Start with a binary ASK envelope for 100 shares at a minimum price of 0.40. Fill 30
shares at an actual price of 0.45, receiving 13.5, and retain a 70-share reservation
at 0.40, receiving 28 in the envelope calculation.

```text
Filled vector:        [16.5, -13.5, 1.5]
Remaining raw vector: [42, -28, 7]
Stored open reserve:  [42, 0, 7]
Combined envelope:    [58.5, -13.5, 8.5]
After cancellation:   [16.5, -13.5, 1.5]
```

Cancellation releases only the remaining reservation. It does not erase the filled
position or its active scenario vector.

## 4. Domains And Aggregation

Every outcome book for one market belongs to one market-level risk domain. A maker's
ASK and BID exposure across those books is aggregated in two layers:

```text
openLoss[i] = sum(max(each unfilled quote loss[i], 0))
filledPositionLoss[i] = sum(each executed signed loss[i])
aggregatePositionLoss[i] = openLoss[i] + filledPositionLoss[i]
```

This prevents two independently optional quotes from manufacturing collateral relief.
Once fills execute, their real debt and inventory may net across mutually exclusive
outcomes. For example, unfilled binary YES and NO asks for 100 shares each at 0.40 store
open loss `[60, 60, 20]`, not `[20, 20, 20]`. If both execute, their signed filled
positions aggregate to `[20, 20, 20]`.

Independent market or domain requirements are additive. They are not netted merely
because a maker owns the same margin account. A mutually exclusive group can use a
maximum-over-group calculation only after an explicit, separately proven mapping
establishes that exactly one group's scenarios can occur. A missing, stale, or ambiguous
mapping falls back to independent additive requirements.

The position vector does not add Senior debt again. Debt is already the first term in
every scenario loss. For accrued unpaid funding `F`, effective loss is:

```text
effectiveLoss[i] = aggregatePositionLoss[i] + F
```

Funding is uniform positive loss across every scenario and remains a distinct ledger.
It must be added exactly once to effective loss, never added again as debt or another
position term. Funding payment reduces `F` uniformly, so paying `Q` changes every
effective entry to `aggregatePositionLoss[i] + (F - Q)`.

## 5. Launch Risk Parameters

```text
Launch asset:                 eveUSDC
Initial margin:               10,000 bps (100% of true maximum scenario loss)
Maintenance margin:            9,000 bps (90% of true maximum scenario loss)
Valid outcome count:           2 through 16
Invalid scenario:              one entry after the valid outcomes
Insurance in pretrade IM:      no
Insurance in quote capacity:   no
```

At 0.40, both binary examples require less than gross share notional at 100% IM. IM
equals gross notional only when the actual maximum signed loss equals gross notional,
such as a zero-price ASK or a full-price BID in the fixed examples.

## 6. Ledger Definitions And Transitions

The following entries define the required debits and credits. ASK and BID inventory,
Senior-capital, routing, merge, and current resolution transitions are implemented
through Phase 4. Funding, permissionless recovery, insurance, and the final expanded
resolution waterfall remain later phases.

### Envelope create and update

- Debit maker free `eveUSDC` margin by the new initial requirement, including current
  accrued and pending funding uniformly in every scenario.
- Credit maker committed scenario margin and the envelope's remaining reservation.
- Reserve, but do not deploy, the Senior capital needed for the permitted envelope.
- The envelope reserves its maximum volume at its conservative immutable price bound.
  Updating currently displayed volume or prices within those bounds does not change the
  reservation. Fills replace only the consumed portion with their actual signed vector.
- No insurance balance or insurance availability is credited as quote capacity.

### Fill

- ASK: consume inventory explicitly reserved to the curve first. For any deficit, debit
  Senior available capital by only that deficit, split collateral into outcome tokens,
  transfer the sold outcome to the taker, and credit the complementary outcome to bucket
  inventory. Gross proceeds repay at most outstanding Senior principal; any remainder is
  realized maker profit backed by cash already held by the Diamond.
- BID: debit Senior available capital by gross payment; credit deployed principal;
  pay the seller; credit the bought outcome token to bucket inventory; update debt and
  the executed vector.
- Debit remaining open-order reservation by the filled envelope amount and credit the
  corresponding active position vector. Fees are separate revenue entries.
- Rebuild the filled position vector from actual `Senior debt - scenario inventory
  payout`; do not infer debt from displayed price or gross notional.

### Cancel or expiry

- Debit only the remaining open-order reservation and committed margin.
- Credit that released amount to maker free margin and Senior unreserved capacity.
- Leave filled inventory, deployed principal, debt, and active position risk untouched.
- Expiry is a permissionless state transition with a bounded release. A caller reward
  must be separately configured if cleanup requires a third party.

### Inventory transfer and merge

- Each executable curve earmarks sold-outcome inventory before Senior capital. Global
  reserved inventory for a bucket/market equals the sum of its curve reservations and
  may never exceed vault custody.
- Transfer entries debit the curve reservation and bucket inventory, then transfer the
  exact token amount from the isolated vault to the taker.
- A bounded rebalance may replace a curve's Senior reservation with newly available
  inventory. It never increases total curve backing.
- Unreserved complete sets are merged automatically after inventory-changing MLO fills:
  debit every component, credit the collateral redemption proceeds, credit principal
  repaid, and reduce debt. The explicit permissionless merge remains an accelerator.
- A token committed to an executable reservation cannot also be committed elsewhere.
- The Senior Pool bound to existing bucket exposure remains authoritative until both
  market-level reserved capital and active debt reach zero, even if governance changes
  the default pool.

### Funding accrual and payment

- Accrual increases maker funding payable and Senior funding receivable by the same
  amount. It increases every scenario's effective loss uniformly and does not change
  principal repayment or fee revenue.
- Payment reduces maker funding payable by the collected amount and routes real
  `eveUSDC` between Senior revenue and dedicated MLO insurance under the configured
  split. It is never principal repayment. The launch default is 50/50, with integer
  division remainder assigned to insurance.
- A funding payment of `Q` reduces the effective vector uniformly from
  `aggregatePositionLoss[i] + F` to `aggregatePositionLoss[i] + (F - Q)`.
- Accrual is lazy and bounded to the transition's configured interval; no unbounded
  scan is required.

### Recovery

- Every relevant MLO mutation lazily accrues funding and derives health from current
  onchain accounting; explicit synchronization is only an acceleration surface.
- Immediate and delayed routes may clean encountered expired, resolved, or recovering
  curves within their existing bounded route input.
- Debit recovered inventory proceeds first against the relevant debt and vector loss.
- Debit maker slashable margin for the remaining realized loss.
- Recovery cleanup is permissionless and carries no maker bond or caller reward.
  Protocol keepers may execute the same bounded transition.
- Recovery must not draw insurance before inventory proceeds and maker margin are used.

### Resolution settlement

- A protocol keeper submits one permissionless bucket settlement after resolution;
  it supplies no discretionary price, outcome, loss, or waterfall input.
- Debit winning inventory or redemption proceeds and credit principal repayment.
- Debit maker margin for the remaining realized loss.
- Draw the dedicated insurance reserve only for the remaining realized loss after the
  first two sources.
- Credit any residual to Senior realized loss and reduce Senior NAV exactly once.
- Clear settled principal debt, active scenario vectors, and inventory commitments.
  Uncollectible funding is written off in a separate bad-debt ledger and never consumes
  principal insurance. Invalid dust remains in the loss calculation unless an explicit
  redemption rule proves it is recoverable.
- A repeated settlement of the same closed bucket is a no-op and cannot duplicate
  transfers, insurance draws, funding writeoffs, or Senior losses.

## 7. Senior And Insurance Ledgers

Senior accounting keeps these buckets distinct:

| Ledger | Meaning |
|---|---|
| Reserved capital | Capacity earmarked for an unfilled envelope |
| Deployed principal | Full capital actually drawn for a fill |
| Principal repaid | Gross proceeds, redemption, or other principal return |
| Funding receivable | Funding owed by makers before collection |
| Funding paid | Funding cash actually split between Senior revenue and insurance |
| Revenue/fees | Fees and revenue; never silently principal repayment |
| Realized loss | Final loss after inventory, maker margin, and insurance |

Insurance is a dedicated `eveUSDC` MLO insurance contract or fund outside
SeniorCapitalPool ownership. Its ledgers distinguish balance, inflow, draw, and
remaining availability.
Insurance is not quote capacity and cannot lower initial margin. The loss waterfall is:

```text
inventory proceeds -> maker margin -> dedicated MLO insurance -> Senior realized loss
```

The waterfall is a settlement ordering, not a pretrade solvency shortcut.

## 8. Recovery Execution

Recovery is a bounded permissionless transition with no additional maker bond. A maker
below initial margin enters reduce-only mode and may return to healthy after curing the
deficit. A maker below maintenance enters irreversible recovery. While recovering, any
caller can cancel caller-supplied curve IDs and release reservations; the protocol may
operate a keeper over the same public surface. Unresolved inventory stays in custody
until resolution rather than being sold through a privileged liquidation venue.
Terminal settlement is explicit protocol maintenance because a resolved market may
have an unbounded number of maker buckets. The keeper processes one bucket per call;
the contract remains permissionless so keeper operation is a liveness service rather
than an accounting authority.

## 9. Margin Accounting Authority

Margin policy remains owner/governance-configurable, including assets, risk parameters,
marks, oracles, and funding rates. Operational ledger mutation has no external manager:
only installed Diamond facet code can invoke the internal risk and margin libraries.
Senior Pool and MLO insurance retain separate Diamond-authorized risk-manager fields
because they are external contracts authenticating cross-contract calls.

## 10. Bounded-Gas Requirements

- Envelope updates validate fixed-size metadata and do not scan all maker envelopes.
- A market vector has at most 17 entries.
- Recovery processes a bounded batch selected by the caller and does not scan all
  buckets, curves, markets, or inventory.
- Resolution settlement processes one explicit bucket and market per call.
- Health checks use stored aggregates or bounded deltas. They never depend on an
  unbounded health scan.
- Inventory reservation, rebalance, fill, and merge touch one curve and one fixed-size
  market ledger. None scans all maker curves.

## 11. Machine-Checkable Invariants

The Phase 1 math, Phase 2 scenario engine, Phase 3 inventory ledger, and Phase 4
execution surface establish these invariants:

1. Valid outcome counts are 2 through 16, and the outcome index is less than the count.
2. Supported shares, cash, prices, and denominators fit the bounded amount domain;
   cash never exceeds shares and price never exceeds its denominator.
3. ASK reservation cash ceils `shares * minimumPrice / denominator`; BID reservation
   cash ceils `shares * maximumPrice / denominator`.
4. Every scenario entry equals debt minus that scenario's inventory payout.
5. Invalid ASK payout is `(N - 1) * floor(shares / N)`; invalid BID payout is
   `floor(shares / N)`.
6. Optional open quotes positive-clip each scenario entry before aggregation; executed
   positions sum signed entries element by element before maximum-loss selection.
7. Required margin is `ceil(max(0, maximum signed loss) * marginBps / 10,000)`.
8. At 10,000 bps, required margin is below gross share notional whenever the true
   maximum loss is below that notional, and equals it when the true maximum loss equals it.
9. Cancellation removes only remaining open-order risk.
10. Effective loss equals position loss plus accrued unpaid funding in every scenario.
11. Funding accrual increases every effective-loss entry uniformly; payment reduces every
    entry uniformly and reduces both funding ledgers by the same amount.
12. Senior debt and funding are not added to scenario loss a second time.
13. Insurance cannot increase pretrade capacity or reduce initial margin.
14. Senior realized loss is recorded once, after inventory, maker margin, and insurance.
15. No token inventory or Senior reservation unit is pledged twice.
16. Curve inventory plus conservative taker proceeds plus net Senior backing is
    conserved across create, fill, rebalance, and cancel.
17. Per-market Senior debt equals the pool bucket's active exposure, and per-market
    Senior reservation equals the pool bucket's reserved capital.
18. Recorded per-outcome inventory equals CTF or native ERC-1155 custody in the isolated
    vault; complete-set merge reduces every outcome and Senior debt exactly once.
19. ASK Senior reservation uses the envelope minimum price, each fill combines
    rounded-up gross proceeds with only the net Senior deficit needed to manufacture
    positions, and unused bound surplus is released. BID Senior reservation uses the
    envelope maximum price, while each fill deploys only its actual gross payment.
20. Direct and delayed route execution preserve the economic taker/seller while using
    the Diamond as custody source only for already escrowed delayed-order assets.
21. Native collateral retained by the Diamond equals the explicit collateral liability
    backing live native positions; mint, complete-set merge, and redemption update it
    exactly once.

The independent test reference deliberately does not call the production library.
The focused suite covers fixed examples, fuzz comparisons, rounding, invalid dust,
maximum supported values, price boundaries, margin rounding, and invalid inputs.
