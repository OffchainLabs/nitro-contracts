#!/bin/bash
# Seed BOLD template contracts onto an Anvil fork.
# Templates were deployed on mainnet after the BOLD upgrade via CREATE2, so they
# don't exist at the pre-upgrade fork block. Copy bytecode from current mainnet.
#
# Requires: L1_RPC (source RPC), ANVIL_RPC (target Anvil instance)

set -eo pipefail

ANVIL_RPC="${ANVIL_RPC:-http://localhost:8545}"

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
  if [[ "$code" == "0x" || -z "$code" ]]; then
    echo "ERROR: no bytecode found for template $addr -- check L1_RPC"
    exit 1
  fi
  cast rpc anvil_setCode "$addr" "$code" --rpc-url "$ANVIL_RPC" > /dev/null
done
echo "templates seeded"
