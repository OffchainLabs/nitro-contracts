// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/DelayBufferable.sol";

contract SimpleDelayBufferable is DelayBufferable {
    constructor(
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        ReplenishRate memory replenishRate_,
        Config memory config_
    ) DelayBufferable(maxTimeVariation_, replenishRate_, config_) {}

    uint64 fullBufferSyncExpiryBlockNumber;
    uint64 fullBufferSyncExpiryTimestamp;

    function isFullBufferSyncCacheValid() internal view override returns (bool) {
        return (block.number <= fullBufferSyncExpiryBlockNumber &&
            block.timestamp <= fullBufferSyncExpiryTimestamp);
    }

    function cacheFullBufferSyncExpiry(uint64 _block, uint64 _time) internal override {
        fullBufferSyncExpiryBlockNumber = _block;
        fullBufferSyncExpiryTimestamp = _time;
    }

    function cachedFullBufferSyncExpiry_() external view returns (uint64, uint64) {
        return (fullBufferSyncExpiryBlockNumber, fullBufferSyncExpiryTimestamp);
    }

    function cacheFullBufferSyncExpiry_(uint64 _block, uint64 _time) external {
        cacheFullBufferSyncExpiry(_block, _time);
    }

    function updateSyncValidity_(uint64 blockNumber, uint64 timestamp) external {
        updateSyncValidity(blockNumber, timestamp);
    }

    function isValidSyncProof_(
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage,
        bytes32 beforeAcc,
        Messages.InboxAccPreimage memory preimage
    ) external view returns (bool) {
        return (Messages.isValidSequencerInboxAccPreimage(beforeAcc, preimage) &&
            Messages.isValidDelayedAccPreimage(
                preimage.delayedAcc,
                beforeDelayedAcc,
                delayedMessage
            ) &&
            isOnTime(delayedMessage.blockNumber, delayedMessage.timestamp));
    }

    function updateBuffers_(uint64 blockNumber, uint64 timestampe) external {
        updateBuffers(blockNumber, timestampe);
    }
}
