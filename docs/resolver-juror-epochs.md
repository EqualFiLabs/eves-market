# Resolver Juror Epochs

Resolver capacity is now modeled as an active epoch size, not a permanent pool cap.

- Registered resolver identities are not capped by active epoch size.
- Candidates opt into the next epoch by staking, keeping resolver role enabled, and submitting a randomness commitment.
- Candidate reveals are mixed with epoch metadata, chain context, and delayed block entropy to produce the epoch seed.
- Seed finalization is a permissionless two-call flow after the reveal deadline: the first call schedules a future reference block and a later call consumes its block hash.
- If the scheduled hash leaves the EVM's 256-block lookup window before it is consumed, any caller can schedule a fresh reference block; a missed keeper call cannot brick the epoch.
- The score-submission window starts only when the seed is actually finalized, so entropy rescheduling does not consume candidate scoring time.
- Candidate score is `uint256(keccak256(abi.encode(epochSeed, epochId, identityId)))`.
- Anyone may submit candidate scores after seed finalization.
- The contract keeps only the lowest `activeEpochSize` submitted scores.
- Selected candidates are locked as the active resolver set for the epoch.
- Nonselected candidates can exit and withdraw after normal cooldown rules.
- Disputes sample committees only from the current epoch active set.
- Candidate opt-in can charge a fixed protocol fee routed to treasury.
- Resolver stake is a fixed seat amount. Identities cannot buy higher voting or reward weight.
- Slashed stake is split evenly across compliant active jurors and becomes claimable immediately.
- Trading fee resolver share accrues to the current epoch and is split evenly across compliant active jurors after epoch end.
- Slashed jurors are excluded from future epoch rewards until they restore the fixed seat stake and re-enter through a later epoch.

Default V1 parameters:

- Active epoch size: 16
- Resolver seat stake: 100 EVE
- Candidate epoch fee: configurable, intended around 5 eveUSD
- Resolver trading fee share: configurable, intended around 1% of trading fees
- Epoch length: 180 days
- Rotation window: 30 days
- Epoch randomness commit window: 7 days
- Epoch randomness reveal window: 7 days
- Epoch score submission window: 3 days
- Committee sizes: 3, then 5 on appeal

Active jurors can contribute randomness for the next epoch through
`commitResolverEpochRandomness` and `revealResolverEpochRandomness`. Missed active-juror
epoch randomness duties are slashable at seed finalization. Candidate entropy is also
accepted so the current active set is not the only source of next-epoch randomness.

Keepers should watch `ResolverEpochSeedReferenceBlockSet`, wait until a later block,
then call `finalizeResolverEpochSeed` again. If the reference expires, the same call
emits a replacement reference and the keeper repeats the process.
