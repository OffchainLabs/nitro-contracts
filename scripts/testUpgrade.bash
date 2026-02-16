#!/bin/bash
set -eo pipefail

ANVILFORK=true
export ANVILFORK

anvil --fork-url $L1_RPC > /dev/null &
anvil_pid=$!
trap 'kill $anvil_pid' EXIT

yarn script:bold-prepare
yarn script:bold-populate-lookup
yarn script:bold-local-execute 2>&1 | tee execute.log

tx_hash=$(grep 'upgrade tx hash:' execute.log | awk '{print $NF}')
rm -f execute.log

TX_HASH=$tx_hash yarn script:bold-verify