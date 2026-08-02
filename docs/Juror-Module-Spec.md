# Juror Module Specification

**Status:** Draft
**Date:** 2026-05-18
**Author:** Eve (for Matt)
**System:** Eves Market — OBR (Optimistic Bond-then-Resolve) Resolution Layer

---

## 1. Overview

The Juror Module introduces a curated, incentivized jury pool for OBR market resolution. Rather than open token-weighted voting, high-stakes or disputed markets are resolved by a randomly selected subset of bonded jurors who have skin in the game.

**Core thesis:** Economic stake + random selection + slashing = credible decentralized resolution without governance capture.

---

## 2. Key Parameters

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| **Juror Cap** | 150 slots | Large enough for diffusion of influence; small enough for coordination |
| **Mint Fee** | 100 USDC | Anti-spam floor; creates sunk cost |
| **Stake Requirement** | 100,000 EVE minimum | Real economic bond (~$10 at current prices, scales with token) |
| **Exit Queue** | 7 days | Friction against strategic exit before controversial votes |
| **Yield Source** | Protocol trading fees | Sustainable, non-dilutive |
| **Selection per Market** | TBD (recommend 11 or 21) | Odd number to prevent ties; large enough for statistical integrity |
| **Vote Deadline** | 72 hours from selection | Sufficient for research; not so long that markets stall |

---

## 3. Juror Lifecycle

### 3.1 Admission

1. **Apply:** User calls `applyForJuror()`
2. **Pay:** 100 USDC mint fee (non-refundable, goes to treasury)
3. **Stake:** 100,000 EVE minimum locked in Juror Module
4. **Mint:** Receive Juror NFT (ERC-721) representing active membership
5. **Activation:** If pool < 150, immediately active. If pool = 150, enter waitlist.

### 3.2 Active State

- Juror is eligible for random selection
- Staked EVE earns marginal yield from protocol fees
- NFT can be transferred/sold on secondary market (transfers stake + rights)

### 3.3 Exit

1. **Initiate:** Call `initiateExit()`
2. **Queue:** 7-day cooldown begins
3. **During Queue:** Still eligible for selection; must participate if selected
4. **Complete:** After 7 days, call `completeExit()` → unstake EVE + burn NFT
5. **Spot Opens:** New juror can mint into the freed slot

### 3.4 Forced Exit (Slashing)

- Triggered by non-participation or protocol-defined violations
- Staked EVE slashed (amount TBD, recommend 10-25%)
- NFT burned
- Spot opens for new mint

---

## 4. Economic Design

### 4.1 Stake as Security

The 100K EVE stake is the *real* security parameter. The $100 USDC mint fee is anti-spam theater by comparison.

**Example:** At $0.001/EVE, stake = $100. At $0.10/EVE, stake = $10,000. The mechanism auto-scales with token appreciation.

**Slashing Math:**
- If slash = 25% of stake, and EVE = $0.001: cost of attack = $25 + opportunity cost
- If EVE = $0.10: cost of attack = $2,500
- This scales with the value of the protocol

### 4.2 Yield Mechanics

**Source:** Fixed percentage of protocol trading fees (recommend 2-5% of fee pool)

**Distribution:**
- Split pro-rata among active jurors
- Accrued continuously, claimable anytime
- Not compounded automatically (gas optimization)

**Target APR:**
- At 150 jurors, if protocol generates $50K/month in fees:
  - 5% to jurors = $2,500/month
  - Per juror = ~$16.67/month = ~$200/year
  - At $100 stake: 200% APR (early days)
  - At $10,000 stake: 2% APR (mature protocol)

This is *marginal* yield — not the primary attraction. The primary attraction is juror NFT scarcity + status.

### 4.3 NFT Secondary Market

Juror NFTs will trade. This is expected and desired:
- Prices reflect expected yield + scarcity premium
- Creates exit liquidity without protocol withdrawal
- Spot transfers preserve total juror count

**Important:** Transferring an NFT transfers the *obligation* — new owner must maintain stake or face slashing.

---

## 5. Random Selection Mechanism

### 5.1 The Problem

True randomness on-chain is hard. Miners/validators can:
- Withhold blocks that produce unfavorable selections
- Influence block hashes used as entropy

### 5.2 Options

| Method | Pros | Cons |
|--------|------|------|
| **Chainlink VRF** | Provably fair, industry standard | Oracle dependency, per-call cost |
| **Commit-Reveal** | No oracle, fully on-chain | 2-step UX, longer resolution time |
| **Block Hash + Future Block** | Simple, free | Miner extractable, less secure |

### 5.3 Recommendation: Hybrid Approach

**Phase 1 (Launch):** Use existing open vote system. Juror pool fills in background.

**Phase 2 (Pool > 50% full):** Implement commit-reveal for selection
- Step 1: Protocol commits to random seed (hash of future block)
- Step 2: After block passes, reveal + select jurors
- Step 3: Selected jurors vote

**Phase 3 (Scale):** Migrate to Chainlink VRF if commit-reveal UX proves too clunky

### 5.4 Selection Algorithm

```solidity
// Pseudocode
function selectJurors(bytes32 seed, uint256 count) internal view returns (uint256[] memory) {
    uint256[] memory selected = new uint256[](count);
    uint256 total = activeJurorCount;

    for (uint i = 0; i < count; i++) {
        uint256 rand = uint256(keccak256(abi.encodePacked(seed, i)));
        uint256 index = rand % total;
        selected[i] = jurorAtIndex(index);
        // Remove selected to prevent duplicates
        swapAndRemove(index, --total);
    }
    return selected;
}
```

---

## 6. Voting Process

### 6.1 Market Resolution Flow

1. **Market closes** (outcome known or deadline reached)
2. **Creator proposes resolution** (YES/NO/Outcome)
3. **Challenge window:** 24 hours for disputes
4. **If no dispute:** Creator's resolution stands
5. **If disputed:** Juror module activates

### 6.2 Juror Voting

1. **Random selection:** 11 or 21 jurors selected
2. **Notification:** Off-chain service alerts jurors (on-chain event emitted)
3. **Research window:** 72 hours to evaluate evidence
4. **Vote:** Submit encrypted vote (commit)
5. **Reveal:** After all votes submitted or deadline passes, reveal
6. **Tally:** Simple majority wins
7. **Reward/Slash:** Participating jurors split reward; non-participants slashed

### 6.3 Vote Commitment

To prevent voting based on others' choices:
- Step 1: Submit `keccak256(vote + salt)`
- Step 2: Reveal actual vote + salt
- If reveal doesn't match commit → slash

---

## 7. Slashing Conditions

### 7.1 Non-Participation (Primary)

- Selected for vote → no commit submitted within 72 hours
- **Penalty:** 25% of staked EVE slashed, NFT burned, spot opens

### 7.2 Failed Reveal

- Committed but failed to reveal within window
- **Penalty:** 10% of staked EVE slashed (less severe — may be technical issue)

### 7.3 Provable Corruption

- Voting against evidence with provable financial interest
- *Note:* Extremely hard to prove on-chain. Rely on economic incentives rather than detection.

### 7.4 No Slash for "Wrong" Vote

Jurors vote their conscience. There is no "correct" answer oracle. The system relies on:
- Random selection (hard to bribe specific jurors)
- Economic stake (expensive to acquire majority)
- Schelling point (honest resolution is the equilibrium)

---

## 8. Phased Launch

### Phase 0: Current System (Now)
- Open token-weighted voting for all markets
- Juror module deployed but inactive
- Jurors can apply and stake

### Phase 1: Pool Filling (0-150 jurors)
- Juror applications open
- Mint fees + staking active
- Yield accrual begins immediately
- Random selection not yet active
- **Disputed markets still use open vote**

### Phase 2: Activation Threshold (≥50 jurors)
- First disputed market triggers juror selection
- Commit-reveal selection activated
- Open vote deprecated for disputed markets
- Juror-only resolution for escalations

### Phase 3: Full Operation (150 jurors)
- All disputed markets use juror resolution
- Optimizations (VRF migration if needed)
- Parameter tuning based on data

---

## 9. Security Considerations

### 9.1 Bribery Attacks

**Cost to bribe majority of 11 jurors:**
- If stake = $100: $550 (trivial — mechanism fails at low prices)
- If stake = $10,000: $55,000 (meaningful)
- **Mitigation:** Minimum stake value check. If 100K EVE < $1,000 equivalent, increase minimum or delay activation.

### 9.2 Sybil Attacks

**Risk:** One person controls multiple juror slots
**Mitigation:**
- Economic cost ($100 + stake per slot)
- 150 cap limits scale
- No perfect defense without KYC (accept tradeoff)

### 9.3 Smart Contract Risk

- Staked EVE locked in module (custody risk)
- Slashing logic must be bulletproof
- Emergency pause for critical bugs

### 9.4 Oracle Risk (if using VRF)

- Chainlink dependency
- Fallback to commit-reveal if VRF fails

---

## 10. Implementation Notes

### 10.1 Smart Contracts Needed

1. **JurorRegistry.sol**
   - Juror admission, exit, staking
   - NFT minting/burning
   - Waitlist management

2. **JurorSelection.sol**
   - Random selection logic
   - Commit-reveal mechanism
   - Integration with dispute system

3. **JurorVoting.sol**
   - Vote submission and tallying
   - Reward distribution
   - Slashing execution

4. **JurorYieldDistributor.sol**
   - Fee collection from protocol
   - Pro-rata distribution to jurors
   - Claim mechanism

### 10.2 Off-Chain Components

- **Notification service:** Alert selected jurors (email/Telegram/Discord)
- **Evidence aggregation:** Pull IPFS docs, market context for juror review
- **Monitoring:** Track participation rates, slash events

### 10.3 Gas Optimization

- Batch juror selection
- Merkle drops for yield distribution
- NFT transfers should update stake tracking efficiently

---

## 11. Open Questions

1. **Exact selection count:** 11 vs 21? (11 = faster, cheaper; 21 = more robust)
2. **Slash percentage:** 25% feels right but needs modeling
3. **Yield percentage:** 2-5% of fees? Need revenue projections
4. **KYC markets:** How do jurors handle regulated-market disputes? (Separate juror pool?)
5. **Appeals:** What if juror decision is clearly wrong? Second jury? Protocol fork?
6. **Emergency pause:** Who can pause? Multisig? Timelock?

---

## 12. Success Metrics

- **Juror pool fills to 150:** Within 6 months of activation
- **Participation rate:** >80% of selected jurors vote
- **Slash events:** <5% of selections (some slashing expected and healthy)
- **Resolution time:** Disputed markets resolve within 96 hours
- **No successful bribery:** Zero proven bribery attacks

---

*Next step: Review spec, resolve open questions, begin contract architecture.*
