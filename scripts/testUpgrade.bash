#!/bin/bash
set -eo pipefail

if [[ -z "$L1_RPC" ]]; then
  echo "ERROR: L1_RPC environment variable is not set"
  exit 1
fi

ANVILFORK=true
export ANVILFORK
export CONFIG_NETWORK_NAME=arb1
export HARDHAT_NETWORK=custom

# Fork before the BOLD upgrade (block 21830860) so the rollup is still active
FORK_BLOCK=${FORK_BLOCK:-21830000}
anvil --fork-url "$L1_RPC" --fork-block-number $FORK_BLOCK > /dev/null &
anvil_pid=$!
trap 'kill $anvil_pid' EXIT

# Give Anvil time to start before seeding templates
sleep 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/seed-bold-templates.bash"

yarn script:bold-prepare
yarn script:bold-populate-lookup
yarn script:bold-local-execute 2>&1 | tee execute.log

tx_hash=$(grep 'upgrade tx hash:' execute.log | awk '{print $NF}')
rm -f execute.log

if [[ -z "$tx_hash" ]]; then
  echo "Failed to capture tx hash from bold-local-execute"
  exit 1
fi

# Re-verify via standalone TX_HASH mode to exercise that code path
TX_HASH=$tx_hash yarn script:bold-verify
