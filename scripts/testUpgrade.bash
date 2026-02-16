#!/bin/bash

ANVILFORK=true
export ANVILFORK

anvil --fork-url $L1_RPC > /dev/null &

anvil_pid=$!

yarn script:bold-prepare && \
yarn script:bold-populate-lookup && \
execute_output=$(yarn script:bold-local-execute 2>&1)
ecode=$?
echo "$execute_output"

if [ $ecode -ne 0 ]; then
  kill $anvil_pid
  exit $ecode
fi

# Test standalone verification by re-running with the tx hash from execute
tx_hash=$(echo "$execute_output" | grep 'upgrade tx hash:' | awk '{print $NF}')
if [ -z "$tx_hash" ]; then
  echo "FAIL: could not extract tx hash from execute output"
  kill $anvil_pid
  exit 1
fi

echo "testing standalone verification with TX_HASH=$tx_hash"
TX_HASH=$tx_hash yarn script:bold-verify
ecode=$?

kill $anvil_pid

exit $ecode