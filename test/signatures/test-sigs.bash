#!/bin/bash
output_dir="./test/signatures"
for CONTRACTNAME in Bridge Inbox Outbox RollupCore RollupUserLogic RollupAdminLogic SequencerInbox ChallengeManager ERC20Bridge ERC20Inbox ERC20Outbox BridgeCreator DeployHelper RollupCreator OneStepProofEntry CacheManager
do
    echo "Checking for signature changes in $CONTRACTNAME"
    [ -f "$output_dir/$CONTRACTNAME" ] && mv "$output_dir/$CONTRACTNAME" "$output_dir/$CONTRACTNAME-old"
    forge inspect "$CONTRACTNAME" methods > "$output_dir/$CONTRACTNAME"
    diff "$output_dir/$CONTRACTNAME-old" "$output_dir/$CONTRACTNAME"
    if [[ $? != "0" ]]
    then
        CHANGED=1
    fi
done
if [[ $CHANGED == 1 ]]
then
    exit 1
fi