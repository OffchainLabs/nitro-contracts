#!/bin/bash
set -eo pipefail

# Validates the Safe multisig flow: calldata is generated BEFORE populate-lookup,
# proving that Safe signature collection can happen while validators are still running.
#
# Flow:
#   1. bold-prepare
#   2. bold-local-execute (ANVILFORK unset + non-executor key -> captures calldata only)
#   3. bold-populate-lookup (happens AFTER calldata generation)
#   4. cast send (impersonate executor, send captured calldata)
#   5. bold-verify (standalone verification via TX_HASH)

if [[ -z "$L1_RPC" ]]; then
  echo "ERROR: L1_RPC environment variable is not set"
  exit 1
fi

# Arb1 DAO L1 Timelock (executor role on the UpgradeExecutor)
EXECUTOR="0xE6841D92B0C345144506576eC13ECf5103aC7f49"
export CONFIG_NETWORK_NAME=arb1
export HARDHAT_NETWORK=custom

ANVIL_RPC="http://localhost:8545"

# Fork before the BOLD upgrade (block 21830860) so the rollup is still active
FORK_BLOCK=${FORK_BLOCK:-21830000}
anvil --fork-url "$L1_RPC" --fork-block-number $FORK_BLOCK > /dev/null &
anvil_pid=$!
trap 'kill $anvil_pid' EXIT

# Give Anvil time to start before seeding templates
sleep 2

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export ANVIL_RPC
source "$SCRIPT_DIR/seed-bold-templates.bash"

# Step 1: Deploy BOLDUpgradeAction
yarn script:bold-prepare

# Step 2: Generate calldata WITHOUT executing.
# A dummy private key that lacks the executor role causes perform() to print
# the calldata and exit without sending a transaction.
ANVILFORK= L1_PRIV_KEY=0x0000000000000000000000000000000000000000000000000000000000000001 \
  yarn script:bold-local-execute 2>&1 | tee execute.log

upgrade_executor=$(grep -m1 'upgrade executor:' execute.log | awk '{print $NF}')
calldata=$(grep 'call to upgrade executor:' execute.log | awk '{print $NF}')
rm -f execute.log

if [[ -z "$calldata" ]]; then
  echo "Failed to capture calldata from bold-local-execute"
  exit 1
fi
if [[ -z "$upgrade_executor" ]]; then
  echo "Failed to capture upgrade executor address from bold-local-execute"
  exit 1
fi
echo "captured calldata for upgrade executor $upgrade_executor"

# Step 3: Populate lookup AFTER calldata generation.
# This ordering proves calldata is independent of assertion state.
yarn script:bold-populate-lookup

# Step 4: Execute the upgrade via cast send, simulating a Safe/external execution
cast rpc anvil_impersonateAccount "$EXECUTOR" --rpc-url "$ANVIL_RPC" > /dev/null
cast rpc anvil_setBalance "$EXECUTOR" "0x1000000000000000" --rpc-url "$ANVIL_RPC" > /dev/null
tx_hash=$(cast send "$upgrade_executor" "$calldata" \
  --from "$EXECUTOR" --unlocked --rpc-url "$ANVIL_RPC" --json | jq -r '.transactionHash')

echo "upgrade tx hash: $tx_hash"

# Step 5: Verify the upgrade using standalone TX_HASH mode
TX_HASH=$tx_hash yarn script:bold-verify
