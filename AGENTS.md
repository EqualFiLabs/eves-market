# AGENTS.md

DO NOT USE "Task" Or Task (n)" or "Task 1" etc. in file or function names. This is a constraint.

REFER TO ETHSKILLS.md Before any solidity code and use it when making solidity code changes.  Decide which skill to use from the list and curl/load it (if not present locally already) and actually use it.

## Compiling

do not run `forge build --force` or `forge build --contracts` or `forge clean` this does a full build and takes too long.

use `forge test --match-path path/to/test` for testing

# After changes

All code changes should come with tests proving functionality

## Test Fidelity Guardrails

Keep the test pyramid balanced:

- Use unit harness tests for narrow branch coverage, storage checks, and otherwise unreachable state-machine edges.
- Use live integration or launch-level tests for every value-moving lifecycle.
- Use invariant and fuzz suites to broaden state-machine coverage, not to replace live-flow proofs.

Prefer real flows always.

If a synthetic shortcut is still necessary, document it clearly in the test file and keep it narrow. Every such shortcut should have a concrete reason, such as:

- storage or library smoke coverage
- unreachable failure branches that require direct accounting drift
- explicit status-machine jumps that are impractical to reach economically in setup

Synthetic harness coverage does not count as end-to-end confidence by itself. Each value-moving behavior should still have at least one real-flow or launch-level regression elsewhere in the repo.

Please add a commit messages wrapped in a text box to your response in chat in the format below.

# Commit Messages

DO NOT USE "Task" Or Task (n)" or "Task 1" etc. in messages. DO NOT Mention marking tasks complete or anything at all regarding tasks! This is a constraint.

Commit messages: Use Conventional Commits (feat(scope): …). Title ≤72 chars. Body in bullets explaining what/where/how/why. Present tense. Format:

feat(scope): short summary

- Key change detail
- Another change
- Rationale/context

## Compiler-Resilience Rule for Test Harnesses

When editing or adding external/public helper functions in large harness contracts (especially ones inheriting many facets/modules), prefer:

- `uint256` for external/public numeric parameters
- Internal casts to narrower types (`uint16`, `uint8`, etc.) at assignment boundaries
- Explicit bounds checks before narrowing casts

Example pattern:

```solidity
function setLtv(uint256 ltvBps) external {
    if (ltvBps > type(uint16).max) revert();
    cfg.ltvBps = uint16(ltvBps);
}
```

## When to Use This Rule

Apply this proactively when:

- The contract is a broad test harness/fixture with many inherited selectors
- You are touching external/public helper methods used only for tests/setup
- You have seen `stack too deep`/Yul `Variable ... is ... too deep in the stack`/`memoryguard was present` compile failures
- You are introducing or modifying narrow integer params (`uint16`, `uint8`) on external/public functions

## When Not to Use Blindly

Do not change ABI widths without checking call sites when:

- The function is part of a production interface expected by integrations
- ABI compatibility is required across deployed contracts or external tools

In those cases, keep the existing ABI and consider function decomposition/scoping refactors instead.
