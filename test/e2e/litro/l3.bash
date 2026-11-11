#!/usr/bin/env bash
# Deploys this checkout's RollupCreator and an L3 rollup on a running arbitrum-litro L2, then runs the
# L3 node as a sidecar container so `yarn test:e2e` exercises these contracts.
#
# usage: test/e2e/litro/l3.bash deploy|start|fund <out dir>
#   deploy  deploy the fee token (optional), RollupCreator and L3 rollup; write the L3 node config
#   start   stake the L3 validator, then run the L3 node on :3347
#   fund    fee-token chains only: deposit fee token from user_fee_token_deployer to the L3
#
# env:
#   ARBITRUM_TESTNODE_CONFIG_DIR  litro's exported config dir (set by the arbitrum-litro action)
#   L3_IMAGE                      image to run the L3 node from; use the litro image so Nitro matches
#   FEE_TOKEN_DECIMALS            18 or 6; unset deploys an ETH-fee L3
#   FEE_TOKEN_PRICER              true deploys a ConstantExchangeRatePricer
set -euo pipefail

cmd=${1:?usage: l3.bash deploy|start|fund <out dir>}
out=${2:?usage: l3.bash deploy|start|fund <out dir>}
mkdir -p "$out"
out=$(cd "$out" && pwd)
cd "$(dirname "$0")/../../.."

litro_config=${ARBITRUM_TESTNODE_CONFIG_DIR:?ARBITRUM_TESTNODE_CONFIG_DIR must point at litro exported config}
l2=http://127.0.0.1:8547
l3=http://127.0.0.1:3347
zero=0x0000000000000000000000000000000000000000

# nitro-testnode accounts, funded on litro's L2
owner_key=0xecdf21cb41c65afb51f91df408b7656e2c8739a5877f2814add0afd780cc210e # l3owner
owner=0x863c904166E801527125D8672442D736194A3362
sequencer=0x3E6134aAD4C4d422FF2A4391Dc315c4DDf98D1a5 # l3sequencer
user_key() { printf '0x%s' "$(printf %s "$1" | shasum -a 256 | cut -d' ' -f1)"; }
token_bridge_deployer_key=$(user_key user_token_bridge_deployer)
fee_token_deployer_key=$(user_key user_fee_token_deployer)

send() { cast send "$@" --private-key "$owner_key" --rpc-url "$l2" >/dev/null; }

# Build only the test helpers the fee-token chains need, so the jobs can skip the full forge build.
test_contracts=out/litro
create_test_contract() { # <file> <contract> [abi-encoded constructor args]
  local bytecode
  bytecode=$(jq -r .bytecode.object "$test_contracts/$1/$2.json")
  cast send --json --private-key "$owner_key" --rpc-url "$l2" --create "$bytecode${3:+${3#0x}}" |
    jq -r .contractAddress
}

deploy() {
  cp -n scripts/config.example.ts scripts/config.ts 2>/dev/null || true

  # The root litro's own L3 uses is one the image's Nitro is known to accept.
  local wasm_root
  wasm_root=$(cast call "$(jq -r .rollup "$litro_config/l3deployment.json")" \
    'wasmModuleRoot()(bytes32)' --rpc-url "$l2")

  local fee_token=$zero pricer=$zero
  if [ -n "${FEE_TOKEN_DECIMALS:-}" ]; then
    FOUNDRY_SKIP='[]' FOUNDRY_OUT=$test_contracts FOUNDRY_CACHE_PATH=forge-cache/litro forge build \
      src/test-helpers/TestToken.sol test/foundry/ERC20Bridge.t.sol \
      test/foundry/fee-token-pricers/ConstantExchangeRatePricer.sol >/dev/null
    local users=("$(cast wallet address "$token_bridge_deployer_key")" "$(cast wallet address "$fee_token_deployer_key")")
    case "$FEE_TOKEN_DECIMALS" in
      18)
        fee_token=$(create_test_contract TestToken.sol TestToken \
          "$(cast abi-encode 'constructor(uint256)' 1000000000000000000000000000)")
        for u in "${users[@]}"; do send "$fee_token" 'transfer(address,uint256)' "$u" 1000000000000000000000000; done
        ;;
      6)
        fee_token=$(create_test_contract ERC20Bridge.t.sol ERC20_6Decimals)
        for u in "$owner" "${users[@]}"; do send "$fee_token" 'mint(address,uint256)' "$u" 1000000000000; done
        ;;
      *) echo "FEE_TOKEN_DECIMALS must be 18 or 6" >&2; exit 1 ;;
    esac
    if [ "${FEE_TOKEN_PRICER:-}" = true ]; then
      pricer=$(create_test_contract ConstantExchangeRatePricer.sol ConstantExchangeRatePricer \
        "$(cast abi-encode 'constructor(uint256)' 1000000000000000000)")
    fi
  fi
  echo "fee token $fee_token, pricer $pricer"

  PARENT_CHAIN_RPC=$l2 PARENT_CHAIN_ID=412346 \
    DEPLOYER_PRIVKEY=$owner_key OWNER_ADDRESS=$owner SEQUENCER_ADDRESS=$sequencer \
    CHILD_CHAIN_NAME=orbit-dev-test CHILD_CHAIN_CONFIG_PATH=$litro_config/l3_chain_config.json \
    WASM_MODULE_ROOT=$wasm_root MAX_DATA_SIZE=104857 \
    FEE_TOKEN_ADDRESS=$fee_token FEE_TOKEN_PRICER_ADDRESS=$pricer \
    CHAIN_DEPLOYMENT_INFO=$out/l3deployment.json CHILD_CHAIN_INFO=$out/l3_chain_info.json \
    yarn -s create-rollup-testnode

  # The staker's validator wallet doesn't exist yet, so it can't be whitelisted ahead of time.
  local rollup upgrade_executor
  rollup=$(jq -r .rollup "$out/l3deployment.json")
  upgrade_executor=$(jq -r '."upgrade-executor"' "$out/l3deployment.json")
  send "$upgrade_executor" 'executeCall(address,bytes)' "$rollup" \
    "$(cast calldata 'setValidatorWhitelistDisabled(bool)' true)"

  # litro's L3 config with our chain info. Nitro refuses both batch-size limits at once.
  # litro posts L3 batches after 100ms; at that pace the batch carrying one spending report is posted
  # and reported before customFeeRollup reads the report it measured. 2s leaves room for that read.
  jq '.chain."info-files" = ["/config/l3_chain_info.json"] | del(.chain."info-json")
      | .node.staker.enable = true | del(.node."batch-poster"."max-size")
      | .node."batch-poster"."max-delay" = "2s"' \
    "$litro_config/l3-nodeConfig.json" >"$out/l3-nodeConfig.json"
  echo "deployed L3 rollup $rollup"
}

start() {
  local image=${L3_IMAGE:?L3_IMAGE must name the litro image}
  local net parent
  if [ "$(uname)" = Linux ]; then
    net=(--network host) parent=http://127.0.0.1:8547
  else
    net=(--add-host host.docker.internal:host-gateway -p 3347:3347 -p 3348:3348)
    parent=http://host.docker.internal:8547
  fi
  # Set up the staker's validator wallet and stake before the node starts. Left to the node, it queues
  # create wallet, wrap ETH and approve together; each estimate reverts until the step before it is mined,
  # and the node retries every 30s, so the first assertion (and every withdrawal) waits about a minute.
  local staker_key creator rollup weth stake prefunded
  staker_key=0x$(jq -r '.node.staker."parent-chain-wallet"."private-key"' "$out/l3-nodeConfig.json")
  creator=$(jq -r '."validator-wallet-creator"' "$out/l3deployment.json")
  rollup=$(jq -r .rollup "$out/l3deployment.json")
  weth=$(cast call "$rollup" 'stakeToken()(address)' --rpc-url "$l2")
  stake=$(cast call "$rollup" 'baseStake()(uint256)' --rpc-url "$l2" | cut -d' ' -f1)
  prefunded=$(cast send "$creator" 'createWallet(address[])' '[]' --private-key "$staker_key" --rpc-url "$l2" --json |
    jq -r --arg c "$(echo "$creator" | tr A-F a-f)" '.logs[] | select((.address | ascii_downcase) == $c) | .topics[1]')
  prefunded=$(cast to-check-sum-address "0x${prefunded:26}")
  cast send "$prefunded" 'executeTransaction(bytes,address,uint256)' "$(cast calldata 'deposit()')" "$weth" "$stake" \
    --value "$stake" --private-key "$staker_key" --rpc-url "$l2" >/dev/null
  cast send "$prefunded" 'executeTransaction(bytes,address,uint256)' \
    "$(cast calldata 'approve(address,uint256)' "$rollup" "$(cast max-uint)")" "$weth" 0 \
    --private-key "$staker_key" --rpc-url "$l2" >/dev/null
  echo "validator wallet $prefunded holds $stake stake token"

  docker rm -f nc-l3 >/dev/null 2>&1 || true
  docker run -d --name nc-l3 "${net[@]}" -v "$out":/config:ro -e HOME=/tmp/l3home \
    --entrypoint /usr/local/bin/nitro "$image" \
    --conf.file=/config/l3-nodeConfig.json \
    --parent-chain.connection.url="$parent" \
    --validation.wasm.allowed-wasm-module-roots=/home/user/nitro-legacy/machines,/home/user/target/machines \
    --node.dangerous.disable-blob-reader \
    --node.staker.dangerous.without-block-validator \
    --node.bold.check-staker-switch-interval=1s \
    --node.parent-chain-reader.poll-interval=250ms --execution.parent-chain-reader.poll-interval=250ms \
    --node.bold.state-provider-config.check-batch-finality=false \
    --execution.stylus-target.allow-offchain-activation \
    --http.addr=0.0.0.0 --http.port=3347 --http.api=net,web3,eth,txpool,debug \
    --http.corsdomain='*' --http.vhosts='*' --ws.addr=0.0.0.0 --ws.port=3348 >/dev/null

  local i
  for i in $(seq 1 120); do
    if [ "$(cast chain-id --rpc-url "$l3" 2>/dev/null)" = 333333 ]; then echo "L3 up after ${i}s"; break; fi
    if [ "$i" = 120 ] || [ "$(docker inspect -f '{{.State.Running}}' nc-l3)" != true ]; then
      docker logs --tail 80 nc-l3; echo "L3 node did not start" >&2; exit 1
    fi
    sleep 1
  done
}

# Fee-token L3s start with no balances: l3owner pays for ArbOwner calls and user_fee_token_deployer
# sends L3 transactions, so both deposit fee token from the L2.
fund() {
  local token inbox amount key user i
  token=$(jq -r '."native-token"' "$out/l3deployment.json")
  inbox=$(jq -r .inbox "$out/l3deployment.json")
  [ "$token" != "$zero" ] || { echo "ETH-fee L3, nothing to fund"; return; }
  amount=$(cast parse-units 10000 "$(cast call "$token" 'decimals()(uint8)' --rpc-url "$l2")")
  for key in "$owner_key" "$fee_token_deployer_key"; do
    cast send "$token" 'approve(address,uint256)' "$inbox" "$amount" --private-key "$key" --rpc-url "$l2" >/dev/null
    cast send "$inbox" 'depositERC20(uint256)' "$amount" --private-key "$key" --rpc-url "$l2" >/dev/null
  done
  for key in "$owner_key" "$fee_token_deployer_key"; do
    user=$(cast wallet address "$key")
    for i in $(seq 1 120); do
      [ "$(cast balance "$user" --rpc-url "$l3")" != 0 ] && break
      [ "$i" != 120 ] || { echo "fee token deposit for $user never reached the L3" >&2; exit 1; }
      sleep 1
    done
    echo "funded $user on the L3"
  done

  pay_batch_poster_dues
}

arb_owner=0x0000000000000000000000000000000000000070
arb_gas_info=0x000000000000000000000000000000000000006C
surplus() { cast call "$arb_gas_info" 'getL1PricingSurplus()(int256)' --rpc-url "$l3" | cut -d' ' -f1; }

# Every batch adds its L1 cost to the batch poster's dues, and the poster is paid only from L1 fees
# that L3 transactions have paid in (surplus = fees available - dues). Setup's few small transactions
# pay almost nothing, so a fresh L3 owes the poster more than customFeeRollup's single clearing batch
# covers, and the rest is paid with the batch that test measures. nitro-testnode's L3 has worked its
# dues off through traffic by test time. Do the same: raise the L1 price per unit the way that test
# does, send transactions until the surplus is non-negative, then restore the price.
pay_batch_poster_dues() {
  local price round
  price=$(cast call "$arb_gas_info" 'getL1BaseFeeEstimate()(uint256)' --rpc-url "$l3" | cut -d' ' -f1)
  send_and_wait_for_report "$arb_owner" 'setL1PricePerUnit(uint256)' "$((price * 1000))"
  for round in 1 2 3 4 5; do
    [ "$(surplus | cut -c1)" = - ] || break
    send_and_wait_for_report 0x00000000000000000000000000000000000000dd
  done
  [ "$(surplus | cut -c1)" != - ] || { echo "L1 pricing surplus still negative: $(surplus)" >&2; exit 1; }
  send_and_wait_for_report "$arb_owner" 'setL1PricePerUnit(uint256)' "$price"
  echo "batch poster dues paid; L1 pricing surplus $(surplus)"
}

# Sends an L3 transaction, then waits until the batch holding it is posted and the L3 has read that
# batch's spending report (an L3 block's nonce counts the delayed messages it has read).
send_and_wait_for_report() {
  local block bridge target i
  block=$(cast send "$@" --private-key "$owner_key" --rpc-url "$l3" --json | jq -r .blockNumber)
  block=$(cast to-dec "$block")
  for i in $(seq 1 90); do
    cast call 0x00000000000000000000000000000000000000C8 'findBatchContainingBlock(uint64)(uint64)' "$block" \
      --rpc-url "$l3" >/dev/null 2>&1 && break
    [ "$i" != 90 ] || { echo "L3 block $block never posted in a batch" >&2; exit 1; }
    sleep 1
  done
  bridge=$(jq -r .bridge "$out/l3deployment.json")
  target=$(cast call "$bridge" 'delayedMessageCount()(uint256)' --rpc-url "$l2" | cut -d' ' -f1)
  for i in $(seq 1 60); do
    [ "$(cast to-dec "$(cast block latest -f nonce --rpc-url "$l3")")" -lt "$target" ] || return 0
    sleep 1
  done
  echo "L3 never read the spending report for block $block" >&2
  exit 1
}

case "$cmd" in
  deploy) deploy ;;
  start) start ;;
  fund) fund ;;
  *) echo "unknown command $cmd" >&2; exit 1 ;;
esac
