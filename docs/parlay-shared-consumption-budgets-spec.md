# P2P Parlay Shared Consumption Budgets Spec

**Status:** Draft implementation spec
**Scope:** `src/facets/parlay/*`, `src/libraries/LibParlay.sol`, `src/types/ParlayTypes.sol`, `src/interfaces/IParlayFacet.sol`, deploy selectors/tests
**Motivation:** Let makers/takers publish many parlay offers/requests against one bounded liquidity budget, so any fills consume the shared budget until exhausted.

---

## 1. Problem

Current P2P parlay offers/requests require isolated escrow per posted item.

### Current maker offer flow

```text
postParlayOffer(template, premium, maxPayout, units)
→ maker transfers maxPayout * units into the contract immediately
→ offer.escrowRemaining stores that isolated collateral
```

This is safe but capital-inefficient.

If a maker wants to quote 100 World Cup products, each with `1000` max payout, they need to lock `100,000` even if they only want `10,000` total exposure.

### Current taker request flow

```text
postParlayRequest(template, premium, maxPayout, units)
→ requester transfers premium * units + fee * units into the contract immediately
→ request premium/fee escrow is isolated per request
```

This also over-locks taker capital when a user wants to broadcast many acceptable structures but only spend a fixed total budget.

---

## 2. Goal

Add **shared consumption budgets**:

```text
owner locks X collateral once
owner attaches many offers/requests to that budget
any fill consumes from the budget
fills continue until the budget is exhausted or cancelled
```

This enables:

- makers to blast many priced parlay offers with bounded total max-payout exposure,
- takers to blast many parlay requests with bounded total premium/fee spend,
- World Cup competition maker menus,
- future signed-offer / Merkle-root / session-key evolution,
- future vault-backed / borrow-backed fill-time sourcing.

---

## 3. Design Principles

1. **Preserve current isolated escrow flows.** Existing `postParlayOffer` and `postParlayRequest` remain valid.
2. **MVP is onchain and escrow-backed.** No callbacks or borrowed budget in first version.
3. **Budget consumption is monotonic.** Filled exposure/spend moves from available budget into ticket bucket escrow or paid premium/fees.
4. **Ticket buckets remain settlement source of truth.** Once filled, each ticket bucket has its own `escrowRemaining`; budget is no longer needed for that filled exposure.
5. **Budget cancellation must not affect already minted tickets.** Only unconsumed budget can be withdrawn.
6. **Mode-specific accounting.** Maker payout budgets and taker premium budgets are different risk types.
7. **Do not allow cross-token budgets.** MVP uses the global parlay collateral token only.
8. **Budgets are lifetime consumption caps, not revolving pools.** Consumed budget does not become available again after ticket settlement.

---

## 4. Budget Modes

Add to `ParlayTypes.sol`:

```solidity
enum BudgetMode {
    MakerPayout, // budget backs underwriter max payout escrow for maker-created offers
    TakerSpend   // budget backs requester premium + protocol fee escrow for taker-created requests
}
```

### MakerPayout budget

Used by maker-created offers.

Consumption unit:

```text
maxPayoutPerUnit * unitsFilled
```

When a taker fills a budget-backed maker offer:

```text
budget.available decreases
bucket.escrowRemaining increases
maker receives premium from taker
protocol receives fee from taker
```

### TakerSpend budget

Used by taker-created requests.

Consumption unit:

```text
premiumPerUnit * unitsFilled + underwritingFee * unitsFilled
```

When a maker fills a budget-backed taker request:

```text
budget.available decreases by premium + fee
maker transfers max payout escrow
maker receives premium from consumed budget
protocol fee routes from consumed budget
bucket.escrowRemaining increases from maker escrow
```

---

## 5. Storage Changes

Update `LibParlay.Storage`.

```solidity
struct SharedBudget {
    address owner;
    uint8 mode; // ParlayTypes.BudgetMode
    uint256 deposited;
    uint256 consumed;
    bool active;
}

struct ParlayOffer {
    uint256 templateId;
    address maker;
    uint128 premiumPerUnit;
    uint128 maxPayoutPerUnit;
    uint128 totalUnits;
    uint128 remainingUnits;
    uint256 escrowRemaining;
    uint64 fillDeadline;
    bool active;
    uint256 budgetId; // 0 = isolated escrow, nonzero = shared maker payout budget
}

struct ParlayRequest {
    uint256 templateId;
    address requester;
    uint128 premiumPerUnit;
    uint128 desiredMaxPayoutPerUnit;
    uint128 totalUnits;
    uint128 remainingUnits;
    uint256 premiumEscrowRemaining;
    uint256 feeEscrowRemaining;
    uint64 fillDeadline;
    bool active;
    uint256 budgetId; // 0 = isolated escrow, nonzero = shared taker spend budget
}

struct Storage {
    Config config;
    uint256 nextOfferId;
    uint256 nextRequestId;
    uint256 nextBudgetId;
    mapping(uint256 budgetId => SharedBudget budget) budgets;
    ...existing mappings...
}
```

Budget IDs use `0` as the isolated-escrow sentinel, so the first shared budget must be created with:

```solidity
budgetId = ++state.nextBudgetId;
```

### Storage compatibility note

This app is still staging/testnet, so direct struct extension is acceptable if redeploying. If preserving deployed storage is required, append new fields only and verify layout. Since structs are in diamond storage mappings, adding fields at the end of structs is the least invasive path, but still requires careful upgrade tests.

---

## 6. View Types

Extend `ParlayTypes` views:

```solidity
struct SharedBudgetView {
    uint256 budgetId;
    address owner;
    uint8 mode;
    uint256 deposited;
    uint256 consumed;
    uint256 available;
    bool active;
}
```

Add to `ParlayOfferView`:

```solidity
uint256 budgetId;
```

Add to `ParlayRequestView`:

```solidity
uint256 budgetId;
```

Optional helper fields:

```solidity
uint256 budgetAvailable;
bool budgetBacked;
```

---

## 7. Events

Add to `Events.sol`:

```solidity
event ParlayBudgetCreated(
    uint256 indexed budgetId,
    address indexed owner,
    uint8 indexed mode,
    uint256 deposited
);

event ParlayBudgetFunded(
    uint256 indexed budgetId,
    address indexed owner,
    uint256 amount,
    uint256 deposited
);

event ParlayBudgetConsumed(
    uint256 indexed budgetId,
    uint256 indexed sourceId,
    uint8 indexed sourceType,
    uint256 amount,
    uint256 consumed,
    uint256 available
);

event ParlayBudgetCancelled(
    uint256 indexed budgetId,
    address indexed owner,
    uint256 refunded
);

event ParlayBudgetOfferPosted(
    uint256 indexed offerId,
    uint256 indexed budgetId,
    uint256 indexed templateId,
    address maker,
    uint128 premiumPerUnit,
    uint128 maxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
);

event ParlayBudgetRequestPosted(
    uint256 indexed requestId,
    uint256 indexed budgetId,
    uint256 indexed templateId,
    address requester,
    uint128 premiumPerUnit,
    uint128 desiredMaxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
);
```

Existing `ParlayOfferFilled` / `ParlayRequestFilled` can remain unchanged because they already emit `escrowLocked`, premium, and fee. The budget-consumption event links fills to budget usage.

---

## 8. Errors

Add to `Errors.sol`:

```solidity
error ParlayBudgetNotFound(uint256 budgetId);
error ParlayBudgetInactive(uint256 budgetId);
error ParlayBudgetWrongOwner(address caller, address owner);
error ParlayBudgetWrongMode(uint8 expected, uint8 actual);
error ParlayBudgetInsufficient(uint256 required, uint256 available);
error ParlayBudgetLinked(uint256 budgetId);
```

`ParlayBudgetLinked` is optional if we later track open offer/request counts and want to block cancellation while sources remain active. MVP can allow cancellation anytime because fills check `active` and available budget.

---

## 9. External API

Add a new facet, preferred:

```text
ParlayBudgetFacet.sol
```

or add to `ParlayUnderwritingFacet` if selector count is manageable.

### Budget lifecycle

```solidity
function createParlayBudget(ParlayTypes.BudgetMode mode, uint256 amount)
    external
    nonReentrant
    returns (uint256 budgetId);

function fundParlayBudget(uint256 budgetId, uint256 amount)
    external
    nonReentrant;

function cancelParlayBudget(uint256 budgetId)
    external
    nonReentrant
    returns (uint256 refunded);

function getParlayBudget(uint256 budgetId)
    external
    view
    returns (ParlayTypes.SharedBudgetView memory);
```

MVP ownership rules:

- `createParlayBudget` sets `owner = msg.sender`.
- `fundParlayBudget` requires `msg.sender == budget.owner`.
- `cancelParlayBudget` requires `msg.sender == budget.owner`.
- `cancelParlayBudget` is terminal: inactive budgets cannot be funded or reactivated.

### Budget-backed posting

```solidity
function postParlayOfferFromBudget(
    uint256 budgetId,
    uint256 templateId,
    uint128 premiumPerUnit,
    uint128 maxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
) external nonReentrant returns (uint256 offerId);

function postParlayRequestFromBudget(
    uint256 budgetId,
    uint256 templateId,
    uint128 premiumPerUnit,
    uint128 desiredMaxPayoutPerUnit,
    uint128 units,
    uint64 fillDeadline
) external nonReentrant returns (uint256 requestId);
```

### Optional batch posting

For World Cup maker menus:

```solidity
struct BudgetOfferPost {
    uint256 templateId;
    uint128 premiumPerUnit;
    uint128 maxPayoutPerUnit;
    uint128 units;
    uint64 fillDeadline;
}

function postParlayOffersFromBudgetBatch(uint256 budgetId, BudgetOfferPost[] calldata posts)
    external
    nonReentrant
    returns (uint256[] memory offerIds);
```

Analogous `BudgetRequestPost` for takers.

---

## 10. Budget Accounting Helpers

Add to `ParlayBase` or `LibParlay`.

```solidity
function _requireBudget(
    LibParlay.Storage storage state,
    uint256 budgetId
) internal view returns (LibParlay.SharedBudget storage budget);

function _availableBudget(LibParlay.SharedBudget storage budget)
    internal
    view
    returns (uint256 available)
{
    available = budget.deposited - budget.consumed;
}

function _consumeBudget(
    LibParlay.SharedBudget storage budget,
    uint256 budgetId,
    uint256 sourceId,
    uint8 sourceType,
    uint8 expectedMode,
    uint256 amount
) internal {
    if (!budget.active) revert Errors.ParlayBudgetInactive(budgetId);
    if (budget.mode != expectedMode) revert Errors.ParlayBudgetWrongMode(expectedMode, budget.mode);
    uint256 available = budget.deposited - budget.consumed;
    if (amount > available) revert Errors.ParlayBudgetInsufficient(amount, available);
    budget.consumed += amount;
    emit Events.ParlayBudgetConsumed(budgetId, sourceId, sourceType, amount, budget.consumed, available - amount);
}
```

---

## 11. Fill Logic Changes

### Current `_fillParlayOffer`

Current code assumes maker escrow already exists on the offer:

```solidity
result.escrowLocked = uint256(offer.maxPayoutPerUnit) * units;
offer.remainingUnits -= units;
offer.escrowRemaining -= result.escrowLocked;
...
_mintIntoBucket(..., result.escrowLocked, receiver);
```

### New `_fillParlayOffer`

Pseudo:

```solidity
result.escrowLocked = uint256(offer.maxPayoutPerUnit) * units;

if (offer.budgetId == 0) {
    offer.escrowRemaining -= result.escrowLocked;
} else {
    LibParlay.SharedBudget storage budget = _requireBudget(state, offer.budgetId);
    _consumeBudget(
        budget,
        offer.budgetId,
        offerId,
        uint8(ParlayTypes.SourceType.Offer),
        uint8(ParlayTypes.BudgetMode.MakerPayout),
        result.escrowLocked
    );
}

offer.remainingUnits -= units;
if (offer.remainingUnits == 0) offer.active = false;

collateralToken.safeTransferFrom(msg.sender, address(this), premium + fee);
if (premium != 0) collateralToken.safeTransfer(offer.maker, premium);

_mintIntoBucket(..., result.escrowLocked, receiver);
_routeFlatFee(...);
```

Budget-backed maker offers do **not** decrement `offer.escrowRemaining`, because the offer did not hold isolated escrow. The locked payout moves directly from budget availability into the ticket bucket accounting.

Important invariant:

```text
contract collateral balance = sum(unconsumed active budget deposits) + sum(ticket bucket escrow) + isolated request premium/fee escrow + isolated offer escrow + other transient balances
```

Budget `consumed` should not imply funds leave the contract. It means funds are no longer withdrawable by budget owner because they now back minted ticket buckets.

### Current `_fillParlayRequest`

Current code assumes requester premium/fee escrow exists on request:

```solidity
request.premiumEscrowRemaining -= premium;
request.feeEscrowRemaining -= fee;
collateralToken.safeTransferFrom(msg.sender, address(this), escrowLocked);
if (premium != 0) collateralToken.safeTransfer(msg.sender, premium);
_mintIntoBucket(..., escrowLocked, request.requester);
_routeFlatFee(..., fee);
```

### New `_fillParlayRequest`

Pseudo:

```solidity
result.premium = uint256(request.premiumPerUnit) * units;
result.fee = uint256(config.underwritingFee) * units;
result.escrowLocked = uint256(request.desiredMaxPayoutPerUnit) * units;

if (request.budgetId == 0) {
    request.premiumEscrowRemaining -= result.premium;
    request.feeEscrowRemaining -= result.fee;
} else {
    LibParlay.SharedBudget storage budget = _requireBudget(state, request.budgetId);
    _consumeBudget(
        budget,
        request.budgetId,
        requestId,
        uint8(ParlayTypes.SourceType.Request),
        uint8(ParlayTypes.BudgetMode.TakerSpend),
        result.premium + result.fee
    );
}

request.remainingUnits -= units;
if (request.remainingUnits == 0) request.active = false;

collateralToken.safeTransferFrom(msg.sender, address(this), result.escrowLocked);
if (result.premium != 0) collateralToken.safeTransfer(msg.sender, result.premium);
_mintIntoBucket(..., result.escrowLocked, request.requester);
_routeFlatFee(..., result.fee);
```

Budget-backed taker requests do **not** decrement request-level premium/fee escrow.

---

## 12. Posting Logic

### `postParlayOfferFromBudget`

Validation:

1. budget exists
2. budget owner is `msg.sender`
3. budget active
4. budget mode is `MakerPayout`
5. template exists and fillable
6. terms match template max payout
7. implied maximum source exposure does not have to be available at post time if we allow over-posting against the budget

Decision: **allow over-posting**.

Reason: the whole point is letting a maker publish many offers against one budget. Fills enforce available budget. Posting should not reserve against budget.

Race behavior: over-posted budget-backed offers are best-effort quotes. If multiple fills race for the same remaining budget, whichever transaction consumes availability first wins and later transactions revert with `ParlayBudgetInsufficient` or `ParlayBudgetInactive`.

Store offer:

```solidity
escrowRemaining = 0;
budgetId = budgetId;
```

Emit both:

- `ParlayOfferPosted` for compatibility, with same terms
- `ParlayBudgetOfferPosted` for budget linkage

### `postParlayRequestFromBudget`

Same concept.

Validation:

1. budget owner is `msg.sender`
2. budget mode is `TakerSpend`
3. terms valid
4. over-posting allowed

Race behavior is identical to maker offers: requests are visible intents against last-known budget availability, not guaranteed fills.

Store request:

```solidity
premiumEscrowRemaining = 0;
feeEscrowRemaining = 0;
budgetId = budgetId;
```

---

## 13. Cancellation Semantics

### Cancel isolated offer/request

Existing behavior unchanged.

### Cancel budget-backed offer

Cancels only the offer:

```text
offer.remainingUnits = 0
offer.active = false
escrowReturned = 0
```

No budget refund occurs because no offer-specific escrow was reserved.

### Cancel budget-backed request

Cancels only the request:

```text
request.remainingUnits = 0
request.active = false
premiumReturned = 0
feeReturned = 0
```

No budget refund occurs.

### Cancel budget

`cancelParlayBudget`:

```text
refund = deposited - consumed
active = false
deposited = consumed // or leave deposited and use active=false + consumed tracking
transfer refund to owner
```

After budget cancellation, existing budget-backed offers/requests remain in storage but cannot fill because `_consumeBudget` reverts inactive.

Cancellation is terminal in MVP. A cancelled budget cannot be funded again and cannot be reactivated. Users who want more shared liquidity create a new budget.

Consumed funds are not refunded through budget cancellation. They have already moved into ticket bucket escrow or paid premium/fee flows.

Settlement note:

```text
Shared budgets are lifetime consumption caps, not reusable revolving pools.
If a maker-budget-backed ticket settles below max payout, unused ticket escrow returns to the ticket bucket underwriter address, not to budget.available.
```

This matches the existing settlement model where finalized ticket buckets return unused escrow to `bucket.underwriter`.

Optional V2 cleanup:
- track budget offer IDs and request IDs for UI cancellation.
- expose budget sources.

MVP can rely on views/indexer/events.

---

## 14. View / Indexer Requirements

Need UI/indexer to answer:

- show all active offers attached to budget,
- show all active requests attached to budget,
- show budget deposited/consumed/available,
- show potential exposure if all open offers filled,
- show over-posting ratio:

```text
sum(max remaining offer exposure) / available budget
```

This ratio is useful for makers:

```text
10k budget, 250k visible offer exposure = 25x quote fanout
```

---

## 15. Invariants

### Budget invariants

1. `budget.consumed <= budget.deposited` always.
2. `available = deposited - consumed`.
3. `cancelParlayBudget` can only transfer `available`.
4. A budget-backed fill must consume budget before minting ticket.
5. A budget-backed fill must revert if budget inactive.
6. A budget-backed fill must revert if mode mismatch.
7. Budget cancellation must not reduce ticket bucket escrow.

### Offer/request invariants

8. Isolated offer escrow behavior unchanged.
9. Isolated request premium/fee escrow behavior unchanged.
10. Budget-backed offer has `escrowRemaining == 0` before and after fills.
11. Budget-backed request has `premiumEscrowRemaining == 0` and `feeEscrowRemaining == 0` before and after fills.
12. `remainingUnits` remains the per-source fill cap independent of budget availability.
13. Budget-backed offers/requests may be over-posted; fill-time budget availability is authoritative.

### Ticket bucket invariants

14. `bucket.escrowRemaining` increases by max payout exposure on fill.
15. `bucket.escrowRemaining` is the only settlement backing for minted tickets.
16. Finalization/claim logic does not read budgets.
17. Cancelled budgets cannot affect finalized or unfinalized buckets.

### Token-balance invariant

For parlay collateral held by contract:

```text
balance >=
  sum(active budget available)
+ sum(ticket bucket escrowRemaining)
+ sum(isolated active offer escrowRemaining)
+ sum(isolated active request premiumEscrowRemaining + feeEscrowRemaining)
```

This can be hard to assert globally onchain due mappings, but tests should track created records and assert conservation.

---

## 16. Test Plan

### Unit tests

1. Create maker budget.
2. Fund maker budget.
3. Post 3 offers from same budget with total possible exposure > budget.
4. Fill offer A partially.
5. Assert budget consumed/available.
6. Fill offer B until budget nearly exhausted.
7. Attempt fill offer C exceeding available budget: revert.
8. Cancel budget: only available refunds.
9. Existing ticket claims still work after budget cancellation.

### Taker budget tests

1. Create taker budget.
2. Post many requests from same budget.
3. Maker fills request A.
4. Assert premium paid to maker from budget.
5. Assert fee routes from budget through the configured vault/fee-recipient split.
6. Assert maker escrow transfer still required.
7. Attempt fill beyond remaining spend: revert.
8. Cancel budget and ensure remaining spend refunds.
9. Assert cancelled budgets cannot be funded or reactivated.

### Race/terminal-state tests

1. Two offers over-post one maker budget.
2. Fill the first offer up to available budget.
3. Attempt to fill the second offer beyond remaining budget: revert.
4. Cancel a partially consumed budget.
5. Attempt to fill any linked offer/request: revert inactive.
6. Finalize/claim an already minted ticket after budget cancellation: succeeds.

### Existing compatibility tests

Run existing parlay tests unchanged:

```bash
forge test --match-path test/unit/ParlayFacet.t.sol
```

Add new tests, likely:

```text
test/unit/ParlaySharedBudget.t.sol
```

### Fuzz/property tests

- random fills across N offers never exceed budget.
- cancellation refunds exactly deposited - consumed.
- bucket escrow equals sum consumed maker exposure from fills plus maker escrow from request fills.
- no budget-backed source has isolated escrow underflow.

---

## 17. Suggested Implementation Order

1. Extend `ParlayTypes` with `BudgetMode` and `SharedBudgetView`.
2. Extend `LibParlay` storage:
   - `nextBudgetId`
   - `budgets`
   - `budgetId` fields on offers/requests
3. Add events/errors.
4. Add `ParlayBudgetFacet`:
   - create/fund/cancel/get budget
   - post offer from budget
   - post request from budget
5. Modify `_fillParlayOffer` for budget-backed offers.
6. Modify `_fillParlayRequest` for budget-backed requests.
7. Modify view facet to return budget IDs.
8. Add interface selectors and deploy script selectors.
9. Add tests.
10. Add UI/indexer support.

---

## 18. MVP vs Later

### MVP: onchain escrowed shared budgets

```text
simple
safe
fast to ship
works for World Cup competition
```

### V2: signed budget offers

Add EIP-712/Merkle-root offer sets:

```text
maker signs many offer leaves against budgetId
fills bring proof/signature
no onchain post for every offer
```

### V3: position/vault-backed callback budgets

Budget can reference position/vault/borrow capacity:

```text
positionId
maxExposure
sessionKeyPolicy
fill-time source action
```

On fill:

```text
borrow/withdraw/source collateral
lock ticket escrow
mint ticket
consume budget
```

This is the Midnight/EqualLend/EqualFi synthesis.

---

## 19. Product UX

### Maker flow

```text
Create Underwriting Budget
- deposit 10,000 test eveUSD
- choose Maker Payout Budget

Build offer menu
- Favorites Sweep
- Underdog Chaos
- Canada Moonshot
- 3/5 Ladder
- single-leg longshots

All offers visible.
Any fill consumes the same 10,000 budget.
```

### Taker flow

```text
Create Betting Budget
- deposit 500 test eveUSD
- choose Taker Spend Budget

Post many desired tickets
- Brazil thesis
- Argentina thesis
- single-leg moonshot
- group chaos

Any maker fill consumes spend budget.
```

### Competition leaderboard hooks

Budget-aware metrics:

- total maker budget posted
- quote fanout ratio
- budget utilization
- underwriting PnL per consumed budget
- taker request fill rate
- most efficient underwriter

---

## 20. Summary

Shared consumption budgets turn P2P parlays from isolated escrow tickets into an intent/risk marketplace.

Instead of forcing makers and takers to lock capital per offer/request, users lock one budget and broadcast many acceptable deals. Fills consume the budget until exhausted.

This is the missing capital-efficiency bridge between:

- current P2P parlay underwriting,
- EqualLend Direct tranche/encumbrance accounting,
- Morpho Midnight shared offer consumption,
- future EqualFi Position NFT agent businesses.
