// Copyright 2021-2022, Offchain Labs, Inc.
// For license information, see https://github.com/OffchainLabs/nitro-contracts/blob/main/LICENSE
// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.0;

import "../bridge/DelayBufferable.sol";

/**
 * @title   Manages the delay buffer for the sequencer (SequencerInbox.sol)
 * @notice  Messages are expected to be delayed up to a threshold, beyond which they are unexpected
 *          and deplete a delay buffer. Buffer depletion is preveneted from decreasing too fast by only
 *          depleting by as many seconds / blocks has elapsed in the delayed message queue.
 */
contract SimpleDelayBufferable is DelayBufferable {
    constructor(
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        ReplenishRate memory replenishRate_,
        Config memory config_
    ) DelayBufferable(maxTimeVariation_, replenishRate_, config_) {}

    uint64 fullBufferSyncExpiryBlock;
    uint64 fullBufferSyncExpirySeconds;

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function cachedFullBufferSyncExpiry() internal view override returns (uint64, uint64){
        return (fullBufferSyncExpiryBlock, fullBufferSyncExpirySeconds);
    }

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferSyncExpiry(uint64 _block, uint64 _time) internal override {
        fullBufferSyncExpiryBlock = _block;
        fullBufferSyncExpirySeconds = _time;
    }

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function cachedFullBufferSyncExpiry_() external view returns (uint64, uint64){
        return cachedFullBufferSyncExpiry();
    }

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferSyncExpiry_(uint64 _block, uint64 _time) external {
        cacheFullBufferSyncExpiry(_block, _time);
    }

    function updateSyncValidity_(
        uint64 blockNumber,
        uint64 timestamp
    ) external {
        updateSyncValidity(blockNumber, timestamp);
    }

    function isValidSyncProof_(
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage,
        bytes32 beforeAcc,
        Messages.InboxAccPreimage memory preimage
    ) external view returns (bool) {
        return
            isValidSyncProof(
                beforeDelayedAcc,
                delayedMessage,
                beforeAcc,
                preimage
            );
    }

    function updateBuffers_(
        uint64 blockNumber,
        uint64 timestampe
    ) external {
        updateBuffers(blockNumber, timestampe);
    }
}
