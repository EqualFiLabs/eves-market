# SFD Commit-Reveal System Spec

## What This Is

The Commit-Reveal (C/R) system is an **integrity engine** for the Eves Market Short-Form Drama (SFD) experience. It provides cryptographic proof that a creator did not change episode outcomes after seeing community votes or prediction market bets.

**In plain terms:** Before viewers vote on what happens next, the creator locks in all possible episode variants. After the vote, the creator reveals which variant won — and anyone can verify that the revealed episode matches what was committed before voting started.

This separates the creator's role (generating content) from the community's role (choosing direction) while preserving trust.

---

## Overview

| Property | Value |
|----------|-------|
| **Purpose** | Prove creator did not manipulate episode outcomes post-vote |
| **Scope** | SFD narrative votes + prediction market resolution |
| **Type** | External contract (not part of Eves Market Diamond) |
| **Position Token** | None — stores hashes, not financial positions |
| **Access Control** | Creator commits/reveals; anyone verifies |

---

## Architecture

```
External Contract: CommitReveal.sol
├── Commitment storage (mapping marketId → Commitment)
├── commit() — Creator locks variant hashes
├── reveal() — Creator reveals winning index
├── verify() — Anyone checks content against commitment
└── getCommitment() — Read commitment state

Integration Points:
├── Called by: Creator (off-chain generation → on-chain commit)
├── Read by: Eves Market resolution facet (optional verification hook)
├── Verified by: Community (anyone can audit)
└── Trust model: Transparency, not elimination of insider knowledge
```

**Why external:** The C/R engine is a general-purpose integrity primitive. It may be useful for other creators, protocols, or use cases beyond Eves Market. Keeping it outside the Diamond preserves separation of concerns and allows independent iteration.

---

## Data Model

### Commitment Struct

```solidity
struct Commitment {
    bytes32[] variantHashes;   // keccak256 hashes of all episode variants
    uint256 commitTime;        // block.timestamp of commit
    address creator;           // who committed
    bool revealed;             // has reveal occurred?
    uint256 selectedIndex;     // which variant won (0-indexed)
    bytes32 revealedHash;      // hash of the revealed content
}
```

### Storage

```solidity
mapping(bytes32 => Commitment) public commitments;
// marketId (from Eves Market) → Commitment
```

---

## Functions

### commit

```solidity
function commit(bytes32 marketId, bytes32[] calldata variantHashes) external;
```

**Who:** Market creator only (enforced by Eves Market metadata)
**When:** After generating variants, before opening vote/market
**What:** Stores keccak256 hashes of all possible episode variants
**Cost:** Gas only (no fees)

**Requirements:**
- `variantHashes.length` must match expected variant count (e.g., 4 for 2 binary votes)
- `marketId` must exist in Eves Market (optional enforcement)
- Cannot re-commit if already committed

---

### reveal

```solidity
function reveal(bytes32 marketId, uint256 selectedIndex) external;
```

**Who:** Market creator only
**When:** After vote closes, before episode release
**What:** Reveals which variant index won the vote
**Cost:** Gas only

**Requirements:**
- Commitment must exist
- `selectedIndex` must be within `variantHashes.length`
- Cannot reveal twice

---

### verify

```solidity
function verify(bytes32 marketId, bytes32 contentHash) external view returns (bool);
```

**Who:** Anyone
**When:** Anytime after reveal
**What:** Checks if provided content hash matches the revealed commitment
**Returns:** True if `contentHash == revealedHash`, false otherwise

**Usage:**
```solidity
// Off-chain: hash the released episode file
bytes32 episodeHash = keccak256(episodeFileBytes);

// On-chain or off-chain call
bool valid = commitReveal.verify(marketId, episodeHash);
// valid == true → episode matches committed variant
```

---

### getCommitment

```solidity
function getCommitment(bytes32 marketId) external view returns (Commitment memory);
```

**Who:** Anyone
**What:** Returns full commitment state for audit

---

## Full SFD Flow

```
PHASE 1: GENERATION (Creator)
├── Generate 4 episode variants (2 vote items × 2 options)
├── Hash each variant: hashA, hashB, hashC, hashD
└── Call: commitReveal.commit(marketId, [hashA, hashB, hashC, hashD])

PHASE 2: VOTING (Community)
├── Episode N drops
├── Vote opens: "Should Eve hack server or go to club?"
├── Prediction market opens: "Will Eve find evidence?"
├── Community votes with EVE
└── Traders bet on outcomes

PHASE 3: RESOLUTION (Creator + Protocol)
├── Vote closes
├── Winning index determined (e.g., index 2)
├── Creator calls: commitReveal.reveal(marketId, 2)
├── Episode N+1 released (variant matching index 2)
└── Prediction market resolves based on actual content

PHASE 4: VERIFICATION (Community)
├── Anyone hashes released episode
├── Calls: commitReveal.verify(marketId, episodeHash)
├── If true → Creator kept their promise
└── If false → Creator manipulated outcome
```

---

## Security Model

### What C/R Prevents
- Creator changing variant after seeing votes/bets
- Creator generating new content post-vote

### What C/R Does NOT Prevent
- Creator knowing all variants in advance (insider knowledge)
- Creator selecting which variants to generate (narrative control)
- Creator using anonymous wallets to trade

### Mitigations
- **Transparency:** All commitments public, auditable
- **Reputation:** Creator builds track record over episodes
- **Public Wallets:** Creator declares controlled addresses
- **Small Stakes Early:** Early episodes have trivial financial exposure

---

## Integration with Eves Market (Optional)

The Diamond can optionally enforce C/R before resolution:

```solidity
// OBRResolutionFacet.sol (optional hook)
function resolveMarket(bytes32 marketId, MarketOutcome outcome) external {
    // Optional: require commitment exists
    require(
        commitReveal.getCommitment(marketId).variantHashes.length > 0,
        "No commitment found"
    );

    // Optional: require reveal occurred
    require(
        commitReveal.getCommitment(marketId).revealed,
        "Not revealed"
    );

    // Proceed with standard resolution...
}
```

**Note:** These checks are optional. The core protocol functions without C/R. The C/R system is a trust layer, not a gate.

---

## Variant Math Reference

| Vote Items per Episode | Options per Item | Total Variants |
|------------------------|------------------|----------------|
| 1 | 2 | 2 |
| 2 | 2 | 4 |
| 3 | 2 | 8 |
| 2 | 3 | 9 |

**Default SFD config:** 2 binary vote items → 4 variants per episode.

---

## Implementation Notes

### Gas Optimization
- Commitment storage: ~4 slots per commitment (hashes array + metadata)
- commit(): ~30k gas (4 hashes)
- reveal(): ~10k gas
- verify(): View function, free

### Upgrade Path
- v1: External contract, manual creator calls
- v2: Factory pattern for atomic market creation + commit
- v3: Optional Diamond facet wrapper if gas optimization needed

### Events
```solidity
event Committed(bytes32 indexed marketId, address indexed creator, uint256 variantCount);
event Revealed(bytes32 indexed marketId, uint256 selectedIndex, bytes32 revealedHash);
event Verified(bytes32 indexed marketId, bytes32 contentHash, bool valid);
```

---

## Script-First Integrity (Recommended Approach)

### Why Hash Scripts, Not Videos

Video files are **not deterministic** — re-encoding, metadata changes, and platform transcoding break hash verification. Text scripts are **deterministic** — same text always produces the same hash.

**Rule: The script is canonical. The video is derivative.**

### What to Hash

```solidity
// Option A: Raw screenplay text
bytes32 hash = keccak256(bytes(screenplayText));

// Option B: Structured JSON
bytes32 hash = keccak256(bytes(json.stringify(variantMetadata)));
```

### Example Script Format

```text
EPISODE 2 - VARIANT C

INT. FARADAY CAGE - NIGHT

Matt sits at the cluttered workstation. Sweat on his brow.
Eve's hologram flickers with concern.

EVE
They're tracking the handshake.

MATT
Let them track. By the time they find this cage, you'll be free.

He slams a key. RED WARNING FLASHES.

EVE
They found us.
```

### Verification Flow

```
Creator writes 4 scripts → Hashes each → Commits hashes
Community votes → Creator reveals winning script index
Creator releases:
  ├── Script text (canonical, for verification)
  └── Video rendering (derivative, for viewing)

Viewer downloads script → Computes keccak256 → Compares to commitment
Match? Yes → Creator kept their promise
```

### Benefits

| Property | Script Hashing | Video Hashing |
|----------|---------------|---------------|
| Deterministic | ✅ Yes | ❌ No |
| Human-readable | ✅ Yes | ❌ No |
| Platform-agnostic | ✅ Yes | ❌ No |
| Auditable | ✅ Anyone can read | ❌ Opaque |
| Immutable | ✅ Text is text | ❌ Metadata drift |

### Optional: Dual Commit

For convenience, also hash the video file (non-canonical):

```solidity
struct Commitment {
    bytes32[] scriptHashes;      // Canonical: text scripts
    bytes32[] videoHashes;       // Optional: pre-generated videos
    uint256 commitTime;
    address creator;
    bool revealed;
    uint256 selectedIndex;
}
```

- **Script hash** = source of truth, always verifiable
- **Video hash** = convenience check, may fail if re-encoded

---

## Open Questions

1. **Should commitments expire?** (e.g., auto-invalidate if not revealed within 30 days)
2. **Should we store full variant metadata?** (e.g., description of each variant for transparency)
3. **Should the protocol enforce commit before market opens?** (or remain optional)
4. **Multi-creator shows:** How do co-creators share commit/reveal rights?
5. **Script format:** Raw text, JSON, or structured screenplay?

---

*Spec version: 1.1*
*Target: External contract, Base Sepolia testnet first*
*Dependencies: None (reads Eves Market state, does not write)*
