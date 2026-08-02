#!/usr/bin/env bash
# Current local smoke check for the greenfield deployment surface.
# The old cast-driven script referenced removed vault/lending flows and stale
# selector signatures. Keep this wrapper pointed at the maintained deployment
# regression instead of duplicating selector wiring here.

set -euo pipefail
cd "$(dirname "$0")/.."

forge test --match-path test/unit/DeployScript.t.sol
