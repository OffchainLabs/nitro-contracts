#!/bin/bash

anvil --fork-url $L1_RPC > /dev/null &

anvil_pid=$!

sleep 5

cast chain-id

yarn script:bold-prepare && \
yarn script:bold-populate-lookup && \
yarn script:bold-local-execute

ecode=$? 

kill $anvil_pid

exit $ecode