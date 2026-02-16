#!/bin/bash
set -eo pipefail

# Validates the Safe multisig flow: calldata is generated BEFORE populate-lookup,
# proving that Safe signature collection can happen while validators are still running.
#
# Flow:
#   1. bold-prepare
#   2. bold-local-execute (non-executor key -> captures calldata, does not execute)
#   3. bold-populate-lookup (happens AFTER calldata generation)
#   4. cast send (impersonate executor, send captured calldata)
#   5. bold-verify (standalone verification via TX_HASH)

# Arb1 DAO L1 Timelock (executor role on the UpgradeExecutor)
EXECUTOR="0xE6841D92B0C345144506576eC13ECf5103aC7f49"
export CONFIG_NETWORK_NAME=arb1
export HARDHAT_NETWORK=custom

ANVIL_RPC="http://localhost:8545"

# Fork before the BOLD upgrade (block 21830860) so the rollup is still active
FORK_BLOCK=${FORK_BLOCK:-21830000}
anvil --fork-url $L1_RPC --fork-block-number $FORK_BLOCK > /dev/null &
anvil_pid=$!
trap 'kill $anvil_pid' EXIT

# Give Anvil time to start before seeding templates
sleep 2

# Seed BOLD template contracts onto the fork.
# Templates were deployed on mainnet after the BOLD upgrade via CREATE2, so they
# don't exist at the pre-upgrade fork block. Copy bytecode from current mainnet.
TEMPLATES=(
  0x677ECf96DBFeE1deFbDe8D2E905A39f73Aa27B89  # eth.bridge
  0x93dCfC7E658050c80700a6eB7FAF12efaCF5BF76  # eth.sequencerInbox
  0xE4bE5495054fE4fa4Ea5972219484984927681E3  # eth.delayBufferableSequencerInbox
  0x9C4ce5EF20F831F4e7fEcf58aAA0Cda8d3091c35  # eth.inbox
  0x7b6784fbd233EDB47E11eA4e7205fC4229447662  # eth.rollupEventInbox
  0x186267690cb723d72A7EDBC002476E23D694cB33  # eth.outbox
  0x81be1Bf06cB9B23e8EEDa3145c3366A912DAD9D6  # erc20.bridge
  0xe154a8d54e39Cd8edaEA85870Ea349B82B0E4eF4  # erc20.sequencerInbox
  0x6F2E7F9B5Db5e4e9B5B1181D2Eb0e4972500C324  # erc20.delayBufferableSequencerInbox
  0xD210b64eD9D47Ef8Acf1A3284722FcC7Fc6A1f4e  # erc20.inbox
  0x0d079b22B0B4083b9b0bDc62Bf1a4EAF4a95bDEe  # erc20.rollupEventInbox
  0x17E0C5fE0dFF2AE4cfC9E96d9Ccd112DaF5c0386  # erc20.outbox
  0xA4892FFE3Deab25337D7D1A5b94b35dABa255451  # rollupUserLogic
  0x16aD566aaa05fe6977A033DE2472c05C84CAB724  # rollupAdminLogic
  0x93069fFd7730733eCfd57A0D2D528CF686248524  # challengeManagerTemplate
  0x91cB57F200Bd5F897E41C164425Ab4DB0991A64f  # osp
  0x43698080f40dB54DEE6871540037b8AB8fD0AB44  # rollupCreator
)
echo "seeding ${#TEMPLATES[@]} BOLD template contracts..."
for addr in "${TEMPLATES[@]}"; do
  code=$(cast code "$addr" --rpc-url "$L1_RPC")
  cast rpc anvil_setCode "$addr" "$code" --rpc-url "$ANVIL_RPC" > /dev/null
done
echo "templates seeded"

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
