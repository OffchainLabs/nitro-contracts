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
    uint64 internal fullBufferExpiryBlockNumber;
    uint64 internal fullBufferExpiryTimestamp;

    constructor(
        ISequencerInbox.MaxTimeVariation memory maxTimeVariation_,
        ReplenishRate memory replenishRate_,
        DelayConfig memory delayConfig_
    ) DelayBufferable(maxTimeVariation_, replenishRate_, delayConfig_) {}

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function cachedFullBufferExpiry() internal view override returns (uint64, uint64) {
        return (fullBufferExpiryBlockNumber, fullBufferExpiryTimestamp);
    }

    /// @dev Inheriting contracts must implement this function to fetch the cached full buffer expiry state.
    function cacheFullBufferExpiry(uint64 blockNumber, uint64 timestamp) internal override {
        fullBufferExpiryBlockNumber = blockNumber;
        fullBufferExpiryTimestamp = timestamp;
    }

    /// @dev Inheriting contracts must implement this function to cache the full buffer expiry state.
    function cachedFullBufferExpiry_() external view returns (uint64, uint64) {
        return (fullBufferExpiryBlockNumber, fullBufferExpiryTimestamp);
    }

    /// @inheritdoc IDelayBufferable
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        bytes32 beforeDelayedAcc,
        Messages.Message calldata delayedMessage
    ) external {
        // no-op
    }

    /// @inheritdoc IDelayBufferable
    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        bytes32 beforeDelayedAcc,
        Messages.Message calldata delayedMessage
    ) external {
        // no-op
    }

    /// @inheritdoc IDelayBufferable
    function addSequencerL2BatchFromBlobs(
        uint256 sequenceNumber,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        bool isCachingRequested,
        bytes32 beforeDelayedAcc,
        Messages.Message calldata delayedMessage,
        Messages.InboxAccPreimage calldata preimage
    ) external {
        // no-op
    }

    /// @inheritdoc IDelayBufferable
    function addSequencerL2BatchFromOrigin(
        uint256 sequenceNumber,
        bytes calldata data,
        uint256 afterDelayedMessagesRead,
        IGasRefunder gasRefunder,
        uint256 prevMessageCount,
        uint256 newMessageCount,
        bool isCachingRequested,
        bytes32 beforeDelayedAcc,
        Messages.Message calldata delayedMessage,
        Messages.InboxAccPreimage calldata preimage
    ) external {
        // no-op
    }

    function isValidSyncProof_(
        bytes32 beforeDelayedAcc,
        Messages.Message memory delayedMessage,
        bytes32 beforeAcc,
        Messages.InboxAccPreimage memory preimage
    ) external view returns (bool) {
        return isValidSyncProof(beforeDelayedAcc, delayedMessage, beforeAcc, preimage);
    }

    function updateSyncValidity_(
        bool isCachingRequested,
        uint64 blockNumber,
        uint64 timestamp
    ) external {
        updateSyncValidity(isCachingRequested, blockNumber, timestamp);
    }

    function maxTimeVariationExternal()
        external
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        return maxTimeVariationInternal();
    }

    function maxTimeVariationBufferable_()
        external
        view
        returns (
            uint64,
            uint64,
            uint64,
            uint64
        )
    {
        return maxTimeVariationBufferable();
    }

    function isSynced_() external view returns (bool) {
        return isSynced();
    }

    function deplete_(
        uint64 start,
        uint64 end,
        uint64 delay,
        uint64 threshold,
        uint64 buffer
    ) external pure returns (uint64) {
        return deplete(start, end, delay, threshold, buffer);
    }

    function replenish_(
        uint64 start,
        uint64 end,
        uint64 buffer,
        uint64 maxBuffer,
        uint64 replenishAmountPerPeriod,
        uint64 replenishPeriod,
        uint64 repelenishRoundoff
    ) external pure returns (uint64, uint64) {
        return
            replenish(
                start,
                end,
                buffer,
                maxBuffer,
                replenishAmountPerPeriod,
                replenishPeriod,
                repelenishRoundoff
            );
    }

    function updateBuffers_(uint64 blockNumber, uint64 timestamp) external {
        updateBuffers(blockNumber, timestamp);
    }

    function prevDelay_() external view returns (DelayCache memory) {
        return prevDelay;
    }

    function roundOff() external view returns (uint64, uint64) {
        return (roundOffBlocks, roundOffSeconds);
    }
}
