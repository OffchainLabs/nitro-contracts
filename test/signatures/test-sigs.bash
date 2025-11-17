#!/bin/bash
output_dir="./test/signatures"
PIDS=()
CHANGED=0

forge build
for CONTRACTNAME in Bridge Inbox Outbox RollupCore RollupUserLogic RollupAdminLogic SequencerInbox EdgeChallengeManager ERC20Bridge ERC20Inbox ERC20Outbox BridgeCreator DeployHelper RollupCreator OneStepProofEntry OneStepProverHostIo OneStepProverMemory OneStepProverMath OneStepProver0 CacheManager ERC20MigrationOutbox
do
    (
        echo "Checking for signature changes in $CONTRACTNAME"
        [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
        forge inspect "$CONTRACTNAME" methods > "$output_dir/$CONTRACTNAME"
        diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
        if [[ $? != "0" ]]; then
            exit 1
        fi
        exit 0
    ) &
    PIDS+=($!)
done

for PID in "${PIDS[@]}"; do
    wait $PID || CHANGED=1
done

if [[ $CHANGED == 1 ]]
then
    exit 1
fi